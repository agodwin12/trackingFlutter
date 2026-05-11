// lib/screens/auth/create_pin_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/pin_service.dart';
import '../../core/utility/app_theme.dart';
import '../dashboard/dashboard.dart';
import '../recouvrement/dashboard/recouvrement_dashboard.dart';

class CreatePinScreen extends StatefulWidget {
  final int userId;

  const CreatePinScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen> {
  final PinService _pinService = PinService();

  String _pin              = '';
  String _confirmPin       = '';
  bool   _isConfirmStep    = false;
  bool   _isCreatingPin    = false;
  String _errorMessage     = '';
  String _selectedLanguage = 'en';

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
    _syncUserIdToPrefs();
  }

  Future<void> _syncUserIdToPrefs() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final current = prefs.getInt('user_id');
      if (current != widget.userId) {
        await prefs.setInt('user_id', widget.userId);
        debugPrint('🧩 Synced prefs user_id=$current → ${widget.userId}');
      }
    } catch (e) {
      debugPrint('❌ Failed to sync user_id: $e');
    }
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _selectedLanguage = prefs.getString('language') ?? 'en');
    }
  }

  // ── keypad ────────────────────────────────────────────────────────────────
  void _onNumberPressed(String number) {
    if (_isCreatingPin) return;
    setState(() {
      _errorMessage = '';
      if (!_isConfirmStep) {
        if (_pin.length < 4) {
          _pin += number;
          if (_pin.length == 4) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) setState(() => _isConfirmStep = true);
            });
          }
        }
      } else {
        if (_confirmPin.length < 4) {
          _confirmPin += number;
          if (_confirmPin.length == 4) _verifyAndSavePin();
        }
      }
    });
  }

  void _onDeletePressed() {
    if (_isCreatingPin) return;
    setState(() {
      _errorMessage = '';
      if (!_isConfirmStep) {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else {
        if (_confirmPin.isNotEmpty)
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
      }
    });
  }

  // ── create PIN ────────────────────────────────────────────────────────────
  Future<void> _verifyAndSavePin() async {
    if (_pin != _confirmPin) {
      setState(() {
        _errorMessage = _selectedLanguage == 'en'
            ? 'PINs do not match. Please try again.'
            : 'Les codes PIN ne correspondent pas. Veuillez réessayer.';
        _pin           = '';
        _confirmPin    = '';
        _isConfirmStep = false;
      });
      return;
    }

    setState(() => _isCreatingPin = true);

    try {
      await _syncUserIdToPrefs();
      final success = await _pinService.createPin(_pin);

      if (!success) {
        setState(() {
          _isCreatingPin = false;
          _errorMessage  = _selectedLanguage == 'en'
              ? 'Error creating PIN. Please try again.'
              : 'Erreur lors de la création du PIN. Veuillez réessayer.';
          _pin           = '';
          _confirmPin    = '';
          _isConfirmStep = false;
        });
        return;
      }

      debugPrint('✅ PIN created — navigating');
      await _navigateToDashboard();

    } catch (e) {
      debugPrint('❌ _verifyAndSavePin error: $e');
      if (!mounted) return;
      setState(() {
        _isCreatingPin = false;
        _errorMessage  = _selectedLanguage == 'en'
            ? 'An error occurred. Please try again.'
            : 'Une erreur s\'est produite. Veuillez réessayer.';
        _pin           = '';
        _confirmPin    = '';
        _isConfirmStep = false;
      });
    }
  }

  // ── navigate after PIN created ────────────────────────────────────────────
  Future<void> _navigateToDashboard() async {
    try {
      final prefs    = await SharedPreferences.getInstance();
      final userType = prefs.getString('user_type') ?? '';

      debugPrint('🧭 _navigateToDashboard userType="$userType"');

      // ── lease / recouvrement users — no vehicle needed ──────────────────
      if (userType == 'tracking_lease' || userType == 'lease') {
        final userJson = prefs.getString('user_data');
        final token    = prefs.getString('accessToken') ?? '';
        final roles    = prefs.getStringList('user_roles') ?? [];

        Map<String, dynamic> user = {};
        if (userJson != null) {
          try { user = jsonDecode(userJson) as Map<String, dynamic>; }
          catch (e) { debugPrint('❌ Failed to parse user_data: $e'); }
        }

        debugPrint('🚀 → RecouvrementDashboard');
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RecouvrementDashboard(
              user       : user,
              accessToken: token,
              roles      : roles,
            ),
          ),
        );
        return;
      }

      // ── tracking users — need a vehicle ─────────────────────────────────

      // Primary: current_vehicle_id saved at login
      final int? vehicleId = prefs.getInt('current_vehicle_id');
      if (vehicleId != null) {
        debugPrint('🚗 → ModernDashboard vehicleId=$vehicleId');
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ModernDashboard(vehicleId: vehicleId),
          ),
        );
        return;
      }

      // Fallback: first vehicle in vehicles_list
      final vehiclesJson = prefs.getString('vehicles_list');
      if (vehiclesJson != null) {
        try {
          final List vehicles = jsonDecode(vehiclesJson);
          if (vehicles.isNotEmpty) {
            final int firstId = vehicles[0]['id'] as int;
            await prefs.setInt('current_vehicle_id', firstId);
            debugPrint('🚗 → ModernDashboard (fallback) vehicleId=$firstId');
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ModernDashboard(vehicleId: firstId),
              ),
            );
            return;
          }
        } catch (e) {
          debugPrint('❌ Failed to parse vehicles_list: $e');
        }
      }

      // ── no vehicle + no lease user type ──────────────────────────────────
      // PIN was created OK. user_type was not saved at login (common first-login
      // race condition) or account is not fully configured.
      // Show a brief message and pop back to login — never leave user stuck.
      debugPrint('⚠️ No vehicle and no recognised user_type — popping to root');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedLanguage == 'en'
                ? 'PIN created! Please log in again to continue.'
                : 'PIN créé ! Veuillez vous reconnecter pour continuer.',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );

      // Always navigate — never leave user on PIN screen
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);

    } catch (error) {
      debugPrint('❌ _navigateToDashboard error: $error');
      if (!mounted) return;
      // Even on error — pop back to login so user is never stuck
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedLanguage == 'en'
                ? 'PIN created! Please log in again.'
                : 'PIN créé ! Veuillez vous reconnecter.',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: AppColors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(AppSizes.spacingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: AppSizes.spacingXL),

                  // lock icon
                  Center(
                    child: Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(
                          color: AppColors.primaryLight, shape: BoxShape.circle),
                      child: Icon(Icons.lock_outline,
                          color: AppColors.primary, size: 50),
                    ),
                  ),

                  SizedBox(height: AppSizes.spacingXL),

                  // title
                  Center(
                    child: Text(
                      _selectedLanguage == 'en'
                          ? 'Create Your PIN' : 'Créer votre PIN',
                      style: AppTypography.h2,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(height: AppSizes.spacingS),
                  Center(
                    child: Text(
                      !_isConfirmStep
                          ? (_selectedLanguage == 'en'
                          ? 'Choose a 4-digit PIN for security'
                          : 'Choisissez un code PIN à 4 chiffres')
                          : (_selectedLanguage == 'en'
                          ? 'Confirm your 4-digit PIN'
                          : 'Confirmez votre code PIN à 4 chiffres'),
                      style: AppTypography.body2,
                      textAlign: TextAlign.center,
                    ),
                  ),

                  SizedBox(height: AppSizes.spacingXL),

                  // PIN dots
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (index) {
                        final current = !_isConfirmStep ? _pin : _confirmPin;
                        final filled  = index < current.length;
                        return Container(
                          margin: EdgeInsets.symmetric(
                              horizontal: AppSizes.spacingM),
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: filled
                                ? AppColors.primary : Colors.transparent,
                            border: Border.all(
                                color: AppColors.primary, width: 2),
                          ),
                        );
                      }),
                    ),
                  ),

                  SizedBox(height: AppSizes.spacingL),

                  // error
                  if (_errorMessage.isNotEmpty)
                    Container(
                      padding: EdgeInsets.all(AppSizes.spacingM),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius:
                        BorderRadius.circular(AppSizes.radiusM),
                        border: Border.all(
                            color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        Icon(Icons.error_outline,
                            color: AppColors.error, size: 20),
                        SizedBox(width: AppSizes.spacingS),
                        Expanded(
                          child: Text(_errorMessage,
                              style: AppTypography.caption.copyWith(
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),

                  // loading
                  if (_isCreatingPin)
                    Container(
                      padding: EdgeInsets.all(AppSizes.spacingM),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius:
                        BorderRadius.circular(AppSizes.radiusM),
                      ),
                      child: Row(children: [
                        SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary),
                        ),
                        SizedBox(width: AppSizes.spacingM),
                        Text(
                          _selectedLanguage == 'en'
                              ? 'Setting up your account...'
                              : 'Configuration de votre compte...',
                          style: AppTypography.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      ]),
                    ),

                  SizedBox(height: AppSizes.spacingXL),

                  _buildNumberPad(),

                  SizedBox(height: AppSizes.spacingL),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── number pad ────────────────────────────────────────────────────────────
  Widget _buildNumberPad() {
    return Column(children: [
      _buildNumberRow(['1', '2', '3']),
      SizedBox(height: AppSizes.spacingM),
      _buildNumberRow(['4', '5', '6']),
      SizedBox(height: AppSizes.spacingM),
      _buildNumberRow(['7', '8', '9']),
      SizedBox(height: AppSizes.spacingM),
      _buildNumberRow(['', '0', 'delete']),
    ]);
  }

  Widget _buildNumberRow(List<String> numbers) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: numbers.map((number) {
        if (number.isEmpty) return const SizedBox(width: 80, height: 56);

        if (number == 'delete') {
          return InkWell(
            onTap: _isCreatingPin ? null : _onDeletePressed,
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            child: Container(
              width: 80, height: 56,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
              child: Icon(Icons.backspace_outlined,
                  color: AppColors.textSecondary, size: 24),
            ),
          );
        }

        return InkWell(
          onTap: _isCreatingPin ? null : () => _onNumberPressed(number),
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
          child: Container(
            width: 80, height: 56,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
              border: Border.all(color: AppColors.border, width: 1.5),
            ),
            child: Center(
              child: Text(number,
                  style: AppTypography.h2.copyWith(
                      color: AppColors.black,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        );
      }).toList(),
    );
  }
}