// lib/src/screens/dashboard/services/dashboard_controller.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui hide Codec;
import 'package:FLEETRA/src/screens/dashboard/services/safe_zone_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../services/env_config.dart';
import '../../../services/socket_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/cache_service.dart';
import '../../../services/api_service.dart';
import '../../../services/vehicles_refresh_service.dart';
import '../models/safe_zone_model.dart';
import '../models/vehicle_model.dart';
import 'dashboard_service.dart';

class DashboardController extends ChangeNotifier {
  // ─── Services ──────────────────────────────────────────────────────────────
  final ConnectivityService _connectivityService = ConnectivityService();
  final CacheService        _cacheService        = CacheService();
  final SocketService       _socketService       = SocketService();

  // ─── Core state ────────────────────────────────────────────────────────────
  bool     _isLoading           = true;
  bool     _isRefreshing        = false;
  bool     _isReloadingVehicles = false;
  bool     _geofenceEnabled     = true;
  bool     _safeZoneEnabled     = false;
  bool     _engineOn            = true;
  int      _selectedVehicleId   = 0;
  bool     _isTogglingGeofence  = false;
  bool     _isTogglingSafeZone  = false;
  bool     _isTogglingEngine    = false;
  bool     _isReportingStolen   = false;
  int      _notificationCount   = 0;
  MapType  _currentMapType      = MapType.normal;
  double   _vehicleLat          = 4.0511;
  double   _vehicleLng          = 9.7679;
  List<Vehicle> _vehicles       = [];
  BitmapDescriptor?    _customCarIcon;
  GoogleMapController? _mapController;
  DateTime? _lastLocationUpdate;
  String   _userType            = 'regular';

  // ─── Safe Zone geometry ────────────────────────────────────────────────────
  SafeZone? _activeSafeZone;
  SafeZone? get activeSafeZone => _activeSafeZone;

  // ─── Battery state ─────────────────────────────────────────────────────────
  int    _batteryPercentage = 0;
  double _batteryVoltage    = 0.0;
  bool   _isLowBattery      = false;

  // ─── Timers / subscriptions ────────────────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _alertSubscription;
  StreamSubscription<Map<String, dynamic>>? _locationSubscription;
  Timer? _cachePollingTimer;
  Timer? _engineVerificationTimer;
  Timer? _engineStatePollingTimer;
  int _pollAttempts = 0;
  static const int MAX_POLL_ATTEMPTS = 6;

  // ─── Getters ───────────────────────────────────────────────────────────────
  bool          get isLoading           => _isLoading;
  bool          get isRefreshing        => _isRefreshing;
  bool          get isReloadingVehicles => _isReloadingVehicles;
  bool          get geofenceEnabled     => _geofenceEnabled;
  bool          get safeZoneEnabled     => _safeZoneEnabled;
  bool          get engineOn            => _engineOn;
  int           get selectedVehicleId   => _selectedVehicleId;
  bool          get isTogglingGeofence  => _isTogglingGeofence;
  bool          get isTogglingSafeZone  => _isTogglingSafeZone;
  bool          get isTogglingEngine    => _isTogglingEngine;
  bool          get isReportingStolen   => _isReportingStolen;
  int           get notificationCount   => _notificationCount;
  MapType       get currentMapType      => _currentMapType;
  double        get vehicleLat          => _vehicleLat;
  double        get vehicleLng          => _vehicleLng;
  List<Vehicle> get vehicles            => _vehicles;
  BitmapDescriptor?    get customCarIcon  => _customCarIcon;
  GoogleMapController? get mapController => _mapController;
  List<dynamic> _nearbyPolice = [];
  List<dynamic> get nearbyPolice       => _nearbyPolice;
  DateTime?     get lastLocationUpdate => _lastLocationUpdate;
  String        get userType           => _userType;
  bool          get isChauffeur        => _userType == 'chauffeur';

