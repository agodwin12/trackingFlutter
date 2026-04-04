

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class VehiclesRefreshService {
  VehiclesRefreshService._();


  static Future<bool> refreshVehiclesList() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');

      if (userStr == null) {
        debugPrint('⚠️ [VehiclesRefresh] No user in prefs — skipping refresh');
        return false;
      }

      final userId = (jsonDecode(userStr)['id'] as num).toInt();

      debugPrint('🔄 [VehiclesRefresh] Fetching vehicles for user $userId...');

      final data = await ApiService.get('/voitures/user/$userId');

      if (data['success'] != true) {
        debugPrint('❌ [VehiclesRefresh] API returned success=false');
        return false;
      }

      final List<dynamic> vehicles = data['vehicles'] as List<dynamic>;

      // Overwrite vehicles_list — same key and format written at login
      await prefs.setString('vehicles_list', jsonEncode(vehicles));

      debugPrint(
        '✅ [VehiclesRefresh] vehicles_list updated — '
            '${vehicles.length} vehicle(s)',
      );

      return true;
    } catch (e) {
      debugPrint('❌ [VehiclesRefresh] Error: $e');
      return false;
    }
  }
}