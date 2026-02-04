import 'package:FLEETRA/src/screens/change%20password%20in%20app/change_password.dart';
import 'package:FLEETRA/src/screens/contact%20us/contact_us.dart';
import 'package:FLEETRA/src/screens/dashboard/dashboard.dart';
import 'package:FLEETRA/src/screens/lock%20screen/lock_screen.dart';
import 'package:FLEETRA/src/screens/login/login.dart';
import 'package:FLEETRA/src/screens/notification/notification_screen.dart';
import 'package:FLEETRA/src/screens/onBoarding/onBoardingScreen.dart';
import 'package:FLEETRA/src/screens/profile/profile.dart';
import 'package:FLEETRA/src/screens/settings/settings.dart';
import 'package:FLEETRA/src/screens/splash/splash_screen.dart';
import 'package:FLEETRA/src/screens/track/VehicleTrackingMap.dart';
import 'package:FLEETRA/src/screens/trip%20map/trip_map.dart';
import 'package:FLEETRA/src/screens/trip/trip_screen.dart';
import 'package:FLEETRA/src/services/app_lifecycle_service.dart';
import 'package:FLEETRA/src/services/connectivity_service.dart';
import 'package:FLEETRA/src/services/env_config.dart';
import 'package:FLEETRA/src/services/notification_service.dart';
import 'package:FLEETRA/src/services/pin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Screens


// Services


/// =====================================================
///  FCM Service - Handles token lifecycle with listeners
/// =====================================================
class FCMService {
  static const platform = MethodChannel('com.proxym.tracking/fcm');
  static bool _isInitialized = false;
  static String? _lastProcessedToken;

