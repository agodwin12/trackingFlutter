import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isOnline = true;
  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;

  // Initialize the service
  Future<void> initialize() async {
    // Check initial connectivity
    await checkConnectivity();

    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
          (List<ConnectivityResult> results) {
        _updateConnectionStatus(results);
      },
    );
  }

  // Check current connectivity status
  Future<void> checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectionStatus(results);
    } catch (e) {
      print('Error checking connectivity: $e');
      _isOnline = false;
      notifyListeners();
    }
  }

  // Update connection status based on connectivity results
  void _updateConnectionStatus(List<ConnectivityResult> results) {
    bool wasOnline = _isOnline;

    // Check if any result indicates connectivity
    _isOnline = results.any((result) =>
    result == ConnectivityResult.mobile ||
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.ethernet);

    // Notify listeners only if status changed
    if (wasOnline != _isOnline) {
      print('Connectivity changed: ${_isOnline ? "ONLINE" : "OFFLINE"}');
      notifyListeners();
    }
  }

  // Clean up
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // Get connectivity status as string
  String get statusText => _isOnline ? 'Online' : 'Offline';
}