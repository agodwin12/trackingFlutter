// lib/screens/notifications_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';
import '../../services/socket_service.dart';
import 'widgets/notifications_skeleton.dart';




enum NotificationType {
  safeZone,
  geofence,
  speed,
  timeZone,
  alert,
}

class AppNotification {
  final int id;
  final NotificationType type;
  final String title;
  final String vehicleNickname;
  final String zone;
  final DateTime time;
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
    final String alertType = (json['alert_type'] ?? 'alert').toLowerCase();
    final String message = json['message'] ?? '';

    // Determine notification type
    NotificationType type;
    String title = 'Alert';

    if (alertType.contains('speed')) {
      type = NotificationType.speed;
      title = 'Speed Alert';
    } else if (alertType.contains('time') || alertType.contains('zone')) {
      // Check if it's time_zone or safe_zone
      if (alertType == 'time_zone') {
        type = NotificationType.timeZone;
        title = 'Time Zone Alert';
      } else if (alertType.contains('safe')) {
        type = NotificationType.safeZone;
        title = 'Safe Zone Alert';
      } else {
        type = NotificationType.alert;
      }
    } else if (alertType.contains('geofence') || alertType.contains('fence')) {
      type = NotificationType.geofence;
      title = 'Geofence Alert';
    } else {
      type = NotificationType.alert;
    }

    // Parse message to extract details
    if (message.contains('left') || message.contains('outside')) {
      title = 'Safe Zone Alert';
    } else if (message.contains('returned') || message.contains('inside')) {
      title = 'Safe Zone Return';
    } else if (message.contains('entered')) {
      title = 'Geofence Entry';
    } else if (message.contains('exited')) {
      title = 'Geofence Exit';
    } else if (message.contains('exceeded') || message.contains('speed')) {
      title = 'Speed Alert';
    } else if (message.contains('restricted') || message.contains('hours')) {
      title = 'Time Zone Alert';
    }

    // Extract vehicle name
    String vehicleNickname = 'Vehicle';
    final vehicleMatch = RegExp(r'Vehicle\s+([A-Za-z0-9\s]+)\s+(left|returned|entered|exited|exceeded|moved)').firstMatch(message);
    if (vehicleMatch != null) {
      vehicleNickname = vehicleMatch.group(1)?.trim() ?? vehicleNickname;
    }

    // Extract zone
    String zone = 'Unknown Zone';
    final zoneMatch = RegExp(r'zone\s+"([^"]+)"').firstMatch(message);
    if (zoneMatch != null) {
      zone = zoneMatch.group(1) ?? zone;
    }

    return AppNotification(
      id: json['id'] ?? 0,
      type: type,
      title: title,
      vehicleNickname: vehicleNickname,
      zone: zone,
      time: DateTime.parse(json['alerted_at'] ?? DateTime.now().toIso8601String()),
      isRead: json['read'] == true || json['read'] == 1,
      message: message,
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

  // Pagination
  int _currentPage = 1;
  final int _pageSize = 20;
  bool _hasMoreData = true;
  int _totalNotifications = 0;

  AppNotification? _latestAlert;

  final SocketService _socketService = SocketService();
  StreamSubscription<Map<String, dynamic>>? _alertSubscription;

  String get baseUrl => EnvConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
    _tabController = TabController(length: 5, vsync: this);
    _fetchNotifications();
    _connectSocketForAlerts();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
    debugPrint('✅ Notification screen loaded language preference: $_selectedLanguage');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _alertSubscription?.cancel();
    super.dispose();
  }

  void _connectSocketForAlerts() {
    _socketService.connect(EnvConfig.socketUrl);
    _socketService.joinVehicleTracking(widget.vehicleId);

    _alertSubscription = _socketService.safeZoneAlertStream.listen((alertData) {
      debugPrint('🚨 Real-time alert received: $alertData');
      if (mounted) {
        _showRealtimePushNotification(alertData);
        _handleRefresh();
      }
    });
  }

  void _showRealtimePushNotification(Map<String, dynamic> alertData) {
    final title = alertData['title'] ?? (_selectedLanguage == 'en' ? 'Alert' : 'Alerte');
    final message = alertData['message'] ?? '';
    final vehicleName = alertData['nickname'] ?? (_selectedLanguage == 'en' ? 'Vehicle' : 'Véhicule');
    final zoneName = alertData['safeZoneName'] ?? (_selectedLanguage == 'en' ? 'Unknown Zone' : 'Zone inconnue');

    setState(() {
      _latestAlert = AppNotification(
        id: alertData['alertId'] ?? 0,
        type: NotificationType.safeZone,
        title: title,
        vehicleNickname: vehicleName,
        zone: zoneName,
        time: DateTime.now(),
        isRead: false,
        message: message,
      );
      _showPushNotification = true;
    });

    Future.delayed(Duration(seconds: 8), () {
      if (mounted && _showPushNotification) {
        setState(() {
          _showPushNotification = false;
        });
      }
    });
  }

