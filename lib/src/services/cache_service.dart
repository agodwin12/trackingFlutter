import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  // Cache keys
  static const String _vehicleListKey = 'cached_vehicle_list';
  static const String _vehicleDetailsKey = 'cached_vehicle_';
  static const String _tripsKey = 'cached_trips_';
  static const String _lastCacheTimeKey = 'last_cache_time_';

  /// =====================================================
  /// 🚗 VEHICLE CACHING
  /// =====================================================

  /// Save vehicle list to cache
  Future<bool> cacheVehicleList(List<Map<String, dynamic>> vehicles) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(vehicles);
      await prefs.setString(_vehicleListKey, jsonString);
      await prefs.setString('${_lastCacheTimeKey}vehicles', DateTime.now().toIso8601String());
      debugPrint('✅ Cached ${vehicles.length} vehicles');
      return true;
    } catch (e) {
      debugPrint('❌ Error caching vehicle list: $e');
      return false;
    }
  }

  /// Get cached vehicle list
  Future<List<Map<String, dynamic>>?> getCachedVehicleList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_vehicleListKey);

      if (jsonString == null) {
        debugPrint('ℹ️ No cached vehicle list found');
        return null;
      }

      final List<dynamic> decoded = jsonDecode(jsonString);
      final vehicles = decoded.map((e) => e as Map<String, dynamic>).toList();

      final cacheTime = prefs.getString('${_lastCacheTimeKey}vehicles');
      debugPrint('✅ Retrieved ${vehicles.length} cached vehicles (cached: $cacheTime)');

      return vehicles;
    } catch (e) {
      debugPrint('❌ Error retrieving cached vehicles: $e');
      return null;
    }
  }

  /// Save individual vehicle details
  Future<bool> cacheVehicleDetails(int vehicleId, Map<String, dynamic> vehicleData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(vehicleData);
      await prefs.setString('$_vehicleDetailsKey$vehicleId', jsonString);
      await prefs.setString('${_lastCacheTimeKey}vehicle_$vehicleId', DateTime.now().toIso8601String());
      debugPrint('✅ Cached vehicle details for ID: $vehicleId');
      return true;
    } catch (e) {
      debugPrint('❌ Error caching vehicle details: $e');
      return false;
    }
  }

  /// Get cached vehicle details
  Future<Map<String, dynamic>?> getCachedVehicleDetails(int vehicleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('$_vehicleDetailsKey$vehicleId');

      if (jsonString == null) {
        debugPrint('ℹ️ No cached details for vehicle $vehicleId');
        return null;
      }

      final vehicleData = jsonDecode(jsonString) as Map<String, dynamic>;
      final cacheTime = prefs.getString('${_lastCacheTimeKey}vehicle_$vehicleId');
      debugPrint('✅ Retrieved cached vehicle $vehicleId (cached: $cacheTime)');

      return vehicleData;
    } catch (e) {
      debugPrint('❌ Error retrieving cached vehicle details: $e');
      return null;
    }
  }

  /// =====================================================
  /// 🛣️ TRIP CACHING (Last 30 days)
  /// =====================================================

  /// Save trips for a vehicle
  Future<bool> cacheTrips(int vehicleId, List<Map<String, dynamic>> trips) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Filter trips from last 30 days
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final recentTrips = trips.where((trip) {
        try {
          final startTime = DateTime.parse(trip['start_time'] ?? '');
          return startTime.isAfter(thirtyDaysAgo);
        } catch (e) {
          return false;
        }
      }).toList();

      final jsonString = jsonEncode(recentTrips);
      await prefs.setString('$_tripsKey$vehicleId', jsonString);
      await prefs.setString('${_lastCacheTimeKey}trips_$vehicleId', DateTime.now().toIso8601String());

      debugPrint('✅ Cached ${recentTrips.length} trips for vehicle $vehicleId (last 30 days)');
      return true;
    } catch (e) {
      debugPrint('❌ Error caching trips: $e');
      return false;
    }
  }

  /// Get cached trips for a vehicle
  Future<List<Map<String, dynamic>>?> getCachedTrips(int vehicleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('$_tripsKey$vehicleId');

      if (jsonString == null) {
        debugPrint('ℹ️ No cached trips for vehicle $vehicleId');
        return null;
      }

      final List<dynamic> decoded = jsonDecode(jsonString);
      final trips = decoded.map((e) => e as Map<String, dynamic>).toList();

      final cacheTime = prefs.getString('${_lastCacheTimeKey}trips_$vehicleId');
      debugPrint('✅ Retrieved ${trips.length} cached trips for vehicle $vehicleId (cached: $cacheTime)');

      return trips;
    } catch (e) {
      debugPrint('❌ Error retrieving cached trips: $e');
      return null;
    }
  }

  /// =====================================================
  /// 📍 LAST KNOWN LOCATION CACHING
  /// =====================================================

  /// Save last known location for a vehicle
  Future<bool> cacheLastLocation(int vehicleId, double lat, double lng, DateTime timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final locationData = {
        'lat': lat,
        'lng': lng,
        'timestamp': timestamp.toIso8601String(),
      };

      await prefs.setString('last_location_$vehicleId', jsonEncode(locationData));
      debugPrint('✅ Cached last location for vehicle $vehicleId');
      return true;
    } catch (e) {
      debugPrint('❌ Error caching last location: $e');
      return false;
    }
  }

  /// Get cached last location
  Future<Map<String, dynamic>?> getCachedLastLocation(int vehicleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('last_location_$vehicleId');

      if (jsonString == null) return null;

      final locationData = jsonDecode(jsonString) as Map<String, dynamic>;
      debugPrint('✅ Retrieved cached location for vehicle $vehicleId');
      return locationData;
    } catch (e) {
      debugPrint('❌ Error retrieving cached location: $e');
      return null;
    }
  }

  /// =====================================================
  /// 🗑️ CACHE MANAGEMENT
  /// =====================================================

  /// Clear all cache
  Future<bool> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith('cached_') || key.startsWith('last_cache_time_') || key.startsWith('last_location_')) {
          await prefs.remove(key);
        }
      }

      debugPrint('✅ Cleared all cache');
      return true;
    } catch (e) {
      debugPrint('❌ Error clearing cache: $e');
      return false;
    }
  }

  /// Clear cache for specific vehicle
  Future<bool> clearVehicleCache(int vehicleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_vehicleDetailsKey$vehicleId');
      await prefs.remove('$_tripsKey$vehicleId');
      await prefs.remove('last_location_$vehicleId');
      await prefs.remove('${_lastCacheTimeKey}vehicle_$vehicleId');
      await prefs.remove('${_lastCacheTimeKey}trips_$vehicleId');

      debugPrint('✅ Cleared cache for vehicle $vehicleId');
      return true;
    } catch (e) {
      debugPrint('❌ Error clearing vehicle cache: $e');
      return false;
    }
  }

  /// Get cache age in minutes
  Future<int?> getCacheAge(String type, {int? vehicleId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = vehicleId != null
          ? '${_lastCacheTimeKey}${type}_$vehicleId'
          : '${_lastCacheTimeKey}$type';

      final cacheTimeString = prefs.getString(key);
      if (cacheTimeString == null) return null;

      final cacheTime = DateTime.parse(cacheTimeString);
      final age = DateTime.now().difference(cacheTime).inMinutes;

      return age;
    } catch (e) {
      debugPrint('❌ Error getting cache age: $e');
      return null;
    }
  }
}