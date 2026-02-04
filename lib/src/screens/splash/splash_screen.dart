// lib/src/screens/splash/splash_screen.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';
import '../../services/notification_service.dart';
import '../dashboard/dashboard.dart';
import '../login/login.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _floatingController;
  late AnimationController _pulseController;
  late AnimationController _rotationController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _slideUpAnimation;
  late Animation<double> _logoRotation;
  late Animation<double> _pulseAnimation;

  String get baseUrl => EnvConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _checkSessionAndNavigate();
  }

  void _setupAnimations() {
    _mainController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    _floatingController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.1, 0.5, curve: Curves.elasticOut),
      ),
    );

    _slideUpAnimation = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.3, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    _logoRotation = Tween<double>(begin: 0.0, end: 2 * math.pi).animate(
      _rotationController,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // Start main animation
    _mainController.forward();
  }

  // ✅ IMPROVED: Robust session validation with proper error handling
  Future<void> _checkSessionAndNavigate() async {
    try {
      // ✅ Wait for animation to complete properly
      await _mainController.forward();
      await Future.delayed(const Duration(milliseconds: 500)); // Extra buffer

      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("accessToken");
      final userData = prefs.getString("user");

      debugPrint('🔍 Session Check: token=${token != null}, userData=${userData != null}');

      // ✅ STEP 1: Check if session data exists
      if (token == null || token.isEmpty || userData == null || userData.isEmpty) {
        debugPrint('❌ No session found - redirecting to login');
        await Future.delayed(const Duration(milliseconds: 300));
        _navigateToLogin();
        return;
      }

      // ✅ STEP 2: Parse user data
      Map<String, dynamic> user;
      try {
        user = jsonDecode(userData);
      } catch (e) {
        debugPrint('❌ Invalid user data format - clearing session');
        await _clearSession();
        _navigateToLogin();
        return;
      }

      // ✅ STEP 3: Validate user data structure
      if (!user.containsKey('id') || user['id'] == null) {
        debugPrint('❌ User ID missing - clearing session');
        await _clearSession();
        _navigateToLogin();
        return;
      }

      final int userId = user["id"];
      debugPrint('✅ Valid session found for user ID: $userId');

      // ✅ STEP 4: Register FCM token for logged-in users
      try {
        debugPrint('📱 Registering FCM token...');
        await NotificationService.registerToken();
        debugPrint('✅ FCM token registered successfully');
      } catch (e) {
        debugPrint('⚠️ FCM token registration failed (non-critical): $e');
        // Don't block navigation on FCM failure
      }

      // ✅ STEP 5: Validate session with backend (fetch vehicles)
      await _validateSessionAndNavigate(userId, token);

    } catch (error, stackTrace) {
      debugPrint("❌ Critical error during session check: $error");
      debugPrint("Stack trace: $stackTrace");

      // On critical error, go to login but keep session data
      // (might be temporary network issue)
      if (mounted) {
        _navigateToLogin();
      }
    }
  }

  // ✅ NEW: Validate session with backend and navigate
  Future<void> _validateSessionAndNavigate(int userId, String token) async {
    try {
      debugPrint('🌐 Validating session with backend...');

      final response = await http.get(
        Uri.parse("$baseUrl/voitures/user/$userId"),
        headers: {
          'Authorization': 'Bearer $token', // ✅ Include token in request
          'Content-Type': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 10), // ✅ Increased timeout
        onTimeout: () {
          throw TimeoutException('Request timed out after 10 seconds');
        },
      );

      if (!mounted) return;

      debugPrint('📡 Backend response: ${response.statusCode}');

      // ✅ CASE 1: Successful response (200)
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List vehicles = data["vehicles"] ?? [];

        debugPrint('✅ Found ${vehicles.length} vehicles');

        if (vehicles.isNotEmpty) {
          final int firstVehicleId = vehicles[0]["id"];
          debugPrint('✅ Session valid - Navigating to dashboard (vehicle: $firstVehicleId)');

          await Future.delayed(const Duration(milliseconds: 300));

          if (mounted) {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    ModernDashboard(vehicleId: firstVehicleId),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
                transitionDuration: const Duration(milliseconds: 500),
              ),
            );
          }
          return;
        } else {
          // No vehicles found - valid session but no vehicles
          debugPrint('⚠️ Valid session but no vehicles - redirecting to login');
          await _clearSession();
          _navigateToLogin();
          return;
        }
      }

      // ✅ CASE 2: Unauthorized (401) - Invalid/Expired token
      else if (response.statusCode == 401) {
        debugPrint('❌ Unauthorized (401) - Token expired or invalid');
        await _clearSession();
        _navigateToLogin();
        return;
      }

      // ✅ CASE 3: Forbidden (403) - Access denied
      else if (response.statusCode == 403) {
        debugPrint('❌ Forbidden (403) - Access denied');
        await _clearSession();
        _navigateToLogin();
        return;
      }

      // ✅ CASE 4: Server error (500+)
      else if (response.statusCode >= 500) {
        debugPrint('⚠️ Server error (${response.statusCode}) - Keeping session, redirecting to login');
        // Don't clear session on server errors
        _navigateToLogin();
        return;
      }

      // ✅ CASE 5: Other errors (404, etc.)
      else {
        debugPrint('⚠️ Unexpected status code: ${response.statusCode}');
        await _clearSession();
        _navigateToLogin();
        return;
      }

    } on TimeoutException catch (e) {
      debugPrint('⏱️ Request timeout: $e');
      // Keep session on timeout, but go to login
      // User can retry login which will use cached credentials
      if (mounted) {
        _navigateToLogin();
      }
    } on http.ClientException catch (e) {
      debugPrint('🌐 Network error: $e');
      // Keep session on network errors
      if (mounted) {
        _navigateToLogin();
      }
    } catch (error) {
      debugPrint('❌ Error validating session: $error');
      // Clear session on unexpected errors (likely malformed response)
      await _clearSession();
      if (mounted) {
        _navigateToLogin();
      }
    }
  }

  // ✅ NEW: Safely clear session data
  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('accessToken');
      await prefs.remove('user');
      debugPrint('🗑️ Session cleared');
    } catch (e) {
      debugPrint('⚠️ Error clearing session: $e');
    }
  }

  void _navigateToLogin() {
    if (!mounted) return;

    debugPrint('🔐 Navigating to login screen');

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ModernLoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _mainController.dispose();
    _floatingController.dispose();
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.background,
        child: Stack(
          children: [
            _buildAnimatedBackground(),
            _buildGPSRings(),
            _buildFloatingPins(),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildAnimatedLogo(),
                  SizedBox(height: AppSizes.spacingXL + AppSizes.spacingM),
                  _buildBrandName(),
                  SizedBox(height: AppSizes.spacingXL + AppSizes.spacingXL),
                  _buildLoadingIndicator(),
                  SizedBox(height: AppSizes.spacingM),
                  _buildLoadingText(),
                ],
              ),
            ),
            _buildCopyrightFooter(),
          ],
        ),
      ),
    );
  }

  // ✅ Animated Background with Grid
  Widget _buildAnimatedBackground() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _floatingController,
        builder: (context, child) {
          return Opacity(
            opacity: 0.05 + (_floatingController.value * 0.03),
            child: CustomPaint(
              painter: GridPainter(
                animationValue: _floatingController.value,
                primaryColor: AppColors.primary,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGPSRings() {
    return Center(
      child: AnimatedBuilder(
        animation: _rotationController,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: _logoRotation.value,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.1),
                      width: 2,
                    ),
                  ),
                ),
              ),
              Transform.rotate(
                angle: -_logoRotation.value * 1.5,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.15),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              Transform.rotate(
                angle: _logoRotation.value * 2,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFloatingPins() {
    return AnimatedBuilder(
      animation: _floatingController,
      builder: (context, child) {
        return Stack(
          children: [
            Positioned(
              top: 80 + (_floatingController.value * 40),
              right: 50,
              child: _buildLocationPin(size: 45, opacity: 0.2, rotation: _floatingController.value * math.pi / 8),
            ),
            Positioned(
              top: 150 + (_floatingController.value * -30),
              left: 40,
              child: _buildLocationPin(size: 35, opacity: 0.15, rotation: -_floatingController.value * math.pi / 6),
            ),
            Positioned(
              bottom: 180 + (_floatingController.value * 35),
              right: 70,
              child: _buildLocationPin(size: 40, opacity: 0.18, rotation: _floatingController.value * math.pi / 10),
            ),
            Positioned(
              bottom: 250 + (_floatingController.value * -25),
              left: 60,
              child: _buildLocationPin(size: 30, opacity: 0.12, rotation: -_floatingController.value * math.pi / 12),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.4 + (_floatingController.value * 20),
              right: 30,
              child: _buildLocationPin(size: 38, opacity: 0.16, rotation: _floatingController.value * math.pi / 7),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLocationPin({required double size, required double opacity, required double rotation}) {
    return Transform.rotate(
      angle: rotation,
      child: Opacity(
        opacity: opacity,
        child: Icon(Icons.location_on_rounded, size: size, color: AppColors.primary),
      ),
    );
  }

  Widget _buildAnimatedLogo() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.3),
                      AppColors.primary.withOpacity(0.1),
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Container(
                  margin: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.5),
                        blurRadius: 25,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(Icons.gps_fixed_rounded, size: 60, color: AppColors.white);
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBrandName() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: AnimatedBuilder(
        animation: _slideUpAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _slideUpAnimation.value),
            child: Column(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
                  ).createShader(bounds),
                  child: Text(
                    'FLEETRA',
                    style: AppTypography.tesla(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: AppColors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                SizedBox(height: AppSizes.spacingS),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'by ',
                        style: AppTypography.metropolis(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      TextSpan(
                        text: 'PROXYM ',
                        style: AppTypography.metropolis(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.black,
                        ),
                      ),
                      TextSpan(
                        text: 'GROUP',
                        style: AppTypography.metropolis(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: AppSizes.spacingM),
                Text(
                  'Track your vehicle anywhere',
                  style: AppTypography.body2.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        width: 200,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(AppSizes.radiusS / 2),
        ),
        child: AnimatedBuilder(
          animation: _mainController,
          builder: (context, child) {
            return Stack(
              children: [
                Container(
                  width: 200 * _mainController.value,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSizes.radiusS / 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoadingText() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Opacity(
            opacity: 0.4 + (_pulseController.value * 0.4),
            child: Text(
              'Loading...',
              style: AppTypography.body2.copyWith(fontWeight: FontWeight.w600, letterSpacing: 1),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCopyrightFooter() {
    return Positioned(
      bottom: AppSizes.spacingXL + AppSizes.spacingS,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: Text(
            '© ${DateTime.now().year} PROXYM GROUP',
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.5),
          ),
        ),
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  final double animationValue;
  final Color primaryColor;

  GridPainter({required this.animationValue, required this.primaryColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = primaryColor.withOpacity(0.15)
      ..strokeWidth = 1;

    final spacing = 50.0;
    final offset = animationValue * spacing;

    for (double i = -spacing + offset; i < size.width + spacing; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }

    for (double i = -spacing + offset; i < size.height + spacing; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }

    paint.strokeWidth = 0.5;
    paint.color = primaryColor.withOpacity(0.08);

    for (double i = -size.width; i < size.width * 2; i += spacing * 2) {
      canvas.drawLine(
        Offset(i + offset, 0),
        Offset(i + size.height + offset, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(GridPainter oldDelegate) => oldDelegate.animationValue != animationValue;
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  @override
  String toString() => message;
}