  Future<void> _fetchNotifications({bool loadMore = false}) async {
    if (loadMore && !_hasMoreData) return;
    if (loadMore && _isLoadingMore) return;

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
      final response = await http.get(
        Uri.parse('$baseUrl/alerts/vehicle/${widget.vehicleId}?page=$_currentPage&limit=$_pageSize'),
      );

      debugPrint('📡 Fetch notifications response: ${response.statusCode}');
      debugPrint('📡 Page: $_currentPage, Limit: $_pageSize');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final List<dynamic> alertsJson = data['data']['alerts'] ?? [];
          final pagination = data['data']['pagination'];

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

              // Update read status
              _readNotifications = _allNotifications
                  .where((n) => n.isRead)
                  .map((n) => n.id)
                  .toSet();

              // Update pagination info
              _totalNotifications = pagination['totalAlerts'] ?? 0;
              _hasMoreData = pagination['hasNextPage'] ?? false;

              _isLoading = false;
              _isRefreshing = false;
              _isLoadingMore = false;
            });
          }

          debugPrint('✅ Loaded ${_allNotifications.length} of $_totalNotifications notifications');
          debugPrint('✅ Has more data: $_hasMoreData');
        }
      } else {
        debugPrint('⚠️ Failed to load notifications: ${response.statusCode}');
      }
    } catch (error) {
      debugPrint('🔥 Error fetching notifications: $error');
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _isLoadingMore = false;
      });
    }
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
    setState(() {
      _showPushNotification = false;
    });
  }

  void _navigateToDashboard() {
    Navigator.pushReplacementNamed(
      context,
      '/dashboard',
      arguments: widget.vehicleId,
    );
  }

  void _handleEngineAction() {
    _dismissPushNotification();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
        ),
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
                final response = await http.post(
                  Uri.parse('$baseUrl/gps/issue-command'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'vehicleId': widget.vehicleId,
                    'command': 'CLOSERELAY',
                    'params': '',
                    'password': '',
                    'sendTime': '',
                  }),
                );

                if (response.statusCode == 200) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_selectedLanguage == 'en'
                          ? 'Engine cut off successfully'
                          : 'Moteur coupé avec succès'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } else {
                  throw Exception('Failed to cut engine');
                }
              } catch (error) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_selectedLanguage == 'en'
                        ? 'Failed to cut engine'
                        : 'Échec de la coupure du moteur'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              _selectedLanguage == 'en' ? 'Cut Engine' : 'Couper le moteur',
              style: AppTypography.body2.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<AppNotification> get _unreadNotifications {
    return _allNotifications
        .where((n) => !_readNotifications.contains(n.id))
        .toList();
  }

  List<AppNotification> get _safeZoneNotifications {
    return _allNotifications
        .where((n) => n.type == NotificationType.safeZone)
        .toList();
  }

  List<AppNotification> get _geofenceNotifications {
    return _allNotifications
        .where((n) => n.type == NotificationType.geofence)
        .toList();
  }

  List<AppNotification> get _speedNotifications {
    return _allNotifications
        .where((n) => n.type == NotificationType.speed)
        .toList();
  }

  List<AppNotification> get _timeZoneNotifications {
    return _allNotifications
        .where((n) => n.type == NotificationType.timeZone)
        .toList();
  }

  Future<void> _markAsRead(int notificationId) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/alerts/$notificationId/read'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        setState(() {
          _readNotifications.add(notificationId);
          _expandedNotificationId = null;
        });
      }
    } catch (error) {
      debugPrint('🔥 Error marking as read: $error');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/alerts/vehicle/${widget.vehicleId}/read-all'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        setState(() {
          for (var notification in _allNotifications) {
            _readNotifications.add(notification.id);
          }
          _expandedNotificationId = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_selectedLanguage == 'en'
                ? 'All notifications marked as read'
                : 'Toutes les notifications marquées comme lues'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (error) {
      debugPrint('🔥 Error marking all as read: $error');
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return _selectedLanguage == 'en' ? 'Now' : 'Maintenant';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
    } else {
      return '${difference.inDays}${_selectedLanguage == 'en' ? 'd' : 'j'}';
    }
  }

  IconData _getNotificationIcon(NotificationType type) {
    switch (type) {
      case NotificationType.safeZone:
        return Icons.shield_rounded;
      case NotificationType.geofence:
        return Icons.location_on_rounded;
      case NotificationType.speed:
        return Icons.speed_rounded;
      case NotificationType.timeZone:
        return Icons.access_time_rounded;
      case NotificationType.alert:
        return Icons.warning_rounded;
    }
  }

  Color _getNotificationColor(NotificationType type) {
    switch (type) {
      case NotificationType.safeZone:
        return Color(0xFF3B82F6);
      case NotificationType.geofence:
        return Color(0xFF8B5CF6);
      case NotificationType.speed:
        return Color(0xFFEF4444);
      case NotificationType.timeZone:
        return Color(0xFFF59E0B);
      case NotificationType.alert:
        return Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const NotificationsSkeleton();  // ✅ Use skeleton instead
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
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSizes.spacingL,
                    vertical: AppSizes.spacingM,
                  ),
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
                    isScrollable: true,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondary,
                    labelStyle: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 2,
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_selectedLanguage == 'en' ? 'All' : 'Tout'),
                            if (_unreadNotifications.isNotEmpty) ...[
                              SizedBox(width: 6),
                              Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.error,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_unreadNotifications.length}',
                                  style: TextStyle(
                                    color: AppColors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Tab(text: _selectedLanguage == 'en' ? 'Safe Zone' : 'Zone de sécurité'),
                      Tab(text: _selectedLanguage == 'en' ? 'Geofence' : 'Géofence'),
                      Tab(text: _selectedLanguage == 'en' ? 'Speed' : 'Vitesse'),
                      Tab(text: _selectedLanguage == 'en' ? 'Time Zone' : 'Horaire'),
                    ],
                  ),
                ),

                // Tab Views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildNotificationsList(_allNotifications),
                      _buildNotificationsList(_safeZoneNotifications),
                      _buildNotificationsList(_geofenceNotifications),
                      _buildNotificationsList(_speedNotifications),
                      _buildNotificationsList(_timeZoneNotifications),
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
          gradient: LinearGradient(
            colors: [AppColors.error, AppColors.error.withOpacity(0.8)],
          ),
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
          boxShadow: [
            BoxShadow(
              color: AppColors.error.withOpacity(0.4),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
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
                        style: AppTypography.body1.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${_latestAlert!.vehicleNickname} - ${_latestAlert!.zone}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.white.withOpacity(0.9),
                          fontSize: 12,
                        ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSizes.radiusM),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_rounded, color: AppColors.error, size: 16),
                        SizedBox(width: 6),
                        Text(
                          _selectedLanguage == 'en' ? 'Cut Engine' : 'Couper moteur',
                          style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSizes.radiusM),
                      ),
                    ),
                    child: Text(
                      _selectedLanguage == 'en' ? 'View Location' : 'Voir position',
                      style: TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
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

  Widget _buildNotificationsList(List<AppNotification> notifications) {
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
                  Icon(Icons.notifications_off_outlined,
                      size: 64, color: AppColors.textSecondary.withOpacity(0.5)),
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

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: AppColors.primary,
      child: ListView.builder(
        padding: EdgeInsets.all(AppSizes.spacingM),
        itemCount: notifications.length + (_hasMoreData ? 1 : 0),
        itemBuilder: (context, index) {
          // Load more indicator
          if (index == notifications.length) {
            if (_isLoadingMore) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSizes.spacingL),
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                ),
              );
            }

            // Load more button
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
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSizes.spacingL,
                      vertical: AppSizes.spacingM,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusM),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            );
          }

          final notification = notifications[index];
          final isRead = _readNotifications.contains(notification.id);
          final isExpanded = _expandedNotificationId == notification.id.toString();

          return Padding(
            padding: EdgeInsets.only(bottom: AppSizes.spacingM),
            child: _buildNotificationCard(notification, isRead, isExpanded),
          );
        },
      ),
    );
  }

  Widget _buildNotificationCard(
      AppNotification notification, bool isRead, bool isExpanded) {
    final color = _getNotificationColor(notification.type);
    final icon = _getNotificationIcon(notification.type);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        border: Border.all(
          color: isRead ? AppColors.border : AppColors.error,
          width: isRead ? 1 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: isRead
                ? AppColors.black.withOpacity(0.05)
                : AppColors.error.withOpacity(0.15),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                notification.title,
                                style: AppTypography.body1.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              _formatTime(notification.time),
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: AppSizes.spacingXS),
                        Text(
                          notification.message,
                          style: AppTypography.body2.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          maxLines: isExpanded ? null : 2,
                          overflow: isExpanded ? null : TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _expandedNotificationId = isExpanded ? null : notification.id.toString();
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                  ),
                  if (!isRead)
                    Container(
                      width: 8,
                      height: 8,
                      margin: EdgeInsets.only(left: AppSizes.spacingS),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppSizes.radiusM),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_rounded, size: 16),
                            SizedBox(width: 6),
                            Text(
                              _selectedLanguage == 'en' ? 'Cut Engine' : 'Couper moteur',
                              style: TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (notification.type == NotificationType.safeZone)
                    SizedBox(width: AppSizes.spacingS),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _markAsRead(notification.id),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSizes.radiusM),
                        ),
                      ),
                      child: Text(
                        _selectedLanguage == 'en' ? 'Mark Read' : 'Marquer lu',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
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