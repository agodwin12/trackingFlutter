// lib/src/services/notification_service.dart
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
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

  /// ✅ Initialize Firebase and notification services
  static Future<void> initialize() async {
    if (_initialized) {
      debugPrint('⚠️ Notification service already initialized');
      return;
    }

    try {
      debugPrint('🔔 Initializing notification service...');

      // ✅ Initialize local notifications first (always works)
      await _initializeLocalNotifications();

      // ✅ Try Firebase initialization with error handling
      try {
        // Request permissions
        NotificationSettings settings = await _firebaseMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          debugPrint('✅ Notification permissions granted');

          // Try to get FCM token
          try {
            String? token = await _firebaseMessaging.getToken();
            if (token != null) {
              _fcmToken = token;
              _firebaseAvailable = true;
              debugPrint('📱 FCM Token: $token');
              await _registerTokenWithBackend(token);
            } else {
              debugPrint('⚠️ No FCM token available');
            }

            // Listen for token refresh
            _firebaseMessaging.onTokenRefresh.listen((newToken) {
              _fcmToken = newToken;
              debugPrint('🔄 FCM Token refreshed: $newToken');
              _registerTokenWithBackend(newToken);
            });

            // ✅ Set up background message handler
            FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

            // ✅ Handle foreground messages
            FirebaseMessaging.onMessage.listen((RemoteMessage message) {
              debugPrint('📨 Foreground message received: ${message.notification?.title}');
              _handleForegroundMessage(message);
            });

            // ✅ Handle notification tap when app is in background
            FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
              debugPrint('📬 Notification opened app: ${message.notification?.title}');
              _handleNotificationTap(message);
            });

            // ✅ Check for initial notification (if app was opened from terminated state)
            RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
            if (initialMessage != null) {
              debugPrint('📬 App opened from notification: ${initialMessage.notification?.title}');
              _handleNotificationTap(initialMessage);
            }

            debugPrint('✅ Firebase Messaging initialized successfully');
          } catch (tokenError) {
            debugPrint('⚠️ FCM token error: $tokenError');
            _firebaseAvailable = false;
          }
        } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
          debugPrint('❌ Notification permissions denied');
        } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
          debugPrint('⚠️ Notification permissions provisional');
        }
      } catch (firebaseError) {
        debugPrint('⚠️ Firebase Cloud Messaging not available: $firebaseError');
        debugPrint('ℹ️ Push notifications will be disabled, but app will continue working');
        _firebaseAvailable = false;
      }

      _initialized = true;
      debugPrint('✅ Notification service initialized successfully');
    } catch (error) {
      debugPrint('❌ Error initializing notifications: $error');
      _initialized = true; // Mark as initialized even with errors to prevent re-init
      // Don't throw - allow app to continue without notifications
    }
  }

  /// ✅ Initialize local notifications plugin
  static Future<void> _initializeLocalNotifications() async {
    try {
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

      await _localNotifications.initialize(
        settings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Handle notification tap from local notification
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

      debugPrint("✅ Local notifications initialized");
    } catch (e) {
      debugPrint("❌ Error initializing local notifications: $e");
    }
  }

  /// ✅ Handle foreground messages (when app is open)
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint("📩 Foreground message received: ${message.notification?.title}");

    // Show local notification
    if (message.notification != null) {
      await _showLocalNotification(
        title: message.notification!.title ?? 'Notification',
        body: message.notification!.body ?? '',
        payload: jsonEncode(message.data),
      );
    }
  }

  /// ✅ Handle notification tap from Firebase (when user taps on notification)
  static void _handleNotificationTap(RemoteMessage message) {
    debugPrint("👆 Firebase notification tapped: ${message.data}");
    _handleLocalNotificationTap(message.data);
  }

  /// ✅ Handle notification tap routing
  static void _handleLocalNotificationTap(Map<String, dynamic> data) {
    final String? type = data['type'];

    debugPrint("📱 Notification type: $type");

    switch (type) {
      case 'geofence':
        debugPrint("🗺️ Navigate to geofence details");
        // TODO: Navigate to geofence screen
        break;
      case 'safe_zone':
        debugPrint("🛡️ Navigate to safe zone details");
        // TODO: Navigate to safe zone screen
        break;
      case 'speeding':
        debugPrint("⚡ Navigate to speed alerts");
        // TODO: Navigate to alerts screen
        break;
      case 'engine_control':
        debugPrint("🔧 Navigate to engine control");
        // TODO: Navigate to dashboard
        break;
      case 'trip':
        debugPrint("🚗 Navigate to trip details");
        // TODO: Navigate to trips screen
        break;
      case 'battery':
        debugPrint("🔋 Navigate to vehicle details");
        // TODO: Navigate to vehicle screen
        break;
      default:
        debugPrint("📱 Navigate to dashboard");
    // TODO: Navigate to dashboard
    }
  }

  /// ✅ Show local notification
  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'default_channel',
        'Default Notifications',
        channelDescription: 'General notifications from PROXYM TRACKING',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
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

      debugPrint("✅ Local notification shown: $title");
    } catch (e) {
      debugPrint("❌ Error showing local notification: $e");
    }
  }

  /// ✅ Register FCM token with backend
  static Future<void> registerToken() async {
    if (_fcmToken == null) {
      debugPrint("⚠️ No FCM token available to register");
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

      debugPrint("📱 Registering FCM token with backend...");

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
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint("✅ FCM token registered with backend");
      } else {
        debugPrint("⚠️ Failed to register FCM token: ${response.statusCode} - ${response.body}");
      }
    } catch (error) {
      debugPrint("❌ Error registering FCM token: $error");
    }
  }

  /// ✅ Internal method - don't register automatically
  static Future<void> _registerTokenWithBackend(String token) async {
    // Store token but don't register yet (no auth token available)
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
          // Still show local notification
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
          // Fallback to local notification
          await _showLocalNotification(
            title: '🔔 Test Notification',
            body: 'This is a local test notification!',
            payload: jsonEncode({'type': 'test'}),
          );
        }
      } else {
        // Show local notification if Firebase not available
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