  /// Initialize FCM with token listeners
  static Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('⚠️ FCM Service already initialized, skipping...');
      return;
    }

    try {
      debugPrint('\n📲 ==========================================');
      debugPrint('📲 INITIALIZING FCM SERVICE WITH LISTENERS');
      debugPrint('📲 ==========================================');
      debugPrint('📲 Platform: ${Platform.isIOS ? "iOS" : "Android"}');

      // ✅ LISTENER 1: iOS Native Method Channel
      if (Platform.isIOS) {
        debugPrint('📱 Setting up iOS native method channel listener...');
        platform.setMethodCallHandler((call) async {
          if (call.method == 'onTokenRefresh') {
            String token = call.arguments as String;
            debugPrint('\n🔔 ==========================================');
            debugPrint('🔔 TOKEN RECEIVED FROM iOS NATIVE SIDE');
            debugPrint('🔔 ==========================================');
            debugPrint('🔔 Token: ${token.substring(0, 30)}...');
            debugPrint('🔔 Length: ${token.length} characters');
            debugPrint('🔔 ==========================================\n');
            await _handleTokenReceived(token, 'iOS Native');
          }
        });
        debugPrint('✅ iOS method channel listener active');
      }

      // ✅ LISTENER 2: Firebase onTokenRefresh (works for both iOS and Android)
      debugPrint('🔥 Setting up Firebase token refresh listener...');
      FirebaseMessaging.instance.onTokenRefresh.listen(
            (newToken) {
          debugPrint('\n🔔 ==========================================');
          debugPrint('🔔 TOKEN REFRESH EVENT FROM FIREBASE');
          debugPrint('🔔 ==========================================');
          debugPrint('🔔 Token: ${newToken.substring(0, 30)}...');
          debugPrint('🔔 Length: ${newToken.length} characters');
          debugPrint('🔔 ==========================================\n');
          _handleTokenReceived(newToken, 'Firebase Refresh');
        },
        onError: (error) {
          debugPrint('❌ Token refresh error: $error');
        },
      );
      debugPrint('✅ Firebase token refresh listener active');

      // ✅ OPTIONAL: Try to get initial token (may be null on iOS until APNs arrives)
      debugPrint('\n📱 Attempting to get initial FCM token...');
      final messaging = FirebaseMessaging.instance;

      // Check permission status
      final settings = await messaging.getNotificationSettings();
      debugPrint('🔔 Permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ Notification permission granted');

        try {
          final token = await messaging.getToken();
          if (token != null) {
            debugPrint('\n🎯 ==========================================');
            debugPrint('🎯 INITIAL TOKEN AVAILABLE IMMEDIATELY');
            debugPrint('🎯 ==========================================');
            debugPrint('🎯 Token: ${token.substring(0, 30)}...');
            debugPrint('🎯 Length: ${token.length} characters');
            debugPrint('🎯 ==========================================\n');
            await _handleTokenReceived(token, 'Initial Fetch');
          } else {
            debugPrint('⏳ Initial token not ready yet');
            debugPrint('⏳ This is normal on iOS - APNs token may still be loading');
            debugPrint('⏳ Token will arrive via listener when ready');
          }
        } catch (e) {
          debugPrint('⚠️ Error getting initial token: $e');
          if (e.toString().contains('apns-token-not-set')) {
            debugPrint('⏳ APNs token not set yet (iOS)');
            debugPrint('⏳ Token will arrive via listener when APNs is ready');
          }
        }
      } else {
        debugPrint('⚠️ Notification permission not granted: ${settings.authorizationStatus}');
      }

      _isInitialized = true;
      debugPrint('\n📲 ==========================================');
      debugPrint('📲 FCM SERVICE INITIALIZED SUCCESSFULLY');
      debugPrint('📲 Listeners are now active and waiting for tokens');
      debugPrint('📲 ==========================================\n');

    } catch (e, stackTrace) {
      debugPrint('❌ FCM Service initialization error: $e');
      debugPrint('❌ Stack trace: $stackTrace');
    }
  }

  /// Handle token when it's received from any source
  static Future<void> _handleTokenReceived(String token, String source) async {
    try {
      // Prevent duplicate processing
      if (_lastProcessedToken == token) {
        debugPrint('⚠️ Token already processed, skipping duplicate from $source');
        return;
      }

      debugPrint('\n🔑 ==========================================');
      debugPrint('🔑 PROCESSING NEW FCM TOKEN');
      debugPrint('🔑 ==========================================');
      debugPrint('🔑 Source: $source');
      debugPrint('🔑 Token: ${token.substring(0, 50)}...');
      debugPrint('🔑 Full length: ${token.length} characters');
      debugPrint('🔑 Time: ${DateTime.now()}');

      final prefs = await SharedPreferences.getInstance();

      // Save token locally immediately
      await prefs.setString('fcm_token', token);
      debugPrint('💾 Token saved to SharedPreferences');

      // Mark as processed
      _lastProcessedToken = token;

      // Check if user is logged in
      final userId = prefs.getInt('user_id');
      final authToken = prefs.getString('auth_token');

      debugPrint('👤 User ID: ${userId ?? "NOT LOGGED IN"}');
      debugPrint('🔐 Auth token: ${authToken != null ? "PRESENT" : "NOT PRESENT"}');

      if (userId == null || authToken == null) {
        debugPrint('\n⏳ ==========================================');
        debugPrint('⏳ USER NOT LOGGED IN - SAVING AS PENDING');
        debugPrint('⏳ ==========================================');
        await prefs.setString('pending_fcm_token', token);
        debugPrint('💾 Pending token saved');
        debugPrint('💾 Will send to backend after user logs in');
        debugPrint('⏳ ==========================================\n');
        return;
      }

      // User is logged in - send to backend
      debugPrint('\n📤 ==========================================');
      debugPrint('📤 SENDING TOKEN TO BACKEND');
      debugPrint('📤 ==========================================');
      await _sendTokenToBackend(token, userId, authToken);
      debugPrint('📤 ==========================================\n');

      debugPrint('🔑 ==========================================');
      debugPrint('🔑 TOKEN PROCESSING COMPLETE');
      debugPrint('🔑 ==========================================\n');

    } catch (e, stackTrace) {
      debugPrint('❌ Error handling token: $e');
      debugPrint('❌ Stack trace: $stackTrace');
    }
  }

  /// Send token to backend
  static Future<void> _sendTokenToBackend(String fcmToken, int userId, String authToken) async {
    try {
      final baseUrl = EnvConfig.baseUrl;
      debugPrint('📡 Backend URL: $baseUrl/users/fcm-token');
      debugPrint('📡 User ID: $userId');
      debugPrint('📡 Device type: ${Platform.isIOS ? "ios" : "android"}');

      final response = await http.post(
        Uri.parse('$baseUrl/users/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'user_id': userId,
          'fcm_token': fcmToken,
          'device_type': Platform.isIOS ? 'ios' : 'android',
        }),
      ).timeout(Duration(seconds: 10));

      debugPrint('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        debugPrint('\n✅ ==========================================');
        debugPrint('✅ TOKEN SUCCESSFULLY SENT TO BACKEND');
        debugPrint('✅ ==========================================');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('registered_fcm_token', fcmToken);
        await prefs.remove('pending_fcm_token');
        debugPrint('✅ Token marked as registered');
        debugPrint('✅ Pending token removed');
        debugPrint('✅ ==========================================\n');
      } else {
        debugPrint('\n❌ ==========================================');
        debugPrint('❌ FAILED TO SEND TOKEN TO BACKEND');
        debugPrint('❌ ==========================================');
        debugPrint('❌ Status code: ${response.statusCode}');
        debugPrint('❌ Response body: ${response.body}');
        debugPrint('❌ ==========================================\n');

        // Save as pending for retry
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_fcm_token', fcmToken);
        debugPrint('💾 Saved as pending token for retry');
      }
    } catch (e, stackTrace) {
      debugPrint('\n❌ ==========================================');
      debugPrint('❌ ERROR SENDING TOKEN TO BACKEND');
      debugPrint('❌ ==========================================');
      debugPrint('❌ Error: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      debugPrint('❌ ==========================================\n');

      // Save as pending for retry
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_fcm_token', fcmToken);
      debugPrint('💾 Saved as pending token for retry');
    }
  }

  /// Retry sending pending token (call after login)
  static Future<void> retryPendingToken() async {
    try {
      debugPrint('\n🔄 ==========================================');
      debugPrint('🔄 CHECKING FOR PENDING TOKEN');
      debugPrint('🔄 ==========================================');

      final prefs = await SharedPreferences.getInstance();
      final pendingToken = prefs.getString('pending_fcm_token');

      if (pendingToken != null) {
        debugPrint('🔄 Pending token found: ${pendingToken.substring(0, 30)}...');
        debugPrint('🔄 Retrying send to backend...');

        final userId = prefs.getInt('user_id');
        final authToken = prefs.getString('auth_token');

        if (userId != null && authToken != null) {
          await _sendTokenToBackend(pendingToken, userId, authToken);
          debugPrint('✅ Pending token retry complete');
        } else {
          debugPrint('⚠️ User credentials not available for retry');
        }
      } else {
        debugPrint('ℹ️ No pending token to retry');
      }

      debugPrint('🔄 ==========================================\n');
    } catch (e) {
      debugPrint('❌ Error retrying pending token: $e');
    }
  }
}

