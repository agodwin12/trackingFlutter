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

// ✅ Top-level function for background message handling
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint("📩 Background message received: ${message.notification?.title}");
  } catch (e) {
    debugPrint("⚠️ Background handler error: $e");
  }
}

class NotificationService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static String? _fcmToken;
  static bool _firebaseAvailable = false;

  // ✅ Global navigator key for navigation from notifications
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// ✅ Initialize Firebase and notification services - ENHANCED DEBUGGING
  static Future<void> initialize() async {
    if (_initialized) {
      debugPrint('⚠️ Notification service already initialized');
      return;
    }

    try {
      print("\n========================================");
      print("🔔 INITIALIZING NOTIFICATION SERVICE");
      print("========================================");
      print("📱 Platform: ${defaultTargetPlatform.toString()}");
      print("🏗️ Debug Mode: ${kDebugMode}");
      print("========================================\n");

      // ✅ Initialize local notifications first (always works)
      await _initializeLocalNotifications();

      // ✅ Try Firebase initialization with error handling
      try {
        print("========================================");
        print("🔥 REQUESTING NOTIFICATION PERMISSIONS");
        print("========================================");

        // Request permissions with detailed logging
        NotificationSettings settings = await _firebaseMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
          announcement: false,
          carPlay: false,
          criticalAlert: false,
        );

        print("📋 Permission Status: ${settings.authorizationStatus}");
        print("🔔 Alert: ${settings.alert}");
        print("🔵 Badge: ${settings.badge}");
        print("🔊 Sound: ${settings.sound}");
        print("📢 Announcement: ${settings.announcement}");
        print("🚗 CarPlay: ${settings.carPlay}");
        print("⚠️ Critical: ${settings.criticalAlert}");
        print("🔒 Lock Screen: ${settings.lockScreen}");
        print("📱 Notification Center: ${settings.notificationCenter}");
        print("========================================\n");

        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          debugPrint('✅ Notification permissions granted');

          // ✅ Configure FCM for iOS to receive notifications in foreground
          if (defaultTargetPlatform == TargetPlatform.iOS) {
            print("🍎 Configuring iOS foreground notification presentation options...");
            await _firebaseMessaging.setForegroundNotificationPresentationOptions(
              alert: true,
              badge: true,
              sound: true,
            );
            print("✅ iOS foreground options configured");
          }

          // Try to get FCM token with enhanced error handling
          try {
            print("\n========================================");
            print("📱 GETTING FCM TOKEN");
            print("========================================");

            // Add timeout to token retrieval
            String? token = await _firebaseMessaging.getToken().timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                print("⏰ FCM token retrieval timeout!");
                return null;
              },
            );

            if (token != null && token.isNotEmpty) {
              _fcmToken = token;
              _firebaseAvailable = true;
              print("✅ FCM Token received!");
              print("📱 Token (first 50 chars): ${token.substring(0, token.length > 50 ? 50 : token.length)}...");
              print("📏 Token length: ${token.length}");
              print("========================================\n");

              await _registerTokenWithBackend(token);
            } else {
              print("❌ FCM token is null or empty");
              print("🔍 Possible causes:");
              print("   - Google Play Services not available (Android)");
              print("   - APNs not configured (iOS)");
              print("   - No internet connection");
              print("   - Firebase configuration missing");
              print("========================================\n");
              _firebaseAvailable = false;
            }

            // Listen for token refresh
            _firebaseMessaging.onTokenRefresh.listen((newToken) {
              print("\n========================================");
              print("🔄 FCM TOKEN REFRESHED");
              print("========================================");
              _fcmToken = newToken;
              print('📱 New Token: ${newToken.substring(0, 50)}...');
              print("========================================\n");
              _registerTokenWithBackend(newToken);
            }, onError: (error) {
              print("❌ Token refresh error: $error");
            });

            // ✅ Set up background message handler
            FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
            print("✅ Background message handler registered");

            // ✅ Handle foreground messages
            FirebaseMessaging.onMessage.listen((RemoteMessage message) {
              debugPrint('📨 Foreground message received: ${message.notification?.title}');
              _handleForegroundMessage(message);
            }, onError: (error) {
              print("❌ Foreground message error: $error");
            });

            // ✅ Handle notification tap when app is in background
            FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
              debugPrint('📬 Notification opened app: ${message.notification?.title}');
              _handleNotificationTap(message);
            }, onError: (error) {
              print("❌ Message opened error: $error");
            });

            // ✅ Check for initial notification (if app was opened from terminated state)
            RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
            if (initialMessage != null) {
              debugPrint('📬 App opened from notification: ${initialMessage.notification?.title}');
              _handleNotificationTap(initialMessage);
            }

            print("✅ Firebase Messaging initialized successfully\n");
          } catch (tokenError) {
            print("\n========================================");
            print("❌ FCM TOKEN ERROR");
            print("========================================");
            print("Error: $tokenError");
            print("Stack trace: ${StackTrace.current}");
            print("========================================\n");
            _firebaseAvailable = false;
          }
        } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
          print("========================================");
          print("❌ NOTIFICATION PERMISSIONS DENIED");
          print("========================================");
          print("User has denied notification permissions.");
          print("On iOS: User must enable in Settings > App > Notifications");
          print("On Android: User must enable in Settings > Apps > App > Notifications");
          print("========================================\n");
        } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
          print("========================================");
          print("⚠️ NOTIFICATION PERMISSIONS PROVISIONAL");
          print("========================================");
          print("Notifications will be delivered quietly.");
          print("========================================\n");
        } else if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
          print("========================================");
          print("❓ NOTIFICATION PERMISSIONS NOT DETERMINED");
          print("========================================");
          print("User hasn't been asked for permissions yet.");
          print("========================================\n");
        }
      } catch (firebaseError) {
        print("\n========================================");
        print("❌ FIREBASE INITIALIZATION ERROR");
        print("========================================");
        print("Error: $firebaseError");
        print("Stack trace: ${StackTrace.current}");
        print("\n🔍 Common causes:");
        print("   Android:");
        print("     - google-services.json missing or incorrect");
        print("     - Google Play Services not installed/updated");
        print("     - SHA-1 fingerprint not added to Firebase Console");
        print("   iOS:");
        print("     - GoogleService-Info.plist missing");
        print("     - APNs certificate/key not configured in Firebase");
        print("     - Push Notifications capability not enabled in Xcode");
        print("========================================\n");
        _firebaseAvailable = false;
      }

      _initialized = true;
      print("✅ Notification service initialization complete\n");
    } catch (error) {
      print("\n========================================");
      print("❌ CRITICAL INITIALIZATION ERROR");
      print("========================================");
      print("Error: $error");
      print("Stack trace: ${StackTrace.current}");
      print("========================================\n");
      _initialized = true; // Mark as initialized even with errors to prevent re-init
    }
  }

  /// ✅ Initialize local notifications plugin
  static Future<void> _initializeLocalNotifications() async {
    try {
      print("🔔 Initializing local notifications plugin...");

      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      bool? initialized = await _localNotifications.initialize(
        settings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          if (response.payload != null) {
            debugPrint("🔔 Local notification tapped: ${response.payload}");
            try {
              final Map<String, dynamic> data = jsonDecode(response.payload!);
              _handleLocalNotificationTap(data);
            } catch (e) {
              debugPrint("⚠️ Error parsing notification payload: $e");
            }
          }
        },
      );

      if (initialized == true) {
        print("✅ Local notifications initialized successfully\n");
      } else {
        print("⚠️ Local notifications initialization returned: $initialized\n");
      }
    } catch (e) {
      print("❌ Error initializing local notifications: $e");
      print("Stack trace: ${StackTrace.current}\n");
    }
  }

  /// ✅ Handle foreground messages (when app is open) - ENHANCED DEBUG
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print("========================================");
    print("📩 FOREGROUND NOTIFICATION RECEIVED!");
    print("========================================");
    print("🔔 Title: ${message.notification?.title}");
    print("🔔 Body: ${message.notification?.body}");
    print("📦 Data payload: ${message.data}");
    print("🆔 Message ID: ${message.messageId}");
    print("⏰ Sent at: ${message.sentTime}");

    // ✅ Check notification type
    final String? type = message.data['type'];
    print("📱 Notification Type: $type");

    if (type == 'safe_zone') {
      print("========================================");
      print("🛡️ SAFE ZONE ALERT DETECTED!");
      print("Vehicle: ${message.data['vehicle']}");
      print("Zone: ${message.data['zone']}");
      print("Event: ${message.data['event'] ?? 'exit'}");
      print("Timestamp: ${message.data['timestamp']}");
      print("========================================");
    } else if (type == 'geofence' || type == 'geofence_violation') {
      print("========================================");
      print("📍 GEOFENCE ALERT DETECTED!");
      print("Vehicle ID: ${message.data['vehicleId']}");
      print("Vehicle Name: ${message.data['vehicleName']}");
      print("Location: ${message.data['locationName']}");
      print("Latitude: ${message.data['latitude']}");
      print("Longitude: ${message.data['longitude']}");
      print("========================================");
    }

    print("========================================");

    // Show local notification
    if (message.notification != null) {
      print("📱 Showing local notification...");
      await _showLocalNotification(
        title: message.notification!.title ?? 'Notification',
        body: message.notification!.body ?? '',
        payload: jsonEncode(message.data),
      );
      print("✅ Local notification shown!");
    } else {
      print("⚠️ No notification payload in message - data only notification");
    }

    print("========================================\n");
  }

  /// ✅ Handle notification tap from Firebase (when user taps on notification)
  static void _handleNotificationTap(RemoteMessage message) {
    debugPrint("👆 Firebase notification tapped: ${message.data}");
    _handleLocalNotificationTap(message.data);
  }

  /// ✅ Handle notification tap routing - ENHANCED DEBUG
  static void _handleLocalNotificationTap(Map<String, dynamic> data) {
    print("\n========================================");
    print("👆 NOTIFICATION TAPPED!");
    print("========================================");
    print("📦 Full data: $data");

    final String? type = data['type'];
    print("📱 Notification type: $type");

    switch (type) {
      case 'geofence_violation':
        print("========================================");
        print("🚨 GEOFENCE VIOLATION TAP DETECTED");
        print("Vehicle ID: ${data['vehicleId']}");
        print("Vehicle Name: ${data['vehicleName']}");
        print("Location: ${data['locationName']}");
        print("Coordinates: [${data['latitude']}, ${data['longitude']}]");
        print("========================================");

        _handleGeofenceAlert(data);
        final vehicleId = int.tryParse(data['vehicleId']?.toString() ?? '');
        if (vehicleId != null) {
          _navigateToDashboard(vehicleId);
        }
        break;

      case 'geofence':
        print("========================================");
        print("📍 GEOFENCE TAP DETECTED");
        print("Vehicle ID: ${data['vehicleId']}");
        print("Vehicle Name: ${data['vehicleName']}");
        print("========================================");

        _handleGeofenceAlert(data);
        final vehicleId = int.tryParse(data['vehicleId']?.toString() ?? '');
        if (vehicleId != null) {
          _navigateToDashboard(vehicleId);
        }
        break;

      case 'safe_zone':
        print("========================================");
        print("🛡️ SAFE ZONE TAP DETECTED");
        print("Vehicle ID: ${data['vehicleId']}");
        print("Vehicle Name: ${data['vehicleName']}");
        print("Zone: ${data['zone_name']}");
        print("Event: ${data['event'] ?? 'exit'}");
        print("========================================");

        final vehicleId = int.tryParse(data['vehicleId']?.toString() ?? '');
        if (vehicleId != null) {
          _navigateToDashboard(vehicleId);
        }
        break;

      case 'speeding':
        print("⚡ SPEEDING ALERT TAP");
        break;

      case 'engine_control':
        print("🔧 ENGINE CONTROL TAP");
        final vehicleId = int.tryParse(data['vehicleId']?.toString() ?? '');
        if (vehicleId != null) {
          _navigateToDashboard(vehicleId);
        }
        break;

      case 'trip':
        print("🚗 TRIP TAP");
        break;

      case 'battery':
        print("🔋 BATTERY TAP");
        break;

      default:
        print("📱 DEFAULT TAP - Navigating to dashboard");
        final vehicleId = int.tryParse(data['vehicleId']?.toString() ?? '');
        if (vehicleId != null) {
          _navigateToDashboard(vehicleId);
        }
    }

    print("========================================\n");
  }

  /// ✅ Handle geofence violation alert
  static void _handleGeofenceAlert(Map<String, dynamic> data) {
    final vehicleId = int.tryParse(data['vehicleId']?.toString() ?? '');
    final vehicleName = data['vehicleName'] ?? 'Your vehicle';
    final latitude = double.tryParse(data['latitude']?.toString() ?? '');
    final longitude = double.tryParse(data['longitude']?.toString() ?? '');

    if (vehicleId == null || latitude == null || longitude == null) {
      debugPrint('❌ Invalid geofence alert data');
      return;
    }

    debugPrint('🚨 Handling geofence alert for vehicle $vehicleId');

    // Navigate to dashboard
    _navigateToDashboard(vehicleId);

    // Show dialog after navigation
    Future.delayed(const Duration(milliseconds: 800), () {
      _showGeofenceAlertDialog(vehicleId, vehicleName, latitude, longitude);
    });
  }

  /// ✅ Navigate to dashboard
  static void _navigateToDashboard(int vehicleId) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      debugPrint('🧭 Navigating to dashboard for vehicle $vehicleId');
      Navigator.of(context).pushReplacementNamed(
        '/dashboard',
        arguments: vehicleId,
      );
    } else {
      debugPrint('⚠️ Navigator context not available');
    }
  }

  /// ✅ Show geofence alert dialog with option to disable engine
  static void _showGeofenceAlertDialog(
      int vehicleId,
      String vehicleName,
      double latitude,
      double longitude,
      ) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('⚠️ Cannot show dialog - context not available');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              Icons.warning_rounded,
              color: Colors.red,
              size: 28,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Geofence Alert',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
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
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Location: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Do you want to disable the engine?',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: Text(
              'Not Now',
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _disableEngine(vehicleId, vehicleName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text('Disable Engine'),
          ),
        ],
      ),
    );
  }

  /// ✅ Disable engine (send CLOSERELAY command)
  static Future<void> _disableEngine(int vehicleId, String vehicleName) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Center(
        child: Container(
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
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
      debugPrint('🔧 Sending CLOSERELAY command for vehicle $vehicleId');

      final response = await http.post(
        Uri.parse("${EnvConfig.baseUrl}/gps/issue-command"),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "vehicleId": vehicleId,
          "command": "CLOSERELAY",
          "params": "",
          "password": "",
          "sendTime": "",
        }),
      );

      Navigator.of(context).pop(); // Close loading

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final bool success = data['success'] == true ||
            (data['response'] is Map && data['response']['success'] == 'true');

        if (success) {
          debugPrint('✅ Engine disabled successfully');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Engine disabled successfully'),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          throw Exception('Command failed');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error disabling engine: $e');

      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // Close loading if still open
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to disable engine: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// ✅ Show local notification - ENHANCED FOR ANDROID 13+
  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      print("🔔 Attempting to show local notification...");
      print("   Title: $title");
      print("   Body: $body");

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'default_channel',
        'Default Notifications',
        channelDescription: 'General notifications from PROXYM TRACKING',
        importance: Importance.max, // Changed from high to max
        priority: Priority.high,
        showWhen: true,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
        ticker: 'PROXYM TRACKING',
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unique ID
        title,
        body,
        details,
        payload: payload,
      );

      print("✅ Local notification command sent successfully");
    } catch (e) {
      print("❌ Error showing local notification: $e");
      print("Stack trace: ${StackTrace.current}");
    }
  }

  /// ✅ Register FCM token with backend - ENHANCED LOGGING
  static Future<void> registerToken() async {
    if (_fcmToken == null) {
      print("========================================");
      print("⚠️ NO FCM TOKEN TO REGISTER");
      print("========================================");
      print("This means FCM token was not generated.");
      print("Check the initialization logs above for errors.");
      print("========================================\n");
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('accessToken');

      if (authToken == null) {
        debugPrint("⚠️ No auth token found, skipping FCM registration");
        debugPrint("ℹ️ Token will be registered after login");
        return;
      }

      print("\n========================================");
      print("📱 REGISTERING FCM TOKEN WITH BACKEND");
      print("========================================");
      print("Token: ${_fcmToken!.substring(0, 50)}...");
      print("Device: ${defaultTargetPlatform == TargetPlatform.iOS ? "iOS" : "Android"}");

      final response = await http.post(
        Uri.parse("${EnvConfig.baseUrl}/notifications/register-token"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $authToken",
        },
        body: json.encode({
          "token": _fcmToken,
          "device_type": defaultTargetPlatform == TargetPlatform.iOS ? "ios" : "android",
          "device_id": null,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Token registration timeout');
        },
      );

      print("Response status: ${response.statusCode}");
      print("Response body: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        print("✅ FCM TOKEN REGISTERED SUCCESSFULLY");
        print("========================================\n");
      } else {
        print("❌ FAILED TO REGISTER FCM TOKEN");
        print("Status: ${response.statusCode}");
        print("Body: ${response.body}");
        print("========================================\n");
      }
    } catch (error) {
      print("\n========================================");
      print("❌ ERROR REGISTERING FCM TOKEN");
      print("========================================");
      print("Error: $error");
      print("Stack trace: ${StackTrace.current}");
      print("========================================\n");
    }
  }

  /// ✅ Internal method - don't register automatically
  static Future<void> _registerTokenWithBackend(String token) async {
    debugPrint("📱 FCM Token received: ${token.substring(0, 50)}...");
    debugPrint("ℹ️ Will register after user login");
  }

  /// ✅ Unregister token (call on logout)
  static Future<void> unregisterToken() async {
    try {
      if (_fcmToken == null) {
        debugPrint("⚠️ No FCM token to unregister");
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('accessToken');

      if (authToken == null) {
        debugPrint("⚠️ No auth token found for unregistration");
        return;
      }

      final response = await http.post(
        Uri.parse("${EnvConfig.baseUrl}/notifications/unregister-token"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $authToken",
        },
        body: json.encode({
          "token": _fcmToken,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint("✅ FCM token unregistered");
        _fcmToken = null;
      } else {
        debugPrint("⚠️ Failed to unregister token: ${response.statusCode}");
      }
    } catch (error) {
      debugPrint("❌ Error unregistering token: $error");
    }
  }

  /// ✅ Send safe zone alert notification
  static Future<void> sendSafeZoneAlert(String vehicleName, String zoneName) async {
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

  /// ✅ Send geofence alert notification
  static Future<void> sendGeofenceAlert(String vehicleName, String action, String zoneName) async {
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

  /// ✅ Send engine control notification
  static Future<void> sendEngineAlert(String vehicleName, String status) async {
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

  /// ✅ Send test notification
  static Future<void> sendTestNotification() async {
    try {
      if (_firebaseAvailable) {
        final prefs = await SharedPreferences.getInstance();
        final authToken = prefs.getString('accessToken');

        if (authToken == null) {
          debugPrint("⚠️ No auth token found");
          await _showLocalNotification(
            title: '🔔 Test Notification',
            body: 'This is a local test notification!',
            payload: jsonEncode({'type': 'test'}),
          );
          return;
        }

        final response = await http.post(
          Uri.parse("${EnvConfig.baseUrl}/notifications/test"),
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $authToken",
          },
          body: json.encode({
            "title": "🔔 Test Notification",
            "body": "This is a test notification from server!",
          }),
        );

        if (response.statusCode == 200) {
          debugPrint("✅ Test notification sent from server");
        } else {
          debugPrint("⚠️ Failed to send test notification: ${response.body}");
          await _showLocalNotification(
            title: '🔔  Notification',
            body: 'notification!',
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
    } catch (error) {
      debugPrint("❌ Error sending test notification: $error");
    }
  }

  /// ✅ Check if notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    try {
      final settings = await _firebaseMessaging.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      debugPrint("⚠️ Error checking notification status: $e");
      return false;
    }
  }

  /// ✅ Public method to show notification (for backward compatibility)
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

  /// ✅ Request notification permissions
  static Future<bool> requestPermissions() async {
    try {
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      debugPrint("⚠️ Error requesting permissions: $e");
      return false;
    }
  }

  /// Get current FCM token
  static String? get fcmToken => _fcmToken;

  /// Check if Firebase is available
  static bool get isFirebaseAvailable => _firebaseAvailable;

  /// Check if service is initialized
  static bool get isInitialized => _initialized;
}