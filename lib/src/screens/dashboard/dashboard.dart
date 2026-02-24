// lib/screens/dashboard/dashboard.dart

import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:FLEETRA/src/screens/dashboard/services/dashboard_controller.dart';
import 'package:FLEETRA/src/screens/dashboard/widgets/dashboard_skeleton.dart';
import 'package:FLEETRA/src/screens/dashboard/widgets/dashboard_widget.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utility/app_theme.dart';
import '../../widgets/offline_barner.dart';
import '../settings/settings.dart';
import '../stoeln vehicle/stolen_alert.dart';
import '../trip/trip_screen.dart';

class ModernDashboard extends StatefulWidget {
  final int vehicleId;

  const ModernDashboard({Key? key, required this.vehicleId}) : super(key: key);

  @override
  State<ModernDashboard> createState() => _ModernDashboardState();
}

class _ModernDashboardState extends State<ModernDashboard>
    with TickerProviderStateMixin {
  DashboardController? _controller;
  StreamSubscription<Map<String, dynamic>>? _alertSubscription;
  String _selectedLanguage = 'en';

  // ✅ Track if user has manually moved the map
  // Auto-centering is DISABLED — map only centers on user tap of recenter button
  bool _userHasMovedMap = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Marker animation
  late AnimationController _markerAnimationController;
  Animation<double>? _latAnimation;
  Animation<double>? _lngAnimation;
  Animation<double>? _rotationAnimation;
  double _currentMarkerLat = 4.0511;
  double _currentMarkerLng = 9.7679;
  double _currentRotation = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadSavedVehicleId();
    await _loadLanguagePreference();

    _controller = DashboardController(_savedVehicleId ?? widget.vehicleId);
    await _controller!.initialize();

    if (mounted) {
      setState(() {
        _currentMarkerLat = _controller!.vehicleLat;
        _currentMarkerLng = _controller!.vehicleLng;
      });
    }

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _markerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _alertSubscription = _controller!.safeZoneAlertStream.listen((alertData) {
      if (mounted) _showSafeZoneAlert(alertData);
    });

    // ✅ Only animate the marker icon — do NOT move the camera
    _setupLocationListener();
  }

  int? _savedVehicleId;

  Future<void> _loadSavedVehicleId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getInt('current_vehicle_id');
      if (savedId != null) {
        _savedVehicleId = savedId;
        debugPrint('✅ Loaded saved vehicle ID: $savedId');
      }
    } catch (e) {
      debugPrint('⚠️ Error loading saved vehicle ID: $e');
    }
  }

  // ✅ Listener: only moves the MARKER — never the camera
  void _setupLocationListener() {
    _controller?.addListener(() {
      if (_controller!.vehicleLat != _currentMarkerLat ||
          _controller!.vehicleLng != _currentMarkerLng) {
        _animateMarkerToNewPosition(
          _controller!.vehicleLat,
          _controller!.vehicleLng,
        );
        // ✅ No camera move here — user controls the map
      }
    });
  }

  double _calculateBearing(
      double startLat, double startLng, double endLat, double endLng) {
    final dLon = (endLng - startLng) * (3.14159265359 / 180);
    final startLatRad = startLat * (3.14159265359 / 180);
    final endLatRad = endLat * (3.14159265359 / 180);
    final y = math.sin(dLon) * math.cos(endLatRad);
    final x = math.cos(startLatRad) * math.sin(endLatRad) -
        math.sin(startLatRad) * math.cos(endLatRad) * math.cos(dLon);
    final bearing = math.atan2(y, x) * (180 / 3.14159265359);
    return (bearing + 360) % 360;
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000;
    final dLat = (lat2 - lat1) * (3.14159265359 / 180);
    final dLon = (lon2 - lon1) * (3.14159265359 / 180);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (3.14159265359 / 180)) *
            math.cos(lat2 * (3.14159265359 / 180)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  void _animateMarkerToNewPosition(double newLat, double newLng) {
    final distance = _calculateDistance(
        _currentMarkerLat, _currentMarkerLng, newLat, newLng);

    int durationMs;
    if (distance < 10) {
      durationMs = 500;
    } else if (distance < 100) {
      durationMs = (1000 + (distance * 10)).clamp(1000, 2000).toInt();
    } else {
      durationMs = 2500;
    }

    final bearing = _calculateBearing(
        _currentMarkerLat, _currentMarkerLng, newLat, newLng);

    _markerAnimationController.duration = Duration(milliseconds: durationMs);

    _latAnimation = Tween<double>(
      begin: _currentMarkerLat,
      end: newLat,
    ).animate(CurvedAnimation(
      parent: _markerAnimationController,
      curve: Curves.easeInOut,
    ));

    _lngAnimation = Tween<double>(
      begin: _currentMarkerLng,
      end: newLng,
    ).animate(CurvedAnimation(
      parent: _markerAnimationController,
      curve: Curves.easeInOut,
    ));

    _rotationAnimation = Tween<double>(
      begin: _currentRotation,
      end: bearing,
    ).animate(CurvedAnimation(
      parent: _markerAnimationController,
      curve: Curves.easeInOut,
    ));

    _markerAnimationController.addListener(() {
      if (_latAnimation != null &&
          _lngAnimation != null &&
          _rotationAnimation != null) {
        setState(() {
          _currentMarkerLat = _latAnimation!.value;
          _currentMarkerLng = _lngAnimation!.value;
          _currentRotation = _rotationAnimation!.value;
        });
      }
    });

    _markerAnimationController.forward(from: 0.0);
  }

  // ✅ RECENTER: manually snap camera to vehicle position
  void _recenterMap() {
    if (_controller == null) return;
    _controller!.mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(_controller!.vehicleLat, _controller!.vehicleLng),
          zoom: 16,
        ),
      ),
    );
    setState(() => _userHasMovedMap = false);
    debugPrint('📍 Recentered to vehicle: ${_controller!.vehicleLat}, ${_controller!.vehicleLng}');
  }

  String _getLastSeenText(DateTime lastUpdate) {
    final difference = DateTime.now().difference(lastUpdate);
    if (difference.inMinutes < 1) {
      return _selectedLanguage == 'en' ? 'Just now' : 'À l\'instant';
    } else if (difference.inMinutes < 60) {
      return _selectedLanguage == 'en'
          ? 'Last seen ${difference.inMinutes} min ago'
          : 'Vu il y a ${difference.inMinutes} min';
    } else if (difference.inHours < 24) {
      return _selectedLanguage == 'en'
          ? 'Last seen ${difference.inHours}h ago'
          : 'Vu il y a ${difference.inHours}h';
    } else {
      return _selectedLanguage == 'en'
          ? 'Last seen ${difference.inDays}d ago'
          : 'Vu il y a ${difference.inDays}j';
    }
  }

  Set<Marker> _createAnimatedMarkers() {
    if (_controller == null ||
        _controller!.selectedVehicle == null ||
        _controller!.customCarIcon == null) {
      return {};
    }

    return {
      Marker(
        markerId: const MarkerId('vehicle'),
        position: LatLng(_currentMarkerLat, _currentMarkerLng),
        icon: _controller!.customCarIcon!,
        anchor: const Offset(0.5, 0.5),
        rotation: _currentRotation,
        infoWindow: InfoWindow(
          title: _controller!.selectedVehicle!.nickname.isNotEmpty
              ? _controller!.selectedVehicle!.nickname
              : '${_controller!.selectedVehicle!.brand} ${_controller!.selectedVehicle!.model}',
          snippet: _controller!.selectedVehicle!.immatriculation,
        ),
      ),
    };
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _selectedLanguage = prefs.getString('language') ?? 'en';
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _markerAnimationController.dispose();
    _alertSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _showSafeZoneAlert(Map<String, dynamic> alertData) {
    final title = alertData['title'] ??
        (_selectedLanguage == 'en' ? 'Safe Zone Alert' : 'Alerte zone sécurisée');
    final message = alertData['message'] ??
        (_selectedLanguage == 'en'
            ? 'Vehicle left safe zone'
            : 'Véhicule a quitté la zone sécurisée');
    final severity = alertData['severity'] ?? 'warning';

    Color backgroundColor;
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
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: AppTypography.subtitle1.copyWith(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(message,
                style: AppTypography.body2
                    .copyWith(color: Colors.white.withOpacity(0.95))),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            icon: Icon(Icons.close_rounded, color: Colors.white, size: 18),
            label: Text(
              _selectedLanguage == 'en' ? 'DISMISS' : 'FERMER',
              style: AppTypography.button.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w600),
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
    if (_controller == null || _controller!.isTogglingGeofence) return;
    final success = await _controller!.toggleGeofence();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success
                  ? Icons.check_circle_rounded
                  : Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Text(
                success
                    ? (_controller!.geofenceEnabled
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
            ? (_controller!.geofenceEnabled
            ? const Color(0xFF10B981)
            : const Color(0xFF64748B))
            : AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _handleSafeZoneToggle() async {
    if (_controller == null || _controller!.isTogglingSafeZone) return;
    final result = await _controller!.toggleSafeZone();
    if (!mounted) return;
    if (result['success']) {
      final bool wasCreated = _controller!.safeZoneEnabled;
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
                      : 'Zone de sécurité créée!')
                      : (_selectedLanguage == 'en'
                      ? 'Safe Zone deleted'
                      : 'Zone de sécurité supprimée'),
                  style: AppTypography.body2.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: wasCreated
              ? const Color(0xFF10B981)
              : const Color(0xFF64748B),
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } else {
      final errorMessage = result['message'] ??
          (_selectedLanguage == 'en'
              ? 'Failed to toggle safe zone'
              : 'Échec');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  void _handleEngineToggle() async {
    if (_controller == null) return;
    final success = await _controller!.toggleEngine();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success
                  ? Icons.check_circle_rounded
                  : Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Text(
                success
                    ? (_controller!.engineOn
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
            ? (_controller!.engineOn
            ? const Color(0xFF10B981)
            : AppColors.error)
            : AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: success ? 2 : 3),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _handleReportStolen() async {
    if (_controller == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.warning_amber_rounded,
                  color: AppColors.error, size: 28),
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
              style:
              AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: AppSizes.spacingM),
            _buildConfirmationItem(Icons.power_settings_new_rounded,
                _selectedLanguage == 'en' ? 'Disable engine immediately' : 'Désactiver le moteur'),
            _buildConfirmationItem(Icons.notification_add_rounded,
                _selectedLanguage == 'en' ? 'Create theft alert' : 'Créer alerte de vol'),
            _buildConfirmationItem(Icons.my_location_rounded,
                _selectedLanguage == 'en' ? 'Show vehicle location' : 'Afficher localisation'),
            _buildConfirmationItem(Icons.local_police_rounded,
                _selectedLanguage == 'en' ? 'Show nearby police' : 'Afficher police'),
            SizedBox(height: AppSizes.spacingM),
            Container(
              padding: EdgeInsets.all(AppSizes.spacingM),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppColors.error, size: 20),
                  SizedBox(width: AppSizes.spacingS),
                  Expanded(
                    child: Text(
                      _selectedLanguage == 'en'
                          ? 'This action cannot be undone'
                          : 'Action irréversible',
                      style: AppTypography.caption.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600),
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
                    horizontal: 24, vertical: 12)),
            child: Text(
              _selectedLanguage == 'en' ? 'Cancel' : 'Annuler',
              style: AppTypography.button
                  .copyWith(color: AppColors.textSecondary),
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
              style:
              AppTypography.button.copyWith(color: Colors.white),
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
      builder: (context) => Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20)),
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
                style: AppTypography.body1
                    .copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    final success = await _controller!.reportStolen();

    if (!mounted) return;
    Navigator.pop(context);

    if (success) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StolenAlertScreen(
            vehicleId: _controller!.selectedVehicleId,
            vehicleLat: _controller!.vehicleLat,
            vehicleLng: _controller!.vehicleLng,
            vehicleName:
            _controller!.selectedVehicle?.nickname.isNotEmpty == true
                ? _controller!.selectedVehicle!.nickname
                : '${_controller!.selectedVehicle?.brand ?? ''} ${_controller!.selectedVehicle?.model ?? ''}'
                .trim(),
            nearbyPolice: _controller!.nearbyPolice,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedLanguage == 'en'
                ? 'Failed to report. Try again.'
                : 'Échec. Réessayez.',
            style: AppTypography.body1.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          Expanded(child: Text(text, style: AppTypography.body2)),
        ],
      ),
    );
  }

  void _showVehicleSelectorModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildMinimalistVehicleSelector(),
    );
  }

  void _showEngineConfirmDialog() {
    if (_controller == null) return;
    showDialog(
      context: context,
      builder: (context) => EngineConfirmDialog(
        controller: _controller!,
        onConfirm: _handleEngineToggle,
        selectedLanguage: _selectedLanguage,
      ),
    );
  }

  void _showReportStolenDialog() {
    if (_controller == null) return;
    showDialog(
      context: context,
      builder: (context) => ReportStolenDialog(
        controller: _controller!,
        onConfirm: _handleReportStolen,
        selectedLanguage: _selectedLanguage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return const DashboardSkeleton();

    return ChangeNotifierProvider.value(
      value: _controller!,
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
                  _buildCompactHeader(controller),
                  const OfflineBanner(),
                  Expanded(
                    child: Stack(
                      children: [
                        // ✅ Google Map — fully free scroll, no zoom limits
                        GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: LatLng(
                                controller.vehicleLat, controller.vehicleLng),
                            zoom: 16,
                          ),
                          markers: _createAnimatedMarkers(),
                          mapType: controller.currentMapType,
                          onMapCreated: (mapController) {
                            controller.setMapController(mapController);
                          },
                          // ✅ Detect when user manually moves map
                          onCameraMove: (position) {
                            if (!_userHasMovedMap) {
                              setState(() => _userHasMovedMap = true);
                            }
                          },
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          mapToolbarEnabled: false,
                          // ✅ No minMaxZoomPreference — user can zoom all
                          // the way out to see the whole earth
                        ),

                        // Top center — vehicle selector
                        _buildCompactVehicleSelectorButton(controller),

                        // Top left — map type
                        _buildCompactMapTypeButton(controller),

                        // ✅ Recenter button — below map type, Google Maps style
                        _buildRecenterButton(controller),

                        // Top right — engine
                        _buildCompactEngineButton(controller),

                        // Below engine — stolen
                        _buildCompactStolenButton(controller),

                        // Bottom controls
                        _buildPureGlassmorphicBottomControls(controller),
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

  // ========== COMPACT HEADER ==========
  Widget _buildCompactHeader(DashboardController controller) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFD85119), Color(0xFFD85119)],
            ).createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: const Text(
              'FLEETRA',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                fontFamily: 'Roboto',
                color: Colors.white,
              ),
            ),
          ),
          Row(
            children: [
              // Refresh
              _buildSimpleIconButton(
                icon: controller.isRefreshing
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black54),
                )
                    : Icon(Icons.refresh_rounded,
                    size: 20,
                    color: controller.isOffline
                        ? Colors.grey
                        : Colors.black54),
                onTap: controller.isOffline || controller.isRefreshing
                    ? null
                    : () async {
                  await controller.refresh();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 10),
                            Text(
                              _selectedLanguage == 'en'
                                  ? 'Refreshed'
                                  : 'Actualisé',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 1),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        margin: const EdgeInsets.all(12),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(width: 10),

              // Notifications
              Stack(
                children: [
                  _buildSimpleIconButton(
                    icon: Icon(Icons.notifications_outlined,
                        size: 20,
                        color: controller.notificationCount > 0
                            ? Colors.black
                            : Colors.black54),
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        '/notifications',
                        arguments: {
                          'vehicleId': controller.selectedVehicleId
                        },
                      ).then((_) => controller.fetchUnreadNotifications());
                    },
                  ),
                  if (controller.notificationCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                          border:
                          Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),

              // Settings
              _buildSimpleIconButton(
                icon: const Icon(Icons.settings_outlined,
                    size: 20, color: Colors.black54),
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
            ],
          ),
        ],
      ),
    );
  }

  // ========== VEHICLE SELECTOR BUTTON ==========
  Widget _buildCompactVehicleSelectorButton(DashboardController controller) {
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: _showVehicleSelectorModal,
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.directions_car,
                    color: Colors.black87, size: 18),
                const SizedBox(width: 8),
                Text(
                  controller.selectedVehicle!.nickname.isNotEmpty
                      ? controller.selectedVehicle!.nickname
                      : controller.selectedVehicle!.immatriculation,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                if (controller.selectedVehicle!.isOnline)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down,
                    color: Colors.black54, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ========== MAP TYPE BUTTON ==========
  Widget _buildCompactMapTypeButton(DashboardController controller) {
    return Positioned(
      top: 12,
      left: 12,
      child: GestureDetector(
        onTap: () => controller.cycleMapType(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.layers, color: Colors.black87, size: 20),
        ),
      ),
    );
  }

  // ========== RECENTER BUTTON (Google Maps style) ==========
  // Placed directly below the map type button
  // Shows blue when map is centered, grey when user has moved away
  Widget _buildRecenterButton(DashboardController controller) {
    return Positioned(
      top: 62, // directly below map type button (12 top + 40 height + 10 gap)
      left: 12,
      child: GestureDetector(
        onTap: _recenterMap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.my_location_rounded,
            // ✅ Blue when map needs recentering, grey when already centered
            color: _userHasMovedMap
                ? const Color(0xFF1A73E8) // Google Maps blue
                : Colors.black38,
            size: 20,
          ),
        ),
      ),
    );
  }

  // ========== ENGINE BUTTON ==========
  Widget _buildCompactEngineButton(DashboardController controller) {
    final bool isDisabled =
        controller.isOffline || controller.isTogglingEngine;
    return Positioned(
      top: 12,
      right: 12,
      child: GestureDetector(
        onTap: isDisabled ? null : _showEngineConfirmDialog,
        child: Opacity(
          opacity: controller.isOffline ? 0.5 : 1.0,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: controller.engineOn
                  ? Colors.white
                  : const Color(0xFFEF4444),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: controller.isTogglingEngine
                ? Padding(
              padding: const EdgeInsets.all(12.0),
              child: CircularProgressIndicator(
                color: controller.engineOn
                    ? Colors.black87
                    : Colors.white,
                strokeWidth: 2,
              ),
            )
                : Stack(
              alignment: Alignment.center,
              children: [
                Image.asset(
                  controller.engineOn
                      ? 'assets/open.ico'
                      : 'assets/lock.ico',
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                  color: controller.engineOn
                      ? const Color(0xFF10B981)
                      : Colors.white,
                  colorBlendMode: BlendMode.srcIn,
                ),
                if (controller.isOffline)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.cloud_off,
                          color: Colors.red, size: 10),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ========== STOLEN BUTTON ==========
  Widget _buildCompactStolenButton(DashboardController controller) {
    final bool isDisabled =
        controller.isOffline || controller.isReportingStolen;
    return Positioned(
      top: 64,
      right: 12,
      child: GestureDetector(
        onTap: isDisabled ? null : _showReportStolenDialog,
        child: Opacity(
          opacity: controller.isOffline ? 0.5 : 1.0,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: controller.isReportingStolen
                ? const Padding(
              padding: EdgeInsets.all(12.0),
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            )
                : Stack(
              alignment: Alignment.center,
              children: [
                Image.asset(
                  'assets/stolen.png',
                  width: 24,
                  height: 24,
                  fit: BoxFit.cover,
                  color: Colors.white,
                  colorBlendMode: BlendMode.srcIn,
                ),
                if (controller.isOffline)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.cloud_off,
                          color: Colors.red, size: 10),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ========== BOTTOM GLASSMORPHIC CONTROLS ==========
  Widget _buildPureGlassmorphicBottomControls(
      DashboardController controller) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRRect(
        borderRadius:
        const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(
                    color: Colors.white.withOpacity(0.2), width: 1),
              ),
            ),
            padding:
            const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: _buildGlassFeatureButton(
                    icon: Icons.radio_button_checked_rounded,
                    label: _selectedLanguage == 'en'
                        ? 'Geofence'
                        : 'Barrière Virtuelle',
                    isActive: controller.geofenceEnabled,
                    isLoading: controller.isTogglingGeofence,
                    onTap: _handleGeofenceToggle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildGlassFeatureButton(
                    icon: Icons.shield_rounded,
                    label: _selectedLanguage == 'en'
                        ? 'Safe Zone'
                        : 'Zone de sécurité',
                    isActive: controller.safeZoneEnabled,
                    isLoading: controller.isTogglingSafeZone,
                    onTap: _handleSafeZoneToggle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildGlassActionButton(
                    icon: Icons.timeline_rounded,
                    label: _selectedLanguage == 'en'
                        ? 'Trip History'
                        : 'Historique',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TripsScreen(
                              vehicleId: controller.selectedVehicleId),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ========== VEHICLE SELECTOR MODAL ==========
  Widget _buildMinimalistVehicleSelector() {
    if (_controller == null) return const SizedBox.shrink();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _selectedLanguage == 'en'
                    ? 'Select Vehicle'
                    : 'Sélectionner véhicule',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _controller!.vehicles.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (context, index) {
                final vehicle = _controller!.vehicles[index];
                final isSelected =
                    vehicle.id == _controller!.selectedVehicleId;

                return InkWell(
                  onTap: () async {
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('current_vehicle_id', vehicle.id);
                    } catch (e) {
                      debugPrint('⚠️ Error saving vehicle ID: $e');
                    }

                    _controller!.onVehicleSelected(vehicle.id);

                    setState(() {
                      _currentMarkerLat = _controller!.vehicleLat;
                      _currentMarkerLng = _controller!.vehicleLng;
                      _currentRotation = 0.0;
                      _userHasMovedMap = false;
                    });

                    // ✅ Recenter when switching vehicles
                    _recenterMap();
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    color: isSelected
                        ? AppColors.primary.withOpacity(0.05)
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Icon(
                          Icons.directions_car,
                          color: isSelected
                              ? AppColors.primary
                              : Colors.grey.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vehicle.nickname.isNotEmpty
                                    ? vehicle.nickname
                                    : '${vehicle.brand} ${vehicle.model}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? AppColors.primary
                                      : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                vehicle.nickname.isNotEmpty
                                    ? '${vehicle.brand} ${vehicle.model} — ${vehicle.immatriculation}'
                                    : vehicle.immatriculation,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: vehicle.isOnline
                                ? const Color(0xFF10B981)
                                : Colors.grey.shade400,
                            shape: BoxShape.circle,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.check_circle,
                              color: AppColors.primary, size: 20),
                        ],
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
  }

  // ========== HELPERS ==========
  Widget _buildSimpleIconButton(
      {required Widget icon, required VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(padding: const EdgeInsets.all(6), child: icon),
    );
  }

  Widget _buildGlassFeatureButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    final Color activeColor = const Color(0xFF10B981);
    final Color inactiveColor = const Color(0xFFEF4444);

    return GestureDetector(
      onTap: () {
        if (_controller?.isOffline ?? false) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedLanguage == 'en'
                          ? 'Requires Internet'
                          : 'Internet requis',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFFF59E0B),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(12),
            ),
          );
          return;
        }
        if (!isLoading) onTap();
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity:
        (_controller?.isOffline ?? false) || isLoading ? 0.5 : 1.0,
        child: Container(
          padding:
          const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: Colors.white.withOpacity(0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: isLoading
                        ? Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black87),
                      ),
                    )
                        : Icon(icon, color: Colors.black87, size: 20),
                  ),
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isActive ? activeColor : inactiveColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: (isActive ? activeColor : inactiveColor)
                                .withOpacity(0.6),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                    height: 1.1,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppColors.primary.withOpacity(0.8), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.1,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}