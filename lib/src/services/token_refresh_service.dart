// lib/src/services/token_refresh_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'env_config.dart';

class TokenRefreshService {
  static final TokenRefreshService _instance = TokenRefreshService._internal();
  factory TokenRefreshService() => _instance;
  TokenRefreshService._internal();

  bool _isRefreshing = false;
  final List<Function> _pendingRequests = [];

  // ── Refresh access token ──────────────────────────────────────────────────
  Future<String?> refreshAccessToken() async {
    if (_isRefreshing) {
      debugPrint('⏳ Token refresh already in progress, waiting...');
      return await _waitForRefresh();
    }

    _isRefreshing = true;
    debugPrint('🔄 Starting token refresh...');

    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refreshToken');

      if (refreshToken == null) {
        debugPrint('❌ No refresh token found — user needs to login');
        _isRefreshing = false;
        await _handleLogout();
        return null;
      }

      debugPrint('✅ Found refresh token, sending to server...');

      final response = await http.post(
        Uri.parse('${EnvConfig.baseUrl}/auth/refresh-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Token refresh timeout'),
      );

      debugPrint('📡 Refresh token response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccessToken  = data['accessToken']  as String?;
        final newRefreshToken = data['refreshToken'] as String?;

        if (newAccessToken != null) {
          // Save new access token under both keys (legacy code reads 'auth_token')
          await prefs.setString('accessToken', newAccessToken);
          await prefs.setString('auth_token',  newAccessToken);

          // ✅ Save the rotated refresh token — without this the next refresh
          // fails because the server invalidates the old one on every rotation.
          if (newRefreshToken != null) {
            await prefs.setString('refreshToken', newRefreshToken);
            debugPrint('✅ Rotated refresh token saved');
          }

          debugPrint('✅ Token refreshed successfully');
          _isRefreshing = false;
          _resolvePendingRequests();
          return newAccessToken;
        }
      } else if (response.statusCode == 401) {
        debugPrint('❌ Refresh token expired — user needs to login again');
        _isRefreshing = false;
        await _handleLogout();
        return null;
      }

      debugPrint('❌ Token refresh failed: ${response.statusCode}');
      debugPrint('📦 Response body: ${response.body}');
      _isRefreshing = false;
      return null;

    } catch (error) {
      debugPrint('🔥 Error refreshing token: $error');
      _isRefreshing = false;
      return null;
    }
  }

  // ── Wait for an in-progress refresh ──────────────────────────────────────
  Future<String?> _waitForRefresh() async {
    final completer = Completer<String?>();
    _pendingRequests.add(() async {
      final prefs = await SharedPreferences.getInstance();
      completer.complete(prefs.getString('accessToken'));
    });
    return completer.future;
  }

  // ── Resolve all requests that queued behind a refresh ────────────────────
  void _resolvePendingRequests() {
    for (final req in _pendingRequests) {
      req();
    }
    _pendingRequests.clear();
  }

  // ── Clear tokens and signal logout ───────────────────────────────────────
  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('accessToken');
    await prefs.remove('auth_token');
    await prefs.remove('refreshToken');
    await prefs.remove('user');
    debugPrint('🚪 Tokens cleared — redirect to login');
  }

  // ── Make an authenticated request, auto-retrying after a 401 ─────────────
  Future<http.Response> makeAuthenticatedRequest({
    required Future<http.Response> Function(String token) request,
    int retryCount = 0,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('accessToken');

      if (token == null) {
        debugPrint('❌ No access token available');
        throw Exception('No access token available');
      }

      final response = await request(token);

      // Backend auto-refreshed the token mid-request via authMiddleware.
      // Save both the new access token AND the rotated refresh token.
      final headerNewAccess  = response.headers['x-new-access-token'];
      final headerNewRefresh = response.headers['x-new-refresh-token'];

      if (headerNewAccess != null && headerNewAccess.isNotEmpty) {
        debugPrint('🔄 Backend issued new access token via header — saving');
        await prefs.setString('accessToken', headerNewAccess);
        await prefs.setString('auth_token',  headerNewAccess);
      }
      if (headerNewRefresh != null && headerNewRefresh.isNotEmpty) {
        debugPrint('🔄 Backend issued new refresh token via header — saving');
        await prefs.setString('refreshToken', headerNewRefresh);
      }

      // 401 → attempt one refresh + retry
      if (response.statusCode == 401 && retryCount < 1) {
        debugPrint('🔄 401 detected, attempting token refresh...');
        final newToken = await refreshAccessToken();

        if (newToken != null) {
          debugPrint('✅ Retrying request with refreshed token...');
          return await makeAuthenticatedRequest(
            request:    request,
            retryCount: retryCount + 1,
          );
        } else {
          debugPrint('❌ Token refresh failed — authentication required');
          throw Exception('Authentication failed');
        }
      }

      return response;

    } catch (error) {
      debugPrint('🔥 Request error: $error');
      rethrow;
    }
  }

  // ── Get a valid (non-expired) access token, refreshing proactively ────────
  Future<String?> getValidAccessToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('accessToken');

      if (token == null) {
        debugPrint('❌ No access token found');
        return null;
      }

      // Decode JWT payload and check expiry without a package
      try {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payload = jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
          ) as Map<String, dynamic>;

          final exp = payload['exp'] as int?;
          if (exp != null) {
            final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
            // Proactively refresh if less than 5 minutes remain
            if (expiry.difference(DateTime.now()).inMinutes < 5) {
              debugPrint('⏰ Token expires in < 5 min, refreshing proactively...');
              final refreshed = await refreshAccessToken();
              return refreshed ?? token;
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ Could not decode token, using as-is: $e');
      }

      return token;

    } catch (error) {
      debugPrint('🔥 Error getting valid token: $error');
      return null;
    }
  }

  // ── Quick auth check ──────────────────────────────────────────────────────
  Future<bool> isAuthenticated() async {
    final token = await getValidAccessToken();
    return token != null;
  }
}