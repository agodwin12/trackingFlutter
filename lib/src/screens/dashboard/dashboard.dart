// lib/screens/dashboard/dashboard.dart

import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:FLEETRA/src/screens/dashboard/services/dashboard_controller.dart';
import 'package:FLEETRA/src/screens/dashboard/widgets/dashboard_skeleton.dart';
import 'package:FLEETRA/src/screens/dashboard/widgets/dashboard_widget.dart';
import 'package:FLEETRA/src/services/payment_notifier.dart';
import 'package:FLEETRA/src/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utility/app_theme.dart';
import '../../widgets/offline_barner.dart';
import '../settings/settings.dart';
import '../stoeln vehicle/stolen_alert.dart';
import '../subscriptions/renewal_payment_screen.dart';
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
  bool   _userHasMovedMap  = false;

  late AnimationController _pulseController;
  late Animation<double>   _pulseAnimation;
  late AnimationController _markerAnimationController;
  Animation<double>? _latAnimation;
  Animation<double>? _lngAnimation;
  Animation<double>? _rotationAnimation;
  double _currentMarkerLat = 4.0734;
  double _currentMarkerLng = 9.7740;
  double _currentRotation  = 0.0;

  // ─── locked-button palette ────────────────────────────────────────────────
  // Grey background with fully-opaque black text so labels are always readable.
  static const Color _lockedBg   = Color(0xFFEEEEEE);
  static const Color _lockedText = Colors.black;
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initializeApp();
    PaymentNotifier.instance.addListener(_onPaymentNotification);
  }

  void _onPaymentNotification() {
    if (!PaymentNotifier.instance.paymentSucceeded) return;
    PaymentNotifier.instance.consume();
    _handleVehiclesRefreshed();
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

    _alertSubscription = _controller!.safeZoneAlertStream.listen((data) {
      if (mounted) _showSafeZoneAlert(data);
    });

    _setupLocationListener();
  }

  int? _savedVehicleId;

  Future<void> _loadSavedVehicleId() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final savedId = prefs.getInt('current_vehicle_id');
      if (savedId != null) _savedVehicleId = savedId;
    } catch (e) {
      debugPrint('⚠️ Error loading saved vehicle ID: $e');
    }
  }

  void _setupLocationListener() {
    _controller?.addListener(() {
      if (_controller!.vehicleLat != _currentMarkerLat ||
          _controller!.vehicleLng != _currentMarkerLng) {
        _animateMarkerToNewPosition(
            _controller!.vehicleLat, _controller!.vehicleLng);
      }
    });
  }

  double _calculateBearing(double sLat, double sLng, double eLat, double eLng) {
    final dLon = (eLng - sLng) * (math.pi / 180);
    final y    = math.sin(dLon) * math.cos(eLat * math.pi / 180);
    final x    = math.cos(sLat * math.pi / 180) *
        math.sin(eLat * math.pi / 180) -
        math.sin(sLat * math.pi / 180) *
            math.cos(eLat * math.pi / 180) *
            math.cos(dLon);
    return (math.atan2(y, x) * (180 / math.pi) + 360) % 360;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R    = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a    = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  void _animateMarkerToNewPosition(double newLat, double newLng) {
    final distance   = _calculateDistance(_currentMarkerLat, _currentMarkerLng, newLat, newLng);
    final durationMs = distance < 10
        ? 500
        : distance < 100
        ? (1000 + distance * 10).clamp(1000, 2000).toInt()
        : 2500;
    final bearing = _calculateBearing(_currentMarkerLat, _currentMarkerLng, newLat, newLng);

    _markerAnimationController.duration = Duration(milliseconds: durationMs);
    _latAnimation = Tween<double>(begin: _currentMarkerLat, end: newLat).animate(
        CurvedAnimation(parent: _markerAnimationController, curve: Curves.easeInOut));
    _lngAnimation = Tween<double>(begin: _currentMarkerLng, end: newLng).animate(
        CurvedAnimation(parent: _markerAnimationController, curve: Curves.easeInOut));
    _rotationAnimation = Tween<double>(begin: _currentRotation, end: bearing).animate(
        CurvedAnimation(parent: _markerAnimationController, curve: Curves.easeInOut));

    _markerAnimationController.addListener(() {
      if (_latAnimation != null && _lngAnimation != null && _rotationAnimation != null) {
        setState(() {
          _currentMarkerLat = _latAnimation!.value;
          _currentMarkerLng = _lngAnimation!.value;
          _currentRotation  = _rotationAnimation!.value;
        });
      }
    });
    _markerAnimationController.forward(from: 0.0);
  }

  void _recenterMap() {
    if (_controller == null) return;
    _controller!.mapController?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(
        target: LatLng(_controller!.vehicleLat, _controller!.vehicleLng),
        zoom: 16,
      )),
    );
    setState(() => _userHasMovedMap = false);
  }

  Set<Marker> _createAnimatedMarkers() {
    if (_controller == null ||
        _controller!.selectedVehicle == null ||
        _controller!.customCarIcon == null) return {};
    return {
      Marker(
        markerId:   const MarkerId('vehicle'),
        position:   LatLng(_currentMarkerLat, _currentMarkerLng),
        icon:       _controller!.customCarIcon!,
        anchor:     const Offset(0.5, 0.5),
        rotation:   _currentRotation,
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
      setState(() => _selectedLanguage = prefs.getString('language') ?? 'en');
    }
  }

  @override
  void dispose() {
    PaymentNotifier.instance.removeListener(_onPaymentNotification);
    _pulseController.dispose();
    _markerAnimationController.dispose();
    _alertSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _handleVehiclesRefreshed() async {
    if (!mounted || _controller == null) return;
    await _controller!.reloadVehicles();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Text(
          _selectedLanguage == 'en' ? 'Subscription activated!' : 'Abonnement activé !',
          style: const TextStyle(fontSize: 13),
        ),
      ]),
      backgroundColor: const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      shape:  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // Full refresh: reloadVehicles (API vehicles + subscriptions) then
  // refresh (location, engine, geofence, safe zone, notifications).
  Future<void> _handleFullRefresh() async {
    if (_controller == null || _controller!.isOffline) return;
    await _controller!.reloadVehicles();
    if (!mounted) return;
    await _controller!.refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Text(
          _selectedLanguage == 'en' ? 'Refreshed' : 'Actualisé',
          style: const TextStyle(fontSize: 13),
        ),
      ]),
      backgroundColor: const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  // Called by ApiService._handleLogout() via NotificationService.navigatorKey
  // when the refresh token is expired and the session is unrecoverable.
  static void redirectToLogin() {
    NotificationService.navigatorKey.currentState
        ?.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _navigateToRenewal() {
    if (_controller == null) return;
    final vehicle = _controller!.selectedVehicle;
    if (vehicle == null) return;
    final vehicleName = vehicle.nickname.isNotEmpty
        ? vehicle.nickname
        : '${vehicle.brand} ${vehicle.model}'.trim();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubscriptionPlansScreen(
          vehicleId:    vehicle.id,
          vehicleName:  vehicleName,
          onSubscribed: (_) {},
        ),
      ),
    );
  }

  void _showSafeZoneAlert(Map<String, dynamic> alertData) {
    final title    = alertData['title'] ??
        (_selectedLanguage == 'en' ? 'Safe Zone Alert' : 'Alerte zone sécurisée');
    final message  = alertData['message'] ??
        (_selectedLanguage == 'en' ? 'Vehicle left safe zone' : 'Véhicule a quitté la zone sécurisée');
    final severity = alertData['severity'] ?? 'warning';
    final Color bgColor;
    final IconData icon;
    if (severity == 'info') {
      bgColor = const Color(0xFF10B981);
      icon    = Icons.check_circle_rounded;
    } else if (severity == 'warning') {
      bgColor = const Color(0xFFF59E0B);
      icon    = Icons.warning_amber_rounded;
    } else {
      bgColor = AppColors.error;
      icon    = Icons.notifications_active_rounded;
    }
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: bgColor,
        padding:         const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize:       MainAxisSize.min,
          children: [
            Text(title,
                style: AppTypography.subtitle1.copyWith(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(message,
                style: AppTypography.body2.copyWith(
                    color: Colors.white.withOpacity(0.95))),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            icon:  const Icon(Icons.close_rounded, color: Colors.white, size: 18),
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
        try { ScaffoldMessenger.of(context).hideCurrentMaterialBanner(); } catch (_) {}
      }
    });
  }

  void _handleGeofenceToggle() async {
    if (_controller == null || _controller!.isTogglingGeofence) return;
    final success = await _controller!.toggleGeofence();
    if (!mounted) return;
    if (!success && _controller!.isOffline) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          color: Colors.white, size: 20,
        ),
        SizedBox(width: AppSizes.spacingM),
        Expanded(
          child: Text(
            success
                ? (_controller!.geofenceEnabled
                ? (_selectedLanguage == 'en' ? 'Geofencing enabled'  : 'Géofence activée')
                : (_selectedLanguage == 'en' ? 'Geofencing disabled' : 'Géofence désactivée'))
                : (_selectedLanguage == 'en' ? 'Failed to toggle geofencing' : 'Échec'),
            style: AppTypography.body2.copyWith(color: Colors.white),
          ),
        ),
      ]),
      backgroundColor: success
          ? (_controller!.geofenceEnabled ? const Color(0xFF10B981) : const Color(0xFF64748B))
          : AppColors.error,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape:  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _handleSafeZoneToggle() async {
    if (_controller == null || _controller!.isTogglingSafeZone) return;
    final result = await _controller!.toggleSafeZone();
    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
          SizedBox(width: AppSizes.spacingM),
          Expanded(
            child: Text(
              _controller!.safeZoneEnabled
                  ? (_selectedLanguage == 'en' ? 'Safe Zone created!'  : 'Zone sécurisée créée!')
                  : (_selectedLanguage == 'en' ? 'Safe Zone deleted'   : 'Zone sécurisée supprimée'),
              style: AppTypography.body2.copyWith(color: Colors.white),
            ),
          ),
        ]),
        backgroundColor: _controller!.safeZoneEnabled
            ? const Color(0xFF10B981)
            : const Color(0xFF64748B),
        behavior: SnackBarBehavior.floating,
        shape:  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['message'] ??
            (_selectedLanguage == 'en' ? 'Failed to toggle safe zone' : 'Échec')),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape:  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  void _handleEngineToggle() async {
    if (_controller == null) return;
    final success = await _controller!.toggleEngine();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          color: Colors.white, size: 20,
        ),
        SizedBox(width: AppSizes.spacingM),
        Expanded(
          child: Text(
            success
                ? (_controller!.engineOn
                ? (_selectedLanguage == 'en' ? 'Engine unlocked'   : 'Moteur déverrouillé')
                : (_selectedLanguage == 'en' ? 'Engine locked'     : 'Moteur verrouillé'))
                : (_selectedLanguage == 'en' ? 'Failed to toggle engine' : 'Échec'),
            style: AppTypography.body2.copyWith(color: Colors.white),
          ),
        ),
      ]),
      backgroundColor: success
          ? (_controller!.engineOn ? const Color(0xFF10B981) : AppColors.error)
          : AppColors.error,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: success ? 2 : 3),
      shape:  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  Future<void> _handleReportStolen() async {
    if (_controller == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 28),
          ),
          SizedBox(width: AppSizes.spacingM),
          Expanded(
            child: Text(
              _selectedLanguage == 'en' ? 'Report Stolen?' : 'Signaler Volé?',
              style: AppTypography.h3,
            ),
          ),
        ]),
        content: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedLanguage == 'en' ? 'This will:' : 'Cela va:',
              style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: AppSizes.spacingM),
            _buildConfirmationItem(Icons.power_settings_new_rounded,
                _selectedLanguage == 'en' ? 'Disable engine immediately' : 'Désactiver le moteur'),
            _buildConfirmationItem(Icons.notification_add_rounded,
                _selectedLanguage == 'en' ? 'Create theft alert'         : 'Créer alerte de vol'),
            _buildConfirmationItem(Icons.my_location_rounded,
                _selectedLanguage == 'en' ? 'Show vehicle location'      : 'Afficher localisation'),
            _buildConfirmationItem(Icons.local_police_rounded,
                _selectedLanguage == 'en' ? 'Show nearby police'         : 'Afficher police'),
            SizedBox(height: AppSizes.spacingM),
            Container(
              padding: EdgeInsets.all(AppSizes.spacingM),
              decoration: BoxDecoration(
                color:        AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border:       Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, color: AppColors.error, size: 20),
                SizedBox(width: AppSizes.spacingS),
                Expanded(
                  child: Text(
                    _selectedLanguage == 'en'
                        ? 'This action cannot be undone'
                        : 'Action irréversible',
                    style: AppTypography.caption.copyWith(
                        color: AppColors.error, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_selectedLanguage == 'en' ? 'Cancel' : 'Annuler',
                style: AppTypography.button.copyWith(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(_selectedLanguage == 'en' ? 'Report Stolen' : 'Signaler',
                style: AppTypography.button.copyWith(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog(
      context:            context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          margin:  const EdgeInsets.all(32),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
            const SizedBox(height: 24),
            Text(
              _selectedLanguage == 'en'
                  ? 'Reporting stolen vehicle...'
                  : 'Signalement en cours...',
              style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      ),
    );

    final success = await _controller!.reportStolen();
    if (!mounted) return;
    Navigator.pop(context);

    if (success) {
      Navigator.push(context, MaterialPageRoute(
        builder: (context) => StolenAlertScreen(
          vehicleId:    _controller!.selectedVehicleId,
          vehicleLat:   _controller!.vehicleLat,
          vehicleLng:   _controller!.vehicleLng,
          vehicleName:  _controller!.selectedVehicle?.nickname.isNotEmpty == true
              ? _controller!.selectedVehicle!.nickname
              : '${_controller!.selectedVehicle?.brand ?? ''} '
              '${_controller!.selectedVehicle?.model ?? ''}'.trim(),
          nearbyPolice: _controller!.nearbyPolice,
        ),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          _selectedLanguage == 'en' ? 'Failed to report. Try again.' : 'Échec. Réessayez.',
          style: AppTypography.body1.copyWith(color: Colors.white),
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape:  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  Widget _buildConfirmationItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:        const Color(0xFF10B981).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF10B981), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: AppTypography.body2)),
      ]),
    );
  }

  void _showVehicleSelectorModal() {
    showModalBottomSheet(
      context:            context,
      backgroundColor:    Colors.transparent,
      isScrollControlled: true,
      useRootNavigator:   true,
      builder: (context) => _buildMinimalistVehicleSelector(),
    );
  }

  void _showEngineConfirmDialog(DashboardController controller) {
    showDialog(
      context: context,
      builder: (context) => EngineConfirmDialog(
        controller:       controller,
        onConfirm:        _handleEngineToggle,
        selectedLanguage: _selectedLanguage,
      ),
    );
  }

  void _showReportStolenDialog(DashboardController controller) {
    showDialog(
      context: context,
      builder: (context) => ReportStolenDialog(
        controller:       controller,
        onConfirm:        _handleReportStolen,
        selectedLanguage: _selectedLanguage,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

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

          final bool locked = !controller.hasActiveSubscription;

          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Column(children: [
                _buildCompactHeader(controller),
                const OfflineBanner(),
                Expanded(
                  child: Stack(children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(controller.vehicleLat, controller.vehicleLng),
                        zoom: 16,
                      ),
                      markers: _createAnimatedMarkers(),
                      circles: controller.activeSafeZone != null
                          ? {
                        Circle(
                          circleId:    const CircleId('safe_zone'),
                          center:      LatLng(
                            controller.activeSafeZone!.centerLatitude,
                            controller.activeSafeZone!.centerLongitude,
                          ),
                          radius:      controller.activeSafeZone!.radiusMeters.toDouble(),
                          fillColor:   const Color(0xFF10B981).withOpacity(0.15),
                          strokeColor: const Color(0xFF10B981),
                          strokeWidth: 2,
                        ),
                      }
                          : const {},
                      mapType:              controller.currentMapType,
                      onMapCreated:         controller.setMapController,
                      onCameraMove: (_) {
                        if (!_userHasMovedMap) setState(() => _userHasMovedMap = true);
                      },
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled:     false,
                      mapToolbarEnabled:       false,
                    ),

                    _buildCompactVehicleSelectorButton(controller),
                    _buildCompactMapTypeButton(controller),
                    _buildRecenterButton(controller),
                    _buildCompactEngineButton(controller, locked),
                    _buildCompactStolenButton(controller, locked),

                    if (controller.isReloadingVehicles)
                      Positioned(
                        top: 0, left: 0, right: 0,
                        child: Container(
                          color:   Colors.black.withOpacity(0.05),
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 12, height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5, color: Colors.black54),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _selectedLanguage == 'en'
                                    ? 'Updating...'
                                    : 'Mise à jour...',
                                style: const TextStyle(fontSize: 11, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ),

                    _buildBottomControls(controller, locked),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCompactHeader(DashboardController controller) {
    final bool busy = controller.isRefreshing || controller.isReloadingVehicles;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
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
            child: const Text('FLEETRA',
                style: TextStyle(
                  fontSize:   19,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Roboto',
                  color:      Colors.white,
                )),
          ),
          Row(children: [
            _buildSimpleIconButton(
              icon: busy
                  ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
                  : Icon(Icons.refresh_rounded,
                  size: 20,
                  color: controller.isOffline ? Colors.grey : Colors.black54),
              onTap: (busy || controller.isOffline) ? null : _handleFullRefresh,
            ),
            const SizedBox(width: 10),
            Stack(children: [
              _buildSimpleIconButton(
                icon: Icon(Icons.notifications_outlined,
                    size: 20,
                    color: controller.notificationCount > 0
                        ? Colors.black
                        : Colors.black54),
                onTap: () {
                  Navigator.pushNamed(context, '/notifications',
                      arguments: {'vehicleId': controller.selectedVehicleId})
                      .then((_) => controller.fetchUnreadNotifications());
                },
              ),
              if (controller.notificationCount > 0)
                Positioned(
                  right: 4, top: 4,
                  child: Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color:  AppColors.error,
                      shape:  BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 10),
            _buildSimpleIconButton(
              icon: const Icon(Icons.settings_outlined, size: 20, color: Colors.black54),
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SettingsScreen(vehicleId: widget.vehicleId)),
                );
                if (result == 'language_changed' && mounted) {
                  await _loadLanguagePreference();
                }
              },
            ),
          ]),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAP OVERLAY BUTTONS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCompactVehicleSelectorButton(DashboardController controller) {
    return Positioned(
      top: 12, left: 0, right: 0,
      child: Center(
        child: GestureDetector(
          onTap: _showVehicleSelectorModal,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.directions_car, color: Colors.black87, size: 18),
              const SizedBox(width: 8),
              Text(
                controller.selectedVehicle!.nickname.isNotEmpty
                    ? controller.selectedVehicle!.nickname
                    : controller.selectedVehicle!.immatriculation,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 13),
              ),
              const SizedBox(width: 4),
              if (controller.selectedVehicle!.isOnline)
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(
                      color: Color(0xFF10B981), shape: BoxShape.circle),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, color: Colors.black54, size: 16),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactMapTypeButton(DashboardController controller) {
    return Positioned(
      top: 12, left: 12,
      child: GestureDetector(
        onTap: controller.cycleMapType,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: Colors.white, shape: BoxShape.circle,
            boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: const Icon(Icons.layers, color: Colors.black87, size: 20),
        ),
      ),
    );
  }

  Widget _buildRecenterButton(DashboardController controller) {
    return Positioned(
      top: 62, left: 12,
      child: GestureDetector(
        onTap: _recenterMap,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: Colors.white, shape: BoxShape.circle,
            boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Icon(Icons.my_location_rounded,
              color: _userHasMovedMap ? const Color(0xFF1A73E8) : Colors.black38, size: 20),
        ),
      ),
    );
  }

  Widget _buildCompactEngineButton(DashboardController controller, bool locked) {
    final bool fullyDisabled = locked || controller.isOffline || controller.isTogglingEngine;
    return Positioned(
      top: 12, right: 12,
      child: Opacity(
        opacity: fullyDisabled ? 0.4 : 1.0,
        child: GestureDetector(
          onTap: fullyDisabled ? null : () => _showEngineConfirmDialog(controller),
          child: Container(
            width: 44, height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: locked
                  ? const Color(0xFFB0B0B0)
                  : (controller.engineOn ? Colors.white : const Color(0xFFEF4444)),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: controller.isTogglingEngine
                ? SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                  color: locked ? Colors.white : Colors.black87, strokeWidth: 2),
            )
                : Image.asset(
              locked || !controller.engineOn ? 'assets/lock.ico' : 'assets/open.ico',
              width: 24, height: 24,
              fit:            BoxFit.contain,
              color:          locked
                  ? Colors.white
                  : (controller.engineOn ? const Color(0xFF10B981) : Colors.white),
              colorBlendMode: BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactStolenButton(DashboardController controller, bool locked) {
    final bool fullyDisabled = locked || controller.isOffline || controller.isReportingStolen;
    return Positioned(
      top: 64, right: 12,
      child: Opacity(
        opacity: fullyDisabled ? 0.4 : 1.0,
        child: GestureDetector(
          onTap: fullyDisabled ? null : () => _showReportStolenDialog(controller),
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: locked ? const Color(0xFFB0B0B0) : const Color(0xFFEF4444),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: controller.isReportingStolen
                ? const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
                : Image.asset('assets/stolen.png',
              width: 24, height: 24,
              fit:            BoxFit.cover,
              color:          Colors.white,
              colorBlendMode: BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTTOM CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomControls(DashboardController controller, bool locked) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.2), width: 1)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Expanded(
                    child: _buildFeatureButton(
                      icon:      Icons.radio_button_checked_rounded,
                      label:     _selectedLanguage == 'en' ? 'Geofence' : 'Barrière\nVirtuelle',
                      isActive:  controller.geofenceEnabled,
                      isLoading: controller.isTogglingGeofence,
                      locked:    locked,
                      onTap:     _handleGeofenceToggle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildFeatureButton(
                      icon:      Icons.shield_rounded,
                      label:     _selectedLanguage == 'en' ? 'Safe Zone' : 'Zone\nSécurisée',
                      isActive:  controller.safeZoneEnabled,
                      isLoading: controller.isTogglingSafeZone,
                      locked:    locked,
                      onTap:     _handleSafeZoneToggle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildActionButton(
                      icon:   Icons.timeline_rounded,
                      label:  _selectedLanguage == 'en' ? 'Trip History' : 'Historique\nTrajet',
                      locked: locked,
                      onTap:  () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TripsScreen(vehicleId: controller.selectedVehicleId),
                        ),
                      ),
                    ),
                  ),
                ]),

                // No-subscription banner — only when selected vehicle is locked
                if (locked) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _navigateToRenewal,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                      decoration: BoxDecoration(
                        color:        AppColors.error.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.error.withOpacity(0.35), width: 1),
                      ),
                      child: Row(children: [
                        Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedLanguage == 'en'
                                ? 'No active subscription — tap to renew'
                                : 'Aucun abonnement actif — appuyer pour renouveler',
                            style: TextStyle(
                              fontSize:   12,
                              fontWeight: FontWeight.w600,
                              color:      AppColors.error,
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, color: AppColors.error, size: 12),
                      ]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Feature button (Geofence / Safe Zone) ──────────────────────────────────
  // locked  → solid _lockedBg (#EEEEEE) with bold black icon + text
  // unlocked → glassmorphic with coloured status dot
  Widget _buildFeatureButton({
    required IconData     icon,
    required String       label,
    required bool         isActive,
    required bool         isLoading,
    required bool         locked,
    required VoidCallback onTap,
  }) {
    final Color activeColor   = const Color(0xFF10B981);
    final Color inactiveColor = const Color(0xFFEF4444);

    return GestureDetector(
      onTap: locked || isLoading || (_controller?.isOffline ?? false) ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: locked ? _lockedBg : Colors.white.withOpacity(0.25),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: locked ? Colors.grey.shade400 : Colors.white.withOpacity(0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withOpacity(locked ? 0.06 : 0.10),
              blurRadius: 8,
              offset:     const Offset(0, 2),
            ),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color:        locked ? Colors.white : Colors.white.withOpacity(0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: isLoading
                  ? const Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                ),
              )
                  : Icon(icon, color: locked ? _lockedText : Colors.black87, size: 20),
            ),
            if (!locked)
              Positioned(
                top: -2, right: -2,
                child: Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color:  isActive ? activeColor : inactiveColor,
                    shape:  BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: (isActive ? activeColor : inactiveColor).withOpacity(0.6),
                        blurRadius: 4, spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize:   11,
                fontWeight: FontWeight.w700,
                color:      locked ? _lockedText : Colors.black87,
                height:     1.1,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
    );
  }

  // ── Action button (Trip History) ──────────────────────────────────────────
  // locked  → solid _lockedBg with bold black icon + text
  // unlocked → AppColors.primary fill
  Widget _buildActionButton({
    required IconData     icon,
    required String       label,
    required bool         locked,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: locked ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: locked ? _lockedBg : AppColors.primary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: locked ? Colors.grey.shade400 : AppColors.primary.withOpacity(0.8),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: locked
                  ? Colors.black.withOpacity(0.06)
                  : AppColors.primary.withOpacity(0.4),
              blurRadius: 8,
              offset:     const Offset(0, 2),
            ),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color:        locked ? Colors.white : Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: locked ? _lockedText : Colors.white, size: 20),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize:   11,
                fontWeight: FontWeight.w700,
                color:      locked ? _lockedText : Colors.white,
                height:     1.1,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VEHICLE SELECTOR BOTTOM SHEET
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMinimalistVehicleSelector() {
    if (_controller == null) return const SizedBox.shrink();
    final double bottomInset = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      bottom: true,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
        decoration: const BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 32, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _selectedLanguage == 'en' ? 'Select Vehicle' : 'Sélectionner véhicule',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.only(top: 4, bottom: bottomInset + 12),
              itemCount: _controller!.vehicles.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (context, index) {
                final vehicle    = _controller!.vehicles[index];
                final isSelected = vehicle.id == _controller!.selectedVehicleId;

                return InkWell(
                  onTap: () async {
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('current_vehicle_id', vehicle.id);
                      final displayName = vehicle.nickname?.isNotEmpty == true
                          ? vehicle.nickname as String
                          : vehicle.immatriculation;
                      await prefs.setString('vehicle_name_${vehicle.id}', displayName);
                      await prefs.setString('current_vehicle_name', displayName);
                    } catch (e) {
                      debugPrint('⚠️ Error saving vehicle ID: $e');
                    }
                    _controller!.onVehicleSelected(vehicle.id);
                    setState(() {
                      _currentMarkerLat = _controller!.vehicleLat;
                      _currentMarkerLng = _controller!.vehicleLng;
                      _currentRotation  = 0.0;
                      _userHasMovedMap  = false;
                    });
                    _recenterMap();
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: isSelected
                        ? AppColors.primary.withOpacity(0.05)
                        : Colors.transparent,
                    child: Row(children: [
                      Icon(Icons.directions_car,
                          color: isSelected ? AppColors.primary : Colors.grey.shade600,
                          size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vehicle.nickname?.isNotEmpty == true
                                  ? vehicle.nickname
                                  : '${vehicle.brand} ${vehicle.model}',
                              style: TextStyle(
                                fontSize:   14,
                                fontWeight: FontWeight.w600,
                                color:      isSelected ? AppColors.primary : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              vehicle.nickname?.isNotEmpty == true
                                  ? '${vehicle.brand} ${vehicle.model} — ${vehicle.immatriculation}'
                                  : vehicle.immatriculation,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: vehicle.hasActiveSubscription
                              ? const Color(0xFF10B981).withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            vehicle.hasActiveSubscription
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            size:  13,
                            color: vehicle.hasActiveSubscription
                                ? const Color(0xFF10B981)
                                : Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            vehicle.hasActiveSubscription
                                ? (_selectedLanguage == 'en' ? 'Active'  : 'Actif')
                                : (_selectedLanguage == 'en' ? 'No plan' : 'Sans plan'),
                            style: TextStyle(
                              fontSize:   10,
                              fontWeight: FontWeight.w600,
                              color:      vehicle.hasActiveSubscription
                                  ? const Color(0xFF10B981)
                                  : Colors.red,
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          color: vehicle.isOnline
                              ? const Color(0xFF10B981)
                              : Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                      ],
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildSimpleIconButton({required Widget icon, required VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(padding: const EdgeInsets.all(6), child: icon),
    );
  }
}