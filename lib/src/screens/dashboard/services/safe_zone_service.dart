import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:tracking/src/services/env_config.dart';

class SafeZoneService {
  // ✅ Use dynamic BASE_URL from EnvConfig
  static String get baseUrl => EnvConfig.baseUrl;

  /// Retrieve user access token
  static Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('accessToken');
      debugPrint("🔑 Loaded token: ${token != null ? 'Exists' : 'Not found'}");
      return token;
    } catch (error) {
      debugPrint("🔥 Error getting token: $error");
      return null;
    }
  }

  /// ✅ Create a new safe zone
  static Future<Map<String, dynamic>> createSafeZone({
    required int vehicleId,
    required double latitude,
    required double longitude,
    String? name,
    int? radiusMeters,
  }) async {
    try {
      final token = await _getToken();

      final response = await http.post(
        Uri.parse('$baseUrl/safezones'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'vehicle_id': vehicleId,
          'name': name ?? 'Safe Zone',
          'center_latitude': latitude,
          'center_longitude': longitude,
          'radius_meters': radiusMeters ?? 10,
        }),
      );

      debugPrint("📡 [SafeZone] Create response: ${response.statusCode}");

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'],
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

  /// ✅ Get safe zone for a specific vehicle
  static Future<Map<String, dynamic>> getSafeZone(int vehicleId) async {
    try {
      final token = await _getToken();

      final response = await http.get(
        Uri.parse('$baseUrl/safezones/vehicle/$vehicleId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      debugPrint("📡 [SafeZone] Get response: ${response.statusCode}");

      if (response.statusCode == 403 || response.statusCode == 401) {
        debugPrint("⚠️ Authentication error - token may be invalid");
        return {
          'success': false,
          'message': 'Authentication error',
          'safeZone': null,
          'needsLogin': true, // ✅ Flag for re-authentication
        };
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'safeZone': data['data']};
      } else if (response.statusCode == 404) {
        return {'success': false, 'message': 'No safe zone found', 'safeZone': null};
      }

      return {'success': false, 'message': data['message'] ?? 'Failed to fetch safe zone'};
    } catch (error) {
      debugPrint("🔥 Error fetching safe zone: $error");
      return {'success': false, 'message': 'Error: $error'};
    }
  }


  /// ✅ Get all safe zones for the current user
  static Future<Map<String, dynamic>> getAllSafeZones() async {
    try {
      final token = await _getToken();

      final response = await http.get(
        Uri.parse('$baseUrl/safezones'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      debugPrint("📡 [SafeZone] Get all response: ${response.statusCode}");
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'safeZones': data['data'],
          'count': data['count'] ?? 0,
        };
      }

      return {'success': false, 'message': data['message'] ?? 'Failed to fetch safe zones'};
    } catch (error) {
      debugPrint("🔥 Error fetching all safe zones: $error");
      return {'success': false, 'message': 'Error: $error'};
    }
  }


  /// ✅ Update a safe zone
  static Future<Map<String, dynamic>> updateSafeZone({
    required int safeZoneId,
    String? name,
    double? latitude,
    double? longitude,
    int? radiusMeters,
  }) async {
    try {
      final token = await _getToken();

      final Map<String, dynamic> body = {};
      if (name != null) body['name'] = name;
      if (latitude != null) body['center_latitude'] = latitude;
      if (longitude != null) body['center_longitude'] = longitude;
      if (radiusMeters != null) body['radius_meters'] = radiusMeters;

      final response = await http.put(
        Uri.parse('$baseUrl/safezones/$safeZoneId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      debugPrint("📡 [SafeZone] Update response: ${response.statusCode}");
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'], 'safeZone': data['data']};
      }

      return {'success': false, 'message': data['message'] ?? 'Failed to update safe zone'};
    } catch (error) {
      debugPrint("🔥 Error updating safe zone: $error");
      return {'success': false, 'message': 'Error: $error'};
    }
  }

  /// ✅ Toggle safe zone active/inactive
  static Future<Map<String, dynamic>> toggleSafeZone(int safeZoneId) async {
    try {
      final token = await _getToken();

      final response = await http.patch(
        Uri.parse('$baseUrl/safezones/$safeZoneId/toggle'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      debugPrint("📡 [SafeZone] Toggle response: ${response.statusCode}");
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'], 'safeZone': data['data']};
      }

      return {'success': false, 'message': data['message'] ?? 'Failed to toggle safe zone'};
    } catch (error) {
      debugPrint("🔥 Error toggling safe zone: $error");
      return {'success': false, 'message': 'Error: $error'};
    }
  }

  /// ✅ Delete safe zone
  static Future<Map<String, dynamic>> deleteSafeZone(int safeZoneId) async {
    try {
      final token = await _getToken();

      final response = await http.delete(
        Uri.parse('$baseUrl/safezones/$safeZoneId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      debugPrint("📡 [SafeZone] Delete response: ${response.statusCode}");
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      }

      return {'success': false, 'message': data['message'] ?? 'Failed to delete safe zone'};
    } catch (error) {
      debugPrint("🔥 Error deleting safe zone: $error");
      return {'success': false, 'message': 'Error: $error'};
    }
  }
}
