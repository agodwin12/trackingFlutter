// lib/src/services/notification_service.dart
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'env_config.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint('📩 Background message: ${message.notification?.title}');
    if (message.notification != null) {
      await NotificationService.showNotification(
        title: message.notification!.title ?? 'Notification',
        body: message.notification!.body ?? '',
        data: message.data,
      );
    }
  } catch (e) {
    debugPrint('⚠️ Background handler error: $e');
  }
}

class NotificationService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static String? _fcmToken;
  static bool _firebaseAvailable = false;

  static final GlobalKey<NavigatorState> navigatorKey =
  GlobalKey<NavigatorState>();

  // ─────────────────────────────────────────────────────────────────────────
  // INITIALIZE
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      debugPrint('🔔 Initializing notification service...');

      await _initializeLocalNotifications();

      try {
        final settings = await _firebaseMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
          announcement: false,
          carPlay: false,
          criticalAlert: false,
        );

        debugPrint('📋 Permission: ${settings.authorizationStatus}');

        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          if (defaultTargetPlatform == TargetPlatform.iOS) {
            await _firebaseMessaging.setForegroundNotificationPresentationOptions(
              alert: true,
              badge: true,
              sound: true,
            );

            String? apnsToken;
            for (int i = 0; i < 10; i++) {
              apnsToken = await _firebaseMessaging.getAPNSToken();
              if (apnsToken != null && apnsToken.isNotEmpty) {
                debugPrint('✅ APNs token available');
                break;
              }
              debugPrint('⏳ Waiting for APNs token...');
              await Future.delayed(const Duration(seconds: 1));
            }

            if (apnsToken == null || apnsToken.isEmpty) {
              debugPrint('⚠️ APNs token still not available yet');
            }
          }

          try {
            final token = await _firebaseMessaging.getToken().timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                debugPrint('⏰ FCM token retrieval timeout');
                return null;
              },
            );

            if (token != null && token.isNotEmpty) {
              _fcmToken = token;
              _firebaseAvailable = true;
              debugPrint('✅ FCM token received (${token.length} chars)');

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('fcm_token', token);

              await _registerTokenWithBackend(token);
            } else {
              debugPrint('❌ FCM token null or empty');
              _firebaseAvailable = false;
            }

            _firebaseMessaging.onTokenRefresh.listen((newToken) async {
              debugPrint('🔄 FCM token refreshed');
              _fcmToken = newToken;

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('fcm_token', newToken);

              await _registerTokenWithBackend(newToken);
            }, onError: (e) {
              debugPrint('❌ Token refresh error: $e');
            });

            FirebaseMessaging.onBackgroundMessage(
              firebaseMessagingBackgroundHandler,
            );

            FirebaseMessaging.onMessage.listen((message) {
              debugPrint('📨 Foreground: ${message.notification?.title}');
              _handleForegroundMessage(message);
            });

            FirebaseMessaging.onMessageOpenedApp.listen((message) {
              debugPrint(
                  '📬 Opened from notification: ${message.notification?.title}');
              _handleNotificationTap(message);
            });

            final initial = await _firebaseMessaging.getInitialMessage();
            if (initial != null) {
              debugPrint(
                  '📬 Launched from notification: ${initial.notification?.title}');
              _handleNotificationTap(initial);
            }
          } catch (tokenError) {
            debugPrint('❌ FCM token error: $tokenError');
            _firebaseAvailable = false;
          }
        } else {
          debugPrint(
              '⚠️ Permission not granted: ${settings.authorizationStatus}');
        }
      } catch (firebaseError) {
        debugPrint('❌ Firebase error: $firebaseError');
        _firebaseAvailable = false;
      }

      _initialized = true;
      debugPrint('✅ Notification service initialized');
    } catch (e) {
      debugPrint('❌ Critical notification init error: $e');
      _initialized = true;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOCAL NOTIFICATIONS
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _initializeLocalNotifications() async {
    const androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _localNotifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          try {
            _handleLocalNotificationTap(
              jsonDecode(response.payload!) as Map<String, dynamic>,
            );
          } catch (e) {
            debugPrint('⚠️ Error parsing notification payload: $e');
          }
        }
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TOKEN REGISTRATION
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _registerTokenWithBackend(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('accessToken');

      await prefs.setString('fcm_token', token);

      if (authToken == null) {
        await prefs.setString('pending_fcm_token', token);
        debugPrint('⏳ FCM token saved as pending (no auth token yet)');
        return;
      }

      debugPrint('📤 Registering FCM token with backend...');

      final response = await http
          .post(
        Uri.parse('${EnvConfig.baseUrl}/notifications/register-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'token': token,
          'device_type':
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
          'device_id': null,
        }),
      )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        await prefs.setString('registered_fcm_token', token);
        await prefs.remove('pending_fcm_token');
        debugPrint('✅ FCM token registered with backend');
      } else {
        await prefs.setString('pending_fcm_token', token);
        debugPrint(
          '❌ FCM token registration failed (${response.statusCode}) — saved as pending',
        );
        debugPrint('Response body: ${response.body}');
      }
    } catch (e) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_fcm_token', token);
      } catch (_) {}
      debugPrint('❌ FCM token registration error: $e — saved as pending');
    }
  }

  static Future<void> registerToken() async {
    final prefs = await SharedPreferences.getInstance();

    final token = _fcmToken ??
        prefs.getString('fcm_token') ??
        prefs.getString('pending_fcm_token');

    if (token == null || token.isEmpty) {
      debugPrint('⚠️ registerToken: no FCM token available to register');
      return;
    }

    _fcmToken = token;
    await prefs.setString('fcm_token', token);

    await _registerTokenWithBackend(token);
  }

  static Future<void> unregisterToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final tokenToUnregister =
          _fcmToken ?? prefs.getString('fcm_token') ?? prefs.getString('registered_fcm_token');

      if (tokenToUnregister == null || tokenToUnregister.isEmpty) return;

      final authToken = prefs.getString('accessToken');
      if (authToken == null) return;

      final response = await http.post(
        Uri.parse('${EnvConfig.baseUrl}/notifications/unregister-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'token': tokenToUnregister}),
      );

      if (response.statusCode == 200) {
        _fcmToken = null;
        await prefs.remove('registered_fcm_token');
        await prefs.remove('pending_fcm_token');
        await prefs.remove('fcm_token');
        debugPrint('✅ FCM token unregistered');
      }
    } catch (e) {
      debugPrint('❌ FCM token unregistration error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FOREGROUND MESSAGE HANDLER
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final type = message.data['type'] as String?;
    debugPrint(
      '📩 Foreground | type: $type | title: ${message.notification?.title}',
    );

    switch (type) {
      case 'payment_success':
        debugPrint(
          '💳 Payment success | paymentId: ${message.data['payment_id']}',
        );
        break;
      case 'payment_failed':
        debugPrint(
          '❌ Payment failed | paymentId: ${message.data['payment_id']}',
        );
        break;
      case 'subscription_expiry':
        debugPrint(
          '⏰ Expiry | daysLeft: ${message.data['days_left']} | plates: ${message.data['plates']}',
        );
        break;
      case 'safe_zone':
        debugPrint(
          '🛡️ Safe zone | vehicle: ${message.data['vehicle']} | zone: ${message.data['zone']}',
        );
        break;
      case 'geofence':
      case 'geofence_violation':
        debugPrint('📍 Geofence | vehicleId: ${message.data['vehicleId']}');
        break;
    }

    if (message.notification != null) {
      await _showLocalNotification(
        title: message.notification!.title ?? 'Notification',
        body: message.notification!.body ?? '',
        payload: jsonEncode(message.data),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAP ROUTING
  // ─────────────────────────────────────────────────────────────────────────

  static void _handleNotificationTap(RemoteMessage message) {
    _handleLocalNotificationTap(message.data);
  }

  static void _handleLocalNotificationTap(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final context = navigatorKey.currentContext;
    debugPrint('👆 Notification tapped | type: $type');

    switch (type) {
      case 'payment_success':
      case 'payment_failed':
        if (context != null) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        break;

      case 'subscription_expiry':
        if (context != null) {
          _handleSubscriptionExpiryTap(context, data);
        }
        break;

      case 'geofence_violation':
      case 'geofence':
        _handleGeofenceAlert(data);
        final vehicleIdG = int.tryParse(data['vehicleId']?.toString() ?? '');
        if (vehicleIdG != null) _navigateToDashboard(vehicleIdG);
        break;

      case 'safe_zone':
        final vehicleIdS = int.tryParse(data['vehicleId']?.toString() ?? '');
        if (vehicleIdS != null) _navigateToDashboard(vehicleIdS);
        break;

      case 'engine_control':
        final vehicleIdE = int.tryParse(data['vehicleId']?.toString() ?? '');
        if (vehicleIdE != null) _navigateToDashboard(vehicleIdE);
        break;

      case 'speeding':
      case 'trip':
      case 'battery':
        debugPrint('📌 $type tap — no navigation');
        break;

      default:
        final vehicleIdD = int.tryParse(data['vehicleId']?.toString() ?? '');
        if (vehicleIdD != null) _navigateToDashboard(vehicleIdD);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SUBSCRIPTION EXPIRY TAP
  // ─────────────────────────────────────────────────────────────────────────

  static void _handleSubscriptionExpiryTap(
      BuildContext context,
      Map<String, dynamic> data,
      ) {
    final rawIds = data['vehicle_ids']?.toString() ?? '';
    final rawPlates = data['plates']?.toString() ?? '';
    final daysLeft =
        int.tryParse(data['days_left']?.toString() ?? '3') ?? 3;

    final vehicleIds = rawIds
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();

    final plates = rawPlates
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (vehicleIds.isEmpty) return;

    if (vehicleIds.length == 1) {
      _navigateToSubscription(
        vehicleIds.first,
        plateHint: plates.isNotEmpty ? plates.first : null,
      );
      return;
    }

    final urgencyColor = daysLeft == 1
        ? Colors.red
        : daysLeft == 2
        ? Colors.orange
        : const Color(0xFF3B82F6);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.access_time_rounded, color: urgencyColor, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                daysLeft == 1 ? 'Expires Tomorrow' : 'Expires in $daysLeft Days',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: urgencyColor,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select a vehicle to renew:',
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            ...List.generate(vehicleIds.length, (i) {
              final plate =
              i < plates.length ? plates[i] : 'Vehicle ${vehicleIds[i]}';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: urgencyColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.directions_car,
                    color: urgencyColor,
                    size: 20,
                  ),
                ),
                title: Text(
                  plate,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _navigateToSubscription(vehicleIds[i], plateHint: plate);
                },
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Later', style: TextStyle(color: Colors.grey[600])),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NAVIGATION HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _navigateToSubscription(
      int vehicleId, {
        String? plateHint,
      }) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    String vehicleName = plateHint ?? '';
    if (vehicleName.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        vehicleName = prefs.getString('vehicle_name_$vehicleId') ??
            prefs.getString('current_vehicle_name') ??
            'Vehicle $vehicleId';
      } catch (_) {
        vehicleName = 'Vehicle $vehicleId';
      }
    }

    Navigator.of(context).pushNamed('/subscription', arguments: {
      'vehicleId': vehicleId,
      'vehicleName': vehicleName,
    });
  }

  static void _navigateToDashboard(int vehicleId) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      Navigator.of(context)
          .pushReplacementNamed('/dashboard', arguments: vehicleId);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GEOFENCE ALERT
  // ─────────────────────────────────────────────────────────────────────────

  static void _handleGeofenceAlert(Map<String, dynamic> data) {
    final vehicleId = int.tryParse(data['vehicleId']?.toString() ?? '');
    final vehicleName =
        data['vehicleName'] as String? ?? 'Your vehicle';
    final latitude = double.tryParse(data['latitude']?.toString() ?? '');
    final longitude = double.tryParse(data['longitude']?.toString() ?? '');

    if (vehicleId == null || latitude == null || longitude == null) {
      debugPrint('❌ Invalid geofence alert data');
      return;
    }

    _navigateToDashboard(vehicleId);

    Future.delayed(const Duration(milliseconds: 800), () {
      _showGeofenceAlertDialog(vehicleId, vehicleName, latitude, longitude);
    });
  }

  static void _showGeofenceAlertDialog(
      int vehicleId,
      String vehicleName,
      double lat,
      double lng,
      ) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Geofence Alert',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$vehicleName has left your defined geofence area.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Location: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                      style: TextStyle(fontSize: 12, color: Colors.red[900]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Do you want to disable the engine?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Not Now', style: TextStyle(color: Colors.grey[700])),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _disableEngine(vehicleId, vehicleName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Disable Engine'),
          ),
        ],
      ),
    );
  }

  static Future<void> _disableEngine(int vehicleId, String vehicleName) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF3B82F6)),
              SizedBox(height: 16),
              Text('Disabling engine...'),
            ],
          ),
        ),
      ),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('accessToken') ?? '';

      final response = await http.post(
        Uri.parse('${EnvConfig.baseUrl}/gps/issue-command'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'vehicleId': vehicleId,
          'command': 'CLOSERELAY',
          'params': '',
          'password': '',
          'sendTime': '',
        }),
      );

      if (context.mounted) Navigator.of(context).pop();

      final success = response.statusCode == 200 &&
          (() {
            try {
              final d = jsonDecode(response.body);
              return d['success'] == true ||
                  (d['response'] is Map &&
                      d['response']['success'] == 'true');
            } catch (_) {
              return false;
            }
          })();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  success ? Icons.check_circle : Icons.error_outline,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    success
                        ? 'Engine disabled successfully'
                        : 'Failed to disable engine',
                  ),
                ),
              ],
            ),
            backgroundColor: success ? Colors.red : Colors.grey[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error disabling engine: $e');
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOCAL NOTIFICATION DISPLAY
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'default_channel',
        'Default Notifications',
        channelDescription: 'General notifications from FLEETRA',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('❌ Error showing local notification: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DOMAIN HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> showNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    await _showLocalNotification(
      title: title,
      body: body,
      payload: data != null ? jsonEncode(data) : null,
    );
  }

  static Future<void> sendSafeZoneAlert(
      String vehicleName,
      String zoneName,
      ) async {
    await _showLocalNotification(
      title: '🛡️ Safe Zone Alert',
      body: '$vehicleName left safe zone "$zoneName"',
      payload: jsonEncode({
        'type': 'safe_zone',
        'vehicle': vehicleName,
        'zone': zoneName,
      }),
    );
  }

  static Future<void> sendGeofenceAlert(
      String vehicleName,
      String action,
      String zoneName,
      ) async {
    await _showLocalNotification(
      title: '📍 Geofence Alert',
      body: '$vehicleName $action geofence "$zoneName"',
      payload: jsonEncode({
        'type': 'geofence',
        'vehicle': vehicleName,
        'action': action,
        'zone': zoneName,
      }),
    );
  }

  static Future<void> sendEngineAlert(
      String vehicleName,
      String status,
      ) async {
    await _showLocalNotification(
      title: '🔧 Engine Alert',
      body: '$vehicleName engine is now $status',
      payload: jsonEncode({
        'type': 'engine_control',
        'vehicle': vehicleName,
        'status': status,
      }),
    );
  }

  static Future<void> sendTestNotification() async {
    try {
      if (_firebaseAvailable) {
        final prefs = await SharedPreferences.getInstance();
        final authToken = prefs.getString('accessToken');

        if (authToken == null) {
          await _showLocalNotification(
            title: '🔔 Test Notification',
            body: 'This is a local test notification!',
            payload: jsonEncode({'type': 'test'}),
          );
          return;
        }

        final response = await http.post(
          Uri.parse('${EnvConfig.baseUrl}/notifications/test'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $authToken',
          },
          body: jsonEncode({
            'title': '🔔 Test Notification',
            'body': 'This is a test notification from server!',
          }),
        );

        if (response.statusCode != 200) {
          await _showLocalNotification(
            title: '🔔 Test Notification',
            body: 'Local fallback notification',
            payload: jsonEncode({'type': 'test'}),
          );
        }
      } else {
        await _showLocalNotification(
          title: '🔔 Test Notification',
          body: 'This is a local test notification!',
          payload: jsonEncode({'type': 'test'}),
        );
      }
    } catch (e) {
      debugPrint('❌ sendTestNotification error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PERMISSIONS
  // ─────────────────────────────────────────────────────────────────────────

  static Future<bool> areNotificationsEnabled() async {
    try {
      final settings = await _firebaseMessaging.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestPermissions() async {
    try {
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GETTERS
  // ─────────────────────────────────────────────────────────────────────────

  static String? get fcmToken => _fcmToken;
  static bool get isFirebaseAvailable => _firebaseAvailable;
  static bool get isInitialized => _initialized;
}