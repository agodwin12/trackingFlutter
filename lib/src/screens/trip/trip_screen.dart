// lib/src/screens/trips/trips_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utility/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/cache_service.dart';
import '../../widgets/offline_barner.dart';
import '../../widgets/subscription_upgrade_sheet.dart';
import '../settings/settings.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Stats model — holds the two values shown in the banner
// ─────────────────────────────────────────────────────────────────────────────
class _TripStats {
  final double totalDistanceKm;
  final double avgSpeedKmh;
  final int    totalTrips;

  const _TripStats({
    required this.totalDistanceKm,
    required this.avgSpeedKmh,
    required this.totalTrips,
  });

  /// Compute stats locally from a list of trip maps.
  /// Used for the default "recent 10" view — avoids an extra API call.
  factory _TripStats.fromTrips(List<Map<String, dynamic>> trips) {
    if (trips.isEmpty) {
      return const _TripStats(
          totalDistanceKm: 0, avgSpeedKmh: 0, totalTrips: 0);
    }
    double dist  = 0;
    double speed = 0;
    for (final t in trips) {
      dist  += (t['totalDistanceKm'] as num?)?.toDouble()  ?? 0;
      speed += (t['avgSpeedKmh']     as num?)?.toDouble()  ?? 0;
    }
    return _TripStats(
      totalDistanceKm: double.parse(dist.toStringAsFixed(2)),
      avgSpeedKmh:     double.parse((speed / trips.length).toStringAsFixed(1)),
      totalTrips:      trips.length,
    );
  }

