// lib/src/services/api_service.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'env_config.dart';
import 'token_refresh_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Exception thrown when the backend returns 403 FEATURE_NOT_SUBSCRIBED.
// Caught by the caller (controller or widget) to show the upgrade bottom sheet.
// ─────────────────────────────────────────────────────────────────────────────
class FeatureNotSubscribedException implements Exception {
  final String feature;
  final String message;

  const FeatureNotSubscribedException({
    required this.feature,
    this.message = 'Your current subscription does not include this feature.',
  });

  @override
  String toString() => 'FeatureNotSubscribedException($feature): $message';
}


class ApiService {
  static String get _base => EnvConfig.baseUrl;
  static final TokenRefreshService _tokenService = TokenRefreshService();

  // ─── GET ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> get(
      String path, {
        Map<String, String>? queryParams,
      }) async {
    final uri = _buildUri(path, queryParams);
    debugPrint('📡 GET $uri');

    final response = await _tokenService.makeAuthenticatedRequest(
      request: (token) async {
        return await http.get(uri, headers: _headers(token));
      },
    );

    return _handleResponse(response);
  }

  // ─── POST ─────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> post(
      String path, {
        Map<String, dynamic>? body,
      }) async {
    final uri = _buildUri(path);
    debugPrint('📡 POST $uri');

    final response = await _tokenService.makeAuthenticatedRequest(
      request: (token) async {
        return await http.post(
          uri,
          headers: _headers(token),
          body: body != null ? jsonEncode(body) : null,
        );
      },
    );

    return _handleResponse(response);
  }

  // ─── PUT ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> put(
      String path, {
        Map<String, dynamic>? body,
      }) async {
    final uri = _buildUri(path);
    debugPrint('📡 PUT $uri');

    final response = await _tokenService.makeAuthenticatedRequest(
      request: (token) async {
        return await http.put(
          uri,
          headers: _headers(token),
          body: body != null ? jsonEncode(body) : null,
        );
      },
    );

    return _handleResponse(response);
  }

  // ─── PATCH ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> patch(
      String path, {
        Map<String, dynamic>? body,
      }) async {
    final uri = _buildUri(path);
    debugPrint('📡 PATCH $uri');

    final response = await _tokenService.makeAuthenticatedRequest(
      request: (token) async {
        return await http.patch(
          uri,
          headers: _headers(token),
          body: body != null ? jsonEncode(body) : null,
        );
      },
    );

    return _handleResponse(response);
  }

  // ─── DELETE ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> delete(String path) async {
    final uri = _buildUri(path);
    debugPrint('📡 DELETE $uri');

    final response = await _tokenService.makeAuthenticatedRequest(
      request: (token) async {
        return await http.delete(uri, headers: _headers(token));
      },
    );

    return _handleResponse(response);
  }

  // ─── INTERNAL HELPERS ─────────────────────────────────────────────────────

  static Uri _buildUri(String path, [Map<String, String>? queryParams]) {
    final base = Uri.parse('$_base$path');
    if (queryParams == null || queryParams.isEmpty) return base;
    return base.replace(queryParameters: {
      ...base.queryParameters,
      ...queryParams,
    });
  }

  static Map<String, String> _headers(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  /// Parses the response and intercepts subscription errors centrally.
  ///
  /// - 403 + code == 'FEATURE_NOT_SUBSCRIBED' → throws [FeatureNotSubscribedException]
  /// - Everything else → returns the decoded body as a Map
  static Map<String, dynamic> _handleResponse(http.Response response) {
    debugPrint('📡 Response ${response.statusCode}: ${response.request?.url}');

    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // Body is not JSON — return a generic error map
      return {
        'success': false,
        'statusCode': response.statusCode,
        'message': 'Unexpected response from server',
      };
    }

    // ── Subscription gate interception ────────────────────────────────────
    if (response.statusCode == 403 &&
        data['code'] == 'FEATURE_NOT_SUBSCRIBED') {
      debugPrint('🔒 Feature blocked: ${data['feature']}');
      throw FeatureNotSubscribedException(
        feature: data['feature']?.toString() ?? 'unknown',
        message: data['message']?.toString() ??
            'Your current subscription does not include this feature.',
      );
    }

    // ── Attach raw status code so callers can inspect it if needed ────────
    return {
      ...data,
      'statusCode': response.statusCode,
    };
  }
}