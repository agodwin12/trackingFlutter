// lib/src/screens/dashboard/services/dashboard_controller.dart

import 'dart:async';
import 'dart:convert';
import 'dart:convert' as ui;
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui hide Codec;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:tracking/src/screens/dashboard/services/safe_zone_service.dart';
import '../../../services/env_config.dart';
import '../../../services/socket_service.dart';
import '../../../services/connectivity_service.dart'; // ✅ NEW
import '../../../services/cache_service.dart'; // ✅ NEW
import '../models/vehicle_model.dart';
import 'dashboard_service.dart';

class DashboardController extends ChangeNotifier {
  // Services
  final ConnectivityService _connectivityService = ConnectivityService(); // ✅ NEW
  final CacheService _cacheService = CacheService(); // ✅ NEW
  final SocketService _socketService = SocketService();

  // State Variables
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _geofenceEnabled = true;
  bool _safeZoneEnabled = false;
  bool _engineOn = true;
  int _selectedVehicleId = 0;
  bool _isTogglingGeofence = false;
  bool _isTogglingSafeZone = false;
  bool _isTogglingEngine = false;
  bool _isReportingStolen = false;
  int _notificationCount = 0;
  MapType _currentMapType = MapType.normal;
  double _vehicleLat = 4.0511;
  double _vehicleLng = 9.7679;
  List<Vehicle> _vehicles = [];
  BitmapDescriptor? _customCarIcon;
  GoogleMapController? _mapController;
  DateTime? _lastLocationUpdate; // ✅ NEW - Track when location was last updated

  // Battery State Variables
  int _batteryPercentage = 0;
  double _batteryVoltage = 0.0;
  bool _isLowBattery = false;

  // Timers
  StreamSubscription<Map<String, dynamic>>? _alertSubscription;
  StreamSubscription<Map<String, dynamic>>? _locationSubscription;
  Timer? _cachePollingTimer;
  Timer? _engineVerificationTimer;
  Timer? _engineStatePollingTimer;
  int _pollAttempts = 0;
  static const int MAX_POLL_ATTEMPTS = 6;

  // Getters
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get geofenceEnabled => _geofenceEnabled;
  bool get safeZoneEnabled => _safeZoneEnabled;
  bool get engineOn => _engineOn;
  int get selectedVehicleId => _selectedVehicleId;
  bool get isTogglingGeofence => _isTogglingGeofence;
  bool get isTogglingSafeZone => _isTogglingSafeZone;
  bool get isTogglingEngine => _isTogglingEngine;
  bool get isReportingStolen => _isReportingStolen;
  int get notificationCount => _notificationCount;
  MapType get currentMapType => _currentMapType;
  double get vehicleLat => _vehicleLat;
  double get vehicleLng => _vehicleLng;
  List<Vehicle> get vehicles => _vehicles;
  BitmapDescriptor? get customCarIcon => _customCarIcon;
  GoogleMapController? get mapController => _mapController;
  List<dynamic> _nearbyPolice = [];
  List<dynamic> get nearbyPolice => _nearbyPolice;
  DateTime? get lastLocationUpdate => _lastLocationUpdate; // ✅ NEW

  // Battery Getters
  int get batteryPercentage => _batteryPercentage;
  double get batteryVoltage => _batteryVoltage;
  bool get isLowBattery => _isLowBattery;

  // ✅ NEW: Check if we're online
  bool get isOnline => _connectivityService.isOnline;
  bool get isOffline => _connectivityService.isOffline;

  Vehicle? get selectedVehicle => _vehicles.isEmpty
      ? null
      : _vehicles.firstWhere(
        (v) => v.id == _selectedVehicleId,
    orElse: () => _vehicles[0],
  );

  // Constructor
  DashboardController(int vehicleId) {
    _selectedVehicleId = vehicleId;
  }

