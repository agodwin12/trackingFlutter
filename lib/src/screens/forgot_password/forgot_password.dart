// lib/src/screens/forgot_password/forgot_password_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';
import '../login/login.dart';

class Country {
  final String name;
  final String code;
  final String flag;

  Country({required this.name, required this.code, required this.flag});
}

class ForgotPasswordScreen extends StatefulWidget {
  @override
  _ForgotPasswordScreenState createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  // Step management
  int _currentStep = 1; // 1: Phone, 2: OTP, 3: New Password

  // Phone number step
  final TextEditingController _phoneController = TextEditingController();
  Country _selectedCountry = Country(name: 'Cameroon', code: '+237', flag: '🇨🇲');

  // OTP step
  final List<TextEditingController> _otpControllers = List.generate(
    6,
        (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    6,
        (index) => FocusNode(),
  );
  late Timer _timer;
  int _secondsRemaining = 300;
  bool _canResend = false;

  // Password step
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  // State variables
  bool _isLoading = false;
  bool _isResending = false;
  String _phoneWithCountryCode = '';
  String _resetToken = '';

  // Get base URL from environment config
  String get baseUrl => EnvConfig.baseUrl;

  // Central African Countries
  final List<Country> _centralAfricanCountries = [
    Country(name: 'Cameroon', code: '+237', flag: '🇨🇲'),
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

  @override
  void dispose() {
    if (_currentStep == 2) {
      _timer.cancel();
    }
    _phoneController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  // ========================================
  // STEP 1: REQUEST OTP
  // ========================================
  void _requestOTP() async {
    if (_phoneController.text.trim().isEmpty) {
      _showErrorSnackbar("Phone number is required");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Remove the + sign from country code before combining
    String countryCodeWithoutPlus = _selectedCountry.code.replaceAll('+', '');
    _phoneWithCountryCode = countryCodeWithoutPlus + _phoneController.text.trim();

    final Uri url = Uri.parse("$baseUrl/auth/forgot-password/request-otp");

    try {
      debugPrint('📱 Requesting OTP for: $_phoneWithCountryCode');

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": _phoneWithCountryCode,
        }),
      );

      final responseData = jsonDecode(response.body);

      setState(() {
        _isLoading = false;
      });

      if (response.statusCode == 200) {
        debugPrint('✅ OTP sent successfully');
        _showSuccessSnackbar("OTP sent to your phone number");

        // Move to Step 2 (OTP)
        setState(() {
          _currentStep = 2;
        });

        // Start timer for OTP
        _startTimer();

      } else {
        debugPrint('❌ Failed to send OTP: ${responseData["message"]}');
        _showErrorSnackbar(responseData["message"] ?? "Failed to send OTP");
      }
    } catch (error) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar("Connection error. Please try again.");
      debugPrint("❌ Request OTP error: $error");
    }
  }

