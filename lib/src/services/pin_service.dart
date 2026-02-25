// lib/services/pin_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'env_config.dart';

class PinService {
  static const String _failedAttemptsKey = 'failed_pin_attempts';
  static const int _maxFailedAttempts = 5;

  // ---------- Helpers ----------
  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  Future<String?> _getToken() async {
    final prefs = await _prefs;
    // you save both, keep compatibility
    return prefs.getString('accessToken') ?? prefs.getString('auth_token');
  }

  Future<int?> getLoggedInUserId() async {
    final prefs = await _prefs;
    return prefs.getInt('user_id');
  }

  Map<String, String> _jsonHeaders({String? token}) => {
    'Content-Type': 'application/json',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  // ---------- PIN Existence ----------
  // ✅ IMPORTANT: Prefer checking for an explicit userId (e.g. first-login flow)
  Future<bool> hasPinSetFor(int userId) async {
    try {
      final token = await _getToken();
      final url = Uri.parse('${EnvConfig.baseUrl}/pin/exists/$userId');
      print('🔍 Checking PIN existence at: $url (userId=$userId)');

      final response = await http.get(url, headers: _jsonHeaders(token: token));
      print('📥 PIN exists status: ${response.statusCode}');
      print('📥 PIN exists body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['hasPinSet'] == true;
      }

      // If server errors, don't block onboarding — force PIN creation
      return false;
    } catch (e) {
      print('❌ Error checking PIN: $e');
      return false;
    }
  }

  // Backward-compatible method: uses prefs user_id
  Future<bool> hasPinSet() async {
    final userId = await getLoggedInUserId();
    if (userId == null) {
      print('❌ No user ID found in prefs for hasPinSet()');
      return false;
    }
    return hasPinSetFor(userId);
  }

  // ---------- Create PIN ----------
  // ✅ Prefer explicit userId if you have it; falls back to prefs user_id
  Future<bool> createPin(String pin, {int? userId}) async {
    if (!_isValidPin(pin)) {
      print('❌ Invalid PIN format');
      return false;
    }

    try {
      final uid = userId ?? await getLoggedInUserId();
      if (uid == null) {
        print('❌ No user ID found');
        return false;
      }

      final token = await _getToken();
      final url = Uri.parse('${EnvConfig.baseUrl}/pin/set');
      print('📤 Creating PIN at: $url (userId=$uid)');

      final response = await http.post(
        url,
        headers: _jsonHeaders(token: token),
        body: json.encode({'userId': uid, 'pin': pin}),
      );

      print('📥 Create PIN status: ${response.statusCode}');
      print('📥 Create PIN body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          await resetFailedAttempts();
          print('✅ PIN created successfully');
          return true;
        }
      }

      return false;
    } catch (e) {
      print('❌ Error creating PIN: $e');
      return false;
    }
  }

  // ---------- Verify PIN ----------
  Future<bool> verifyPin(String pin, {int? userId}) async {
    if (!_isValidPin(pin)) {
      print('❌ Invalid PIN format');
      return false;
    }

    try {
      final uid = userId ?? await getLoggedInUserId();
      if (uid == null) {
        print('❌ No user ID found');
        return false;
      }

      final token = await _getToken();
      final url = Uri.parse('${EnvConfig.baseUrl}/pin/verify');
      print('🔐 Verifying PIN at: $url (userId=$uid)');

      final response = await http.post(
        url,
        headers: _jsonHeaders(token: token),
        body: json.encode({'userId': uid, 'pin': pin}),
      );

      print('📥 Verify PIN status: ${response.statusCode}');
      print('📥 Verify PIN body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          await resetFailedAttempts();
          print('✅ PIN verified successfully');
          return true;
        }
      }

      final failedAttempts = await incrementFailedAttempts();
      print('❌ Wrong PIN - Attempt $failedAttempts/$_maxFailedAttempts');
      return false;
    } catch (e) {
      print('❌ Error verifying PIN: $e');
      return false;
    }
  }

  // ---------- Change PIN ----------
  Future<bool> changePin(String oldPin, String newPin, {int? userId}) async {
    if (!_isValidPin(oldPin) || !_isValidPin(newPin)) {
      print('❌ Invalid PIN format');
      return false;
    }

    try {
      final uid = userId ?? await getLoggedInUserId();
      if (uid == null) {
        print('❌ No user ID found');
        return false;
      }

      final token = await _getToken();
      final url = Uri.parse('${EnvConfig.baseUrl}/pin/change');
      print('🔄 Changing PIN at: $url (userId=$uid)');

      final response = await http.post(
        url,
        headers: _jsonHeaders(token: token),
        body: json.encode({'userId': uid, 'oldPin': oldPin, 'newPin': newPin}),
      );

      print('📥 Change PIN status: ${response.statusCode}');
      print('📥 Change PIN body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true;
      }

      return false;
    } catch (e) {
      print('❌ Error changing PIN: $e');
      return false;
    }
  }

  // ---------- Delete PIN (optional / usually NOT on logout) ----------
  // ⚠️ Security note: generally you should NOT delete PIN on logout.
  // Keep it for "Reset PIN" flows only.
  Future<bool> deletePinFor(int userId) async {
    try {
      final token = await _getToken();
      final url = Uri.parse('${EnvConfig.baseUrl}/pin/delete/$userId');
      print('🗑️ Deleting PIN at: $url (userId=$userId)');

      final response = await http.delete(url, headers: _jsonHeaders(token: token));
      print('📥 Delete PIN status: ${response.statusCode}');
      print('📥 Delete PIN body: ${response.body}');

      if (response.statusCode == 200) {
        await resetFailedAttempts();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error deleting PIN: $e');
      return false;
    }
  }

  // Backward-compatible delete using prefs user_id
  Future<bool> deletePin() async {
    final uid = await getLoggedInUserId();
    if (uid == null) return false;
    return deletePinFor(uid);
  }

  // ---------- Failed attempts (local) ----------
  Future<int> getFailedAttempts() async {
    final prefs = await _prefs;
    return prefs.getInt(_failedAttemptsKey) ?? 0;
  }

  Future<int> incrementFailedAttempts() async {
    final prefs = await _prefs;
    final currentAttempts = prefs.getInt(_failedAttemptsKey) ?? 0;
    final newAttempts = currentAttempts + 1;
    await prefs.setInt(_failedAttemptsKey, newAttempts);
    return newAttempts;
  }

  Future<bool> isMaxAttemptsReached() async {
    final attempts = await getFailedAttempts();
    return attempts >= _maxFailedAttempts;
  }

  Future<void> resetFailedAttempts() async {
    final prefs = await _prefs;
    await prefs.setInt(_failedAttemptsKey, 0);
    print('✅ Failed attempts reset');
  }

  int get maxAttempts => _maxFailedAttempts;

  // ---------- Validation ----------
  bool _isValidPin(String pin) {
    if (pin.length != 4) return false;
    return RegExp(r'^\d{4}$').hasMatch(pin);
  }
}