import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;

import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';

class StolenAlertScreen extends StatefulWidget {
  final int vehicleId;
  final double vehicleLat;
  final double vehicleLng;
  final String vehicleName;

  const StolenAlertScreen({
    Key? key,
    required this.vehicleId,
    required this.vehicleLat,
    required this.vehicleLng,
    required this.vehicleName,
  }) : super(key: key);

  @override
  State<StolenAlertScreen> createState() => _StolenAlertScreenState();
}

class _StolenAlertScreenState extends State<StolenAlertScreen> {
  GoogleMapController? _mapController;
  Position? _userPosition;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<LatLng> _routeCoordinates = [];
  List<Map<String, dynamic>> _policeStations = [];
  bool _isLoadingLocation = true;
  bool _isLoadingRoute = false;
  bool _isLoadingPoliceStations = false;
  String _distanceText = '';
  String _durationText = '';
  BitmapDescriptor? _userIcon;
  BitmapDescriptor? _vehicleIcon;
  BitmapDescriptor? _policeIcon;

  // Google Maps API Key
  static const String _googleMapsApiKey = 'AIzaSyBn88TP5X-xaRCYo5gYxvGnVy_0WYotZWo';

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    await _loadCustomIcons();
    await _getUserLocation();
    await _getDirections();
    await _getNearbyPoliceStations();
  }

  // Load custom map icons
  Future<void> _loadCustomIcons() async {
    try {
      _userIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/user_marker.png', // You'll need to add this asset
      );
    } catch (e) {
      debugPrint('⚠️ Failed to load user icon: $e');
      _userIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    }

    try {
      _vehicleIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/carmarker.png',
      );
    } catch (e) {
      debugPrint('⚠️ Failed to load vehicle icon: $e');
      _vehicleIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    }

    try {
      _policeIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    } catch (e) {
      debugPrint('⚠️ Failed to load police icon: $e');
    }
  }

  // Get user's current location
  Future<void> _getUserLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions denied');
        }
      }

      // Get current position
      _userPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      debugPrint('📍 User location: ${_userPosition!.latitude}, ${_userPosition!.longitude}');
      debugPrint('📍 Vehicle location: ${widget.vehicleLat}, ${widget.vehicleLng}');

      // Add markers
      _addMarkers();

      // Move camera to show both points
      _moveCameraToFitMarkers();

      setState(() {
        _isLoadingLocation = false;
      });
    } catch (e) {
      debugPrint('❌ Error getting user location: $e');
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  // Add markers for user and vehicle
  void _addMarkers() {
    _markers.clear();

    // User marker
    if (_userPosition != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('user'),
          position: LatLng(_userPosition!.latitude, _userPosition!.longitude),
          icon: _userIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(
            title: 'Your Location',
            snippet: 'You are here',
          ),
        ),
      );
    }

    // Vehicle marker (stolen)
    _markers.add(
      Marker(
        markerId: const MarkerId('vehicle'),
        position: LatLng(widget.vehicleLat, widget.vehicleLng),
        icon: _vehicleIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: '🚨 ${widget.vehicleName}',
          snippet: 'STOLEN - Engine Disabled',
        ),
      ),
    );

    setState(() {});
  }

  // Get directions from user to vehicle
  Future<void> _getDirections() async {
    if (_userPosition == null) return;

    setState(() {
      _isLoadingRoute = true;
    });

    try {
      final origin = '${_userPosition!.latitude},${_userPosition!.longitude}';
      final destination = '${widget.vehicleLat},${widget.vehicleLng}';

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?'
            'origin=$origin&destination=$destination&key=$_googleMapsApiKey',
      );

      debugPrint('🗺️ Fetching directions...');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final polylinePoints = route['overview_polyline']['points'];

          // Decode polyline
          _routeCoordinates = _decodePolyline(polylinePoints);

          // Get distance and duration
          final leg = route['legs'][0];
          _distanceText = leg['distance']['text'];
          _durationText = leg['duration']['text'];

          debugPrint('✅ Route loaded: $_distanceText, $_durationText');

          // Add polyline to map
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: _routeCoordinates,
              color: AppColors.error,
              width: 5,
              patterns: [PatternItem.dash(20), PatternItem.gap(10)],
            ),
          );

          setState(() {
            _isLoadingRoute = false;
          });
        } else {
          throw Exception('No route found');
        }
      } else {
        throw Exception('Directions API failed');
      }
    } catch (e) {
      debugPrint('❌ Error getting directions: $e');
      setState(() {
        _isLoadingRoute = false;
      });
    }
  }

  // Get nearby police stations
  Future<void> _getNearbyPoliceStations() async {
    if (_userPosition == null) return;

    setState(() {
      _isLoadingPoliceStations = true;
    });

    try {
      final location = '${_userPosition!.latitude},${_userPosition!.longitude}';
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?'
            'location=$location&radius=5000&type=police&key=$_googleMapsApiKey',
      );

      debugPrint('🚔 Fetching nearby police stations...');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'OK') {
          _policeStations = List<Map<String, dynamic>>.from(data['results']);

          debugPrint('✅ Found ${_policeStations.length} police stations');

          // Add police station markers
          for (int i = 0; i < _policeStations.length && i < 5; i++) {
            final station = _policeStations[i];
            final lat = station['geometry']['location']['lat'];
            final lng = station['geometry']['location']['lng'];
            final name = station['name'];

            _markers.add(
              Marker(
                markerId: MarkerId('police_$i'),
                position: LatLng(lat, lng),
                icon: _policeIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                infoWindow: InfoWindow(
                  title: '🚔 $name',
                  snippet: 'Police Station',
                ),
              ),
            );
          }

          setState(() {
            _isLoadingPoliceStations = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error getting police stations: $e');
      setState(() {
        _isLoadingPoliceStations = false;
      });
    }
  }

  // Decode Google polyline
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

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return points;
  }

  // Move camera to fit all markers
  void _moveCameraToFitMarkers() {
    if (_userPosition == null || _mapController == null) return;

    double minLat = math.min(_userPosition!.latitude, widget.vehicleLat);
    double maxLat = math.max(_userPosition!.latitude, widget.vehicleLat);
    double minLng = math.min(_userPosition!.longitude, widget.vehicleLng);
    double maxLng = math.max(_userPosition!.longitude, widget.vehicleLng);

    // Add padding
    double padding = 0.01;

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - padding, minLng - padding),
          northeast: LatLng(maxLat + padding, maxLng + padding),
        ),
        100, // padding in pixels
      ),
    );
  }

  // Call 911
  Future<void> _call911() async {
    final Uri phoneUri = Uri(scheme: 'tel', path: '911');

    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch phone dialer')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(widget.vehicleLat, widget.vehicleLng),
              zoom: 14,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              if (_userPosition != null) {
                _moveCameraToFitMarkers();
              }
            },
          ),

          // Top Alert Banner
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: EdgeInsets.all(AppSizes.spacingM),
                padding: EdgeInsets.all(AppSizes.spacingL),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(AppSizes.radiusL),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.warning_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        SizedBox(width: AppSizes.spacingM),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'VEHICLE STOLEN',
                                style: AppTypography.h3.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: AppSizes.spacingXS),
                              Text(
                                'Engine has been disabled remotely',
                                style: AppTypography.body2.copyWith(
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),

                    if (_distanceText.isNotEmpty) ...[
                      SizedBox(height: AppSizes.spacingM),
                      Container(
                        padding: EdgeInsets.all(AppSizes.spacingM),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(AppSizes.radiusM),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(
                                  _distanceText,
                                  style: AppTypography.h3.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Distance',
                                  style: AppTypography.caption.copyWith(
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.white.withOpacity(0.3),
                            ),
                            Column(
                              children: [
                                Text(
                                  _durationText,
                                  style: AppTypography.h3.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Estimated Time',
                                  style: AppTypography.caption.copyWith(
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Call 911 Button (Floating)
          Positioned(
            bottom: AppSizes.spacingXL,
            left: AppSizes.spacingL,
            right: AppSizes.spacingL,
            child: SafeArea(
              child: ElevatedButton(
                onPressed: _call911,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding: EdgeInsets.symmetric(vertical: AppSizes.spacingL),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusL),
                  ),
                  elevation: 8,
                  shadowColor: Colors.black.withOpacity(0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.phone_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    SizedBox(width: AppSizes.spacingM),
                    Text(
                      'CALL 911 EMERGENCY',
                      style: AppTypography.button.copyWith(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Loading Indicator
          if (_isLoadingLocation || _isLoadingRoute || _isLoadingPoliceStations)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}