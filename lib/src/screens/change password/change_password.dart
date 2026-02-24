// lib/screens/change_password/change_password.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';
import '../../services/pin_service.dart';
import '../create_pin screen/create_pin.dart';
import '../dashboard/dashboard.dart';



class ResetPasswordScreen extends StatefulWidget {
  final int userId;
  final bool isFirstLogin;

  const ResetPasswordScreen({
    Key? key,
    required this.userId,
    this.isFirstLogin = false,
  }) : super(key: key);

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
  TextEditingController();
  final PinService _pinService = PinService();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  String get baseUrl => EnvConfig.baseUrl;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (password.isEmpty || confirmPassword.isEmpty) {
      _showErrorSnackbar('Please fill in all fields');
      return;
    }

    if (password.length < 6) {
      _showErrorSnackbar('Password must be at least 6 characters');
      return;
    }

    if (password != confirmPassword) {
      _showErrorSnackbar('Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('accessToken');

      final response = await http.post(
        Uri.parse('$baseUrl/users/set-password'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userId': widget.userId,
          'newPassword': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          setState(() => _isLoading = false);
          _showSuccessSnackbar('Password set successfully!');

          await Future.delayed(const Duration(seconds: 1));
          if (!mounted) return;

          // ✅ Check PIN using the logged-in user's own ID from SharedPreferences
          // PinService._getUserId() reads prefs.getInt('user_id') which was
          // saved at login as the actual logged-in user's ID — correct for
          // both regular users and chauffeurs
          debugPrint('🔐 Checking PIN for user: ${widget.userId}');
          final hasPinSet = await _pinService.hasPinSet();
          debugPrint('🔐 Has PIN set: $hasPinSet');

          if (!mounted) return;

          if (!hasPinSet) {
            // ✅ No PIN → go to create PIN screen
            debugPrint('🔑 No PIN found → navigating to Create PIN screen');
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    CreatePinScreen(userId: widget.userId),
              ),
            );
          } else {
            // ✅ PIN exists → go straight to dashboard
            debugPrint('✅ PIN already exists → navigating to dashboard');
            _navigateToDashboard();
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to set password');
        }
      } else {
        throw Exception('Failed to set password: ${response.statusCode}');
      }
    } catch (error) {
      setState(() => _isLoading = false);
      debugPrint('🔥 Error setting password: $error');
      _showErrorSnackbar('Failed to set password. Please try again.');
    }
  }

  // ========== NAVIGATE TO DASHBOARD ==========
  // ✅ FIX: Reads vehicle from SharedPreferences instead of calling
  // /voitures/user/:userId which fails for chauffeurs and is redundant
  // since login already saved the vehicles list
  void _navigateToDashboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ✅ Read from SharedPreferences — saved at login for both user types
      final int? vehicleId = prefs.getInt('current_vehicle_id');

      if (vehicleId != null) {
        debugPrint('🚗 Navigating to dashboard with vehicle ID: $vehicleId');
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ModernDashboard(vehicleId: vehicleId),
          ),
        );
      } else {
        // Fallback: try vehicles_list
        final vehiclesJson = prefs.getString('vehicles_list');
        if (vehiclesJson != null) {
          final List vehicles = jsonDecode(vehiclesJson);
          if (vehicles.isNotEmpty) {
            final int firstVehicleId = vehicles[0]["id"];
            await prefs.setInt('current_vehicle_id', firstVehicleId);

            debugPrint('🚗 Fallback vehicle ID: $firstVehicleId');
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ModernDashboard(vehicleId: firstVehicleId),
              ),
            );
          } else {
            _showErrorSnackbar('No vehicles found for this account');
          }
        } else {
          _showErrorSnackbar('Unable to load dashboard. Please login again.');
        }
      }
    } catch (error) {
      debugPrint('🔥 Error navigating to dashboard: $error');
      _showErrorSnackbar('Failed to load dashboard. Please login again.');
    }
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.white),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: widget.isFirstLogin
            ? null
            : IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.black),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(AppSizes.spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: AppSizes.spacingL),

                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_reset_rounded,
                    color: AppColors.primary,
                    size: 40,
                  ),
                ),

                SizedBox(height: AppSizes.spacingXL),

                // Title
                Text(
                  widget.isFirstLogin
                      ? 'Set Your Password'
                      : 'Reset Password',
                  style: AppTypography.h2,
                ),
                SizedBox(height: AppSizes.spacingS),
                Text(
                  widget.isFirstLogin
                      ? 'Welcome to FLEETRA! Please create a secure password to access your account.'
                      : 'Please create a new password for your account.',
                  style: AppTypography.body2,
                ),

                SizedBox(height: AppSizes.spacingXL),

                // New Password Field
                Text(
                  'New Password',
                  style: AppTypography.body1
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: AppSizes.spacingS),
                _buildPasswordField(
                  controller: _passwordController,
                  hint: 'Enter new password',
                  obscure: _obscurePassword,
                  onToggle: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),

                SizedBox(height: AppSizes.spacingL),

                // Confirm Password Field
                Text(
                  'Confirm Password',
                  style: AppTypography.body1
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: AppSizes.spacingS),
                _buildPasswordField(
                  controller: _confirmPasswordController,
                  hint: 'Confirm your password',
                  obscure: _obscureConfirmPassword,
                  onToggle: () => setState(
                          () => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),

                SizedBox(height: AppSizes.spacingM),

                // Password Requirements
                Container(
                  padding: EdgeInsets.all(AppSizes.spacingM),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppSizes.radiusM),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: AppColors.primary, size: 20),
                      SizedBox(width: AppSizes.spacingM),
                      Expanded(
                        child: Text(
                          'Password must be at least 6 characters long',
                          style: AppTypography.caption
                              .copyWith(color: AppColors.black),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: AppSizes.spacingXL),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleResetPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor:
                      AppColors.primary.withOpacity(0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(AppSizes.radiusM),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.white),
                      ),
                    )
                        : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Set Password & Continue',
                          style: AppTypography.button
                              .copyWith(color: AppColors.white),
                        ),
                        SizedBox(width: AppSizes.spacingS),
                        Icon(Icons.arrow_forward_rounded,
                            color: AppColors.white, size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
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
            padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingM),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_outline,
                  color: AppColors.primary, size: 16),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              style: AppTypography.body1,
              enabled: !_isLoading,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle: AppTypography.body1.copyWith(
                  color: AppColors.textSecondary.withOpacity(0.6),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onToggle,
            icon: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}