  /// Build from the API response of GET /trips/vehicle/:id/stats
  factory _TripStats.fromApi(Map<String, dynamic> data) {
    return _TripStats(
      totalDistanceKm: (data['totalDistanceKm'] as num?)?.toDouble() ?? 0,
      avgSpeedKmh:     (data['avgSpeed']         as num?)?.toDouble() ?? 0,
      totalTrips:      (data['totalTrips']        as num?)?.toInt()   ?? 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class TripsScreen extends StatefulWidget {
  final int vehicleId;
  const TripsScreen({Key? key, required this.vehicleId}) : super(key: key);

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  // ─── Services ──────────────────────────────────────────────────────────────
  final ConnectivityService _connectivityService = ConnectivityService();
  final CacheService        _cacheService        = CacheService();

  // ─── UI state ──────────────────────────────────────────────────────────────
  bool   _isLoading         = true;
  bool   _showFilters       = false;
  String _selectedLanguage  = 'en';
  bool   _isLoadedFromCache = false;

  // ─── Trip tracking ─────────────────────────────────────────────────────────
  bool _isTripTrackingEnabled = false;
  bool _isLoadingStatus       = true;
  int? _userId;

  bool get isOnline  => _connectivityService.isOnline;
  bool get isOffline => _connectivityService.isOffline;

  // ─── Trips ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _trips = [];
  int  _currentPage   = 1;
  bool _hasMoreTrips  = false;
  bool _isLoadingMore = false;

  // ─── Filters ───────────────────────────────────────────────────────────────
  // null  = default "recent 10" view (no date filter, no chip selected)
  // 'today' | 'yesterday' | 'week' | 'month' | 'custom'
  String?   _selectedFilter  = null;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  // ─── Stats ─────────────────────────────────────────────────────────────────
  _TripStats? _stats;
  bool        _isLoadingStats = false;

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
    _initializeScreen();
    _connectivityService.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    _connectivityService.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (!mounted) return;
    setState(() {});
    if (isOnline && _isLoadedFromCache) {
      _fetchTrips();
      _fetchTripTrackingStatus();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INIT
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _selectedLanguage = prefs.getString('language') ?? 'en');
    }
  }

  Future<void> _initializeScreen() async {
    await _loadUserId();
    if (isOffline) {
      await _loadTripsFromCache();
    } else {
      await Future.wait([
        _fetchTripTrackingStatus(),
        _fetchTrips(), // default: recent 10, no date filter
      ]);
    }
  }

  Future<void> _loadUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str   = prefs.getString('user');
      if (str != null) _userId = (jsonDecode(str)['id'] as num).toInt();
    } catch (e) {
      debugPrint('🔥 Error loading user ID: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CACHE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadTripsFromCache() async {
    setState(() => _isLoading = true);
    try {
      final cached = await _cacheService.getCachedTrips(widget.vehicleId);
      final trips  = cached ?? [];
      setState(() {
        _trips            = trips;
        _stats            = _TripStats.fromTrips(trips);
        _isLoadedFromCache = true;
      });
    } catch (e) {
      debugPrint('❌ Cache load error: $e');
      setState(() { _trips = []; _isLoadedFromCache = true; });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TRACKING STATUS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _fetchTripTrackingStatus() async {
    if (_userId == null || isOffline) {
      if (mounted) setState(() => _isLoadingStatus = false);
      return;
    }
    try {
      final data = await ApiService.get('/users-settings/$_userId/settings');
      if (data['success'] == true && data['data'] != null) {
        final settings = data['data']['settings'];
        if (mounted) {
          setState(() {
            _isTripTrackingEnabled = settings['tripTrackingEnabled'] ?? false;
            _isLoadingStatus       = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingStatus = false);
      }
    } catch (e) {
      debugPrint('🔥 Error fetching tracking status: $e');
      if (mounted) setState(() => _isLoadingStatus = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DATE RANGE HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns {start, end} for the active filter, or {null, null} for recent view.
  Map<String, DateTime?> _getDateRange() {
    final now = DateTime.now();
    switch (_selectedFilter) {
      case 'today':
        return {
          'start': DateTime(now.year, now.month, now.day),
          'end':   DateTime(now.year, now.month, now.day, 23, 59, 59),
        };
      case 'yesterday':
        final y = now.subtract(const Duration(days: 1));
        return {
          'start': DateTime(y.year, y.month, y.day),
          'end':   DateTime(y.year, y.month, y.day, 23, 59, 59),
        };
      case 'week':
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return {
          'start': DateTime(monday.year, monday.month, monday.day),
          'end':   DateTime(now.year, now.month, now.day, 23, 59, 59),
        };
      case 'month':
        return {
          'start': DateTime(now.year, now.month, 1),
          'end':   DateTime(now.year, now.month, now.day, 23, 59, 59),
        };
      case 'custom':
        return {'start': _customStartDate, 'end': _customEndDate};
      default:
      // No filter selected → recent 10
        return {'start': null, 'end': null};
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FETCH TRIPS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _fetchTrips({bool loadMore = false}) async {
    if (loadMore) {
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _isLoading    = true;
        _currentPage  = 1;
        _trips        = [];
      });
    }

    try {
      if (isOffline) {
        await _loadTripsFromCache();
        return;
      }

      final dateRange = _getDateRange();
      final params    = <String, String>{};
      final isRecent  = _selectedFilter == null;

      if (dateRange['start'] != null) {
        params['startDate'] =
            DateFormat('yyyy-MM-dd').format(dateRange['start']!);
      }
      if (dateRange['end'] != null) {
        params['endDate'] =
            DateFormat('yyyy-MM-dd').format(dateRange['end']!);
      }

      // Default view: always fetch exactly 10, no pagination needed
      if (isRecent) {
        params['limit'] = '10';
        params['page']  = '1';
      } else {
        params['page']  = _currentPage.toString();
        params['limit'] = _currentPage == 1 ? '5' : '10';
      }

      final data = await ApiService.get(
        '/trips/vehicle/${widget.vehicleId}',
        queryParams: params,
      );

      if (!mounted) return;

      if (data['success'] == true) {
        final newTrips   =
        List<Map<String, dynamic>>.from(data['data']['trips']);
        final pagination = data['data']['pagination'];

        setState(() {
          if (loadMore) {
            _trips.addAll(newTrips);
          } else {
            _trips = newTrips;
          }
          _hasMoreTrips     = isRecent ? false : (pagination['hasNextPage'] ?? false);
          _isLoadedFromCache = false;
        });

        // ── Stats ──────────────────────────────────────────────────────────
        // Default view: compute locally — no extra API call
        // Filter selected: fetch from stats endpoint for accurate period totals
        if (isRecent) {
          setState(() => _stats = _TripStats.fromTrips(_trips));
        } else if (!loadMore) {
          _fetchStats(dateRange['start'], dateRange['end']);
        }

        if (!loadMore) {
          await _cacheService.cacheTrips(widget.vehicleId, _trips);
        }
      }
    } on FeatureNotSubscribedException catch (e) {
      if (mounted) SubscriptionUpgradeSheet.show(context, feature: e.feature);
    } catch (e) {
      debugPrint('🔥 Error fetching trips: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading    = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FETCH STATS (from API — used when a date filter is active)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _fetchStats(DateTime? start, DateTime? end) async {
    if (isOffline || !mounted) return;

    setState(() => _isLoadingStats = true);

    try {
      final params = <String, String>{};
      if (start != null) params['startDate'] = DateFormat('yyyy-MM-dd').format(start);
      if (end   != null) params['endDate']   = DateFormat('yyyy-MM-dd').format(end);

      final data = await ApiService.get(
        '/trips/vehicle/${widget.vehicleId}/stats',
        queryParams: params,
      );

      if (!mounted) return;

      if (data['success'] == true && data['data'] != null) {
        setState(() => _stats = _TripStats.fromApi(
            data['data'] as Map<String, dynamic>));
      }
    } catch (e) {
      debugPrint('⚠️ Stats fetch error (non-fatal): $e');
    } finally {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOAD MORE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadMoreTrips() async {
    if (_isLoadingMore || !_hasMoreTrips) return;
    setState(() => _currentPage++);
    await _fetchTrips(loadMore: true);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REFRESH
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleRefresh() async {
    if (isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _selectedLanguage == 'en'
                  ? 'Cannot refresh while offline'
                  : 'Impossible de rafraîchir hors ligne',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ]),
        backgroundColor: const Color(0xFFF59E0B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape:  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      return;
    }
    await Future.wait([_fetchTripTrackingStatus(), _fetchTrips()]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FILTER SELECTION
  // ─────────────────────────────────────────────────────────────────────────

  void _onFilterSelected(String value) {
    setState(() {
      _selectedFilter = _selectedFilter == value ? null : value;
      _stats          = null; // clear while loading
    });
    _fetchTrips();
  }

  void _toggleFilters() => setState(() => _showFilters = !_showFilters);

  Future<void> _showCustomDatePicker() async {
    if (isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _selectedLanguage == 'en'
                  ? 'This feature requires internet'
                  : 'Cette fonction nécessite Internet',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ]),
        backgroundColor: const Color(0xFFF59E0B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape:  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      return;
    }

    final picked = await showDateRangePicker(
      context:   context,
      firstDate: DateTime(2020),
      lastDate:  DateTime.now(),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : null,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary:   AppColors.primary,
            onPrimary: AppColors.white,
            onSurface: AppColors.black,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        _selectedFilter  = 'custom';
        _customStartDate = picked.start;
        _customEndDate   = picked.end;
        _stats           = null;
      });
      _fetchTrips();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NAVIGATION
  // ─────────────────────────────────────────────────────────────────────────

  void _goToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => SettingsScreen(vehicleId: widget.vehicleId)),
    ).then((_) {
      if (isOnline) {
        _fetchTripTrackingStatus();
        _fetchTrips();
      }
    });
  }

  void _viewTripOnMap(Map<String, dynamic> trip) {
    Navigator.pushNamed(context, '/trip-map', arguments: {
      'tripId':    trip['id'],
      'vehicleId': widget.vehicleId,
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FORMAT HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  String _formatDate(String? ds) {
    if (ds == null) return 'N/A';
    try { return DateFormat('dd MMM yyyy').format(DateTime.parse(ds).toLocal()); }
    catch (_) { return _selectedLanguage == 'en' ? 'Invalid date' : 'Date invalide'; }
  }

  String _formatTime(String? ds) {
    if (ds == null) return 'N/A';
    try { return DateFormat('HH:mm').format(DateTime.parse(ds).toLocal()); }
    catch (_) { return _selectedLanguage == 'en' ? 'Invalid time' : 'Heure invalide'; }
  }

  String _formatDateShort(String? ds) {
    if (ds == null) return 'N/A';
    try {
      final date = DateTime.parse(ds).toLocal();
      final diff = DateTime.now().difference(date);
      if (diff.inDays == 0)  return _selectedLanguage == 'en' ? 'Today'     : 'Aujourd\'hui';
      if (diff.inDays == 1)  return _selectedLanguage == 'en' ? 'Yesterday' : 'Hier';
      if (diff.inDays < 7)   return DateFormat('EEEE').format(date);
      return DateFormat('MMM dd').format(date);
    } catch (_) {
      return _selectedLanguage == 'en' ? 'Invalid date' : 'Date invalide';
    }
  }

  String _getTripDuration(Map<String, dynamic> trip) {
    try {
      final start    = DateTime.parse(trip['startTime']).toLocal();
      final end      = DateTime.parse(trip['endTime']).toLocal();
      final duration = end.difference(start);
      final hours    = duration.inHours;
      final minutes  = duration.inMinutes % 60;
      return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
    } catch (_) {
      return trip['durationFormatted'] ?? 'N/A';
    }
  }

  String _statsLabel() {
    if (_selectedFilter == null) {
      return _selectedLanguage == 'en'
          ? 'Last ${_trips.length} trips'
          : '${_trips.length} derniers trajets';
    }
    switch (_selectedFilter) {
      case 'today':
        return _selectedLanguage == 'en' ? 'Today'      : 'Aujourd\'hui';
      case 'yesterday':
        return _selectedLanguage == 'en' ? 'Yesterday'  : 'Hier';
      case 'week':
        return _selectedLanguage == 'en' ? 'This week'  : 'Cette semaine';
      case 'month':
        return _selectedLanguage == 'en' ? 'This month' : 'Ce mois';
      case 'custom':
        if (_customStartDate != null && _customEndDate != null) {
          return '${DateFormat('MMM dd').format(_customStartDate!)} — '
              '${DateFormat('MMM dd').format(_customEndDate!)}';
        }
        return _selectedLanguage == 'en' ? 'Custom' : 'Personnalisé';
      default:
        return '';
    }
  }

  String _getFilterDisplayText() {
    if (isOffline && _isLoadedFromCache) {
      return _selectedLanguage == 'en'
          ? 'Last 30 days (cached)'
          : 'Derniers 30 jours (cache)';
    }
    if (_selectedFilter == null) {
      return _selectedLanguage == 'en' ? 'Recent trips' : 'Trajets récents';
    }
    switch (_selectedFilter) {
      case 'today':
        return _selectedLanguage == 'en'
            ? 'Today\'s trips' : 'Trajets d\'aujourd\'hui';
      case 'yesterday':
        return _selectedLanguage == 'en'
            ? 'Yesterday\'s trips' : 'Trajets d\'hier';
      case 'week':
        return _selectedLanguage == 'en'
            ? 'This week\'s trips' : 'Trajets de cette semaine';
      case 'month':
        return _selectedLanguage == 'en'
            ? 'This month\'s trips' : 'Trajets de ce mois';
      case 'custom':
        if (_customStartDate != null && _customEndDate != null) {
          return '${DateFormat('MMM dd').format(_customStartDate!)} - '
              '${DateFormat('MMM dd').format(_customEndDate!)}';
        }
        return _selectedLanguage == 'en' ? 'Custom range' : 'Période personnalisée';
      default:
        return _selectedLanguage == 'en' ? 'All trips' : 'Tous les trajets';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(),
            _buildHeader(),
            if (!_isLoadingStatus && !_isTripTrackingEnabled)
              _buildTrackingDisabledBanner(),
            if (_showFilters) _buildFilterSection(),
            // Stats banner — always visible
            _buildStatsBanner(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATS BANNER
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStatsBanner() {
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.fromLTRB(
        AppSizes.spacingL, AppSizes.spacingM,
        AppSizes.spacingL, AppSizes.spacingM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Period label ──────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color:        AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _statsLabel(),
                style: AppTypography.caption.copyWith(
                  color:      AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize:   11,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (_isLoadingStats)
                SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: AppColors.primary),
                ),
            ],
          ),
          SizedBox(height: AppSizes.spacingM),

          // ── 2 stat cards ──────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon:    Icons.route_rounded,
                  value:   _stats != null
                      ? '${_stats!.totalDistanceKm.toStringAsFixed(1)} km'
                      : '—',
                  label:   _selectedLanguage == 'en' ? 'Distance' : 'Distance',
                  color:   AppColors.primary,
                  loading: _isLoading || _isLoadingStats,
                ),
              ),
              SizedBox(width: AppSizes.spacingM),
              Expanded(
                child: _buildStatCard(
                  icon:    Icons.speed_rounded,
                  value:   _stats != null
                      ? '${_stats!.avgSpeedKmh.toStringAsFixed(1)} km/h'
                      : '—',
                  label:   _selectedLanguage == 'en'
                      ? 'Avg Speed' : 'Vitesse moy.',
                  color:   const Color(0xFF10B981),
                  loading: _isLoading || _isLoadingStats,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String   value,
    required String   label,
    required Color    color,
    required bool     loading,
  }) {
    return Container(
      padding: EdgeInsets.all(AppSizes.spacingM),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border:       Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:        color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          SizedBox(width: AppSizes.spacingS),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                loading
                    ? Container(
                  height: 14,
                  width:  60,
                  decoration: BoxDecoration(
                    color:        Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                )
                    : Text(
                  value,
                  style: AppTypography.body1.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize:   15,
                    color:      color,
                  ),
                  maxLines:  1,
                  overflow:  TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    color:    AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.spacingL,
        vertical:   AppSizes.spacingM,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon:        const Icon(Icons.arrow_back_rounded, size: 22),
            padding:     EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          SizedBox(width: AppSizes.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedLanguage == 'en'
                      ? 'Trip History'
                      : 'Historique des trajets',
                  style: AppTypography.h3.copyWith(fontSize: 18),
                ),
                Text(
                  _getFilterDisplayText(),
                  style: AppTypography.caption.copyWith(
                    color:      isOffline
                        ? const Color(0xFFF59E0B)
                        : AppColors.primary,
                    fontSize:   10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Opacity(
            opacity: isOffline ? 0.5 : 1.0,
            child: IconButton(
              onPressed: isOffline ? null : _toggleFilters,
              icon: Icon(
                Icons.tune_rounded,
                color: _showFilters ? AppColors.primary : AppColors.black,
                size:  22,
              ),
              padding:     EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TRACKING DISABLED BANNER
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTrackingDisabledBanner() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSizes.spacingM),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(
              color: AppColors.warning.withOpacity(0.3), width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.info_outline_rounded,
                color: AppColors.warning, size: 18),
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
                    fontSize:   13,
                    color:      AppColors.warning,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _selectedLanguage == 'en'
                      ? 'New trips will not be recorded'
                      : 'Les nouveaux trajets ne seront pas enregistrés',
                  style: AppTypography.caption
                      .copyWith(fontSize: 11, color: AppColors.textSecondary),
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
                vertical:   AppSizes.spacingS,
              ),
              backgroundColor: AppColors.warning.withOpacity(0.1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusS)),
            ),
            child: Text(
              _selectedLanguage == 'en' ? 'Enable' : 'Activer',
              style: AppTypography.caption
                  .copyWith(fontWeight: FontWeight.w700, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FILTER SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFilterSection() {
    return Opacity(
      opacity: isOffline ? 0.5 : 1.0,
      child: Container(
        color: AppColors.white,
        padding: EdgeInsets.all(AppSizes.spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 1),
            SizedBox(height: AppSizes.spacingM),
            Row(
              children: [
                Text(
                  _selectedLanguage == 'en'
                      ? 'Filter by Date'
                      : 'Filtrer par date',
                  style: AppTypography.subtitle1.copyWith(fontSize: 14),
                ),
                if (isOffline) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.cloud_off_rounded,
                      size: 16, color: Color(0xFFF59E0B)),
                ],
              ],
            ),
            SizedBox(height: AppSizes.spacingM),
            Wrap(
              spacing:    AppSizes.spacingS,
              runSpacing: AppSizes.spacingS,
              children: [
                _buildFilterChip(
                  label: _selectedLanguage == 'en' ? 'Today'      : 'Aujourd\'hui',
                  icon:  Icons.today_rounded,
                  value: 'today',
                ),
                _buildFilterChip(
                  label: _selectedLanguage == 'en' ? 'Yesterday'  : 'Hier',
                  icon:  Icons.calendar_today_rounded,
                  value: 'yesterday',
                ),
                _buildFilterChip(
                  label: _selectedLanguage == 'en' ? 'This Week'  : 'Cette semaine',
                  icon:  Icons.date_range_rounded,
                  value: 'week',
                ),
                _buildFilterChip(
                  label: _selectedLanguage == 'en' ? 'This Month' : 'Ce mois',
                  icon:  Icons.calendar_month_rounded,
                  value: 'month',
                ),
              ],
            ),
            SizedBox(height: AppSizes.spacingM),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isOffline ? null : _showCustomDatePicker,
                icon:  const Icon(Icons.event_rounded, size: 18),
                label: Text(
                  _selectedFilter == 'custom' && _customStartDate != null
                      ? '${DateFormat('MMM dd, yyyy').format(_customStartDate!)} - '
                      '${DateFormat('MMM dd, yyyy').format(_customEndDate!)}'
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
                      borderRadius: BorderRadius.circular(AppSizes.radiusM)),
                  padding: EdgeInsets.symmetric(
                      horizontal: AppSizes.spacingM, vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BODY
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_trips.isEmpty) return _buildEmptyState();

    // Show "load more" only when a date filter is active (not in recent view)
    final showLoadMore =
        _hasMoreTrips && _selectedFilter != null && _selectedFilter != 'recent';

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color:     AppColors.primary,
      child: ListView.builder(
        padding:   EdgeInsets.all(AppSizes.spacingM),
        itemCount: _trips.length + (showLoadMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _trips.length && showLoadMore) {
            return _buildSeeMoreButton();
          }

          final trip     = _trips[index];
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
                      left:   AppSizes.spacingS,
                      bottom: AppSizes.spacingS),
                  child: Text(
                    _formatDateShort(trip['startTime']),
                    style: AppTypography.body1.copyWith(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
              _buildTripCard(trip),
              SizedBox(height: AppSizes.spacingS),
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TRIP CARD
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTripCard(Map<String, dynamic> trip) {
    return Container(
      decoration: BoxDecoration(
        color:        AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border:       Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.all(AppSizes.spacingM),
          child: Row(
            children: [
              // Start time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle)),
                      SizedBox(width: AppSizes.spacingXS),
                      Text(
                        _selectedLanguage == 'en' ? 'Start' : 'Début',
                        style: AppTypography.caption.copyWith(
                            color:      AppColors.success,
                            fontWeight: FontWeight.w600,
                            fontSize:   10),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(_formatTime(trip['startTime']),
                        style: AppTypography.body1.copyWith(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
              ),
              // Divider
              Container(
                width: 1, height: 30, color: AppColors.border,
                margin: EdgeInsets.symmetric(horizontal: AppSizes.spacingM),
              ),
              // End time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle)),
                      SizedBox(width: AppSizes.spacingXS),
                      Text(
                        _selectedLanguage == 'en' ? 'Stop' : 'Arrêt',
                        style: AppTypography.caption.copyWith(
                            color:      AppColors.error,
                            fontWeight: FontWeight.w600,
                            fontSize:   10),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(_formatTime(trip['endTime']),
                        style: AppTypography.body1.copyWith(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
              ),
              // Duration chip
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: AppSizes.spacingS, vertical: 4),
                decoration: BoxDecoration(
                  color:        AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppSizes.radiusS),
                ),
                child: Text(
                  _getTripDuration(trip),
                  style: AppTypography.caption.copyWith(
                      color:      AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize:   11),
                ),
              ),
              SizedBox(width: AppSizes.spacingS),
              // View button
              InkWell(
                onTap:         () => _viewTripOnMap(trip),
                borderRadius:  BorderRadius.circular(AppSizes.radiusS),
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: AppSizes.spacingM,
                      vertical:   AppSizes.spacingS),
                  decoration: BoxDecoration(
                    color:        AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSizes.radiusS),
                  ),
                  child: Text(
                    _selectedLanguage == 'en' ? 'View' : 'Voir',
                    style: AppTypography.caption.copyWith(
                        color:      AppColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize:   11),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEE MORE BUTTON
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSeeMoreButton() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSizes.spacingM),
      child: Center(
        child: _isLoadingMore
            ? SizedBox(
          height: 40, width: 40,
          child: CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 3),
        )
            : OutlinedButton.icon(
          onPressed: _loadMoreTrips,
          icon:  const Icon(Icons.expand_more_rounded, size: 20),
          label: Text(
            _selectedLanguage == 'en'
                ? 'See More Trips'
                : 'Voir plus de trajets',
            style: AppTypography.body2
                .copyWith(fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side:    BorderSide(color: AppColors.primary, width: 2),
            padding: EdgeInsets.symmetric(
                horizontal: AppSizes.spacingL,
                vertical:   AppSizes.spacingM),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusM)),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FILTER CHIP
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFilterChip({
    required String   label,
    required IconData icon,
    required String   value,
  }) {
    final isSelected = _selectedFilter == value;
    return InkWell(
      onTap: isOffline ? null : () => _onFilterSelected(value),
      borderRadius: BorderRadius.circular(AppSizes.radiusL),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: AppSizes.spacingM,
            vertical:   AppSizes.spacingS + 2),
        decoration: BoxDecoration(
          color:        isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size:  16,
                color: isSelected
                    ? AppColors.white
                    : AppColors.textSecondary),
            SizedBox(width: AppSizes.spacingXS),
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color:      isSelected
                    ? AppColors.white
                    : AppColors.textSecondary,
                fontWeight: isSelected
                    ? FontWeight.w700
                    : FontWeight.w600,
                fontSize:   12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EMPTY STATE
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    if (isOffline && _trips.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(AppSizes.spacingXL),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(AppSizes.spacingL),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_off_rounded,
                    size: 48, color: Color(0xFFF59E0B)),
              ),
              SizedBox(height: AppSizes.spacingL),
              Text(
                _selectedLanguage == 'en'
                    ? 'You\'re Offline'
                    : 'Vous êtes hors ligne',
                style: AppTypography.h3
                    .copyWith(color: AppColors.black, fontSize: 18),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSizes.spacingS),
              Text(
                _selectedLanguage == 'en'
                    ? 'No cached trips available. Connect to internet to view trip history.'
                    : 'Aucun trajet en cache. Connectez-vous à Internet pour voir l\'historique.',
                style: AppTypography.body2.copyWith(
                    color:  AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

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
                child: Icon(Icons.block_rounded,
                    size: 48, color: AppColors.warning),
              ),
              SizedBox(height: AppSizes.spacingL),
              Text(
                _selectedLanguage == 'en'
                    ? 'Trip Tracking Disabled'
                    : 'Suivi des trajets désactivé',
                style: AppTypography.h3
                    .copyWith(color: AppColors.black, fontSize: 18),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSizes.spacingS),
              Text(
                _selectedLanguage == 'en'
                    ? 'You won\'t see any trips here because trip tracking is currently turned off.'
                    : 'Vous ne verrez aucun trajet ici car le suivi des trajets est actuellement désactivé.',
                style: AppTypography.body2.copyWith(
                    color:    AppColors.textSecondary,
                    fontSize: 13,
                    height:   1.5),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSizes.spacingL),
              ElevatedButton.icon(
                onPressed: _goToSettings,
                icon:  const Icon(Icons.settings_rounded, size: 18),
                label: Text(_selectedLanguage == 'en'
                    ? 'Go to Settings'
                    : 'Aller aux paramètres'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: AppColors.white,
                  padding: EdgeInsets.symmetric(
                      horizontal: AppSizes.spacingL,
                      vertical:   AppSizes.spacingM),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusM)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Empty for the selected filter
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSizes.spacingXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.route_outlined,
                size:  64,
                color: AppColors.textSecondary.withOpacity(0.5)),
            SizedBox(height: AppSizes.spacingL),
            Text(
              _selectedLanguage == 'en'
                  ? 'No trips found'
                  : 'Aucun trajet trouvé',
              style: AppTypography.h3
                  .copyWith(color: AppColors.textSecondary),
            ),
            SizedBox(height: AppSizes.spacingS),
            Text(
              _selectedLanguage == 'en'
                  ? 'No trips found for ${_getFilterDisplayText().toLowerCase()}'
                  : 'Aucun trajet trouvé pour ${_getFilterDisplayText().toLowerCase()}',
              style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}