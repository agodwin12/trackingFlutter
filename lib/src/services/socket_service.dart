// services/socket_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  // Singleton pattern
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  int? _pendingVehicleId; // ✅ Store vehicle ID to join after connection
  int? _currentVehicleId; // ✅ Track currently joined vehicle

  // Stream controllers for real-time updates
  final _gpsUpdateController = StreamController<Map<String, dynamic>>.broadcast();
  final _dashboardUpdateController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _safeZoneAlertController = StreamController<Map<String, dynamic>>.broadcast();
  final _locationUpdateController = StreamController<Map<String, dynamic>>.broadcast();

  // Public streams
  Stream<Map<String, dynamic>> get gpsUpdateStream => _gpsUpdateController.stream;
  Stream<Map<String, dynamic>> get dashboardUpdateStream => _dashboardUpdateController.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  Stream<Map<String, dynamic>> get safeZoneAlertStream => _safeZoneAlertController.stream;
  Stream<Map<String, dynamic>> get locationUpdateStream => _locationUpdateController.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// Connect to Socket.IO server
  void connect(String serverUrl) {
    if (_socket != null && _socket!.connected) {
      print('⚠️ Socket already connected');
      return;
    }

    print('\n🔌 ========== CONNECTING TO SOCKET.IO ==========');
    print('🔌 Server URL: $serverUrl');

    try {
      _socket = IO.io(serverUrl, <String, dynamic>{
        'transports': ['websocket'], // Force WebSocket (important!)
        'autoConnect': true,
        'reconnection': true,
        'reconnectionDelay': 1000,
        'reconnectionDelayMax': 5000,
        'reconnectionAttempts': 10,
        'timeout': 20000,
      });

      // ✅ Connection established
      _socket!.onConnect((_) {
        print('✅ Socket.IO connected!');
        print('🔌 Socket ID: ${_socket!.id}');
        _connectionStatusController.add(true);

        // ✅ Auto-rejoin vehicle room if there was a pending one
        if (_pendingVehicleId != null) {
          print('📡 Auto-joining pending vehicle room: $_pendingVehicleId');
          joinVehicleTracking(_pendingVehicleId!);
          _pendingVehicleId = null;
        }
      });

      // ✅ Connection error
      _socket!.onConnectError((error) {
        print('❌ Connection error: $error');
        _connectionStatusController.add(false);
      });

      // ✅ Disconnection
      _socket!.onDisconnect((_) {
        print('❌ Socket.IO disconnected');
        _connectionStatusController.add(false);

        // ✅ Store current vehicle ID to rejoin on reconnect
        if (_currentVehicleId != null) {
          print('💾 Storing vehicle ID $_currentVehicleId for reconnection');
          _pendingVehicleId = _currentVehicleId;
        }
      });

      // ✅ Reconnection attempt
      _socket!.on('reconnect_attempt', (data) {
        print('🔄 Attempting to reconnect... (attempt $data)');
      });

      // ✅ Reconnection success
      _socket!.on('reconnect', (data) {
        print('✅ Reconnected successfully!');
        _connectionStatusController.add(true);
      });

      // ✅ Reconnection failed
      _socket!.on('reconnect_failed', (data) {
        print('❌ Reconnection failed after all attempts');
        _connectionStatusController.add(false);
      });

      // ✅ Listen for GPS updates
      _socket!.on('gpsUpdate', (data) {
        print('📡 Received GPS update: $data');
        try {
          _gpsUpdateController.add(Map<String, dynamic>.from(data));
        } catch (e) {
          print('⚠️ Error processing GPS update: $e');
        }
      });

      // ✅ Listen for dashboard updates
      _socket!.on('dashboardUpdate', (data) {
        print('📊 Received dashboard update: $data');
        try {
          _dashboardUpdateController.add(Map<String, dynamic>.from(data));
        } catch (e) {
          print('⚠️ Error processing dashboard update: $e');
        }
      });

      // ✅ Listen for location updates (real-time car movement)
      _socket!.on('location_update', (data) {
        print('📍 ========== LOCATION UPDATE RECEIVED ==========');
        print('📦 Vehicle ID: ${data['vehicleId']}');
        print('📦 Latitude: ${data['latitude']}');
        print('📦 Longitude: ${data['longitude']}');
        print('📦 Speed: ${data['speed']}');
        print('📦 Engine: ${data['engine_status']}');
        print('===============================================');

        try {
          _locationUpdateController.add(Map<String, dynamic>.from(data));
        } catch (e) {
          print('⚠️ Error processing location update: $e');
        }
      });

      // ✅ Listen for safe zone alerts
      _socket!.on('safe_zone_alert', (data) {
        print('🚨 ========== SAFE ZONE ALERT RECEIVED ==========');
        print('📦 Raw data: $data');
        print('📦 Data type: ${data.runtimeType}');
        print('===============================================');

        try {
          _safeZoneAlertController.add(Map<String, dynamic>.from(data));
        } catch (e) {
          print('⚠️ Error processing safe zone alert: $e');
        }
      });

      // ✅ Listen for room joined confirmation
      _socket!.on('joinedRoom', (data) {
        print('✅ Joined room: ${data['room']}');
      });

      // ✅ Listen for room left confirmation
      _socket!.on('leftRoom', (data) {
        print('👋 Left room: ${data['room']}');
      });

      // ✅ Generic error handler
      _socket!.on('error', (error) {
        print('❌ Socket error: $error');
      });

      print('========================================\n');
    } catch (e) {
      print('🔥 Error creating socket: $e');
      _connectionStatusController.add(false);
    }
  }

  /// Join vehicle tracking room
  void joinVehicleTracking(int vehicleId) {
    if (_socket == null) {
      print('⚠️ Cannot join room: Socket is null');
      _pendingVehicleId = vehicleId;
      return;
    }

    if (!_socket!.connected) {
      print('⚠️ Cannot join room: Socket not connected. Will retry when connected...');
      _pendingVehicleId = vehicleId;
      return;
    }

    print('📡 Joining vehicle tracking room: vehicle_$vehicleId');
    _socket!.emit('joinVehicleTracking', vehicleId);
    _currentVehicleId = vehicleId;
    _pendingVehicleId = null; // Clear pending since we successfully joined
  }

  /// Leave vehicle tracking room
  void leaveVehicleTracking(int vehicleId) {
    if (_socket == null || !_socket!.connected) {
      print('⚠️ Cannot leave room: Socket not connected');
      return;
    }

    print('👋 Leaving vehicle tracking room: vehicle_$vehicleId');
    _socket!.emit('leaveVehicleTracking', vehicleId);

    // Clear current vehicle if it matches
    if (_currentVehicleId == vehicleId) {
      _currentVehicleId = null;
    }
  }

  /// Manually trigger reconnection
  void reconnect() {
    if (_socket != null) {
      print('🔄 Manually triggering reconnection...');
      _socket!.connect();
    } else {
      print('⚠️ Cannot reconnect: Socket is null');
    }
  }

  /// Check connection status
  bool isSocketConnected() {
    return _socket != null && _socket!.connected;
  }

  /// Get current vehicle ID
  int? getCurrentVehicleId() {
    return _currentVehicleId;
  }

  /// Disconnect from Socket.IO
  void disconnect() {
    if (_socket != null) {
      print('🔌 Disconnecting Socket.IO...');

      // Leave current room before disconnecting
      if (_currentVehicleId != null) {
        leaveVehicleTracking(_currentVehicleId!);
      }

      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _currentVehicleId = null;
      _pendingVehicleId = null;
      _connectionStatusController.add(false);

      print('✅ Socket disconnected and disposed');
    }
  }

  /// Dispose all resources
  void dispose() {
    print('🧹 Disposing SocketService...');

    disconnect();

    // Close all stream controllers
    _gpsUpdateController.close();
    _dashboardUpdateController.close();
    _connectionStatusController.close();
    _safeZoneAlertController.close();
    _locationUpdateController.close();

    print('✅ SocketService disposed');
  }

  /// Reset connection (useful for debugging)
  void reset() {
    print('🔄 Resetting SocketService...');
    disconnect();
    _currentVehicleId = null;
    _pendingVehicleId = null;
  }
}