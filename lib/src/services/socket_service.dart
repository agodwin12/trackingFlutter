// services/socket_service.dart
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  // Singleton pattern
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  int? _pendingVehicleId; // Store vehicle ID to join after connection
  int? _currentVehicleId; // Track currently joined vehicle
  int? _currentUserId;    // Track currently joined user room

  // Stream controllers for real-time updates
  final _gpsUpdateController            = StreamController<Map<String, dynamic>>.broadcast();
  final _dashboardUpdateController      = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionStatusController     = StreamController<bool>.broadcast();
  final _safeZoneAlertController        = StreamController<Map<String, dynamic>>.broadcast();
  final _locationUpdateController       = StreamController<Map<String, dynamic>>.broadcast();
  // ── Payment updates — pushed by backend after webhook confirms ───────────
  final _paymentUpdateController        = StreamController<Map<String, dynamic>>.broadcast();

  // Public streams
  Stream<Map<String, dynamic>> get gpsUpdateStream       => _gpsUpdateController.stream;
  Stream<Map<String, dynamic>> get dashboardUpdateStream => _dashboardUpdateController.stream;
  Stream<bool>                 get connectionStatusStream => _connectionStatusController.stream;
  Stream<Map<String, dynamic>> get safeZoneAlertStream   => _safeZoneAlertController.stream;
  Stream<Map<String, dynamic>> get locationUpdateStream  => _locationUpdateController.stream;
  Stream<Map<String, dynamic>> get paymentUpdateStream   => _paymentUpdateController.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// Connect to Socket.IO server.
  /// Pass [userId] so the service joins the user room immediately on connect.
  void connect(String serverUrl, {int? userId}) {
    if (_socket != null && _socket!.connected) {
      print('⚠️ Socket already connected');
      // Still join user room if not yet joined (e.g. userId was not known at
      // the time of the original connect call).
      if (userId != null && _currentUserId != userId) {
        joinUserRoom(userId);
      }
      return;
    }

    if (userId != null) _currentUserId = userId;

    print('\n🔌 ========== CONNECTING TO SOCKET.IO ==========');
    print('🔌 Server URL: $serverUrl');

    try {
      _socket = IO.io(serverUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
        'reconnection': true,
        'reconnectionDelay': 1000,
        'reconnectionDelayMax': 5000,
        'reconnectionAttempts': 10,
        'timeout': 20000,
      });

      // ── Connection established ────────────────────────────────────────────
      _socket!.onConnect((_) {
        print('✅ Socket.IO connected!');
        print('🔌 Socket ID: ${_socket!.id}');
        _connectionStatusController.add(true);

        // Rejoin vehicle room if there was a pending one
        if (_pendingVehicleId != null) {
          print('📡 Auto-joining pending vehicle room: $_pendingVehicleId');
          joinVehicleTracking(_pendingVehicleId!);
          _pendingVehicleId = null;
        }

        // Always (re)join the user room so payment_update events reach us
        if (_currentUserId != null) {
          print('👤 Auto-joining user room: $_currentUserId');
          joinUserRoom(_currentUserId!);
        }
      });

      // ── Connection error ──────────────────────────────────────────────────
      _socket!.onConnectError((error) {
        print('❌ Connection error: $error');
        _connectionStatusController.add(false);
      });

      // ── Disconnection ─────────────────────────────────────────────────────
      _socket!.onDisconnect((_) {
        print('❌ Socket.IO disconnected');
        _connectionStatusController.add(false);

        // Store current vehicle ID to rejoin on reconnect
        if (_currentVehicleId != null) {
          print('💾 Storing vehicle ID $_currentVehicleId for reconnection');
          _pendingVehicleId = _currentVehicleId;
        }
      });

      // ── Reconnection events ───────────────────────────────────────────────
      _socket!.on('reconnect_attempt', (data) {
        print('🔄 Attempting to reconnect... (attempt $data)');
      });

      _socket!.on('reconnect', (data) {
        print('✅ Reconnected successfully!');
        _connectionStatusController.add(true);
      });

      _socket!.on('reconnect_failed', (data) {
        print('❌ Reconnection failed after all attempts');
        _connectionStatusController.add(false);
      });

      // ── GPS update ────────────────────────────────────────────────────────
      _socket!.on('gpsUpdate', (data) {
        print('📡 Received GPS update: $data');
        try {
          _gpsUpdateController.add(Map<String, dynamic>.from(data));
        } catch (e) {
          print('⚠️ Error processing GPS update: $e');
        }
      });

      // ── Dashboard update ──────────────────────────────────────────────────
      _socket!.on('dashboardUpdate', (data) {
        print('📊 Received dashboard update: $data');
        try {
          _dashboardUpdateController.add(Map<String, dynamic>.from(data));
        } catch (e) {
          print('⚠️ Error processing dashboard update: $e');
        }
      });

      // ── Location update (real-time car movement) ──────────────────────────
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

      // ── Safe zone alert ───────────────────────────────────────────────────
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

      // ── Payment update — fired by backend after webhook confirms ──────────
      // Payload: { status: 'SUCCESS'|'FAILED', payment_id, vehicle_id, timestamp }
      // PaymentPendingScreen listens to paymentUpdateStream and navigates
      // to success or failed screen when this arrives.
      _socket!.on('payment_update', (data) {
        print('💳 ========== PAYMENT UPDATE RECEIVED ==========');
        print('📦 Status: ${data['status']}');
        print('📦 Payment ID: ${data['payment_id']}');
        print('📦 Vehicle ID: ${data['vehicle_id']}');
        print('===============================================');

        try {
          _paymentUpdateController.add(Map<String, dynamic>.from(data));
        } catch (e) {
          print('⚠️ Error processing payment update: $e');
        }
      });

      // ── Room confirmations ────────────────────────────────────────────────
      _socket!.on('joinedRoom', (data) {
        print('✅ Joined vehicle room: ${data['room']}');
      });

      _socket!.on('joinedUserRoom', (data) {
        print('✅ Joined user room: ${data['room']}');
      });

      _socket!.on('leftRoom', (data) {
        print('👋 Left room: ${data['room']}');
      });

      // ── Generic error handler ─────────────────────────────────────────────
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
    _pendingVehicleId = null;
  }

  /// Leave vehicle tracking room
  void leaveVehicleTracking(int vehicleId) {
    if (_socket == null || !_socket!.connected) {
      print('⚠️ Cannot leave room: Socket not connected');
      return;
    }

    print('👋 Leaving vehicle tracking room: vehicle_$vehicleId');
    _socket!.emit('leaveVehicleTracking', vehicleId);

    if (_currentVehicleId == vehicleId) {
      _currentVehicleId = null;
    }
  }

  /// Join the user room for payment updates and user-level notifications.
  /// Called automatically on connect/reconnect if userId is known.
  void joinUserRoom(int userId) {
    if (_socket == null || !_socket!.connected) {
      print('⚠️ Cannot join user room: Socket not connected');
      _currentUserId = userId; // Store so onConnect can retry
      return;
    }

    print('👤 Joining user room: user_$userId');
    _socket!.emit('joinUserRoom', userId);
    _currentUserId = userId;
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
  int? getCurrentVehicleId() => _currentVehicleId;

  /// Get current user ID
  int? getCurrentUserId() => _currentUserId;

  /// Disconnect from Socket.IO
  void disconnect() {
    if (_socket != null) {
      print('🔌 Disconnecting Socket.IO...');

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

    _gpsUpdateController.close();
    _dashboardUpdateController.close();
    _connectionStatusController.close();
    _safeZoneAlertController.close();
    _locationUpdateController.close();
    _paymentUpdateController.close();

    print('✅ SocketService disposed');
  }

  /// Reset connection (useful for debugging)
  void reset() {
    print('🔄 Resetting SocketService...');
    disconnect();
    _currentVehicleId = null;
    _pendingVehicleId = null;
    _currentUserId    = null;
  }
}