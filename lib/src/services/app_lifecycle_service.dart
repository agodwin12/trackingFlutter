import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/pin_service.dart';

class AppLifecycleService with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> navigatorKey;
  final PinService _pinService = PinService();
  bool _isAppInBackground = false;
  int? _currentVehicleId;

  AppLifecycleService(this.navigatorKey);

  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    debugPrint('✅ App lifecycle observer registered');
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    debugPrint('🗑️ App lifecycle observer removed');
  }

  void setCurrentVehicleId(int vehicleId) {
    _currentVehicleId = vehicleId;
    debugPrint('🚗 Current vehicle ID set: $vehicleId');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    debugPrint('📱 App lifecycle state changed: $state');

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      // App is going to background
        _isAppInBackground = true;
        debugPrint('🔒 App moved to background');
        break;

      case AppLifecycleState.resumed:
      // App is coming back to foreground
        if (_isAppInBackground) {
          debugPrint('✅ App resumed from background');
          _isAppInBackground = false;

          // Check if PIN is required
          final hasPinSet = await _pinService.hasPinSet();
          if (hasPinSet && _currentVehicleId != null) {
            debugPrint('🔐 PIN required - navigating to PIN entry screen');

            // Navigate to PIN entry screen
            navigatorKey.currentState?.pushNamedAndRemoveUntil(
              '/pin-entry',
                  (route) => false,
              arguments: _currentVehicleId,
            );
          }
        }
        break;

      case AppLifecycleState.detached:
        debugPrint('❌ App is being terminated');
        break;

      case AppLifecycleState.hidden:
        debugPrint('👁️ App is hidden');
        break;
    }
  }
}