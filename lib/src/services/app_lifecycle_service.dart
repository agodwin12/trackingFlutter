// lib/services/app_lifecycle_service.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLifecycleService with WidgetsBindingObserver {
  static final AppLifecycleService _instance = AppLifecycleService._internal();
  factory AppLifecycleService() => _instance;
  AppLifecycleService._internal();

  // ✅ CHANGED: 3 seconds instead of 10
  static const String _lastPausedTimeKey = 'last_paused_time';
  static const int _pinLockDelaySeconds = 3; // 3 seconds delay

  DateTime? _lastPausedTime;
  bool _isInitialized = false;

  void initialize() {
    if (_isInitialized) return;
    WidgetsBinding.instance.addObserver(this);
    _isInitialized = true;
    debugPrint('✅ AppLifecycleService initialized');
  }

  void dispose() {
    if (_isInitialized) {
      WidgetsBinding.instance.removeObserver(this);
      _isInitialized = false;
      debugPrint('🗑️ AppLifecycleService disposed');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    debugPrint('📱 Lifecycle: $state');

    switch (state) {
      case AppLifecycleState.paused:
      // ✅ App went to background - save timestamp
        _lastPausedTime = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastPausedTimeKey, _lastPausedTime!.toIso8601String());
        debugPrint('🔒 Paused at: $_lastPausedTime');
        break;

      case AppLifecycleState.resumed:
      // ✅ App came back - check if we need PIN
        debugPrint('🔓 Resumed');
        break;

      case AppLifecycleState.inactive:
      // ✅ IGNORE inactive - happens during notification tray pull
        debugPrint('⏸️ Inactive (notification tray or transition)');
        break;

      default:
        break;
    }
  }

  Future<bool> shouldRequirePin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pausedTimeString = prefs.getString(_lastPausedTimeKey);

      if (pausedTimeString == null) {
        debugPrint('✅ No pause time - PIN not required');
        return false;
      }

      final pausedTime = DateTime.parse(pausedTimeString);
      final now = DateTime.now();
      final secondsAway = now.difference(pausedTime).inSeconds;

      debugPrint('⏱️ Away for $secondsAway seconds (threshold: $_pinLockDelaySeconds)');

      if (secondsAway >= _pinLockDelaySeconds) {
        debugPrint('🔐 PIN REQUIRED - Away for $secondsAway seconds');
        await prefs.remove(_lastPausedTimeKey);
        return true;
      } else {
        debugPrint('✅ PIN NOT required - Only $secondsAway seconds');
        await prefs.remove(_lastPausedTimeKey);
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error: $e');
      return false;
    }
  }

  Future<void> resetTimer() async {
    _lastPausedTime = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastPausedTimeKey);
    debugPrint('✅ Timer reset');
  }
}