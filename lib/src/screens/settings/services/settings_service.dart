// lib/src/screens/settings/services/settings_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';

class SettingsService {
  // ========== LOAD USER DATA FROM SHARED PREFERENCES ==========
  static Future<Map<String, dynamic>?> loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');
      if (userDataString != null) {
        return jsonDecode(userDataString) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('🔥 Error loading user data: $e');
      return null;
    }
  }

  // ========== LOAD VEHICLE ID FROM SHARED PREFERENCES ==========
  static Future<int?> loadCurrentVehicleId({int? fallback}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getInt('current_vehicle_id');
      if (savedId != null) {
        debugPrint('✅ Vehicle ID loaded from SharedPreferences: $savedId');
        return savedId;
      }
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

    final localSettings = <String, dynamic>{
      'geofenceAlerts': prefs.getBool('geofence_alerts') ?? true,
      'safeZoneAlerts': prefs.getBool('safe_zone_alerts') ?? true,
      'tripTracking': prefs.getBool('trip_tracking') ?? false,
    };

    if (userId != null) {
      try {
        final data =
        await ApiService.get('/users-settings/$userId/settings');

        if (data['success'] == true && data['data'] != null) {
          final settings = data['data']['settings'];
          localSettings['tripTracking'] =
              settings['tripTrackingEnabled'] ?? false;

          await prefs.setBool(
              'trip_tracking', localSettings['tripTracking'] as bool);
          debugPrint('✅ Settings synced from backend');
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
    final data = await ApiService.put(
      '/users-settings/$userId/settings/trip-tracking',
      body: {'enabled': enabled},
    );

    if (data['success'] != true) {
      throw Exception(
          data['message'] ?? 'Backend rejected trip tracking update');
    }

    debugPrint('✅ Trip tracking saved to backend: $enabled');
  }

  // ========== CHECK PIN STATUS ==========
  static Future<bool> checkPinStatus(int userId) async {
    try {
      final data = await ApiService.get('/pin/exists/$userId');
      final hasPinSet = data['hasPinSet'] ?? false;
      debugPrint('✅ PIN status: ${hasPinSet ? "SET" : "NOT SET"}');
      return hasPinSet as bool;
    } catch (e) {
      debugPrint('🔥 Error checking PIN status: $e');
      return false;
    }
  }

  // ========== CREATE PIN ==========
  static Future<void> createPin(int userId, String pin) async {
    final data = await ApiService.post(
      '/pin/set',
      body: {'userId': userId, 'pin': pin},
    );

    if (data['success'] == true) {
      debugPrint('✅ PIN created successfully');
      return;
    }

    throw Exception(data['message'] ?? 'Failed to create PIN');
  }

  // ========== CHANGE PIN ==========
  static Future<void> changePin(
      int userId, String oldPin, String newPin) async {
    final data = await ApiService.post(
      '/pin/change',
      body: {'userId': userId, 'oldPin': oldPin, 'newPin': newPin},
    );

    if (data['statusCode'] == 400 || data['statusCode'] == 401) {
      throw Exception('Current PIN is incorrect');
    }

    if (data['success'] == true) {
      debugPrint('✅ PIN changed successfully');
      return;
    }

    throw Exception(data['message'] ?? 'Failed to change PIN');
  }

  // ========== LOAD VEHICLE SUBSCRIPTION STATUS ==========
  /// Returns one of: 'ACTIVE' | 'EXPIRED' | 'CANCELLED' | 'NONE'
  /// 'NONE' means no subscription record exists for this vehicle.
  static Future<String> loadVehicleSubscriptionStatus(int vehicleId) async {
    try {
      final data = await ApiService.get('/payments/vehicle/$vehicleId');

      if (data['success'] == true && data['subscription'] != null) {
        final status = data['subscription']['status'] as String?;
        debugPrint('✅ Subscription status for vehicle $vehicleId: $status');
        return status ?? 'NONE';
      }

      return 'NONE';
    } on FeatureNotSubscribedException {
      return 'NONE';
    } catch (e) {
      debugPrint('⚠️ Could not load subscription status: $e');
      return 'NONE';
    }
  }

  // ========== LOGOUT ==========
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