  // Battery
  int    get batteryPercentage => _batteryPercentage;
  double get batteryVoltage    => _batteryVoltage;
  bool   get isLowBattery      => _isLowBattery;

  // Connectivity
  bool get isOnline  => _connectivityService.isOnline;
  bool get isOffline => _connectivityService.isOffline;

  /// Single source of truth for all 5 gated buttons.
  /// The dashboard reads this to decide disabled state — no sheet, no callback.
  bool get hasActiveSubscription =>
      selectedVehicle?.hasActiveSubscription ?? false;

  Vehicle? get selectedVehicle => _vehicles.isEmpty
      ? null
      : _vehicles.firstWhere(
        (v) => v.id == _selectedVehicleId,
    orElse: () => _vehicles[0],
  );

  // ─── Constructor ───────────────────────────────────────────────────────────
  DashboardController(int vehicleId) {
    _selectedVehicleId = vehicleId;
  }

  // ─── Parse SafeZone ────────────────────────────────────────────────────────
  SafeZone? _parseSafeZoneFromMap(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    try {
      return SafeZone.fromJson(raw);
    } catch (e) {
      debugPrint('⚠️ Failed to parse SafeZone: $e');
      return null;
    }
  }

  // ─── Validate vehicle ID ───────────────────────────────────────────────────
  Future<void> _validateAndUpdateVehicleId(int requestedVehicleId) async {
    if (_vehicles.isEmpty) return;

    final exists = _vehicles.any((v) => v.id == requestedVehicleId);
    if (exists) {
      _selectedVehicleId = requestedVehicleId;
    } else {
      _selectedVehicleId = _vehicles.first.id;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('current_vehicle_id', _selectedVehicleId);
      } catch (e) {
        debugPrint('⚠️ Error updating SharedPreferences: $e');
      }
    }
    notifyListeners();
  }

  // ─── Load user type ────────────────────────────────────────────────────────
  Future<void> _loadUserType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _userType = prefs.getString('user_type') ?? 'regular';
    } catch (e) {
      _userType = 'regular';
    }
  }

  // ─── Load vehicles from SharedPreferences ─────────────────────────────────
  Future<bool> _loadVehiclesFromPrefs() async {
    try {
      final prefs        = await SharedPreferences.getInstance();
      final vehiclesJson = prefs.getString('vehicles_list');

      if (vehiclesJson != null) {
        final List<dynamic> list = jsonDecode(vehiclesJson);
        if (list.isNotEmpty) {
          _vehicles = list
              .map((v) => Vehicle.fromJson(v as Map<String, dynamic>))
              .toList();
          await _cacheService.cacheVehicleList(
            list.map((v) => v as Map<String, dynamic>).toList(),
          );
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('⚠️ Error loading vehicles: $e');
      return false;
    }
  }

  // ─── Reload vehicles after successful payment ──────────────────────────────
  Future<void> reloadVehicles() async {
    if (isOffline) return;

    _isReloadingVehicles = true;
    notifyListeners();

    try {
      final refreshed = await VehiclesRefreshService.refreshVehiclesList();
      if (!refreshed) return;

      final prefs   = await SharedPreferences.getInstance();
      final rawJson = prefs.getString('vehicles_list');
      if (rawJson == null) return;

      final List<dynamic> raw = jsonDecode(rawJson) as List<dynamic>;
      _vehicles = raw
          .map((v) => Vehicle.fromJson(v as Map<String, dynamic>))
          .toList();

      if (!_vehicles.any((v) => v.id == _selectedVehicleId) &&
          _vehicles.isNotEmpty) {
        _selectedVehicleId = _vehicles.first.id;
      }

      await fetchDashboardData();
    } catch (e) {
      debugPrint('❌ reloadVehicles error: $e');
    } finally {
      _isReloadingVehicles = false;
      notifyListeners();
    }
  }

  // ─── Initialize ────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    try {
      await loadCustomMarker();
      await _loadUserType();

      if (isOffline) {
        await _loadFromCache();
      } else {
        await initializeDashboard();
        connectSocketAndListenForUpdates();
        startCachePolling();
      }
    } catch (error) {
      debugPrint('🔥 initialize error: $error');
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Load from cache ───────────────────────────────────────────────────────
  Future<void> _loadFromCache() async {
    try {
      final cachedVehicles = await _cacheService.getCachedVehicleList();
      if (cachedVehicles != null && cachedVehicles.isNotEmpty) {
        _vehicles = cachedVehicles.map((v) => Vehicle.fromJson(v)).toList();
      } else {
        await _loadVehiclesFromPrefs();
      }
      await _validateAndUpdateVehicleId(_selectedVehicleId);

      final details =
      await _cacheService.getCachedVehicleDetails(_selectedVehicleId);
      if (details != null) {
        _geofenceEnabled = details['geofenceEnabled'] ?? true;
        _safeZoneEnabled = details['safeZoneEnabled'] ?? false;
        _engineOn        = details['engineOn']        ?? true;
      }

      final location =
      await _cacheService.getCachedLastLocation(_selectedVehicleId);
      if (location != null) {
        _vehicleLat         = location['lat'];
        _vehicleLng         = location['lng'];
        _lastLocationUpdate = DateTime.parse(location['timestamp']);
      }
    } catch (e) {
      debugPrint('❌ _loadFromCache error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Load custom marker ────────────────────────────────────────────────────
  Future<void> loadCustomMarker() async {
    try {
      final ByteData data = await rootBundle.load('assets/carmarker.png');
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 100, targetHeight: 100,
      );
      final fi      = await codec.getNextFrame();
      final resized = await fi.image.toByteData(format: ui.ImageByteFormat.png);
      if (resized != null) {
        _customCarIcon = BitmapDescriptor.fromBytes(resized.buffer.asUint8List());
      } else {
        throw Exception('Resize failed');
      }
    } catch (e) {
      _customCarIcon = BitmapDescriptor.defaultMarker;
    }
  }

  // ─── Create markers ────────────────────────────────────────────────────────
  Set<Marker> createMarkers() {
    if (selectedVehicle == null || _customCarIcon == null) return {};
    return {
      Marker(
        markerId:   const MarkerId('vehicle'),
        position:   LatLng(_vehicleLat, _vehicleLng),
        icon:       _customCarIcon!,
        anchor:     const Offset(0.5, 0.5),
        infoWindow: InfoWindow(
          title: selectedVehicle!.nickname.isNotEmpty
              ? selectedVehicle!.nickname
              : '${selectedVehicle!.brand} ${selectedVehicle!.model}',
          snippet: selectedVehicle!.immatriculation,
        ),
      ),
    };
  }

  // ─── Initialize dashboard (online) ────────────────────────────────────────
  Future<void> initializeDashboard() async {
    try {
      await _loadVehiclesFromPrefs();
      await _fetchInitialLocation();
      await _validateAndUpdateVehicleId(_selectedVehicleId);
      _isLoading = false;
      notifyListeners();
      _loadBackgroundData();
    } catch (error) {
      debugPrint('🔥 initializeDashboard error: $error');
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchInitialLocation() async {
    try {
      if (isOffline) return;
      final result =
      await DashboardService.fetchCurrentLocation(_selectedVehicleId);
      if (result['success'] == true) {
        _vehicleLat         = result['latitude']  ?? 4.0511;
        _vehicleLng         = result['longitude'] ?? 9.7679;
        _lastLocationUpdate = DateTime.now();
        await _cacheService.cacheLastLocation(
          _selectedVehicleId, _vehicleLat, _vehicleLng, _lastLocationUpdate!,
        );
      }
    } catch (e) {
      _vehicleLat = 4.0511;
      _vehicleLng = 9.7679;
    }
  }

  // ─── Background data ───────────────────────────────────────────────────────
  // All errors are swallowed here — background polling must NEVER
  // trigger any UI interruption regardless of subscription state.
  Future<void> _loadBackgroundData() async {
    try {
      await Future.wait([
        fetchDashboardData(),
        fetchRealtimeEngineStatus(),
        fetchUnreadNotifications(),
      ]);
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ _loadBackgroundData error (silent): $e');
    }
  }

  // ─── Refresh ───────────────────────────────────────────────────────────────
  Future<void> refresh() async {
    if (isOffline) return;
    _isRefreshing = true;
    notifyListeners();
    try {
      await fetchDashboardData();
      await fetchRealtimeEngineStatus();
      await fetchCurrentLocation();
      await fetchUnreadNotifications();
    } catch (e) {
      debugPrint('⚠️ refresh error (silent): $e');
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> fetchVehicles() async {
    if (isOffline) { await _loadFromCache(); return; }
    final loaded = await _loadVehiclesFromPrefs();
    if (loaded) notifyListeners();
  }

  // ─── Fetch dashboard data ──────────────────────────────────────────────────
  Future<void> fetchDashboardData() async {
    if (isOffline) return;
    try {
      final geofencingActive =
      await DashboardService.fetchGeofencingStatus(_selectedVehicleId);
      _geofenceEnabled = geofencingActive ?? true;

      final safeZoneResult =
      await SafeZoneService.getSafeZone(_selectedVehicleId);
      if (safeZoneResult['success'] == true) {
        final rawZone = safeZoneResult['safeZone'] as Map<String, dynamic>?;
        _safeZoneEnabled = rawZone?['is_active'] ?? false;
        _activeSafeZone  = _parseSafeZoneFromMap(rawZone);
      } else {
        _safeZoneEnabled = false;
        _activeSafeZone  = null;
      }

      await _cacheService.cacheVehicleDetails(_selectedVehicleId, {
        'geofenceEnabled': _geofenceEnabled,
        'safeZoneEnabled': _safeZoneEnabled,
        'engineOn':        _engineOn,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ fetchDashboardData error (silent): $e');
      _geofenceEnabled = true;
      _safeZoneEnabled = false;
      _activeSafeZone  = null;
      notifyListeners();
    }
  }

  // ─── Fetch engine status ───────────────────────────────────────────────────
  Future<void> fetchRealtimeEngineStatus() async {
    if (isOffline) return;
    try {
      final data = await ApiService.get('/gps/location/$_selectedVehicleId');
      if (data['success'] == true) {
        _engineOn = (data['engine_status'] ?? 'OFF') == 'ON';
        if (data['raw_status'] is String &&
            (data['raw_status'] as String).isNotEmpty) {
          _parseVehicleStatus(data['raw_status']);
        }
        await _cacheService.cacheVehicleDetails(_selectedVehicleId, {
          'geofenceEnabled': _geofenceEnabled,
          'safeZoneEnabled': _safeZoneEnabled,
          'engineOn':        _engineOn,
        });
        notifyListeners();
      }
    } catch (e) {
      debugPrint('⚠️ fetchRealtimeEngineStatus error (silent): $e');
    }
  }

  void _parseVehicleStatus(String status) {
    try {
      final parts = status.split(',');
      if (parts.length >= 5) {
        final v = double.tryParse(parts[4]) ?? 0;
        if (v > 0) {
          if (v < 100) {
            _batteryPercentage = v.round();
            _batteryVoltage    = 0.0;
            _isLowBattery      = _batteryPercentage < 20;
          } else {
            _batteryVoltage    = v - 100;
            _isLowBattery      = _batteryVoltage < 3.6;
            _batteryPercentage = _batteryVoltage >= 3.3 && _batteryVoltage <= 4.2
                ? ((_batteryVoltage - 3.3) / (4.2 - 3.3) * 100).round()
                : _batteryVoltage > 4.2 ? 100 : 0;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ _parseVehicleStatus error: $e');
    }
  }

  // ─── Fetch location ────────────────────────────────────────────────────────
  Future<void> fetchCurrentLocation({bool silent = false}) async {
    if (isOffline) return;
    try {
      final result =
      await DashboardService.fetchCurrentLocation(_selectedVehicleId);
      if (result['success'] == true) {
        _vehicleLat         = result['latitude']  ?? 4.0511;
        _vehicleLng         = result['longitude'] ?? 9.7679;
        _lastLocationUpdate = DateTime.now();
        await _cacheService.cacheLastLocation(
          _selectedVehicleId, _vehicleLat, _vehicleLng, _lastLocationUpdate!,
        );
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(LatLng(_vehicleLat, _vehicleLng)),
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('⚠️ fetchCurrentLocation error (silent): $e');
    }
  }

  // ─── Fetch notifications ───────────────────────────────────────────────────
  Future<void> fetchUnreadNotifications() async {
    if (isOffline) return;
    try {
      final result =
      await DashboardService.fetchUnreadNotifications(_selectedVehicleId);
      if (result['success'] == true) {
        _notificationCount = result['unreadCount'];
        notifyListeners();
      }
    } catch (e) {
      debugPrint('⚠️ fetchUnreadNotifications error (silent): $e');
    }
  }

  // ─── Socket ────────────────────────────────────────────────────────────────
  void connectSocketAndListenForUpdates() {
    if (isOffline) return;
    final socketUrl = dotenv.env['SOCKET_URL'] ?? 'http://10.0.2.2:5000';

    SharedPreferences.getInstance().then((prefs) {
      int? userId;
      try {
        final userStr = prefs.getString('user');
        if (userStr != null) {
          userId = (jsonDecode(userStr)['id'] as num?)?.toInt();
        }
      } catch (_) {}
      _socketService.connect(socketUrl, userId: userId);
    });

    _socketService.connectionStatusStream.listen((connected) {
      if (connected) _socketService.joinVehicleTracking(_selectedVehicleId);
    });

    _alertSubscription = _socketService.safeZoneAlertStream.listen((_) {});

    _locationSubscription =
        _socketService.locationUpdateStream.listen((data) {
          if (data['vehicleId'] != _selectedVehicleId) return;
          final lat    = data['latitude'];
          final lon    = data['longitude'];
          if (lat == null || lon == null) return;

          _vehicleLat         = (lat as num).toDouble();
          _vehicleLng         = (lon as num).toDouble();
          _lastLocationUpdate = DateTime.now();

          _cacheService.cacheLastLocation(
            _selectedVehicleId, _vehicleLat, _vehicleLng, _lastLocationUpdate!,
          );

          if (data['status'] is String &&
              (data['status'] as String).isNotEmpty) {
            _parseVehicleStatus(data['status']);
          }

          _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(_vehicleLat, _vehicleLng)),
          );
          notifyListeners();
        });
  }

  Stream<Map<String, dynamic>> get safeZoneAlertStream =>
      _socketService.safeZoneAlertStream;

  void startCachePolling() {
    if (isOffline) return;
    _cachePollingTimer = Timer.periodic(
      const Duration(seconds: 5),
          (_) => fetchCurrentLocation(silent: true),
    );
  }

  // ─── Toggle geofence ───────────────────────────────────────────────────────
  Future<bool> toggleGeofence() async {
    if (isOffline || !hasActiveSubscription) return false;

    _isTogglingGeofence = true;
    notifyListeners();

    try {
      final data = await ApiService.post(
          '/vehicle/$_selectedVehicleId/security/toggle');
      final success =
          data['statusCode'] == 200 || data['statusCode'] == 201;

      if (success) {
        _geofenceEnabled = !_geofenceEnabled;
        await _cacheService.cacheVehicleDetails(_selectedVehicleId, {
          'geofenceEnabled': _geofenceEnabled,
          'safeZoneEnabled': _safeZoneEnabled,
          'engineOn':        _engineOn,
        });
      }
      return success;
    } catch (e) {
      debugPrint('🔥 toggleGeofence error: $e');
      return false;
    } finally {
      _isTogglingGeofence = false;
      notifyListeners();
    }
  }

  // ─── Toggle safe zone ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> toggleSafeZone() async {
    if (isOffline)              return {'success': false, 'message': 'No internet'};
    if (!hasActiveSubscription) return {'success': false, 'message': 'No active subscription'};
    if (_selectedVehicleId == 0) return {'success': false, 'message': 'Vehicle not ready'};

    _isTogglingSafeZone = true;
    notifyListeners();

    try {
      final safeZoneResult =
      await SafeZoneService.getSafeZone(_selectedVehicleId);
      final zoneExists = safeZoneResult['success'] == true &&
          safeZoneResult['safeZone'] != null;

      if (!zoneExists) {
        final result = await SafeZoneService.createSafeZone(
          vehicleId:    _selectedVehicleId,
          latitude:     _vehicleLat,
          longitude:    _vehicleLng,
          name:         'Home',
          radiusMeters: 10,
        );
        if (result['success'] == true) {
          _safeZoneEnabled = true;
          _activeSafeZone  = _parseSafeZoneFromMap(
              result['safeZone'] as Map<String, dynamic>?);
          await _cacheService.cacheVehicleDetails(_selectedVehicleId, {
            'geofenceEnabled': _geofenceEnabled,
            'safeZoneEnabled': _safeZoneEnabled,
            'engineOn':        _engineOn,
          });
          notifyListeners();
        }
        return result;
      }

      final zoneId =
      (safeZoneResult['safeZone'] as Map<String, dynamic>)['id'];
      final result = await SafeZoneService.deleteSafeZone(zoneId);

      if (result['success'] == true) {
        _safeZoneEnabled = false;
        _activeSafeZone  = null;
        await _cacheService.cacheVehicleDetails(_selectedVehicleId, {
          'geofenceEnabled': _geofenceEnabled,
          'safeZoneEnabled': _safeZoneEnabled,
          'engineOn':        _engineOn,
        });
        notifyListeners();
      }
      return result;
    } catch (e) {
      debugPrint('🔥 toggleSafeZone error: $e');
      return {'success': false, 'message': e.toString()};
    } finally {
      _isTogglingSafeZone = false;
      notifyListeners();
    }
  }

  // ─── Toggle engine ─────────────────────────────────────────────────────────
  Future<bool> toggleEngine() async {
    if (isOffline || !hasActiveSubscription) return false;

    _isTogglingEngine = true;
    notifyListeners();

    try {
      final command       = _engineOn ? 'CLOSERELAY' : 'OPENRELAY';
      final expectedState = !_engineOn;

      final data = await ApiService.post('/gps/issue-command', body: {
        'vehicleId': _selectedVehicleId,
        'command':   command,
        'params':    '',
        'password':  '',
        'sendTime':  '',
      });

      final ok = data['statusCode'] == 200 &&
          (data['success'] == true ||
              (data['response'] is Map &&
                  data['response']['success'] == 'true'));

      if (ok) {
        _engineOn = expectedState;
        await _cacheService.cacheVehicleDetails(_selectedVehicleId, {
          'geofenceEnabled': _geofenceEnabled,
          'safeZoneEnabled': _safeZoneEnabled,
          'engineOn':        _engineOn,
        });
        notifyListeners();
        _startEngineStatePolling(expectedState);
        return true;
      }
      throw Exception('Command failed');
    } catch (e) {
      debugPrint('🔥 toggleEngine error: $e');
      return false;
    } finally {
      _isTogglingEngine = false;
      notifyListeners();
    }
  }

  void _startEngineStatePolling(bool expectedState) {
    _engineStatePollingTimer?.cancel();
    _pollAttempts = 0;
    _engineStatePollingTimer =
        Timer.periodic(const Duration(seconds: 5), (timer) async {
          _pollAttempts++;
          try {
            final data = await ApiService.get(
                '/gps/vehicle/$_selectedVehicleId/realtime-status');
            if (data['success'] == true &&
                (data['engineOn'] ?? false) == expectedState) {
              _engineOn = expectedState;
              _cacheService.cacheVehicleDetails(_selectedVehicleId, {
                'geofenceEnabled': _geofenceEnabled,
                'safeZoneEnabled': _safeZoneEnabled,
                'engineOn':        _engineOn,
              });
              notifyListeners();
              timer.cancel();
            }
          } catch (_) {}
          if (_pollAttempts >= MAX_POLL_ATTEMPTS) timer.cancel();
        });
  }

  // ─── Report stolen ─────────────────────────────────────────────────────────
  Future<bool> reportStolen() async {
    if (isOffline || !hasActiveSubscription) return false;

    _isReportingStolen = true;
    notifyListeners();

    try {
      final prefs   = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr == null) return false;

      final userId = (jsonDecode(userStr)['id'] as num).toInt();

      final alertData = await ApiService.post('/alerts/report-stolen', body: {
        'vehicleId': _selectedVehicleId,
        'userId':    userId,
        'latitude':  _vehicleLat,
        'longitude': _vehicleLng,
      });

      if (alertData['statusCode'] != 200 && alertData['statusCode'] != 201) {
        return false;
      }

      _nearbyPolice = alertData['nearbyPolice'] ?? [];

      final cmdData = await ApiService.post('/gps/issue-command', body: {
        'vehicleId': _selectedVehicleId,
        'command':   'CLOSERELAY',
        'params':    '',
        'password':  '',
        'sendTime':  '',
      });

      final cmdOk = cmdData['statusCode'] == 200 &&
          (cmdData['success'] == true ||
              (cmdData['response'] is Map &&
                  cmdData['response']['success'] == 'true'));

      if (cmdOk) {
        _engineOn = false;
        await _cacheService.cacheVehicleDetails(_selectedVehicleId, {
          'geofenceEnabled': _geofenceEnabled,
          'safeZoneEnabled': _safeZoneEnabled,
          'engineOn':        _engineOn,
        });
        _startEngineStatePolling(false);
      }

      return true;
    } catch (e) {
      debugPrint('🔥 reportStolen error: $e');
      return false;
    } finally {
      _isReportingStolen = false;
      notifyListeners();
    }
  }

  // ─── Vehicle selection ─────────────────────────────────────────────────────
  void onVehicleSelected(int vehicleId) async {
    if (_selectedVehicleId == vehicleId) return;

    _socketService.leaveVehicleTracking(_selectedVehicleId);
    _selectedVehicleId = vehicleId;
    _isLoading         = true;
    _activeSafeZone    = null;
    _safeZoneEnabled   = false;
    notifyListeners();

    _socketService.joinVehicleTracking(vehicleId);

    if (isOnline) {
      fetchDashboardData();
      fetchRealtimeEngineStatus();
      fetchCurrentLocation();
      fetchUnreadNotifications();
    } else {
      _loadFromCache();
    }

    _isLoading = false;
    notifyListeners();
  }

  // ─── Map helpers ───────────────────────────────────────────────────────────
  void cycleMapType() {
    switch (_currentMapType) {
      case MapType.normal:    _currentMapType = MapType.satellite; break;
      case MapType.satellite: _currentMapType = MapType.hybrid;    break;
      case MapType.hybrid:    _currentMapType = MapType.terrain;   break;
      default:                _currentMapType = MapType.normal;
    }
    notifyListeners();
  }

  void setMapController(GoogleMapController c) => _mapController = c;

  Color hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) hex = '3B82F6';
    return Color(int.parse('ff$hex', radix: 16));
  }

  // ─── Dispose ───────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _cachePollingTimer?.cancel();
    _engineVerificationTimer?.cancel();
    _engineStatePollingTimer?.cancel();
    _alertSubscription?.cancel();
    _locationSubscription?.cancel();
    _socketService.leaveVehicleTracking(_selectedVehicleId);
    super.dispose();
  }
}