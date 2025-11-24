import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:tracking/src/services/env_config.dart';

class DashboardService {
  // ✅ Using EnvConfig for base URL
  static String get baseUrl => EnvConfig.baseUrl;

  /// Load user data from SharedPreferences
  static Future<Map<String, dynamic>?> loadUserData() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userData = prefs.getString("user");

      if (userData != null) {
        return jsonDecode(userData);
      }
      return null;
    } catch (error) {
      debugPrint("🔥 Error loading user data: $error");
      return null;
    }
  }

  /// Fetch all vehicles for a user
  static Future<List<dynamic>> fetchVehicles(int userId) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/voitures/user/$userId"),
      );

      debugPrint("📡 Vehicles response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data["vehicles"] ?? [];
      }
      return [];
    } catch (error) {
      debugPrint("🔥 Error fetching vehicles: $error");
      return [];
    }
  }

  /// This returns the ACTUAL current engine state from GPS device
  /// Uses: Cache → Database → GPS API (fallback)
  static Future<Map<String, dynamic>> fetchRealtimeVehicleStatus(int vehicleId) async {
    try {
      debugPrint("🔍 Fetching real-time status for vehicle $vehicleId");

      final response = await http.get(
        Uri.parse("$baseUrl/gps/vehicle/$vehicleId/realtime-status"),
      );

      debugPrint("📡 Realtime status response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("📦 Realtime status data: ${jsonEncode(data)}");

        if (data['success'] == true) {
          // ✅ Parse engineOn with multiple type support
          bool engineOn = false;
          final engineValue = data['engineOn'];
          if (engineValue is bool) {
            engineOn = engineValue;
          } else if (engineValue is num) {
            engineOn = engineValue != 0;
          } else if (engineValue is String) {
            engineOn = (engineValue == '1' || engineValue.toLowerCase() == 'true');
          }

          // Parse accOn similarly
          bool accOn = false;
          final accValue = data['accOn'];
          if (accValue is bool) {
            accOn = accValue;
          } else if (accValue is num) {
            accOn = accValue != 0;
          } else if (accValue is String) {
            accOn = (accValue == '1' || accValue.toLowerCase() == 'true');
          }

          debugPrint("✅ Engine Status: ${engineOn ? 'ON' : 'OFF'}");
          debugPrint("✅ Data Source: ${data['source']}"); // cache, database, or api

          return {
            'success': true,
            'engineOn': engineOn,
            'accOn': accOn,
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
      }

      return {
        'success': false,
        'engineOn': false,
        'accOn': false,
        'gpsStatus': "Disconnected",
        'speed': "0",
      };
    } catch (error) {
      debugPrint("🔥 Error fetching realtime vehicle status: $error");
      return {
        'success': false,
        'engineOn': false,
        'accOn': false,
        'gpsStatus': "Disconnected",
        'speed': "0",
      };
    }
  }

  /// Fetch vehicle status (DEPRECATED - use fetchRealtimeVehicleStatus instead)
  /// This is kept for backward compatibility but should be replaced
  static Future<Map<String, dynamic>> fetchVehicleStatus(int vehicleId) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/gps/vehicle/$vehicleId/status"),
      );

      debugPrint("📡 Status response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("📦 Status data: ${jsonEncode(data)}");

        if (data['success'] == true) {
          // ✅ Parse engineOn with multiple type support
          bool engineOn = false;
          final engineValue = data['engineOn'];
          if (engineValue is bool) {
            engineOn = engineValue;
          } else if (engineValue is num) {
            engineOn = engineValue != 0;
          } else if (engineValue is String) {
            engineOn = (engineValue == '1' || engineValue.toLowerCase() == 'true');
          }

          // Parse accOn similarly
          bool accOn = false;
          final accValue = data['accOn'];
          if (accValue is bool) {
            accOn = accValue;
          } else if (accValue is num) {
            accOn = accValue != 0;
          } else if (accValue is String) {
            accOn = (accValue == '1' || accValue.toLowerCase() == 'true');
          }

          return {
            'success': true,
            'engineOn': engineOn,
            'accOn': accOn,
            'gpsStatus': data['gpsStatus']?.toString() ?? "Disconnected",
            'speed': data['speed']?.toString() ?? "0",
            'rawStatus': data['rawStatus']?.toString(),
          };
        }
      }

      return {
        'success': false,
        'engineOn': false,
        'accOn': false,
        'gpsStatus': "Disconnected",
        'speed': "0",
      };
    } catch (error) {
      debugPrint("🔥 Error fetching vehicle status: $error");
      return {
        'success': false,
        'engineOn': false,
        'accOn': false,
        'gpsStatus': "Disconnected",
        'speed': "0",
      };
    }
  }

  /// Fetch current location of vehicle
  static Future<Map<String, dynamic>> fetchCurrentLocation(int vehicleId) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/tracking/location/vehicle/$vehicleId/latest"),
      );

      debugPrint("📡 Location response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          // ✅ Convert to double safely (API returns DECIMAL as numbers)
          double? latitude;
          double? longitude;
          double? speed;

          // Parse latitude
          if (data['latitude'] != null) {
            if (data['latitude'] is num) {
              latitude = (data['latitude'] as num).toDouble();
            } else if (data['latitude'] is String) {
              latitude = double.tryParse(data['latitude']);
            }
          }

          // Parse longitude
          if (data['longitude'] != null) {
            if (data['longitude'] is num) {
              longitude = (data['longitude'] as num).toDouble();
            } else if (data['longitude'] is String) {
              longitude = double.tryParse(data['longitude']);
            }
          }

          // Parse speed
          if (data['speed'] != null) {
            if (data['speed'] is num) {
              speed = (data['speed'] as num).toDouble();
            } else if (data['speed'] is String) {
              speed = double.tryParse(data['speed']);
            }
          }

          return {
            'success': true,
            'latitude': latitude ?? 0.0,
            'longitude': longitude ?? 0.0,
            'address': "Location available",
            'sys_time': DateTime.now().toIso8601String(),
            'speed': speed ?? 0.0,
            'engine_status': data['engine_status'] ?? 'OFF',
            'car_model': data['car_model'] ?? 'Unknown',
          };
        }
      }

      return {
        'success': false,
        'address': "Unable to fetch location",
      };
    } catch (error) {
      debugPrint("⚠️ Error fetching location: $error");
      return {
        'success': false,
        'address': "Unable to fetch location",
      };
    }
  }

  /// Fetch geofencing status
  static Future<bool> fetchGeofencingStatus(int vehicleId) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/vehicle/$vehicleId/security/status"),
      );

      debugPrint("📡 Geofencing status response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['security'] != null) {
          return data['security']['is_active'] ?? false;
        }
      }
      return false;
    } catch (error) {
      debugPrint("⚠️ Error fetching geofencing status: $error");
      return false;
    }
  }

  /// Fetch weekly statistics
  static Future<Map<String, dynamic>> fetchWeeklyStatistics(int vehicleId) async {
    try {
      // Calculate date range for last 7 days
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 7));

      final response = await http.get(
        Uri.parse(
            "$baseUrl/trips/vehicle/$vehicleId/stats"
                "?startDate=${startDate.toIso8601String().split('T')[0]}"
                "&endDate=${endDate.toIso8601String().split('T')[0]}"
        ),
      );

      debugPrint("📡 Weekly stats response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final stats = data['data']?['statistics'];

          if (stats != null) {
            return {
              'success': true,
              'totalDistanceKm': (stats['totalDistanceKm'] ?? 0).toDouble(),
              'totalTrips': stats['totalTrips'] ?? 0,
              'avgSpeed': (stats['avgSpeed'] ?? 0).toDouble(),
              'totalDurationFormatted': stats['totalDurationFormatted'] ?? "0h 0m",
            };
          }
        }
      }

      return {
        'success': false,
        'totalDistanceKm': 0.0,
        'totalTrips': 0,
        'avgSpeed': 0.0,
        'totalDurationFormatted': "0h 0m",
      };
    } catch (error) {
      debugPrint("⚠️ Error fetching weekly statistics: $error");
      return {
        'success': false,
        'totalDistanceKm': 0.0,
        'totalTrips': 0,
        'avgSpeed': 0.0,
        'totalDurationFormatted': "0h 0m",
      };
    }
  }

  /// Fetch recent trips
  static Future<List<Map<String, dynamic>>> fetchRecentTrips(int vehicleId) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/trips/vehicle/$vehicleId?page=1&limit=5"),
      );

      debugPrint("📡 Recent trips response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final trips = data['data']['trips'] as List;

          return trips.map((trip) {
            return {
              "id": trip['id'],
              "title": _getTripTitle(trip['startTime']),
              "from": trip['startLocation']['address']?.split(',')[0] ?? "Unknown",
              "to": trip['endLocation']['address']?.split(',')[0] ?? "Unknown",
              "time": "${_formatTime(trip['startTime'])} - ${_formatTime(trip['endTime'])}",
              "distance": "${trip['totalDistanceKm']} km",
              "date": _getRelativeDate(trip['startTime']),
            };
          }).toList();
        }
      }

      return [];
    } catch (error) {
      debugPrint("⚠️ Error fetching recent trips: $error");
      return [];
    }
  }

  /// Fetch unread notifications count
  static Future<Map<String, dynamic>> fetchUnreadNotifications(int vehicleId) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/notifications/vehicle/$vehicleId/unread-count"),
      );

      debugPrint("📡 Unread notifications response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          return {
            'success': true,
            'unreadCount': data['unreadCount'] ?? 0,
          };
        }
      }

      return {
        'success': false,
        'unreadCount': 0,
      };
    } catch (error) {
      debugPrint("⚠️ Error fetching unread notifications: $error");
      return {
        'success': false,
        'unreadCount': 0,
      };
    }
  }

  // ========== HELPER METHODS ==========

  /// Generate trip title based on time
  static String _getTripTitle(String dateString) {
    final date = DateTime.parse(dateString);
    final hour = date.hour;

    if (hour >= 5 && hour < 9) {
      return "Morning Commute";
    } else if (hour >= 12 && hour < 14) {
      return "Lunch Break";
    } else if (hour >= 17 && hour < 20) {
      return "Evening Return";
    } else if (hour >= 20 || hour < 5) {
      return "Night Trip";
    } else {
      return "Midday Trip";
    }
  }

  /// Format time from datetime string
  static String _formatTime(String dateString) {
    final date = DateTime.parse(dateString);
    final hour = date.hour > 12 ? date.hour - 12 : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? "PM" : "AM";
    return "$hour:$minute $period";
  }

  /// Get relative date (Today, Yesterday, etc.)
  static String _getRelativeDate(String dateString) {
    final date = DateTime.parse(dateString);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tripDate = DateTime(date.year, date.month, date.day);

    final difference = today.difference(tripDate).inDays;

    if (difference == 0) {
      return "Today";
    } else if (difference == 1) {
      return "Yesterday";
    } else if (difference < 7) {
      return "$difference days ago";
    } else {
      return "${date.day}/${date.month}/${date.year}";
    }
  }

  /// Get time ago string
  static String getTimeAgo(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inSeconds < 60) return "Just now";
    if (difference.inMinutes < 60) return "${difference.inMinutes}m ago";
    if (difference.inHours < 24) return "${difference.inHours}h ago";
    return "${difference.inDays}d ago";
  }
}