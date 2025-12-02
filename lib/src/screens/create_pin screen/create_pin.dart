// lib/screens/auth/create_pin_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../../services/pin_service.dart';
import '../../services/env_config.dart';
import '../../core/utility/app_theme.dart';

class CreatePinScreen extends StatefulWidget {
  final int userId;

  const CreatePinScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen> {
  final PinService _pinService = PinService();
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirmStep = false;
  bool _isCreatingPin = false;
  String _errorMessage = '';
  String _selectedLanguage = 'en';

  String get baseUrl => EnvConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
  }

  void _onNumberPressed(String number) {
    if (_isCreatingPin) return;

    setState(() {
      _errorMessage = '';
      if (!_isConfirmStep) {
        if (_pin.length < 4) {
          _pin += number;
          if (_pin.length == 4) {
            // Move to confirm step
            Future.delayed(const Duration(milliseconds: 300), () {
              setState(() {
                _isConfirmStep = true;
              });
            });
          }
        }
      } else {
        if (_confirmPin.length < 4) {
          _confirmPin += number;
          if (_confirmPin.length == 4) {
            // Verify and save PIN
            _verifyAndSavePin();
          }
        }
      }
    });
  }

  void _onDeletePressed() {
    if (_isCreatingPin) return;

    setState(() {
      _errorMessage = '';
      if (!_isConfirmStep) {
        if (_pin.isNotEmpty) {
          _pin = _pin.substring(0, _pin.length - 1);
        }
      } else {
        if (_confirmPin.isNotEmpty) {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        }
      }
    });
  }

  Future<void> _verifyAndSavePin() async {
    if (_pin != _confirmPin) {
      setState(() {
        _errorMessage = _selectedLanguage == 'en'
            ? 'PINs do not match. Please try again.'
            : 'Les codes PIN ne correspondent pas. Veuillez réessayer.';
        _pin = '';
        _confirmPin = '';
        _isConfirmStep = false;
      });
      return;
    }

    setState(() {
      _isCreatingPin = true;
    });

    try {
      // Save PIN
      final success = await _pinService.createPin(_pin);

      if (!success) {
        setState(() {
          _isCreatingPin = false;
          _errorMessage = _selectedLanguage == 'en'
              ? 'Error creating PIN. Please try again.'
              : 'Erreur lors de la création du PIN. Veuillez réessayer.';
          _pin = '';
          _confirmPin = '';
          _isConfirmStep = false;
        });
        return;
      }

      debugPrint('✅ PIN created successfully - fetching vehicles');

      // Fetch user's vehicles to get first vehicle ID
      await _fetchVehiclesAndNavigate();
    } catch (e) {
      debugPrint('❌ Error in _verifyAndSavePin: $e');
      setState(() {
        _isCreatingPin = false;
        _errorMessage = _selectedLanguage == 'en'
            ? 'An error occurred. Please try again.'
            : 'Une erreur s\'est produite. Veuillez réessayer.';
        _pin = '';
        _confirmPin = '';
        _isConfirmStep = false;
      });
    }
  }

  Future<void> _fetchVehiclesAndNavigate() async {
    try {
      debugPrint('📡 Fetching vehicles for user: ${widget.userId}');

      final response = await http.get(
        Uri.parse("$baseUrl/voitures/user/${widget.userId}"),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timeout');
        },
      );

      debugPrint('📥 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List vehicles = data["vehicles"];

        if (vehicles.isNotEmpty) {
          int firstVehicleId = vehicles[0]["id"];

          debugPrint('✅ Found ${vehicles.length} vehicles, navigating to dashboard with vehicle ID: $firstVehicleId');

          if (mounted) {
            // Save vehicle ID first
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('current_vehicle_id', firstVehicleId);
            debugPrint('🚗 Saved vehicle ID: $firstVehicleId');

            // Navigate to dashboard
            Navigator.pushReplacementNamed(
              context,
              '/dashboard',
              arguments: firstVehicleId,
            );
          }
        } else {
          // No vehicles found
          debugPrint('⚠️ No vehicles found');
          setState(() {
            _isCreatingPin = false;
            _errorMessage = _selectedLanguage == 'en'
                ? 'No vehicles found for this account'
                : 'Aucun véhicule trouvé pour ce compte';
            _pin = '';
            _confirmPin = '';
            _isConfirmStep = false;
          });
        }
      } else {
        throw Exception('Failed to fetch vehicles: ${response.statusCode}');
      }
    } catch (error) {
      debugPrint('❌ Error fetching vehicles: $error');

      setState(() {
        _isCreatingPin = false;
        _errorMessage = _selectedLanguage == 'en'
            ? 'Connection error. Please try again.'
            : 'Erreur de connexion. Veuillez réessayer.';
        _pin = '';
        _confirmPin = '';
        _isConfirmStep = false;
      });
    }
  }

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
                      _selectedLanguage == 'en' ? 'Create Your PIN' : 'Créer votre PIN',
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
                          : 'Choisissez un code PIN à 4 chiffres pour la sécurité')
                          : (_selectedLanguage == 'en'
                          ? 'Confirm your 4-digit PIN'
                          : 'Confirmez votre code PIN à 4 chiffres'),
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
                        final currentPin = !_isConfirmStep ? _pin : _confirmPin;
                        final isFilled = index < currentPin.length;
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
                  if (_isCreatingPin)
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
                                ? 'Setting up your account...'
                                : 'Configuration de votre compte...',
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
            onTap: _isCreatingPin ? null : _onDeletePressed,
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
          onTap: _isCreatingPin ? null : () => _onNumberPressed(number),
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

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
}