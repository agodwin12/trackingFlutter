// lib/src/screens/trips/trips_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';
import '../settings/settings.dart';

class TripsScreen extends StatefulWidget {
  final int vehicleId;

  const TripsScreen({Key? key, required this.vehicleId}) : super(key: key);

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  int _selectedNavIndex = 2; // Trips tab
  bool _isLoading = true;
  bool _showFilters = false;
  String _selectedLanguage = 'en';

  // Trip tracking status
  bool _isTripTrackingEnabled = false;
  bool _isLoadingStatus = true;
  int? _userId;

  String get baseUrl => EnvConfig.baseUrl;

  // Trip Data
  List<Map<String, dynamic>> _trips = [];

  // Filter options
  String _selectedFilter = 'today'; // today, yesterday, week, month, custom
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
    _initializeScreen();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
    debugPrint('✅ Trips screen loaded language preference: $_selectedLanguage');
  }

  Future<void> _initializeScreen() async {
    await _loadUserId();
    await Future.wait([
      _fetchTripTrackingStatus(),
      _fetchTrips(),
    ]);
  }

  /// Load user ID from SharedPreferences
  Future<void> _loadUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');

      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        _userId = userData['id'];
        debugPrint('✅ User ID loaded: $_userId');
      }
    } catch (e) {
      debugPrint('🔥 Error loading user ID: $e');
    }
  }

  /// 🔧 FIXED: Corrected API endpoint to match settings_screen.dart
  Future<void> _fetchTripTrackingStatus() async {
    if (_userId == null) {
      setState(() => _isLoadingStatus = false);
      return;
    }

    try {
      debugPrint('📡 Fetching trip tracking status for user: $_userId');

      // 🔧 FIXED: Removed /api prefix to match backend route
      final response = await http.get(
        Uri.parse('$baseUrl/users-settings/$_userId/settings'),
        headers: {'Content-Type': 'application/json'},
      );

      debugPrint('📡 Status response: ${response.statusCode}');
      debugPrint('📡 Status body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final settings = data['data']['settings'];

          if (mounted) {
            setState(() {
              _isTripTrackingEnabled = settings['tripTrackingEnabled'] ?? false;
              _isLoadingStatus = false;
            });
          }

          debugPrint('✅ Trip tracking status loaded: $_isTripTrackingEnabled');
        }
      } else {
        debugPrint('⚠️ Failed to fetch status: ${response.statusCode}');
        if (mounted) {
          setState(() => _isLoadingStatus = false);
        }
      }
    } catch (error) {
      debugPrint('🔥 Error fetching trip tracking status: $error');
      if (mounted) {
        setState(() => _isLoadingStatus = false);
      }
    }
  }

  /// Get date range based on selected filter
  Map<String, DateTime?> _getDateRange() {
    final now = DateTime.now();
    DateTime? startDate;
    DateTime? endDate;

    switch (_selectedFilter) {
      case 'today':
        startDate = DateTime(now.year, now.month, now.day);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;

      case 'yesterday':
        final yesterday = now.subtract(Duration(days: 1));
        startDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
        endDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
        break;

      case 'week':
      // Start from Monday of current week
        final weekday = now.weekday;
        final monday = now.subtract(Duration(days: weekday - 1));
        startDate = DateTime(monday.year, monday.month, monday.day);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;

      case 'month':
        startDate = DateTime(now.year, now.month, 1);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;

      case 'custom':
        startDate = _customStartDate;
        endDate = _customEndDate;
        break;

      default:
        startDate = DateTime(now.year, now.month, now.day);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    }

    return {'start': startDate, 'end': endDate};
  }

  Future<void> _fetchTrips() async {
    setState(() => _isLoading = true);

    try {
      final dateRange = _getDateRange();
      final params = <String, String>{};

      if (dateRange['start'] != null) {
        params['startDate'] = DateFormat('yyyy-MM-dd').format(dateRange['start']!);
      }
      if (dateRange['end'] != null) {
        params['endDate'] = DateFormat('yyyy-MM-dd').format(dateRange['end']!);
      }

      final uri = Uri.parse('$baseUrl/trips/vehicle/${widget.vehicleId}')
          .replace(queryParameters: params);

      debugPrint('📡 Fetching trips with params: $params');

      final response = await http.get(uri);

      debugPrint('📡 Trips response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (mounted && data['success'] == true) {
          setState(() {
            _trips = List<Map<String, dynamic>>.from(data['data']['trips']);
          });
          debugPrint('✅ Loaded ${_trips.length} trips');
        }
      }
    } catch (error) {
      debugPrint('🔥 Error fetching trips: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleRefresh() async {
    await Future.wait([
      _fetchTripTrackingStatus(),
      _fetchTrips(),
    ]);
  }

  void _toggleFilters() {
    setState(() {
      _showFilters = !_showFilters;
    });
  }

  /// Show custom date picker
  Future<void> _showCustomDatePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: AppColors.white,
              onSurface: AppColors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedFilter = 'custom';
        _customStartDate = picked.start;
        _customEndDate = picked.end;
      });
      _fetchTrips();
    }
  }

  /// Navigate to Settings to enable trip tracking
  void _goToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(vehicleId: widget.vehicleId),
      ),
    ).then((_) {
      // 🔧 FIXED: Refresh status when coming back from Settings
      debugPrint('🔄 Returned from Settings, refreshing status...');
      _fetchTripTrackingStatus();
      _fetchTrips();
    });
  }

  void _viewTripOnMap(Map<String, dynamic> trip) {
    Navigator.pushNamed(
      context,
      '/trip-map',
      arguments: {
        'tripId': trip['id'],
        'vehicleId': widget.vehicleId,
      },
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd MMM yyyy').format(date);
    } catch (e) {
      return _selectedLanguage == 'en' ? 'Invalid date' : 'Date invalide';
    }
  }

  String _formatTime(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('HH:mm').format(date);
    } catch (e) {
      return _selectedLanguage == 'en' ? 'Invalid time' : 'Heure invalide';
    }
  }

  String _formatDateShort(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return _selectedLanguage == 'en' ? 'Today' : 'Aujourd\'hui';
      } else if (difference.inDays == 1) {
        return _selectedLanguage == 'en' ? 'Yesterday' : 'Hier';
      } else if (difference.inDays < 7) {
        return DateFormat('EEEE').format(date);
      } else {
        return DateFormat('MMM dd').format(date);
      }
    } catch (e) {
      return _selectedLanguage == 'en' ? 'Invalid date' : 'Date invalide';
    }
  }

  String _getTripDuration(Map<String, dynamic> trip) {
    try {
      final startTime = DateTime.parse(trip['startTime']);
      final endTime = DateTime.parse(trip['endTime']);
      final duration = endTime.difference(startTime);
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;

      if (hours > 0) {
        return '${hours}h ${minutes}m';
      } else {
        return '${minutes}m';
      }
    } catch (e) {
      return trip['durationFormatted'] ?? 'N/A';
    }
  }

  /// Get display text for current filter
  String _getFilterDisplayText() {
    switch (_selectedFilter) {
      case 'today':
        return _selectedLanguage == 'en' ? 'Today\'s trips' : 'Trajets d\'aujourd\'hui';
      case 'yesterday':
        return _selectedLanguage == 'en' ? 'Yesterday\'s trips' : 'Trajets d\'hier';
      case 'week':
        return _selectedLanguage == 'en' ? 'This week\'s trips' : 'Trajets de cette semaine';
      case 'month':
        return _selectedLanguage == 'en' ? 'This month\'s trips' : 'Trajets de ce mois';
      case 'custom':
        if (_customStartDate != null && _customEndDate != null) {
          return '${DateFormat('MMM dd').format(_customStartDate!)} - ${DateFormat('MMM dd').format(_customEndDate!)}';
        }
        return _selectedLanguage == 'en' ? 'Custom range' : 'Période personnalisée';
      default:
        return _selectedLanguage == 'en' ? 'All trips' : 'Tous les trajets';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Compact Header
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
                          _selectedLanguage == 'en' ? 'Trip History' : 'Historique des trajets',
                          style: AppTypography.h3.copyWith(fontSize: 18),
                        ),
                        Text(
                          _getFilterDisplayText(),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _toggleFilters,
                    icon: Icon(
                      Icons.tune_rounded,
                      color: _showFilters ? AppColors.primary : AppColors.black,
                      size: 22,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Trip Tracking Status Banner
            if (!_isLoadingStatus && !_isTripTrackingEnabled)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(AppSizes.spacingM),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.warning.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.warning,
                        size: 18,
                      ),
                    ),
                    SizedBox(width: AppSizes.spacingM),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedLanguage == 'en'
                                ? 'Trip Tracking Disabled'
                                : 'Suivi des trajets désactivé',
                            style: AppTypography.body1.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.warning,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            _selectedLanguage == 'en'
                                ? 'New trips will not be recorded'
                                : 'Les nouveaux trajets ne seront pas enregistrés',
                            style: AppTypography.caption.copyWith(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: AppSizes.spacingS),
                    TextButton(
                      onPressed: _goToSettings,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSizes.spacingM,
                          vertical: AppSizes.spacingS,
                        ),
                        backgroundColor: AppColors.warning.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSizes.radiusS),
                        ),
                      ),
                      child: Text(
                        _selectedLanguage == 'en' ? 'Enable' : 'Activer',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 🆕 REDESIGNED Filter Section
            if (_showFilters)
              Container(
                color: AppColors.white,
                padding: EdgeInsets.all(AppSizes.spacingL),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(height: 1),
                    SizedBox(height: AppSizes.spacingM),
                    Text(
                      _selectedLanguage == 'en' ? 'Filter by Date' : 'Filtrer par date',
                      style: AppTypography.subtitle1.copyWith(fontSize: 14),
                    ),
                    SizedBox(height: AppSizes.spacingM),

                    // Quick filter chips
                    Wrap(
                      spacing: AppSizes.spacingS,
                      runSpacing: AppSizes.spacingS,
                      children: [
                        _buildFilterChip(
                          label: _selectedLanguage == 'en' ? 'Today' : 'Aujourd\'hui',
                          icon: Icons.today_rounded,
                          value: 'today',
                        ),
                        _buildFilterChip(
                          label: _selectedLanguage == 'en' ? 'Yesterday' : 'Hier',
                          icon: Icons.calendar_today_rounded,
                          value: 'yesterday',
                        ),
                        _buildFilterChip(
                          label: _selectedLanguage == 'en' ? 'This Week' : 'Cette semaine',
                          icon: Icons.date_range_rounded,
                          value: 'week',
                        ),
                        _buildFilterChip(
                          label: _selectedLanguage == 'en' ? 'This Month' : 'Ce mois',
                          icon: Icons.calendar_month_rounded,
                          value: 'month',
                        ),
                      ],
                    ),

                    SizedBox(height: AppSizes.spacingM),

                    // Custom date range button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showCustomDatePicker,
                        icon: Icon(Icons.event_rounded, size: 18),
                        label: Text(
                          _selectedFilter == 'custom' && _customStartDate != null
                              ? '${DateFormat('MMM dd, yyyy').format(_customStartDate!)} - ${DateFormat('MMM dd, yyyy').format(_customEndDate!)}'
                              : (_selectedLanguage == 'en'
                                  ? 'Choose Custom Date Range'
                                  : 'Choisir une période personnalisée'),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _selectedFilter == 'custom'
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          side: BorderSide(
                            color: _selectedFilter == 'custom'
                                ? AppColors.primary
                                : AppColors.border,
                            width: _selectedFilter == 'custom' ? 2 : 1,
                          ),
                          backgroundColor: _selectedFilter == 'custom'
                              ? AppColors.primaryLight
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppSizes.radiusM),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSizes.spacingM,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Trips List
            Expanded(
              child: _isLoading
                  ? Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                ),
              )
                  : _trips.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                onRefresh: _handleRefresh,
                color: AppColors.primary,
                child: ListView.builder(
                  padding: EdgeInsets.all(AppSizes.spacingM),
                  itemCount: _trips.length,
                  itemBuilder: (context, index) {
                    final trip = _trips[index];
                    final showDate = index == 0 ||
                        _formatDate(_trips[index - 1]['startTime']) !=
                            _formatDate(trip['startTime']);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showDate) ...[
                          if (index > 0) SizedBox(height: AppSizes.spacingM),
                          Padding(
                            padding: EdgeInsets.only(
                              left: AppSizes.spacingS,
                              bottom: AppSizes.spacingS,
                            ),
                            child: Text(
                              _formatDateShort(trip['startTime']),
                              style: AppTypography.body1.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                        _buildTripCard(trip),
                        SizedBox(height: AppSizes.spacingS),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🆕 Beautiful filter chip widget
  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required String value,
  }) {
    final isSelected = _selectedFilter == value;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedFilter = value;
        });
        _fetchTrips();
      },
      borderRadius: BorderRadius.circular(AppSizes.radiusL),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.spacingM,
          vertical: AppSizes.spacingS + 2,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppColors.white : AppColors.textSecondary,
            ),
            SizedBox(width: AppSizes.spacingXS),
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color: isSelected ? AppColors.white : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripCard(Map<String, dynamic> trip) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.all(AppSizes.spacingM),
          child: Row(
            children: [
              // Start Time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: AppSizes.spacingXS),
                        Text(
                          _selectedLanguage == 'en' ? 'Start' : 'Début',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      _formatTime(trip['startTime']),
                      style: AppTypography.body1.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // Divider
              Container(
                width: 1,
                height: 30,
                color: AppColors.border,
                margin: EdgeInsets.symmetric(horizontal: AppSizes.spacingM),
              ),

              // End Time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: AppSizes.spacingXS),
                        Text(
                          _selectedLanguage == 'en' ? 'Stop' : 'Arrêt',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      _formatTime(trip['endTime']),
                      style: AppTypography.body1.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // Duration Badge
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSizes.spacingS,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppSizes.radiusS),
                ),
                child: Text(
                  _getTripDuration(trip),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),

              SizedBox(width: AppSizes.spacingS),

              // View Button
              InkWell(
                onTap: () => _viewTripOnMap(trip),
                borderRadius: BorderRadius.circular(AppSizes.radiusS),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSizes.spacingM,
                    vertical: AppSizes.spacingS,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSizes.radiusS),
                  ),
                  child: Text(
                    _selectedLanguage == 'en' ? 'View' : 'Voir',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    // Show different message based on tracking status
    if (!_isLoadingStatus && !_isTripTrackingEnabled) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(AppSizes.spacingXL),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(AppSizes.spacingL),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.block_rounded,
                  size: 48,
                  color: AppColors.warning,
                ),
              ),
              SizedBox(height: AppSizes.spacingL),
              Text(
                _selectedLanguage == 'en'
                    ? 'Trip Tracking Disabled'
                    : 'Suivi des trajets désactivé',
                style: AppTypography.h3.copyWith(
                  color: AppColors.black,
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSizes.spacingS),
              Text(
                _selectedLanguage == 'en'
                    ? 'You won\'t see any trips here because trip tracking is currently turned off.'
                    : 'Vous ne verrez aucun trajet ici car le suivi des trajets est actuellement désactivé.',
                style: AppTypography.body2.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSizes.spacingL),
              ElevatedButton.icon(
                onPressed: _goToSettings,
                icon: Icon(Icons.settings_rounded, size: 18),
                label: Text(_selectedLanguage == 'en' ? 'Go to Settings' : 'Aller aux paramètres'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: AppColors.white,
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
            ],
          ),
        ),
      );
    }

    // Default empty state (tracking is enabled, but no trips)
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSizes.spacingXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.route_outlined,
              size: 64,
              color: AppColors.textSecondary.withOpacity(0.5),
            ),
            SizedBox(height: AppSizes.spacingL),
            Text(
              _selectedLanguage == 'en' ? 'No trips found' : 'Aucun trajet trouvé',
              style: AppTypography.h3.copyWith(color: AppColors.textSecondary),
            ),
            SizedBox(height: AppSizes.spacingS),
            Text(
              _selectedLanguage == 'en'
                  ? 'No trips found for ${_getFilterDisplayText().toLowerCase()}'
                  : 'Aucun trajet trouvé pour ${_getFilterDisplayText().toLowerCase()}',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}