import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_ios/local_auth_ios.dart';

class BiometricService {
  final LocalAuthentication _localAuth = LocalAuthentication();
  DateTime? _lastBackgroundTime;
  static const int _lockTimeoutSeconds = 10;
  bool _isSecurityAvailable = false;

  // Initialize and check if device has any security set up
  Future<void> initialize() async {
    try {
      final bool canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();

      _isSecurityAvailable = canAuthenticate;

      if (_isSecurityAvailable) {
        print('✅ Device security is available');
      } else {
        print('⚠️ No device security found - lock feature will be disabled');
      }
    } catch (e) {
      print('Error checking security availability: $e');
      _isSecurityAvailable = false;
    }
  }

  // Check if security is enabled on device
  bool get isSecurityAvailable => _isSecurityAvailable;

  // Check if device supports biometrics
  Future<bool> isBiometricAvailable() async {
    try {
      final bool canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();
      return canAuthenticate;
    } catch (e) {
      print('Error checking biometric availability: $e');
      return false;
    }
  }

  // Get list of available biometrics
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      print('Error getting available biometrics: $e');
      return [];
    }
  }

  // Authenticate user with biometrics or device PIN
  Future<bool> authenticate() async {
    if (!_isSecurityAvailable) {
      print('⚠️ No device security - skipping authentication');
      return true; // Allow access if no security is set up
    }

    try {
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access your account',
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'Biometric Authentication',
            cancelButton: 'Cancel',
            biometricHint: 'Verify identity',
          ),
          IOSAuthMessages(
            cancelButton: 'Cancel',
          ),
        ],
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allow PIN/password fallback
        ),
      );
      return didAuthenticate;
    } on PlatformException catch (e) {
      print('Error during authentication: $e');
      // If there's an error, allow access (graceful degradation)
      return true;
    }
  }

  // Call this when app goes to background
  void onAppPaused() {
    if (!_isSecurityAvailable) return; // Skip if no security

    _lastBackgroundTime = DateTime.now();
    print('App paused at: $_lastBackgroundTime');
  }

  // Call this when app comes to foreground
  // Returns true if authentication is needed
  bool shouldAuthenticate() {
    if (!_isSecurityAvailable) {
      return false; // Never authenticate if no security available
    }

    if (_lastBackgroundTime == null) {
      return false;
    }

    final now = DateTime.now();
    final difference = now.difference(_lastBackgroundTime!).inSeconds;
    print('App was in background for: $difference seconds');

    if (difference >= _lockTimeoutSeconds) {
      _lastBackgroundTime = null; // Reset
      return true;
    }

    return false;
  }

  // Reset the timer (useful after successful authentication)
  void resetTimer() {
    _lastBackgroundTime = null;
  }
}