// lib/src/screens/debug/fcm_debug_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io' show Platform;

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
  String? _pendingToken;
  bool _isRegistered = false;
  bool _permissionGranted = false;
  int _countdown = 15; // 15 seconds countdown
  Timer? _countdownTimer;
  Map<String, dynamic> _debugInfo = {};
  List<String> _setupSteps = [];

  @override
  void initState() {
    super.initState();
    _initializeDebug();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeDebug() async {
    debugPrint('\n🐛 ========================================');
    debugPrint('🐛 FCM DEBUG SCREEN INITIALIZATION');
    debugPrint('🐛 ========================================');

    await _loadDebugInfo();
    _startCountdown();
  }

  void _startCountdown() {
    debugPrint('⏱️ Starting ${_countdown}s countdown to dashboard...');
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() {
          _countdown--;
        });
      } else {
        timer.cancel();
        debugPrint('⏱️ Countdown finished - navigating to dashboard');
        _navigateToDashboard();
      }
    });
  }

  void _navigateToDashboard() {
    debugPrint('🚗 Navigating to dashboard with vehicleId: ${widget.vehicleId}');
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ModernDashboard(vehicleId: widget.vehicleId),
      ),
    );
  }

  Future<void> _loadDebugInfo() async {
    try {
      _setupSteps.clear();

      debugPrint('\n📋 STEP 1: Getting Firebase Messaging instance...');
      final messaging = FirebaseMessaging.instance;
      _addStep('✅ Firebase Messaging instance obtained');

      debugPrint('📋 STEP 2: Checking notification permission...');
      final settings = await messaging.getNotificationSettings();
      _permissionGranted = settings.authorizationStatus == AuthorizationStatus.authorized;
      debugPrint('📋 Permission status: ${settings.authorizationStatus}');
      debugPrint('📋 Permission granted: $_permissionGranted');
      _addStep(_permissionGranted
          ? '✅ Notification permission GRANTED'
          : '❌ Notification permission DENIED');

      debugPrint('\n📋 STEP 3: Fetching current FCM token...');
      _fcmToken = await messaging.getToken();
      debugPrint('📋 FCM Token: ${_fcmToken ?? "NULL"}');
      if (_fcmToken != null) {
        debugPrint('📋 Token length: ${_fcmToken!.length} characters');
        debugPrint('📋 Token preview: ${_fcmToken!.substring(0, _fcmToken!.length > 30 ? 30 : _fcmToken!.length)}...');
        _addStep('✅ FCM token received (${_fcmToken!.length} chars)');
      } else {
        _addStep('❌ FCM token is NULL');
      }

      if (Platform.isIOS) {
        debugPrint('\n📋 STEP 4: Fetching APNs token (iOS only)...');
        _apnsToken = await messaging.getAPNSToken();
        debugPrint('📋 APNs Token: ${_apnsToken ?? "NULL"}');
        if (_apnsToken != null) {
          debugPrint('📋 APNs token length: ${_apnsToken!.length} characters');
          _addStep('✅ APNs token received (${_apnsToken!.length} chars)');
        } else {
          _addStep('⚠️ APNs token is NULL (may still be loading)');
        }
      }

      debugPrint('\n📋 STEP 5: Reading saved tokens from SharedPreferences...');
      final prefs = await SharedPreferences.getInstance();

      _savedToken = prefs.getString('fcm_token');
      debugPrint('📋 Saved FCM token: ${_savedToken ?? "NULL"}');
      _addStep(_savedToken != null
          ? '✅ Token saved locally'
          : '⚠️ No token saved locally yet');

      _pendingToken = prefs.getString('pending_fcm_token');
      debugPrint('📋 Pending FCM token: ${_pendingToken ?? "NULL"}');
      if (_pendingToken != null) {
        _addStep('⏳ Pending token waiting to be sent to backend');
      }

      final registeredToken = prefs.getString('registered_fcm_token');
      debugPrint('📋 Registered FCM token: ${registeredToken ?? "NULL"}');
      _isRegistered = registeredToken != null && registeredToken == _fcmToken;
      debugPrint('📋 Token is registered: $_isRegistered');
      _addStep(_isRegistered
          ? '✅ Token registered with backend'
          : '⚠️ Token NOT registered with backend yet');

      debugPrint('\n📋 STEP 6: Compiling debug information...');
      _debugInfo = {
        '👤 User ID': widget.userId.toString(),
        '🚗 Vehicle ID': widget.vehicleId.toString(),
        '📱 Platform': Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : 'Unknown'),
        '🔔 Permission Status': settings.authorizationStatus.toString().split('.').last,
        '✅ Permission Granted': _permissionGranted ? 'YES ✅' : 'NO ❌',
        '🔑 FCM Token Available': _fcmToken != null ? 'YES ✅' : 'NO ❌',
      };

      if (Platform.isIOS) {
        _debugInfo['🍎 APNs Token (iOS)'] = _apnsToken != null ? 'Available ✅' : 'Not available ❌';
      }

      _debugInfo.addAll({
        '💾 Token Saved Locally': _savedToken != null ? 'YES ✅' : 'NO ❌',
        '⏳ Pending Token': _pendingToken != null ? 'YES ⚠️' : 'NO ✅',
        '📡 Token Registered': _isRegistered ? 'YES ✅' : 'NO ❌',
        '🔄 Tokens Match': (_fcmToken != null && _savedToken != null && _fcmToken == _savedToken) ? 'YES ✅' : 'NO ❌',
      });

      setState(() {});

      debugPrint('\n✅ ========================================');
      debugPrint('✅ DEBUG INFO LOADED SUCCESSFULLY');
      debugPrint('✅ ========================================');
      _debugInfo.forEach((key, value) {
        debugPrint('$key: $value');
      });
      debugPrint('✅ ========================================\n');

    } catch (e, stackTrace) {
      debugPrint('❌ ========================================');
      debugPrint('❌ ERROR LOADING DEBUG INFO');
      debugPrint('❌ ========================================');
      debugPrint('❌ Error: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      debugPrint('❌ ========================================\n');

      setState(() {
        _debugInfo['❌ Error'] = e.toString();
        _addStep('❌ Error occurred: ${e.toString()}');
      });
    }
  }

  void _addStep(String step) {
    setState(() {
      _setupSteps.add(step);
    });
    debugPrint('📝 Setup step: $step');
  }

  void _copyToken() {
    if (_fcmToken != null) {
      Clipboard.setData(ClipboardData(text: _fcmToken!));
      debugPrint('📋 Token copied to clipboard: ${_fcmToken!.substring(0, 20)}...');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Token copied to clipboard'),
            ],
          ),
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
            _buildStatusCard(),
            SizedBox(height: AppSizes.spacingL),

            _buildSetupStepsCard(),
            SizedBox(height: AppSizes.spacingL),

            _buildDebugInfoCards(),
            SizedBox(height: AppSizes.spacingL),

            if (_fcmToken != null) _buildTokenCard(),
            if (_fcmToken != null) SizedBox(height: AppSizes.spacingL),

            if (_apnsToken != null && Platform.isIOS) _buildApnsTokenCard(),
            if (_apnsToken != null && Platform.isIOS) SizedBox(height: AppSizes.spacingL),

            _buildActionButtons(),
            SizedBox(height: AppSizes.spacingL),

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
        boxShadow: [
          BoxShadow(
            color: (isHealthy ? AppColors.success : AppColors.error).withOpacity(0.3),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
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
                      ? 'Notifications configured correctly'
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

  Widget _buildSetupStepsCard() {
    if (_setupSteps.isEmpty) {
      return SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.all(AppSizes.spacingL),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.list_alt_rounded, color: AppColors.primary),
              SizedBox(width: AppSizes.spacingS),
              Text(
                'Setup Steps',
                style: AppTypography.h3,
              ),
            ],
          ),
          SizedBox(height: AppSizes.spacingM),
          Divider(height: 1, color: AppColors.border),
          SizedBox(height: AppSizes.spacingM),
          ..._setupSteps.map((step) => Padding(
            padding: EdgeInsets.only(bottom: AppSizes.spacingS),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '•',
                  style: AppTypography.body1.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: AppSizes.spacingS),
                Expanded(
                  child: Text(
                    step,
                    style: AppTypography.body2,
                  ),
                ),
              ],
            ),
          )).toList(),
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
      padding: EdgeInsets.all(AppSizes.spacingL),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.key, color: AppColors.primary, size: 20),
                  SizedBox(width: AppSizes.spacingS),
                  Text(
                    'FCM Token',
                    style: AppTypography.h3,
                  ),
                ],
              ),
              IconButton(
                onPressed: _copyToken,
                icon: Icon(Icons.copy_rounded),
                color: AppColors.primary,
                iconSize: 20,
              ),
            ],
          ),
          SizedBox(height: AppSizes.spacingM),
          Container(
            padding: EdgeInsets.all(AppSizes.spacingM),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppSizes.radiusS),
            ),
            child: SelectableText(
              _fcmToken!,
              style: AppTypography.caption.copyWith(
                fontFamily: 'monospace',
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
          SizedBox(height: AppSizes.spacingS),
          Text(
            'Length: ${_fcmToken!.length} characters',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApnsTokenCard() {
    return Container(
      padding: EdgeInsets.all(AppSizes.spacingL),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.apple, color: AppColors.success, size: 20),
              SizedBox(width: AppSizes.spacingS),
              Text(
                'APNs Token (iOS)',
                style: AppTypography.h3,
              ),
            ],
          ),
          SizedBox(height: AppSizes.spacingM),
          Container(
            padding: EdgeInsets.all(AppSizes.spacingM),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppSizes.radiusS),
            ),
            child: SelectableText(
              _apnsToken!,
              style: AppTypography.caption.copyWith(
                fontFamily: 'monospace',
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
          SizedBox(height: AppSizes.spacingS),
          Text(
            'Length: ${_apnsToken!.length} characters',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _navigateToDashboard,
            icon: Icon(Icons.dashboard, color: AppColors.black),
            label: Text(
              'Skip & Go to Dashboard',
              style: AppTypography.button.copyWith(color: AppColors.black),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
            ),
          ),
        ),
        SizedBox(height: AppSizes.spacingM),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () async {
              debugPrint('🔄 Retrying token registration...');
              await NotificationService.registerToken();
              await _loadDebugInfo();
              debugPrint('✅ Token registration retry complete');
            },
            icon: Icon(Icons.refresh, color: AppColors.primary),
            label: Text(
              'Retry Token Registration',
              style: AppTypography.button.copyWith(color: AppColors.primary),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
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