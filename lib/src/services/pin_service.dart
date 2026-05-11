// lib/services/pin_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'env_config.dart';

class PinService {
  static const String _failedAttemptsKey = 'failed_pin_attempts';
  static const int    _maxFailedAttempts = 5;

  // ── helpers ───────────────────────────────────────────────────────────────
  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  Future<String?> _getToken() async {
    final prefs = await _prefs;
    return prefs.getString('accessToken') ?? prefs.getString('auth_token');
  }

  Map<String, String> _headers({String? token}) => {
    'Content-Type': 'application/json',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  // ── PIN existence ─────────────────────────────────────────────────────────
  /// Checks whether the currently logged-in user has a PIN set.
  /// userId is resolved from the JWT on the backend — not sent in the URL.
  Future<bool> hasPinSet() async {
    try {
      final token = await _getToken();
      final url   = Uri.parse('${EnvConfig.baseUrl}/pin/exists');
      print('🔍 Checking PIN existence at: $url');

      final res = await http.get(url, headers: _headers(token: token));
      print('📥 PIN exists ${res.statusCode}: ${res.body}');

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data['hasPinSet'] == true;
      }
      // Server error — don't block onboarding, let user create PIN
      return false;
    } catch (e) {
      print('❌ hasPinSet error: $e');
      return false;
    }
  }

  /// Backward-compatible alias — kept so existing call sites don't break.
  Future<bool> hasPinSetFor(int userId) => hasPinSet();

  // ── create PIN ────────────────────────────────────────────────────────────
  Future<bool> createPin(String pin, {int? userId}) async {
    if (!_isValidPin(pin)) { print('❌ Invalid PIN format'); return false; }

    try {
      final token = await _getToken();
      final url   = Uri.parse('${EnvConfig.baseUrl}/pin/set');
      print('📤 Creating PIN at: $url');

      final res = await http.post(url,
        headers: _headers(token: token),
        body   : json.encode({'pin': pin}), // userId from JWT on backend
      );
      print('📥 Create PIN ${res.statusCode}: ${res.body}');

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['success'] == true) {
          await resetFailedAttempts();
          print('✅ PIN created');
          return true;
        }
      }
      return false;
    } catch (e) {
      print('❌ createPin error: $e');
      return false;
    }
  }

  // ── verify PIN ────────────────────────────────────────────────────────────
  Future<bool> verifyPin(String pin, {int? userId}) async {
    if (!_isValidPin(pin)) { print('❌ Invalid PIN format'); return false; }

    try {
      final token = await _getToken();
      final url   = Uri.parse('${EnvConfig.baseUrl}/pin/verify');
      print('🔐 Verifying PIN at: $url');

      final res = await http.post(url,
        headers: _headers(token: token),
        body   : json.encode({'pin': pin}), // userId from JWT on backend
      );
      print('📥 Verify PIN ${res.statusCode}: ${res.body}');

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['success'] == true) {
          await resetFailedAttempts();
          print('✅ PIN verified');
          return true;
        }
      }

      final attempts = await incrementFailedAttempts();
      print('❌ Wrong PIN — attempt $attempts/$_maxFailedAttempts');
      return false;
    } catch (e) {
      print('❌ verifyPin error: $e');
      return false;
    }
  }

  // ── change PIN ────────────────────────────────────────────────────────────
  Future<bool> changePin(String oldPin, String newPin, {int? userId}) async {
    if (!_isValidPin(oldPin) || !_isValidPin(newPin)) {
      print('❌ Invalid PIN format'); return false;
    }

    try {
      final token = await _getToken();
      final url   = Uri.parse('${EnvConfig.baseUrl}/pin/change');
      print('🔄 Changing PIN at: $url');

      final res = await http.post(url,
        headers: _headers(token: token),
        body   : json.encode({'oldPin': oldPin, 'newPin': newPin}),
      );
      print('📥 Change PIN ${res.statusCode}: ${res.body}');

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ changePin error: $e');
      return false;
    }
  }

  // ── delete PIN ────────────────────────────────────────────────────────────
  /// Deletes the PIN for the currently logged-in user.
  /// Use only for "Reset PIN" flows — not on regular logout.
  Future<bool> deletePin() async {
    try {
      final token = await _getToken();
      final url   = Uri.parse('${EnvConfig.baseUrl}/pin/delete');
      print('🗑️ Deleting PIN at: $url');

      final res = await http.delete(url, headers: _headers(token: token));
      print('📥 Delete PIN ${res.statusCode}: ${res.body}');

      if (res.statusCode == 200) {
        await resetFailedAttempts();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ deletePin error: $e');
      return false;
    }
  }

  /// Backward-compatible alias.
  Future<bool> deletePinFor(int userId) => deletePin();

  // ── failed attempts (local) ───────────────────────────────────────────────
  Future<int>  getFailedAttempts()    async =>
      ((await _prefs).getInt(_failedAttemptsKey) ?? 0);

  Future<int>  incrementFailedAttempts() async {
    final prefs    = await _prefs;
    final next     = (prefs.getInt(_failedAttemptsKey) ?? 0) + 1;
    await prefs.setInt(_failedAttemptsKey, next);
    return next;
  }

  Future<bool> isMaxAttemptsReached() async =>
      (await getFailedAttempts()) >= _maxFailedAttempts;

  Future<void> resetFailedAttempts()  async {
    await (await _prefs).setInt(_failedAttemptsKey, 0);
    print('✅ Failed attempts reset');
  }

  int get maxAttempts => _maxFailedAttempts;

  // ── validation ────────────────────────────────────────────────────────────
  bool _isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);
}