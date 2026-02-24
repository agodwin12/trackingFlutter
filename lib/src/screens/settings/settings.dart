// lib/src/screens/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utility/app_theme.dart';
import '../contact us/contact_us.dart';
import '../login/login.dart';
import '../profile/profile.dart';
import '../subscriptions/renewal_payment_screen.dart';
import '../vehicles/my_cars.dart';
import 'services/settings_service.dart';
import 'widgets/settings_pin_dialogs.dart';
import 'widgets/settings_skeleton.dart';
import 'widgets/settings_widgets.dart';

class SettingsScreen extends StatefulWidget {
  final int? vehicleId;

  const SettingsScreen({Key? key, this.vehicleId}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;

  // User data
  int? _userId;
  int? _userVehicleId;
  String _userType = 'regular';

  // Alert settings
  bool _geofenceAlerts = true;
  bool _safeZoneAlerts = true;
  bool _tripTracking = false;

  // Language
  String _selectedLanguage = 'en';

  // PIN
  bool _hasPinSet = false;

  @override
  void initState() {
    super.initState();
    _initSettings();
  }

  // ========== INIT ==========
  Future<void> _initSettings() async {
    await _redirectIfLoggedOut();
    await _loadLanguagePreference();
    await _loadUserData();
    await _loadSettings();
  }

  Future<void> _redirectIfLoggedOut() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('accessToken');
    final uid = prefs.getInt('user_id');

    if (token == null || uid == null) {
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
      }
    }
  }

  Future<void> _loadLanguagePreference() async {
    final lang = await SettingsService.loadLanguage();
    if (mounted) setState(() => _selectedLanguage = lang);
  }

  // ========== LOAD USER DATA ==========
  // ✅ Reads vehicle ID from SharedPreferences — works for both
  // regular users and chauffeurs without any API call
  Future<void> _loadUserData() async {
    try {
      final userData = await SettingsService.loadUserData();

      if (userData == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      _userId = userData['id'];
      _userType = await SettingsService.loadUserType();

      // ✅ Read vehicle ID from SharedPreferences, no API call needed
      _userVehicleId = await SettingsService.loadCurrentVehicleId(
        fallback: widget.vehicleId,
      );

      debugPrint('✅ User ID: $_userId | Type: $_userType | Vehicle: $_userVehicleId');

      // Check PIN status
      if (_userId != null) {
        final hasPinSet = await SettingsService.checkPinStatus(_userId!);
        if (mounted) setState(() => _hasPinSet = hasPinSet);
      }
    } catch (e) {
      debugPrint('🔥 Error loading user data: $e');
    }
  }

  // ========== LOAD SETTINGS ==========
  Future<void> _loadSettings() async {
    try {
      final settings = await SettingsService.loadSettings(_userId);

      if (mounted) {
        setState(() {
          _geofenceAlerts = settings['geofenceAlerts'] as bool;
          _safeZoneAlerts = settings['safeZoneAlerts'] as bool;
          _tripTracking = settings['tripTracking'] as bool;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('🔥 Error loading settings: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ========== SAVE SETTINGS ==========
  Future<void> _saveSettings({
    required String settingName,
    required bool settingValue,
  }) async {
    setState(() => _isSaving = true);

    try {
      await SettingsService.saveSettingsLocally(
        geofenceAlerts: _geofenceAlerts,
        safeZoneAlerts: _safeZoneAlerts,
        tripTracking: _tripTracking,
      );

      // Trip tracking requires a backend sync
      if (settingName == 'Trip Tracking' && _userId != null) {
        try {
          await SettingsService.saveTripTracking(_userId!, _tripTracking);
        } catch (e) {
          debugPrint('🔥 Backend save failed: $e');

          // Revert toggle on failure
          setState(() => _tripTracking = !_tripTracking);
          await SettingsService.saveSettingsLocally(
            geofenceAlerts: _geofenceAlerts,
            safeZoneAlerts: _safeZoneAlerts,
            tripTracking: _tripTracking,
          );

          _showSnack(
            _selectedLanguage == 'en'
                ? 'Failed to save setting. Please try again.'
                : 'Échec de l\'enregistrement. Veuillez réessayer.',
            AppColors.error,
          );
          return;
        }
      }

      _showToggleNotification(settingName, settingValue);
    } catch (e) {
      debugPrint('🔥 Error saving settings: $e');
      _showSnack(
        _selectedLanguage == 'en'
            ? 'Failed to save settings'
            : 'Échec de l\'enregistrement',
        AppColors.error,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ========== LANGUAGE ==========
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
              _selectedLanguage == 'en'
                  ? 'Select Language'
                  : 'Choisir la langue',
              style: AppTypography.h3.copyWith(fontSize: 18),
            ),
            SizedBox(height: AppSizes.spacingL),
            LanguageOptionTile(
              languageCode: 'en',
              languageName: 'English',
              flagEmoji: '🇺🇸',
              isSelected: _selectedLanguage == 'en',
              onTap: () => _changeLanguage('en'),
            ),
            SizedBox(height: AppSizes.spacingM),
            LanguageOptionTile(
              languageCode: 'fr',
              languageName: 'Français',
              flagEmoji: '🇫🇷',
              isSelected: _selectedLanguage == 'fr',
              onTap: () => _changeLanguage('fr'),
            ),
            SizedBox(height: AppSizes.spacingL),
          ],
        ),
      ),
    );
  }

  Future<void> _changeLanguage(String languageCode) async {
    await SettingsService.saveLanguage(languageCode);
    if (mounted) setState(() => _selectedLanguage = languageCode);
    Navigator.pop(context);
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) Navigator.pop(context, 'language_changed');
  }

  // ========== LOGOUT ==========
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
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.logout_rounded,
                  color: AppColors.error, size: 20),
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
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
      await SettingsService.logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => ModernLoginScreen()),
              (route) => false,
        );
      }
    }
  }

  // ========== HELPERS ==========
  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTypography.body2.copyWith(color: AppColors.white),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
        ),
        margin: EdgeInsets.all(AppSizes.spacingM),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showToggleNotification(String settingName, bool isEnabled) {
    String message;
    IconData icon;

    switch (settingName) {
      case 'Geofence Alerts':
        message = _selectedLanguage == 'en'
            ? (isEnabled
            ? 'Geofence alerts enabled'
            : 'Geofence alerts disabled')
            : (isEnabled
            ? 'Alertes géofence activées'
            : 'Alertes géofence désactivées');
        icon = Icons.radar_outlined;
        break;
      case 'Safe Zone Alerts':
        message = _selectedLanguage == 'en'
            ? (isEnabled
            ? 'Safe zone alerts enabled'
            : 'Safe zone alerts disabled')
            : (isEnabled
            ? 'Alertes Zone de sécurité activées'
            : 'Alertes Zone de sécurité désactivées');
        icon = Icons.shield_outlined;
        break;
      case 'Trip Tracking':
        message = _selectedLanguage == 'en'
            ? (isEnabled
            ? 'Trip tracking enabled'
            : 'Trip tracking disabled')
            : (isEnabled
            ? 'Suivi des trajets activé'
            : 'Suivi des trajets désactivé');
        icon = Icons.route_outlined;
        break;
      default:
        message = isEnabled
            ? (_selectedLanguage == 'en' ? 'Setting enabled' : 'Paramètre activé')
            : (_selectedLanguage == 'en' ? 'Setting disabled' : 'Paramètre désactivé');
        icon = Icons.check_circle;
    }

    final color = isEnabled ? AppColors.success : AppColors.warning;

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
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
        ),
        margin: EdgeInsets.all(AppSizes.spacingM),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ========== BUILD ==========
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SettingsSkeleton();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(AppSizes.spacingL),
                children: [
                  // ── ALERTS ────────────────────────────────────
                  SettingsSectionHeader(
                    title: _selectedLanguage == 'en' ? 'ALERTS' : 'ALERTES',
                  ),
                  SizedBox(height: AppSizes.spacingM),
                  SettingsToggleTile(
                    icon: Icons.radar_outlined,
                    title: _selectedLanguage == 'en'
                        ? 'Geofence Alerts'
                        : 'Alertes géofence',
                    subtitle: _selectedLanguage == 'en'
                        ? 'Get notified when vehicle leaves zone'
                        : 'Recevoir une notification quand le véhicule quitte la zone',
                    value: _geofenceAlerts,
                    onChanged: (value) {
                      setState(() => _geofenceAlerts = value);
                      _saveSettings(
                          settingName: 'Geofence Alerts',
                          settingValue: value);
                    },
                  ),
                  SettingsToggleTile(
                    icon: Icons.shield_outlined,
                    title: _selectedLanguage == 'en'
                        ? 'Safe Zone Alerts'
                        : 'Alertes Zone de sécurité',
                    subtitle: _selectedLanguage == 'en'
                        ? 'Get notified about safe zone activity'
                        : 'Recevoir des notifications d\'activité de Zone de sécurité',
                    value: _safeZoneAlerts,
                    onChanged: (value) {
                      setState(() => _safeZoneAlerts = value);
                      _saveSettings(
                          settingName: 'Safe Zone Alerts',
                          settingValue: value);
                    },
                  ),
                  SettingsToggleTile(
                    icon: Icons.route_outlined,
                    title: _selectedLanguage == 'en'
                        ? 'Trip Tracking'
                        : 'Suivi des trajets',
                    subtitle: _selectedLanguage == 'en'
                        ? 'Record and save vehicle trips'
                        : 'Enregistrer et sauvegarder les trajets',
                    value: _tripTracking,
                    onChanged: (value) {
                      setState(() => _tripTracking = value);
                      _saveSettings(
                          settingName: 'Trip Tracking', settingValue: value);
                    },
                  ),

                  SizedBox(height: AppSizes.spacingXL),

                  // ── SECURITY ──────────────────────────────────
                  SettingsSectionHeader(
                    title: _selectedLanguage == 'en' ? 'SECURITY' : 'SÉCURITÉ',
                  ),
                  SizedBox(height: AppSizes.spacingM),
                  SettingsTile(
                    icon: _hasPinSet
                        ? Icons.lock_reset
                        : Icons.lock_outline,
                    title: _hasPinSet
                        ? (_selectedLanguage == 'en'
                        ? 'Change PIN'
                        : 'Changer le PIN')
                        : (_selectedLanguage == 'en'
                        ? 'Create PIN'
                        : 'Créer un PIN'),
                    subtitle: _hasPinSet
                        ? (_selectedLanguage == 'en'
                        ? 'Update your app security PIN'
                        : 'Mettre à jour votre PIN de sécurité')
                        : (_selectedLanguage == 'en'
                        ? 'Set up a security PIN for app protection'
                        : 'Configurer un PIN de sécurité'),
                    onTap: () {
                      if (_userId == null) return;
                      if (_hasPinSet) {
                        PinDialogs.showChangePinDialog(
                          context: context,
                          userId: _userId!,
                          selectedLanguage: _selectedLanguage,
                        );
                      } else {
                        PinDialogs.showCreatePinDialog(
                          context: context,
                          userId: _userId!,
                          selectedLanguage: _selectedLanguage,
                          onPinCreated: () {
                            if (mounted) setState(() => _hasPinSet = true);
                          },
                        );
                      }
                    },
                  ),

                  SizedBox(height: AppSizes.spacingXL),

                  // ── ACCOUNT ───────────────────────────────────
                  SettingsSectionHeader(
                    title:
                    _selectedLanguage == 'en' ? 'ACCOUNT' : 'COMPTE',
                  ),
                  SizedBox(height: AppSizes.spacingM),
                  SettingsTile(
                    icon: Icons.person_outline,
                    title: _selectedLanguage == 'en' ? 'Profile' : 'Profil',
                    subtitle: _selectedLanguage == 'en'
                        ? 'Manage your profile information'
                        : 'Gérer vos informations de profil',
                    onTap: () {
                      // ✅ Uses vehicle ID from SharedPreferences
                      // works for both regular users and chauffeurs
                      if (_userVehicleId != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ProfileScreen(vehicleId: _userVehicleId!),
                          ),
                        );
                      } else {
                        _showSnack(
                          _selectedLanguage == 'en'
                              ? 'Unable to load profile. Please try again.'
                              : 'Impossible de charger le profil. Veuillez réessayer.',
                          AppColors.error,
                        );
                      }
                    },
                  ),
             //     SizedBox(height: AppSizes.spacingM),


                  // ── SUBSCRIPTION (TEMPORARILY DISABLED) ─────────────────────────
