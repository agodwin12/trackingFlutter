// lib/src/screens/debug/fcm_debug_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/utility/app_theme.dart';
import '../../services/notification_service.dart';
import '../dashboard/dashboard.dart';

class FCMDebugScreen extends StatefulWidget {
  final int vehicleId;
  final int userId;

  const FCMDebugScreen({
    Key? key,
    required this.vehicleId,
    required this.userId,
  }) : super(key: key);

  @override
  State<FCMDebugScreen> createState() => _FCMDebugScreenState();
}

class _FCMDebugScreenState extends State<FCMDebugScreen> {
  String? _fcmToken;
  String? _savedToken;
  String? _apnsToken;
  bool _isRegistered = false;
  bool _permissionGranted = false;
  int _countdown = 10; // 10 seconds countdown
  Timer? _countdownTimer;
  Map<String, dynamic> _debugInfo = {};

  @override
  void initState() {
    super.initState();
    _loadDebugInfo();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() {
          _countdown--;
        });
      } else {
        timer.cancel();
        _navigateToDashboard();
      }
    });
  }

  void _navigateToDashboard() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ModernDashboard(vehicleId: widget.vehicleId),
      ),
    );
  }

  Future<void> _loadDebugInfo() async {
    try {
      // Get FCM instance
      final messaging = FirebaseMessaging.instance;

      // Check notification permission
      final settings = await messaging.getNotificationSettings();
      _permissionGranted = settings.authorizationStatus == AuthorizationStatus.authorized;

      // Get current FCM token
      _fcmToken = await messaging.getToken();

      // Get APNS token (iOS only)
      _apnsToken = await messaging.getAPNSToken();

      // Get saved token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      _savedToken = prefs.getString('fcm_token');

      // Check if token was registered with backend
      final registeredToken = prefs.getString('registered_fcm_token');
      _isRegistered = registeredToken != null && registeredToken == _fcmToken;

      // Gather all debug info
      _debugInfo = {
        'User ID': widget.userId,
        'Vehicle ID': widget.vehicleId,
        'Permission Status': settings.authorizationStatus.toString(),
        'Permission Granted': _permissionGranted ? 'YES ✅' : 'NO ❌',
        'FCM Token Available': _fcmToken != null ? 'YES ✅' : 'NO ❌',
        'APNS Token (iOS)': _apnsToken ?? 'Not available',
        'Token Saved Locally': _savedToken != null ? 'YES ✅' : 'NO ❌',
        'Token Registered': _isRegistered ? 'YES ✅' : 'NO ❌',
        'Tokens Match': (_fcmToken != null && _savedToken != null && _fcmToken == _savedToken) ? 'YES ✅' : 'NO ❌',
      };

      setState(() {});

      debugPrint('\n========== FCM DEBUG INFO ==========');
      debugPrint('📱 Platform: ${Theme.of(context).platform}');
      debugPrint('👤 User ID: ${widget.userId}');
      debugPrint('🚗 Vehicle ID: ${widget.vehicleId}');
      debugPrint('🔔 Permission: ${settings.authorizationStatus}');
      debugPrint('✅ Permission Granted: $_permissionGranted');
      debugPrint('🔑 FCM Token: ${_fcmToken ?? "NULL"}');
      debugPrint('🍎 APNS Token: ${_apnsToken ?? "NULL"}');
      debugPrint('💾 Saved Token: ${_savedToken ?? "NULL"}');
      debugPrint('📡 Registered: $_isRegistered');
      debugPrint('====================================\n');

    } catch (e) {
      debugPrint('❌ Error loading debug info: $e');
      setState(() {
        _debugInfo['Error'] = e.toString();
      });
    }
  }

  void _copyToken() {
    if (_fcmToken != null) {
      Clipboard.setData(ClipboardData(text: _fcmToken!));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Token copied to clipboard'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: Text(
          'FCM Debug Info',
          style: AppTypography.h3.copyWith(color: AppColors.black),
        ),
        actions: [
          // Countdown timer
          Center(
            child: Container(
              margin: EdgeInsets.only(right: AppSizes.spacingM),
              padding: EdgeInsets.symmetric(
                horizontal: AppSizes.spacingM,
                vertical: AppSizes.spacingS,
              ),
              decoration: BoxDecoration(
                color: AppColors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
              child: Text(
                '$_countdown s',
                style: AppTypography.body1.copyWith(
                  color: AppColors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(AppSizes.spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            _buildStatusCard(),

            SizedBox(height: AppSizes.spacingL),

            // Debug Info Cards
            _buildDebugInfoCards(),

            SizedBox(height: AppSizes.spacingL),

            // Token Display
            if (_fcmToken != null) _buildTokenCard(),

            SizedBox(height: AppSizes.spacingL),

            // Action Buttons
            _buildActionButtons(),

            SizedBox(height: AppSizes.spacingL),

            // Auto-redirect info
            _buildAutoRedirectInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final isHealthy = _permissionGranted && _fcmToken != null && _isRegistered;

    return Container(
      padding: EdgeInsets.all(AppSizes.spacingL),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isHealthy
              ? [AppColors.success, AppColors.success.withOpacity(0.8)]
              : [AppColors.error, AppColors.error.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(AppSizes.spacingM),
            decoration: BoxDecoration(
              color: AppColors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isHealthy ? Icons.check_circle : Icons.warning_rounded,
              color: AppColors.white,
              size: 32,
            ),
          ),
          SizedBox(width: AppSizes.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHealthy ? 'All Systems Ready' : 'Issues Detected',
                  style: AppTypography.h3.copyWith(
                    color: AppColors.white,
                  ),
                ),
                SizedBox(height: AppSizes.spacingXS),
                Text(
                  isHealthy
                      ? 'Notifications are configured correctly'
                      : 'Some notification features may not work',
                  style: AppTypography.body2.copyWith(
                    color: AppColors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugInfoCards() {
    return Column(
      children: _debugInfo.entries.map((entry) {
        return Container(
          margin: EdgeInsets.only(bottom: AppSizes.spacingM),
          padding: EdgeInsets.all(AppSizes.spacingM),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  entry.key,
                  style: AppTypography.body2.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  entry.value.toString(),
                  style: AppTypography.body2.copyWith(
                    color: AppColors.black,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTokenCard() {
    return Container(
      padding: EdgeInsets.all(AppSizes.spacingM),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'FCM Token',
                style: AppTypography.body1.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                onPressed: _copyToken,
                icon: Icon(Icons.copy_rounded),
                color: AppColors.primary,
                iconSize: 20,
              ),
            ],
          ),
          SizedBox(height: AppSizes.spacingS),
          Container(
            padding: EdgeInsets.all(AppSizes.spacingM),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppSizes.radiusS),
            ),
            child: Text(
              _fcmToken!,
              style: AppTypography.caption.copyWith(
                fontFamily: 'monospace',
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Skip countdown button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _navigateToDashboard,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
            ),
            child: Text(
              'Skip & Go to Dashboard',
              style: AppTypography.button.copyWith(color: AppColors.black),
            ),
          ),
        ),
        SizedBox(height: AppSizes.spacingM),
        // Retry registration button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: () async {
              await NotificationService.registerToken();
              await _loadDebugInfo();
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
            ),
            child: Text(
              'Retry Token Registration',
              style: AppTypography.button.copyWith(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAutoRedirectInfo() {
    return Container(
      padding: EdgeInsets.all(AppSizes.spacingM),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          SizedBox(width: AppSizes.spacingM),
          Expanded(
            child: Text(
              'Auto-redirecting to dashboard in $_countdown seconds...',
              style: AppTypography.body2.copyWith(
                color: AppColors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}