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
import '../models/vehicle_model.dart';
import 'dashboard_service.dart';

class DashboardController extends ChangeNotifier {
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

  // Battery State Variables
  int _batteryPercentage = 0;
  double _batteryVoltage = 0.0;
  bool _isLowBattery = false;

  // Socket Service
  final SocketService _socketService = SocketService();
  StreamSubscription<Map<String, dynamic>>? _alertSubscription;
  StreamSubscription<Map<String, dynamic>>? _locationSubscription;
  Timer? _cachePollingTimer;
  Timer? _engineVerificationTimer;

  // ✅ NEW: Background polling for engine state verification
  Timer? _engineStatePollingTimer;
  int _pollAttempts = 0;
  static const int MAX_POLL_ATTEMPTS = 6; // 6 attempts × 5 seconds = 30 seconds max

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

  // Battery Getters
  int get batteryPercentage => _batteryPercentage;
  double get batteryVoltage => _batteryVoltage;
  bool get isLowBattery => _isLowBattery;

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

  // ✅ OPTIMIZED: Initialize Dashboard with parallel loading
  Future<void> initialize() async {
    try {
      debugPrint('⚡ Starting FAST dashboard initialization...');

      // ✅ Load marker and critical data in parallel
      await Future.wait([
        loadCustomMarker(),
        initializeDashboard(),
      ]);

      // ✅ These can start without waiting
      connectSocketAndListenForUpdates();
      startCachePolling();

      debugPrint('✅ Dashboard fully initialized!');
    } catch (error) {
      debugPrint("🔥 Error initializing dashboard: $error");
      _isLoading = false;
      notifyListeners();
    }
  }

  // ✅ FASTER: Load marker asynchronously without blocking
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

  // ✅ OPTIMIZED: Fast initialization with progressive loading
  Future<void> initializeDashboard() async {
    try {
      debugPrint('⚡ Starting FAST dashboard initialization...');

      // ✅ STEP 1: Load ONLY critical data (vehicles + location) in parallel
      await Future.wait([
        fetchVehicles(),
        _fetchInitialLocation(),
      ]);

      debugPrint('✅ Critical data loaded! Showing map now...');

      // ✅ STEP 2: Show map immediately (under 3 seconds!)
      _isLoading = false;
      notifyListeners();

      debugPrint('🗺️ Map displayed! Loading remaining data in background...');

      // ✅ STEP 3: Load non-critical data in parallel (background)
      _loadBackgroundData();
    } catch (error) {
      debugPrint("🔥 Error initializing dashboard: $error");
      _isLoading = false;
      notifyListeners();
    }
  }

  // ✅ NEW: Fetch initial location without camera animation
  Future<void> _fetchInitialLocation() async {
    try {
      final result =
      await DashboardService.fetchCurrentLocation(_selectedVehicleId);

      if (result['success'] == true) {
        _vehicleLat = result['latitude'] ?? 4.0511;
        _vehicleLng = result['longitude'] ?? 9.7679;
        debugPrint("📍 Initial location loaded: $_vehicleLat, $_vehicleLng");
      }
    } catch (e) {
      debugPrint("⚠️ Error fetching initial location: $e");
      _vehicleLat = 4.0511;
      _vehicleLng = 9.7679;
    }
  }

  // ✅ NEW: Load non-critical data in background
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

