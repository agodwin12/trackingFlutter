// lib/src/screens/splash/splash_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';
import '../../services/notification_service.dart'; // ✅ ADDED
import '../dashboard/dashboard.dart';
import '../login/login.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _carAnimation;
  late Animation<double> _fadeAnimation;

  String get baseUrl => EnvConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _checkSessionAndNavigate();
  }

  void _setupAnimations() {
    // Animation controller for 5 seconds
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2000), // 2 seconds
      vsync: this,
    );

    // Car moves from left to right (0.0 to 1.0)
    _carAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    // Fade in animation for text
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    // Start animation
    _animationController.forward();
  }

  Future<void> _checkSessionAndNavigate() async {
    // Wait for animation to complete (2 seconds)
    await Future.delayed(const Duration(milliseconds: 2000));

    if (!mounted) return;

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString("accessToken");
      String? userData = prefs.getString("user");

      // If no session, go to login
      if (token == null || token.isEmpty || userData == null) {
        _navigateToLogin();
        return;
      }

      // ✅ CRITICAL FIX: Register FCM token for logged-in users
      debugPrint('📱 Registering FCM token for already logged-in user...');
      await NotificationService.registerToken();
      debugPrint('✅ FCM token registered on app startup');

      // Session exists - fetch vehicles and navigate to dashboard
      Map<String, dynamic> user = jsonDecode(userData);
      int userId = user["id"];

      final response = await http.get(
        Uri.parse("$baseUrl/voitures/user/$userId"),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List vehicles = data["vehicles"];

        if (vehicles.isNotEmpty && mounted) {
          int firstVehicleId = vehicles[0]["id"];

          debugPrint('✅ Session valid - Navigating to dashboard with vehicle: $firstVehicleId');

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ModernDashboard(vehicleId: firstVehicleId),
            ),
          );
        } else {
          // No vehicles found - clear session and go to login
          await prefs.clear();
          _navigateToLogin();
        }
      } else {
        // Invalid session - clear and go to login
        await prefs.clear();
        _navigateToLogin();
      }
    } catch (error) {
      debugPrint("❌ Session check error: $error");
      // On error, go to login
      _navigateToLogin();
    }
  }

  void _navigateToLogin() {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ModernLoginScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppColors.white,
      body: Stack(
        children: [
          // Center content - Logo text (SINGLE LINE)
          Positioned(
            top: screenHeight * 0.35,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // PROXYM TRACKING Text (SINGLE LINE)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingL),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'PROXYM ',
                              style: AppTypography.tesla(
                                fontSize: 40,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary, // Orange/Primary color
                              ),
                            ),
                            TextSpan(
                              text: 'TRACKING',
                              style: AppTypography.tesla(
                                fontSize: 40,
                                fontWeight: FontWeight.w900,
                                color: AppColors.black, // Black color
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: AppSizes.spacingL),

                  // Tagline
                  Text(
                    'Track your vehicle anywhere',
                    style: AppTypography.body1.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Road and Car Animation
          Positioned(
            bottom: screenHeight * 0.25,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  // Road container
                  Container(
                    height: 100,
                    margin: EdgeInsets.symmetric(horizontal: AppSizes.spacingXL),
                    decoration: BoxDecoration(
                      color: AppColors.border.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(AppSizes.radiusL),
                    ),
                    child: Stack(
                      children: [
                        // Road lines (dashed)
                        Center(
                          child: Container(
                            height: 3,
                            margin: EdgeInsets.symmetric(horizontal: AppSizes.spacingM),
                            child: CustomPaint(
                              painter: DashedLinePainter(
                                color: AppColors.border,
                                dashWidth: 20,
                                dashSpace: 10,
                              ),
                            ),
                          ),
                        ),

                        // Animated car on the road
                        AnimatedBuilder(
                          animation: _carAnimation,
                          builder: (context, child) {
                            final carWidth = 80.0;
                            final roadWidth = screenWidth - (AppSizes.spacingXL * 2) - carWidth;
                            final carPosition = _carAnimation.value * roadWidth;

                            return Positioned(
                              left: carPosition + AppSizes.spacingM,
                              top: 25,
                              child: Container(
                                padding: EdgeInsets.all(AppSizes.spacingM),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.3),
                                      blurRadius: 15,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.directions_car_rounded,
                                  size: 40,
                                  color: AppColors.primary,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: AppSizes.spacingL),

                  // Loading text
                  Text(
                    'Loading...',
                    style: AppTypography.body2.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Copyright footer
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Center(
                child: Text(
                  '© ${DateTime.now().year} PROXYM GROUP',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for dashed road lines
class DashedLinePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double dashSpace;

  DashedLinePainter({
    required this.color,
    this.dashWidth = 10,
    this.dashSpace = 5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(startX + dashWidth, 0),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
