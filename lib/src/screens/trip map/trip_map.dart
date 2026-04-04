// lib/src/screens/trips/trip_map_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/utility/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/cache_service.dart';
import '../../widgets/offline_barner.dart';
import '../../widgets/subscription_upgrade_sheet.dart';

class TripMapScreen extends StatefulWidget {
  final int tripId;
  final int vehicleId;

  const TripMapScreen({
    Key? key,
    required this.tripId,
    required this.vehicleId,
  }) : super(key: key);

  @override
  State<TripMapScreen> createState() => _TripMapScreenState();
}

class _TripMapScreenState extends State<TripMapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final ConnectivityService _connectivityService = ConnectivityService();
  final CacheService _cacheService = CacheService();

  bool get isOnline  => _connectivityService.isOnline;
  bool get isOffline => _connectivityService.isOffline;

  // ── Loading state ──────────────────────────────────────────────────────────
  bool    _isLoading         = true;
  bool    _isRefreshing      = false;
  String? _errorMessage;
  bool    _isLoadedFromCache = false;

  // ── Trip data ──────────────────────────────────────────────────────────────
  Map<String, dynamic>? _tripData;

  // ── Map data ───────────────────────────────────────────────────────────────
  Set<Marker>   _markers   = {};
  Set<Polyline> _polylines = {};

  LatLng?       _startLocation;
  LatLng?       _endLocation;
  List<LatLng>  _routePoints = [];

  // ── Metadata ───────────────────────────────────────────────────────────────
  bool _isSnappedToRoads = false;

  // ── Map type ───────────────────────────────────────────────────────────────
  MapType _currentMapType  = MapType.normal;
  bool    _showMapTypeMenu = false;

  // ── Playback ───────────────────────────────────────────────────────────────
  bool    _isPlaying                = false;
  double  _currentPlaybackPosition  = 0.0;
  Timer?  _playbackTimer;
  double  _playbackSpeed            = 1.0;
  bool    _showPlaybackControls     = false;
  LatLng? _currentVehiclePosition;

  static const double _defaultZoom = 15.0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadTripData();
    _connectivityService.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _connectivityService.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (!mounted) return;
    setState(() {});
    if (isOnline && _isLoadedFromCache) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.wifi_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Back online! Pull down to refresh route.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ]),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _loadTripData() async {
    setState(() {
      _isLoading    = true;
      _errorMessage = null;
    });

    if (isOffline) {
      await _loadTripFromCache();
      return;
    }

    try {
      debugPrint("📡 Fetching trip ${widget.tripId} with road-following route...");

      // ✅ ApiService attaches the Authorization header automatically —
      //    this is the fix for the 401 that raw http.get caused.
      final data = await ApiService.get(
        '/trips/${widget.tripId}/details-with-route',
        queryParams: {'snapToRoads': 'true'},
      );

      if (data['success'] == true && data['data'] != null) {
        final trip      = data['data']['trip']      as Map<String, dynamic>;
        final waypoints = data['data']['waypoints'] as List;
        final metadata  = data['data']['metadata']  as Map<String, dynamic>?;

        debugPrint("✅ Trip loaded: ${trip['id']}");
        debugPrint("📍 Waypoints received: ${waypoints.length}");
        debugPrint("🗺️ Road-snapped: ${metadata?['isSnappedToRoads'] ?? false}");

        if (waypoints.isEmpty) {
          setState(() {
            _isLoading    = false;
            _errorMessage = "No route data available for this trip";
          });
          return;
        }

        setState(() {
          _tripData          = trip;
          _isSnappedToRoads  = metadata?['isSnappedToRoads'] ?? false;
          _isLoadedFromCache = false;
          final isFallback   = metadata?['isFallback'] ?? false;  // ← ADD THIS

          _startLocation = LatLng(
            (trip['startLocation']['latitude']  as num).toDouble(),
            (trip['startLocation']['longitude'] as num).toDouble(),
          );
          _endLocation = LatLng(
            (trip['endLocation']['latitude']  as num).toDouble(),
            (trip['endLocation']['longitude'] as num).toDouble(),
          );

          _routePoints = waypoints.map((wp) => LatLng(
            (wp['latitude']  as num).toDouble(),
            (wp['longitude'] as num).toDouble(),
          )).toList();

          _currentVehiclePosition =
          _routePoints.isNotEmpty ? _routePoints.first : null;
        });

        _buildMarkersAndPolylines();
        setState(() => _isLoading = false);

        await Future.delayed(const Duration(milliseconds: 300));
        _fitMapToRoute();

        if (_isSnappedToRoads && mounted) {

          // ── Fallback notice ───────────────────────────────────────────────
          if ((metadata?['isFallback'] ?? false) && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(children: [
                  Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'GPS data unavailable — showing straight line only',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ]),
                backgroundColor: const Color(0xFFF59E0B),
                behavior:        SnackBarBehavior.floating,
                duration:        const Duration(seconds: 4),
                shape:  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
              ),
            );
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '✅ Route follows roads (${_routePoints.length} points)',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ]),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      } else {
        setState(() {
          _isLoading    = false;
          _errorMessage = "Failed to load trip data";
        });
      }
    } on FeatureNotSubscribedException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        SubscriptionUpgradeSheet.show(context, feature: e.feature);
      }
    } catch (error) {
      debugPrint("🔥 Error loading trip data: $error");
      if (mounted) {
        setState(() {
          _isLoading    = false;
          _errorMessage = "Failed to load trip: $error";
        });
      }
    }
  }

  Future<void> _loadTripFromCache() async {
    try {
      final cachedTrips = await _cacheService.getCachedTrips(widget.vehicleId);

      if (cachedTrips == null || cachedTrips.isEmpty) {
        setState(() {
          _isLoading    = false;
          _errorMessage = "No cached data available for this trip";
        });
        return;
      }

      final trip = cachedTrips.firstWhere(
            (t) => t['id'] == widget.tripId,
        orElse: () => {},
      );

      if (trip.isEmpty) {
        setState(() {
          _isLoading    = false;
          _errorMessage = "This trip is not available offline";
        });
        return;
      }

      setState(() {
        _tripData = {
          'id':                trip['id'],
          'totalDistanceKm':   trip['totalDistanceKm']   ?? 0,
          'durationFormatted': trip['durationFormatted'] ?? 'N/A',
          'avgSpeedKmh':       trip['avgSpeedKmh']       ?? 0,
          'startTime':         trip['startTime'],
          'endTime':           trip['endTime'],
          'startLocation': {
            'latitude':  trip['startLatitude'],
            'longitude': trip['startLongitude'],
            'address':   trip['startAddress'] ?? 'Start Location',
          },
          'endLocation': {
            'latitude':  trip['endLatitude'],
            'longitude': trip['endLongitude'],
            'address':   trip['endAddress'] ?? 'End Location',
          },
        };

        _startLocation = LatLng(
          (trip['startLatitude']  as num).toDouble(),
          (trip['startLongitude'] as num).toDouble(),
        );
        _endLocation = LatLng(
          (trip['endLatitude']  as num).toDouble(),
          (trip['endLongitude'] as num).toDouble(),
        );

        _routePoints            = [_startLocation!, _endLocation!];
        _currentVehiclePosition = _routePoints.first;
        _isLoadedFromCache      = true;
        _isSnappedToRoads       = false;
      });

      _buildMarkersAndPolylines();
      setState(() => _isLoading = false);

      await Future.delayed(const Duration(milliseconds: 300));
      _fitMapToRoute();
    } catch (e) {
      debugPrint('❌ Error loading trip from cache: $e');
      setState(() {
        _isLoading    = false;
        _errorMessage = "Error loading cached trip: $e";
      });
    }
  }

  Future<void> _handleRefresh() async {
    if (isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Cannot refresh while offline',
                  style: TextStyle(color: Colors.white)),
            ),
          ]),
          backgroundColor: const Color(0xFFF59E0B),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape:  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() => _isRefreshing = true);
    await _loadTripData();
    if (mounted) {
      setState(() => _isRefreshing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            Icon(Icons.check_circle, color: AppColors.white, size: 20),
            SizedBox(width: AppSizes.spacingM),
            Text('Trip map refreshed',
                style: AppTypography.body2.copyWith(color: AppColors.white)),
          ]),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusM)),
          margin: EdgeInsets.all(AppSizes.spacingM),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ── Map helpers ────────────────────────────────────────────────────────────

  void _buildMarkersAndPolylines() {
    _markers.clear();
    _polylines.clear();

    if (_startLocation == null || _endLocation == null) return;

    _markers.add(Marker(
      markerId: const MarkerId('start'),
      position: _startLocation!,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(
        title:   'Start',
        snippet: _displayAddress(
            _tripData?['startLocation']['address'], _startLocation),
      ),
    ));

    _markers.add(Marker(
      markerId: const MarkerId('end'),
      position: _endLocation!,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(
        title:   'Destination',
        snippet: _displayAddress(
            _tripData?['endLocation']['address'], _endLocation),
      ),
    ));

    if (_routePoints.isNotEmpty) {
      final color = _isLoadedFromCache
          ? const Color(0xFFF59E0B)
          : (_isSnappedToRoads ? AppColors.primary : AppColors.success);

      _polylines.add(Polyline(
        polylineId: const PolylineId('main_route'),
        points:     _routePoints,
        color:      color,
        width:      5,
        geodesic:   true,
        startCap:   Cap.roundCap,
        endCap:     Cap.roundCap,
        jointType:  JointType.round,
      ));
    }

    setState(() {});
  }

  void _updateMarkersForPlayback() {
    _markers.clear();
    _polylines.clear();

    if (_startLocation == null || _endLocation == null) return;

    _markers.add(Marker(
      markerId: const MarkerId('start'),
      position: _startLocation!,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(
        title:   'Start',
        snippet: _displayAddress(
            _tripData?['startLocation']['address'], _startLocation),
      ),
    ));

    _markers.add(Marker(
      markerId: const MarkerId('end'),
      position: _endLocation!,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(
        title:   'Destination',
        snippet: _displayAddress(
            _tripData?['endLocation']['address'], _endLocation),
      ),
    ));

    if (_currentVehiclePosition != null) {
      _markers.add(Marker(
        markerId:  const MarkerId('vehicle'),
        position:  _currentVehiclePosition!,
        icon:      BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueBlue),
        anchor:    const Offset(0.5, 0.5),
        rotation:  _calculateBearing(),
        infoWindow: InfoWindow(
          title:   'Current Position',
          snippet: '${_tripData?['avgSpeedKmh'] ?? 0} km/h',
        ),
      ));
    }

    final currentIndex = _currentPlaybackPosition.floor();

    if (currentIndex > 0) {
      _polylines.add(Polyline(
        polylineId: const PolylineId('completed_route'),
        points:     _routePoints.sublist(0, currentIndex + 1),
        color:      AppColors.success,
        width:      5,
        geodesic:   true,
        startCap:   Cap.roundCap,
        endCap:     Cap.roundCap,
        jointType:  JointType.round,
      ));
    }

    if (currentIndex < _routePoints.length - 1) {
      _polylines.add(Polyline(
        polylineId: const PolylineId('remaining_route'),
        points:     _routePoints.sublist(currentIndex),
        color:      AppColors.border,
        width:      4,
        geodesic:   true,
        startCap:   Cap.roundCap,
        endCap:     Cap.roundCap,
        jointType:  JointType.round,
      ));
    }

    setState(() {});
  }

  Future<void> _fitMapToRoute() async {
    if (_routePoints.isEmpty) return;
    try {
      final controller = await _controller.future;

      double minLat = _routePoints.first.latitude;
      double maxLat = _routePoints.first.latitude;
      double minLng = _routePoints.first.longitude;
      double maxLng = _routePoints.first.longitude;

      for (final p in _routePoints) {
        if (p.latitude  < minLat) minLat = p.latitude;
        if (p.latitude  > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          80,
        ),
      );
    } catch (e) {
      debugPrint("⚠️ Error fitting map: $e");
    }
  }

  Future<void> _zoomIn() async {
    final c = await _controller.future;
    c.animateCamera(CameraUpdate.zoomIn());
  }

  Future<void> _zoomOut() async {
    final c = await _controller.future;
    c.animateCamera(CameraUpdate.zoomOut());
  }

  void _changeMapType(MapType type) =>
      setState(() { _currentMapType = type; _showMapTypeMenu = false; });

  // ── Playback ───────────────────────────────────────────────────────────────

  void _togglePlayback() {
    if (_routePoints.isEmpty) return;
    setState(() {
      _isPlaying            = !_isPlaying;
      _showPlaybackControls = true;
      _currentVehiclePosition ??=
      _routePoints.isNotEmpty ? _routePoints.first : null;
    });
    _updateMarkersForPlayback();
    _isPlaying ? _startPlayback() : _pausePlayback();
  }

  void _startPlayback() {
    _playbackTimer?.cancel();

    const baseInterval = 16; // ~60 FPS
    final interval = (baseInterval / _playbackSpeed).round();
    final stepSize = (_routePoints.length / (30.0 / _playbackSpeed)) /
        (1000 / baseInterval);

    _playbackTimer =
        Timer.periodic(Duration(milliseconds: interval), (timer) {
          if (_currentPlaybackPosition < _routePoints.length - 1) {
            setState(() {
              _currentPlaybackPosition += stepSize;
              if (_currentPlaybackPosition >= _routePoints.length - 1) {
                _currentPlaybackPosition = (_routePoints.length - 1).toDouble();
              }
              _currentVehiclePosition =
                  _interpolatedPosition(_currentPlaybackPosition);
            });
            _updateMarkersForPlayback();
            if (timer.tick % 3 == 0) _moveCameraToVehicle(smooth: true);
          } else {
            _pausePlayback();
            setState(() => _isPlaying = false);
          }
        });
  }

  void _pausePlayback() => _playbackTimer?.cancel();

  void _resetPlayback() {
    _pausePlayback();
    setState(() {
      _currentPlaybackPosition = 0.0;
      _isPlaying               = false;
      _currentVehiclePosition  =
      _routePoints.isNotEmpty ? _routePoints.first : null;
    });
    _updateMarkersForPlayback();
    _moveCameraToVehicle(smooth: false);
  }

  void _changePlaybackSpeed() {
    setState(() {
      _playbackSpeed =
      _playbackSpeed == 1.0 ? 2.0 : _playbackSpeed == 2.0 ? 4.0 : 1.0;
    });
    if (_isPlaying) {
      _pausePlayback();
      _startPlayback();
    }
  }

  void _onSliderChanged(double value) {
    _pausePlayback();
    setState(() {
      _isPlaying               = false;
      _currentPlaybackPosition = value;
      _currentVehiclePosition  = _interpolatedPosition(value);
    });
    _updateMarkersForPlayback();
    _moveCameraToVehicle(smooth: false);
  }

  LatLng _interpolatedPosition(double position) {
    if (position <= 0) return _routePoints.first;
    if (position >= _routePoints.length - 1) return _routePoints.last;

    final index    = position.floor();
    final fraction = position - index;
    if (index >= _routePoints.length - 1) return _routePoints.last;

    final from = _routePoints[index];
    final to   = _routePoints[index + 1];
    return LatLng(
      from.latitude  + (to.latitude  - from.latitude)  * fraction,
      from.longitude + (to.longitude - from.longitude) * fraction,
    );
  }

  double _calculateBearing() {
    if (_routePoints.length < 2 || _currentPlaybackPosition < 1) return 0.0;
    final idx = _currentPlaybackPosition.floor();
    if (idx >= _routePoints.length - 1) return 0.0;

    final from = _routePoints[idx];
    final to   = _routePoints[idx + 1];
    final lat1 = from.latitude  * math.pi / 180;
    final lat2 = to.latitude    * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y    = math.sin(dLng) * math.cos(lat2);
    final x    = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  Future<void> _moveCameraToVehicle({bool smooth = true}) async {
    if (_currentVehiclePosition == null) return;
    try {
      final c = await _controller.future;
      final update = CameraUpdate.newCameraPosition(CameraPosition(
        target:  _currentVehiclePosition!,
        zoom:    17.0,
        tilt:    45.0,
        bearing: _calculateBearing(),
      ));
      smooth ? await c.animateCamera(update) : await c.moveCamera(update);
    } catch (e) {
      debugPrint("⚠️ Camera move error: $e");
    }
  }

  // ── Formatters ─────────────────────────────────────────────────────────────

  String _displayAddress(String? address, LatLng? coords) {
    if (address == null || address.isEmpty || address == 'Geocoding...') {
      return coords != null
          ? '${coords.latitude.toStringAsFixed(4)}°,'
          ' ${coords.longitude.toStringAsFixed(4)}°'
          : 'Unknown location';
    }
    // If it looks like raw coordinates, show them formatted
    final parts = address.split(',');
    if (parts.every((p) => double.tryParse(p.trim()) != null)) {
      return coords != null
          ? '${coords.latitude.toStringAsFixed(4)}°,'
          ' ${coords.longitude.toStringAsFixed(4)}°'
          : address;
    }
    return address;
  }

  String _formatTime(String? ds) {
    if (ds == null) return 'N/A';
    try {
      final d      = DateTime.parse(ds).toLocal();
      final hour   = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
      final minute = d.minute.toString().padLeft(2, '0');
      final period = d.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    } catch (_) {
      return 'Invalid time';
    }
  }

  String _getCurrentTime() {
    if (_tripData == null || _routePoints.isEmpty) return '--:--';
    try {
      final start    = DateTime.parse(_tripData!['startTime']);
      final end      = DateTime.parse(_tripData!['endTime']);
      final total    = end.difference(start).inSeconds;
      final progress = _currentPlaybackPosition / (_routePoints.length - 1);
      final current  =
      start.add(Duration(seconds: (total * progress).round()));
      return _formatTime(current.toIso8601String());
    } catch (_) {
      return '--:--';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: _isLoading
          ? _buildLoading()
          : _errorMessage != null
          ? _buildError()
          : Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _startLocation ??
                  const LatLng(3.8480, 11.5021),
              zoom: _defaultZoom,
            ),
            markers:              _markers,
            polylines:            _polylines,
            mapType:              _currentMapType,
            onMapCreated: (c) {
              if (!_controller.isCompleted) _controller.complete(c);
            },
            myLocationEnabled:       false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled:     false,
            mapToolbarEnabled:       false,
          ),

          const OfflineBanner(),
          _buildTopBar(),
          _buildFloatingControls(),

          if (_showPlaybackControls)
            _buildPlaybackControls()
          else
            _buildBottomCard(),

          if (_isRefreshing)
            Positioned(
              top: 120, left: 0, right: 0,
              child: Center(child: _buildRefreshingPill()),
            ),
        ],
      ),
    );
  }

  // ── Loading / error states ─────────────────────────────────────────────────

  Widget _buildLoading() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
        SizedBox(height: AppSizes.spacingM),
        Text(
          isOffline
              ? 'Loading cached route...'
              : 'Loading road-following route...',
          style: AppTypography.body2,
        ),
      ],
    ),
  );

  Widget _buildError() => Center(
    child: Padding(
      padding: EdgeInsets.all(AppSizes.spacingXL + 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(AppSizes.spacingXL),
            decoration: BoxDecoration(
              color: isOffline
                  ? const Color(0xFFF59E0B).withOpacity(0.1)
                  : AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isOffline
                  ? Icons.cloud_off_rounded
                  : Icons.error_outline_rounded,
              size:  80,
              color: isOffline
                  ? const Color(0xFFF59E0B)
                  : AppColors.primary.withOpacity(0.5),
            ),
          ),
          SizedBox(height: AppSizes.spacingL),
          Text(
            isOffline ? 'Trip Not Available Offline' : 'Failed to Load Trip',
            style: AppTypography.h3,
          ),
          SizedBox(height: AppSizes.spacingM),
          Text(
            _errorMessage ?? 'Unknown error occurred',
            textAlign: TextAlign.center,
            style: AppTypography.body2.copyWith(height: 1.5),
          ),
          SizedBox(height: AppSizes.spacingXL),
          ElevatedButton.icon(
            onPressed: isOffline ? null : _loadTripData,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusM)),
              padding: EdgeInsets.symmetric(
                  horizontal: AppSizes.spacingL,
                  vertical:   AppSizes.spacingM + 2),
              elevation: 0,
            ),
            icon:  Icon(Icons.refresh, color: AppColors.black),
            label: Text(
              isOffline ? 'No Internet' : 'Retry',
              style: AppTypography.button.copyWith(color: AppColors.black),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildRefreshingPill() => Container(
    padding: EdgeInsets.symmetric(
        horizontal: AppSizes.spacingL, vertical: AppSizes.spacingM),
    decoration: BoxDecoration(
      color:        AppColors.white,
      borderRadius: BorderRadius.circular(AppSizes.radiusL),
      boxShadow: [
        BoxShadow(
          color:     AppColors.black.withOpacity(0.1),
          blurRadius: 20,
          offset:    const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.primary),
        ),
        SizedBox(width: AppSizes.spacingM),
        Text(
          'Refreshing map...',
          style: AppTypography.body2.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: SafeArea(
        child: Container(
          margin: EdgeInsets.all(AppSizes.spacingM),
          padding: EdgeInsets.symmetric(
              horizontal: AppSizes.spacingS,
              vertical:   AppSizes.spacingS),
          decoration: BoxDecoration(
            color:        AppColors.white,
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            boxShadow: [
              BoxShadow(
                color:     AppColors.black.withOpacity(0.1),
                blurRadius: 20,
                offset:    const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Back
              IconButton(
                onPressed:   () => Navigator.pop(context),
                icon:        Icon(Icons.arrow_back_rounded,
                    color: AppColors.black),
                padding:     EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              SizedBox(width: AppSizes.spacingS),

              // Title + distance/duration
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Trip Route',
                            style: AppTypography.body1
                                .copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_isLoadedFromCache) ...[
                          const SizedBox(width: 6),
                          _badge('OFF', const Color(0xFFF59E0B)),
                        ],
                        if (_isSnappedToRoads && !_isLoadedFromCache) ...[
                          const SizedBox(width: 6),
                          _badge('RD', AppColors.primary,
                              icon: Icons.route, iconSize: 8),
                        ],
                      ],
                    ),
                    if (_tripData != null)
                      Text(
                        '${_tripData!['totalDistanceKm']} km'
                            ' • ${_tripData!['durationFormatted']}',
                        style: AppTypography.caption.copyWith(fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),

              // Play / Pause
              IconButton(
                onPressed:   _togglePlayback,
                icon: Icon(
                  _isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: AppColors.primary,
                  size:  26,
                ),
                padding:     const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip:     _isPlaying ? 'Pause' : 'Play',
              ),
              const SizedBox(width: 4),

              // Refresh
              Opacity(
                opacity: isOffline ? 0.5 : 1.0,
                child: IconButton(
                  onPressed:
                  (isOffline || _isRefreshing) ? null : _handleRefresh,
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: (isOffline || _isRefreshing)
                        ? AppColors.textSecondary.withOpacity(0.5)
                        : AppColors.primary,
                    size: 20,
                  ),
                  padding:     const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  tooltip:     isOffline ? 'Offline' : 'Refresh',
                ),
              ),
              const SizedBox(width: 4),

              // Point count chip
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: (_isLoadedFromCache
                        ? const Color(0xFFF59E0B)
                        : _isSnappedToRoads
                        ? AppColors.primary
                        : AppColors.success)
                        .withOpacity(0.1),
                    borderRadius:
                    BorderRadius.circular(AppSizes.radiusM),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.navigation_rounded,
                        size: 12,
                        color: _isLoadedFromCache
                            ? const Color(0xFFF59E0B)
                            : _isSnappedToRoads
                            ? AppColors.primary
                            : AppColors.success,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${_routePoints.length}',
                          style: AppTypography.caption.copyWith(
                            fontSize:   10,
                            fontWeight: FontWeight.w700,
                            color: _isLoadedFromCache
                                ? const Color(0xFFF59E0B)
                                : _isSnappedToRoads
                                ? AppColors.primary
                                : AppColors.success,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color color,
      {IconData? icon, double iconSize = 8}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: iconSize, color: color),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: AppTypography.caption.copyWith(
              fontSize:   8,
              color:      color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ── Floating controls (layers + zoom) ──────────────────────────────────────

  Widget _buildFloatingControls() {
    return Positioned(
      right: AppSizes.spacingM,
      top:   100,
      child: SafeArea(
        child: Column(
          children: [
            // Layers toggle
            GestureDetector(
              onTap: () =>
                  setState(() => _showMapTypeMenu = !_showMapTypeMenu),
              child: _floatingCircle(
                child: Icon(
                  Icons.layers_rounded,
                  color: _showMapTypeMenu
                      ? AppColors.primary
                      : AppColors.black,
                  size: 22,
                ),
              ),
            ),

            if (_showMapTypeMenu) ...[
              SizedBox(height: AppSizes.spacingS),
              _buildMapTypeMenu(),
            ],

            SizedBox(height: AppSizes.spacingL),

            // Zoom buttons
            Container(
              decoration: BoxDecoration(
                color:        AppColors.white,
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
                boxShadow: [
                  BoxShadow(
                    color:     AppColors.black.withOpacity(0.1),
                    blurRadius: 15,
                    offset:    const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: _zoomIn,
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(AppSizes.radiusM)),
                    child: SizedBox(
                      width: 44, height: 44,
                      child: Icon(Icons.add_rounded,
                          color: AppColors.black, size: 24),
                    ),
                  ),
                  Divider(
                      height: 1, thickness: 1, color: AppColors.border),
                  InkWell(
                    onTap: _zoomOut,
                    borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(AppSizes.radiusM)),
                    child: SizedBox(
                      width: 44, height: 44,
                      child: Icon(Icons.remove_rounded,
                          color: AppColors.black, size: 24),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _floatingCircle({required Widget child}) => Container(
    width:  44,
    height: 44,
    decoration: BoxDecoration(
      color:        AppColors.white,
      borderRadius: BorderRadius.circular(AppSizes.radiusM),
      boxShadow: [
        BoxShadow(
          color:     AppColors.black.withOpacity(0.1),
          blurRadius: 15,
          offset:    const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );

  Widget _buildMapTypeMenu() {
    return Container(
      decoration: BoxDecoration(
        color:        AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        boxShadow: [
          BoxShadow(
            color:     AppColors.black.withOpacity(0.1),
            blurRadius: 15,
            offset:    const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _mapTypeOption(Icons.map_rounded,       'Normal',    MapType.normal),
          Divider(height: 1, thickness: 1, color: AppColors.border),
          _mapTypeOption(Icons.satellite_rounded, 'Satellite', MapType.satellite),
          Divider(height: 1, thickness: 1, color: AppColors.border),
          _mapTypeOption(Icons.terrain_rounded,   'Terrain',   MapType.terrain),
          Divider(height: 1, thickness: 1, color: AppColors.border),
          _mapTypeOption(Icons.layers_outlined,   'Hybrid',    MapType.hybrid),
        ],
      ),
    );
  }

  Widget _mapTypeOption(IconData icon, String label, MapType type) {
    final selected = _currentMapType == type;
    return InkWell(
      onTap: () => _changeMapType(type),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: AppSizes.spacingM,
            vertical:   AppSizes.spacingS + 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary,
                size: 20),
            SizedBox(width: AppSizes.spacingS),
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color:      selected ? AppColors.primary : AppColors.black,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                fontSize:   12,
              ),
            ),
            if (selected) ...[
              SizedBox(width: AppSizes.spacingXS),
              Icon(Icons.check_rounded, color: AppColors.primary, size: 16),
            ],
          ],
        ),
      ),
    );
  }

  // ── Playback panel ─────────────────────────────────────────────────────────

  Widget _buildPlaybackControls() {
    if (_routePoints.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        margin:  EdgeInsets.all(AppSizes.spacingM),
        padding: EdgeInsets.all(AppSizes.spacingL),
        decoration: BoxDecoration(
          color:        AppColors.white,
          borderRadius: BorderRadius.circular(AppSizes.radiusXL),
          boxShadow: [
            BoxShadow(
              color:     AppColors.black.withOpacity(0.15),
              blurRadius: 30,
              offset:    const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Time & speed
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Icon(Icons.access_time,
                      size: 16, color: AppColors.textSecondary),
                  SizedBox(width: AppSizes.spacingXS),
                  Text(
                    _getCurrentTime(),
                    style: AppTypography.body2.copyWith(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ]),
                Row(children: [
                  Icon(Icons.speed, size: 16, color: AppColors.primary),
                  SizedBox(width: AppSizes.spacingXS),
                  Text(
                    '${_tripData?['avgSpeedKmh'] ?? 0} km/h',
                    style: AppTypography.body2.copyWith(
                        color:      AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize:   13),
                  ),
                ]),
              ],
            ),

            SizedBox(height: AppSizes.spacingM),

            // Scrubber
            SliderTheme(
              data: SliderThemeData(
                trackHeight:        4,
                thumbShape:         const RoundSliderThumbShape(
                    enabledThumbRadius: 8),
                overlayShape:       const RoundSliderOverlayShape(
                    overlayRadius: 16),
                activeTrackColor:   AppColors.primary,
                inactiveTrackColor: AppColors.border,
                thumbColor:         AppColors.primary,
                overlayColor:       AppColors.primary.withOpacity(0.2),
              ),
              child: Slider(
                value: _currentPlaybackPosition,
                min:   0,
                max:   (_routePoints.length - 1).toDouble(),
                onChanged: _onSliderChanged,
              ),
            ),

            // Progress labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(_currentPlaybackPosition + 1).floor()}'
                      ' / ${_routePoints.length}',
                  style: AppTypography.caption.copyWith(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
                Text(
                  '${((_currentPlaybackPosition /
                      (_routePoints.length - 1)) *
                      100)
                      .toStringAsFixed(0)}%',
                  style: AppTypography.caption.copyWith(
                      fontSize:   11,
                      fontWeight: FontWeight.w600,
                      color:      AppColors.primary),
                ),
              ],
            ),

            SizedBox(height: AppSizes.spacingM),

            // Buttons row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Reset
                IconButton(
                  onPressed: _resetPlayback,
                  icon: Icon(Icons.replay_rounded,
                      color: AppColors.textSecondary),
                  tooltip: 'Reset',
                ),

                SizedBox(width: AppSizes.spacingL),

                // Play / Pause
                Container(
                  decoration: BoxDecoration(
                    color:  AppColors.primary,
                    shape:  BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:     AppColors.primary.withOpacity(0.3),
                        blurRadius: 12,
                        offset:    const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    onPressed: _togglePlayback,
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: AppColors.white,
                      size:  32,
                    ),
                    iconSize: 32,
                  ),
                ),

                SizedBox(width: AppSizes.spacingL),

                // Speed chip
                InkWell(
                  onTap:        _changePlaybackSpeed,
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: AppSizes.spacingM,
                        vertical:   AppSizes.spacingS),
                    decoration: BoxDecoration(
                      color:        AppColors.background,
                      borderRadius: BorderRadius.circular(AppSizes.radiusM),
                      border:       Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      '${_playbackSpeed.toStringAsFixed(0)}x',
                      style: AppTypography.body2.copyWith(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: AppSizes.spacingS),

            // Close
            TextButton.icon(
              onPressed: () {
                _pausePlayback();
                setState(() {
                  _showPlaybackControls = false;
                  _isPlaying            = false;
                });
                _buildMarkersAndPolylines();
              },
              icon:  Icon(Icons.close, size: 16, color: AppColors.textSecondary),
              label: Text(
                'Close Playback',
                style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom info card ───────────────────────────────────────────────────────

  Widget _buildBottomCard() {
    if (_tripData == null) return const SizedBox.shrink();

    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        margin:  EdgeInsets.all(AppSizes.spacingM),
        padding: EdgeInsets.all(AppSizes.spacingL),
        decoration: BoxDecoration(
          color:        AppColors.white,
          borderRadius: BorderRadius.circular(AppSizes.radiusXL),
          boxShadow: [
            BoxShadow(
              color:     AppColors.black.withOpacity(0.15),
              blurRadius: 30,
              offset:    const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _locationRow(
              icon:      Icons.radio_button_checked_rounded,
              iconColor: AppColors.success,
              title:     'Start',
              address: _displayAddress(
                  _tripData!['startLocation']['address'], _startLocation),
              time:    _formatTime(_tripData!['startTime']),
            ),

            // Connector + stats strip
            Container(
              margin: EdgeInsets.symmetric(vertical: AppSizes.spacingM),
              child: Row(
                children: [
                  SizedBox(width: AppSizes.spacingM),
                  Container(
                    width: 2, height: 30,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin:  Alignment.topCenter,
                        end:    Alignment.bottomCenter,
                        colors: [
                          AppColors.success.withOpacity(0.3),
                          AppColors.error.withOpacity(0.3),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: AppSizes.spacingL),
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: AppSizes.spacingM,
                          vertical:   AppSizes.spacingS),
                      decoration: BoxDecoration(
                        color:        AppColors.background,
                        borderRadius: BorderRadius.circular(AppSizes.radiusM),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statChip(
                            icon:  Icons.straighten_rounded,
                            value: '${_tripData!['totalDistanceKm']} km',
                            color: AppColors.primary,
                          ),
                          Container(
                              width: 1, height: 20,
                              color: AppColors.border),
                          _statChip(
                            icon:  Icons.speed_rounded,
                            value: '${_tripData!['avgSpeedKmh']} km/h',
                            color: AppColors.info,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            _locationRow(
              icon:      Icons.location_on_rounded,
              iconColor: AppColors.error,
              title:     'Destination',
              address: _displayAddress(
                  _tripData!['endLocation']['address'], _endLocation),
              time:    _formatTime(_tripData!['endTime']),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationRow({
    required IconData icon,
    required Color    iconColor,
    required String   title,
    required String   address,
    required String   time,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(AppSizes.spacingS),
          decoration: BoxDecoration(
            color:        iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        SizedBox(width: AppSizes.spacingM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: AppTypography.caption.copyWith(
                      fontSize:     11,
                      fontWeight:   FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    time,
                    style: AppTypography.caption.copyWith(
                      fontSize:   12,
                      color:      AppColors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              SizedBox(height: AppSizes.spacingXS),
              Text(
                address,
                style: AppTypography.caption.copyWith(
                  fontSize:   13,
                  fontWeight: FontWeight.w600,
                  color:      AppColors.black,
                  height:     1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statChip({
    required IconData icon,
    required String   value,
    required Color    color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        SizedBox(width: AppSizes.spacingXS),
        Text(
          value,
          style: AppTypography.caption
              .copyWith(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}