// lib/src/screens/login/login_screen.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';
import '../../services/notification_service.dart';
import '../change password/change_password.dart';
import '../dashboard/dashboard.dart';
import '../forgot_password/forgot_password.dart';
import '../../../main.dart' show FCMService;

class Country {
  final String name;
  final String code;
  final String flag;

  Country({required this.name, required this.code, required this.flag});
}

class ModernLoginScreen extends StatefulWidget {
  @override
  _ModernLoginScreenState createState() => _ModernLoginScreenState();
}

class _ModernLoginScreenState extends State<ModernLoginScreen>
    with TickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;

  late AnimationController _animationController;
  late AnimationController _floatingController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  String get baseUrl => EnvConfig.baseUrl;

  static const Color fleetraOrange = Color(0xFFFF6B35);
  static const Color fleetraBlack = Color(0xFF1A1A1A);
  static const Color fleetraGradientStart = Color(0xFFFF8A5B);
  static const Color fleetraGradientEnd = Color(0xFFFF6B35);

  final List<Country> _centralAfricanCountries = [
    Country(name: 'Cameroon', code: '+237', flag: '🇨🇲'),
    Country(name: 'Nigeria', code: '+234', flag: '🇳🇬'),
    Country(name: 'Togo', code: '+228', flag: '🇹🇬'),
    Country(name: 'Central African Republic', code: '+236', flag: '🇨🇫'),
    Country(name: 'Chad', code: '+235', flag: '🇹🇩'),
    Country(name: 'Republic of the Congo', code: '+242', flag: '🇨🇬'),
    Country(name: 'Democratic Republic of the Congo', code: '+243', flag: '🇨🇩'),
    Country(name: 'Equatorial Guinea', code: '+240', flag: '🇬🇶'),
    Country(name: 'Gabon', code: '+241', flag: '🇬🇦'),
    Country(name: 'São Tomé and Príncipe', code: '+239', flag: '🇸🇹'),
    Country(name: 'Angola', code: '+244', flag: '🇦🇴'),
    Country(name: 'Burundi', code: '+257', flag: '🇧🇮'),
    Country(name: 'Rwanda', code: '+250', flag: '🇷🇼'),
  ];

  Country _selectedCountry =
  Country(name: 'Cameroon', code: '+237', flag: '🇨🇲');

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _floatingController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _floatingController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() async {
    if (_phoneController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      _showErrorSnackbar("Phone and Password are required");
      return;
    }

    setState(() => _isLoading = true);

    final String phoneWithCountryCode =
        _selectedCountry.code + _phoneController.text.trim();
    final String password = _passwordController.text.trim();
    final Uri url = Uri.parse("$baseUrl/auth/login");

    try {
      debugPrint('\n🔐 ==========================================');
      debugPrint('🔐 LOGIN ATTEMPT STARTED');
      debugPrint('🔐 Phone: $phoneWithCountryCode');
      debugPrint('🔐 Backend URL: $url');
      debugPrint('🔐 ==========================================');

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": phoneWithCountryCode,
          "password": password,
          "keepMeLoggedIn": _rememberMe,
        }),
      );

      final responseData = jsonDecode(response.body);
      debugPrint('🔐 Response status: ${response.statusCode}');

      // ✅ SUCCESS
      if (response.statusCode == 200) {
        debugPrint('✅ LOGIN SUCCESSFUL');

        final SharedPreferences prefs = await SharedPreferences.getInstance();

        // ── Save tokens ──────────────────────────────────────────
        await prefs.setString("accessToken", responseData["accessToken"]);
        await prefs.setString("auth_token", responseData["accessToken"]);
        await prefs.setString("user", jsonEncode(responseData["user"]));
        debugPrint('💾 Access token saved');

        if (responseData["refreshToken"] != null) {
          await prefs.setString("refreshToken", responseData["refreshToken"]);
          debugPrint('💾 Refresh token saved');
        }

        // ── Save user info ───────────────────────────────────────
        final int userId = responseData["user"]["id"];
        await prefs.setInt("user_id", userId);
        debugPrint('💾 User ID saved: $userId');

        // ── Save user_type (regular or chauffeur) ────────────────
        final String userType = responseData["user_type"] ?? "regular";
        await prefs.setString("user_type", userType);
        debugPrint('💾 User type saved: $userType');

        // ── Save partner_id if present ───────────────────────────
        if (responseData["user"]["partner_id"] != null) {
          await prefs.setInt(
              "partner_id", responseData["user"]["partner_id"]);
          debugPrint(
              '💾 Partner ID saved: ${responseData["user"]["partner_id"]}');
        }

        // ── Read vehicles from login response ────────────────────
        final List vehicles = responseData["vehicles"] ?? [];
        debugPrint('🚗 Vehicles from login response: ${vehicles.length}');

        if (vehicles.isEmpty) {
          setState(() => _isLoading = false);
          _showErrorSnackbar("No vehicles found for this account");
          return;
        }

        // ── Save full vehicles list to SharedPreferences ─────────
        // ✅ KEY FIX: dashboard_controller reads from here for BOTH
        // regular users and chauffeurs. Without this, chauffeur users
        // get a white screen because the API endpoint /voitures/user/:id
        // does not support chauffeur accounts.
        await prefs.setString('vehicles_list', jsonEncode(vehicles));
        debugPrint('💾 Vehicles list saved (${vehicles.length} vehicles)');

        // ── Save first vehicle ID ────────────────────────────────
        final int firstVehicleId = vehicles[0]["id"];
        await prefs.setInt('current_vehicle_id', firstVehicleId);
        debugPrint('💾 Current vehicle ID saved: $firstVehicleId');

        // ── Register notification token ──────────────────────────
        debugPrint('\n📲 REGISTERING NOTIFICATION TOKEN');
        try {
          await NotificationService.registerToken();
          debugPrint('✅ Notification token registration completed');
        } catch (notifError) {
          debugPrint('⚠️ Notification registration error: $notifError');
        }

        // ── Retry pending FCM token ──────────────────────────────
        debugPrint('\n🔄 RETRYING PENDING FCM TOKEN');
        try {
          await FCMService.retryPendingToken();
          debugPrint('✅ FCM token retry completed');
        } catch (fcmError) {
          debugPrint('⚠️ FCM token retry failed: $fcmError');
        }

        // ── Check first login ────────────────────────────────────
        final bool isFirstLogin = responseData["isFirstLogin"] ?? false;
        debugPrint('🔐 First login: $isFirstLogin');

        setState(() => _isLoading = false);

        if (!mounted) return;

        // ── First login → password reset screen ─────────────────
        if (isFirstLogin) {
          debugPrint('🔑 FIRST LOGIN → navigating to password reset');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ResetPasswordScreen(
                userId: userId,
                isFirstLogin: true,
              ),
            ),
          );
          return;
        }

        // ── Navigate to dashboard ────────────────────────────────
        debugPrint('\n🎯 NAVIGATING TO DASHBOARD');
        debugPrint('🎯 Vehicle ID: $firstVehicleId | User type: $userType');

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ModernDashboard(
              vehicleId: firstVehicleId,
            ),
          ),
        );
      } else {
        // ✅ FAILURE
        setState(() => _isLoading = false);

        debugPrint('❌ LOGIN FAILED — Status: ${response.statusCode}');
        debugPrint('❌ Response: ${response.body}');

        String errorMessage = "Login failed";

        if (responseData["errors"] != null && responseData["errors"] is List) {
          final List errors = responseData["errors"];
          if (errors.isNotEmpty) {
            errorMessage =
                errors[0]["msg"] ?? errors[0]["message"] ?? errorMessage;
          }
        } else if (responseData["message"] != null) {
          errorMessage = responseData["message"];
        }

        _showErrorSnackbar(errorMessage);
      }
    } catch (error, stackTrace) {
      setState(() => _isLoading = false);
      debugPrint('❌ LOGIN EXCEPTION: $error');
      debugPrint('❌ Stack: $stackTrace');
      _showErrorSnackbar("Connection error. Please try again.");
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFE53935),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select Country',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: fleetraBlack,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.grey[600],
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey[200]),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _centralAfricanCountries.length,
                  itemBuilder: (context, index) {
                    final country = _centralAfricanCountries[index];
                    final isSelected = country.code == _selectedCountry.code;

                    return InkWell(
                      onTap: () {
                        setState(() => _selectedCountry = country);
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? fleetraOrange.withOpacity(0.1)
                              : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            Text(
                              country.flag,
                              style: const TextStyle(fontSize: 32),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    country.name,
                                    style: TextStyle(
                                      color: isSelected
                                          ? fleetraOrange
                                          : fleetraBlack,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    country.code,
                                    style: TextStyle(
                                      color: isSelected
                                          ? fleetraOrange
                                          : Colors.grey[600],
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: fleetraOrange,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFF5F0),
              Color(0xFFFFFFFF),
              Color(0xFFFFF8F5),
            ],
          ),
        ),
        child: Stack(
          children: [
            _buildFloatingPins(),
            SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: _buildLogoSection(),
                        ),
                      ),
                      const SizedBox(height: 60),
                      SlideTransition(
                        position: _slideAnimation,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: _buildLoginCard(),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
              top: 100 + (_floatingController.value * 30),
              right: 40,
              child: _buildLocationPin(size: 40, opacity: 0.15),
            ),
            Positioned(
              top: 250 + (_floatingController.value * -25),
              left: 30,
              child: _buildLocationPin(size: 35, opacity: 0.1),
            ),
            Positioned(
              bottom: 200 + (_floatingController.value * 20),
              right: 60,
              child: _buildLocationPin(size: 30, opacity: 0.12),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: 0.05,
                child: CustomPaint(
                  size: const Size(double.infinity, 300),
                  painter: GridPainter(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLocationPin({required double size, required double opacity}) {
    return Opacity(
      opacity: opacity,
      child: Icon(Icons.location_on_rounded, size: size, color: fleetraOrange),
    );
  }

  Widget _buildLogoSection() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: fleetraOrange.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/logo.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [fleetraGradientStart, fleetraGradientEnd],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.gps_fixed_rounded,
                    size: 50,
                    color: Colors.white,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'FLEETRA',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: fleetraOrange,
            letterSpacing: 1.5,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: 'by ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey[600],
                  letterSpacing: 0.5,
                ),
              ),
              const TextSpan(
                text: 'PROXYM ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: fleetraBlack,
                  letterSpacing: 0.5,
                ),
              ),
              const TextSpan(
                text: 'GROUP',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: fleetraOrange,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: fleetraOrange.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome Back',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: fleetraBlack,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to track your vehicle',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 32),
              _buildModernPhoneField(),
              const SizedBox(height: 20),
              _buildModernPasswordField(),
              const SizedBox(height: 16),
              _buildOptionsRow(),
              const SizedBox(height: 28),
              _buildModernLoginButton(),
              const SizedBox(height: 20),
              _buildCopyrightFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Phone Number',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: fleetraBlack,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!, width: 1.5),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: _showCountryPicker,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 18),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                          color: Colors.grey[200]!, width: 1.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _selectedCountry.flag,
                        style: const TextStyle(fontSize: 22),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _selectedCountry.code,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: fleetraBlack,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down_rounded,
                          color: Colors.grey[600], size: 20),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: fleetraBlack,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '612 345 678',
                      hintStyle: TextStyle(
                        color: Colors.grey[400],
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModernPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Password',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: fleetraBlack,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!, width: 1.5),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 12),
                child: Icon(Icons.lock_outline_rounded,
                    color: fleetraOrange, size: 22),
              ),
              Expanded(
                child: TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: fleetraBlack,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Enter your password',
                    hintStyle: TextStyle(
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: Colors.grey[600],
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOptionsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: _rememberMe,
                onChanged: (value) =>
                    setState(() => _rememberMe = value ?? false),
                activeColor: fleetraOrange,
                checkColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                side: BorderSide(color: Colors.grey[300]!, width: 1.5),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Remember me',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => ForgotPasswordScreen()),
          ),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Forgot password?',
            style: TextStyle(
              fontSize: 13,
              color: fleetraOrange,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModernLoginButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [fleetraGradientStart, fleetraGradientEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: fleetraOrange.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor:
            AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        )
            : const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Sign In',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded,
                color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyrightFooter() {
    final currentYear = DateTime.now().year;
    return Center(
      child: Text(
        '© $currentYear All rights reserved to PROXYM GROUP',
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey[500],
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// Custom Painter for GPS Grid Background
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF6B35).withOpacity(0.1)
      ..strokeWidth = 1;

    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}