/// =====================================================
///  Firebase Background Notification Handler
/// =====================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint("📩 Background message: ${message.notification?.title}");

    if (message.notification != null) {
      await NotificationService.showNotification(
        title: message.notification!.title ?? 'Notification',
        body: message.notification!.body ?? '',
        data: message.data,
      );
    }
  } catch (e) {
    debugPrint("⚠️ Background handler error: $e");
  }
}

/// =====================================================
/// 🚀 MAIN ENTRY POINT
/// =====================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    debugPrint('\n🚀 ==========================================');
    debugPrint('🚀 APP INITIALIZATION START');
    debugPrint('🚀 ==========================================');
    debugPrint('🚀 Time: ${DateTime.now()}');
    debugPrint('🚀 Platform: ${Platform.isIOS ? "iOS" : "Android"}');

    // Step 1: Load environment
    debugPrint('\n📂 STEP 1: Loading environment variables...');
    await dotenv.load(fileName: ".env");
    await EnvConfig.load();
    if (!EnvConfig.validate()) {
      debugPrint("⚠️ Warning: Some environment variables missing!");
    }
    EnvConfig.printConfig();
    debugPrint('✅ Environment configuration loaded');

    // Step 2: Initialize Firebase
    debugPrint('\n🔥 STEP 2: Initializing Firebase...');
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      debugPrint('✅ Firebase initialized successfully');
    } catch (e) {
      debugPrint('⚠️ Firebase initialization error: $e');
    }

    // Step 3: Initialize FCM Service with listeners
    debugPrint('\n📲 STEP 3: Initializing FCM Service...');
    await FCMService.initialize();

    // Step 4: Initialize Notification Service
    debugPrint('\n🔔 STEP 4: Initializing Notification Service...');
    await NotificationService.initialize();
    debugPrint('✅ Notification service initialized');

    // Step 5: Initialize Connectivity
    debugPrint('\n🌐 STEP 5: Initializing Connectivity Service...');
    await ConnectivityService().initialize();
    debugPrint('✅ Connectivity service initialized');

    // Step 6: Initialize Lifecycle
    debugPrint('\n🔄 STEP 6: Initializing App Lifecycle Service...');
    AppLifecycleService().initialize();
    debugPrint('✅ Lifecycle service initialized');

    debugPrint('\n🚀 ==========================================');
    debugPrint('🚀 APP INITIALIZATION COMPLETE');
    debugPrint('🚀 ==========================================\n');

    runApp(const MyApp());
  } catch (error, stackTrace) {
    debugPrint('\n❌ ==========================================');
    debugPrint('❌ FATAL INITIALIZATION ERROR');
    debugPrint('❌ ==========================================');
    debugPrint('❌ Error: $error');
    debugPrint('❌ Stack trace: $stackTrace');
    debugPrint('❌ ==========================================\n');
    runApp(const MyApp());
  }
}