  // ✅ UPDATED: Initialize with offline support
  Future<void> initialize() async {
    try {
      debugPrint('⚡ Starting dashboard initialization...');
      debugPrint('🌐 Connection status: ${isOnline ? "ONLINE" : "OFFLINE"}');

      // Load marker first (works offline)
      await loadCustomMarker();

      if (isOffline) {
        // ✅ OFFLINE MODE: Load from cache
        debugPrint('📱 OFFLINE MODE - Loading from cache...');
        await _loadFromCache();
      } else {
        // ✅ ONLINE MODE: Load from API and cache it
        debugPrint('🌐 ONLINE MODE - Loading from API...');
        await initializeDashboard();

        // Connect to real-time updates only when online
        connectSocketAndListenForUpdates();
        startCachePolling();
      }

      debugPrint('✅ Dashboard initialized!');
    } catch (error) {
      debugPrint("🔥 Error initializing dashboard: $error");
      _isLoading = false;
      notifyListeners();
    }
  }

  // ✅ NEW: Load data from cache (offline mode)
  Future<void> _loadFromCache() async {
    try {
      debugPrint('📦 Loading cached data...');

      // Load vehicles from cache
      final cachedVehicles = await _cacheService.getCachedVehicleList();
      if (cachedVehicles != null && cachedVehicles.isNotEmpty) {
        _vehicles = cachedVehicles.map((v) => Vehicle.fromJson(v)).toList();
        debugPrint('✅ Loaded ${_vehicles.length} vehicles from cache');
      }

      // Load vehicle details from cache
      final cachedDetails = await _cacheService.getCachedVehicleDetails(_selectedVehicleId);
      if (cachedDetails != null) {
        _geofenceEnabled = cachedDetails['geofenceEnabled'] ?? true;
        _safeZoneEnabled = cachedDetails['safeZoneEnabled'] ?? false;
        _engineOn = cachedDetails['engineOn'] ?? true;
        debugPrint('✅ Loaded vehicle details from cache');
      }

      // Load last known location from cache
      final cachedLocation = await _cacheService.getCachedLastLocation(_selectedVehicleId);
      if (cachedLocation != null) {
        _vehicleLat = cachedLocation['lat'];
        _vehicleLng = cachedLocation['lng'];
        _lastLocationUpdate = DateTime.parse(cachedLocation['timestamp']);

        final minutesAgo = DateTime.now().difference(_lastLocationUpdate!).inMinutes;
        debugPrint('✅ Loaded location from cache (${minutesAgo} minutes ago)');
      }

      _isLoading = false;
      notifyListeners();

      debugPrint('✅ Offline data loaded successfully');
    } catch (e) {
      debugPrint('❌ Error loading from cache: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load custom marker
  Future<void> loadCustomMarker() async {
    try {
      final ByteData data = await rootBundle.load('assets/carmarker.png');
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 60,
        targetHeight: 60,
      );
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ByteData? resizedData = await frameInfo.image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (resizedData != null) {
        _customCarIcon =
            BitmapDescriptor.fromBytes(resizedData.buffer.asUint8List());
        debugPrint('✅ Custom marker loaded (60x60)');
      } else {
        throw Exception('Failed to resize image');
      }
    } catch (e) {
      debugPrint('⚠️ Using default marker: $e');
      _customCarIcon = BitmapDescriptor.defaultMarker;
    }
  }

  // Create markers
  Set<Marker> createMarkers() {
    if (selectedVehicle == null || _customCarIcon == null) return {};

    return {
      Marker(
        markerId: const MarkerId('vehicle'),
        position: LatLng(_vehicleLat, _vehicleLng),
        icon: _customCarIcon!,
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(
          title: selectedVehicle!.nickname.isNotEmpty
              ? selectedVehicle!.nickname
              : '${selectedVehicle!.brand} ${selectedVehicle!.model}',
          snippet: selectedVehicle!.immatriculation,
        ),
      ),
    };
  }

  // ✅ UPDATED: Initialize dashboard with caching
  Future<void> initializeDashboard() async {
    try {
      debugPrint('⚡ Starting dashboard initialization...');

      // Load critical data in parallel
      await Future.wait([
        fetchVehicles(),
        _fetchInitialLocation(),
      ]);

      debugPrint('✅ Critical data loaded! Showing map now...');

      _isLoading = false;
      notifyListeners();

      debugPrint('🗺️ Map displayed! Loading remaining data in background...');

      // Load non-critical data in background
      _loadBackgroundData();
    } catch (error) {
      debugPrint("🔥 Error initializing dashboard: $error");
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fetch initial location
  Future<void> _fetchInitialLocation() async {
    try {
      if (isOffline) {
        debugPrint('📱 Offline - using cached location');
        return;
      }

      final result = await DashboardService.fetchCurrentLocation(_selectedVehicleId);

      if (result['success'] == true) {
        _vehicleLat = result['latitude'] ?? 4.0511;
        _vehicleLng = result['longitude'] ?? 9.7679;
        _lastLocationUpdate = DateTime.now();

        // ✅ Cache the location
        await _cacheService.cacheLastLocation(
          _selectedVehicleId,
          _vehicleLat,
          _vehicleLng,
          _lastLocationUpdate!,
        );

        debugPrint("📍 Initial location loaded: $_vehicleLat, $_vehicleLng");
      }
    } catch (e) {
      debugPrint("⚠️ Error fetching initial location: $e");
      _vehicleLat = 4.0511;
      _vehicleLng = 9.7679;
    }
  }

  // Load background data
  Future<void> _loadBackgroundData() async {
    try {
      await Future.wait([
        fetchDashboardData(),
        fetchRealtimeEngineStatus(),
        fetchUnreadNotifications(),
      ]);

      debugPrint('✅ All background data loaded!');
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ Error loading background data: $e');
      notifyListeners();
    }
  }

  // ✅ UPDATED: Refresh with offline check
  Future<void> refresh() async {
    if (isOffline) {
      debugPrint('📱 Cannot refresh while offline');
      return;
    }

    _isRefreshing = true;
    notifyListeners();

    try {
      await fetchDashboardData();
      await fetchRealtimeEngineStatus();
      await fetchCurrentLocation();
      await fetchUnreadNotifications();

      debugPrint("✅ Dashboard refreshed successfully");
    } catch (error) {
      debugPrint("🔥 Error refreshing dashboard: $error");
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  // ✅ UPDATED: Fetch vehicles with caching
  Future<void> fetchVehicles() async {
    if (isOffline) {
      debugPrint('📱 Offline - using cached vehicles');
      return;
    }

    final user = await DashboardService.loadUserData();
    if (user == null) return;

    final vehiclesData = await DashboardService.fetchVehicles(user["id"]);

    _vehicles = vehiclesData.map((v) => Vehicle.fromJson(v)).toList();

    // ✅ Cache the vehicle list with proper casting
    await _cacheService.cacheVehicleList(
        vehiclesData.map((v) => v as Map<String, dynamic>).toList()  // ✅ FIXED
    );

    debugPrint("✅ Loaded ${_vehicles.length} vehicles and cached them");
    notifyListeners();
  }

  // ✅ UPDATED: Fetch dashboard data with caching
  Future<void> fetchDashboardData() async {
    try {
      if (isOffline) {
        debugPrint('📱 Offline - using cached dashboard data');
        return;
      }

      debugPrint('📡 ========== FETCHING DASHBOARD DATA ==========');

      // Fetch geofencing status
      final geofencingActive =
      await DashboardService.fetchGeofencingStatus(_selectedVehicleId);

      if (geofencingActive != null) {
        _geofenceEnabled = geofencingActive;
        debugPrint("✅ Geofence status: ${_geofenceEnabled ? 'ON' : 'OFF'}");
      } else {
        _geofenceEnabled = true;
      }

      // Fetch safe zone status
      final safeZoneResult = await SafeZoneService.getSafeZone(_selectedVehicleId);

      if (safeZoneResult['success']) {
        _safeZoneEnabled = safeZoneResult['safeZone']?['is_active'] ?? false;
        debugPrint("✅ Safe zone status: ${_safeZoneEnabled ? 'ON' : 'OFF'}");
      } else {
        _safeZoneEnabled = false;
      }

      // ✅ Cache vehicle details
      await _cacheService.cacheVehicleDetails(_selectedVehicleId, {
        'geofenceEnabled': _geofenceEnabled,
        'safeZoneEnabled': _safeZoneEnabled,
        'engineOn': _engineOn,
      });

      notifyListeners();
    } catch (e) {
      debugPrint("🔥 Error fetching dashboard data: $e");
      _geofenceEnabled = true;
      _safeZoneEnabled = false;
      notifyListeners();
    }
  }

// ✅ UPDATED: Fetch ACTUAL engine status from GPS device
  Future<void> fetchRealtimeEngineStatus() async {
    try {
      if (isOffline) {
        debugPrint('📱 Offline - using cached engine status');
        return;
      }

      debugPrint('🔍 Fetching ACTUAL engine status from GPS device...');

      // ✅ Use the /location endpoint to get real GPS status
      final url = '${EnvConfig.baseUrl}/gps/location/$_selectedVehicleId';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          // ✅ Get engine_status from API (ON or OFF)
          final String engineStatus = data['engine_status'] ?? 'OFF';
          final bool newEngineState = (engineStatus == 'ON');

          debugPrint('✅ Actual GPS Engine Status: $engineStatus');
          debugPrint('✅ Engine boolean: $newEngineState');

          // ✅ Update the engine state
          _engineOn = newEngineState;

          // ✅ Parse battery if available
          if (data['raw_status'] != null && data['raw_status'].isNotEmpty) {
            _parseVehicleStatus(data['raw_status']);
          }

          // ✅ Update cache
          await _cacheService.cacheVehicleDetails(_selectedVehicleId, {
            'geofenceEnabled': _geofenceEnabled,
            'safeZoneEnabled': _safeZoneEnabled,
            'engineOn': _engineOn,
          });

          notifyListeners();
        }
      } else {
        debugPrint('⚠️ Failed to fetch engine status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('🔥 Error fetching realtime engine status: $e');
    }
  }

  void _parseVehicleStatus(String status) {
    try {
      final parts = status.split(',');

      if (parts.length >= 5) {
        final batteryValue = double.tryParse(parts[4]) ?? 0;

        if (batteryValue > 0) {
          if (batteryValue < 100) {
            _batteryPercentage = batteryValue.round();
            _batteryVoltage = 0.0;
            _isLowBattery = _batteryPercentage < 20;
          } else {
            _batteryVoltage = batteryValue - 100;
            _isLowBattery = _batteryVoltage < 3.6;

            if (_batteryVoltage >= 3.3 && _batteryVoltage <= 4.2) {
              _batteryPercentage =
                  ((_batteryVoltage - 3.3) / (4.2 - 3.3) * 100).round();
            } else if (_batteryVoltage > 4.2) {
              _batteryPercentage = 100;
            } else {
              _batteryPercentage = 0;
            }
          }

          debugPrint('🔋 Battery: ${_batteryPercentage}% / ${_batteryVoltage}V');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error parsing battery status: $e');
    }
  }

  // ✅ UPDATED: Fetch location with caching
  Future<void> fetchCurrentLocation({bool silent = false}) async {
    if (isOffline) {
      if (!silent) debugPrint('📱 Offline - using cached location');
      return;
    }

    final result = await DashboardService.fetchCurrentLocation(_selectedVehicleId);

    if (result['success'] == true) {
      _vehicleLat = result['latitude'] ?? 4.0511;
      _vehicleLng = result['longitude'] ?? 9.7679;
      _lastLocationUpdate = DateTime.now();

      // ✅ Cache the location
      await _cacheService.cacheLastLocation(
        _selectedVehicleId,
        _vehicleLat,
        _vehicleLng,
        _lastLocationUpdate!,
      );

      _mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(_vehicleLat, _vehicleLng)),
      );

      if (!silent) {
        debugPrint("📍 Location updated: $_vehicleLat, $_vehicleLng");
      }
      notifyListeners();
    }
  }

  // Fetch unread notifications
  Future<void> fetchUnreadNotifications() async {
    if (isOffline) return;

    final result = await DashboardService.fetchUnreadNotifications(_selectedVehicleId);

    if (result['success'] == true) {
      _notificationCount = result['unreadCount'];
      debugPrint("🔔 Unread notifications: $_notificationCount");
      notifyListeners();
    }
  }

  // Connect socket
  void connectSocketAndListenForUpdates() {
    if (isOffline) {
      debugPrint('📱 Offline - skipping socket connection');
      return;
    }

    final String socketUrl = dotenv.env['SOCKET_URL'] ?? 'http://10.0.2.2:5000';

    debugPrint('🔌 Connecting to Socket.IO at $socketUrl');

    _socketService.connect(socketUrl);

    _socketService.connectionStatusStream.listen((isConnected) {
      if (isConnected) {
        debugPrint('✅ Socket connected!');
        _socketService.joinVehicleTracking(_selectedVehicleId);
      } else {
        debugPrint('❌ Socket disconnected');
      }
    });

    _alertSubscription = _socketService.safeZoneAlertStream.listen((alertData) {
      debugPrint('🚨 Safe Zone Alert: $alertData');
    });

    _locationSubscription = _socketService.locationUpdateStream.listen((data) {
      final vehicleId = data['vehicleId'];
      if (vehicleId == _selectedVehicleId) {
        final lat = data['latitude'];
        final lon = data['longitude'];
        final status = data['status'];

        if (lat != null && lon != null) {
          _vehicleLat = lat is double ? lat : (lat as num).toDouble();
          _vehicleLng = lon is double ? lon : (lon as num).toDouble();
          _lastLocationUpdate = DateTime.now();

          // ✅ Cache real-time location
          _cacheService.cacheLastLocation(
            _selectedVehicleId,
            _vehicleLat,
            _vehicleLng,
            _lastLocationUpdate!,
          );

          if (status != null && status is String && status.isNotEmpty) {
            _parseVehicleStatus(status);
          }

          _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(_vehicleLat, _vehicleLng)),
          );

          notifyListeners();
        }
      }
    });
  }

  Stream<Map<String, dynamic>> get safeZoneAlertStream =>
      _socketService.safeZoneAlertStream;

  void startCachePolling() {
    if (isOffline) return;

    _cachePollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      fetchCurrentLocation(silent: true);
    });
  }

  // ✅ UPDATED: Toggle geofence with offline check
  Future<bool> toggleGeofence() async {
    if (isOffline) {
      debugPrint('❌ Cannot toggle geofence while offline');
      return false;
    }

    _isTogglingGeofence = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse("${EnvConfig.baseUrl}/vehicle/$_selectedVehicleId/security/toggle"),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _geofenceEnabled = !_geofenceEnabled;

        // ✅ Update cache
        await _cacheService.cacheVehicleDetails(_selectedVehicleId, {
          'geofenceEnabled': _geofenceEnabled,
          'safeZoneEnabled': _safeZoneEnabled,
          'engineOn': _engineOn,
        });

        _isTogglingGeofence = false;
        notifyListeners();
        return true;
      }
      return false;
    } catch (error) {
      debugPrint("🔥 Error toggling geofencing: $error");
      _isTogglingGeofence = false;
      notifyListeners();
      return false;
    }
  }

// ✅ UPDATED: Toggle safe zone with offline check
  Future<Map<String, dynamic>> toggleSafeZone() async {
    if (isOffline) {
      debugPrint('❌ Cannot toggle safe zone while offline');
      return {'success': false, 'message': 'No internet connection'};
    }

    _isTogglingSafeZone = true;
    notifyListeners();

    try {
      final safeZoneResult = await SafeZoneService.getSafeZone(_selectedVehicleId);

      if (!safeZoneResult['success'] || safeZoneResult['safeZone'] == null) {
        final createResult = await SafeZoneService.createSafeZone(
          vehicleId: _selectedVehicleId,
          latitude: _vehicleLat,
          longitude: _vehicleLng,
          name: 'Home',
          radiusMeters: 10,  // ✅ CHANGED FROM 100 TO 10
        );

        _isTogglingSafeZone = false;

        if (createResult['success']) {
          _safeZoneEnabled = true;

          // ✅ Update cache
          await _cacheService.cacheVehicleDetails(_selectedVehicleId, {
            'geofenceEnabled': _geofenceEnabled,
            'safeZoneEnabled': _safeZoneEnabled,
            'engineOn': _engineOn,
          });

          notifyListeners();
        }

        return createResult;
      } else {
        final safeZoneId = safeZoneResult['safeZone']['id'];
        final deleteResult = await SafeZoneService.deleteSafeZone(safeZoneId);

        _isTogglingSafeZone = false;

        if (deleteResult['success']) {
          _safeZoneEnabled = false;

          // ✅ Update cache
          await _cacheService.cacheVehicleDetails(_selectedVehicleId, {
            'geofenceEnabled': _geofenceEnabled,
            'safeZoneEnabled': _safeZoneEnabled,
            'engineOn': _engineOn,
          });

          notifyListeners();
        }

        return deleteResult;
      }
    } catch (error) {
      debugPrint('🔥 Error toggling safe zone: $error');
      _isTogglingSafeZone = false;
      notifyListeners();
      return {'success': false, 'message': error.toString()};
    }
  }

