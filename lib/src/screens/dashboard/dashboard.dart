// lib/screens/dashboard/dashboard.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracking/src/screens/dashboard/services/dashboard_controller.dart';
import 'package:tracking/src/screens/dashboard/widgets/dashboard_widget.dart';

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

class _ModernDashboardState extends State<ModernDashboard> {
  late DashboardController _controller;
  StreamSubscription<Map<String, dynamic>>? _alertSubscription;
  String _selectedLanguage = 'en'; // Default to English

  @override
  void initState() {
    super.initState();
    _saveCurrentVehicleId(); // ✅ Save vehicle ID for PIN lock
    _loadLanguagePreference();
    _controller = DashboardController(widget.vehicleId);
    _controller.initialize();

    // Listen to safe zone alerts
    _alertSubscription = _controller.safeZoneAlertStream.listen((alertData) {
      if (mounted) {
        _showSafeZoneAlert(alertData);
      }
    });
  }

  /// ✅ Save current vehicle ID to SharedPreferences for PIN lock
  Future<void> _saveCurrentVehicleId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_vehicle_id', widget.vehicleId);
      debugPrint('🚗 Saved current vehicle ID for PIN lock: ${widget.vehicleId}');
    } catch (e) {
      debugPrint('⚠️ Error saving vehicle ID: $e');
    }
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
    debugPrint('✅ Dashboard loaded language preference: $_selectedLanguage');
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _showSafeZoneAlert(Map<String, dynamic> alertData) {
    final title = alertData['title'] ?? (_selectedLanguage == 'en' ? 'Safe Zone Alert' : 'Alerte Zone Sûre');
    final message = alertData['message'] ?? (_selectedLanguage == 'en' ? 'Vehicle left safe zone' : 'Véhicule a quitté la zone sûre');
    final severity = alertData['severity'] ?? 'warning';

    Color backgroundColor;
    Color textColor = Colors.white;
    IconData icon;

    if (severity == 'warning') {
      backgroundColor = Colors.orange;
      icon = Icons.warning_rounded;
    } else if (severity == 'info') {
      backgroundColor = Colors.green;
      icon = Icons.check_circle_rounded;
    } else {
      backgroundColor = AppColors.error;
      icon = Icons.notifications_active_rounded;
    }

    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: backgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: textColor, size: 28),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: AppTypography.subtitle1.copyWith(color: textColor),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: AppTypography.body2.copyWith(color: textColor),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            },
            child: Text(
              _selectedLanguage == 'en' ? 'DISMISS' : 'FERMER',
              style: AppTypography.button.copyWith(color: textColor),
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
        content: Text(
          success
              ? (_controller.geofenceEnabled
              ? (_selectedLanguage == 'en' ? 'Geofencing enabled' : 'Géofence activée')
              : (_selectedLanguage == 'en' ? 'Geofencing disabled' : 'Géofence désactivée'))
              : (_selectedLanguage == 'en' ? 'Failed to toggle geofencing' : 'Échec du basculement de la géofence'),
        ),
        backgroundColor: success
            ? (_controller.geofenceEnabled ? Color(0xFF10B981) : Color(0xFF64748B))
            : AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
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
              Icon(Icons.check_circle, color: AppColors.white, size: 20),
              SizedBox(width: AppSizes.spacingM),
              Expanded(
                child: Text(
                  wasCreated
                      ? (_selectedLanguage == 'en'
                      ? 'Safe Zone created at current location!'
                      : 'Zone Sûre créée à l\'emplacement actuel!')
                      : (_selectedLanguage == 'en' ? 'Safe Zone deleted' : 'Zone Sûre supprimée'),
                  style: AppTypography.body2.copyWith(color: AppColors.white),
                ),
              ),
            ],
          ),
          backgroundColor: wasCreated ? AppColors.success : Color(0xFF64748B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
          ),
          margin: EdgeInsets.all(AppSizes.spacingM),
        ),
      );
    } else {
      final errorMessage = result['message'] ?? (_selectedLanguage == 'en'
          ? 'Failed to toggle safe zone'
          : 'Échec du basculement de la zone sûre');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleEngineToggle() async {
    final success = await _controller.toggleEngine();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (_controller.engineOn
              ? (_selectedLanguage == 'en' ? 'Engine unlocked' : 'Moteur déverrouillé')
              : (_selectedLanguage == 'en' ? 'Engine locked' : 'Moteur verrouillé'))
              : (_selectedLanguage == 'en'
              ? 'Failed to ${_controller.engineOn ? "unlock" : "lock"} engine'
              : 'Échec du ${_controller.engineOn ? "déverrouillage" : "verrouillage"} du moteur'),
        ),
        backgroundColor: success
            ? (_controller.engineOn ? AppColors.success : AppColors.error)
            : AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: success ? 1 : 2),
      ),
    );
  }

  // 🆕 UPDATED: Report Stolen with Confirmation and Navigation
  Future<void> _handleReportStolen() async {
    // Show confirmation dialog first
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning_rounded,
              color: AppColors.error,
              size: 32,
            ),
            SizedBox(width: AppSizes.spacingM),
            Text(
              _selectedLanguage == 'en' ? 'Report Stolen?' : 'Signaler Volé?',
              style: AppTypography.h3,
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
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: AppSizes.spacingS),
            _buildConfirmationItem(
              _selectedLanguage == 'en'
                  ? 'Immediately disable the vehicle engine'
                  : 'Désactiver immédiatement le moteur du véhicule',
            ),
            _buildConfirmationItem(
              _selectedLanguage == 'en'
                  ? 'Create a theft alert'
                  : 'Créer une alerte de vol',
            ),
            _buildConfirmationItem(
              _selectedLanguage == 'en'
                  ? 'Show you the vehicle location'
                  : 'Afficher l\'emplacement du véhicule',
            ),
            _buildConfirmationItem(
              _selectedLanguage == 'en'
                  ? 'Show nearby police stations'
                  : 'Afficher les postes de police à proximité',
            ),
            SizedBox(height: AppSizes.spacingM),
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
                    Icons.info_outline,
                    color: AppColors.error,
                    size: 20,
                  ),
                  SizedBox(width: AppSizes.spacingS),
                  Expanded(
                    child: Text(
                      _selectedLanguage == 'en'
                          ? 'This action cannot be undone'
                          : 'Cette action ne peut pas être annulée',
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
            child: Text(
              _selectedLanguage == 'en' ? 'Cancel' : 'Annuler',
              style: AppTypography.button.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text(
              _selectedLanguage == 'en' ? 'Report Stolen' : 'Signaler Volé',
              style: AppTypography.button.copyWith(
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: EdgeInsets.all(AppSizes.spacingXL),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppSizes.radiusL),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: AppSizes.spacingL),
              Text(
                _selectedLanguage == 'en'
                    ? 'Reporting stolen vehicle...'
                    : 'Signalement du véhicule volé...',
                style: AppTypography.body1,
              ),
            ],
          ),
        ),
      ),
    );

    // Report stolen
    final success = await _controller.reportStolen();

    // Close loading dialog
    if (!mounted) return;
    Navigator.pop(context);

    if (success) {
      // Navigate to Stolen Alert Screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StolenAlertScreen(
            vehicleId: _controller.selectedVehicleId,
            vehicleLat: _controller.vehicleLat,
            vehicleLng: _controller.vehicleLng,
            vehicleName: _controller.selectedVehicle?.nickname.isNotEmpty == true
                ? _controller.selectedVehicle!.nickname
                : '${_controller.selectedVehicle?.brand ?? ''} ${_controller.selectedVehicle?.model ?? ''}'.trim(),
          ),
        ),
      );

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: AppSizes.spacingM),
              Expanded(
                child: Text(
                  _selectedLanguage == 'en'
                      ? 'Vehicle reported as stolen. Engine disabled.'
                      : 'Véhicule signalé volé. Moteur désactivé.',
                  style: AppTypography.body1.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    } else {
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: AppSizes.spacingM),
              Expanded(
                child: Text(
                  _selectedLanguage == 'en'
                      ? 'Failed to report stolen. Please try again.'
                      : 'Échec du signalement. Veuillez réessayer.',
                  style: AppTypography.body1.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // 🆕 Helper widget for confirmation items
  Widget _buildConfirmationItem(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSizes.spacingS),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            color: AppColors.success,
            size: 20,
          ),
          SizedBox(width: AppSizes.spacingS),
          Expanded(
            child: Text(
              text,
              style: AppTypography.body2,
            ),
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
      builder: (context) => VehicleSelectorModal(
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
      builder: (context) => EngineConfirmDialog(
        controller: _controller,
        onConfirm: _handleEngineToggle,
        selectedLanguage: _selectedLanguage,
      ),
    );
  }

  void _showReportStolenDialog() {
    showDialog(
      context: context,
      builder: (context) => ReportStolenDialog(
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
                  // Compact Header
                  _buildHeader(controller),

                  // Map with Floating Elements
                  Expanded(
                    child: Stack(
                      children: [
                        // Google Map
                        GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: LatLng(controller.vehicleLat, controller.vehicleLng),
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
                          minMaxZoomPreference: MinMaxZoomPreference(10, 20), // ✅ Limit zoom range
                        ),

                        // Floating Vehicle Selector
                        _buildFloatingVehicleSelector(controller),

                        // Floating Map Type Toggle Button
                        _buildFloatingMapTypeButton(controller),

                        // Floating Refresh Button (for manual refresh)
                        _buildFloatingRefreshButton(controller),

                        // Floating Engine Lock/Unlock Button
                        _buildFloatingEngineButton(controller),

                        // Floating Report Stolen Button
                        _buildFloatingReportStolenButton(controller),

                        // Bottom Controls
                        _buildBottomControls(controller),
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

  Widget _buildHeader(DashboardController controller) {
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.spacingL,
        vertical: AppSizes.spacingS,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'PROXYM ',
                  style: AppTypography.h3.copyWith(fontSize: 18),
                ),
                TextSpan(
                  text: 'TRACKING',
                  style: AppTypography.h3.copyWith(
                    fontSize: 18,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Stack(
            children: [
              IconButton(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    '/notifications',
                    arguments: {'vehicleId': controller.selectedVehicleId},
                  ).then((_) => controller.fetchUnreadNotifications());
                },
                icon: Icon(Icons.notifications_outlined, size: 22),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
              if (controller.notificationCount > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    constraints: BoxConstraints(minWidth: 14, minHeight: 14),
                    child: Center(
                      child: Text(
                        controller.notificationCount > 9
                            ? '9+'
                            : '${controller.notificationCount}',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingVehicleSelector(DashboardController controller) {
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: _showVehicleSelectorModal,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: controller.hexToColor(controller.selectedVehicle!.color),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.white,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: controller
                            .hexToColor(controller.selectedVehicle!.color)
                            .withOpacity(0.3),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Icon(
                  Icons.directions_car_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
                SizedBox(width: 6),
                Text(
                  controller.selectedVehicle!.nickname.isNotEmpty
                      ? controller.selectedVehicle!.nickname
                      : controller.selectedVehicle!.immatriculation,
                  style: AppTypography.body1.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    fontSize: 13,
                  ),
                ),
                SizedBox(width: 6),
                if (controller.selectedVehicle!.isOnline)
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingMapTypeButton(DashboardController controller) {
    return Positioned(
      top: 12,
      left: 12,
      child: GestureDetector(
        onTap: () => controller.cycleMapType(),
        child: Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.layers_outlined,
                color: AppColors.primary,
                size: 20,
              ),
              SizedBox(height: 2),
              Text(
                controller.getMapTypeLabel(),
                style: AppTypography.caption.copyWith(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingRefreshButton(DashboardController controller) {
    return Positioned(
      top: 68,
      left: 12,
      child: GestureDetector(
        onTap: () async {
          await controller.refresh();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColors.white, size: 20),
                    SizedBox(width: AppSizes.spacingM),
                    Text(
                      _selectedLanguage == 'en' ? 'Dashboard refreshed' : 'Tableau de bord actualisé',
                      style: AppTypography.body2.copyWith(color: AppColors.white),
                    ),
                  ],
                ),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                ),
                margin: EdgeInsets.all(AppSizes.spacingM),
              ),
            );
          }
        },
        child: Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.refresh_rounded,
            color: AppColors.primary,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingEngineButton(DashboardController controller) {
    return Positioned(
      top: 12,
      right: 12,
      child: GestureDetector(
        onTap: controller.isTogglingEngine ? null : _showEngineConfirmDialog,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: controller.engineOn
                  ? [AppColors.success, AppColors.success.withOpacity(0.8)]
                  : [AppColors.error, AppColors.error.withOpacity(0.8)],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (controller.engineOn ? AppColors.success : AppColors.error)
                    .withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: controller.isTogglingEngine
              ? Padding(
            padding: const EdgeInsets.all(12.0),
            child: CircularProgressIndicator(
              color: AppColors.white,
              strokeWidth: 2,
            ),
          )
              : Icon(
            controller.engineOn ? Icons.lock_open_rounded : Icons.lock_rounded,
            color: AppColors.white,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingReportStolenButton(DashboardController controller) {
    return Positioned(
      top: 68,
      right: 12,
      child: GestureDetector(
        onTap: controller.isReportingStolen ? null : _showReportStolenDialog,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.error, AppColors.error.withOpacity(0.8)],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.error.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: controller.isReportingStolen
              ? Padding(
            padding: const EdgeInsets.all(12.0),
            child: CircularProgressIndicator(
              color: AppColors.white,
              strokeWidth: 2,
            ),
          )
              : Icon(
            Icons.report_problem_rounded,
            color: AppColors.white,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls(DashboardController controller) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: AppColors.background,
        padding: EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Geofence + Safe Zone
            Row(
              children: [
                Expanded(
                  child: CompactGeofenceCard(
                    controller: controller,
                    onTap: _handleGeofenceToggle,
                    selectedLanguage: _selectedLanguage,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: CompactSafeZoneCard(
                    controller: controller,
                    onTap: _handleSafeZoneToggle,
                    selectedLanguage: _selectedLanguage,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            // Quick Actions
            Row(
              children: [
                Expanded(
                  child: QuickActionButton(
                    icon: Icons.route_outlined,
                    label: _selectedLanguage == 'en' ? 'Trips' : 'Trajets',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              TripsScreen(vehicleId: controller.selectedVehicleId),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: QuickActionButton(
                    icon: Icons.settings_outlined,
                    label: _selectedLanguage == 'en' ? 'Settings' : 'Paramètres',
                    onTap: () async {
                      // Navigate to settings and wait for result
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SettingsScreen(vehicleId: widget.vehicleId),
                        ),
                      );

                      // If language was changed, reload it
                      if (result == 'language_changed') {
                        await _loadLanguagePreference();
                        debugPrint('🔄 Dashboard language updated after Settings change');
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
}