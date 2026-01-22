import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:tracking/src/screens/change%20password%20in%20app/change_password.dart';
import 'package:tracking/src/screens/login/login.dart';

// Screens
import 'package:tracking/src/screens/splash/splash_screen.dart';
import 'package:tracking/src/screens/onBoarding/onBoardingScreen.dart';
import 'package:tracking/src/screens/dashboard/dashboard.dart';
import 'package:tracking/src/screens/profile/profile.dart';
import 'package:tracking/src/screens/settings/settings.dart';
import 'package:tracking/src/screens/track/VehicleTrackingMap.dart';
import 'package:tracking/src/screens/trip map/trip_map.dart';
import 'package:tracking/src/screens/trip/trip_screen.dart';
import 'package:tracking/src/screens/notification/notification_screen.dart';
import 'package:tracking/src/screens/contact us/contact_us.dart';
import 'package:tracking/src/screens/lock screen/lock_screen.dart';

// Services
import 'package:tracking/src/services/env_config.dart';
import 'package:tracking/src/services/notification_service.dart';
import 'package:tracking/src/services/pin_service.dart';
import 'package:tracking/src/services/connectivity_service.dart';
import 'package:tracking/src/services/app_lifecycle_service.dart';

/// =====================================================
///  FCM Service for iOS Token Handling
/// =====================================================
class FCMService {
  static const platform = MethodChannel('com.proxym.tracking/fcm');

  // Initialize FCM listener
  static Future<void> initialize() async {
    // Listen for token from iOS
    platform.setMethodCallHandler((call) async {
      if (call.method == 'onTokenRefresh') {
        String token = call.arguments as String;
        debugPrint('📱 FCM Token received from iOS: $token');
        await _sendTokenToBackend(token);
      }
    });

    debugPrint('✅ FCM Service initialized');
  }

  // Send token to backend
  static Future<void> _sendTokenToBackend(String fcmToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      final authToken = prefs.getString('auth_token');

      if (userId == null || authToken == null) {
        debugPrint('⚠️ User not logged in, skipping token send');
        // Save token locally for later
        await prefs.setString('pending_fcm_token', fcmToken);
        return;
      }

      final baseUrl = EnvConfig.baseUrl;
      final response = await http.post(
        Uri.parse('$baseUrl/users/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'user_id': userId,
          'fcm_token': fcmToken,
          'device_type': 'ios',
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ FCM token sent to backend successfully');
        await prefs.setString('fcm_token', fcmToken);
        // Remove pending token
        await prefs.remove('pending_fcm_token');
      } else {
        debugPrint('❌ Failed to send FCM token: ${response.statusCode}');
        // Save as pending for retry
        await prefs.setString('pending_fcm_token', fcmToken);
      }
    } catch (e) {
      debugPrint('❌ Error sending FCM token: $e');
      // Save token locally for retry
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_fcm_token', fcmToken);
    }
  }

  // Retry sending pending token (call after login)
  static Future<void> retryPendingToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingToken = prefs.getString('pending_fcm_token');

      if (pendingToken != null) {
        debugPrint('🔄 Retrying pending FCM token...');
        await _sendTokenToBackend(pendingToken);
      }
    } catch (e) {
      debugPrint('❌ Error retrying pending token: $e');
    }
  }
}

/// =====================================================
///  Firebase Background Notification Handler
/// Must be top-level function (not inside a class)
/// =====================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint("📩 Background message received: ${message.notification?.title}");

    // Show local notification for background messages
    if (message.notification != null) {
      await NotificationService.showNotification(
        title: message.notification!.title ?? 'Notification',
        body: message.notification!.body ?? '',
        data: message.data,
      );
    }
  } catch (e) {
    debugPrint("⚠️ Background message handler error: $e");
  }
}