  // ========================================
  // STEP 2: VERIFY OTP
  // ========================================
  void _startTimer() {
    _secondsRemaining = 300; // 5 minutes
    _canResend = false;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_secondsRemaining > 0) {
            _secondsRemaining--;
          } else {
            _canResend = true;
            _timer.cancel();
          }
        });
      }
    });
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  String _getOTP() {
    return _otpControllers.map((controller) => controller.text).join();
  }

  void _verifyOTP() async {
    String otp = _getOTP();

    if (otp.length != 6) {
      _showErrorSnackbar("Please enter the complete 6-digit OTP");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final Uri url = Uri.parse("$baseUrl/auth/forgot-password/verify-otp");

    try {
      debugPrint('🔍 Verifying OTP: $otp');

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": _phoneWithCountryCode,
          "otp": otp,
        }),
      );

      final responseData = jsonDecode(response.body);

      setState(() {
        _isLoading = false;
      });

      if (response.statusCode == 200) {
        debugPrint('✅ OTP verified successfully');

        _resetToken = responseData["resetToken"];
        _showSuccessSnackbar("OTP verified successfully");

        // Cancel timer
        _timer.cancel();

        // Move to Step 3 (New Password)
        setState(() {
          _currentStep = 3;
        });

      } else {
        debugPrint('❌ OTP verification failed: ${responseData["message"]}');
        _showErrorSnackbar(responseData["message"] ?? "Invalid OTP");

        // Clear OTP fields
        for (var controller in _otpControllers) {
          controller.clear();
        }
        _focusNodes[0].requestFocus();
      }
    } catch (error) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar("Connection error. Please try again.");
      debugPrint("❌ Verify OTP error: $error");
    }
  }

  void _resendOTP() async {
    if (!_canResend || _isResending) return;

    setState(() {
      _isResending = true;
    });

    final Uri url = Uri.parse("$baseUrl/auth/forgot-password/resend-otp");

    try {
      debugPrint('📱 Resending OTP to: $_phoneWithCountryCode');

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": _phoneWithCountryCode,
        }),
      );

      final responseData = jsonDecode(response.body);

      setState(() {
        _isResending = false;
      });

      if (response.statusCode == 200) {
        debugPrint('✅ OTP resent successfully');

        // Clear previous OTP
        for (var controller in _otpControllers) {
          controller.clear();
        }
        _focusNodes[0].requestFocus();

        // Restart timer
        _startTimer();

        _showSuccessSnackbar("New OTP sent to your phone");
      } else {
        debugPrint('❌ Failed to resend OTP: ${responseData["message"]}');
        _showErrorSnackbar(responseData["message"] ?? "Failed to resend OTP");
      }
    } catch (error) {
      setState(() {
        _isResending = false;
      });
      _showErrorSnackbar("Connection error. Please try again.");
      debugPrint("❌ Resend OTP error: $error");
    }
  }

  // ========================================
  // STEP 3: RESET PASSWORD
  // ========================================
  void _resetPassword() async {
    String newPassword = _newPasswordController.text.trim();
    String confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      _showErrorSnackbar("Please fill in all fields");
      return;
    }

    if (newPassword.length < 6) {
      _showErrorSnackbar("Password must be at least 6 characters");
      return;
    }

    if (newPassword != confirmPassword) {
      _showErrorSnackbar("Passwords do not match");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final Uri url = Uri.parse("$baseUrl/auth/forgot-password/reset-password");

    try {
      debugPrint('🔒 Resetting password...');

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": _phoneWithCountryCode,
          "resetToken": _resetToken,
          "newPassword": newPassword,
        }),
      );

      final responseData = jsonDecode(response.body);

      setState(() {
        _isLoading = false;
      });

      if (response.statusCode == 200) {
        debugPrint('✅ Password reset successfully');
        _showSuccessSnackbar("Password reset successfully!");

        // Wait a moment then navigate to login
        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => ModernLoginScreen()),
                (route) => false,
          );
        }

      } else {
        debugPrint('❌ Password reset failed: ${responseData["message"]}');
        _showErrorSnackbar(responseData["message"] ?? "Failed to reset password");
      }
    } catch (error) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar("Connection error. Please try again.");
      debugPrint("❌ Reset password error: $error");
    }
  }

  // ========================================
  // UI HELPERS
  // ========================================
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

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppColors.white),
            SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Text(
                message,
                style: AppTypography.body1.copyWith(color: AppColors.white),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.success,
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
              Container(
                margin: EdgeInsets.only(top: AppSizes.spacingM),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(AppSizes.spacingL),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Select Country', style: AppTypography.h3),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.border),
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
                          color: isSelected ? AppColors.primaryLight : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            Text(country.flag, style: const TextStyle(fontSize: 32)),
                            SizedBox(width: AppSizes.spacingM),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    country.name,
                                    style: AppTypography.body1.copyWith(
                                      color: isSelected ? AppColors.primary : AppColors.black,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: AppSizes.spacingXS / 2),
                                  Text(
                                    country.code,
                                    style: AppTypography.body2.copyWith(
                                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
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

  // ========================================
  // MAIN BUILD
  // ========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.black),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppSizes.spacingL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: AppSizes.spacingL),

              // Step Indicator
              _buildStepIndicator(),

              SizedBox(height: AppSizes.spacingXL),

              // Icon
              _buildIcon(),

              SizedBox(height: AppSizes.spacingXL),

              // Title & Description
              _buildTitleAndDescription(),

              SizedBox(height: AppSizes.spacingXL + 8),

              // Dynamic Content based on step
              _buildStepContent(),

              SizedBox(height: AppSizes.spacingXL + 8),

              // Action Button
              _buildActionButton(),

              SizedBox(height: AppSizes.spacingL),

              // Bottom Link
              _buildBottomLink(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _buildStepDot(1),
        _buildStepLine(1),
        _buildStepDot(2),
        _buildStepLine(2),
        _buildStepDot(3),
      ],
    );
  }

  Widget _buildStepDot(int step) {
    bool isActive = _currentStep >= step;
    bool isCurrent = _currentStep == step;

    return Container(
      width: isCurrent ? 32 : 24,
      height: isCurrent ? 32 : 24,
      decoration: BoxDecoration(
        color: isActive ? AppColors.primary : AppColors.border,
        shape: BoxShape.circle,
        border: isCurrent
            ? Border.all(color: AppColors.primary.withOpacity(0.3), width: 4)
            : null,
      ),
      child: Center(
        child: Text(
          '$step',
          style: AppTypography.body2.copyWith(
            color: isActive ? AppColors.black : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: isCurrent ? 14 : 12,
          ),
        ),
      ),
    );
  }

  Widget _buildStepLine(int step) {
    bool isActive = _currentStep > step;

    return Expanded(
      child: Container(
        height: 2,
        margin: EdgeInsets.symmetric(horizontal: AppSizes.spacingS),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.border,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    IconData iconData;
    if (_currentStep == 1) {
      iconData = Icons.lock_reset_rounded;
    } else if (_currentStep == 2) {
      iconData = Icons.sms_outlined;
    } else {
      iconData = Icons.lock_open_rounded;
    }

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        shape: BoxShape.circle,
      ),
      child: Icon(
        iconData,
        color: AppColors.primary,
        size: 40,
      ),
    );
  }

  Widget _buildTitleAndDescription() {
    String title;
    String description;

    if (_currentStep == 1) {
      title = 'Forgot Password?';
      description = 'Don\'t worry! Enter your phone number and we\'ll send you an OTP to reset your password.';
    } else if (_currentStep == 2) {
      title = 'Enter OTP';
      // Display with + for readability, but backend receives without +
      String displayPhone = '+$_phoneWithCountryCode';
      description = 'We\'ve sent a 6-digit verification code to $displayPhone';
    } else {
      title = 'Create New Password';
      description = 'Your new password must be different from previously used passwords.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.h1),
        SizedBox(height: AppSizes.spacingM),
        Text(
          description,
          style: AppTypography.body1.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildStepContent() {
    if (_currentStep == 1) {
      return _buildPhoneStep();
    } else if (_currentStep == 2) {
      return _buildOTPStep();
    } else {
      return _buildPasswordStep();
    }
  }

  // ========================================
  // STEP 1: PHONE INPUT
  // ========================================
  Widget _buildPhoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phone number',
          style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
        ),
        SizedBox(height: AppSizes.spacingS),
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: _showCountryPicker,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingM),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: AppColors.border, width: 1.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(_selectedCountry.flag, style: const TextStyle(fontSize: 24)),
                      SizedBox(width: AppSizes.spacingS),
                      Text(
                        _selectedCountry.code,
                        style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(width: AppSizes.spacingXS),
                      Icon(Icons.arrow_drop_down_rounded, color: AppColors.textSecondary, size: 20),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingM),
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: AppTypography.body1,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '659 34 56 78',
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
        ),
      ],
    );
  }

  // ========================================
  // STEP 2: OTP INPUT
  // ========================================
  Widget _buildOTPStep() {
    return Column(
      children: [
        // OTP Fields
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 50,
              height: 60,
              child: TextField(
                controller: _otpControllers[index],
                focusNode: _focusNodes[index],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                style: AppTypography.h2,
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusM),
                    borderSide: BorderSide(color: AppColors.border, width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusM),
                    borderSide: BorderSide(color: AppColors.border, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusM),
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  if (value.isNotEmpty && index < 5) {
                    _focusNodes[index + 1].requestFocus();
                  } else if (value.isEmpty && index > 0) {
                    _focusNodes[index - 1].requestFocus();
                  }

                  if (index == 5 && value.isNotEmpty) {
                    String otp = _getOTP();
                    if (otp.length == 6) {
                      _verifyOTP();
                    }
                  }
                },
              ),
            );
          }),
        ),

        SizedBox(height: AppSizes.spacingL),

        // Timer
        Center(
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppSizes.spacingL,
              vertical: AppSizes.spacingM,
            ),
            decoration: BoxDecoration(
              color: _canResend ? AppColors.error.withOpacity(0.1) : AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_outlined,
                  color: _canResend ? AppColors.error : AppColors.primary,
                  size: 20,
                ),
                SizedBox(width: AppSizes.spacingS),
                Text(
                  _canResend ? 'OTP Expired' : 'Expires in ${_formatTime(_secondsRemaining)}',
                  style: AppTypography.body1.copyWith(
                    color: _canResend ? AppColors.error : AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ========================================
  // STEP 3: PASSWORD INPUT
  // ========================================
  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // New Password
        Text(
          'New Password',
          style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
        ),
        SizedBox(height: AppSizes.spacingS),
        _buildPasswordField(_newPasswordController, _obscureNewPassword, 'Enter new password', () {
          setState(() {
            _obscureNewPassword = !_obscureNewPassword;
          });
        }),

        SizedBox(height: AppSizes.spacingL),

        // Confirm Password
        Text(
          'Confirm Password',
          style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
        ),
        SizedBox(height: AppSizes.spacingS),
        _buildPasswordField(_confirmPasswordController, _obscureConfirmPassword, 'Confirm new password', () {
          setState(() {
            _obscureConfirmPassword = !_obscureConfirmPassword;
          });
        }),
      ],
    );
  }

  Widget _buildPasswordField(
      TextEditingController controller,
      bool obscureText,
      String hintText,
      VoidCallback toggleVisibility,
      ) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.only(left: AppSizes.spacingM, right: AppSizes.spacingM),
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
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              style: AppTypography.body1,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hintText,
                hintStyle: AppTypography.body1.copyWith(
                  color: AppColors.textSecondary.withOpacity(0.6),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: toggleVisibility,
            icon: Icon(
              obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // ACTION BUTTON
  // ========================================
  Widget _buildActionButton() {
    String buttonText;
    VoidCallback? onPressed;

    if (_currentStep == 1) {
      buttonText = 'Send OTP';
      onPressed = _requestOTP;
    } else if (_currentStep == 2) {
      buttonText = 'Verify OTP';
      onPressed = _verifyOTP;
    } else {
      buttonText = 'Reset Password';
      onPressed = _resetPassword;
    }

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
          ),
          elevation: 0,
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
              buttonText,
              style: AppTypography.button.copyWith(color: AppColors.black),
            ),
            SizedBox(width: AppSizes.spacingS),
            Icon(Icons.arrow_forward_rounded, color: AppColors.black, size: 20),
          ],
        ),
      ),
    );
  }

  // ========================================
  // BOTTOM LINK
  // ========================================
  Widget _buildBottomLink() {
    if (_currentStep == 1) {
      return Center(
        child: TextButton(
          onPressed: () => Navigator.pop(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: AppSizes.spacingS),
              Text(
                'Back to Login',
                style: AppTypography.body1.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    } else if (_currentStep == 2) {
      return Center(
        child: TextButton(
          onPressed: (_canResend && !_isResending) ? _resendOTP : null,
          child: _isResending
              ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          )
              : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Didn\'t receive the code? ',
                style: AppTypography.body1.copyWith(color: AppColors.textSecondary),
              ),
              Text(
                'Resend',
                style: AppTypography.body1.copyWith(
                  color: _canResend ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }
}