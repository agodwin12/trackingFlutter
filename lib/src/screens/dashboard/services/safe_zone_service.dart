// lib/src/services/safe_zone_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

import '../../../services/env_config.dart';
import '../../../services/token_refresh_service.dart';

class SafeZoneService {
  // ✅ Use dynamic BASE_URL from EnvConfig
  static String get baseUrl => EnvConfig.baseUrl;

  // ✅ Token refresh service instance
  static final TokenRefreshService _tokenService = TokenRefreshService();

  /// ✅ Create a new safe zone with automatic token refresh
  static Future<Map<String, dynamic>> createSafeZone({
    required int vehicleId,
    required double latitude,
    required double longitude,
    String? name,
    int? radiusMeters,
  }) async {
    try {
      debugPrint('🔨 Creating safe zone for vehicle $vehicleId...');

      final response = await _tokenService.makeAuthenticatedRequest(
        request: (token) async {
          return await http.post(
            Uri.parse('$baseUrl/safezones'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'vehicle_id': vehicleId,
              'name': name ?? 'Safe Zone',
              'center_latitude': latitude,
              'center_longitude': longitude,
              'radius_meters': radiusMeters ?? 10,
            }),
          );
        },
      );

      debugPrint("📡 [SafeZone] Create response: ${response.statusCode}");

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message'] ?? 'Safe zone created successfully',
          'safeZone': data['data'],
        };
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Failed to create safe zone',
      };
    } catch (error) {
      debugPrint("🔥 Error creating safe zone: $error");
      return {'success': false, 'message': 'Error: $error'};
    }
  }

  /// ✅ Get safe zone for a specific vehicle with automatic token refresh
  static Future<Map<String, dynamic>> getSafeZone(int vehicleId) async {
    try {
      debugPrint('📡 Fetching safe zone for vehicle $vehicleId...');

      final response = await _tokenService.makeAuthenticatedRequest(
        request: (token) async {
          return await http.get(
            Uri.parse('$baseUrl/safezones/vehicle/$vehicleId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );
        },
      );

      debugPrint("📡 [SafeZone] Get response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Safe zone fetched successfully');
        return {'success': true, 'safeZone': data['data']};
      } else if (response.statusCode == 404) {
        debugPrint('ℹ️ No safe zone found');
        return {
          'success': false,
          'message': 'No safe zone found',
          'safeZone': null
        };
      } else if (response.statusCode == 403 || response.statusCode == 401) {
        debugPrint("⚠️ Authentication error - token may be invalid");
        return {
          'success': false,
          'message': 'Authentication error',
          'safeZone': null,
          'needsLogin': true,
        };
      }

      final data = jsonDecode(response.body);
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to fetch safe zone'
      };
    } catch (error) {
      debugPrint("🔥 Error fetching safe zone: $error");
      return {'success': false, 'message': 'Error: $error'};
    }
  }

  /// ✅ Get all safe zones for the current user with automatic token refresh
  static Future<Map<String, dynamic>> getAllSafeZones() async {
    try {
      debugPrint('📡 Fetching all safe zones...');

      final response = await _tokenService.makeAuthenticatedRequest(
        request: (token) async {
          return await http.get(
            Uri.parse('$baseUrl/safezones'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );
        },
      );

      debugPrint("📡 [SafeZone] Get all response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'safeZones': data['data'],
          'count': data['count'] ?? 0,
        };
      }

      final data = jsonDecode(response.body);
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to fetch safe zones'
      };
    } catch (error) {
      debugPrint("🔥 Error fetching all safe zones: $error");
      return {'success': false, 'message': 'Error: $error'};
    }
  }

  /// ✅ Update a safe zone with automatic token refresh
  static Future<Map<String, dynamic>> updateSafeZone({
    required int safeZoneId,
    String? name,
    double? latitude,
    double? longitude,
    int? radiusMeters,
  }) async {
    try {
      debugPrint('🔄 Updating safe zone $safeZoneId...');

      final Map<String, dynamic> body = {};
      if (name != null) body['name'] = name;
      if (latitude != null) body['center_latitude'] = latitude;
      if (longitude != null) body['center_longitude'] = longitude;
      if (radiusMeters != null) body['radius_meters'] = radiusMeters;

      final response = await _tokenService.makeAuthenticatedRequest(
        request: (token) async {
          return await http.put(
            Uri.parse('$baseUrl/safezones/$safeZoneId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          );
        },
      );

      debugPrint("📡 [SafeZone] Update response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? 'Safe zone updated successfully',
          'safeZone': data['data']
        };
      }

      final data = jsonDecode(response.body);
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to update safe zone'
      };
    } catch (error) {
      debugPrint("🔥 Error updating safe zone: $error");
      return {'success': false, 'message': 'Error: $error'};
    }
  }

  /// ✅ Toggle safe zone active/inactive with automatic token refresh
  static Future<Map<String, dynamic>> toggleSafeZone(int safeZoneId) async {
    try {
      debugPrint('🔄 Toggling safe zone $safeZoneId...');

      final response = await _tokenService.makeAuthenticatedRequest(
        request: (token) async {
          return await http.patch(
            Uri.parse('$baseUrl/safezones/$safeZoneId/toggle'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );
        },
      );

      debugPrint("📡 [SafeZone] Toggle response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? 'Safe zone toggled successfully',
          'safeZone': data['data']
        };
      }

      final data = jsonDecode(response.body);
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to toggle safe zone'
      };
    } catch (error) {
      debugPrint("🔥 Error toggling safe zone: $error");
      return {'success': false, 'message': 'Error: $error'};
    }
  }

  /// ✅ Delete safe zone with automatic token refresh
  static Future<Map<String, dynamic>> deleteSafeZone(int safeZoneId) async {
    try {
      debugPrint('🗑️ Deleting safe zone $safeZoneId...');

      final response = await _tokenService.makeAuthenticatedRequest(
        request: (token) async {
          return await http.delete(
            Uri.parse('$baseUrl/safezones/$safeZoneId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );
        },
      );

      debugPrint("📡 [SafeZone] Delete response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? 'Safe zone deleted successfully'
        };
      }

      final data = jsonDecode(response.body);
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to delete safe zone'
      };
    } catch (error) {
      debugPrint("🔥 Error deleting safe zone: $error");
      return {'success': false, 'message': 'Error: $error'};
    }
  }
}