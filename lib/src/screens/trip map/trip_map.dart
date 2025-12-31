// lib/src/screens/trips/trip_map_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';

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

  String get baseUrl => EnvConfig.baseUrl;

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

  // Map type control
  MapType _currentMapType = MapType.normal;
  bool _showMapTypeMenu = false;

  // Default zoom level
  static const double DEFAULT_ZOOM = 15.0;

  @override
  void initState() {
    super.initState();
    _loadTripData();
  }

  /// ✅ OPTIMIZED: Load trip data and generate road-following route
  Future<void> _loadTripData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint("📡 Fetching trip ${widget.tripId}...");

      final response = await http.get(
        Uri.parse("$baseUrl/trips/${widget.tripId}/details-with-route"),
      );

      debugPrint("📡 Trip details response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final trip = data['data']['trip'];
          final waypoints = data['data']['waypoints'] as List;
          final metadata = data['data']['metadata'];

          debugPrint("✅ Trip loaded: ${trip['id']}");
          debugPrint("📍 GPS waypoints received: ${waypoints.length}");

          if (metadata != null) {
            debugPrint("📊 Total waypoints: ${metadata['totalWaypoints']}");
            debugPrint("📊 Sampled: ${metadata['isSampled']}");
          }

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

            _startLocation = LatLng(
              (trip['startLocation']['latitude'] as num).toDouble(),
              (trip['startLocation']['longitude'] as num).toDouble(),
            );

            _endLocation = LatLng(
              (trip['endLocation']['latitude'] as num).toDouble(),
              (trip['endLocation']['longitude'] as num).toDouble(),
            );

            // Store GPS waypoints
            _gpsWaypoints = waypoints.map((wp) {
              return LatLng(
                (wp['latitude'] as num).toDouble(),
                (wp['longitude'] as num).toDouble(),
              );
            }).toList();

            debugPrint("🗺️ GPS waypoints: ${_gpsWaypoints.length} points");
          });

          // 🔥 NEW: Generate road-following route using OSRM
          await _generateRoadFollowingRoute();

          setState(() {
            _isLoading = false;
          });

          // Fit map to route
          await Future.delayed(const Duration(milliseconds: 300));
          _fitMapToRoute();

          debugPrint("✅ Professional route map loaded!");
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

  /// 🔥 NEW: Generate road-following route using OSRM (FREE routing API)
  Future<void> _generateRoadFollowingRoute() async {
    try {
      debugPrint("🛣️ Generating road-following route...");

      // Sample GPS waypoints intelligently (max 25 points for OSRM)
      final sampledWaypoints = _sampleWaypointsForRouting(_gpsWaypoints, 25);

      debugPrint("🛣️ Using ${sampledWaypoints.length} waypoints for routing");

      // Build OSRM API URL
      final coordinates = sampledWaypoints
          .map((point) => '${point.longitude},${point.latitude}')
          .join(';');

      final osrmUrl = 'https://router.project-osrm.org/route/v1/driving/$coordinates?overview=full&geometries=polyline';

      debugPrint("🛣️ Calling OSRM API...");

      final response = await http.get(Uri.parse(osrmUrl)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint("⚠️ OSRM API timeout - falling back to GPS waypoints");
          return http.Response('{"error": "timeout"}', 408);
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final encodedPolyline = route['geometry'];

          // Decode polyline
          final decodedPoints = _decodePolyline(encodedPolyline);

          setState(() {
            _routePoints = decodedPoints;
          });

          debugPrint("✅ Road-following route generated: ${_routePoints.length} points");
          debugPrint("📏 Route distance from OSRM: ${(route['distance'] / 1000).toStringAsFixed(2)} km");

          _buildMarkersAndPolylines();
          return;
        }
      }

      // Fallback: use GPS waypoints directly
      debugPrint("⚠️ OSRM failed - using GPS waypoints as fallback");
      setState(() {
        _routePoints = _gpsWaypoints;
      });
      _buildMarkersAndPolylines();

    } catch (error) {
      debugPrint("🔥 Error generating road route: $error");
      // Fallback to GPS waypoints
      setState(() {
        _routePoints = _gpsWaypoints;
      });
      _buildMarkersAndPolylines();
    }
  }

  /// 🔥 Smart sampling for routing API (keeps start, end, and evenly distributed points)
  List<LatLng> _sampleWaypointsForRouting(List<LatLng> waypoints, int maxPoints) {
    if (waypoints.length <= maxPoints) return waypoints;

    final sampled = <LatLng>[];

    // Always keep first point
    sampled.add(waypoints.first);

    // Sample middle points evenly
    final step = (waypoints.length - 2) / (maxPoints - 2);
    for (int i = 1; i < maxPoints - 1; i++) {
      final index = 1 + (step * (i - 1)).round();
      if (index < waypoints.length - 1) {
        sampled.add(waypoints[index]);
      }
    }

    // Always keep last point
    sampled.add(waypoints.last);

    return sampled;
  }

  /// 🔥 Decode polyline from OSRM (Encoded Polyline Algorithm Format)
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      double latitude = lat / 1E5;
      double longitude = lng / 1E5;
      points.add(LatLng(latitude, longitude));
    }

    return points;
  }

  /// ✅ Pull to refresh
  Future<void> _handleRefresh() async {
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

  /// 🔥 Build markers and polylines with professional styling
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
          snippet: _tripData?['startLocation']['address'] ?? 'Start location',
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
          snippet: _tripData?['endLocation']['address'] ?? 'End location',
        ),
      ),
    );

    // 🔥 Professional polyline with road-following curves
    if (_routePoints.isNotEmpty) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: _routePoints,
          color: AppColors.success,
          width: 6, // Slightly thicker for better visibility
          geodesic: false, // Use actual route points, not great circle
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
      debugPrint("✅ Drew professional polyline with ${_routePoints.length} road-following points");
    }

    setState(() {});
  }

  /// Fit map to route
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
        CameraUpdate.newLatLngBounds(bounds, 80), // 80px padding
      );

      debugPrint("✅ Map fitted to route bounds");
    } catch (e) {
      debugPrint("⚠️ Error fitting map: $e");
    }
  }

  /// Zoom in
  Future<void> _zoomIn() async {
    final controller = await _controller.future;
    controller.animateCamera(CameraUpdate.zoomIn());
  }

  /// Zoom out
  Future<void> _zoomOut() async {
    final controller = await _controller.future;
    controller.animateCamera(CameraUpdate.zoomOut());
  }

  /// Change map type
  void _changeMapType(MapType type) {
    setState(() {
      _currentMapType = type;
      _showMapTypeMenu = false;
    });
  }

  String _formatTime(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
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

          // Top Bar
          _buildTopBar(),

          // Floating Controls
          _buildFloatingControls(),

          // Bottom Card
          _buildBottomCard(),

          // Loading overlay for refresh
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
            "Loading professional route...",
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
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 80,
                color: AppColors.primary.withOpacity(0.5),
              ),
            ),
            SizedBox(height: AppSizes.spacingL),
            Text(
              'Failed to Load Trip',
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
              onPressed: _loadTripData,
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
                'Retry',
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
              ),
              SizedBox(width: AppSizes.spacingS),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trip Route',
                      style: AppTypography.body1.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_tripData != null)
                      Text(
                        '${_tripData!['totalDistanceKm']} km • ${_tripData!['durationFormatted']}',
                        style: AppTypography.caption,
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _isRefreshing ? null : _handleRefresh,
                icon: Icon(
                  Icons.refresh_rounded,
                  color: _isRefreshing
                      ? AppColors.textSecondary.withOpacity(0.5)
                      : AppColors.primary,
                  size: 22,
                ),
                tooltip: 'Refresh',
              ),
              SizedBox(width: AppSizes.spacingXS),
              Container(
                padding: EdgeInsets.all(AppSizes.spacingS),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.route_rounded,
                      color: AppColors.success,
                      size: 16,
                    ),
                    SizedBox(width: AppSizes.spacingXS),
                    Text(
                      '${_routePoints.length} pts',
                      style: AppTypography.caption.copyWith(
                        fontSize: 11,
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
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
              address: _tripData!['startLocation']['address'] ?? 'Unknown',
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
              address: _tripData!['endLocation']['address'] ?? 'Unknown',
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