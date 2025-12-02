import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'env_config.dart';

class PinService {
  static const String _failedAttemptsKey = 'failed_pin_attempts';
  static const int _maxFailedAttempts = 5;

  // Get user ID from shared preferences
  Future<int?> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }

  // Check if user has created a PIN (from backend)
  Future<bool> hasPinSet() async {
    try {
      final userId = await _getUserId();
      if (userId == null) {
        print('❌ No user ID found');
        return false;
      }

      final url = Uri.parse('${EnvConfig.baseUrl}/pin/exists/$userId');
      print('🔍 Checking PIN existence at: $url');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final hasPinSet = data['hasPinSet'] ?? false;
        print('✅ PIN check result: $hasPinSet');
        return hasPinSet;
      } else {
        print('❌ Error checking PIN: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Error checking PIN: $e');
      return false;
    }
  }

  // Create and save a new PIN (to backend)
  Future<bool> createPin(String pin) async {
    if (!_isValidPin(pin)) {
      print('❌ Invalid PIN format');
      return false;
    }

    try {
      final userId = await _getUserId();
      if (userId == null) {
        print('❌ No user ID found');
        return false;
      }

      final url = Uri.parse('${EnvConfig.baseUrl}/pin/set');
      print('📤 Creating PIN at: $url');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': userId,
          'pin': pin,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          await resetFailedAttempts(); // Reset attempts on successful creation
          print('✅ PIN created successfully');
          return true;
        }
      }

      print('❌ Failed to create PIN: ${response.body}');
      return false;
    } catch (e) {
      print('❌ Error creating PIN: $e');
      return false;
    }
  }

  // Verify PIN (with backend)
  Future<bool> verifyPin(String pin) async {
    try {
      final userId = await _getUserId();
      if (userId == null) {
        print('❌ No user ID found');
        return false;
      }

      final url = Uri.parse('${EnvConfig.baseUrl}/pin/verify');
      print('🔐 Verifying PIN at: $url');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': userId,
          'pin': pin,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          // Reset failed attempts on successful verification
          await resetFailedAttempts();
          print('✅ PIN verified successfully');
          return true;
        }
      }

      // Wrong PIN - increment failed attempts
      final failedAttempts = await incrementFailedAttempts();
      print('❌ Wrong PIN - Attempt $failedAttempts/$_maxFailedAttempts');
      return false;

    } catch (e) {
      print('❌ Error verifying PIN: $e');
      return false;
    }
  }

  // Change existing PIN (requires old PIN for verification)
  Future<bool> changePin(String oldPin, String newPin) async {
    if (!_isValidPin(oldPin) || !_isValidPin(newPin)) {
      print('❌ Invalid PIN format');
      return false;
    }

    try {
      final userId = await _getUserId();
      if (userId == null) {
        print('❌ No user ID found');
        return false;
      }

      final url = Uri.parse('${EnvConfig.baseUrl}/pin/change');
      print('🔄 Changing PIN at: $url');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': userId,
          'oldPin': oldPin,
          'newPin': newPin,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('✅ PIN changed successfully');
          return true;
        }
      }

      print('❌ Failed to change PIN: ${response.body}');
      return false;
    } catch (e) {
      print('❌ Error changing PIN: $e');
      return false;
    }
  }

  // Get number of failed attempts (stored locally)
  Future<int> getFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_failedAttemptsKey) ?? 0;
  }

  // Increment failed attempts and return new count
  Future<int> incrementFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    final currentAttempts = prefs.getInt(_failedAttemptsKey) ?? 0;
    final newAttempts = currentAttempts + 1;
    await prefs.setInt(_failedAttemptsKey, newAttempts);
    return newAttempts;
  }

  // Check if max attempts reached
  Future<bool> isMaxAttemptsReached() async {
    final attempts = await getFailedAttempts();
    return attempts >= _maxFailedAttempts;
  }

  // Reset failed attempts (call this after successful login or PIN reset)
  Future<void> resetFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_failedAttemptsKey, 0);
    print('✅ Failed attempts reset');
  }

  // Delete PIN from backend (call this on logout)
  Future<void> deletePin() async {
    try {
      final userId = await _getUserId();
      if (userId == null) {
        print('❌ No user ID found');
        return;
      }

      final url = Uri.parse('${EnvConfig.baseUrl}/pin/delete/$userId');
      print('🗑️ Deleting PIN at: $url');

      final response = await http.delete(url);

      if (response.statusCode == 200) {
        await resetFailedAttempts();
        print('✅ PIN deleted successfully');
      } else {
        print('❌ Failed to delete PIN: ${response.body}');
      }
    } catch (e) {
      print('❌ Error deleting PIN: $e');
    }
  }

  // Validate PIN format (must be exactly 4 digits)
  bool _isValidPin(String pin) {
    if (pin.length != 4) return false;
    return RegExp(r'^\d{4}$').hasMatch(pin);
  }

  // Get max allowed attempts
  int get maxAttempts => _maxFailedAttempts;
}