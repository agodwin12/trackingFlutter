// lib/src/screens/dashboard/services/safe_zone_service.dart

import '../../../services/api_service.dart';

class SafeZoneService {
  /// Create a new safe zone
  static Future<Map<String, dynamic>> createSafeZone({
    required int vehicleId,
    required double latitude,
    required double longitude,
    String? name,
    int? radiusMeters,
  }) async {
    try {
      final data = await ApiService.post('/safezones', body: {
        'vehicle_id': vehicleId,
        'name': name ?? 'Safe Zone',
        'center_latitude': latitude,
        'center_longitude': longitude,
        'radius_meters': radiusMeters ?? 10,
      });

      if (data['statusCode'] == 201 || data['statusCode'] == 200) {
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
      rethrow;
    }
  }

  /// Get safe zone for a specific vehicle
  static Future<Map<String, dynamic>> getSafeZone(int vehicleId) async {
    try {
      final data =
      await ApiService.get('/safezones/vehicle/$vehicleId');

      if (data['statusCode'] == 200) {
        return {'success': true, 'safeZone': data['data']};
      }

      if (data['statusCode'] == 404) {
        return {'success': false, 'message': 'No safe zone found', 'safeZone': null};
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Failed to fetch safe zone',
      };
    } catch (error) {
      rethrow;
    }
  }

  /// Get all safe zones for the current user
  static Future<Map<String, dynamic>> getAllSafeZones() async {
    try {
      final data = await ApiService.get('/safezones');

      if (data['statusCode'] == 200) {
        return {
          'success': true,
          'safeZones': data['data'],
          'count': data['count'] ?? 0,
        };
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Failed to fetch safe zones',
      };
    } catch (error) {
      rethrow;
    }
  }

  /// Update a safe zone
  static Future<Map<String, dynamic>> updateSafeZone({
    required int safeZoneId,
    String? name,
    double? latitude,
    double? longitude,
    int? radiusMeters,
  }) async {
    try {
      final Map<String, dynamic> body = {};
      if (name != null) body['name'] = name;
      if (latitude != null) body['center_latitude'] = latitude;
      if (longitude != null) body['center_longitude'] = longitude;
      if (radiusMeters != null) body['radius_meters'] = radiusMeters;

      final data = await ApiService.put('/safezones/$safeZoneId', body: body);

      if (data['statusCode'] == 200) {
        return {
          'success': true,
          'message': data['message'] ?? 'Safe zone updated successfully',
          'safeZone': data['data'],
        };
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Failed to update safe zone',
      };
    } catch (error) {
      rethrow;
    }
  }

  /// Toggle safe zone active/inactive
  static Future<Map<String, dynamic>> toggleSafeZone(int safeZoneId) async {
    try {
      final data = await ApiService.patch('/safezones/$safeZoneId/toggle');

      if (data['statusCode'] == 200) {
        return {
          'success': true,
          'message': data['message'] ?? 'Safe zone toggled successfully',
          'safeZone': data['data'],
        };
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Failed to toggle safe zone',
      };
    } catch (error) {
      rethrow;
    }
  }

  /// Delete a safe zone
  static Future<Map<String, dynamic>> deleteSafeZone(int safeZoneId) async {
    try {
      final data = await ApiService.delete('/safezones/$safeZoneId');

      if (data['statusCode'] == 200) {
        return {
          'success': true,
          'message': data['message'] ?? 'Safe zone deleted successfully',
        };
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Failed to delete safe zone',
      };
    } catch (error) {
      rethrow;
    }
  }
}