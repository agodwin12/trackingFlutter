// lib/controllers/dashboard_controller.dart

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

  // ✅ NEW: Battery State Variables
  int _batteryPercentage = 0;
  double _batteryVoltage = 0.0;
  bool _isLowBattery = false;

  // Socket Service
  final SocketService _socketService = SocketService();
  StreamSubscription<Map<String, dynamic>>? _alertSubscription;
  StreamSubscription<Map<String, dynamic>>? _locationSubscription;
  Timer? _cachePollingTimer;

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

  //  Battery Getters
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


  // Initialize Dashboard
  Future<void> initialize() async {
    try {
      await loadCustomMarker();
      await initializeDashboard();
      connectSocketAndListenForUpdates();
      startCachePolling();
    } catch (error) {
      debugPrint("🔥 Error initializing dashboard controller: $error");
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load Custom Marker
  Future<void> loadCustomMarker() async {
    try {
      final ByteData data = await rootBundle.load('assets/carmarker.png');
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 80, // ✅ Adjust this value (try 60, 80, 100, 120)
        targetHeight: 80, // ✅ Keep same as width for proportional scaling
      );
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ByteData? resizedData = await frameInfo.image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (resizedData != null) {
        _customCarIcon = BitmapDescriptor.fromBytes(resizedData.buffer.asUint8List());
        debugPrint('✅ Custom car marker loaded and resized to 80x80');
      } else {
        throw Exception('Failed to resize image');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load custom marker: $e');
      _customCarIcon = BitmapDescriptor.defaultMarker;
    }
  }
// Update the createMarkers function
  Set<Marker> createMarkers() {
    if (selectedVehicle == null || _customCarIcon == null) return {};

    return {
      Marker(
        markerId: const MarkerId('vehicle'),
        position: LatLng(_vehicleLat, _vehicleLng),
        icon: _customCarIcon!,
        anchor: const Offset(0.5, 0.5), // ✅ Center the marker
        infoWindow: InfoWindow(
          title: selectedVehicle!.nickname.isNotEmpty
              ? selectedVehicle!.nickname
              : '${selectedVehicle!.brand} ${selectedVehicle!.model}',
          snippet: selectedVehicle!.immatriculation,
        ),
      ),
    };
  }


  // Initialize Dashboard Data
  Future<void> initializeDashboard() async {
    try {
      await fetchVehicles();
      await Future.delayed(Duration(milliseconds: 100));

      await fetchDashboardData();
      await Future.delayed(Duration(milliseconds: 100));

      // ✅ NEW: Fetch engine status from database on load
      await fetchEngineStatusFromDatabase();
      await Future.delayed(Duration(milliseconds: 100));

      await fetchCurrentLocation();
      await Future.delayed(Duration(milliseconds: 100));

      await fetchUnreadNotifications();

      _isLoading = false;
      notifyListeners();
    } catch (error) {
      debugPrint("🔥 Error initializing dashboard: $error");
      _isLoading = false;
      notifyListeners();
    }
  }


  // Pull to Refresh
  Future<void> refresh() async {
    _isRefreshing = true;
    notifyListeners();

    try {
      await fetchDashboardData();
      await fetchEngineStatusFromDatabase(); // ✅ NEW: Refresh engine status too
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
      debugPrint('📡 Step 1: Fetching geofencing status for vehicle $_selectedVehicleId...');
      final geofencingActive = await DashboardService.fetchGeofencingStatus(_selectedVehicleId);

      if (geofencingActive != null) {
        _geofenceEnabled = geofencingActive;
        debugPrint("✅ Geofence status fetched from backend: ${_geofenceEnabled ? 'ON (ACTIVE)' : 'OFF (INACTIVE)'}");
      } else {
        debugPrint("⚠️ Geofence status is null, defaulting to TRUE");
        _geofenceEnabled = true;
      }

      // Fetch Safe Zone Status
      debugPrint('📡 Step 2: Fetching safe zone status for vehicle $_selectedVehicleId...');
      final safeZoneResult = await SafeZoneService.getSafeZone(_selectedVehicleId);

      if (safeZoneResult['needsLogin'] == true) {
        debugPrint("⚠️ Auth error detected - may need to re-login");
        _safeZoneEnabled = false;
      } else if (safeZoneResult['success']) {
        _safeZoneEnabled = safeZoneResult['safeZone']?['is_active'] ?? false;
        debugPrint("✅ Safe zone status fetched from backend: ${_safeZoneEnabled ? 'ON (ACTIVE)' : 'OFF (INACTIVE)'}");
      } else {
        debugPrint("⚠️ Safe zone fetch failed, defaulting to FALSE");
        _safeZoneEnabled = false;
      }

      debugPrint('📡 ========== DASHBOARD DATA FETCH COMPLETE ==========');
      debugPrint('   🔵 Geofence: ${_geofenceEnabled ? "ENABLED" : "DISABLED"}');
      debugPrint('   🟢 Safe Zone: ${_safeZoneEnabled ? "ENABLED" : "DISABLED"}');
      debugPrint('========================================================\n');

      notifyListeners();
    } catch (e) {
      debugPrint("🔥 ========== ERROR FETCHING DASHBOARD DATA ==========");
      debugPrint("🔥 Error: $e");
      debugPrint("🔥 Setting default values - Geofence: TRUE, Safe Zone: FALSE");
      debugPrint("🔥 ====================================================\n");

      _geofenceEnabled = true;
      _safeZoneEnabled = false;
      notifyListeners();
    }
  }


  // ✅ NEW: Fetch engine status from database (latest location record)
  Future<void> fetchEngineStatusFromDatabase() async {
    try {
      debugPrint('🔍 Fetching engine status from database...');

      final response = await http.get(
        Uri.parse('${EnvConfig.baseUrl}/vehicle/$_selectedVehicleId/engine-status'),
      );

      debugPrint('📡 Engine status response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final bool newEngineState = data['engineOn'] ?? false;
          final int dataAge = data['dataAgeSeconds'] ?? 0;

          debugPrint('✅ Engine status from DB: ${newEngineState ? "ON (UNLOCKED)" : "OFF (LOCKED)"}');
          debugPrint('   ⏰ Data age: $dataAge seconds');
          debugPrint('   📊 Raw status: ${data['rawStatus']}');

          // Update engine state
          _engineOn = newEngineState;

          // ✅ NEW: Parse battery info from raw status if available
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
      // Status format: "mil,oil,weight,temp,batteryV,powerV,gpscount,gsmlevel,..."
      final parts = status.split(',');

      if (parts.length >= 5) {
        final batteryValue = double.tryParse(parts[4]) ?? 0;

        if (batteryValue > 0) {
          if (batteryValue < 100) {
            // It's a percentage
            _batteryPercentage = batteryValue.round();
            _batteryVoltage = 0.0;
            _isLowBattery = _batteryPercentage < 20;
          } else {
            // It's voltage (subtract 100 to get actual voltage)
            _batteryVoltage = batteryValue - 100;
            _isLowBattery = _batteryVoltage < 3.6;

            // Estimate percentage from voltage
            // 4.2V = 100%, 3.7V = 50%, 3.3V = 0%
            if (_batteryVoltage >= 3.3 && _batteryVoltage <= 4.2) {
              _batteryPercentage = ((_batteryVoltage - 3.3) / (4.2 - 3.3) * 100).round();
            } else if (_batteryVoltage > 4.2) {
              _batteryPercentage = 100;
            } else {
              _batteryPercentage = 0;
            }
          }

          debugPrint('🔋 Battery parsed: ${_batteryPercentage}% / ${_batteryVoltage}V (Low: $_isLowBattery)');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error parsing battery status: $e');
    }
  }

  // Fetch Current Location
  Future<void> fetchCurrentLocation({bool silent = false}) async {
    final result = await DashboardService.fetchCurrentLocation(_selectedVehicleId);

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
    final result = await DashboardService.fetchUnreadNotifications(_selectedVehicleId);

    if (result['success'] == true) {
      _notificationCount = result['unreadCount'];
      debugPrint("🔔 Unread notifications: $_notificationCount");
      notifyListeners();
    }
  }

  // Connect Socket and Listen for Updates
  void connectSocketAndListenForUpdates() {
    final String socketUrl = dotenv.env['SOCKET_URL'] ?? 'http://10.0.2.2:5000';

    debugPrint('🔌 Connecting to Socket.IO at $socketUrl for vehicle $_selectedVehicleId');

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
      // Alert will be handled by the UI
    });

    _locationSubscription = _socketService.locationUpdateStream.listen((data) {
      debugPrint('📍 Real-time location update received: $data');

      final vehicleId = data['vehicleId'];
      if (vehicleId == _selectedVehicleId) {
        final lat = data['latitude'];
        final lon = data['longitude'];
        final status = data['status']; // ✅ NEW: Get status for battery parsing

        if (lat != null && lon != null) {
          _vehicleLat = lat is double ? lat : (lat as num).toDouble();
          _vehicleLng = lon is double ? lon : (lon as num).toDouble();

          // ✅ NEW: Parse battery info from status if available
          if (status != null && status is String && status.isNotEmpty) {
            _parseVehicleStatus(status);
          }

          _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(_vehicleLat, _vehicleLng)),
          );

          debugPrint('✅ Map updated with new position: $_vehicleLat, $_vehicleLng');
          notifyListeners();
        }
      }
    });
  }

  // Get Safe Zone Alert Stream
  Stream<Map<String, dynamic>> get safeZoneAlertStream => _socketService.safeZoneAlertStream;

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
        Uri.parse("${EnvConfig.baseUrl}/vehicle/$_selectedVehicleId/security/toggle"),
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
      final safeZoneResult = await SafeZoneService.getSafeZone(_selectedVehicleId);

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

// ✅ IMPROVED: Toggle Engine with retry logic
  Future<bool> toggleEngine() async {
    _isTogglingEngine = true;
    notifyListeners();

    try {
      final String command = _engineOn ? 'CLOSERELAY' : 'OPENRELAY';
      final bool expectedNewState = !_engineOn; // What we expect after command

      debugPrint("🔧 Current engine state: ${_engineOn ? 'ON' : 'OFF'}");
      debugPrint("📤 Sending command: $command");
      debugPrint("🎯 Expected new state: ${expectedNewState ? 'ON' : 'OFF'}");

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
      final bool okNested = (data['response'] is Map) && (data['response']['success'] == 'true');

      if (resp.statusCode == 200 && (okTop || okNested)) {
        debugPrint('✅ Command sent successfully');

        // ✅ Force GPS update immediately
        debugPrint('🔄 Triggering immediate GPS fetch...');
        try {
          await http.post(
            Uri.parse("${EnvConfig.baseUrl}/vehicle/$_selectedVehicleId/force-gps-update"),
            headers: {"Content-Type": "application/json"},
          );
        } catch (e) {
          debugPrint('⚠️ Force GPS update request failed: $e');
        }

        // ✅ RETRY LOGIC: Check status multiple times
        debugPrint('⏳ Waiting for device to process command and update status...');

        bool statusUpdated = false;
        int maxRetries = 4; // Try 4 times
        int retryDelay = 3; // 3 seconds between retries

        for (int attempt = 1; attempt <= maxRetries; attempt++) {
          debugPrint('🔄 Attempt $attempt/$maxRetries: Checking engine status...');

          await Future.delayed(Duration(seconds: retryDelay));

          // Fetch status from database
          final response = await http.get(
            Uri.parse('${EnvConfig.baseUrl}/vehicle/$_selectedVehicleId/engine-status'),
          );

          if (response.statusCode == 200) {
            final statusData = jsonDecode(response.body);

            if (statusData['success'] == true) {
              final bool currentState = statusData['engineOn'] ?? false;
              final int dataAge = statusData['dataAgeSeconds'] ?? 0;

              debugPrint('   📊 Current state: ${currentState ? "ON" : "OFF"} (Age: $dataAge sec)');

              // Check if status matches expected state AND data is fresh (< 60 seconds)
              if (currentState == expectedNewState && dataAge < 60) {
                debugPrint('✅ Status verified! Engine is now ${currentState ? "ON" : "OFF"}');
                _engineOn = currentState;
                statusUpdated = true;
                break;
              } else if (dataAge >= 60) {
                debugPrint('⚠️ Data too old ($dataAge sec), retrying...');
              } else {
                debugPrint('⚠️ State mismatch (expected: $expectedNewState, got: $currentState), retrying...');
              }
            }
          }

          // If not last attempt, trigger another GPS fetch
          if (attempt < maxRetries) {
            debugPrint('🔄 Triggering another GPS fetch...');
            try {
              await http.post(
                Uri.parse("${EnvConfig.baseUrl}/vehicle/$_selectedVehicleId/force-gps-update"),
                headers: {"Content-Type": "application/json"},
              );
            } catch (e) {
              debugPrint('⚠️ Force GPS update failed: $e');
            }
          }
        }

        if (!statusUpdated) {
          debugPrint('⚠️ Could not verify status change after $maxRetries attempts');
          debugPrint('   Device may need more time or may be offline');
          // Still update UI optimistically
          _engineOn = expectedNewState;
        }

        _isTogglingEngine = false;
        notifyListeners();
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


  Future<bool> reportStolen() async {
    _isReportingStolen = true;
    notifyListeners();

    try {
      debugPrint("🚨 Reporting vehicle as stolen");

      // Step 1: Get current user ID
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

      // Step 2: Create stolen alert in database
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

      // Step 3: Send CLOSERELAY command to disable engine
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
          (commandData['response'] is Map && commandData['response']['success'] == 'true');

      if (commandResponse.statusCode == 200 && commandOk) {
        debugPrint('✅ Engine disabled successfully');

        // Update engine state
        _engineOn = false;

        // Wait and verify
        await Future.delayed(Duration(seconds: 2));
        await fetchEngineStatusFromDatabase();
      } else {
        debugPrint('⚠️ Engine disable command may have failed, but alert was created');
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
      fetchEngineStatusFromDatabase();
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
    _alertSubscription?.cancel();
    _locationSubscription?.cancel();
    _socketService.leaveVehicleTracking(_selectedVehicleId);
    super.dispose();
  }
}