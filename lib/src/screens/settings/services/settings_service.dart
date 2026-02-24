// lib/src/screens/settings/services/settings_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/env_config.dart';

class SettingsService {
  static String get baseUrl => EnvConfig.baseUrl;

  // ========== LOAD USER DATA FROM SHARED PREFERENCES ==========
  // ✅ Works for both regular users and chauffeurs
  // Does NOT make any API call — reads from what was saved at login
  static Future<Map<String, dynamic>?> loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');
      if (userDataString != null) {
        return jsonDecode(userDataString);
      }
      return null;
    } catch (e) {
      debugPrint('🔥 Error loading user data: $e');
      return null;
    }
  }

  // ========== LOAD VEHICLE ID FROM SHARED PREFERENCES ==========
  // ✅ Replaces the old _fetchUserVehicle() API call
  // Uses current_vehicle_id saved at login — works for both user types
  static Future<int?> loadCurrentVehicleId({int? fallback}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getInt('current_vehicle_id');
      if (savedId != null) {
        debugPrint('✅ Vehicle ID loaded from SharedPreferences: $savedId');
        return savedId;
      }
      // Use the vehicleId passed from dashboard if no saved ID
      if (fallback != null) {
        debugPrint('✅ Using fallback vehicle ID: $fallback');
        return fallback;
      }
      debugPrint('⚠️ No vehicle ID found');
      return null;
    } catch (e) {
      debugPrint('🔥 Error loading vehicle ID: $e');
      return fallback;
    }
  }

  // ========== LOAD USER TYPE ==========
  static Future<String> loadUserType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('user_type') ?? 'regular';
    } catch (e) {
      return 'regular';
    }
  }

  // ========== LOAD LANGUAGE ==========
  static Future<String> loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('language') ?? 'en';
    } catch (e) {
      return 'en';
    }
  }

  // ========== SAVE LANGUAGE ==========
  static Future<void> saveLanguage(String languageCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', languageCode);
      debugPrint('✅ Language saved: $languageCode');
    } catch (e) {
      debugPrint('🔥 Error saving language: $e');
    }
  }

  // ========== LOAD SETTINGS FROM LOCAL + BACKEND ==========
  static Future<Map<String, dynamic>> loadSettings(int? userId) async {
    final prefs = await SharedPreferences.getInstance();

    // Load from local first
    final localSettings = {
      'geofenceAlerts': prefs.getBool('geofence_alerts') ?? true,
      'safeZoneAlerts': prefs.getBool('safe_zone_alerts') ?? true,
      'tripTracking': prefs.getBool('trip_tracking') ?? false,
    };

    // Sync from backend if we have a userId
    if (userId != null) {
      try {
        final response = await http.get(
          Uri.parse('$baseUrl/users-settings/$userId/settings'),
          headers: {'Content-Type': 'application/json'},
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['data'] != null) {
            final settings = data['data']['settings'];
            localSettings['tripTracking'] =
                settings['tripTrackingEnabled'] ?? false;

            await prefs.setBool(
                'trip_tracking', localSettings['tripTracking'] as bool);
            debugPrint('✅ Settings synced from backend');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Backend settings sync failed, using local: $e');
      }
    }

    return localSettings;
  }

  // ========== SAVE SETTINGS LOCALLY ==========
  static Future<void> saveSettingsLocally({
    required bool geofenceAlerts,
    required bool safeZoneAlerts,
    required bool tripTracking,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('geofence_alerts', geofenceAlerts);
    await prefs.setBool('safe_zone_alerts', safeZoneAlerts);
    await prefs.setBool('trip_tracking', tripTracking);
    debugPrint('✅ Settings saved locally');
  }

  // ========== SAVE TRIP TRACKING TO BACKEND ==========
  static Future<void> saveTripTracking(int userId, bool enabled) async {
    final response = await http.put(
      Uri.parse('$baseUrl/users-settings/$userId/settings/trip-tracking'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'enabled': enabled}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to save trip tracking: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    if (data['success'] != true) {
      throw Exception('Backend rejected trip tracking update');
    }

    debugPrint('✅ Trip tracking saved to backend: $enabled');
  }

  // ========== CHECK PIN STATUS ==========
  static Future<bool> checkPinStatus(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/pin/exists/$userId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final hasPinSet = data['hasPinSet'] ?? false;
        debugPrint('✅ PIN status: ${hasPinSet ? "SET" : "NOT SET"}');
        return hasPinSet;
      }
      return false;
    } catch (e) {
      debugPrint('🔥 Error checking PIN status: $e');
      return false;
    }
  }

  // ========== CREATE PIN ==========
  static Future<void> createPin(int userId, String pin) async {
    final response = await http.post(
      Uri.parse('$baseUrl/pin/set'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'pin': pin}),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['success'] == true) {
      debugPrint('✅ PIN created successfully');
      return;
    }

    throw Exception(data['message'] ?? 'Failed to create PIN');
  }

  // ========== CHANGE PIN ==========
  static Future<void> changePin(
      int userId, String oldPin, String newPin) async {
    final response = await http.post(
      Uri.parse('$baseUrl/pin/change'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
        'oldPin': oldPin,
        'newPin': newPin,
      }),
    );

    if (response.statusCode == 400 || response.statusCode == 401) {
      throw Exception('Current PIN is incorrect');
    }

    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['success'] == true) {
      debugPrint('✅ PIN changed successfully');
      return;
    }

    throw Exception(data['message'] ?? 'Failed to change PIN');
  }

  // ========== LOGOUT ==========
  // ✅ Clears all keys including vehicles_list and user_type
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');
    await prefs.remove('accessToken');
    await prefs.remove('auth_token');
    await prefs.remove('refreshToken');
    await prefs.remove('userId');
    await prefs.remove('user_id');
    await prefs.remove('user_type');
    await prefs.remove('partner_id');
    await prefs.remove('vehicles_list');
    await prefs.remove('current_vehicle_id');
    await prefs.remove('failed_pin_attempts');
    debugPrint('✅ All session data cleared');
  }
}