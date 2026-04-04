// lib/src/screens/dashboard/services/dashboard_service.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';

class DashboardService {
  /// Load user data from SharedPreferences
  static Future<Map<String, dynamic>?> loadUserData() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString("user");
      if (userData != null) {
        return Map<String, dynamic>.from(jsonDecode(userData));
      }
      return null;
    } catch (error) {
      debugPrint("🔥 Error loading user data: $error");
      return null;
    }
  }


  static Future<List<dynamic>> fetchVehicles(int userId) async {
    try {
      final data = await ApiService.get('/voitures/user/$userId');

      if (data['success'] == true) {
        final vehicles = data['vehicles'] ?? [];

        // Cache each vehicle display name for notification resolution
        if ((vehicles as List).isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          for (final v in vehicles) {
            final id = v['id'];
            if (id == null) continue;
            final displayName =
            (v['nickname'] as String?)?.trim().isNotEmpty == true
                ? v['nickname'] as String
                : (v['immatriculation'] as String?) ?? 'Vehicle $id';
            await prefs.setString('vehicle_name_$id', displayName);
          }
          debugPrint("💾 Cached display names for ${vehicles.length} vehicle(s)");
        }

        return vehicles;
      }

      return [];
    } catch (error) {
      debugPrint("🔥 Error fetching vehicles: $error");
      return [];
    }
  }

  /// Returns the ACTUAL current engine state from GPS device.
  /// Uses: Cache → Database → GPS API (fallback)
  static Future<Map<String, dynamic>> fetchRealtimeVehicleStatus(
      int vehicleId) async {
    try {
      debugPrint("🔍 Fetching real-time status for vehicle $vehicleId");

      final data =
      await ApiService.get('/gps/vehicle/$vehicleId/realtime-status');

      if (data['success'] == true) {
        return {
          'success': true,
          'engineOn': _parseBool(data['engineOn']),
          'accOn': _parseBool(data['accOn']),
          'gpsStatus': data['gpsStatus']?.toString() ?? "Disconnected",
          'speed': data['speed']?.toString() ?? "0",
          'rawStatus': data['rawStatus']?.toString(),
          'source': data['source']?.toString() ?? "unknown",
          'latitude': data['latitude'],
          'longitude': data['longitude'],
          'lastUpdate': data['lastUpdate']?.toString(),
          'dataAgeSeconds': data['dataAgeSeconds'],
        };
      }

      return _failedEngineStatus();
    } catch (error) {
      debugPrint("🔥 Error fetching realtime vehicle status: $error");
      // FeatureNotSubscribedException propagates up — do not swallow it
      rethrow;
    }
  }

  /// Fetch vehicle status (DEPRECATED — use fetchRealtimeVehicleStatus)
  static Future<Map<String, dynamic>> fetchVehicleStatus(
      int vehicleId) async {
    try {
      final data =
      await ApiService.get('/gps/vehicle/$vehicleId/status');

      if (data['success'] == true) {
        return {
          'success': true,
          'engineOn': _parseBool(data['engineOn']),
          'accOn': _parseBool(data['accOn']),
          'gpsStatus': data['gpsStatus']?.toString() ?? "Disconnected",
          'speed': data['speed']?.toString() ?? "0",
          'rawStatus': data['rawStatus']?.toString(),
        };
      }

      return _failedEngineStatus();
    } catch (error) {
      debugPrint("🔥 Error fetching vehicle status: $error");
      rethrow;
    }
  }

  /// Fetch current location of vehicle
  static Future<Map<String, dynamic>> fetchCurrentLocation(
      int vehicleId) async {
    try {
      final data = await ApiService.get(
          '/tracking/location/vehicle/$vehicleId/latest');

      if (data['success'] == true) {
        return {
          'success': true,
          'latitude': _parseDouble(data['latitude']),
          'longitude': _parseDouble(data['longitude']),
          'address': "Location available",
          'sys_time': DateTime.now().toIso8601String(),
          'speed': _parseDouble(data['speed']),
          'engine_status': data['engine_status'] ?? 'OFF',
          'car_model': data['car_model'] ?? 'Unknown',
        };
      }

      return {'success': false, 'address': "Unable to fetch location"};
    } catch (error) {
      debugPrint("⚠️ Error fetching location: $error");
      rethrow;
    }
  }

  /// Fetch geofencing / security status
  static Future<bool?> fetchGeofencingStatus(int vehicleId) async {
    try {
      debugPrint("📡 Fetching geofencing status for vehicle $vehicleId...");

      final data =
      await ApiService.get('/vehicle/$vehicleId/security/status');

      if (data['success'] == true && data['security'] != null) {
        final status = _parseBool(data['security']['is_active']);
        debugPrint(
            "✅ Geofencing status: ${status ? 'ACTIVE' : 'INACTIVE'}");
        return status;
      }

      return null;
    } catch (error) {
      debugPrint("🔥 Error fetching geofencing status: $error");
      rethrow;
    }
  }

  /// Fetch weekly trip statistics
  static Future<Map<String, dynamic>> fetchWeeklyStatistics(
      int vehicleId) async {
    try {
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 7));

      final data = await ApiService.get(
        '/trips/vehicle/$vehicleId/stats',
        queryParams: {
          'startDate': startDate.toIso8601String().split('T')[0],
          'endDate': endDate.toIso8601String().split('T')[0],
        },
      );

      if (data['success'] == true) {
        final stats = data['data']?['statistics'];
        if (stats != null) {
          return {
            'success': true,
            'totalDistanceKm':
            (stats['totalDistanceKm'] ?? 0).toDouble(),
            'totalTrips': stats['totalTrips'] ?? 0,
            'avgSpeed': (stats['avgSpeed'] ?? 0).toDouble(),
            'totalDurationFormatted':
            stats['totalDurationFormatted'] ?? "0h 0m",
          };
        }
      }

      return _failedStats();
    } catch (error) {
      debugPrint("⚠️ Error fetching weekly statistics: $error");
      rethrow;
    }
  }

  /// Fetch recent trips (last 5)
  static Future<List<Map<String, dynamic>>> fetchRecentTrips(
      int vehicleId) async {
    try {
      final data = await ApiService.get(
        '/trips/vehicle/$vehicleId',
        queryParams: {'page': '1', 'limit': '5'},
      );

      if (data['success'] == true) {
        final trips = data['data']['trips'] as List;
        return trips.map((trip) {
          return {
            "id": trip['id'],
            "title": _getTripTitle(trip['startTime']),
            "from": trip['startLocation']['address']?.split(',')[0] ??
                "Unknown",
            "to": trip['endLocation']['address']?.split(',')[0] ??
                "Unknown",
            "time":
            "${_formatTime(trip['startTime'])} - ${_formatTime(trip['endTime'])}",
            "distance": "${trip['totalDistanceKm']} km",
            "date": _getRelativeDate(trip['startTime']),
          };
        }).toList();
      }

      return [];
    } catch (error) {
      debugPrint("⚠️ Error fetching recent trips: $error");
      rethrow;
    }
  }

  /// Fetch unread notifications count
  static Future<Map<String, dynamic>> fetchUnreadNotifications(
      int vehicleId) async {
    try {
      final data = await ApiService.get(
          '/notifications/vehicle/$vehicleId/unread-count');

      if (data['success'] == true) {
        return {
          'success': true,
          'unreadCount': data['unreadCount'] ?? 0,
        };
      }

      return {'success': false, 'unreadCount': 0};
    } catch (error) {
      debugPrint("⚠️ Error fetching unread notifications: $error");
      return {'success': false, 'unreadCount': 0};
    }
  }

  // ─── HELPERS ──────────────────────────────────────────────────────────────

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      return value == '1' || value.toLowerCase() == 'true';
    }
    return false;
  }

  static double _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static Map<String, dynamic> _failedEngineStatus() => {
    'success': false,
    'engineOn': false,
    'accOn': false,
    'gpsStatus': "Disconnected",
    'speed': "0",
  };

  static Map<String, dynamic> _failedStats() => {
    'success': false,
    'totalDistanceKm': 0.0,
    'totalTrips': 0,
    'avgSpeed': 0.0,
    'totalDurationFormatted': "0h 0m",
  };

  static String _getTripTitle(String dateString) {
    final date = DateTime.parse(dateString);
    final hour = date.hour;
    if (hour >= 5 && hour < 9) return "Morning Commute";
    if (hour >= 12 && hour < 14) return "Lunch Break";
    if (hour >= 17 && hour < 20) return "Evening Return";
    if (hour >= 20 || hour < 5) return "Night Trip";
    return "Midday Trip";
  }

  static String _formatTime(String dateString) {
    final date = DateTime.parse(dateString);
    final hour = date.hour > 12 ? date.hour - 12 : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? "PM" : "AM";
    return "$hour:$minute $period";
  }

  static String _getRelativeDate(String dateString) {
    final date = DateTime.parse(dateString);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tripDate = DateTime(date.year, date.month, date.day);
    final difference = today.difference(tripDate).inDays;
    if (difference == 0) return "Today";
    if (difference == 1) return "Yesterday";
    if (difference < 7) return "$difference days ago";
    return "${date.day}/${date.month}/${date.year}";
  }

  static String getTimeAgo(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    if (difference.inSeconds < 60) return "Just now";
    if (difference.inMinutes < 60) return "${difference.inMinutes}m ago";
    if (difference.inHours < 24) return "${difference.inHours}h ago";
    return "${difference.inDays}d ago";
  }
}