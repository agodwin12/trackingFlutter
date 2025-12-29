import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:tracking/src/screens/change%20password%20in%20app/change_password.dart';
import 'package:tracking/src/screens/login/login.dart';

// Screens
import 'package:tracking/src/screens/splash/splash_screen.dart'; // ✅ NEW
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

/// =====================================================
/// 🔥 Firebase Background Notification Handler
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

    // ✅ Step 3: Initialize Notification Service
    debugPrint('🔔 Initializing notification service...');
    await NotificationService.initialize();
    debugPrint('✅ Notification service initialized');

    debugPrint('🚀 ========== APP INITIALIZATION COMPLETE ==========\n');

    // ✅ Step 4: Launch app with Splash Screen
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
  bool _isAppInBackground = false;

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

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      // App is going to background
        _isAppInBackground = true;
        debugPrint('🔒 App moved to background');
        break;

      case AppLifecycleState.resumed:
      // App is coming back to foreground
        if (_isAppInBackground) {
          debugPrint('✅ App resumed from background');
          _isAppInBackground = false;

          // Check if user has PIN set
          final hasPinSet = await _pinService.hasPinSet();

          if (hasPinSet) {
            // Get stored vehicle ID
            final prefs = await SharedPreferences.getInstance();
            final vehicleId = prefs.getInt('current_vehicle_id');

            if (vehicleId != null) {
              debugPrint('🔐 PIN required - navigating to PIN entry screen');

              // Navigate to PIN entry screen
              NotificationService.navigatorKey.currentState?.pushNamedAndRemoveUntil(
                '/pin-entry',
                    (route) => false,
                arguments: vehicleId,
              );
            } else {
              debugPrint('⚠️ No vehicle ID stored - user may need to login again');
            }
          } else {
            debugPrint('ℹ️ No PIN set - user can continue without PIN');
          }
        }
        break;

      case AppLifecycleState.detached:
        debugPrint('❌ App is being terminated');
        break;

      case AppLifecycleState.hidden:
        debugPrint('👁️ App is hidden');
        break;
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