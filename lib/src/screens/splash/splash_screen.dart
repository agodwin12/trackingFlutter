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
  late final AnimationController _logoCtrl;
  late final AnimationController _textCtrl;
  late final AnimationController _floatCtrl;
  late final AnimationController _shimmerCtrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoRotate;
  late final Animation<double> _floatY;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _textFade;
  late final Animation<double> _shimmer;

  bool _animationDone = false;
  VoidCallback? _pendingNavigation;

  static const int _minSplashMs = 2800;

  String get baseUrl => EnvConfig.baseUrl;

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

  Future<void> _checkSessionAndNavigate() async {
    final start = DateTime.now();

    try {
      final prefs = await SharedPreferences.getInstance();

      final accessToken = prefs.getString('accessToken');
      final refreshToken = prefs.getString('refreshToken');
      final clientId = prefs.getString('client_id');
      final userData = prefs.getString('user');

      if (refreshToken == null ||
          refreshToken.isEmpty ||
          clientId == null ||
          clientId.isEmpty ||
          userData == null ||
          userData.isEmpty) {
        await _waitRemaining(start);
        _scheduleNavigation(_navigateToLogin);
        return;
      }

      Map<String, dynamic> user;
      try {
        user = jsonDecode(userData) as Map<String, dynamic>;
      } catch (_) {
        await _clearBrokenSessionOnly();
        await _waitRemaining(start);
        _scheduleNavigation(_navigateToLogin);
        return;
      }

      final int? userId = _safeUserId(user);
      if (userId == null) {
        await _clearBrokenSessionOnly();
        await _waitRemaining(start);
        _scheduleNavigation(_navigateToLogin);
        return;
      }

      try {
        await NotificationService.registerToken();
      } catch (_) {}

      final String appType = prefs.getString('app_type') ?? 'tracking';

      String? validToken = accessToken;

      try {
        validToken = await TokenRefreshService().getValidAccessToken();
      } catch (_) {
        validToken = accessToken;
      }

      await _waitRemaining(start);

      if (TokenRefreshService().sessionExpired) {
        return;
      }

      if (appType == 'recouvrement') {
        await _restoreRecouvrementSession(
          user: user,
          token: validToken ?? accessToken ?? '',
          prefs: prefs,
        );
        return;
      }

      await _validateTrackingSessionAndNavigate(userId);
    } catch (_) {
      await _waitRemaining(start);
      if (!TokenRefreshService().sessionExpired) {
        await _navigateUsingCacheOrLogin();
      }
    }
  }

  int? _safeUserId(Map<String, dynamic> user) {
    try {
      final raw = user['id'];
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw);
    } catch (_) {}
    return null;
  }

  Future<void> _waitRemaining(DateTime start) async {
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    final remaining = _minSplashMs - elapsed;
    if (remaining > 0) {
      await Future.delayed(Duration(milliseconds: remaining));
    }
  }

  Future<void> _restoreRecouvrementSession({
    required Map<String, dynamic> user,
    required String token,
    required SharedPreferences prefs,
  }) async {
    final rolesRaw = prefs.getString('roles');
    List<String> roles = [];

    if (rolesRaw != null && rolesRaw.isNotEmpty) {
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

  Future<void> _validateTrackingSessionAndNavigate(int userId) async {
    try {
      final response = await TokenRefreshService().makeAuthenticatedRequest(
        request: (token) => http
            .get(
          Uri.parse('$baseUrl/voitures/user/$userId'),
          headers: {
            'Authorization': 'Bearer $token',
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
          await _cacheVehicles(vehicles);
          final int firstVehicleId = (vehicles[0]['id'] as num).toInt();
          _scheduleNavigation(() => _goToDashboard(firstVehicleId));
          return;
        }

        await _navigateUsingCacheOrLogin();
        return;
      }

      await _handleTransientFailure();
    } catch (_) {
      await _handleTransientFailure();
    }
  }

  Future<void> _handleTransientFailure() async {
    if (TokenRefreshService().sessionExpired) return;
    await _navigateUsingCacheOrLogin();
  }

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
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        if (list.isNotEmpty) {
          final first = list.first as Map<String, dynamic>;
          final id = first['id'];
          if (id is num) return id.toInt();
          if (id is String) return int.tryParse(id);
        }
      }
    } catch (_) {}

    return null;
  }

  Future<void> _cacheVehicles(List vehicles) async {
    if (vehicles.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('vehicles_list', jsonEncode(vehicles));

      final int firstVehicleId = (vehicles[0]['id'] as num).toInt();
      await prefs.setInt('current_vehicle_id', firstVehicleId);

      final firstVehicle = vehicles[0] as Map<String, dynamic>;
      final String firstName =
      (firstVehicle['nickname'] as String?)?.isNotEmpty == true
          ? firstVehicle['nickname'] as String
          : '${firstVehicle['marque'] ?? ''} ${firstVehicle['model'] ?? ''}'
          .trim();

      if (firstName.isNotEmpty) {
        await prefs.setString('current_vehicle_name', firstName);
      }
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
    if (_animationDone) {
      navigate();
    }
  }

  Future<void> _clearBrokenSessionOnly() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('accessToken');
    await prefs.remove('auth_token');
    await prefs.remove('refreshToken');
    await prefs.remove('client_id');
    await prefs.remove('user');
    await prefs.remove('vehicles_list');
    await prefs.remove('current_vehicle_id');
    await prefs.remove('current_vehicle_name');
    await prefs.remove('user_id');
    await prefs.remove('user_phone');
    await prefs.remove('app_type');
    await prefs.remove('roles');
  }

  void _navigateToLogin() {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ModernLoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final logoSize = screenWidth * 0.18;
    final fontSize = screenWidth * 0.09;

    return Scaffold(
      backgroundColor: kSplashBg,
      body: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
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