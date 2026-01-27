// lib/src/screens/trips/trip_map_screen.dart - FIXED OVERFLOW + SMOOTH PLAYBACK + ROAD ROUTES
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';
import '../../services/connectivity_service.dart';
import '../../services/cache_service.dart';
import '../../widgets/offline_barner.dart';

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
  bool _isLoadedFromCache = false;

  String get baseUrl => EnvConfig.baseUrl;

  bool get isOnline => _connectivityService.isOnline;
  bool get isOffline => _connectivityService.isOffline;

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  Map<String, dynamic>? _tripData;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  LatLng? _startLocation;
  LatLng? _endLocation;
  List<LatLng> _routePoints = [];
  List<LatLng> _gpsWaypoints = [];

  // Metadata
  int _totalWaypoints = 0;
  int _sampledWaypoints = 0;
  bool _isSampled = false;
  bool _isSnappedToRoads = false; // 🆕 Track if route follows roads

  // Map type control
  MapType _currentMapType = MapType.normal;
  bool _showMapTypeMenu = false;

  // 🎬 SMOOTH PLAYBACK CONTROLS
  bool _isPlaying = false;
  double _currentPlaybackPosition = 0.0; // 🆕 Use double for smooth interpolation
  Timer? _playbackTimer;
  double _playbackSpeed = 1.0; // 1x, 2x, 4x
  bool _showPlaybackControls = false;
  LatLng? _currentVehiclePosition;

  // Default zoom level
  static const double DEFAULT_ZOOM = 15.0;

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
    if (mounted) {
      setState(() {});

      if (isOnline && _isLoadedFromCache) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.wifi_rounded, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Back online! Pull down to refresh route.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  // 🎬 SMOOTH PLAYBACK METHODS

  void _togglePlayback() {
    if (_routePoints.isEmpty) return;

    setState(() {
      _isPlaying = !_isPlaying;
      _showPlaybackControls = true;

      // Initialize vehicle position if not set
      if (_currentVehiclePosition == null && _routePoints.isNotEmpty) {
        _currentVehiclePosition = _routePoints[0];
        _currentPlaybackPosition = 0.0;
      }
    });

    // Update markers immediately to show the blue marker
    _updateMarkersForPlayback();

    if (_isPlaying) {
      _startPlayback();
    } else {
      _pausePlayback();
    }
  }

  void _startPlayback() {
    _playbackTimer?.cancel();

    // 🆕 SMOOTHER: Use 60 FPS for smooth animation
    final baseInterval = 16; // ~60 FPS (16ms per frame)
    final interval = (baseInterval / _playbackSpeed).round();

    // Calculate step size based on route length and desired completion time
    // Adjust this to control overall playback speed
    final stepsPerSecond = 1000 / baseInterval;
    final stepSize = (_routePoints.length / (30.0 / _playbackSpeed)) / stepsPerSecond; // Complete in ~30 seconds

    _playbackTimer = Timer.periodic(Duration(milliseconds: interval), (timer) {
      if (_currentPlaybackPosition < _routePoints.length - 1) {
        setState(() {
          _currentPlaybackPosition += stepSize;
          if (_currentPlaybackPosition >= _routePoints.length - 1) {
            _currentPlaybackPosition = _routePoints.length - 1;
          }

          // 🆕 INTERPOLATE between points for smooth movement
          _currentVehiclePosition = _getInterpolatedPosition(_currentPlaybackPosition);
        });

        _updateMarkersForPlayback();

        // 🆕 Only update camera every few frames to reduce jank
        if (timer.tick % 3 == 0) {
          _moveCameraToVehicle(smooth: true);
        }
      } else {
        // Reached end
        _pausePlayback();
        setState(() {
          _isPlaying = false;
        });
      }
    });
  }

  // 🆕 INTERPOLATE position between waypoints for smooth animation
  LatLng _getInterpolatedPosition(double position) {
    if (position <= 0) return _routePoints[0];
    if (position >= _routePoints.length - 1) return _routePoints[_routePoints.length - 1];

    final index = position.floor();
    final fraction = position - index;

    if (index >= _routePoints.length - 1) {
      return _routePoints[_routePoints.length - 1];
    }

    final start = _routePoints[index];
    final end = _routePoints[index + 1];

    // Linear interpolation
    final lat = start.latitude + (end.latitude - start.latitude) * fraction;
    final lng = start.longitude + (end.longitude - start.longitude) * fraction;

    return LatLng(lat, lng);
  }

  void _pausePlayback() {
    _playbackTimer?.cancel();
  }

  void _resetPlayback() {
    _pausePlayback();
    setState(() {
      _currentPlaybackPosition = 0.0;
      _isPlaying = false;
      _currentVehiclePosition = _routePoints.isNotEmpty ? _routePoints[0] : null;
    });
    _updateMarkersForPlayback();
    _moveCameraToVehicle(smooth: false);
  }

  void _changePlaybackSpeed() {
    setState(() {
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 2.0;
      } else if (_playbackSpeed == 2.0) {
        _playbackSpeed = 4.0;
      } else {
        _playbackSpeed = 1.0;
      }
    });

    // Restart playback with new speed
    if (_isPlaying) {
      _pausePlayback();
      _startPlayback();
    }
  }

  void _onSliderChanged(double value) {
    _pausePlayback();
    setState(() {
      _isPlaying = false;
      _currentPlaybackPosition = value;
      _currentVehiclePosition = _getInterpolatedPosition(value);
    });
    _updateMarkersForPlayback();
    _moveCameraToVehicle(smooth: false);
  }

  Future<void> _moveCameraToVehicle({bool smooth = true}) async {
    if (_currentVehiclePosition == null) return;

    try {
      final controller = await _controller.future;

      if (smooth) {
        // Smooth camera movement
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: _currentVehiclePosition!,
              zoom: 17.0,
              tilt: 45.0,
              bearing: _calculateBearing(),
            ),
          ),
        );
      } else {
        // Instant camera movement
        await controller.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: _currentVehiclePosition!,
              zoom: 17.0,
              tilt: 45.0,
              bearing: _calculateBearing(),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("⚠️ Error moving camera: $e");
    }
  }

  // 🆕 Calculate bearing for camera rotation based on movement direction
  double _calculateBearing() {
    if (_routePoints.length < 2 || _currentPlaybackPosition < 1) return 0.0;

    final currentIndex = _currentPlaybackPosition.floor();
    if (currentIndex >= _routePoints.length - 1) return 0.0;

    final from = _routePoints[currentIndex];
    final to = _routePoints[currentIndex + 1];

    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final lng1 = from.longitude * math.pi / 180;
    final lng2 = to.longitude * math.pi / 180;

    final dLng = lng2 - lng1;

    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

    final bearing = math.atan2(y, x);
    return (bearing * 180 / math.pi + 360) % 360;
  }

  void _updateMarkersForPlayback() {
    _markers.clear();
    _polylines.clear();

    if (_startLocation == null || _endLocation == null) return;

    // Start marker (green)
    _markers.add(
      Marker(
        markerId: const MarkerId('start'),
        position: _startLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Start',
          snippet: _getDisplayAddress(_tripData?['startLocation']['address'], _startLocation),
        ),
      ),
    );

    // End marker (red)
    _markers.add(
      Marker(
        markerId: const MarkerId('end'),
        position: _endLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Destination',
          snippet: _getDisplayAddress(_tripData?['endLocation']['address'], _endLocation),
        ),
      ),
    );

    // 🚗 Current vehicle position (blue marker)
    if (_currentVehiclePosition != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('vehicle'),
          position: _currentVehiclePosition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          anchor: Offset(0.5, 0.5),
          rotation: _calculateBearing(), // 🆕 Rotate marker based on direction
          infoWindow: InfoWindow(
            title: 'Current Position',
            snippet: _getCurrentSpeed(),
          ),
        ),
      );
    }

    final currentIndex = _currentPlaybackPosition.floor();

    // Completed route (green)
    if (currentIndex > 0) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('completed_route'),
          points: _routePoints.sublist(0, currentIndex + 1),
          color: AppColors.success,
          width: 5,
          geodesic: true,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
    }

    // Remaining route (light gray)
    if (currentIndex < _routePoints.length - 1) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('remaining_route'),
          points: _routePoints.sublist(currentIndex),
          color: AppColors.border,
          width: 4,
          geodesic: true,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
    }

    setState(() {});
  }

  String _getCurrentSpeed() {
    if (_tripData == null) return '0 km/h';
    return '${_tripData!['avgSpeedKmh']} km/h';
  }

  String _getCurrentTime() {
    if (_tripData == null || _routePoints.isEmpty) return '--:--';

    try {
      final startTime = DateTime.parse(_tripData!['startTime']);
      final endTime = DateTime.parse(_tripData!['endTime']);
      final totalDuration = endTime.difference(startTime).inSeconds;

      final progress = _currentPlaybackPosition / (_routePoints.length - 1);
      final currentDuration = (totalDuration * progress).round();

      final currentTime = startTime.add(Duration(seconds: currentDuration));
      return _formatTime(currentTime.toIso8601String());
    } catch (e) {
      return '--:--';
    }
  }

  // Helper method to get proper display address
  String _getDisplayAddress(String? address, LatLng? coordinates) {
    if (address == null || address.isEmpty) {
      if (coordinates != null) {
        return '${coordinates.latitude.toStringAsFixed(4)}°, ${coordinates.longitude.toStringAsFixed(4)}°';
      }
      return 'Unknown location';
    }

    if (address == 'Geocoding...') {
      return 'Loading address...';
    }

    if (address.contains('°') || (address.contains(',') && address.split(',').every((part) => double.tryParse(part.trim()) != null))) {
      if (coordinates != null) {
        return '${coordinates.latitude.toStringAsFixed(4)}°, ${coordinates.longitude.toStringAsFixed(4)}°';
      }
    }

    return address;
  }

  // EXISTING METHODS

  Future<void> _loadTripData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (isOffline) {
        debugPrint("📱 OFFLINE MODE - Loading trip from cache...");
        await _loadTripFromCache();
        return;
      }

      debugPrint("📡 Fetching trip ${widget.tripId} with road-following route...");

      // 🆕 ADD snapToRoads=true parameter
      final response = await http.get(
        Uri.parse("$baseUrl/trips/${widget.tripId}/details-with-route?snapToRoads=true"),
      );

      debugPrint("📡 Trip details response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final trip = data['data']['trip'];
          final waypoints = data['data']['waypoints'] as List;
          final metadata = data['data']['metadata'];

          debugPrint("✅ Trip loaded: ${trip['id']}");
          debugPrint("📍 Waypoints received: ${waypoints.length}");
          debugPrint("🗺️ Road-snapped: ${metadata?['isSnappedToRoads'] ?? false}");

          if (waypoints.isEmpty) {
            setState(() {
              _isLoading = false;
              _errorMessage = "No route data available for this trip";
            });
            return;
          }

          setState(() {
            _tripData = trip;
            _totalWaypoints = metadata?['totalWaypoints'] ?? waypoints.length;
            _sampledWaypoints = metadata?['returnedWaypoints'] ?? waypoints.length;
            _isSampled = metadata?['isSampled'] ?? false;
            _isSnappedToRoads = metadata?['isSnappedToRoads'] ?? false;
            _isLoadedFromCache = false;

            _startLocation = LatLng(
              (trip['startLocation']['latitude'] as num).toDouble(),
              (trip['startLocation']['longitude'] as num).toDouble(),
            );

            _endLocation = LatLng(
              (trip['endLocation']['latitude'] as num).toDouble(),
              (trip['endLocation']['longitude'] as num).toDouble(),
            );

            _routePoints = waypoints.map((wp) {
              return LatLng(
                (wp['latitude'] as num).toDouble(),
                (wp['longitude'] as num).toDouble(),
              );
            }).toList();

            _gpsWaypoints = _routePoints;
            _currentVehiclePosition = _routePoints.isNotEmpty ? _routePoints[0] : null;

            debugPrint("🗺️ Route: ${_routePoints.length} ${_isSnappedToRoads ? '(roads)' : '(GPS)'} points");
          });

          _buildMarkersAndPolylines();

          setState(() {
            _isLoading = false;
          });

          await Future.delayed(const Duration(milliseconds: 300));
          _fitMapToRoute();

          if (_isSnappedToRoads && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '✅ Route follows roads (${_routePoints.length} points)',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: EdgeInsets.all(16),
              ),
            );
          }

          debugPrint("✅ Road-following map loaded!");
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = "Server error: ${response.statusCode}";
        });
      }
    } catch (error) {
      debugPrint("🔥 Error loading trip data: $error");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to load trip: $error";
        });
      }
    }
  }

  Future<void> _loadTripFromCache() async {
    try {
      debugPrint('📦 Loading trip from cache...');

      final cachedTrips = await _cacheService.getCachedTrips(widget.vehicleId);

      if (cachedTrips == null || cachedTrips.isEmpty) {
        setState(() {
          _isLoading = false;
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
          _isLoading = false;
          _errorMessage = "This trip is not available offline";
        });
        return;
      }

      debugPrint('✅ Found cached trip: ${trip['id']}');

      setState(() {
        _tripData = {
          'id': trip['id'],
          'totalDistanceKm': trip['totalDistanceKm'] ?? 0,
          'durationFormatted': trip['durationFormatted'] ?? 'N/A',
          'avgSpeedKmh': trip['avgSpeedKmh'] ?? 0,
          'startTime': trip['startTime'],
          'endTime': trip['endTime'],
          'startLocation': {
            'latitude': trip['startLatitude'],
            'longitude': trip['startLongitude'],
            'address': trip['startAddress'] ?? 'Start Location',
          },
          'endLocation': {
            'latitude': trip['endLatitude'],
            'longitude': trip['endLongitude'],
            'address': trip['endAddress'] ?? 'End Location',
          },
        };

        _startLocation = LatLng(
          (trip['startLatitude'] as num).toDouble(),
          (trip['startLongitude'] as num).toDouble(),
        );

        _endLocation = LatLng(
          (trip['endLatitude'] as num).toDouble(),
          (trip['endLongitude'] as num).toDouble(),
        );

        _routePoints = [_startLocation!, _endLocation!];
        _currentVehiclePosition = _routePoints[0];

        _isLoadedFromCache = true;
        _isSnappedToRoads = false;
      });

      _buildMarkersAndPolylines();

      setState(() {
        _isLoading = false;
      });

      await Future.delayed(const Duration(milliseconds: 300));
      _fitMapToRoute();

      debugPrint('✅ Loaded trip from cache (offline mode)');
    } catch (e) {
      debugPrint('❌ Error loading trip from cache: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = "Error loading cached trip: $e";
      });
    }
  }

  Future<void> _handleRefresh() async {
    if (isOffline) {
      debugPrint('📱 Cannot refresh while offline');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cannot refresh while offline',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Color(0xFFF59E0B),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.all(16),
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
          content: Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.white, size: 20),
              SizedBox(width: AppSizes.spacingM),
              Text(
                'Trip map refreshed',
                style: AppTypography.body2.copyWith(color: AppColors.white),
              ),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
          ),
          margin: EdgeInsets.all(AppSizes.spacingM),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _buildMarkersAndPolylines() {
    _markers.clear();
    _polylines.clear();

    if (_startLocation == null || _endLocation == null) return;

    // Start marker (green)
    _markers.add(
      Marker(
        markerId: const MarkerId('start'),
        position: _startLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Start',
          snippet: _getDisplayAddress(_tripData?['startLocation']['address'], _startLocation),
        ),
      ),
    );

    // End marker (red)
    _markers.add(
      Marker(
        markerId: const MarkerId('end'),
        position: _endLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Destination',
          snippet: _getDisplayAddress(_tripData?['endLocation']['address'], _endLocation),
        ),
      ),
    );

    if (_routePoints.isNotEmpty) {
      _createPolylineWithArrows();
    }

    setState(() {});
  }

  void _createPolylineWithArrows() {
    final Color routeColor = _isLoadedFromCache
        ? Color(0xFFF59E0B)
        : (_isSnappedToRoads ? AppColors.primary : AppColors.success);

    _polylines.add(
      Polyline(
        polylineId: const PolylineId('main_route'),
        points: _routePoints,
        color: routeColor,
        width: 5,
        geodesic: true,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    );

    debugPrint("✅ Drew route with ${_routePoints.length} points");
  }

  Future<void> _fitMapToRoute() async {
    if (_routePoints.isEmpty) return;

    try {
      final controller = await _controller.future;

      double minLat = _routePoints.first.latitude;
      double maxLat = _routePoints.first.latitude;
      double minLng = _routePoints.first.longitude;
      double maxLng = _routePoints.first.longitude;

      for (var point in _routePoints) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }

      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 80),
      );

      debugPrint("✅ Map fitted to route bounds");
    } catch (e) {
      debugPrint("⚠️ Error fitting map: $e");
    }
  }

  Future<void> _zoomIn() async {
    final controller = await _controller.future;
    controller.animateCamera(CameraUpdate.zoomIn());
  }

  Future<void> _zoomOut() async {
    final controller = await _controller.future;
    controller.animateCamera(CameraUpdate.zoomOut());
  }

  void _changeMapType(MapType type) {
    setState(() {
      _currentMapType = type;
      _showMapTypeMenu = false;
    });
  }

  String _formatTime(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString).toLocal();
      final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
      final minute = date.minute.toString().padLeft(2, '0');
      final period = date.hour >= 12 ? "PM" : "AM";
      return "$hour:$minute $period";
    } catch (e) {
      return 'Invalid time';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: _isLoading
          ? _buildLoadingState()
          : _errorMessage != null
          ? _buildErrorState()
          : Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _startLocation ?? const LatLng(3.8480, 11.5021),
              zoom: DEFAULT_ZOOM,
            ),
            markers: _markers,
            polylines: _polylines,
            mapType: _currentMapType,
            onMapCreated: (GoogleMapController controller) {
              if (!_controller.isCompleted) {
                _controller.complete(controller);
              }
            },
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          const OfflineBanner(),
          _buildTopBar(),
          _buildFloatingControls(),

          // 🎬 Show either playback controls or bottom card
          if (_showPlaybackControls)
            _buildPlaybackControls()
          else
            _buildBottomCard(),

          if (_isRefreshing)
            Positioned(
              top: 120,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSizes.spacingL,
                    vertical: AppSizes.spacingM,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(AppSizes.radiusL),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: AppSizes.spacingM),
                      Text(
                        'Refreshing map...',
                        style: AppTypography.body2.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 3,
          ),
          SizedBox(height: AppSizes.spacingM),
          Text(
            isOffline ? "Loading cached route..." : "Loading road-following route...",
            style: AppTypography.body2,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSizes.spacingXL + 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(AppSizes.spacingXL),
              decoration: BoxDecoration(
                color: isOffline
                    ? Color(0xFFF59E0B).withOpacity(0.1)
                    : AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isOffline ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
                size: 80,
                color: isOffline ? Color(0xFFF59E0B) : AppColors.primary.withOpacity(0.5),
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
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: AppSizes.spacingL,
                  vertical: AppSizes.spacingM + 2,
                ),
                elevation: 0,
              ),
              icon: Icon(Icons.refresh, color: AppColors.black),
              label: Text(
                isOffline ? 'No Internet' : 'Retry',
                style: AppTypography.button.copyWith(
                  color: AppColors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: EdgeInsets.all(AppSizes.spacingM),
          padding: EdgeInsets.symmetric(
            horizontal: AppSizes.spacingS,
            vertical: AppSizes.spacingS,
          ),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.arrow_back_rounded, color: AppColors.black),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
              SizedBox(width: AppSizes.spacingS),
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
                            style: AppTypography.body1.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_isLoadedFromCache) ...[
                          SizedBox(width: 6),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Color(0xFFF59E0B).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'OFF',
                              style: AppTypography.caption.copyWith(
                                fontSize: 8,
                                color: Color(0xFFF59E0B),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        if (_isSnappedToRoads && !_isLoadedFromCache) ...[
                          SizedBox(width: 6),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.route,
                                  size: 8,
                                  color: AppColors.primary,
                                ),
                                SizedBox(width: 2),
                                Text(
                                  'RD',
                                  style: AppTypography.caption.copyWith(
                                    fontSize: 8,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_tripData != null)
                      Text(
                        '${_tripData!['totalDistanceKm']} km • ${_tripData!['durationFormatted']}',
                        style: AppTypography.caption.copyWith(fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),

              // 🎬 Playback button
              IconButton(
                onPressed: _togglePlayback,
                icon: Icon(
                  _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  color: AppColors.primary,
                  size: 26,
                ),
                padding: EdgeInsets.all(4),
                constraints: BoxConstraints(),
                tooltip: _isPlaying ? 'Pause' : 'Play',
              ),

              SizedBox(width: 4),

              Opacity(
                opacity: isOffline ? 0.5 : 1.0,
                child: IconButton(
                  onPressed: (isOffline || _isRefreshing) ? null : _handleRefresh,
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: (isOffline || _isRefreshing)
                        ? AppColors.textSecondary.withOpacity(0.5)
                        : AppColors.primary,
                    size: 20,
                  ),
                  padding: EdgeInsets.all(4),
                  constraints: BoxConstraints(),
                  tooltip: isOffline ? 'Offline' : 'Refresh',
                ),
              ),

              SizedBox(width: 4),

              // 🔧 FIXED: Constrain this container to prevent overflow
              Flexible(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _isLoadedFromCache
                        ? Color(0xFFF59E0B).withOpacity(0.1)
                        : (_isSnappedToRoads
                        ? AppColors.primary.withOpacity(0.1)
                        : AppColors.success.withOpacity(0.1)),
                    borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.navigation_rounded,
                        color: _isLoadedFromCache
                            ? Color(0xFFF59E0B)
                            : (_isSnappedToRoads ? AppColors.primary : AppColors.success),
                        size: 12,
                      ),
                      SizedBox(width: 4),
                      // 🔧 FIXED: Use Flexible to prevent overflow
                      Flexible(
                        child: Text(
                          '${_routePoints.length}',
                          style: AppTypography.caption.copyWith(
                            fontSize: 10,
                            color: _isLoadedFromCache
                                ? Color(0xFFF59E0B)
                                : (_isSnappedToRoads ? AppColors.primary : AppColors.success),
                            fontWeight: FontWeight.w700,
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

  Widget _buildFloatingControls() {
    return Positioned(
      right: AppSizes.spacingM,
      top: 100,
      child: SafeArea(
        child: Column(
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _showMapTypeMenu = !_showMapTypeMenu;
                });
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.withOpacity(0.1),
                      blurRadius: 15,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.layers_rounded,
                  color: _showMapTypeMenu ? AppColors.primary : AppColors.black,
                  size: 22,
                ),
              ),
            ),
            if (_showMapTypeMenu) ...[
              SizedBox(height: AppSizes.spacingS),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.withOpacity(0.1),
                      blurRadius: 15,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildMapTypeOption(
                      icon: Icons.map_rounded,
                      label: 'Normal',
                      type: MapType.normal,
                    ),
                    Divider(height: 1, thickness: 1),
                    _buildMapTypeOption(
                      icon: Icons.satellite_rounded,
                      label: 'Satellite',
                      type: MapType.satellite,
                    ),
                    Divider(height: 1, thickness: 1),
                    _buildMapTypeOption(
                      icon: Icons.terrain_rounded,
                      label: 'Terrain',
                      type: MapType.terrain,
                    ),
                    Divider(height: 1, thickness: 1),
                    _buildMapTypeOption(
                      icon: Icons.layers_outlined,
                      label: 'Hybrid',
                      type: MapType.hybrid,
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: AppSizes.spacingL),
            Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.black.withOpacity(0.1),
                    blurRadius: 15,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: _zoomIn,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppSizes.radiusM),
                    ),
                    child: Container(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.add_rounded,
                        color: AppColors.black,
                        size: 24,
                      ),
                    ),
                  ),
                  Divider(height: 1, thickness: 1),
                  InkWell(
                    onTap: _zoomOut,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(AppSizes.radiusM),
                    ),
                    child: Container(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.remove_rounded,
                        color: AppColors.black,
                        size: 24,
                      ),
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

  Widget _buildMapTypeOption({
    required IconData icon,
    required String label,
    required MapType type,
  }) {
    final isSelected = _currentMapType == type;

    return InkWell(
      onTap: () => _changeMapType(type),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.spacingM,
          vertical: AppSizes.spacingS + 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 20,
            ),
            SizedBox(width: AppSizes.spacingS),
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color: isSelected ? AppColors.primary : AppColors.black,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 12,
              ),
            ),
            if (isSelected) ...[
              SizedBox(width: AppSizes.spacingXS),
              Icon(
                Icons.check_rounded,
                color: AppColors.primary,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 🎬 PLAYBACK CONTROLS UI
  Widget _buildPlaybackControls() {
    if (_routePoints.isEmpty) return SizedBox.shrink();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        margin: EdgeInsets.all(AppSizes.spacingM),
        padding: EdgeInsets.all(AppSizes.spacingL),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSizes.radiusXL),
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withOpacity(0.15),
              blurRadius: 30,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Current time and speed
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: AppColors.textSecondary),
                    SizedBox(width: AppSizes.spacingXS),
                    Text(
                      _getCurrentTime(),
                      style: AppTypography.body2.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.speed, size: 16, color: AppColors.primary),
                    SizedBox(width: AppSizes.spacingXS),
                    Text(
                      _getCurrentSpeed(),
                      style: AppTypography.body2.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            SizedBox(height: AppSizes.spacingM),

            // Timeline slider
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: AppColors.border,
                thumbColor: AppColors.primary,
                overlayColor: AppColors.primary.withOpacity(0.2),
              ),
              child: Slider(
                value: _currentPlaybackPosition,
                min: 0,
                max: (_routePoints.length - 1).toDouble(),
                onChanged: _onSliderChanged,
              ),
            ),

            // Progress text
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(_currentPlaybackPosition + 1).floor()} / ${_routePoints.length}',
                  style: AppTypography.caption.copyWith(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '${((_currentPlaybackPosition / (_routePoints.length - 1)) * 100).toStringAsFixed(0)}%',
                  style: AppTypography.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),

            SizedBox(height: AppSizes.spacingM),

            // Control buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Reset button
                IconButton(
                  onPressed: _resetPlayback,
                  icon: Icon(Icons.replay_rounded, color: AppColors.textSecondary),
                  tooltip: 'Reset',
                ),

                SizedBox(width: AppSizes.spacingL),

                // Play/Pause button (larger)
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    onPressed: _togglePlayback,
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: AppColors.white,
                      size: 32,
                    ),
                    iconSize: 32,
                  ),
                ),

                SizedBox(width: AppSizes.spacingL),

                // Speed control button
                InkWell(
                  onTap: _changePlaybackSpeed,
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSizes.spacingM,
                      vertical: AppSizes.spacingS,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(AppSizes.radiusM),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      '${_playbackSpeed}x',
                      style: AppTypography.body2.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: AppSizes.spacingS),

            // Close playback button
            TextButton.icon(
              onPressed: () {
                _pausePlayback();
                setState(() {
                  _showPlaybackControls = false;
                  _isPlaying = false;
                });
                _buildMarkersAndPolylines();
              },
              icon: Icon(Icons.close, size: 16, color: AppColors.textSecondary),
              label: Text(
                'Close Playback',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomCard() {
    if (_tripData == null) return const SizedBox.shrink();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        margin: EdgeInsets.all(AppSizes.spacingM),
        padding: EdgeInsets.all(AppSizes.spacingL),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSizes.radiusXL),
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withOpacity(0.15),
              blurRadius: 30,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLocationRow(
              icon: Icons.radio_button_checked_rounded,
              iconColor: AppColors.success,
              title: 'Start',
              address: _getDisplayAddress(
                _tripData!['startLocation']['address'],
                _startLocation,
              ),
              time: _formatTime(_tripData!['startTime']),
            ),
            Container(
              margin: EdgeInsets.symmetric(vertical: AppSizes.spacingM),
              child: Row(
                children: [
                  SizedBox(width: AppSizes.spacingM),
                  Container(
                    width: 2,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
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
                        vertical: AppSizes.spacingS,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(AppSizes.radiusM),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatChip(
                            icon: Icons.straighten_rounded,
                            value: '${_tripData!['totalDistanceKm']} km',
                            color: AppColors.primary,
                          ),
                          Container(
                            width: 1,
                            height: 20,
                            color: AppColors.border,
                          ),
                          _buildStatChip(
                            icon: Icons.speed_rounded,
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
            _buildLocationRow(
              icon: Icons.location_on_rounded,
              iconColor: AppColors.error,
              title: 'Destination',
              address: _getDisplayAddress(
                _tripData!['endLocation']['address'],
                _endLocation,
              ),
              time: _formatTime(_tripData!['endTime']),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String address,
    required String time,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(AppSizes.spacingS),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
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
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    time,
                    style: AppTypography.caption.copyWith(
                      fontSize: 12,
                      color: AppColors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              SizedBox(height: AppSizes.spacingXS),
              Text(
                address,
                style: AppTypography.caption.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.black,
                  height: 1.4,
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

  Widget _buildStatChip({
    required IconData icon,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        SizedBox(width: AppSizes.spacingXS),
        Text(
          value,
          style: AppTypography.caption.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}