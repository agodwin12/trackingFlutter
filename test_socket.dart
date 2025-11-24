// test_socket.dart
import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() {
  print('🧪 Testing Socket.IO connection...');

  final socket = IO.io('http://10.0.2.2:5000',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build()
  );

  socket.onConnect((_) {
    print('✅ CONNECTED!');
    socket.emit('joinVehicleTracking', 12);
  });

  socket.onConnectError((error) {
    print('❌ Error: $error');
  });

  socket.on('gpsUpdate', (data) {
    print('📡 GPS UPDATE: $data');
  });

  socket.connect();
  print('🔌 Attempting connection...');
}