  // ✅ UPDATED: Toggle engine with offline check
  Future<bool> toggleEngine() async {
    if (isOffline) {
      debugPrint('❌ Cannot control engine while offline');
      return false;
    }

    _isTogglingEngine = true;
    notifyListeners();

    try {
      final String command = _engineOn ? 'CLOSERELAY' : 'OPENRELAY';
      final bool expectedNewState = !_engineOn;

      debugPrint("🔧 Sending command: $command");

      final resp = await http.post(
        Uri.parse("${EnvConfig.baseUrl}/gps/issue-command"),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "vehicleId": _selectedVehicleId,
          "command": command,
          "params": "",
          "password": "",
          "sendTime": "",
        }),
      );

      final data = jsonDecode(resp.body);
      final bool okTop = data['success'] == true;
      final bool okNested = (data['response'] is Map) && (data['response']['success'] == 'true');

      if (resp.statusCode == 200 && (okTop || okNested)) {
        _engineOn = expectedNewState;
        _isTogglingEngine = false;

        // ✅ Update cache
        await _cacheService.cacheVehicleDetails(_selectedVehicleId, {
          'geofenceEnabled': _geofenceEnabled,
          'safeZoneEnabled': _safeZoneEnabled,
          'engineOn': _engineOn,
        });

        notifyListeners();

        _startEngineStatePolling(expectedNewState);

        return true;
      } else {
        throw Exception('Command failed');
      }
    } catch (error) {
      debugPrint("🔥 Error toggling engine: $error");
      _isTogglingEngine = false;
      notifyListeners();
      return false;
    }
  }

  void _startEngineStatePolling(bool expectedState) {
    _engineStatePollingTimer?.cancel();
    _pollAttempts = 0;

    _engineStatePollingTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      _pollAttempts++;

      try {
        final response = await http.get(
          Uri.parse('${EnvConfig.baseUrl}/gps/vehicle/$_selectedVehicleId/realtime-status'),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          if (data['success'] == true) {
            final bool actualState = data['engineOn'] ?? false;

            if (actualState == expectedState) {
              _engineOn = actualState;

              // ✅ Update cache
              _cacheService.cacheVehicleDetails(_selectedVehicleId, {
                'geofenceEnabled': _geofenceEnabled,
                'safeZoneEnabled': _safeZoneEnabled,
                'engineOn': _engineOn,
              });

              notifyListeners();
              timer.cancel();
              return;
            }
          }
        }
      } catch (e) {
        debugPrint("⚠️ Poll error: $e");
      }

      if (_pollAttempts >= MAX_POLL_ATTEMPTS) {
        timer.cancel();
      }
    });
  }

