// lib/src/screens/login/login_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';
import '../../services/notification_service.dart';
import '../change password/change_password.dart';
import '../dashboard/dashboard.dart';
import '../debug/debug screen.dart';
import '../forgot_password/forgot_password.dart';

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

class _ModernLoginScreenState extends State<ModernLoginScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // ✅ Get base URL from environment config
  String get baseUrl => EnvConfig.baseUrl;

  // ✅ Central African Countries + Togo + Nigeria
  final List<Country> _centralAfricanCountries = [
    Country(name: 'Cameroon', code: '+237', flag: '🇨🇲'),
    Country(name: 'Nigeria', code: '+234', flag: '🇳🇬'), // ✅ ADDED
    Country(name: 'Togo', code: '+228', flag: '🇹🇬'),    // ✅ ADDED
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

  // Default country is Cameroon
  Country _selectedCountry = Country(name: 'Cameroon', code: '+237', flag: '🇨🇲');

  @override
  void initState() {
    super.initState();

    // Setup animations
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() async {
    if (_phoneController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      _showErrorSnackbar("Phone and Password are required");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Combine country code with phone number
    String phoneWithCountryCode = _selectedCountry.code + _phoneController.text.trim();
    String password = _passwordController.text.trim();

    final Uri url = Uri.parse("$baseUrl/auth/login");

    try {
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

      if (response.statusCode == 200) {
        SharedPreferences prefs = await SharedPreferences.getInstance();

        // ✅ Save all user data
        await prefs.setString("accessToken", responseData["accessToken"]);
        await prefs.setString("user", jsonEncode(responseData["user"]));

        // ✅ NEW: Save refresh token from response
        if (responseData["refreshToken"] != null) {
          await prefs.setString("refreshToken", responseData["refreshToken"]);
          debugPrint('✅ Saved refresh token');
        }

        // 🆕 CRITICAL: Save user_id separately for PIN service
        await prefs.setInt("user_id", responseData["user"]["id"]);

        debugPrint('✅ Login successful - Saved user_id: ${responseData["user"]["id"]}');

        // ✅ Register notification token
        await NotificationService.registerToken();

        // ✅ Check if user needs to change password (first login)
        bool isFirstLogin = responseData["isFirstLogin"] ?? false;

        setState(() {
          _isLoading = false;
        });

        if (mounted) {
          // ✅ If first login, navigate to Reset Password screen
          if (isFirstLogin) {
            debugPrint('🔐 First login detected - navigating to password reset');
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => ResetPasswordScreen(
                  userId: responseData["user"]["id"],
                  isFirstLogin: true,
                ),
              ),
            );
            return;
          }

          // ✅ Otherwise, fetch vehicles and navigate to debug screen then dashboard
          int userId = responseData["user"]["id"];

          final vehiclesResponse = await http.get(
            Uri.parse("$baseUrl/voitures/user/$userId"),
          );

          if (vehiclesResponse.statusCode == 200) {
            final vehiclesData = jsonDecode(vehiclesResponse.body);
            List vehicles = vehiclesData["vehicles"];

            if (vehicles.isNotEmpty) {
              int firstVehicleId = vehicles[0]["id"];

              debugPrint('✅ Navigating to FCM debug screen with vehicle ID: $firstVehicleId');

              // ✅ CHANGED: Navigate to FCM Debug Screen (will auto-redirect to dashboard)
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => FCMDebugScreen(
                    vehicleId: firstVehicleId,
                    userId: userId,
                  ),
                ),
              );
            } else {
              _showErrorSnackbar("No vehicles found for this account");
            }
          }
        }
      } else {
        setState(() {
          _isLoading = false;
        });

        // ✅ IMPROVED ERROR HANDLING - Show backend validation errors
        String errorMessage = "Login failed";

        // Check if there are validation errors from backend
        if (responseData["errors"] != null && responseData["errors"] is List) {
          List errors = responseData["errors"];
          if (errors.isNotEmpty) {
            // Show the first validation error message
            errorMessage = errors[0]["msg"] ?? errors[0]["message"] ?? errorMessage;
          }
        } else if (responseData["message"] != null) {
          errorMessage = responseData["message"];
        }

        _showErrorSnackbar(errorMessage);
      }
    } catch (error) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar("Connection error. Please try again.");
      debugPrint("❌ Login error: $error");
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.white),
            SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Text(
                message,
                style: AppTypography.body1.copyWith(color: AppColors.white),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
        ),
        margin: EdgeInsets.all(AppSizes.spacingM),
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
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(AppSizes.radiusXL),
              topRight: Radius.circular(AppSizes.radiusXL),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: EdgeInsets.only(top: AppSizes.spacingM),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: EdgeInsets.all(AppSizes.spacingL),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select Country',
                      style: AppTypography.h3,
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.border),
              // Countries List
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.symmetric(vertical: AppSizes.spacingS),
                  itemCount: _centralAfricanCountries.length,
                  itemBuilder: (context, index) {
                    final country = _centralAfricanCountries[index];
                    final isSelected = country.code == _selectedCountry.code;

                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedCountry = country;
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSizes.spacingL,
                          vertical: AppSizes.spacingM,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primaryLight
                              : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            // Flag
                            Text(
                              country.flag,
                              style: const TextStyle(fontSize: 32),
                            ),
                            SizedBox(width: AppSizes.spacingM),
                            // Country info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    country.name,
                                    style: AppTypography.body1.copyWith(
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.black,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: AppSizes.spacingXS / 2),
                                  Text(
                                    country.code,
                                    style: AppTypography.body2.copyWith(
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Checkmark
                            if (isSelected)
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.check_rounded,
                                  color: AppColors.black,
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
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Car Image Section
              FadeTransition(
                opacity: _fadeAnimation,
                child: _buildCarSection(),
              ),

              // Login Form Section
              SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildLoginForm(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCarSection() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.45,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background,
            AppColors.white,
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: AppSizes.spacingXL + 8),

          // Logo/Title
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'PROXYM ',
                  style: AppTypography.tesla(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.black,
                  ),
                ),
                TextSpan(
                  text: 'TRACKING',
                  style: AppTypography.tesla(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: AppSizes.spacingS),

          // Tagline
          Text(
            'Track your vehicle anywhere',
            style: AppTypography.body2,
          ),

          SizedBox(height: AppSizes.spacingL + 6),

          // Car Image
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingL),
              child: Image.asset(
                'assets/login1.png',
                fit: BoxFit.contain,
              ),
            ),
          ),

          SizedBox(height: AppSizes.spacingL),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return Container(
      padding: EdgeInsets.all(AppSizes.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Text
          Text(
            'Welcome back',
            style: AppTypography.h2,
          ),

          SizedBox(height: AppSizes.spacingS),

          Text(
            'Sign in to continue tracking',
            style: AppTypography.body2,
          ),

          SizedBox(height: AppSizes.spacingXL),

          // Phone Number Field
          _buildInputLabel('Phone number'),
          SizedBox(height: AppSizes.spacingS),
          _buildPhoneField(),

          SizedBox(height: AppSizes.spacingL),

          // Password Field
          _buildInputLabel('Password'),
          SizedBox(height: AppSizes.spacingS),
          _buildPasswordField(),

          SizedBox(height: AppSizes.spacingM),

          // Remember Me & Forgot Password
          _buildOptionsRow(),

          SizedBox(height: AppSizes.spacingXL),

          // Login Button
          _buildLoginButton(),

          SizedBox(height: AppSizes.spacingL),

          // ✅ ADDED: Copyright Footer with Dynamic Year
          _buildCopyrightFooter(),

          SizedBox(height: AppSizes.spacingL),
        ],
      ),
    );
  }

  // ✅ NEW: Copyright Footer Widget
  Widget _buildCopyrightFooter() {
    final currentYear = DateTime.now().year;

    return Center(
      child: Text(
        '© $currentYear All rights reserved to PROXYM GROUP',
        style: AppTypography.caption.copyWith(
          color: AppColors.textSecondary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: AppTypography.body1.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildPhoneField() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: Border.all(
          color: AppColors.border,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          // Country Selector
          InkWell(
            onTap: _showCountryPicker,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingM),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: AppColors.border,
                    width: 1.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Flag
                  Text(
                    _selectedCountry.flag,
                    style: const TextStyle(fontSize: 24),
                  ),
                  SizedBox(width: AppSizes.spacingS),
                  // Country Code
                  Text(
                    _selectedCountry.code,
                    style: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: AppSizes.spacingXS),
                  // Dropdown Icon
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          // Phone Input
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingM),
              child: TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: AppTypography.body1,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: '612 345 678',
                  hintStyle: AppTypography.body1.copyWith(
                    color: AppColors.textSecondary.withOpacity(0.6),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: Border.all(
          color: AppColors.border,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          // Lock Icon
          Padding(
            padding: EdgeInsets.only(
              left: AppSizes.spacingM,
              right: AppSizes.spacingM,
            ),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                color: AppColors.primary,
                size: 16,
              ),
            ),
          ),
          // Password Input
          Expanded(
            child: TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: AppTypography.body1,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Enter your password',
                hintStyle: AppTypography.body1.copyWith(
                  color: AppColors.textSecondary.withOpacity(0.6),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          // Toggle Password Visibility
          IconButton(
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
            icon: Icon(
              _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Remember Me
        Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _rememberMe,
                onChanged: (value) {
                  setState(() {
                    _rememberMe = value ?? false;
                  });
                },
                activeColor: AppColors.primary,
                checkColor: AppColors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                side: BorderSide(
                  color: AppColors.border,
                  width: 1.5,
                ),
              ),
            ),
            SizedBox(width: AppSizes.spacingS),
            Text(
              'Remember me',
              style: AppTypography.body2.copyWith(
                color: AppColors.black,
              ),
            ),
          ],
        ),
        // Forgot Password
        TextButton(
          onPressed: () {
            // Navigate to Forgot Password screen
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ForgotPasswordScreen(),
              ),
            );
          },
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'Forgot password?',
            style: AppTypography.body2.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
          ),
          elevation: 0,
          shadowColor: AppColors.primary.withOpacity(0.3),
        ),
        child: _isLoading
            ? SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.black),
          ),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Sign In',
              style: AppTypography.button.copyWith(
                color: AppColors.black,
              ),
            ),
            SizedBox(width: AppSizes.spacingS),
            Icon(
              Icons.arrow_forward_rounded,
              color: AppColors.black,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}