/// =====================================================
/// 🚀 MAIN ENTRY POINT
/// =====================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    debugPrint('🚀 ========== APP INITIALIZATION START ==========');

    // ✅ Step 1: Load environment variables
    debugPrint('📂 Loading environment variables...');
    await dotenv.load(fileName: ".env");
    await EnvConfig.load();

    if (!EnvConfig.validate()) {
      debugPrint("⚠️ Warning: Some environment variables are missing!");
    }

    EnvConfig.printConfig();
    debugPrint('✅ Environment configuration loaded');

    // ✅ Step 2: Initialize Firebase
    debugPrint('🔥 Initializing Firebase...');
    try {
      await Firebase.initializeApp();
      debugPrint('✅ Firebase initialized successfully');

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      debugPrint('✅ Firebase background handler registered');
    } catch (firebaseError) {
      debugPrint('⚠️ Firebase initialization failed: $firebaseError');
      debugPrint('ℹ️ App will continue without Firebase push notifications');
    }

    // ✅ Step 3: Initialize FCM Service (iOS token handling)
    debugPrint('📲 Initializing FCM service for iOS...');
    try {
      await FCMService.initialize();
      debugPrint('✅ FCM service initialized');
    } catch (fcmError) {
      debugPrint('⚠️ FCM service initialization failed: $fcmError');
    }

    // ✅ Step 4: Initialize Notification Service
    debugPrint('🔔 Initializing notification service...');
    await NotificationService.initialize();
    debugPrint('✅ Notification service initialized');

    // ✅ Step 5: Initialize Connectivity Service
    debugPrint('🌐 Initializing connectivity service...');
    await ConnectivityService().initialize();
    debugPrint('✅ Connectivity service initialized');

    // ✅ Step 6: Initialize App Lifecycle Service
    debugPrint('🔄 Initializing lifecycle service...');
    AppLifecycleService().initialize();
    debugPrint('✅ Lifecycle service initialized');

    debugPrint('🚀 ========== APP INITIALIZATION COMPLETE ==========\n');

    // ✅ Step 7: Launch app with Splash Screen
    runApp(const MyApp());
  } catch (error) {
    debugPrint('❌ ========== FATAL INITIALIZATION ERROR ==========');
    debugPrint('❌ Error: $error');
    debugPrint('❌ App may not function correctly');
    debugPrint('❌ ================================================\n');

    // Run app anyway
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
    // ✅ Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    debugPrint('✅ App lifecycle observer registered');
  }

  @override
  void dispose() {
    // ✅ Unregister lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    debugPrint('🗑️ App lifecycle observer removed');
    super.dispose();
  }

  /// =====================================================
  /// 🔄 App Lifecycle Management (PIN Lock on Resume)
  /// =====================================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    debugPrint('📱 App lifecycle state changed: $state');

    // ✅ Only check on RESUMED (when coming back to app)
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔓 App resumed - checking if PIN required...');

      // Check if enough time has passed to require PIN
      final shouldLock = await AppLifecycleService().shouldRequirePin();

      if (shouldLock) {
        // Check if user has PIN set
        final hasPinSet = await _pinService.hasPinSet();

        if (hasPinSet) {
          final prefs = await SharedPreferences.getInstance();
          final vehicleId = prefs.getInt('current_vehicle_id');

          if (vehicleId != null) {
            debugPrint('🔐 Showing PIN screen...');

            // Show PIN screen
            NotificationService.navigatorKey.currentState?.pushNamedAndRemoveUntil(
              '/pin-entry',
                  (route) => false,
              arguments: vehicleId,
            );
          } else {
            debugPrint('⚠️ No vehicle ID stored');
          }
        } else {
          debugPrint('ℹ️ No PIN set - user can continue');
        }
      } else {
        debugPrint('✅ PIN not required - user returned quickly');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PROXYM TRACKING',
      debugShowCheckedModeBanner: false,

      // ✅ CRITICAL: Use NotificationService's navigator key for notification navigation
      navigatorKey: NotificationService.navigatorKey,

      // ✅ Material 3 Theme with PROXYM Blue
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Color(0xFF3B82F6), // PROXYM blue
          brightness: Brightness.light,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF3B82F6),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),

      // ✅ Start with Splash Screen
      home: const SplashScreen(),

      /// =====================================================
      /// 🛣️ Route Management
      /// =====================================================
      onGenerateRoute: (settings) {
        debugPrint('📍 Navigating to: ${settings.name}');

        switch (settings.name) {
        // ============================================
        // Splash & Authentication Routes
        // ============================================
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

        // ============================================
        // Main App Routes
        // ============================================
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
              return _errorRoute("❌ Missing vehicleId for Profile Screen");
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => ProfileScreen(vehicleId: vehicleId),
            );

          case '/change-password':
            final args = settings.arguments as Map<String, dynamic>?;
            if (args == null || args['phone'] == null || args['userId'] == null) {
              return _errorRoute("❌ Missing phone or userId for Change Password");
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
              return _errorRoute("❌ Missing vehicleId for Settings Screen");
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

        // ============================================
        // Tracking & Map Routes
        // ============================================
          case '/track':
            final vehicleId = settings.arguments as int?;
            if (vehicleId == null) {
              return _errorRoute("❌ Missing vehicleId for Tracking Screen");
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => VehicleTrackingMap(vehicleId: vehicleId),
            );

          case '/trip-map':
            final args = settings.arguments as Map<String, dynamic>?;
            if (args == null || args['tripId'] == null || args['vehicleId'] == null) {
              return _errorRoute("❌ Missing tripId or vehicleId for Trip Map");
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => TripMapScreen(
                tripId: args['tripId'],
                vehicleId: args['vehicleId'],
              ),
            );

        // ============================================
        // Trip Routes
        // ============================================
          case '/trips':
            final vehicleId = settings.arguments as int?;
            if (vehicleId == null) {
              return _errorRoute("❌ Missing vehicleId for Trips Screen");
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => TripsScreen(vehicleId: vehicleId),
            );

        // ============================================
        // Notification Routes
        // ============================================
          case '/notifications':
            final args = settings.arguments as Map<String, dynamic>?;
            final int? vehicleId = args?['vehicleId'];

            if (vehicleId == null) {
              return _errorRoute("❌ Missing vehicleId for Notification Screen");
            }

            return MaterialPageRoute(
              settings: settings,
              builder: (_) => NotificationScreen(vehicleId: vehicleId),
            );

        // ============================================
        // PIN Lock Screen Route
        // ============================================
          case '/pin-entry':
            final vehicleId = settings.arguments as int?;
            if (vehicleId == null) {
              return _errorRoute("❌ Missing vehicleId for PIN Entry");
            }
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => PinEntryScreen(vehicleId: vehicleId),
            );

        // ============================================
        // Error Route (Unknown Route)
        // ============================================
          default:
            return _errorRoute("❌ Route not found: ${settings.name}");
        }
      },
    );
  }

  /// ✅ Helper method for error pages
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
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                SizedBox(height: 24),
                Text(
                  'Navigation Error',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed('/splash');
                  },
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