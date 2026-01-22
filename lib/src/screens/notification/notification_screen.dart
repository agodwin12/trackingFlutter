// lib/screens/notifications_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticky_headers/sticky_headers.dart';
import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';
import '../../services/socket_service.dart';
import '../../services/token_refresh_service.dart';
import 'widgets/notifications_skeleton.dart';

enum NotificationType {
  safeZone,
  geofence,
}

class AppNotification {
  final int id;
  final NotificationType type;
  final String title;
  final String vehicleNickname;
  final String zone;
  final DateTime time; // ✅ Already converted to local time
  final bool isRead;
  final String message;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.vehicleNickname,
    required this.zone,
    required this.time,
    required this.isRead,
    required this.message,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final String alertType = (json['alert_type'] ?? '').toLowerCase();
    final String message = json['message'] ?? '';

    NotificationType type;
    String title = 'Alert';

    if (alertType.contains('safe') || message.toLowerCase().contains('safe zone')) {
      type = NotificationType.safeZone;
      if (message.contains('left') || message.contains('outside')) {
        title = 'Safe Zone Alert';
      } else if (message.contains('returned') || message.contains('inside')) {
        title = 'Safe Zone Return';
      } else {
        title = 'Safe Zone Alert';
      }
    } else {
      type = NotificationType.geofence;
      if (message.contains('entered')) {
        title = 'Geofence Entry';
      } else if (message.contains('exited')) {
        title = 'Geofence Exit';
      } else {
        title = 'Geofence Alert';
      }
    }

    String vehicleNickname = 'Vehicle';
    final vehicleMatch = RegExp(r'Vehicle\s+([A-Za-z0-9\s]+)\s+(left|returned|entered|exited|moved)').firstMatch(message);
    if (vehicleMatch != null) {
      vehicleNickname = vehicleMatch.group(1)?.trim() ?? vehicleNickname;
    }

    String zone = 'Unknown Zone';
    final zoneMatch = RegExp(r'zone\s+"([^"]+)"').firstMatch(message);
    if (zoneMatch != null) {
      zone = zoneMatch.group(1) ?? zone;
    }

    // ✅ FIXED: Parse UTC time and convert to local time
    String alertedAtStr = json['alerted_at'] ?? DateTime.now().toIso8601String();
    DateTime utcTime = DateTime.parse(alertedAtStr);
    DateTime localTime = utcTime.toLocal(); // ← CONVERT TO LOCAL TIME

    debugPrint('🕐 Time conversion: UTC=$utcTime → Local=$localTime');

    return AppNotification(
      id: json['id'] ?? 0,
      type: type,
      vehicleNickname: vehicleNickname,
      zone: zone,
      time: localTime, // ← USE LOCAL TIME
      isRead: json['read'] == true || json['read'] == 1,
      message: message,
      title: title,
    );
  }
}

class NotificationScreen extends StatefulWidget {
  final int vehicleId;

  const NotificationScreen({Key? key, required this.vehicleId}) : super(key: key);

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _expandedNotificationId;
  bool _showPushNotification = false;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isLoadingMore = false;
  String _selectedLanguage = 'en';

  List<AppNotification> _allNotifications = [];
  Set<int> _readNotifications = {};

  int _currentPage = 1;
  final int _pageSize = 20;
  bool _hasMoreData = true;
  int _totalNotifications = 0;

  AppNotification? _latestAlert;

  final SocketService _socketService = SocketService();
  final TokenRefreshService _tokenService = TokenRefreshService();
  StreamSubscription<Map<String, dynamic>>? _alertSubscription;

  String get baseUrl => EnvConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    debugPrint('🔔 ========== NOTIFICATIONS SCREEN INITIALIZED ==========');
    debugPrint('🚗 Vehicle ID: ${widget.vehicleId}');
    debugPrint('🌍 Local timezone: ${DateTime.now().timeZoneName}');
    debugPrint('🕐 Local time offset: ${DateTime.now().timeZoneOffset}');

