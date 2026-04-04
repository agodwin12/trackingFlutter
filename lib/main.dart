// lib/main.dart

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
import 'package:FLEETRA/src/screens/subscriptions/renewal_payment_screen.dart';
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
import 'dart:io' show Platform;

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FCMService
//
// Manages token lifecycle — receiving, deduplicating, persisting, and
// registering with the backend.
//
// Registration always goes through NotificationService._registerTokenWithBackend
// which uses the single correct endpoint:
//   POST /api/notifications/register-token
// with Authorization: Bearer <accessToken>
// ─────────────────────────────────────────────────────────────────────────────
class FCMService {
  static const _iosChannel = MethodChannel('com.proxym.tracking/fcm');

  static bool    _isInitialized      = false;
  static String? _lastProcessedToken;

  static Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('⚠️ FCMService already initialized');
      return;
    }

    try {
      debugPrint('\n📲 FCMService — initializing...');

      // iOS native channel (APNs token arrives here first on iOS)
      if (Platform.isIOS) {
        _iosChannel.setMethodCallHandler((call) async {
          if (call.method == 'onTokenRefresh') {
            await _onTokenReceived(call.arguments as String, 'iOS native');
          }
        });
      }

      // Firebase token refresh (covers both platforms)
      FirebaseMessaging.instance.onTokenRefresh.listen(
            (t) => _onTokenReceived(t, 'Firebase refresh'),
        onError: (e) => debugPrint('❌ FCM onTokenRefresh error: $e'),
      );

      // Try getting the token immediately (may be null on iOS)
      final settings =
      await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        try {
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null) {
            await _onTokenReceived(token, 'initial fetch');
          } else {
            debugPrint('⏳ FCM token not ready yet — listener will catch it');
          }
        } catch (e) {
          if (e.toString().contains('apns-token-not-set')) {
            debugPrint('⏳ APNs token not ready (iOS) — listener will catch it');
          } else {
            debugPrint('⚠️ FCM getToken error: $e');
          }
        }
      }

      _isInitialized = true;
      debugPrint('✅ FCMService initialized');
    } catch (e) {
      debugPrint('❌ FCMService init error: $e');
    }
  }

  // ── Token arrival handler ─────────────────────────────────────────────────
  static Future<void> _onTokenReceived(String token, String source) async {
    // Deduplicate — the same token can arrive from multiple sources
    if (_lastProcessedToken == token) {
      debugPrint('ℹ️ FCM token already processed ($source) — skipping');
      return;
    }
    _lastProcessedToken = token;

    debugPrint('🔑 FCM token received ($source): ${token.substring(0, 30)}...');

    // Always persist locally first
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);

    // Delegate registration to NotificationService — single path, correct endpoint
    await NotificationService.registerToken();
  }

  // ── Called by login screen after a successful login ───────────────────────
  // Retries any token that couldn't be registered before auth was available.
  static Future<void> retryPendingToken() async {
    try {
      final prefs        = await SharedPreferences.getInstance();
      final pendingToken = prefs.getString('pending_fcm_token');

      if (pendingToken == null) {
        debugPrint('ℹ️ FCMService: no pending token to retry');
        return;
      }

      debugPrint('🔄 FCMService: retrying pending token...');
      _lastProcessedToken = null; // allow reprocessing after login
      await _onTokenReceived(pendingToken, 'retry after login');
    } catch (e) {
      debugPrint('❌ FCMService retryPendingToken error: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    debugPrint('\n🚀 APP INITIALIZATION START — ${DateTime.now()}');

    // 1. Environment
    await dotenv.load(fileName: '.env');
    await EnvConfig.load();
    if (!EnvConfig.validate()) {
      debugPrint('⚠️ Some environment variables are missing');
    }

    // 2. Firebase
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    debugPrint('✅ Firebase initialized');

    // 3. FCM Service — sets up token listeners
    await FCMService.initialize();

    // 4. Notification Service — sets up local notifications + message handlers
    await NotificationService.initialize();

    // 5. Connectivity
    await ConnectivityService().initialize();

    // 6. App Lifecycle
    AppLifecycleService().initialize();

    debugPrint('🚀 APP INITIALIZATION COMPLETE\n');
    runApp(const MyApp());
  } catch (e, st) {
    debugPrint('❌ FATAL INIT ERROR: $e\n$st');
    runApp(const MyApp());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP WIDGET
// ─────────────────────────────────────────────────────────────────────────────

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.resumed) return;

    final shouldLock = await AppLifecycleService().shouldRequirePin();
    if (!shouldLock) return;

    final hasPinSet = await _pinService.hasPinSet();
    if (!hasPinSet) return;

    final prefs     = await SharedPreferences.getInstance();
    final vehicleId = prefs.getInt('current_vehicle_id');
    if (vehicleId == null) return;

    NotificationService.navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/pin-entry',
          (route) => false,
      arguments: vehicleId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                    'FLEETRA',
      debugShowCheckedModeBanner: false,
      navigatorKey:             NotificationService.navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme:  ColorScheme.fromSeed(
          seedColor:  const Color(0xFF3B82F6),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF3B82F6),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home:            const SplashScreen(),
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    debugPrint('📍 Route: ${settings.name}');

    switch (settings.name) {
      case '/splash':
        return _route(settings, const SplashScreen());

      case '/login':
        return _route(settings, ModernLoginScreen());

      case '/onboarding':
        return _route(settings, OnboardingScreen());

      case '/dashboard':
        final vehicleId = settings.arguments as int?;
        if (vehicleId == null) return _errorRoute('Missing vehicleId for Dashboard');
        return _route(settings, ModernDashboard(vehicleId: vehicleId));

      case '/profile':
        final vehicleId = settings.arguments as int?;
        if (vehicleId == null) return _errorRoute('Missing vehicleId for Profile');
        return _route(settings, ProfileScreen(vehicleId: vehicleId));

      case '/change-password':
        final args = settings.arguments as Map<String, dynamic>?;
        if (args?['phone'] == null || args?['userId'] == null) {
          return _errorRoute('Missing args for Change Password');
        }
        return _route(
          settings,
          ChangePasswordScreen(
            initialPhone: args!['phone'] as String,
            userId:       args['userId'] as int,
          ),
        );

      case '/settings':
        final vehicleId = settings.arguments as int?;
        if (vehicleId == null) return _errorRoute('Missing vehicleId for Settings');
        return _route(settings, SettingsScreen(vehicleId: vehicleId));

      case '/contact':
        return _route(settings, ContactScreen());

      case '/track':
        final vehicleId = settings.arguments as int?;
        if (vehicleId == null) return _errorRoute('Missing vehicleId for Tracking');
        return _route(settings, VehicleTrackingMap(vehicleId: vehicleId));

      case '/trip-map':
        final args = settings.arguments as Map<String, dynamic>?;
        if (args?['tripId'] == null || args?['vehicleId'] == null) {
          return _errorRoute('Missing args for Trip Map');
        }
        return _route(
          settings,
          TripMapScreen(
            tripId:    args!['tripId'],
            vehicleId: args['vehicleId'],
          ),
        );

      case '/trips':
        final vehicleId = settings.arguments as int?;
        if (vehicleId == null) return _errorRoute('Missing vehicleId for Trips');
        return _route(settings, TripsScreen(vehicleId: vehicleId));

      case '/notifications':
        final args      = settings.arguments as Map<String, dynamic>?;
        final vehicleId = args?['vehicleId'] as int?;
        if (vehicleId == null) return _errorRoute('Missing vehicleId for Notifications');
        return _route(settings, NotificationScreen(vehicleId: vehicleId));

      case '/subscription':
      case '/subscription-plans':
      // Accept both int and Map<String,dynamic> arguments for flexibility
        final args = settings.arguments;
        final int? vehicleId = args is int
            ? args
            : (args is Map<String, dynamic> ? args['vehicleId'] as int? : null);
        if (vehicleId == null) return _errorRoute('Missing vehicleId for Subscription');
        return _route(
          settings,
          SubscriptionPlansScreen(
            vehicleId:    vehicleId,
            vehicleName:  (settings.arguments is Map<String, dynamic>)
                ? (settings.arguments as Map<String, dynamic>)['vehicleName'] as String? ?? ''
                : '',
            onSubscribed: (_) {},
          ),
        );

      case '/pin-entry':
        final vehicleId = settings.arguments as int?;
        if (vehicleId == null) return _errorRoute('Missing vehicleId for PIN Entry');
        return _route(settings, PinEntryScreen(vehicleId: vehicleId));

      default:
        return _errorRoute('Route not found: ${settings.name}');
    }
  }

  MaterialPageRoute<dynamic> _route(RouteSettings s, Widget page) =>
      MaterialPageRoute(settings: s, builder: (_) => page);

  MaterialPageRoute<dynamic> _errorRoute(String message) {
    debugPrint('❌ Route error: $message');
    return MaterialPageRoute(
      builder: (context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Error'),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 24),
                const Text('Navigation Error',
                    style: TextStyle(
                      fontSize:   24,
                      fontWeight: FontWeight.bold,
                      color:      Colors.red,
                    )),
                const SizedBox(height: 16),
                Text(message,
                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                    textAlign: TextAlign.center),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context)
                      .pushReplacementNamed('/splash'),
                  icon:  const Icon(Icons.refresh),
                  label: const Text('Restart App'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
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