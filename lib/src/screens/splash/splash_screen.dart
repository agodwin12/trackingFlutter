// lib/src/screens/splash/splash_screen.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/env_config.dart';
import '../../services/notification_service.dart';
import '../../services/token_refresh_service.dart';
import '../dashboard/dashboard.dart';
import '../login/login.dart';
import '../recouvrement/dashboard/recouvrement_dashboard.dart';

const Color kSplashBg = Colors.black;

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  // ── Animation controllers ──────────────────────────────────────────────
  late final AnimationController _logoCtrl;
  late final AnimationController _textCtrl;
  late final AnimationController _floatCtrl;
  late final AnimationController _shimmerCtrl;

  // ── Animations ─────────────────────────────────────────────────────────
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoRotate;
  late final Animation<double> _floatY;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _textFade;
  late final Animation<double> _shimmer;

  // ── Navigation state ───────────────────────────────────────────────────
  bool _animationDone = false;
  VoidCallback? _pendingNavigation;

  static const int _minSplashMs = 2800;

  String get baseUrl => EnvConfig.baseUrl;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _runAnimationSequence();
    _checkSessionAndNavigate();
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    _floatCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ── Animation setup ────────────────────────────────────────────────────

  void _setupAnimations() {
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoCtrl,
        curve: const Interval(0.0, 0.35, curve: Curves.easeIn),
      ),
    );
    _logoRotate = Tween<double>(begin: -0.25, end: 0.0).animate(
      CurvedAnimation(
        parent: _logoCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _floatY = Tween<double>(begin: -5.0, end: 5.0).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );

    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0.5, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _textCtrl, curve: Curves.easeOutCubic),
    );
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn),
    );

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _shimmer = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut),
    );
  }

  Future<void> _runAnimationSequence() async {
    await _logoCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 60));
    await _textCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 150));
    await _shimmerCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    _animationDone = true;
    _pendingNavigation?.call();
  }

  // ── Session check ──────────────────────────────────────────────────────

  Future<void> _checkSessionAndNavigate() async {
    final start = DateTime.now();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('accessToken');
      final userData = prefs.getString('user');

      if (token == null || token.isEmpty || userData == null || userData.isEmpty) {
        await _waitRemaining(start);
        _scheduleNavigation(_navigateToLogin);
        return;
      }

      Map<String, dynamic> user;
      try {
        user = jsonDecode(userData) as Map<String, dynamic>;
      } catch (_) {
        // Corrupt stored user JSON — this is a genuinely broken session, so
        // clearing here is correct.
        await _clearSession();
        await _waitRemaining(start);
        _scheduleNavigation(_navigateToLogin);
        return;
      }

      final int userId = (user['id'] as num).toInt();
      final String appType = prefs.getString('app_type') ?? 'tracking';

      try {
        await NotificationService.registerToken();
      } catch (_) {}

      await _waitRemaining(start);

      if (appType == 'recouvrement') {
        await _restoreRecouvrementSession(user, token, prefs);
      } else {
        await _validateTrackingSessionAndNavigate(userId, token);
      }
    } catch (_) {
      _scheduleNavigation(_navigateToLogin);
    }
  }

  Future<void> _waitRemaining(DateTime start) async {
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    final remaining = _minSplashMs - elapsed;
    if (remaining > 0) await Future.delayed(Duration(milliseconds: remaining));
  }

  Future<void> _restoreRecouvrementSession(
      Map<String, dynamic> user,
      String token,
      SharedPreferences prefs,
      ) async {
    final rolesRaw = prefs.getString('roles');
    List<String> roles = [];
    if (rolesRaw != null) {
      try {
        roles = (jsonDecode(rolesRaw) as List).map((e) => e.toString()).toList();
      } catch (_) {}
    }
    _scheduleNavigation(() {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RecouvrementDashboard(
            user: user,
            accessToken: token,
            roles: roles,
          ),
        ),
      );
    });
  }

  Future<void> _validateTrackingSessionAndNavigate(
      int userId,
      String token,
      ) async {
    try {
      // Route the validation call through the refresh service so an expired
      // access token (the normal state after >1h idle or a cold restart) is
      // silently refreshed and retried instead of treated as a logout.
      final response = await TokenRefreshService().makeAuthenticatedRequest(
        request: (t) => http
            .get(
          Uri.parse('$baseUrl/voitures/user/$userId'),
          headers: {
            'Authorization': 'Bearer $t',
            'Content-Type': 'application/json',
          },
        )
            .timeout(const Duration(seconds: 10)),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final vehicles = data['vehicles'] as List? ?? [];

        if (vehicles.isNotEmpty) {
          // Fresh data — refresh the cache so future cold starts have a recent
          // vehicle to fall back on, then navigate to the first vehicle.
          await _cacheVehicles(vehicles);
          final int firstVehicleId = (vehicles[0]['id'] as num).toInt();
          _scheduleNavigation(() => _goToDashboard(firstVehicleId));
          return;
        }

        // 200 but empty vehicles → NON-FATAL. This is a data state, not an auth
        // failure, so we never clear the session. Fall back to a cached vehicle
        // if we have one; only land on login if there is nothing to show.
        await _navigateUsingCacheOrLogin();
        return;
      }

      // Any non-200 (e.g. a 401 the refresh service couldn't resolve due to a
      // transient failure, or a 5xx from the endpoint itself). Recover.
      await _handleTransientFailure();
    } catch (_) {
      // makeAuthenticatedRequest threw (no usable token), or the GET failed
      // (network / timeout). Recover gracefully — never clear here.
      await _handleTransientFailure();
    }
  }

  /// Decide what to do when validation couldn't complete cleanly.
  ///
  /// If a genuine session-death logout is already in flight (the refresh
  /// service hit a real 401 / missing local credentials), it has already
  /// cleared prefs and redirected to login via the global navigator key — we
  /// must do nothing here, or we risk a dashboard-vs-login redirect race.
  ///
  /// Otherwise the failure was transient (timeout / 5xx / no signal) and the
  /// session is still intact, so we go optimistic and drop into the dashboard
  /// using cached vehicle data. If that session turns out to be dead, the
  /// dashboard's first authenticated call will 401 and the refresh service
  /// will redirect to login then.
  Future<void> _handleTransientFailure() async {
    if (TokenRefreshService().sessionExpired) return;
    await _navigateUsingCacheOrLogin();
  }

  /// Navigate to the dashboard using a cached vehicle id, or to login if no
  /// cached vehicle exists. Never clears the session — over-eager clearing was
  /// the original cause of the idle/restart sign-outs.
  Future<void> _navigateUsingCacheOrLogin() async {
    final int? vehicleId = await _readCachedVehicleId();
    if (!mounted) return;
    if (vehicleId != null) {
      _scheduleNavigation(() => _goToDashboard(vehicleId));
    } else {
      _scheduleNavigation(_navigateToLogin);
    }
  }

  Future<int?> _readCachedVehicleId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getInt('current_vehicle_id');
      if (cached != null) return cached;

      final raw = prefs.getString('vehicles_list');
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        if (list.isNotEmpty) return (list[0]['id'] as num).toInt();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _cacheVehicles(List vehicles) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('vehicles_list', jsonEncode(vehicles));
      final int firstVehicleId = (vehicles[0]['id'] as num).toInt();
      await prefs.setInt('current_vehicle_id', firstVehicleId);
    } catch (_) {}
  }

  void _goToDashboard(int vehicleId) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ModernDashboard(vehicleId: vehicleId),
      ),
    );
  }

  void _scheduleNavigation(VoidCallback navigate) {
    _pendingNavigation = navigate;
    if (_animationDone) navigate();
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ModernLoginScreen()),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Scale logo and font so it fits any screen width safely
    final logoSize = screenWidth * 0.18;
    final fontSize = screenWidth * 0.09;

    return Scaffold(
      backgroundColor: kSplashBg,
      body: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [

            // ── Animated Logo ────────────────────────────────────────
            AnimatedBuilder(
              animation: Listenable.merge([_logoCtrl, _floatCtrl]),
              builder: (context, child) {
                return Opacity(
                  opacity: _logoFade.value,
                  child: Transform.translate(
                    offset: Offset(0, _floatY.value),
                    child: Transform.rotate(
                      angle: _logoRotate.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: child,
                      ),
                    ),
                  ),
                );
              },
              child: Image.asset(
                'assets/splash.png',
                width: logoSize,
                height: logoSize,
              ),
            ),

            SizedBox(width: screenWidth * 0.04),

            // ── Animated text block ──────────────────────────────────
            ClipRect(
              child: SlideTransition(
                position: _textSlide,
                child: FadeTransition(
                  opacity: _textFade,
                  child: AnimatedBuilder(
                    animation: _shimmer,
                    builder: (context, child) {
                      return ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) {
                          final p = _shimmer.value;
                          return LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: const [
                              Colors.white,
                              Colors.white,
                              Color(0xFFFFE8D6),
                              Colors.white,
                              Colors.white,
                            ],
                            stops: [
                              0.0,
                              (p - 0.25).clamp(0.0, 1.0),
                              p.clamp(0.0, 1.0),
                              (p + 0.25).clamp(0.0, 1.0),
                              1.0,
                            ],
                          ).createShader(bounds);
                        },
                        child: child,
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'FLEETRA',
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: screenWidth * 0.012,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
}