/// =====================================================
/// 🟦 MAIN APP WIDGET
/// =====================================================
class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final PinService _pinService = PinService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('✅ App lifecycle observer registered');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    debugPrint('🗑️ App lifecycle observer removed');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    debugPrint('📱 App lifecycle: $state');

    if (state == AppLifecycleState.resumed) {
      debugPrint('🔓 App resumed - checking PIN...');

      final shouldLock = await AppLifecycleService().shouldRequirePin();

      if (shouldLock) {
        final hasPinSet = await _pinService.hasPinSet();

        if (hasPinSet) {
          final prefs = await SharedPreferences.getInstance();
          final vehicleId = prefs.getInt('current_vehicle_id');

          if (vehicleId != null) {
            debugPrint('🔐 Showing PIN screen...');
            NotificationService.navigatorKey.currentState?.pushNamedAndRemoveUntil(
              '/pin-entry',
                  (route) => false,
              arguments: vehicleId,
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FLEETRA',
      debugShowCheckedModeBanner: false,
      navigatorKey: NotificationService.navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Color(0xFF3B82F6),
          brightness: Brightness.light,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF3B82F6),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const SplashScreen(),
      onGenerateRoute: (settings) {
        debugPrint('📍 Navigating to: ${settings.name}');

        switch (settings.name) {
          case '/splash':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const SplashScreen(),
            );

          case '/login':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => ModernLoginScreen(),
            );

          case '/onboarding':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => OnboardingScreen(),
            );

          case '/dashboard':
            final vehicleId = settings.arguments as int?;
            if (vehicleId == null) {
              return _errorRoute("❌ Missing vehicleId for Dashboard");
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => ModernDashboard(vehicleId: vehicleId),
            );

          case '/profile':
            final vehicleId = settings.arguments as int?;
            if (vehicleId == null) {
              return _errorRoute("❌ Missing vehicleId for Profile");
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => ProfileScreen(vehicleId: vehicleId),
            );

          case '/change-password':
            final args = settings.arguments as Map<String, dynamic>?;
            if (args == null || args['phone'] == null || args['userId'] == null) {
              return _errorRoute("❌ Missing args for Change Password");
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => ChangePasswordScreen(
                initialPhone: args['phone'] as String,
                userId: args['userId'] as int,
              ),
            );

          case '/settings':
            final vehicleId = settings.arguments as int?;
            if (vehicleId == null) {
              return _errorRoute("❌ Missing vehicleId for Settings");
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => SettingsScreen(vehicleId: vehicleId),
            );

          case '/contact':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => ContactScreen(),
            );

          case '/track':
            final vehicleId = settings.arguments as int?;
            if (vehicleId == null) {
              return _errorRoute("❌ Missing vehicleId for Tracking");
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => VehicleTrackingMap(vehicleId: vehicleId),
            );

          case '/trip-map':
            final args = settings.arguments as Map<String, dynamic>?;
            if (args == null || args['tripId'] == null || args['vehicleId'] == null) {
              return _errorRoute("❌ Missing args for Trip Map");
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => TripMapScreen(
                tripId: args['tripId'],
                vehicleId: args['vehicleId'],
              ),
            );

          case '/trips':
            final vehicleId = settings.arguments as int?;
            if (vehicleId == null) {
              return _errorRoute("❌ Missing vehicleId for Trips");
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => TripsScreen(vehicleId: vehicleId),
            );

          case '/notifications':
            final args = settings.arguments as Map<String, dynamic>?;
            final int? vehicleId = args?['vehicleId'];
            if (vehicleId == null) {
              return _errorRoute("❌ Missing vehicleId for Notifications");
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => NotificationScreen(vehicleId: vehicleId),
            );

          case '/pin-entry':
            final vehicleId = settings.arguments as int?;
            if (vehicleId == null) {
              return _errorRoute("❌ Missing vehicleId for PIN Entry");
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => PinEntryScreen(vehicleId: vehicleId),
            );

          default:
            return _errorRoute("❌ Route not found: ${settings.name}");
        }
      },
    );
  }

  MaterialPageRoute _errorRoute(String message) {
    debugPrint(message);
    return MaterialPageRoute(
      builder: (context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text('Error'),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red),
                SizedBox(height: 24),
                Text(
                  'Navigation Error',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red),
                ),
                SizedBox(height: 16),
                Text(
                  message,
                  style: TextStyle(fontSize: 16, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacementNamed('/splash'),
                  icon: Icon(Icons.refresh),
                  label: Text('Restart App'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}