// lib/src/screens/settings/settings_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';
import '../contact us/contact_us.dart';
import '../login/login.dart';
import '../profile/profile.dart';
import '../vehicles/my_cars.dart';

class SettingsScreen extends StatefulWidget {
  final int? vehicleId;

  const SettingsScreen({Key? key, this.vehicleId}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;

  // User Data
  Map<String, dynamic>? _userData;
  String _userName = "";
  String _userEmail = "";
  String _userPhone = "";
  int? _userId;
  int? _userVehicleId;

  // Alert Settings
  bool _geofenceAlerts = true;
  bool _safeZoneAlerts = true;
  bool _tripTracking = false;

  // Language
  String _selectedLanguage = 'en'; // Default to English

  String get baseUrl => EnvConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
    _loadUserData();
    _loadSettings();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
    debugPrint('✅ Loaded language preference: $_selectedLanguage');
  }

  Future<void> _changeLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', languageCode);

    setState(() {
      _selectedLanguage = languageCode;
    });

    debugPrint('✅ Language changed to: $languageCode');

    // Close the bottom sheet
    Navigator.pop(context);

    // Wait a brief moment for the sheet to close, then return to Dashboard with result
    await Future.delayed(Duration(milliseconds: 100));

    // Pop back to Dashboard with language_changed result
    if (mounted) {
      Navigator.pop(context, 'language_changed');
    }
  }

  void _showLanguageSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(AppSizes.radiusXL),
            topRight: Radius.circular(AppSizes.radiusXL),
          ),
        ),
        padding: EdgeInsets.all(AppSizes.spacingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: AppSizes.spacingL),

            Text(
              _selectedLanguage == 'en' ? 'Select Language' : 'Choisir la langue',
              style: AppTypography.h3.copyWith(fontSize: 18),
            ),
            SizedBox(height: AppSizes.spacingL),

            // English Option
            _buildLanguageOption(
              languageCode: 'en',
              languageName: 'English',
              flagEmoji: '🇺🇸',
              isSelected: _selectedLanguage == 'en',
            ),

            SizedBox(height: AppSizes.spacingM),

            // French Option
            _buildLanguageOption(
              languageCode: 'fr',
              languageName: 'Français',
              flagEmoji: '🇫🇷',
              isSelected: _selectedLanguage == 'fr',
            ),

            SizedBox(height: AppSizes.spacingL),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption({
    required String languageCode,
    required String languageName,
    required String flagEmoji,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () => _changeLanguage(languageCode),
      borderRadius: BorderRadius.circular(AppSizes.radiusL),
      child: Container(
        padding: EdgeInsets.all(AppSizes.spacingM),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.background,
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Flag
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
                border: Border.all(color: AppColors.border),
              ),
              child: Center(
                child: Text(
                  flagEmoji,
                  style: TextStyle(fontSize: 32),
                ),
              ),
            ),
            SizedBox(width: AppSizes.spacingM),

            // Language Name
            Expanded(
              child: Text(
                languageName,
                style: AppTypography.body1.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: isSelected ? AppColors.primary : AppColors.black,
                ),
              ),
            ),

            // Check mark if selected
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: AppColors.primary,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');

      if (userDataString != null) {
        final userData = jsonDecode(userDataString);

        if (mounted) {
          setState(() {
            _userData = userData;
            _userId = userData['id'];
            _userName = "${userData['prenom'] ?? ''} ${userData['nom'] ?? ''}".trim();
            _userEmail = userData['email'] ?? '';
            _userPhone = userData['phone'] ?? '';
          });
        }

        debugPrint('✅ User data loaded: $_userName (ID: $_userId)');
        await _fetchUserVehicle();
      } else {
        debugPrint('⚠️ No user data found in SharedPreferences');
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('🔥 Error loading user data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchUserVehicle() async {
    try {
      if (_userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      debugPrint('📡 Fetching vehicles for user: $_userId');

      final response = await http.get(
        Uri.parse('$baseUrl/voitures/user/$_userId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final vehicles = data['vehicles'] as List;

          if (vehicles.isNotEmpty && mounted) {
            setState(() {
              _userVehicleId = widget.vehicleId ?? vehicles[0]['id'];
              _isLoading = false;
            });

            debugPrint('✅ Vehicle ID loaded: $_userVehicleId');
          } else {
            debugPrint('⚠️ No vehicles found for user');
            if (mounted) {
              setState(() => _isLoading = false);
            }
          }
        }
      } else {
        debugPrint('⚠️ Failed to fetch vehicles: ${response.statusCode}');
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('🔥 Error fetching user vehicle: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        _geofenceAlerts = prefs.getBool('geofence_alerts') ?? true;
        _safeZoneAlerts = prefs.getBool('safe_zone_alerts') ?? true;
        _tripTracking = prefs.getBool('trip_tracking') ?? false;
      });

      debugPrint('✅ Settings loaded from cache');

      if (_userId != null) {
        await _fetchSettingsFromBackend();
      }
    } catch (e) {
      debugPrint('🔥 Error loading settings: $e');
    }
  }

  Future<void> _fetchSettingsFromBackend() async {
    try {
      debugPrint('📡 Fetching settings from backend for user: $_userId');

      final response = await http.get(
        Uri.parse('$baseUrl/users-settings/$_userId/settings'),
        headers: {'Content-Type': 'application/json'},
      );

      debugPrint('📡 Response status: ${response.statusCode}');
      debugPrint('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final settings = data['data']['settings'];

          if (mounted) {
            setState(() {
              _tripTracking = settings['tripTrackingEnabled'] ?? false;
            });
          }

          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('trip_tracking', _tripTracking);

          debugPrint('✅ Settings synced from backend - Trip Tracking: $_tripTracking');
        }
      } else {
        debugPrint('⚠️ Failed to fetch settings: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('🔥 Error fetching settings from backend: $e');
    }
  }

  Future<void> _saveTripTrackingToBackend(bool enabled) async {
    try {
      debugPrint('💾 Saving trip tracking to backend: $enabled');

      final response = await http.put(
        Uri.parse('$baseUrl/users-settings/$_userId/settings/trip-tracking'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'enabled': enabled}),
      );

      debugPrint('📡 Response status: ${response.statusCode}');
      debugPrint('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          debugPrint('✅ Trip tracking saved to backend successfully');
          return;
        }
      }

      throw Exception('Failed to save trip tracking: ${response.statusCode}');
    } catch (e) {
      debugPrint('🔥 Error saving trip tracking to backend: $e');
      rethrow;
    }
  }

  Future<void> _saveSettings({String? settingName, bool? settingValue}) async {
    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('geofence_alerts', _geofenceAlerts);
      await prefs.setBool('safe_zone_alerts', _safeZoneAlerts);
      await prefs.setBool('trip_tracking', _tripTracking);

      debugPrint('✅ Settings saved locally');

      bool backendSaveSuccessful = true;

      if (settingName == 'Trip Tracking' && _userId != null) {
        try {
          await _saveTripTrackingToBackend(_tripTracking);
          debugPrint('✅ Trip tracking saved to backend');
        } catch (e) {
          debugPrint('🔥 Backend save failed: $e');
          backendSaveSuccessful = false;

          setState(() {
            _tripTracking = !_tripTracking;
          });

          await prefs.setBool('trip_tracking', _tripTracking);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.white, size: 20),
                    SizedBox(width: AppSizes.spacingM),
                    Expanded(
                      child: Text(
                        _selectedLanguage == 'en'
                            ? 'Failed to save setting. Please try again.'
                            : 'Échec de l\'enregistrement. Veuillez réessayer.',
                        style: AppTypography.body2.copyWith(color: AppColors.white),
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
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      }

      if (mounted && settingName != null && settingValue != null && backendSaveSuccessful) {
        _showToggleNotification(settingName, settingValue);
      }
    } catch (e) {
      debugPrint('🔥 Error saving settings: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.white, size: 20),
                SizedBox(width: AppSizes.spacingM),
                Text(
                  _selectedLanguage == 'en'
                      ? 'Failed to save settings'
                      : 'Échec de l\'enregistrement',
                  style: AppTypography.body2.copyWith(color: AppColors.white),
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
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showToggleNotification(String settingName, bool isEnabled) {
    String message;
    IconData icon;
    Color backgroundColor;

    switch (settingName) {
      case 'Geofence Alerts':
        message = _selectedLanguage == 'en'
            ? (isEnabled ? 'Geofence alerts enabled' : 'Geofence alerts disabled')
            : (isEnabled ? 'Alertes géofence activées' : 'Alertes géofence désactivées');
        icon = Icons.radar_outlined;
        break;
      case 'Safe Zone Alerts':
        message = _selectedLanguage == 'en'
            ? (isEnabled ? 'Safe zone alerts enabled' : 'Safe zone alerts disabled')
            : (isEnabled ? 'Alertes zone sûre activées' : 'Alertes zone sûre désactivées');
        icon = Icons.shield_outlined;
        break;
      case 'Trip Tracking':
        message = _selectedLanguage == 'en'
            ? (isEnabled
            ? 'Trip tracking enabled - Trips will be recorded'
            : 'Trip tracking disabled - Trips will NOT be recorded')
            : (isEnabled
            ? 'Suivi des trajets activé - Les trajets seront enregistrés'
            : 'Suivi des trajets désactivé - Les trajets ne seront PAS enregistrés');
        icon = Icons.route_outlined;
        break;
      default:
        message = _selectedLanguage == 'en'
            ? (isEnabled ? 'Setting enabled' : 'Setting disabled')
            : (isEnabled ? 'Paramètre activé' : 'Paramètre désactivé');
        icon = Icons.check_circle;
    }

    backgroundColor = isEnabled ? AppColors.success : AppColors.warning;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: AppColors.white, size: 20),
            SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Text(
                message,
                style: AppTypography.body2.copyWith(color: AppColors.white),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
        ),
        margin: EdgeInsets.all(AppSizes.spacingM),
        duration: Duration(seconds: 3),
      ),
    );
  }

  // ========================================
  // CHANGE PIN DIALOG
  // ========================================
  void _showChangePinDialog() {
    final TextEditingController currentPinController = TextEditingController();
    final TextEditingController newPinController = TextEditingController();
    final TextEditingController confirmPinController = TextEditingController();

    bool isCurrentPinVisible = false;
    bool isNewPinVisible = false;
    bool isConfirmPinVisible = false;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusL),
              ),
              contentPadding: EdgeInsets.all(AppSizes.spacingL),
              title: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_reset,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: AppSizes.spacingM),
                  Text(
                    _selectedLanguage == 'en' ? 'Change PIN' : 'Changer le PIN',
                    style: AppTypography.subtitle1.copyWith(fontSize: 16),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedLanguage == 'en'
                          ? 'Enter your current PIN and choose a new one'
                          : 'Entrez votre PIN actuel et choisissez-en un nouveau',
                      style: AppTypography.body2.copyWith(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: AppSizes.spacingL),

                    // Current PIN Field
                    Text(
                      _selectedLanguage == 'en' ? 'Current PIN' : 'PIN actuel',
                      style: AppTypography.body2.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: AppSizes.spacingS),
                    TextField(
                      controller: currentPinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: !isCurrentPinVisible,
                      decoration: InputDecoration(
                        hintText: '••••',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSizes.radiusM),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSizes.spacingM,
                          vertical: AppSizes.spacingS,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            isCurrentPinVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 20,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              isCurrentPinVisible = !isCurrentPinVisible;
                            });
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: AppSizes.spacingM),

                    // New PIN Field
                    Text(
                      _selectedLanguage == 'en' ? 'New PIN' : 'Nouveau PIN',
                      style: AppTypography.body2.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: AppSizes.spacingS),
                    TextField(
                      controller: newPinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: !isNewPinVisible,
                      decoration: InputDecoration(
                        hintText: '••••',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSizes.radiusM),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSizes.spacingM,
                          vertical: AppSizes.spacingS,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            isNewPinVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 20,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              isNewPinVisible = !isNewPinVisible;
                            });
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: AppSizes.spacingM),

                    // Confirm PIN Field
                    Text(
                      _selectedLanguage == 'en'
                          ? 'Confirm New PIN'
                          : 'Confirmer le nouveau PIN',
                      style: AppTypography.body2.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: AppSizes.spacingS),
                    TextField(
                      controller: confirmPinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: !isConfirmPinVisible,
                      decoration: InputDecoration(
                        hintText: '••••',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSizes.radiusM),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSizes.spacingM,
                          vertical: AppSizes.spacingS,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            isConfirmPinVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 20,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              isConfirmPinVisible = !isConfirmPinVisible;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: Text(
                    _selectedLanguage == 'en' ? 'Cancel' : 'Annuler',
                    style: AppTypography.body2.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                    // Validate inputs
                    if (currentPinController.text.length != 4) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _selectedLanguage == 'en'
                                ? 'Please enter your current PIN'
                                : 'Veuillez entrer votre PIN actuel',
                          ),
                          backgroundColor: AppColors.error,
                        ),
                      );
                      return;
                    }

                    if (newPinController.text.length != 4) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _selectedLanguage == 'en'
                                ? 'New PIN must be 4 digits'
                                : 'Le nouveau PIN doit contenir 4 chiffres',
                          ),
                          backgroundColor: AppColors.error,
                        ),
                      );
                      return;
                    }

                    if (newPinController.text != confirmPinController.text) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _selectedLanguage == 'en'
                                ? 'PINs do not match'
                                : 'Les PINs ne correspondent pas',
                          ),
                          backgroundColor: AppColors.error,
                        ),
                      );
                      return;
                    }

                    if (currentPinController.text == newPinController.text) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _selectedLanguage == 'en'
                                ? 'New PIN must be different from current PIN'
                                : 'Le nouveau PIN doit être différent du PIN actuel',
                          ),
                          backgroundColor: AppColors.error,
                        ),
                      );
                      return;
                    }

                    setDialogState(() {
                      isLoading = true;
                    });

                    try {
                      await _changePin(
                        currentPinController.text,
                        newPinController.text,
                      );

                      Navigator.pop(dialogContext);

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                Icon(Icons.check_circle, color: AppColors.white, size: 20),
                                SizedBox(width: AppSizes.spacingM),
                                Expanded(
                                  child: Text(
                                    _selectedLanguage == 'en'
                                        ? 'PIN changed successfully'
                                        : 'PIN changé avec succès',
                                    style: AppTypography.body2.copyWith(color: AppColors.white),
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
                    } catch (e) {
                      setDialogState(() {
                        isLoading = false;
                      });

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                Icon(Icons.error_outline, color: AppColors.white, size: 20),
                                SizedBox(width: AppSizes.spacingM),
                                Expanded(
                                  child: Text(
                                    e.toString(),
                                    style: AppTypography.body2.copyWith(color: AppColors.white),
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
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusM),
                    ),
                    elevation: 0,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: isLoading
                      ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  )
                      : Text(
                    _selectedLanguage == 'en' ? 'Change' : 'Changer',
                    style: AppTypography.body2.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _changePin(String currentPin, String newPin) async {
    try {
      debugPrint('🔐 Changing PIN for user: $_userId');

      final response = await http.post(
        Uri.parse('$baseUrl/pin/change'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': _userId,
          'oldPin': currentPin,
          'newPin': newPin,
        }),
      );

      debugPrint('📡 Change PIN Response status: ${response.statusCode}');
      debugPrint('📡 Change PIN Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          debugPrint('✅ PIN changed successfully');
          return;
        } else {
          throw Exception(
            _selectedLanguage == 'en'
                ? (data['message'] ?? 'Failed to change PIN')
                : (data['message'] ?? 'Échec du changement de PIN'),
          );
        }
      } else if (response.statusCode == 400 || response.statusCode == 401) {
        final data = jsonDecode(response.body);
        throw Exception(
          _selectedLanguage == 'en'
              ? 'Current PIN is incorrect'
              : 'Le PIN actuel est incorrect',
        );
      } else {
        throw Exception(
          _selectedLanguage == 'en'
              ? 'Failed to change PIN. Please try again.'
              : 'Échec du changement de PIN. Veuillez réessayer.',
        );
      }
    } catch (e) {
      debugPrint('🔥 Error changing PIN: $e');
      rethrow;
    }
  }

  Future<void> _handleLogout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
        ),
        contentPadding: EdgeInsets.all(AppSizes.spacingL),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.logout_rounded,
                color: AppColors.error,
                size: 20,
              ),
            ),
            SizedBox(width: AppSizes.spacingM),
            Text(
              _selectedLanguage == 'en' ? 'Logout' : 'Déconnexion',
              style: AppTypography.subtitle1.copyWith(fontSize: 16),
            ),
          ],
        ),
        content: Text(
          _selectedLanguage == 'en'
              ? 'Are you sure you want to logout?'
              : 'Êtes-vous sûr de vouloir vous déconnecter ?',
          style: AppTypography.body2.copyWith(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              _selectedLanguage == 'en' ? 'Cancel' : 'Annuler',
              style: AppTypography.body2.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
              elevation: 0,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              _selectedLanguage == 'en' ? 'Logout' : 'Déconnexion',
              style: AppTypography.body2.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _performLogout();
    }
  }

  Future<void> _performLogout() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove('user');
      await prefs.remove('accessToken');
      await prefs.remove('refreshToken');
      await prefs.remove('userId');

      debugPrint('✅ User logged out successfully');

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => ModernLoginScreen(),
          ),
              (route) => false,
        );
      }
    } catch (e) {
      debugPrint('🔥 Error during logout: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header with Language Selector
            Container(
              color: AppColors.white,
              padding: EdgeInsets.symmetric(
                horizontal: AppSizes.spacingL,
                vertical: AppSizes.spacingM,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded, size: 22),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                  SizedBox(width: AppSizes.spacingM),
                  Expanded(
                    child: Text(
                      _selectedLanguage == 'en' ? 'Settings' : 'Paramètres',
                      style: AppTypography.h3.copyWith(fontSize: 18),
                    ),
                  ),
                  // Language Flag Button
                  InkWell(
                    onTap: _showLanguageSelector,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedLanguage == 'en' ? '🇺🇸' : '🇫🇷',
                            style: TextStyle(fontSize: 24),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isSaving) ...[
                    SizedBox(width: AppSizes.spacingM),
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: EdgeInsets.all(AppSizes.spacingL),
                children: [
                  // Alerts Section
                  _buildSectionHeader(
                    _selectedLanguage == 'en' ? 'ALERTS' : 'ALERTES',
                  ),
                  SizedBox(height: AppSizes.spacingM),
                  _buildSettingsTile(
                    icon: Icons.radar_outlined,
                    title: _selectedLanguage == 'en' ? 'Geofence Alerts' : 'Alertes géofence',
                    subtitle: _selectedLanguage == 'en'
                        ? 'Get notified when vehicle leaves zone'
                        : 'Recevoir une notification quand le véhicule quitte la zone',
                    trailing: Transform.scale(
                      scale: 0.85,
                      child: Switch(
                        value: _geofenceAlerts,
                        onChanged: (value) {
                          setState(() {
                            _geofenceAlerts = value;
                          });
                          _saveSettings(
                            settingName: 'Geofence Alerts',
                            settingValue: value,
                          );
                        },
                        activeColor: AppColors.white,
                        activeTrackColor: AppColors.success,
                        inactiveThumbColor: AppColors.white,
                        inactiveTrackColor: AppColors.error,
                      ),
                    ),
                  ),
                  _buildSettingsTile(
                    icon: Icons.shield_outlined,
                    title: _selectedLanguage == 'en' ? 'Safe Zone Alerts' : 'Alertes zone sûre',
                    subtitle: _selectedLanguage == 'en'
                        ? 'Get notified about safe zone activity'
                        : 'Recevoir des notifications d\'activité de zone sûre',
                    trailing: Transform.scale(
                      scale: 0.85,
                      child: Switch(
                        value: _safeZoneAlerts,
                        onChanged: (value) {
                          setState(() {
                            _safeZoneAlerts = value;
                          });
                          _saveSettings(
                            settingName: 'Safe Zone Alerts',
                            settingValue: value,
                          );
                        },
                        activeColor: AppColors.white,
                        activeTrackColor: AppColors.success,
                        inactiveThumbColor: AppColors.white,
                        inactiveTrackColor: AppColors.error,
                      ),
                    ),
                  ),
                  _buildSettingsTile(
                    icon: Icons.route_outlined,
                    title: _selectedLanguage == 'en' ? 'Trip Tracking' : 'Suivi des trajets',
                    subtitle: _selectedLanguage == 'en'
                        ? 'Record and save vehicle trips'
                        : 'Enregistrer et sauvegarder les trajets',
                    trailing: Transform.scale(
                      scale: 0.85,
                      child: Switch(
                        value: _tripTracking,
                        onChanged: (value) {
                          setState(() {
                            _tripTracking = value;
                          });
                          _saveSettings(
                            settingName: 'Trip Tracking',
                            settingValue: value,
                          );
                        },
                        activeColor: AppColors.white,
                        activeTrackColor: AppColors.success,
                        inactiveThumbColor: AppColors.white,
                        inactiveTrackColor: AppColors.error,
                      ),
                    ),
                  ),

                  SizedBox(height: AppSizes.spacingXL),

                  // Security Section
                  _buildSectionHeader(
                    _selectedLanguage == 'en' ? 'SECURITY' : 'SÉCURITÉ',
                  ),
                  SizedBox(height: AppSizes.spacingM),
                  _buildSettingsTile(
                    icon: Icons.lock_reset,
                    title: _selectedLanguage == 'en' ? 'Change PIN' : 'Changer le PIN',
                    subtitle: _selectedLanguage == 'en'
                        ? 'Update your app security PIN'
                        : 'Mettre à jour votre PIN de sécurité',
                    onTap: _showChangePinDialog,
                  ),

                  SizedBox(height: AppSizes.spacingXL),

                  // Account Section
                  _buildSectionHeader(
                    _selectedLanguage == 'en' ? 'ACCOUNT' : 'COMPTE',
                  ),
                  SizedBox(height: AppSizes.spacingM),
                  _buildSettingsTile(
                    icon: Icons.person_outline,
                    title: _selectedLanguage == 'en' ? 'Profile' : 'Profil',
                    subtitle: _selectedLanguage == 'en'
                        ? 'Manage your profile information'
                        : 'Gérer vos informations de profil',
                    onTap: () {
                      if (_userVehicleId != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfileScreen(vehicleId: _userVehicleId!),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _selectedLanguage == 'en'
                                  ? 'Unable to load profile. Please try again.'
                                  : 'Impossible de charger le profil. Veuillez réessayer.',
                            ),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    },
                  ),
                  _buildSettingsTile(
                    icon: Icons.directions_car_outlined,
                    title: _selectedLanguage == 'en' ? 'My Vehicles' : 'Mes Véhicules',
                    subtitle: _selectedLanguage == 'en'
                        ? 'View and manage your vehicles'
                        : 'Voir et gérer vos véhicules',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MyCarsScreen(),
                        ),
                      );
                    },
                  ),

                  SizedBox(height: AppSizes.spacingXL),

                  // Support Section
                  _buildSectionHeader(
                    _selectedLanguage == 'en' ? 'SUPPORT' : 'SUPPORT',
                  ),
                  SizedBox(height: AppSizes.spacingM),
                  _buildSettingsTile(
                    icon: Icons.headset_mic_outlined,
                    title: _selectedLanguage == 'en' ? 'Contact Us' : 'Nous contacter',
                    subtitle: _selectedLanguage == 'en'
                        ? 'Get help and support'
                        : 'Obtenir de l\'aide et du support',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ContactScreen(),
                        ),
                      );
                    },
                  ),

                  SizedBox(height: AppSizes.spacingXL),

                  // Logout Button
                  _buildLogoutButton(),

                  SizedBox(height: AppSizes.spacingL),

                  // Version Info
                  Center(
                    child: Text(
                      'Version 1.0.0',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: AppTypography.caption.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: AppSizes.spacingS),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
        title: Text(
          title,
          style: AppTypography.body1.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: AppTypography.caption.copyWith(
            fontSize: 12,
          ),
        ),
        trailing: trailing ??
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSizes.spacingM,
          vertical: AppSizes.spacingS,
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        border: Border.all(color: AppColors.error, width: 1),
      ),
      child: ListTile(
        onTap: _handleLogout,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.logout_rounded, color: AppColors.error, size: 22),
        ),
        title: Text(
          _selectedLanguage == 'en' ? 'Logout' : 'Déconnexion',
          style: AppTypography.body1.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: AppColors.error,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSizes.spacingM,
          vertical: AppSizes.spacingS,
        ),
      ),
    );
  }
}