// ✅ UPDATED: Report stolen with offline check
  Future<bool> reportStolen() async {
    if (isOffline) {
      debugPrint('❌ Cannot report stolen while offline');
      return false;
    }

    _isReportingStolen = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');

      if (userDataString == null) {
        _isReportingStolen = false;
        notifyListeners();
        return false;
      }

      final userData = jsonDecode(userDataString);
      final int userId = userData['id'];

      final requestBody = {
        "vehicleId": _selectedVehicleId,
        "userId": userId,
        "latitude": _vehicleLat,
        "longitude": _vehicleLng,
      };

      // 1️⃣ Create/fetch stolen alert
      final alertResponse = await http.post(
        Uri.parse("${EnvConfig.baseUrl}/alerts/report-stolen"),
        headers: {"Content-Type": "application/json"},
        body: json.encode(requestBody),
      );

      if (alertResponse.statusCode != 200 && alertResponse.statusCode != 201) {
        _isReportingStolen = false;
        notifyListeners();
        return false;
      }

      final alertData = jsonDecode(alertResponse.body);
      final bool alreadyReported = alertData['alreadyReported'] ?? false;
      final List<dynamic> nearbyPolice = alertData['nearbyPolice'] ?? [];

      debugPrint('🚨 Alert ${alreadyReported ? "already exists" : "created"}. Securing vehicle...');

      // 2️⃣ ✅ ALWAYS send CLOSERELAY command (removed the if (!alreadyReported) check)
      final commandResponse = await http.post(
        Uri.parse("${EnvConfig.baseUrl}/gps/issue-command"),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "vehicleId": _selectedVehicleId,
          "command": "CLOSERELAY",
          "params": "",
          "password": "",
          "sendTime": "",
        }),
      );

      final commandData = jsonDecode(commandResponse.body);
      final bool commandOk = commandData['success'] == true ||
          (commandData['response'] is Map && commandData['response']['success'] == 'true');

      if (commandResponse.statusCode == 200 && commandOk) {
        debugPrint('✅ Engine CLOSERELAY command sent successfully');
        _engineOn = false;

        // ✅ Update cache
        await _cacheService.cacheVehicleDetails(_selectedVehicleId, {
          'geofenceEnabled': _geofenceEnabled,
          'safeZoneEnabled': _safeZoneEnabled,
          'engineOn': _engineOn,
        });

        _startEngineStatePolling(false);
      } else {
        debugPrint('⚠️ Engine command failed or returned error');
      }

      _isReportingStolen = false;
      notifyListeners();

      _nearbyPolice = nearbyPolice;

      return true;
    } catch (error) {
      debugPrint("🔥 Error reporting stolen: $error");
      _isReportingStolen = false;
      notifyListeners();
      return false;
    }
  }

  void onVehicleSelected(int vehicleId) {
    if (_selectedVehicleId != vehicleId) {
      _socketService.leaveVehicleTracking(_selectedVehicleId);

      _selectedVehicleId = vehicleId;
      _isLoading = true;
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
  }

  void cycleMapType() {
    switch (_currentMapType) {
      case MapType.normal:
        _currentMapType = MapType.satellite;
        break;
      case MapType.satellite:
        _currentMapType = MapType.hybrid;
        break;
      case MapType.hybrid:
        _currentMapType = MapType.terrain;
        break;
      case MapType.terrain:
        _currentMapType = MapType.normal;
        break;
      default:
        _currentMapType = MapType.normal;
    }
    notifyListeners();
  }

  String getMapTypeLabel() {
    switch (_currentMapType) {
      case MapType.satellite:
        return 'Satellite';
      case MapType.hybrid:
        return 'Hybrid';
      case MapType.terrain:
        return 'Terrain';
      default:
        return '';
    }
  }

  void setMapController(GoogleMapController controller) {
    _mapController = controller;
  }

  Color hexToColor(String hexString) {
    if (hexString.isEmpty) return Colors.blue;
    hexString = hexString.replaceAll('#', '');
    final validHex = RegExp(r'^[0-9a-fA-F]{6}$');
    if (!validHex.hasMatch(hexString)) {
      hexString = '3B82F6';
    }
    return Color(int.parse('ff$hexString', radix: 16));
  }

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