// lib/src/services/token_refresh_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/login/login.dart';
import 'env_config.dart';
import 'socket_service.dart';

import '../../../main.dart' show navigatorKey;

class TokenRefreshService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final TokenRefreshService _instance = TokenRefreshService._internal();
  factory TokenRefreshService() => _instance;
  TokenRefreshService._internal();

  // ── State ──────────────────────────────────────────────────────────────────
  bool _isRefreshing = false;
  bool _sessionExpiredGuard = false; // prevents double-redirect

  final List<Completer<String?>> _queue = [];

  // Call this after a successful login to re-arm the guard
  void resetSessionState() {
    _sessionExpiredGuard = false;
    debugPrint('🔓 [TokenRefresh] Session guard reset — ready for new session');
  }

  Future<http.Response> makeAuthenticatedRequest({
    required Future<http.Response> Function(String token) request,
    int retryCount = 0,
  }) async {
    final token = await getValidAccessToken();

    if (token == null) {
      debugPrint('❌ [TokenRefresh] No valid token — forcing logout');
      await _handleLogout();
      throw Exception('Authentication required');
    }

    final response = await request(token);

    await _saveRotatedHeaderTokens(response);

    if (response.statusCode == 401 && retryCount < 1) {
      String? bodyCode;
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        bodyCode = body['code'] as String?;
      } catch (_) {}

      // Any 401 triggers a refresh attempt
      debugPrint('🔄 [TokenRefresh] 401 received (code: $bodyCode) — refreshing...');
      final newToken = await refreshAccessToken();
      if (newToken != null) {
        debugPrint('✅ [TokenRefresh] Retrying with new token');
        return makeAuthenticatedRequest(request: request, retryCount: 1);
      }
      // refreshAccessToken already called _handleLogout if it failed
    }

    return response;
  }

  Future<String?> getValidAccessToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('accessToken');
      if (token == null) return null;

      final exp = _decodeExp(token);
      if (exp != null) {
        final secondsLeft =
            exp - (DateTime.now().millisecondsSinceEpoch ~/ 1000);
        debugPrint('⏱ [TokenRefresh] Token expires in ${secondsLeft}s');

        if (secondsLeft <= 60) {
          debugPrint('⚡ [TokenRefresh] Proactive refresh (≤60s left)');
          final refreshed = await refreshAccessToken();
          // If refresh failed, refreshAccessToken handled logout already.
          // Return null so the caller knows no token is available.
          return refreshed;
        }
      }

      return token;
    } catch (e) {
      debugPrint('⚠️ [TokenRefresh] getValidAccessToken error: $e');
      return null;
    }
  }

  Future<String?> refreshAccessToken() async {
    if (_isRefreshing) {
      debugPrint('⏳ [TokenRefresh] Queued — refresh already in progress');
      final completer = Completer<String?>();
      _queue.add(completer);
      return completer.future;
    }

    _isRefreshing = true;
    String? newToken;

    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refreshToken');
      final clientId = prefs.getString('client_id');

      if (refreshToken == null) {
        debugPrint('❌ [TokenRefresh] No refresh token — forcing logout');
        await _handleLogout();
        return null;
      }

      if (clientId == null) {
        debugPrint('❌ [TokenRefresh] No client_id — forcing logout');
        await _handleLogout();
        return null;
      }

      debugPrint(
          '🔄 [TokenRefresh] Calling /auth/refresh-token client=$clientId');

      final response = await http
          .post(
        Uri.parse('${EnvConfig.baseUrl}/auth/refresh-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'refreshToken': refreshToken,
          'client_id': clientId,
        }),
      )
          .timeout(const Duration(seconds: 15));

      debugPrint('📡 [TokenRefresh] Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final String? newAccess = data['accessToken'] as String?;
        final String? newRefresh = data['refreshToken'] as String?;

        if (newAccess == null) {
          debugPrint('❌ [TokenRefresh] Response missing accessToken — logout');
          await _handleLogout();
          return null;
        }

        await prefs.setString('accessToken', newAccess);
        await prefs.setString('auth_token', newAccess);
        if (newRefresh != null) {
          await prefs.setString('refreshToken', newRefresh);
          debugPrint('✅ [TokenRefresh] Refresh token rotated and saved');
        }

        newToken = newAccess;
        debugPrint('✅ [TokenRefresh] Tokens refreshed successfully');
      } else if (response.statusCode == 401) {
        debugPrint(
            '❌ [TokenRefresh] Refresh token expired (401) — forcing logout');
        await _handleLogout();
      } else {
        // 5xx or unexpected — treat as expired to be safe
        debugPrint(
            '⚠️ [TokenRefresh] Unexpected ${response.statusCode} — forcing logout');
        await _handleLogout();
      }
    } on TimeoutException {
      debugPrint('⏰ [TokenRefresh] Refresh timed out — forcing logout');
      await _handleLogout();
    } catch (e) {
      debugPrint('🔥 [TokenRefresh] Network error: $e — forcing logout');
      await _handleLogout();
    } finally {
      _isRefreshing = false;
      for (final completer in _queue) {
        completer.complete(newToken);
      }
      _queue.clear();
    }

    return newToken;
  }

  Future<bool> isAuthenticated() async {
    final token = await getValidAccessToken();
    return token != null;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  int? _decodeExp(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      return payload['exp'] as int?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveRotatedHeaderTokens(http.Response response) async {
    final newAccess = response.headers['x-new-access-token'];
    final newRefresh = response.headers['x-new-refresh-token'];
    if (newAccess == null && newRefresh == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (newAccess != null && newAccess.isNotEmpty) {
      await prefs.setString('accessToken', newAccess);
      await prefs.setString('auth_token', newAccess);
      debugPrint('🔄 [TokenRefresh] Header rotation — new access token saved');
    }
    if (newRefresh != null && newRefresh.isNotEmpty) {
      await prefs.setString('refreshToken', newRefresh);
      debugPrint('🔄 [TokenRefresh] Header rotation — new refresh token saved');
    }
  }

  Future<void> _handleLogout() async {
    // Guard: only execute once per session — prevents race conditions where
    // multiple in-flight requests all fail and each tries to redirect.
    if (_sessionExpiredGuard) {
      debugPrint('🔒 [TokenRefresh] Logout already in progress — skipping');
      return;
    }
    _sessionExpiredGuard = true;

    debugPrint('🚪 [TokenRefresh] Session expired — clearing credentials');

    // Disconnect socket immediately so it stops streaming stale data
    try {
      SocketService().disconnect();
      debugPrint('🔌 [TokenRefresh] Socket disconnected');
    } catch (e) {
      debugPrint('⚠️ [TokenRefresh] Socket disconnect error: $e');
    }

    // Clear all auth and session data
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('accessToken');
      await prefs.remove('auth_token');
      await prefs.remove('refreshToken');
      await prefs.remove('client_id');
      await prefs.remove('user');
      await prefs.remove('vehicles_list');
      await prefs.remove('current_vehicle_id');
      await prefs.remove('current_vehicle_name');
      await prefs.remove('user_id');
      await prefs.remove('user_phone');
      await prefs.remove('app_type');
      await prefs.remove('roles');
    } catch (e) {
      debugPrint('⚠️ [TokenRefresh] Error clearing prefs: $e');
    }

    debugPrint('🚪 [TokenRefresh] Navigating to login screen');
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ModernLoginScreen()),
          (_) => false,
    );
  }
}