//
// SettingsTile(
//   icon: Icons.subscriptions_outlined,
//   title: _selectedLanguage == 'en' ? 'Subscription' : 'Abonnement',
//   subtitle: _selectedLanguage == 'en'
//       ? 'Manage your plan and renewals'
//       : 'Gérer votre forfait et renouvellements',
//   trailing: Container(
//     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//     decoration: BoxDecoration(
//       color: AppColors.success.withOpacity(0.1),
//       borderRadius: BorderRadius.circular(6),
//     ),
//     child: Text(
//       _selectedLanguage == 'en' ? 'ACTIVE' : 'ACTIF',
//       style: AppTypography.caption.copyWith(
//         color: AppColors.success,
//         fontWeight: FontWeight.bold,
//       ),
//     ),
//   ),
//   onTap: () {
//     if (_userId != null && _userVehicleId != null) {
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => RenewalPaymentScreen(
//             userId: _userId!,
//             vehicleId: _userVehicleId!,
//             currentExpiryDate: "Oct 20, 2027",
//           ),
//         ),
//       );
//     } else {
//       _showSnack(
//         _selectedLanguage == 'en'
//             ? 'Vehicle data not loaded'
//             : 'Données du véhicule non chargées',
//         AppColors.error,
//       );
//     }
//   },
// ),

                  SettingsTile(
                    icon: Icons.directions_car_outlined,
                    title: _selectedLanguage == 'en'
                        ? 'My Vehicles'
                        : 'Mes Véhicules',
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

                  // ── SUPPORT ───────────────────────────────────
                  SettingsSectionHeader(
                    title: 'SUPPORT',
                  ),
                  SizedBox(height: AppSizes.spacingM),
                  SettingsTile(
                    icon: Icons.headset_mic_outlined,
                    title: _selectedLanguage == 'en'
                        ? 'Contact Us'
                        : 'Nous contacter',
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

                  // ── LOGOUT ────────────────────────────────────
                  SettingsLogoutButton(
                    label: _selectedLanguage == 'en'
                        ? 'Logout'
                        : 'Déconnexion',
                    onTap: _handleLogout,
                  ),

                  SizedBox(height: AppSizes.spacingM),

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

  // ========== HEADER ==========
  Widget _buildHeader() {
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.spacingL,
        vertical: AppSizes.spacingM,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          SizedBox(width: AppSizes.spacingM),
          Expanded(
            child: Text(
              _selectedLanguage == 'en' ? 'Settings' : 'Paramètres',
              style: AppTypography.h3.copyWith(fontSize: 18),
            ),
          ),
          // Language selector button
          InkWell(
            onTap: _showLanguageSelector,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(8),
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
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(width: 4),
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
    );
  }
}