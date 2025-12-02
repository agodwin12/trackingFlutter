// lib/screens/auth/pin_entry_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/pin_service.dart';
import '../../core/utility/app_theme.dart';

class PinEntryScreen extends StatefulWidget {
  final int vehicleId;

  const PinEntryScreen({
    Key? key,
    required this.vehicleId,
  }) : super(key: key);

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final PinService _pinService = PinService();
  String _pin = '';
  String _errorMessage = '';
  bool _isVerifying = false;
  String _selectedLanguage = 'en';
  int _failedAttempts = 0;

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
    _checkFailedAttempts();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
  }

  Future<void> _checkFailedAttempts() async {
    final attempts = await _pinService.getFailedAttempts();
    setState(() {
      _failedAttempts = attempts;
    });

    if (await _pinService.isMaxAttemptsReached()) {
      _showMaxAttemptsDialog();
    }
  }

  void _onNumberPressed(String number) {
    if (_pin.length >= 4 || _isVerifying) return;

    setState(() {
      _errorMessage = '';
      _pin += number;
    });

    // Auto-verify when 4 digits entered
    if (_pin.length == 4) {
      _verifyPin();
    }
  }

  void _onDeletePressed() {
    if (_pin.isEmpty || _isVerifying) return;

    setState(() {
      _errorMessage = '';
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  Future<void> _verifyPin() async {
    setState(() {
      _isVerifying = true;
    });

    final isCorrect = await _pinService.verifyPin(_pin);

    if (isCorrect) {
      // PIN correct - navigate to dashboard
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(
          '/dashboard',
          arguments: widget.vehicleId,
        );
      }
    } else {
      // PIN incorrect
      final attempts = await _pinService.getFailedAttempts();
      final remainingAttempts = _pinService.maxAttempts - attempts;

      setState(() {
        _isVerifying = false;
        _failedAttempts = attempts;
        _errorMessage = _selectedLanguage == 'en'
            ? 'Incorrect PIN. $remainingAttempts attempts remaining.'
            : 'Code PIN incorrect. Il reste $remainingAttempts tentatives.';
        _pin = '';
      });

      if (await _pinService.isMaxAttemptsReached()) {
        _showMaxAttemptsDialog();
      }
    }
  }

  void _showMaxAttemptsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.error),
              SizedBox(width: 12),
              Text(
                _selectedLanguage == 'en' ? 'Access Locked' : 'Accès verrouillé',
                style: AppTypography.h3,
              ),
            ],
          ),
          content: Text(
            _selectedLanguage == 'en'
                ? 'Too many failed attempts. Please log in again to reset your PIN attempts.'
                : 'Trop de tentatives échouées. Veuillez vous reconnecter pour réinitialiser vos tentatives de code PIN.',
            style: AppTypography.body2,
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                // Clear all data and go to login
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();

                if (mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/login',
                        (route) => false,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: Text(_selectedLanguage == 'en' ? 'Go to Login' : 'Aller à la connexion'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent back button
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

                  // Lock Icon
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_outline,
                        color: AppColors.primary,
                        size: 50,
                      ),
                    ),
                  ),

                  SizedBox(height: AppSizes.spacingXL),

                  // Title
                  Center(
                    child: Text(
                      _selectedLanguage == 'en' ? 'Enter Your PIN' : 'Entrez votre PIN',
                      style: AppTypography.h2,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(height: AppSizes.spacingS),
                  Center(
                    child: Text(
                      _selectedLanguage == 'en'
                          ? 'Enter your 4-digit PIN to continue'
                          : 'Entrez votre code PIN à 4 chiffres pour continuer',
                      style: AppTypography.body2,
                      textAlign: TextAlign.center,
                    ),
                  ),

                  SizedBox(height: AppSizes.spacingXL),

                  // PIN Dots Display
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (index) {
                        final isFilled = index < _pin.length;
                        return Container(
                          margin: EdgeInsets.symmetric(horizontal: AppSizes.spacingM),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isFilled ? AppColors.primary : Colors.transparent,
                            border: Border.all(
                              color: AppColors.primary,
                              width: 2,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                  SizedBox(height: AppSizes.spacingL),

                  // Error Message
                  if (_errorMessage.isNotEmpty)
                    Container(
                      padding: EdgeInsets.all(AppSizes.spacingM),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(AppSizes.radiusM),
                        border: Border.all(
                          color: AppColors.error.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: AppColors.error,
                            size: 20,
                          ),
                          SizedBox(width: AppSizes.spacingS),
                          Expanded(
                            child: Text(
                              _errorMessage,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Loading Indicator
                  if (_isVerifying)
                    Container(
                      padding: EdgeInsets.all(AppSizes.spacingM),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(AppSizes.radiusM),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                          SizedBox(width: AppSizes.spacingM),
                          Text(
                            _selectedLanguage == 'en'
                                ? 'Verifying...'
                                : 'Vérification...',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                  SizedBox(height: AppSizes.spacingXL),

                  // Number Pad
                  _buildNumberPad(),

                  SizedBox(height: AppSizes.spacingL),

                  // Forgot PIN button
                  Center(
                    child: TextButton(
                      onPressed: _isVerifying
                          ? null
                          : () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear();
                        if (mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil(
                            '/login',
                                (route) => false,
                          );
                        }
                      },
                      child: Text(
                        _selectedLanguage == 'en' ? 'Forgot PIN? Login again' : 'PIN oublié ? Se reconnecter',
                        style: AppTypography.body2.copyWith(
                          color: AppColors.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumberPad() {
    return Column(
      children: [
        _buildNumberRow(['1', '2', '3']),
        SizedBox(height: AppSizes.spacingM),
        _buildNumberRow(['4', '5', '6']),
        SizedBox(height: AppSizes.spacingM),
        _buildNumberRow(['7', '8', '9']),
        SizedBox(height: AppSizes.spacingM),
        _buildNumberRow(['', '0', 'delete']),
      ],
    );
  }

  Widget _buildNumberRow(List<String> numbers) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: numbers.map((number) {
        if (number.isEmpty) {
          return SizedBox(width: 80, height: 56);
        }

        if (number == 'delete') {
          return InkWell(
            onTap: _isVerifying ? null : _onDeletePressed,
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            child: Container(
              width: 80,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
                border: Border.all(
                  color: AppColors.border,
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.backspace_outlined,
                color: AppColors.textSecondary,
                size: 24,
              ),
            ),
          );
        }

        return InkWell(
          onTap: _isVerifying ? null : () => _onNumberPressed(number),
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
          child: Container(
            width: 80,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
              border: Border.all(
                color: AppColors.border,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                number,
                style: AppTypography.h2.copyWith(
                  color: AppColors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}