// lib/src/services/payment_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/env_config.dart';

class PaymentService {
  static String get baseUrl => EnvConfig.baseUrl;

  // ── Auth token ─────────────────────────────────────────────
  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('accessToken');
  }

  // ── Get logged-in user ID ──────────────────────────────────
  static Future<int?> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('user_id');
    return id ?? prefs.getInt('userId');
  }

  // ── Fetch all available subscription plans ─────────────────
  static Future<List<Map<String, dynamic>>> getSubscriptionPlans() async {
    final token = await _getToken();

    final response = await http.get(
      Uri.parse('$baseUrl/payments/plans'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    debugPrint('📦 [PLANS] Status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['data']);
    } else {
      throw Exception('Failed to load subscription plans');
    }
  }

  // ── Fetch all vehicles for the logged-in user ──────────────
  static Future<List<Map<String, dynamic>>> getUserVehicles() async {
    final token  = await _getToken();
    final userId = await _getUserId();

    if (userId == null) throw Exception('User not logged in');

    debugPrint('🚗 [VEHICLES] Fetching vehicles for user: $userId');

    final response = await http.get(
      Uri.parse('$baseUrl/voitures/user/$userId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    debugPrint('🚗 [VEHICLES] Status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['vehicles']);
    } else if (response.statusCode == 404) {
      return [];
    } else {
      final data = jsonDecode(response.body);
      throw Exception(data['message'] ?? 'Failed to load vehicles');
    }
  }

  // ── Get active subscription for a single vehicle ───────────
  static Future<Map<String, dynamic>?> getVehicleSubscription(
      int vehicleId) async {
    final token = await _getToken();

    final response = await http.get(
      Uri.parse('$baseUrl/payments/vehicle/$vehicleId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    debugPrint('🔖 [SUBSCRIPTION] Vehicle $vehicleId → ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Map<String, dynamic>.from(data['data']);
    } else if (response.statusCode == 404) {
      return null;
    } else {
      debugPrint('⚠️ [SUBSCRIPTION] Unexpected status for vehicle $vehicleId');
      return null;
    }
  }

  // ── Single-vehicle payment ─────────────────────────────────
  // POST /payments/initiate
  static Future<Map<String, dynamic>> initiatePayment({
    required int    vehicleId,
    required int    planId,
    required String method,
    required String countryCode,   // ← now always included in body
    String? provider,
    String? phoneNumber,
  }) async {
    final token = await _getToken();

    // FIX: country_code was accepted as a parameter but never added to the
    // request body — PayGate rejected every request with:
    // "country_code": ["Le code pays est obligatoire."]
    final Map<String, dynamic> body = {
      'vehicle_id':   vehicleId,
      'plan_id':      planId,
      'method':       method,
      'country_code': countryCode,  // ← was missing
    };

    if (provider    != null) body['provider']     = provider;
    if (phoneNumber != null) body['phone_number'] = phoneNumber;

    debugPrint(
      '💳 [PAYMENT] Initiating | Vehicle: $vehicleId | Plan: $planId '
          '| Method: $method | Country: $countryCode',
    );

    final response = await http.post(
      Uri.parse('$baseUrl/payments/initiate'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    debugPrint('💳 [PAYMENT] Status: ${response.statusCode}');
    debugPrint('💳 [PAYMENT] Response: ${response.body}');

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(data['data']);
    } else {
      throw Exception(data['message'] ?? 'Payment initiation failed');
    }
  }

  // ── Batch payment — multiple vehicles, one PayGate call ────
  // POST /payments/initiate-batch
  static Future<Map<String, dynamic>> initiatePaymentBatch({
    required List<int> vehicleIds,
    required int       planId,
    required String    method,
    required String    countryCode,  // ← now always included in body
    String? provider,
    String? phoneNumber,
  }) async {
    final token = await _getToken();

    // FIX: same bug as initiatePayment — country_code was silently dropped
    final Map<String, dynamic> body = {
      'vehicle_ids':  vehicleIds,
      'plan_id':      planId,
      'method':       method,
      'country_code': countryCode,  // ← was missing
    };

    if (provider    != null) body['provider']     = provider;
    if (phoneNumber != null) body['phone_number'] = phoneNumber;

    debugPrint(
      '💳 [BATCH PAYMENT] Vehicles: $vehicleIds | Plan: $planId '
          '| Method: $method | Country: $countryCode',
    );

    final response = await http.post(
      Uri.parse('$baseUrl/payments/initiate-batch'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    debugPrint('💳 [BATCH PAYMENT] Status: ${response.statusCode}');
    debugPrint('💳 [BATCH PAYMENT] Response: ${response.body}');

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(data['data']);
    } else {
      throw Exception(data['message'] ?? 'Batch payment initiation failed');
    }
  }

  // ── Get payment history for logged-in user ─────────────────
  static Future<List<Map<String, dynamic>>> getPaymentHistory() async {
    final token = await _getToken();

    final response = await http.get(
      Uri.parse('$baseUrl/payments/history'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    debugPrint('📋 [HISTORY] Status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['data']);
    } else {
      throw Exception('Failed to load payment history');
    }
  }
}