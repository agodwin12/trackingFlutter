// lib/src/screens/profile/change_password_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';

class ChangePasswordScreen extends StatefulWidget {
  final String initialPhone;
  final int userId;

  const ChangePasswordScreen({
    Key? key,
    required this.initialPhone,
    required this.userId,
  }) : super(key: key);

  @override
  _ChangePasswordScreenState createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  // Step management
  int _currentStep = 1; // 1: Phone, 2: OTP, 3: New Password
  String _selectedLanguage = 'en';

  // Phone number step
  final TextEditingController _phoneController = TextEditingController();

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

  @override
  void initState() {
    super.initState();
    // Remove the + sign from phone number for SMS API compatibility
    _phoneController.text = widget.initialPhone;
    _phoneWithCountryCode = widget.initialPhone.replaceAll('+', '');
    _loadLanguagePreference();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
  }

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
      _showErrorSnackbar(
        _selectedLanguage == 'en'
            ? "Phone number is required"
            : "Le numéro de téléphone est requis",
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Remove the + sign for SMS API compatibility
    _phoneWithCountryCode = _phoneController.text.trim().replaceAll('+', '');

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
        _showSuccessSnackbar(
          _selectedLanguage == 'en'
              ? "OTP sent to your phone number"
              : "OTP envoyé à votre numéro",
        );

        // Move to Step 2 (OTP)
        setState(() {
          _currentStep = 2;
        });

        // Start timer for OTP
        _startTimer();
      } else {
        debugPrint('❌ Failed to send OTP: ${responseData["message"]}');
        _showErrorSnackbar(
          responseData["message"] ?? (_selectedLanguage == 'en'
              ? "Failed to send OTP"
              : "Échec de l'envoi de l'OTP"),
        );
      }
    } catch (error) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar(
        _selectedLanguage == 'en'
            ? "Connection error. Please try again."
            : "Erreur de connexion. Veuillez réessayer.",
      );
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
      _showErrorSnackbar(
        _selectedLanguage == 'en'
            ? "Please enter the complete 6-digit OTP"
            : "Veuillez saisir le code OTP complet à 6 chiffres",
      );
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
        _showSuccessSnackbar(
          _selectedLanguage == 'en'
              ? "OTP verified successfully"
              : "OTP vérifié avec succès",
        );

        // Cancel timer
        _timer.cancel();

        // Move to Step 3 (New Password)
        setState(() {
          _currentStep = 3;
        });
      } else {
        debugPrint('❌ OTP verification failed: ${responseData["message"]}');
        _showErrorSnackbar(
          responseData["message"] ?? (_selectedLanguage == 'en'
              ? "Invalid OTP"
              : "OTP invalide"),
        );

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
      _showErrorSnackbar(
        _selectedLanguage == 'en'
            ? "Connection error. Please try again."
            : "Erreur de connexion. Veuillez réessayer.",
      );
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

        _showSuccessSnackbar(
          _selectedLanguage == 'en'
              ? "New OTP sent to your phone"
              : "Nouveau OTP envoyé à votre téléphone",
        );
      } else {
        debugPrint('❌ Failed to resend OTP: ${responseData["message"]}');
        _showErrorSnackbar(
          responseData["message"] ?? (_selectedLanguage == 'en'
              ? "Failed to resend OTP"
              : "Échec du renvoi de l'OTP"),
        );
      }
    } catch (error) {
      setState(() {
        _isResending = false;
      });
      _showErrorSnackbar(
        _selectedLanguage == 'en'
            ? "Connection error. Please try again."
            : "Erreur de connexion. Veuillez réessayer.",
      );
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
      _showErrorSnackbar(
        _selectedLanguage == 'en'
            ? "Please fill in all fields"
            : "Veuillez remplir tous les champs",
      );
      return;
    }

    if (newPassword.length < 6) {
      _showErrorSnackbar(
        _selectedLanguage == 'en'
            ? "Password must be at least 6 characters"
            : "Le mot de passe doit contenir au moins 6 caractères",
      );
      return;
    }

    if (newPassword != confirmPassword) {
      _showErrorSnackbar(
        _selectedLanguage == 'en'
            ? "Passwords do not match"
            : "Les mots de passe ne correspondent pas",
      );
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
        debugPrint('✅ Password changed successfully');
        _showSuccessSnackbar(
          _selectedLanguage == 'en'
              ? "Password changed successfully!"
              : "Mot de passe changé avec succès !",
        );

        // Wait a moment then navigate back to profile
        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        debugPrint('❌ Password change failed: ${responseData["message"]}');
        _showErrorSnackbar(
          responseData["message"] ?? (_selectedLanguage == 'en'
              ? "Failed to change password"
              : "Échec du changement de mot de passe"),
        );
      }
    } catch (error) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar(
        _selectedLanguage == 'en'
            ? "Connection error. Please try again."
            : "Erreur de connexion. Veuillez réessayer.",
      );
      debugPrint("❌ Change password error: $error");
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
      title = _selectedLanguage == 'en' ? 'Change Password' : 'Changer le mot de passe';
      description = _selectedLanguage == 'en'
          ? 'We\'ll send a verification code to your phone number to confirm it\'s you.'
          : 'Nous enverrons un code de vérification à votre numéro pour confirmer votre identité.';
    } else if (_currentStep == 2) {
      title = _selectedLanguage == 'en' ? 'Enter OTP' : 'Entrez le code OTP';
      String displayPhone = _phoneWithCountryCode.startsWith('+')
          ? _phoneWithCountryCode
          : '+$_phoneWithCountryCode';
      description = _selectedLanguage == 'en'
          ? 'We\'ve sent a 6-digit verification code to $displayPhone'
          : 'Nous avons envoyé un code à 6 chiffres à $displayPhone';
    } else {
      title = _selectedLanguage == 'en' ? 'Create New Password' : 'Créer un nouveau mot de passe';
      description = _selectedLanguage == 'en'
          ? 'Your new password must be different from previously used passwords.'
          : 'Votre nouveau mot de passe doit être différent des précédents.';
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
  // STEP 1: PHONE INPUT (READ-ONLY)
  // ========================================
  Widget _buildPhoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _selectedLanguage == 'en' ? 'Phone number' : 'Numéro de téléphone',
          style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
        ),
        SizedBox(height: AppSizes.spacingS),
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.border.withOpacity(0.2),
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingM),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.phone_outlined,
                    color: AppColors.primary,
                    size: 16,
                  ),
                ),
                SizedBox(width: AppSizes.spacingM),
                Expanded(
                  child: Text(
                    _phoneController.text,
                    style: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSizes.spacingS,
                    vertical: AppSizes.spacingXS,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppSizes.radiusS),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user, color: AppColors.success, size: 14),
                      SizedBox(width: 4),
                      Text(
                        _selectedLanguage == 'en' ? 'Verified' : 'Vérifié',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ],
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
                  _canResend
                      ? (_selectedLanguage == 'en' ? 'OTP Expired' : 'OTP expiré')
                      : (_selectedLanguage == 'en'
                      ? 'Expires in ${_formatTime(_secondsRemaining)}'
                      : 'Expire dans ${_formatTime(_secondsRemaining)}'),
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
          _selectedLanguage == 'en' ? 'New Password' : 'Nouveau mot de passe',
          style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
        ),
        SizedBox(height: AppSizes.spacingS),
        _buildPasswordField(
          _newPasswordController,
          _obscureNewPassword,
          _selectedLanguage == 'en' ? 'Enter new password' : 'Entrez le nouveau mot de passe',
              () {
            setState(() {
              _obscureNewPassword = !_obscureNewPassword;
            });
          },
        ),

        SizedBox(height: AppSizes.spacingL),

        // Confirm Password
        Text(
          _selectedLanguage == 'en' ? 'Confirm Password' : 'Confirmer le mot de passe',
          style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
        ),
        SizedBox(height: AppSizes.spacingS),
        _buildPasswordField(
          _confirmPasswordController,
          _obscureConfirmPassword,
          _selectedLanguage == 'en' ? 'Confirm new password' : 'Confirmez le nouveau mot de passe',
              () {
            setState(() {
              _obscureConfirmPassword = !_obscureConfirmPassword;
            });
          },
        ),
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
      buttonText = _selectedLanguage == 'en' ? 'Send OTP' : 'Envoyer OTP';
      onPressed = _requestOTP;
    } else if (_currentStep == 2) {
      buttonText = _selectedLanguage == 'en' ? 'Verify OTP' : 'Vérifier OTP';
      onPressed = _verifyOTP;
    } else {
      buttonText = _selectedLanguage == 'en' ? 'Change Password' : 'Changer le mot de passe';
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
                _selectedLanguage == 'en' ? 'Back to Profile' : 'Retour au profil',
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
                _selectedLanguage == 'en'
                    ? 'Didn\'t receive the code? '
                    : 'Code non reçu ? ',
                style: AppTypography.body1.copyWith(color: AppColors.textSecondary),
              ),
              Text(
                _selectedLanguage == 'en' ? 'Resend' : 'Renvoyer',
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