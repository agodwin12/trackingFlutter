import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Screens
import 'package:tracking/src/screens/login/login.dart';
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
import 'package:tracking/src/services/biometric_service.dart';

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

    // ✅ Step 3: Initialize Notification Service (handles permissions internally)
    debugPrint('🔔 Initializing notification service...');
    await NotificationService.initialize();
    debugPrint('✅ Notification service initialized');

    // ✅ Step 4: Initialize Biometric Service
    debugPrint('🔐 Initializing biometric service...');
    final biometricService = BiometricService();
    await biometricService.initialize();
    debugPrint('✅ Biometric service initialized');

    // ✅ Step 5: Check onboarding status
    debugPrint('📱 Checking onboarding status...');
    final prefs = await SharedPreferences.getInstance();
    final bool hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;
    debugPrint('✅ Onboarding status: ${hasSeenOnboarding ? "Completed" : "Not completed"}');

    debugPrint('🚀 ========== APP INITIALIZATION COMPLETE ==========\n');

    // ✅ Step 6: Launch app
    runApp(MyApp(hasSeenOnboarding: hasSeenOnboarding));
  } catch (error) {
    debugPrint('❌ ========== FATAL INITIALIZATION ERROR ==========');
    debugPrint('❌ Error: $error');
    debugPrint('❌ App may not function correctly');
    debugPrint('❌ ================================================\n');

    // Run app anyway with default state
    runApp(MyApp(hasSeenOnboarding: false));
  }
}

/// =====================================================
/// 🟦 MAIN APP WIDGET
/// =====================================================
class MyApp extends StatefulWidget {
  final bool hasSeenOnboarding;

  const MyApp({Key? key, required this.hasSeenOnboarding}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final BiometricService _biometricService = BiometricService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _isLocked = false;
  bool _isOnLoginOrOnboarding = true;

  // Route observer to track navigation - initialize inline
  late final _RouteObserver _routeObserver = _RouteObserver(onRouteChanged: _updateRouteStatus);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeBiometrics();

    // Set initial route status based on whether user has seen onboarding
    // If they've seen onboarding, they're on login screen initially
    _isOnLoginOrOnboarding = true;
  }

  Future<void> _initializeBiometrics() async {
    await _biometricService.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    debugPrint('🔄 App lifecycle changed: $state');
    debugPrint('🔍 Current state - isOnLoginOrOnboarding: $_isOnLoginOrOnboarding, isLocked: $_isLocked');

    // ✅ Handle BOTH paused AND inactive as background states
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App went to background
      if (!_isOnLoginOrOnboarding) {
        _biometricService.onAppPaused();
        debugPrint('🔒 App paused/inactive - timer started');
      } else {
        debugPrint('⏭️ Skipping lock - user is on login/onboarding screen');
      }
    } else if (state == AppLifecycleState.resumed) {
      // App came to foreground
      debugPrint('🔓 App resumed');

      if (!_isOnLoginOrOnboarding && !_isLocked) {
        if (_biometricService.shouldAuthenticate()) {
          debugPrint('🔐 Authentication required - showing lock screen');
          _showLockScreen();
        } else {
          debugPrint('✅ No authentication needed');
        }
      } else {
        if (_isOnLoginOrOnboarding) {
          debugPrint('⏭️ Skipping lock - user is on login/onboarding screen');
        }
        if (_isLocked) {
          debugPrint('⏭️ Already locked');
        }
      }
    }
  }

  void _showLockScreen() {
    setState(() {
      _isLocked = true;
    });
  }

  void _onAuthenticated() {
    debugPrint('✅ User authenticated - unlocking app');
    setState(() {
      _isLocked = false;
    });
  }

  void _updateRouteStatus(String? routeName) {
    final wasOnLoginOrOnboarding = _isOnLoginOrOnboarding;

    final newStatus = routeName == '/login' ||
        routeName == '/onboarding' ||
        routeName == null;

    debugPrint('🔍 Route update: $routeName → isOnLoginOrOnboarding: $newStatus');

    if (wasOnLoginOrOnboarding != newStatus) {
      // Defer setState to avoid calling it during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isOnLoginOrOnboarding = newStatus;
          });
          debugPrint('✅ Route status changed: $wasOnLoginOrOnboarding → $_isOnLoginOrOnboarding');

          // If we just moved to a protected screen, reset the timer
          if (!_isOnLoginOrOnboarding) {
            _biometricService.resetTimer();
            debugPrint('🔓 Moved to protected screen - timer reset');
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PROXYM TRACKING',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      navigatorObservers: [_routeObserver],

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

      // ✅ Show lock screen overlay when locked
      builder: (context, child) {
        if (_isLocked) {
          return LockScreen(
            onAuthenticated: _onAuthenticated,
          );
        }
        return child ?? SizedBox.shrink();
      },

      // ✅ Initial route based on onboarding status
      home: widget.hasSeenOnboarding ? ModernLoginScreen() : OnboardingScreen(),

      /// =====================================================
      /// 🛣️ Route Management
      /// =====================================================
      onGenerateRoute: (settings) {
        debugPrint('📍 Navigating to: ${settings.name}');

        // Update login/onboarding status
        _updateRouteStatus(settings.name);

        switch (settings.name) {
        // ============================================
        // Authentication Routes
        // ============================================
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
      builder: (_) => Scaffold(
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
                    Navigator.of(_).pushReplacementNamed('/login');
                  },
                  icon: Icon(Icons.home),
                  label: Text('Go to Login'),
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

/// =====================================================
/// 📍 ROUTE OBSERVER
/// Tracks all route changes including initial route
/// =====================================================
class _RouteObserver extends NavigatorObserver {
  final Function(String?) onRouteChanged;

  _RouteObserver({required this.onRouteChanged});

  void _handleRouteChange(Route? route) {
    if (route != null) {
      final routeName = route.settings.name;
      debugPrint('👀 RouteObserver: Route changed to "$routeName"');
      onRouteChanged(routeName);
    }
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    _handleRouteChange(route);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _handleRouteChange(newRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    _handleRouteChange(previousRoute);
  }
}