  // Pull to Refresh
  Future<void> refresh() async {
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

  // Fetch Vehicles
  Future<void> fetchVehicles() async {
    final user = await DashboardService.loadUserData();
    if (user == null) return;

    final vehiclesData = await DashboardService.fetchVehicles(user["id"]);

    _vehicles = vehiclesData.map((v) => Vehicle.fromJson(v)).toList();
    debugPrint("✅ Loaded ${_vehicles.length} vehicles");
    notifyListeners();
  }

  /// Fetch Dashboard Data
  Future<void> fetchDashboardData() async {
    try {
      debugPrint('📡 ========== FETCHING DASHBOARD DATA ==========');

      // Fetch Geofencing Status
      debugPrint(
          '📡 Step 1: Fetching geofencing status for vehicle $_selectedVehicleId...');
      final geofencingActive =
      await DashboardService.fetchGeofencingStatus(_selectedVehicleId);

      if (geofencingActive != null) {
        _geofenceEnabled = geofencingActive;
        debugPrint(
            "✅ Geofence status fetched from backend: ${_geofenceEnabled ? 'ON (ACTIVE)' : 'OFF (INACTIVE)'}");
      } else {
        debugPrint("⚠️ Geofence status is null, defaulting to TRUE");
        _geofenceEnabled = true;
      }

      // Fetch Safe Zone Status
      debugPrint(
          '📡 Step 2: Fetching safe zone status for vehicle $_selectedVehicleId...');
      final safeZoneResult =
      await SafeZoneService.getSafeZone(_selectedVehicleId);

      if (safeZoneResult['needsLogin'] == true) {
        debugPrint("⚠️ Auth error detected - may need to re-login");
        _safeZoneEnabled = false;
      } else if (safeZoneResult['success']) {
        _safeZoneEnabled = safeZoneResult['safeZone']?['is_active'] ?? false;
        debugPrint(
            "✅ Safe zone status fetched from backend: ${_safeZoneEnabled ? 'ON (ACTIVE)' : 'OFF (INACTIVE)'}");
      } else {
        debugPrint("⚠️ Safe zone fetch failed, defaulting to FALSE");
        _safeZoneEnabled = false;
      }

      debugPrint('📡 ========== DASHBOARD DATA FETCH COMPLETE ==========');
      debugPrint('   🔵 Geofence: ${_geofenceEnabled ? "ENABLED" : "DISABLED"}');
      debugPrint(
          '   🟢 Safe Zone: ${_safeZoneEnabled ? "ENABLED" : "DISABLED"}');
      debugPrint('========================================================\n');

      notifyListeners();
    } catch (e) {
      debugPrint("🔥 ========== ERROR FETCHING DASHBOARD DATA ==========");
      debugPrint("🔥 Error: $e");
      debugPrint(
          "🔥 Setting default values - Geofence: TRUE, Safe Zone: FALSE");
      debugPrint("🔥 ====================================================\n");

      _geofenceEnabled = true;
      _safeZoneEnabled = false;
      notifyListeners();
    }
  }

  // ✅ UPDATED: Fetch REALTIME engine status from GPS device
  Future<void> fetchRealtimeEngineStatus() async {
    try {
      debugPrint('🔍 Fetching REALTIME engine status from GPS device...');

      final url =
          '${EnvConfig.baseUrl}/gps/vehicle/$_selectedVehicleId/realtime-status';

      final response = await http.get(Uri.parse(url));

      debugPrint('📡 Realtime engine status response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final bool newEngineState = data['engineOn'] ?? false;
          final String source = data['source'] ?? 'unknown';

          debugPrint(
              '✅ Engine status from GPS: ${newEngineState ? "ON (UNLOCKED)" : "OFF (LOCKED)"}');
          debugPrint('   📊 Source: $source');
          debugPrint('   📡 GPS Status: ${data['gpsStatus']}');
          debugPrint('   🚗 Speed: ${data['speed']} km/h');

          // Update engine state
          _engineOn = newEngineState;

          // Parse battery info from raw status if available
          if (data['rawStatus'] != null && data['rawStatus'].isNotEmpty) {
            _parseVehicleStatus(data['rawStatus']);
          }

          notifyListeners();
        } else {
          debugPrint('⚠️ Realtime engine status fetch unsuccessful');
        }
      } else {
        debugPrint(
            '❌ Failed to fetch realtime engine status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('🔥 Error fetching realtime engine status: $e');
    }
  }

  // ✅ KEPT FOR BACKWARD COMPATIBILITY: Fetch engine status from database
  Future<void> fetchEngineStatusFromDatabase() async {
    try {
      debugPrint('🔍 Fetching engine status from database...');

      final response = await http.get(
        Uri.parse(
            '${EnvConfig.baseUrl}/vehicle/$_selectedVehicleId/engine-status'),
      );

      debugPrint('📡 Engine status response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final bool newEngineState = data['engineOn'] ?? false;
          final int dataAge = data['dataAgeSeconds'] ?? 0;

          debugPrint(
              '✅ Engine status from DB: ${newEngineState ? "ON (UNLOCKED)" : "OFF (LOCKED)"}');
          debugPrint('   ⏰ Data age: $dataAge seconds');
          debugPrint('   📊 Raw status: ${data['rawStatus']}');

          _engineOn = newEngineState;

          if (data['rawStatus'] != null && data['rawStatus'].isNotEmpty) {
            _parseVehicleStatus(data['rawStatus']);
          }

          notifyListeners();
        } else {
          debugPrint('⚠️ Engine status fetch unsuccessful');
        }
      } else {
        debugPrint('❌ Failed to fetch engine status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('🔥 Error fetching engine status: $e');
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

          debugPrint(
              '🔋 Battery parsed: ${_batteryPercentage}% / ${_batteryVoltage}V (Low: $_isLowBattery)');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error parsing battery status: $e');
    }
  }

  // Fetch Current Location
  Future<void> fetchCurrentLocation({bool silent = false}) async {
    final result =
    await DashboardService.fetchCurrentLocation(_selectedVehicleId);

    if (result['success'] == true) {
      _vehicleLat = result['latitude'] ?? 4.0511;
      _vehicleLng = result['longitude'] ?? 9.7679;

      _mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(_vehicleLat, _vehicleLng)),
      );

      if (!silent) {
        debugPrint("📍 Location updated: $_vehicleLat, $_vehicleLng");
      }
      notifyListeners();
    }
  }

  // Fetch Unread Notifications
  Future<void> fetchUnreadNotifications() async {
    final result =
    await DashboardService.fetchUnreadNotifications(_selectedVehicleId);

    if (result['success'] == true) {
      _notificationCount = result['unreadCount'];
      debugPrint("🔔 Unread notifications: $_notificationCount");
      notifyListeners();
    }
  }

  // Connect Socket and Listen for Updates
  void connectSocketAndListenForUpdates() {
    final String socketUrl =
        dotenv.env['SOCKET_URL'] ?? 'http://10.0.2.2:5000';

    debugPrint(
        '🔌 Connecting to Socket.IO at $socketUrl for vehicle $_selectedVehicleId');

    _socketService.connect(socketUrl);

    _socketService.connectionStatusStream.listen((isConnected) {
      if (isConnected) {
        debugPrint('✅ Socket connected! Now joining vehicle tracking room...');
        _socketService.joinVehicleTracking(_selectedVehicleId);
      } else {
        debugPrint('❌ Socket disconnected');
      }
    });

    _alertSubscription = _socketService.safeZoneAlertStream.listen((alertData) {
      debugPrint('🚨 Safe Zone Alert received: $alertData');
    });

    _locationSubscription = _socketService.locationUpdateStream.listen((data) {
      debugPrint('📍 Real-time location update received: $data');

      final vehicleId = data['vehicleId'];
      if (vehicleId == _selectedVehicleId) {
        final lat = data['latitude'];
        final lon = data['longitude'];
        final status = data['status'];

        if (lat != null && lon != null) {
          _vehicleLat = lat is double ? lat : (lat as num).toDouble();
          _vehicleLng = lon is double ? lon : (lon as num).toDouble();

          if (status != null && status is String && status.isNotEmpty) {
            _parseVehicleStatus(status);
          }

          _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(_vehicleLat, _vehicleLng)),
          );

          debugPrint(
              '✅ Map updated with new position: $_vehicleLat, $_vehicleLng');
          notifyListeners();
        }
      }
    });
  }

  // Get Safe Zone Alert Stream
  Stream<Map<String, dynamic>> get safeZoneAlertStream =>
      _socketService.safeZoneAlertStream;

  // Start Cache Polling
  void startCachePolling() {
    _cachePollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      fetchCurrentLocation(silent: true);
    });
  }

  // Toggle Geofence
  Future<bool> toggleGeofence() async {
    _isTogglingGeofence = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse(
            "${EnvConfig.baseUrl}/vehicle/$_selectedVehicleId/security/toggle"),
        headers: {"Content-Type": "application/json"},
      );

      debugPrint("📡 Geofencing toggle response: ${response.statusCode}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        _geofenceEnabled = !_geofenceEnabled;
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

  // Toggle Safe Zone
  Future<Map<String, dynamic>> toggleSafeZone() async {
    _isTogglingSafeZone = true;
    notifyListeners();

    try {
      final safeZoneResult =
      await SafeZoneService.getSafeZone(_selectedVehicleId);

      if (!safeZoneResult['success'] || safeZoneResult['safeZone'] == null) {
        debugPrint('📍 No safe zone found. Creating new safe zone...');

        final createResult = await SafeZoneService.createSafeZone(
          vehicleId: _selectedVehicleId,
          latitude: _vehicleLat,
          longitude: _vehicleLng,
          name: 'Home',
          radiusMeters: 100,
        );

        _isTogglingSafeZone = false;

        if (createResult['success']) {
          _safeZoneEnabled = true;
          notifyListeners();
        }

        return createResult;
      } else {
        debugPrint('📍 Safe zone exists. Deleting safe zone...');

        final safeZoneId = safeZoneResult['safeZone']['id'];
        final deleteResult = await SafeZoneService.deleteSafeZone(safeZoneId);

        _isTogglingSafeZone = false;

        if (deleteResult['success']) {
          _safeZoneEnabled = false;
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

  // ✅ IMPROVED: Toggle Engine with optimistic UI + background polling
  Future<bool> toggleEngine() async {
    _isTogglingEngine = true;
    notifyListeners();

    try {
      final String command = _engineOn ? 'CLOSERELAY' : 'OPENRELAY';
      final bool expectedNewState = !_engineOn;

      debugPrint("🔧 ========== ENGINE TOGGLE STARTED ==========");
      debugPrint("🔧 Current engine state: ${_engineOn ? 'ON' : 'OFF'}");
      debugPrint("📤 Sending command: $command");
      debugPrint("🎯 Expected new state: ${expectedNewState ? 'ON' : 'OFF'}");

      // ✅ STEP 1: Send command to GPS device
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

      debugPrint("📡 Engine control response: ${resp.statusCode}");

      final data = jsonDecode(resp.body);
      final bool okTop = data['success'] == true;
      final bool okNested =
          (data['response'] is Map) && (data['response']['success'] == 'true');

      if (resp.statusCode == 200 && (okTop || okNested)) {
        debugPrint('✅ Command sent successfully to GPS device');

        // ✅ STEP 2: Immediate optimistic UI update (instant feedback)
        _engineOn = expectedNewState;
        _isTogglingEngine = false;
        notifyListeners();
        debugPrint('⚡ UI updated optimistically to: ${_engineOn ? "ON" : "OFF"}');

        // ✅ STEP 3: Start background polling to verify actual GPS state
        _startEngineStatePolling(expectedNewState);

        debugPrint("🔧 ========== ENGINE TOGGLE COMPLETED ==========");
        debugPrint("✅ UI state: ${_engineOn ? 'ON' : 'OFF'} (will verify in background)");
        debugPrint("================================================\n");

        return true;
      } else {
        throw Exception('Command failed - device may be offline');
      }
    } catch (error) {
      debugPrint("🔥 Error toggling engine: $error");
      _isTogglingEngine = false;
      notifyListeners();
      return false;
    }
  }

  // ✅ NEW: Start background polling to verify engine state
  void _startEngineStatePolling(bool expectedState) {
    // Cancel any existing polling
    _engineStatePollingTimer?.cancel();
    _pollAttempts = 0;

    debugPrint("🔄 Starting background engine state polling...");
    debugPrint("   Expected state: ${expectedState ? 'ON' : 'OFF'}");
    debugPrint("   Will poll every 5 seconds (max 30 seconds)");

    _engineStatePollingTimer =
        Timer.periodic(Duration(seconds: 5), (timer) async {
          _pollAttempts++;

          debugPrint("🔍 Poll attempt $_pollAttempts/$MAX_POLL_ATTEMPTS...");

          try {
            // Fetch realtime status
            final response = await http.get(
              Uri.parse(
                  '${EnvConfig.baseUrl}/gps/vehicle/$_selectedVehicleId/realtime-status'),
            );

            if (response.statusCode == 200) {
              final data = jsonDecode(response.body);

              if (data['success'] == true) {
                final bool actualState = data['engineOn'] ?? false;
                final String source = data['source'] ?? 'unknown';
                final int dataAge = data['dataAgeSeconds'] ?? 9999;

                debugPrint(
                    "📊 Poll result: Engine ${actualState ? 'ON' : 'OFF'} (source: $source, age: ${dataAge}s)");

                // ✅ Check if actual state matches expected state
                if (actualState == expectedState) {
                  debugPrint(
                      "✅ SUCCESS! GPS confirmed engine is ${actualState ? 'ON' : 'OFF'}");

                  // Update UI with confirmed state
                  _engineOn = actualState;
                  notifyListeners();

                  // Stop polling - we got confirmation!
                  timer.cancel();
                  _engineStatePollingTimer = null;
                  debugPrint("🛑 Stopped polling - state confirmed!");
                  return;
                } else {
                  debugPrint(
                      "⏳ Waiting... GPS still shows ${actualState ? 'ON' : 'OFF'}, expected ${expectedState ? 'ON' : 'OFF'}");
                }

                // ✅ If data is fresh (< 10 seconds) but wrong, update UI anyway
                if (dataAge < 10 && actualState != _engineOn) {
                  debugPrint(
                      "⚠️ Fresh GPS data shows different state - updating UI");
                  _engineOn = actualState;
                  notifyListeners();
                }
              }
            }
          } catch (e) {
            debugPrint("⚠️ Poll error: $e");
          }

          // ✅ Stop after max attempts
          if (_pollAttempts >= MAX_POLL_ATTEMPTS) {
            debugPrint("⏱️ Max polling attempts reached (30 seconds)");
            debugPrint("   Final UI state: ${_engineOn ? 'ON' : 'OFF'}");
            timer.cancel();
            _engineStatePollingTimer = null;
            debugPrint("🛑 Stopped polling - timeout");
          }
        });
  }

  Future<bool> reportStolen() async {
    _isReportingStolen = true;
    notifyListeners();

    try {
      debugPrint("🚨 Reporting vehicle as stolen");

      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');

      if (userDataString == null) {
        debugPrint("❌ No user data found");
        _isReportingStolen = false;
        notifyListeners();
        return false;
      }

      final userData = jsonDecode(userDataString);
      final int userId = userData['id'];

      debugPrint("📝 Creating stolen alert in database...");
      final alertResponse = await http.post(
        Uri.parse("${EnvConfig.baseUrl}/alerts/report-stolen"),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "vehicleId": _selectedVehicleId,
          "userId": userId,
          "latitude": _vehicleLat,
          "longitude": _vehicleLng,
        }),
      );

      debugPrint("📡 Alert creation response: ${alertResponse.statusCode}");

      if (alertResponse.statusCode != 201) {
        throw Exception('Failed to create stolen alert');
      }

      final alertData = jsonDecode(alertResponse.body);
      debugPrint("✅ Stolen alert created: ${alertData['alert']['id']}");

      debugPrint("🔧 Sending CLOSERELAY command to disable engine...");
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

      debugPrint("📡 Engine disable response: ${commandResponse.statusCode}");

      final commandData = jsonDecode(commandResponse.body);
      final bool commandOk = commandData['success'] == true ||
          (commandData['response'] is Map &&
              commandData['response']['success'] == 'true');

      if (commandResponse.statusCode == 200 && commandOk) {
        debugPrint('✅ Engine disabled successfully');
        _engineOn = false;

        // Start background polling for stolen report
        _startEngineStatePolling(false);
      } else {
        debugPrint(
            '⚠️ Engine disable command may have failed, but alert was created');
      }

      _isReportingStolen = false;
      notifyListeners();

      return true;
    } catch (error) {
      debugPrint("🔥 Error reporting stolen: $error");
      _isReportingStolen = false;
      notifyListeners();
      return false;
    }
  }

  // Change Vehicle
  void onVehicleSelected(int vehicleId) {
    if (_selectedVehicleId != vehicleId) {
      _socketService.leaveVehicleTracking(_selectedVehicleId);

      _selectedVehicleId = vehicleId;
      _isLoading = true;
      notifyListeners();

      _socketService.joinVehicleTracking(vehicleId);

      fetchDashboardData();
      fetchRealtimeEngineStatus();
      fetchCurrentLocation();
      fetchUnreadNotifications();

      _isLoading = false;
      notifyListeners();
    }
  }

  // Cycle Map Type
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

  // Get Map Type Label
  String getMapTypeLabel() {
    switch (_currentMapType) {
      case MapType.satellite:
        return 'Satellite';
      case MapType.hybrid:
        return 'Hybrid';
      case MapType.terrain:
        return 'Terrain';
      default:
        return 'Default';
    }
  }

  // Set Map Controller
  void setMapController(GoogleMapController controller) {
    _mapController = controller;
  }

  // Hex to Color Utility
  Color hexToColor(String hexString) {
    if (hexString.isEmpty) return Colors.blue;
    hexString = hexString.replaceAll('#', '');
    final validHex = RegExp(r'^[0-9a-fA-F]{6}$');
    if (!validHex.hasMatch(hexString)) {
      debugPrint('⚠️ Invalid color string: $hexString. Using fallback.');
      hexString = '3B82F6';
    }
    return Color(int.parse('ff$hexString', radix: 16));
  }

  // Dispose
  @override
  void dispose() {
    _cachePollingTimer?.cancel();
    _engineVerificationTimer?.cancel();
    _engineStatePollingTimer?.cancel(); // ✅ ADD THIS
    _alertSubscription?.cancel();
    _locationSubscription?.cancel();
    _socketService.leaveVehicleTracking(_selectedVehicleId);
    super.dispose();
  }
}