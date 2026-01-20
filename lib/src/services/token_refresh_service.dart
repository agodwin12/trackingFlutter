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
  List<Function> _pendingRequests = [];

  /// ✅ Automatically refresh token when it expires
  Future<String?> refreshAccessToken() async {
    if (_isRefreshing) {
      // Wait for ongoing refresh to complete
      debugPrint('⏳ Token refresh already in progress, waiting...');
      return await _waitForRefresh();
    }

    _isRefreshing = true;
    debugPrint('🔄 Starting token refresh...');

    try {
      // ✅ Get stored refresh token
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refreshToken');

      if (refreshToken == null) {
        debugPrint('❌ No refresh token found - user needs to login');
        _isRefreshing = false;
        await _handleLogout();
        return null;
      }

      debugPrint('✅ Found refresh token, sending to server...');

      // ✅ Send refresh token in request body
      final response = await http.post(
        Uri.parse('${EnvConfig.baseUrl}/auth/refresh-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'refreshToken': refreshToken,  // ✅ ADDED: Send refresh token
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Token refresh timeout');
        },
      );

      debugPrint('📡 Refresh token response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccessToken = data['accessToken'];

        if (newAccessToken != null) {
          // ✅ Save new access token
          await prefs.setString('accessToken', newAccessToken);

          debugPrint('✅ Token refreshed successfully!');

          _isRefreshing = false;
          _resolvePendingRequests();

          return newAccessToken;
        }
      } else if (response.statusCode == 401) {
        debugPrint('❌ Refresh token expired - user needs to login again');
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

  /// ✅ Wait for ongoing token refresh to complete
  Future<String?> _waitForRefresh() async {
    final completer = Completer<String?>();
    _pendingRequests.add(() async {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('accessToken');
      completer.complete(token);
    });
    return completer.future;
  }

  /// ✅ Resolve all pending requests after refresh
  void _resolvePendingRequests() {
    for (var request in _pendingRequests) {
      request();
    }
    _pendingRequests.clear();
  }

  /// ✅ Handle logout when refresh token expires
  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('accessToken');
    await prefs.remove('refreshToken');  // ✅ ADDED: Also remove refresh token
    await prefs.remove('user');
    debugPrint('🚪 User logged out - tokens cleared');
    // Navigate to login will be handled by the calling code
  }

  /// ✅ Make an authenticated HTTP request with auto token refresh
  Future<http.Response> makeAuthenticatedRequest({
    required Future<http.Response> Function(String token) request,
    int retryCount = 0,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('accessToken');

      if (token == null) {
        debugPrint('❌ No access token available');
        throw Exception('No access token available');
      }

      // Make the request
      final response = await request(token);

      // ✅ If 401, refresh token and retry
      if (response.statusCode == 401 && retryCount < 1) {
        debugPrint('🔄 401 detected, attempting token refresh...');

        final newToken = await refreshAccessToken();

        if (newToken != null) {
          debugPrint('✅ Retrying request with new token...');
          // Retry the request with new token
          return await makeAuthenticatedRequest(
            request: request,
            retryCount: retryCount + 1,
          );
        } else {
          debugPrint('❌ Token refresh failed, user needs to login');
          throw Exception('Authentication failed');
        }
      }

      return response;

    } catch (error) {
      debugPrint('🔥 Request error: $error');
      rethrow;
    }
  }

  /// ✅ Get current access token (refreshes if needed)
  Future<String?> getValidAccessToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('accessToken');

      if (token == null) {
        debugPrint('❌ No access token found');
        return null;
      }

      // Try to decode and check expiration
      try {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payload = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))
          );

          final exp = payload['exp'];
          if (exp != null) {
            final expiryDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
            final now = DateTime.now();

            // ✅ If token expires in less than 5 minutes, refresh it
            if (expiryDate.difference(now).inMinutes < 5) {
              debugPrint('⏰ Token expires soon, refreshing...');
              final newToken = await refreshAccessToken();
              return newToken ?? token;
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

  /// ✅ Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final token = await getValidAccessToken();
    return token != null;
  }
}