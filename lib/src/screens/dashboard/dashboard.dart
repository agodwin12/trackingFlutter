// lib/screens/dashboard/dashboard.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracking/src/screens/dashboard/services/dashboard_controller.dart';
import 'package:tracking/src/screens/dashboard/widgets/dashboard_widget.dart';
import 'package:tracking/src/screens/dashboard/widgets/dashboard_skeleton.dart';
import '../../core/utility/app_theme.dart';

import '../settings/settings.dart';
import '../stoeln vehicle/stolen_alert.dart';
import '../trip/trip_screen.dart';

class ModernDashboard extends StatefulWidget {
  final int vehicleId;

  const ModernDashboard({Key? key, required this.vehicleId}) : super(key: key);

  @override
  State<ModernDashboard> createState() => _ModernDashboardState();
}

class _ModernDashboardState extends State<ModernDashboard> with TickerProviderStateMixin {
  late DashboardController _controller;
  StreamSubscription<Map<String, dynamic>>? _alertSubscription;
  String _selectedLanguage = 'en';

  // Animation controllers for micro-interactions
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _saveCurrentVehicleId();
    _loadLanguagePreference();
    _controller = DashboardController(widget.vehicleId);
    _controller.initialize();

    // Setup pulse animation for online indicator
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )
      ..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _alertSubscription = _controller.safeZoneAlertStream.listen((alertData) {
      if (mounted) {
        _showSafeZoneAlert(alertData);
      }
    });
  }

  Future<void> _saveCurrentVehicleId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_vehicle_id', widget.vehicleId);
      debugPrint(
          '🚗 Saved current vehicle ID for PIN lock: ${widget.vehicleId}');
    } catch (e) {
      debugPrint('⚠️ Error saving vehicle ID: $e');
    }
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _alertSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _showSafeZoneAlert(Map<String, dynamic> alertData) {
    final title = alertData['title'] ?? (_selectedLanguage == 'en'
        ? 'Safe Zone Alert'
        : 'Alerte zone sécurisée');
    final message = alertData['message'] ?? (_selectedLanguage == 'en'
        ? 'Vehicle left safe zone'
        : 'Véhicule a quitté la zone sécurisée');
    final severity = alertData['severity'] ?? 'warning';

    Color backgroundColor;
    Color textColor = Colors.white;
    IconData icon;

    if (severity == 'warning') {
      backgroundColor = const Color(0xFFF59E0B);
      icon = Icons.warning_amber_rounded;
    } else if (severity == 'info') {
      backgroundColor = const Color(0xFF10B981);
      icon = Icons.check_circle_rounded;
    } else {
      backgroundColor = AppColors.error;
      icon = Icons.notifications_active_rounded;
    }

    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: backgroundColor,
        padding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: textColor, size: 24),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: AppTypography.subtitle1.copyWith(
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: AppTypography.body2.copyWith(
                  color: textColor.withOpacity(0.95)),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            },
            icon: Icon(Icons.close_rounded, color: textColor, size: 18),
            label: Text(
              _selectedLanguage == 'en' ? 'DISMISS' : 'FERMER',
              style: AppTypography.button.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) {
        try {
          ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
        } catch (e) {
          debugPrint('⚠️ Error dismissing banner: $e');
        }
      }
    });
  }

  void _handleGeofenceToggle() async {
    final success = await _controller.toggleGeofence();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons
                  .error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Text(
                success
                    ? (_controller.geofenceEnabled
                    ? (_selectedLanguage == 'en'
                    ? 'Geofencing enabled'
                    : 'Géofence activée')
                    : (_selectedLanguage == 'en'
                    ? 'Geofencing disabled'
                    : 'Géofence désactivée'))
                    : (_selectedLanguage == 'en'
                    ? 'Failed to toggle geofencing'
                    : 'Échec'),
                style: AppTypography.body2.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: success
            ? (_controller.geofenceEnabled
            ? const Color(0xFF10B981)
            : const Color(0xFF64748B))
            : AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _handleSafeZoneToggle() async {
    final result = await _controller.toggleSafeZone();

    if (!mounted) return;

    if (result['success']) {
      final bool wasCreated = _controller.safeZoneEnabled;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: AppSizes.spacingM),
              Expanded(
                child: Text(
                  wasCreated
                      ? (_selectedLanguage == 'en'
                      ? 'Safe Zone created!'
                      : 'Zone sécurisée créée!')
                      : (_selectedLanguage == 'en'
                      ? 'Safe Zone deleted'
                      : 'Zone supprimée'),
                  style: AppTypography.body2.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: wasCreated ? const Color(0xFF10B981) : const Color(
              0xFF64748B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } else {
      final errorMessage = result['message'] ?? (_selectedLanguage == 'en'
          ? 'Failed to toggle safe zone'
          : 'Échec');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  void _handleEngineToggle() async {
    final success = await _controller.toggleEngine();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons
                  .error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Text(
                success
                    ? (_controller.engineOn
                    ? (_selectedLanguage == 'en'
                    ? 'Engine unlocked'
                    : 'Moteur déverrouillé')
                    : (_selectedLanguage == 'en'
                    ? 'Engine locked'
                    : 'Moteur verrouillé'))
                    : (_selectedLanguage == 'en'
                    ? 'Failed to toggle engine'
                    : 'Échec'),
                style: AppTypography.body2.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: success
            ? (_controller.engineOn ? const Color(0xFF10B981) : AppColors.error)
            : AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: success ? 2 : 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _handleReportStolen() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.error,
                    size: 28,
                  ),
                ),
                SizedBox(width: AppSizes.spacingM),
                Expanded(
                  child: Text(
                    _selectedLanguage == 'en'
                        ? 'Report Stolen?'
                        : 'Signaler Volé?',
                    style: AppTypography.h3,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedLanguage == 'en' ? 'This will:' : 'Cela va:',
                  style: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w600),
                ),
                SizedBox(height: AppSizes.spacingM),
                _buildConfirmationItem(
                  Icons.power_settings_new_rounded,
                  _selectedLanguage == 'en'
                      ? 'Disable engine immediately'
                      : 'Désactiver le moteur',
                ),
                _buildConfirmationItem(
                  Icons.notification_add_rounded,
                  _selectedLanguage == 'en'
                      ? 'Create theft alert'
                      : 'Créer alerte de vol',
                ),
                _buildConfirmationItem(
                  Icons.my_location_rounded,
                  _selectedLanguage == 'en'
                      ? 'Show vehicle location'
                      : 'Afficher localisation',
                ),
                _buildConfirmationItem(
                  Icons.local_police_rounded,
                  _selectedLanguage == 'en'
                      ? 'Show nearby police'
                      : 'Afficher police',
                ),
                SizedBox(height: AppSizes.spacingM),
                Container(
                  padding: EdgeInsets.all(AppSizes.spacingM),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: AppColors.error,
                          size: 20),
                      SizedBox(width: AppSizes.spacingS),
                      Expanded(
                        child: Text(
                          _selectedLanguage == 'en'
                              ? 'This action cannot be undone'
                              : 'Action irréversible',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                ),
                child: Text(
                  _selectedLanguage == 'en' ? 'Cancel' : 'Annuler',
                  style: AppTypography.button.copyWith(
                      color: AppColors.textSecondary),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _selectedLanguage == 'en' ? 'Report Stolen' : 'Signaler',
                  style: AppTypography.button.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
    );

    if (confirmed != true) return;

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 3),
                  const SizedBox(height: 24),
                  Text(
                    _selectedLanguage == 'en'
                        ? 'Reporting stolen vehicle...'
                        : 'Signalement en cours...',
                    style: AppTypography.body1.copyWith(
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
    );

    final success = await _controller.reportStolen();

    if (!mounted) return;
    Navigator.pop(context);

    if (success) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              StolenAlertScreen(
                vehicleId: _controller.selectedVehicleId,
                vehicleLat: _controller.vehicleLat,
                vehicleLng: _controller.vehicleLng,
                vehicleName: _controller.selectedVehicle?.nickname.isNotEmpty ==
                    true
                    ? _controller.selectedVehicle!.nickname
                    : '${_controller.selectedVehicle?.brand ?? ''} ${_controller
                    .selectedVehicle?.model ?? ''}'.trim(),
              ),
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedLanguage == 'en'
                      ? 'Vehicle reported as stolen'
                      : 'Véhicule signalé volé',
                  style: AppTypography.body1.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedLanguage == 'en'
                      ? 'Failed to report. Try again.'
                      : 'Échec. Réessayez.',
                  style: AppTypography.body1.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Widget _buildConfirmationItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF10B981), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: AppTypography.body2),
          ),
        ],
      ),
    );
  }

  void _showVehicleSelectorModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) =>
          VehicleSelectorModal(
            controller: _controller,
            onVehicleSelected: (vehicleId) {
              _controller.onVehicleSelected(vehicleId);
            },
            selectedLanguage: _selectedLanguage,
          ),
    );
  }

  void _showEngineConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          EngineConfirmDialog(
            controller: _controller,
            onConfirm: _handleEngineToggle,
            selectedLanguage: _selectedLanguage,
          ),
    );
  }

  void _showReportStolenDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          ReportStolenDialog(
            controller: _controller,
            onConfirm: _handleReportStolen,
            selectedLanguage: _selectedLanguage,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<DashboardController>(
        builder: (context, controller, child) {
          if (controller.isLoading || controller.selectedVehicle == null) {
            return const DashboardSkeleton();
          }

          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Column(
                children: [
                  _buildModernHeader(controller),
                  Expanded(
                    child: Stack(
                      children: [
                        // Google Map
                        GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: LatLng(
                                controller.vehicleLat, controller.vehicleLng),
                            zoom: 16,
                          ),
                          markers: controller.createMarkers(),
                          mapType: controller.currentMapType,
                          onMapCreated: (mapController) {
                            controller.setMapController(mapController);
                          },
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          mapToolbarEnabled: false,
                          minMaxZoomPreference: const MinMaxZoomPreference(
                              10, 20),
                        ),

                        // Modern Floating Elements
                        _buildModernVehicleSelector(controller),
                        _buildModernMapTypeButton(controller),
                        _buildModernRefreshButton(controller),
                        _buildModernEngineButton(controller),
                        _buildModernReportStolenButton(controller),
                        _buildModernBottomControls(controller),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildModernHeader(DashboardController controller) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo with gradient
          ShaderMask(
            shaderCallback: (bounds) =>
                LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withOpacity(0.7)
                  ],
                ).createShader(bounds),
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'PROXYM ',
                    style: AppTypography.h3.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  TextSpan(
                    text: 'TRACKING',
                    style: AppTypography.h3.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Row(
            children: [

              const SizedBox(width: 16),

              // Modern Notification Button
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.border.withOpacity(0.5)),
                    ),
                    child: IconButton(
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          '/notifications',
                          arguments: {
                            'vehicleId': controller.selectedVehicleId
                          },
                        ).then((_) => controller.fetchUnreadNotifications());
                      },
                      icon: Icon(
                        Icons.notifications_rounded,
                        size: 22,
                        color: controller.notificationCount > 0
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  if (controller.notificationCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.error, AppColors.error
                                .withOpacity(0.8)
                            ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.error.withOpacity(0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                            minWidth: 16, minHeight: 16),
                        child: Text(
                          controller.notificationCount > 9
                              ? '9+'
                              : '${controller.notificationCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernVehicleSelector(DashboardController controller) {
    return Positioned(
      top: 16,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: _showVehicleSelectorModal,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white,
                  Colors.white.withOpacity(0.95),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Vehicle color indicator
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: controller.hexToColor(
                        controller.selectedVehicle!.color),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: controller
                            .hexToColor(controller.selectedVehicle!.color)
                            .withOpacity(0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Car icon with gradient
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withOpacity(0.1),
                        AppColors.primary.withOpacity(0.05)
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.directions_car_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),

                // Vehicle name
                Text(
                  controller.selectedVehicle!.nickname.isNotEmpty
                      ? controller.selectedVehicle!.nickname
                      : controller.selectedVehicle!.immatriculation,
                  style: AppTypography.body1.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.black,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 10),

                // Online indicator with pulse animation
                if (controller.selectedVehicle!.isOnline)
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withOpacity(0.5),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 8),

                // Dropdown arrow
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernMapTypeButton(DashboardController controller) {
    return Positioned(
      top: 16,
      left: 16,
      child: GestureDetector(
        onTap: () => controller.cycleMapType(),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, Colors.white.withOpacity(0.95)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.1),
                      AppColors.primary.withOpacity(0.05)
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.layers_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                controller.getMapTypeLabel(),
                style: AppTypography.caption.copyWith(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernRefreshButton(DashboardController controller) {
    return Positioned(
      top: 88,
      left: 16,
      child: GestureDetector(
        onTap: () async {
          await controller.refresh();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.white,
                        size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedLanguage == 'en' ? 'Refreshed' : 'Actualisé',
                        style: AppTypography.body2.copyWith(
                            color: Colors.white),
                      ),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFF10B981),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, Colors.white.withOpacity(0.95)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            Icons.refresh_rounded,
            color: AppColors.primary,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildModernEngineButton(DashboardController controller) {
    return Positioned(
      top: 16,
      right: 16,
      child: GestureDetector(
        onTap: controller.isTogglingEngine ? null : _showEngineConfirmDialog,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: controller.engineOn
                  ? [const Color(0xFF10B981), const Color(0xFF059669)]
                  : [const Color(0xFFEF4444), const Color(0xFFDC2626)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (controller.engineOn
                    ? const Color(0xFF10B981)
                    : const Color(0xFFEF4444))
                    .withOpacity(0.4),
                blurRadius: 16,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: controller.isTogglingEngine
              ? Padding(
            padding: const EdgeInsets.all(14.0),
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
          )
              : Icon(
            controller.engineOn ? Icons.lock_open_rounded : Icons.lock_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }

  Widget _buildModernReportStolenButton(DashboardController controller) {
    return Positioned(
      top: 88,
      right: 16,
      child: GestureDetector(
        onTap: controller.isReportingStolen ? null : _showReportStolenDialog,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEF4444).withOpacity(0.4),
                blurRadius: 16,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: controller.isReportingStolen
              ? Padding(
            padding: const EdgeInsets.all(14.0),
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
          )
              : Icon(
            Icons.shield_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }

  Widget _buildModernBottomControls(DashboardController controller) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.background,
              AppColors.background.withOpacity(0.98),
            ],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Geofence + Safe Zone
            Row(
              children: [
                Expanded(
                  child: _buildModernFeatureCard(
                    icon: Icons.fence_rounded,
                    label: _selectedLanguage == 'en' ? 'Geofence' : 'Géofence',
                    isActive: controller.geofenceEnabled,
                    onTap: _handleGeofenceToggle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildModernFeatureCard(
                    icon: Icons.shield_rounded,
                    label: _selectedLanguage == 'en'
                        ? 'Safe Zone'
                        : 'Zone de sécurité',
                    isActive: controller.safeZoneEnabled,
                    onTap: _handleSafeZoneToggle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10), // ✅ Space between rows
            // Quick Actions
            Row(
              children: [
                Expanded(
                  child: _buildModernQuickAction(
                    icon: Icons.route_rounded,
                    label: _selectedLanguage == 'en' ? 'Trips' : 'Trajets',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              TripsScreen(
                                  vehicleId: controller.selectedVehicleId),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildModernQuickAction(
                    icon: Icons.settings_rounded,
                    label: _selectedLanguage == 'en'
                        ? 'Settings'
                        : 'Paramètres',
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              SettingsScreen(vehicleId: widget.vehicleId),
                        ),
                      );
                      if (result == 'language_changed') {
                        await _loadLanguagePreference();
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernFeatureCard({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    // ✅ Use green when active, red when inactive
    final Color activeColor = isActive ? AppColors.success : AppColors.error;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isActive
                ? [
              AppColors.success.withOpacity(0.15),
              AppColors.success.withOpacity(0.05)
            ]
                : [
              AppColors.error.withOpacity(0.15),
              AppColors.error.withOpacity(0.05)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: activeColor.withOpacity(0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: activeColor.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8), // ✅ Reduced padding
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [activeColor, activeColor.withOpacity(0.8)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 18, // ✅ Reduced icon size
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.body2.copyWith(
                      fontWeight: FontWeight.w700,
                      color: activeColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isActive
                        ? (_selectedLanguage == 'en' ? 'Active' : 'Actif')
                        : (_selectedLanguage == 'en' ? 'Inactive' : 'Inactif'),
                    style: AppTypography.caption.copyWith(
                      fontSize: 10,
                      color: activeColor.withOpacity(0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isActive ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: activeColor,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primary.withOpacity(0.85)],
            // ✅ Use brand primary color
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Text(
              label,
              style: AppTypography.body2.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}