    _loadLanguagePreference();
    _tabController = TabController(length: 3, vsync: this);
    _fetchNotifications();
    _connectSocketForAlerts();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
    debugPrint('✅ Language loaded: $_selectedLanguage');
  }

  @override
  void dispose() {
    debugPrint('🔔 Notifications screen disposed');
    _tabController.dispose();
    _alertSubscription?.cancel();
    super.dispose();
  }

  void _connectSocketForAlerts() {
    debugPrint('🔌 Connecting socket for real-time alerts...');
    try {
      _socketService.connect(EnvConfig.socketUrl);
      _socketService.joinVehicleTracking(widget.vehicleId);

      _alertSubscription = _socketService.safeZoneAlertStream.listen((alertData) {
        debugPrint('🚨 Real-time alert received: $alertData');
        if (mounted) {
          _showRealtimePushNotification(alertData);
          _handleRefresh();
        }
      });

      debugPrint('✅ Socket connected successfully');
    } catch (e) {
      debugPrint('❌ Socket connection error: $e');
    }
  }

  void _showRealtimePushNotification(Map<String, dynamic> alertData) {
    final title = alertData['title'] ?? (_selectedLanguage == 'en' ? 'Alert' : 'Alerte');
    final message = alertData['message'] ?? '';
    final vehicleName = alertData['nickname'] ?? (_selectedLanguage == 'en' ? 'Vehicle' : 'Véhicule');
    final zoneName = alertData['safeZoneName'] ?? (_selectedLanguage == 'en' ? 'Unknown Zone' : 'Zone inconnue');

    debugPrint('📢 Showing push notification banner');

    // ✅ Use local time for real-time notifications
    setState(() {
      _latestAlert = AppNotification(
        id: alertData['alertId'] ?? 0,
        type: NotificationType.safeZone,
        title: title,
        vehicleNickname: vehicleName,
        zone: zoneName,
        time: DateTime.now(), // ← Already local time
        isRead: false,
        message: message,
      );
      _showPushNotification = true;
    });

    Future.delayed(Duration(seconds: 8), () {
      if (mounted && _showPushNotification) {
        debugPrint('⏱️ Auto-dismissing push notification banner');
        setState(() {
          _showPushNotification = false;
        });
      }
    });
  }

  Future<void> _fetchNotifications({bool loadMore = false}) async {
    if (loadMore && !_hasMoreData) {
      debugPrint('⚠️ No more data to load');
      return;
    }
    if (loadMore && _isLoadingMore) {
      debugPrint('⚠️ Already loading more data');
      return;
    }

    debugPrint('\n📡 ========== FETCHING NOTIFICATIONS ==========');
    debugPrint('📄 Page: $_currentPage');
    debugPrint('📊 Page Size: $_pageSize');
    debugPrint('🔄 Load More: $loadMore');

    if (loadMore) {
      setState(() => _isLoadingMore = true);
    } else {
      if (!_isRefreshing) {
        setState(() => _isLoading = true);
      }
      _currentPage = 1;
      _allNotifications.clear();
    }

    try {
      debugPrint('🔐 Making authenticated request...');

      final response = await _tokenService.makeAuthenticatedRequest(
        request: (token) async {
          return await http.get(
            Uri.parse('$baseUrl/alerts/vehicle/${widget.vehicleId}?page=$_currentPage&limit=$_pageSize'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );
        },
      );

      debugPrint('📬 Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        debugPrint('✅ Success - parsing response...');
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final List<dynamic> alertsJson = data['data']['alerts'] ?? [];
          final pagination = data['data']['pagination'];

          debugPrint('📦 Received ${alertsJson.length} notifications');

          if (mounted) {
            setState(() {
              final newNotifications = alertsJson
                  .map((json) => AppNotification.fromJson(json))
                  .toList();

              if (loadMore) {
                _allNotifications.addAll(newNotifications);
              } else {
                _allNotifications = newNotifications;
              }

              _readNotifications = _allNotifications
                  .where((n) => n.isRead)
                  .map((n) => n.id)
                  .toSet();

              _totalNotifications = pagination['totalAlerts'] ?? 0;
              _hasMoreData = pagination['hasNextPage'] ?? false;

              _isLoading = false;
              _isRefreshing = false;
              _isLoadingMore = false;
            });
          }

          debugPrint('✅ Notifications loaded successfully\n');
        }
      } else if (response.statusCode == 401) {
        if (mounted) {
          _showSessionExpiredDialog();
        }
      } else {
        if (mounted) {
          _showErrorSnackBar(
              _selectedLanguage == 'en'
                  ? 'Failed to load notifications'
                  : 'Échec du chargement des notifications'
          );
        }
      }
    } catch (error) {
      debugPrint('🔥 Error fetching notifications: $error');
      if (mounted) {
        _showErrorSnackBar(
            _selectedLanguage == 'en'
                ? 'Network error - check your connection'
                : 'Erreur réseau - vérifiez votre connexion'
        );
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _isLoadingMore = false;
      });
    }
  }

  void _showSessionExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
        ),
        title: Row(
          children: [
            Icon(Icons.lock_clock_rounded, color: AppColors.error, size: 28),
            SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Text(
                _selectedLanguage == 'en' ? 'Session Expired' : 'Session expirée',
                style: AppTypography.h3.copyWith(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          _selectedLanguage == 'en'
              ? 'Your session has expired. Please login again to continue.'
              : 'Votre session a expiré. Veuillez vous reconnecter pour continuer.',
          style: AppTypography.body2,
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: EdgeInsets.symmetric(
                horizontal: AppSizes.spacingL,
                vertical: AppSizes.spacingM,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
            ),
            child: Text(
              _selectedLanguage == 'en' ? 'Login Again' : 'Se reconnecter',
              style: AppTypography.button.copyWith(color: AppColors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Expanded(child: Text(message, style: TextStyle(color: Colors.white))),
          ],
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
      ),
    );
  }

  void _loadMoreNotifications() {
    if (!_hasMoreData || _isLoadingMore) return;
    _currentPage++;
    _fetchNotifications(loadMore: true);
  }

  Future<void> _handleRefresh() async {
    setState(() => _isRefreshing = true);
    await _fetchNotifications();
  }

  void _dismissPushNotification() {
    setState(() => _showPushNotification = false);
  }

  void _navigateToDashboard() {
    Navigator.pushReplacementNamed(context, '/dashboard', arguments: widget.vehicleId);
  }

  void _handleEngineAction() {
    _dismissPushNotification();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusL)),
        contentPadding: EdgeInsets.all(AppSizes.spacingL),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_rounded, color: AppColors.error, size: 20),
            ),
            SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Text(
                _selectedLanguage == 'en' ? 'Cut Engine' : 'Couper le moteur',
                style: AppTypography.subtitle1.copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          _selectedLanguage == 'en'
              ? 'Are you sure you want to remotely cut off ${_latestAlert?.vehicleNickname ?? "the vehicle"}\'s engine?'
              : 'Êtes-vous sûr de vouloir couper à distance le moteur de ${_latestAlert?.vehicleNickname ?? "le véhicule"} ?',
          style: AppTypography.body2.copyWith(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _selectedLanguage == 'en' ? 'Cancel' : 'Annuler',
              style: AppTypography.body2.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final response = await _tokenService.makeAuthenticatedRequest(
                  request: (token) async {
                    return await http.post(
                      Uri.parse('$baseUrl/gps/issue-command'),
                      headers: {
                        'Content-Type': 'application/json',
                        'Authorization': 'Bearer $token',
                      },
                      body: jsonEncode({
                        'vehicleId': widget.vehicleId,
                        'command': 'CLOSERELAY',
                        'params': '',
                        'password': '',
                        'sendTime': '',
                      }),
                    );
                  },
                );

                if (response.statusCode == 200 && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_selectedLanguage == 'en' ? 'Engine cut off successfully' : 'Moteur coupé avec succès'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } else {
                  throw Exception('Failed');
                }
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_selectedLanguage == 'en' ? 'Failed to cut engine' : 'Échec'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusM)),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              _selectedLanguage == 'en' ? 'Cut Engine' : 'Couper le moteur',
              style: AppTypography.body2.copyWith(color: AppColors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  List<AppNotification> get _unreadNotifications => _allNotifications.where((n) => !_readNotifications.contains(n.id)).toList();
  List<AppNotification> get _safeZoneNotifications => _allNotifications.where((n) => n.type == NotificationType.safeZone).toList();
  List<AppNotification> get _geofenceNotifications => _allNotifications.where((n) => n.type == NotificationType.geofence).toList();

  Future<void> _markAsRead(int notificationId) async {
    try {
      final response = await _tokenService.makeAuthenticatedRequest(
        request: (token) async {
          return await http.patch(
            Uri.parse('$baseUrl/alerts/$notificationId/read'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          );
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _readNotifications.add(notificationId);
          _expandedNotificationId = null;
        });
      }
    } catch (error) {
      debugPrint('Error marking as read: $error');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final response = await _tokenService.makeAuthenticatedRequest(
        request: (token) async {
          return await http.patch(
            Uri.parse('$baseUrl/alerts/vehicle/${widget.vehicleId}/read-all'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          );
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          for (var notification in _allNotifications) {
            _readNotifications.add(notification.id);
          }
          _expandedNotificationId = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_selectedLanguage == 'en' ? 'All notifications marked as read' : 'Toutes marquées comme lues'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } catch (error) {
      debugPrint('Error marking all as read: $error');
    }
  }

  // ✅ FIXED: Use local time for date grouping
  Map<String, List<AppNotification>> _groupNotificationsByDate(List<AppNotification> notifications) {
    final Map<String, List<AppNotification>> grouped = {
      'Today': [],
      'Yesterday': [],
      'This Week': [],
      'This Month': [],
      'Older': [],
    };

    final now = DateTime.now(); // ← Local time
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(Duration(days: 1));
    final thisWeekStart = today.subtract(Duration(days: now.weekday - 1));
    final thisMonthStart = DateTime(now.year, now.month, 1);

    for (var notification in notifications) {
      // notification.time is already in local time
      final notificationDate = DateTime(
        notification.time.year,
        notification.time.month,
        notification.time.day,
      );

      if (notificationDate.isAtSameMomentAs(today)) {
        grouped['Today']!.add(notification);
      } else if (notificationDate.isAtSameMomentAs(yesterday)) {
        grouped['Yesterday']!.add(notification);
      } else if (notificationDate.isAfter(thisWeekStart) || notificationDate.isAtSameMomentAs(thisWeekStart)) {
        grouped['This Week']!.add(notification);
      } else if (notificationDate.isAfter(thisMonthStart) || notificationDate.isAtSameMomentAs(thisMonthStart)) {
        grouped['This Month']!.add(notification);
      } else {
        grouped['Older']!.add(notification);
      }
    }

    grouped.removeWhere((key, value) => value.isEmpty);
    return grouped;
  }

  // ✅ FIXED: Format local time correctly
  String _formatDetailedTime(DateTime localTime) {
    final hour = localTime.hour > 12 ? localTime.hour - 12 : (localTime.hour == 0 ? 12 : localTime.hour);
    final minute = localTime.minute.toString().padLeft(2, '0');
    final period = localTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  IconData _getNotificationIcon(NotificationType type) {
    switch (type) {
      case NotificationType.safeZone:
        return Icons.shield_rounded;
      case NotificationType.geofence:
        return Icons.location_on_rounded;
    }
  }

  Color _getNotificationColor(NotificationType type) {
    switch (type) {
      case NotificationType.safeZone:
        return Color(0xFF3B82F6);
      case NotificationType.geofence:
        return Color(0xFF8B5CF6);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const NotificationsSkeleton();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Header
                Container(
                  color: AppColors.white,
                  padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingL, vertical: AppSizes.spacingM),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.arrow_back_rounded, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),
                      SizedBox(width: AppSizes.spacingM),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedLanguage == 'en' ? 'Notifications' : 'Notifications',
                              style: AppTypography.h3.copyWith(fontSize: 18),
                            ),
                            if (_unreadNotifications.isNotEmpty)
                              Text(
                                _selectedLanguage == 'en'
                                    ? '${_unreadNotifications.length} unread'
                                    : '${_unreadNotifications.length} non lue${_unreadNotifications.length > 1 ? 's' : ''}',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.error,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_unreadNotifications.isNotEmpty)
                        IconButton(
                          onPressed: _markAllAsRead,
                          icon: Icon(Icons.done_all_rounded, size: 20),
                          color: AppColors.primary,
                        ),
                      IconButton(
                        onPressed: _handleRefresh,
                        icon: Icon(Icons.refresh_rounded, size: 20),
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),

                // Tabs
                Container(
                  color: AppColors.white,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondary,
                    labelStyle: AppTypography.body1.copyWith(fontWeight: FontWeight.w600, fontSize: 12),
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 2,
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_selectedLanguage == 'en' ? 'All' : 'Tout'),
                            if (_unreadNotifications.isNotEmpty) ...[
                              SizedBox(width: 4),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.error,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_unreadNotifications.length}',
                                  style: TextStyle(color: AppColors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield_rounded, size: 14),
                            SizedBox(width: 4),
                            Flexible(child: Text(_selectedLanguage == 'en' ? 'Safe' : 'Sûr', overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_on_rounded, size: 14),
                            SizedBox(width: 4),
                            Flexible(child: Text(_selectedLanguage == 'en' ? 'Geo' : 'Géo', overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Tab Views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildStickyNotificationsList(_allNotifications),
                      _buildStickyNotificationsList(_safeZoneNotifications),
                      _buildStickyNotificationsList(_geofenceNotifications),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Push Notification Banner
          if (_showPushNotification && _latestAlert != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: AnimatedSlide(
                  duration: Duration(milliseconds: 400),
                  curve: Curves.easeOutBack,
                  offset: _showPushNotification ? Offset.zero : Offset(0, -1),
                  child: _buildPushNotificationBanner(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPushNotificationBanner() {
    if (_latestAlert == null) return SizedBox.shrink();

    return GestureDetector(
      onTap: _navigateToDashboard,
      child: Container(
        margin: EdgeInsets.all(AppSizes.spacingM),
        padding: EdgeInsets.all(AppSizes.spacingM),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [AppColors.error, AppColors.error.withOpacity(0.8)]),
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
          boxShadow: [BoxShadow(color: AppColors.error.withOpacity(0.4), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.shield_rounded, color: AppColors.white, size: 20),
                SizedBox(width: AppSizes.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _latestAlert!.title,
                        style: AppTypography.body1.copyWith(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        '${_latestAlert!.vehicleNickname} - ${_latestAlert!.zone}',
                        style: AppTypography.caption.copyWith(color: AppColors.white.withOpacity(0.9), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _dismissPushNotification,
                  icon: Icon(Icons.close, color: AppColors.white, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              ],
            ),
            SizedBox(height: AppSizes.spacingM),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      _dismissPushNotification();
                      _handleEngineAction();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.white,
                      padding: EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusM)),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_rounded, color: AppColors.error, size: 16),
                        SizedBox(width: 6),
                        Text(
                          _selectedLanguage == 'en' ? 'Cut Engine' : 'Couper moteur',
                          style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: AppSizes.spacingS),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _navigateToDashboard,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.white),
                      padding: EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusM)),
                    ),
                    child: Text(
                      _selectedLanguage == 'en' ? 'View Location' : 'Voir position',
                      style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickyNotificationsList(List<AppNotification> notifications) {
    if (notifications.isEmpty) {
      return RefreshIndicator(
        onRefresh: _handleRefresh,
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 64, color: AppColors.textSecondary.withOpacity(0.5)),
                  SizedBox(height: AppSizes.spacingL),
                  Text(
                    _selectedLanguage == 'en' ? 'No notifications' : 'Aucune notification',
                    style: AppTypography.h3.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final groupedNotifications = _groupNotificationsByDate(notifications);

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: AppColors.primary,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: groupedNotifications.length + (_hasMoreData ? 1 : 0),
        itemBuilder: (context, index) {
          // Load more button
          if (index == groupedNotifications.length) {
            if (_isLoadingMore) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSizes.spacingL),
                  child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                ),
              );
            }

            return Center(
              child: Padding(
                padding: EdgeInsets.all(AppSizes.spacingL),
                child: ElevatedButton.icon(
                  onPressed: _loadMoreNotifications,
                  icon: Icon(Icons.expand_more_rounded, size: 20),
                  label: Text(
                    _selectedLanguage == 'en' ? 'Load More' : 'Charger plus',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.black,
                    padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingL, vertical: AppSizes.spacingM),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusM)),
                    elevation: 0,
                  ),
                ),
              ),
            );
          }

          final groupKey = groupedNotifications.keys.elementAt(index);
          final groupNotifications = groupedNotifications[groupKey]!;

          return StickyHeader(
            header: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingL, vertical: AppSizes.spacingS),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              child: Text(
                _selectedLanguage == 'en' ? groupKey : _translateGroupKey(groupKey),
                style: AppTypography.body1.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            content: Column(
              children: groupNotifications.map((notification) {
                final isRead = _readNotifications.contains(notification.id);
                final isExpanded = _expandedNotificationId == notification.id.toString();
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingM, vertical: AppSizes.spacingS),
                  child: _buildNotificationCard(notification, isRead, isExpanded),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  String _translateGroupKey(String key) {
    switch (key) {
      case 'Today':
        return 'Aujourd\'hui';
      case 'Yesterday':
        return 'Hier';
      case 'This Week':
        return 'Cette semaine';
      case 'This Month':
        return 'Ce mois';
      case 'Older':
        return 'Plus ancien';
      default:
        return key;
    }
  }

  Widget _buildNotificationCard(AppNotification notification, bool isRead, bool isExpanded) {
    final color = _getNotificationColor(notification.type);
    final icon = _getNotificationIcon(notification.type);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        border: Border.all(color: isRead ? AppColors.border : AppColors.error, width: isRead ? 1 : 2),
        boxShadow: [
          BoxShadow(
            color: isRead ? AppColors.black.withOpacity(0.05) : AppColors.error.withOpacity(0.15),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: _navigateToDashboard,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(AppSizes.radiusL),
              topRight: Radius.circular(AppSizes.radiusL),
              bottomLeft: isExpanded ? Radius.zero : Radius.circular(AppSizes.radiusL),
              bottomRight: isExpanded ? Radius.zero : Radius.circular(AppSizes.radiusL),
            ),
            child: Padding(
              padding: EdgeInsets.all(AppSizes.spacingM),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  SizedBox(width: AppSizes.spacingM),

                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title,
                          style: AppTypography.body1.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        SizedBox(height: 4),
                        Text(
                          notification.message,
                          style: AppTypography.body2.copyWith(color: AppColors.textSecondary, fontSize: 12),
                          maxLines: isExpanded ? null : 2,
                          overflow: isExpanded ? null : TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 6),
                        Text(
                          _formatDetailedTime(notification.time), // ← Uses local time
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary.withOpacity(0.7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(width: AppSizes.spacingS),

                  // Expand button
                  InkWell(
                    onTap: () {
                      setState(() {
                        _expandedNotificationId = isExpanded ? null : notification.id.toString();
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                  ),

                  // Unread indicator
                  if (!isRead)
                    Container(
                      width: 8,
                      height: 8,
                      margin: EdgeInsets.only(left: AppSizes.spacingS),
                      decoration: BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                    ),
                ],
              ),
            ),
          ),

          // Expanded actions
          if (isExpanded)
            Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(AppSizes.radiusL),
                  bottomRight: Radius.circular(AppSizes.radiusL),
                ),
              ),
              padding: EdgeInsets.all(AppSizes.spacingM),
              child: Row(
                children: [
                  if (notification.type == NotificationType.safeZone)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _handleEngineAction,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusM)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_rounded, size: 16),
                            SizedBox(width: 6),
                            Text(_selectedLanguage == 'en' ? 'Cut Engine' : 'Couper moteur', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  if (notification.type == NotificationType.safeZone) SizedBox(width: AppSizes.spacingS),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _markAsRead(notification.id),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusM)),
                      ),
                      child: Text(
                        _selectedLanguage == 'en' ? 'Mark Read' : 'Marquer lu',
                        style: TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}