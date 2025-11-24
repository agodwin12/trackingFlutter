// lib/src/screens/tracking/vehicle_tracking_map.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';
import '../../services/socket_service.dart';

class VehicleTrackingMap extends StatefulWidget {
  final int vehicleId;

  const VehicleTrackingMap({Key? key, required this.vehicleId}) : super(key: key);

  @override
  State<VehicleTrackingMap> createState() => _VehicleTrackingMapState();
}

class _VehicleTrackingMapState extends State<VehicleTrackingMap> {
  GoogleMapController? _mapController;
  final SocketService _socketService = SocketService();

  // ✅ Get URLs from environment config
  String get baseUrl => EnvConfig.baseUrl;
  String get socketUrl => EnvConfig.socketUrl;

  // ✅ Default position (Yaoundé, Cameroon)
  static const LatLng _defaultPosition = LatLng(3.8480, 11.5021);
  late LatLng _currentPosition;

  bool isLoading = true;
  bool hasError = false;
  String errorMessage = "";
  String carModel = "Unknown";
  String speed = "0 Km/h";
  Timer? _fallbackTimer;
  StreamSubscription? _gpsSubscription;
  StreamSubscription? _connectionSubscription;

  bool isSocketConnected = false;
  String connectionSource = "Initializing...";

  MapType _currentMapType = MapType.normal;
  Set<Marker> _markers = {};

  BitmapDescriptor _carIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);

  @override
  void initState() {
    super.initState();

    // ✅ Initialize position immediately
    _currentPosition = _defaultPosition;

    print('\n╔════════════════════════════════════════╗');
    print('║  🚀 VEHICLE TRACKING MAP - INIT       ║');
    print('╚════════════════════════════════════════╝');
    print('🚀 Vehicle ID: ${widget.vehicleId}');
    print('🚀 Base URL: $baseUrl');
    print('🚀 Socket URL: $socketUrl');
    print('🚀 Initial Position: $_currentPosition');
    print('🚀 Timestamp: ${DateTime.now()}');
    print('════════════════════════════════════════\n');

    _createCarMarkerIcon();
    _updateMarker();
    _initializeTracking();
  }

  @override
  void dispose() {
    print('\n🔴 DISPOSE CALLED - Cleaning up resources');
    _mapController?.dispose();
    _cleanupTracking();
    super.dispose();
  }

  void _updateMarker() {
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId("vehicle"),
          position: _currentPosition,
          infoWindow: InfoWindow(
            title: carModel,
            snippet: "Speed: $speed",
          ),
          icon: _carIcon,
        ),
      };
    });
  }

  void _initializeTracking() {
    print('\n╔════════════════════════════════════════╗');
    print('║  📡 INITIALIZING VEHICLE TRACKING     ║');
    print('╚════════════════════════════════════════╝');
    print('📡 Vehicle ID: ${widget.vehicleId}');
    print('📡 Base URL: $baseUrl');
    print('📡 Socket URL: $socketUrl');
    print('════════════════════════════════════════\n');

    print('📍 Step 1/3: Fetching initial location from API...');
    fetchVehicleLocation();

    print('🔌 Step 2/3: Connecting to Socket.IO...');
    _connectSocketIO();

    print('⏰ Step 3/3: Setting up fallback polling...');
    _setupFallbackPolling();

    print('\n✅ Initialization sequence complete\n');
  }

  void _connectSocketIO() {
    print('\n╔════════════════════════════════════════╗');
    print('║  🔌 _connectSocketIO() CALLED         ║');
    print('╚════════════════════════════════════════╝');
    print('🔌 Socket URL: $socketUrl');
    print('🔌 Vehicle ID: ${widget.vehicleId}');
    print('════════════════════════════════════════\n');

    try {
      print('🔌 Step 1: Calling _socketService.connect()...');
      _socketService.connect(socketUrl);
      print('✅ Step 1 complete - connect() called\n');
    } catch (e) {
      print('🔥 ERROR in Step 1 (connect): $e\n');
      return;
    }

    try {
      print('🔌 Step 2: Setting up connection status listener...');
      _connectionSubscription = _socketService.connectionStatusStream.listen(
            (isConnected) {
          print('\n📡 ========== CONNECTION STATUS CHANGED ==========');
          print('📡 Is Connected: $isConnected');
          print('📡 Timestamp: ${DateTime.now()}');

          if (mounted) {
            setState(() {
              isSocketConnected = isConnected;
              connectionSource = isConnected ? "Live (Socket.IO)" : "Offline";
            });
            print('📡 UI State updated - isSocketConnected: $isSocketConnected');
          }

          if (isConnected) {
            print('✅ Socket connected! Now joining vehicle room...');
            _socketService.joinVehicleTracking(widget.vehicleId);

            print('⏰ Cancelling fallback polling timer...');
            _fallbackTimer?.cancel();
            print('✅ Fallback polling cancelled');
          } else {
            print('❌ Socket disconnected, restarting fallback polling...');
            _setupFallbackPolling();
          }
          print('════════════════════════════════════════\n');
        },
        onError: (error) {
          print('🔥 ERROR in connection status stream: $error');
        },
      );
      print('✅ Step 2 complete - Status listener set up\n');
    } catch (e) {
      print('🔥 ERROR in Step 2 (status listener): $e\n');
    }

    try {
      print('🔌 Step 3: Setting up GPS update listener...');
      _gpsSubscription = _socketService.gpsUpdateStream.listen(
            (data) {
          print('\n📡 ========== GPS UPDATE RECEIVED IN UI ==========');
          print('📡 Raw data: $data');
          print('📡 Data type: ${data.runtimeType}');
          print('📡 Timestamp: ${DateTime.now()}');
          _handleGPSUpdate(data);
          print('════════════════════════════════════════\n');
        },
        onError: (error) {
          print('🔥 ERROR in GPS update stream: $error');
        },
      );
      print('✅ Step 3 complete - GPS listener set up\n');
    } catch (e) {
      print('🔥 ERROR in Step 3 (GPS listener): $e\n');
    }

    print('╔════════════════════════════════════════╗');
    print('║  ✅ _connectSocketIO() COMPLETE       ║');
    print('╚════════════════════════════════════════╝\n');
  }

  void _setupFallbackPolling() {
    print('\n⏰ ========== SETTING UP FALLBACK POLLING ==========');

    _fallbackTimer?.cancel();
    print('⏰ Old timer cancelled (if existed)');

    _fallbackTimer = Timer.periodic(const Duration(seconds: 10), (Timer t) {
      if (mounted && !isSocketConnected) {
        print('\n🔄 ========== FALLBACK POLL ==========');
        print('🔄 Time: ${DateTime.now()}');
        print('🔄 Socket connected: $isSocketConnected');
        print('🔄 Fetching from API...');
        fetchVehicleLocation();
        print('════════════════════════════════════════\n');
      } else if (isSocketConnected) {
        print('⏰ Poll skipped - Socket is connected');
      }
    });

    print('✅ Fallback timer created (10s interval)');
    print('════════════════════════════════════════\n');
  }

  void _handleGPSUpdate(Map<String, dynamic> data) {
    print('\n📡 ========== HANDLING GPS UPDATE ==========');
    print('📡 Mounted: $mounted');

    if (!mounted) {
      print('⚠️ Widget not mounted, skipping update');
      return;
    }

    try {
      print('📡 Parsing latitude...');
      final double lat = double.parse(data["latitude"].toString());
      print('✅ Latitude: $lat');

      print('📡 Parsing longitude...');
      final double lng = double.parse(data["longitude"].toString());
      print('✅ Longitude: $lng');

      final LatLng newPosition = LatLng(lat, lng);
      print('✅ New position: $newPosition');

      print('📡 Updating UI state...');
      setState(() {
        _currentPosition = newPosition;
        speed = "${data["speed"] ?? 0} Km/h";
        carModel = data["car_model"] ?? "Unknown";
        isLoading = false;
        hasError = false;
        connectionSource = "Live (Socket.IO)";
        _updateMarker();
      });
      print('✅ UI state updated');
      print('   - Speed: $speed');
      print('   - Model: $carModel');
      print('   - Source: Live (Socket.IO)');

      print('📡 Moving camera to new position...');
      _moveCamera(newPosition);

      print('✅ GPS update handled successfully');
      print('════════════════════════════════════════\n');

    } catch (e, stackTrace) {
      print('🔥 ERROR handling GPS update: $e');
      print('🔥 Stack trace: $stackTrace');
      print('🔥 Data that caused error: $data');
      print('════════════════════════════════════════\n');
    }
  }

  void _moveCamera(LatLng position) {
    print('🗺️ Attempting to move camera...');
    print('🗺️ Map controller status: ${_mapController == null ? "NULL" : "READY"}');

    if (_mapController != null) {
      try {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(position),
        );
        print('✅ Camera moved to: $position');
      } catch (e) {
        print('🔥 Error animating camera: $e');
      }
    } else {
      print('⚠️ Map controller is NULL - camera movement skipped');
      print('⚠️ Map might still be initializing...');
    }
  }

  void _cleanupTracking() {
    print('\n╔════════════════════════════════════════╗');
    print('║  🧹 CLEANUP TRACKING RESOURCES        ║');
    print('╚════════════════════════════════════════╝');

    print('🧹 Cancelling fallback timer...');
    _fallbackTimer?.cancel();
    print('✅ Timer cancelled');

    print('🧹 Cancelling GPS subscription...');
    _gpsSubscription?.cancel();
    print('✅ GPS subscription cancelled');

    print('🧹 Cancelling connection subscription...');
    _connectionSubscription?.cancel();
    print('✅ Connection subscription cancelled');

    print('🧹 Leaving vehicle tracking room...');
    _socketService.leaveVehicleTracking(widget.vehicleId);
    print('✅ Room left');

    print('╔════════════════════════════════════════╗');
    print('║  ✅ CLEANUP COMPLETE                  ║');
    print('╚════════════════════════════════════════╝\n');
  }

  Future<void> _createCarMarkerIcon() async {
    try {
      final ByteData imageData = await NetworkAssetBundle(
          Uri.parse('https://cdn-icons-png.flaticon.com/512/3774/3774278.png'))
          .load('');
      final Uint8List bytes = imageData.buffer.asUint8List();
      final Uint8List resizedBytes = await _resizeImage(bytes, 64, 64);
      final BitmapDescriptor customIcon = BitmapDescriptor.fromBytes(resizedBytes);

      if (mounted) {
        setState(() {
          _carIcon = customIcon;
          _updateMarker();
        });
        print('✅ Custom car icon created');
      }
    } catch (e) {
      print("🔥 Error creating custom marker: $e");
    }
  }

  Future<Uint8List> _resizeImage(Uint8List data, int width, int height) async {
    final ui.Codec codec = await ui.instantiateImageCodec(
      data,
      targetWidth: width,
      targetHeight: height,
    );
    final ui.FrameInfo fi = await codec.getNextFrame();
    final ByteData? byteData = await fi.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return byteData!.buffer.asUint8List();
  }

  Future<void> fetchVehicleLocation() async {
    if (!mounted) return;

    print("\n📡 ========== FETCHING FROM API ==========");
    print("📡 URL: $baseUrl/tracking/location/${widget.vehicleId}");
    print("📡 Timestamp: ${DateTime.now()}");

    final String apiUrl = "$baseUrl/tracking/location/${widget.vehicleId}";

    try {
      final response = await http.get(Uri.parse(apiUrl)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Connection timed out. Check your server.');
        },
      );

      if (!mounted) return;

      print("📡 Response status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        print("✅ GPS Data Found: $data");

        if (data["success"] == true) {
          final double lat = double.parse(data["latitude"].toString());
          final double lng = double.parse(data["longitude"].toString());
          final LatLng newPosition = LatLng(lat, lng);

          if (mounted) {
            setState(() {
              _currentPosition = newPosition;
              isLoading = false;
              hasError = false;
              speed = "${data["speed"] ?? 0} Km/h";
              carModel = data["car_model"] ?? "Unknown";
              connectionSource = data["source"] == "cache"
                  ? "Cached (${isSocketConnected ? 'Socket.IO Active' : 'Polling'})"
                  : "Database (${isSocketConnected ? 'Socket.IO Active' : 'Polling'})";
              _updateMarker();
            });
            print("✅ UI updated with new location");
          }

          _moveCamera(newPosition);
        } else {
          print("❌ API returned success=false");
          if (mounted) {
            setState(() {
              isLoading = false;
              hasError = true;
              errorMessage = "No location data available";
            });
          }
        }
      } else {
        print("❌ HTTP error: ${response.statusCode}");
        if (mounted) {
          setState(() {
            isLoading = false;
            hasError = true;
            errorMessage = "Error: HTTP ${response.statusCode}";
          });
        }
      }
      print("════════════════════════════════════════\n");
    } catch (error) {
      print("🔥 Error fetching vehicle location: $error");
      if (mounted) {
        setState(() {
          isLoading = false;
          hasError = true;
          errorMessage = "Connection error: ${error.toString().split(":")[0]}";
        });
      }
      print("════════════════════════════════════════\n");
    }
  }

  void _showMapTypeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.white, // ✅ Brand white
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(AppSizes.radiusL), // ✅ Brand radius
              topRight: Radius.circular(AppSizes.radiusL),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: AppSizes.spacingM), // ✅ Brand spacing
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border, // ✅ Brand border
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: AppSizes.spacingM), // ✅ Brand spacing
              Text(
                'Select Map Type',
                style: AppTypography.subtitle1, // ✅ Brand typography
              ),
              SizedBox(height: AppSizes.spacingM), // ✅ Brand spacing
              _buildMapTypeOption('Default', 'Standard road map', Icons.map, MapType.normal),
              _buildMapTypeOption('Satellite', 'Satellite imagery', Icons.satellite_alt, MapType.satellite),
              _buildMapTypeOption('Terrain', 'Topographic map', Icons.terrain, MapType.terrain),
              _buildMapTypeOption('Hybrid', 'Satellite with labels', Icons.layers, MapType.hybrid),
              SizedBox(height: AppSizes.spacingM), // ✅ Brand spacing
            ],
          ),
        );
      },
    );
  }

  Widget _buildMapTypeOption(String title, String subtitle, IconData icon, MapType mapType) {
    final isSelected = _currentMapType == mapType;

    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(AppSizes.spacingS), // ✅ Brand spacing
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryLight // ✅ Brand primary light
              : AppColors.background, // ✅ Brand background
          borderRadius: BorderRadius.circular(AppSizes.spacingS), // ✅ Brand radius
        ),
        child: Icon(
          icon,
          color: isSelected
              ? AppColors.primary // ✅ Brand primary (yellow)
              : AppColors.textSecondary, // ✅ Brand text secondary
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: AppTypography.body1.copyWith( // ✅ Brand typography
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected
              ? AppColors.primary // ✅ Brand primary (yellow)
              : AppColors.black, // ✅ Brand black
        ),
      ),
      subtitle: Text(
        subtitle,
        style: AppTypography.caption, // ✅ Brand typography
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: AppColors.primary) // ✅ Brand primary
          : null,
      onTap: () {
        setState(() {
          _currentMapType = mapType;
        });
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background, // ✅ Brand background
      appBar: AppBar(
        backgroundColor: AppColors.primary, // ✅ Brand primary (yellow)
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.black), // ✅ Black icon on yellow
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Vehicle Tracking",
          style: AppTypography.subtitle1.copyWith( // ✅ Brand typography
            color: AppColors.black, // ✅ Black text on yellow
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.bug_report, color: AppColors.black), // ✅ Black icon
            onPressed: () {
              print('\n🧪 ========== MANUAL DEBUG TEST ==========');
              print('🧪 Socket connected: ${_socketService.isConnected}');
              print('🧪 isSocketConnected: $isSocketConnected');
              print('🧪 Current position: $_currentPosition');
              print('🧪 Map controller: ${_mapController == null ? "NULL ❌" : "READY ✅"}');
              print('🧪 Speed: $speed');
              print('🧪 Car model: $carModel');
              print('🧪 Connection source: $connectionSource');
              print('🧪 Manually rejoining room...');
              _socketService.joinVehicleTracking(widget.vehicleId);
              print('🧪 ======================================\n');
            },
            tooltip: "Debug Test",
          ),
          IconButton(
            icon: Icon(Icons.layers, color: AppColors.black), // ✅ Black icon
            onPressed: _showMapTypeSelector,
            tooltip: "Change map type",
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.black), // ✅ Black icon
            onPressed: fetchVehicleLocation,
            tooltip: "Refresh location",
          ),
        ],
      ),
      body: Stack(
        children: [
          // ✅ GOOGLE MAP - PROPERLY INITIALIZED
          GoogleMap(
            mapType: _currentMapType,
            initialCameraPosition: CameraPosition(
              target: _currentPosition,
              zoom: 16.0,
            ),
            markers: _markers,
            onMapCreated: (GoogleMapController controller) {
              print('\n🗺️ ========== MAP CREATED CALLBACK ==========');
              print('🗺️ Timestamp: ${DateTime.now()}');
              print('🗺️ Controller received from Google Maps');

              _mapController = controller;

              print('✅ Map controller STORED successfully');
              print('✅ Map is now ready for camera operations');
              print('════════════════════════════════════════\n');

              // Move to current position once map is ready
              Future.delayed(const Duration(milliseconds: 500), () {
                _moveCamera(_currentPosition);
              });
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            compassEnabled: true,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // Vehicle Info Card
          if (!isLoading && !hasError)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: EdgeInsets.all(AppSizes.spacingM), // ✅ Brand spacing
                decoration: BoxDecoration(
                  color: AppColors.white, // ✅ Brand white
                  borderRadius: BorderRadius.circular(AppSizes.radiusM), // ✅ Brand radius
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.withOpacity(0.1), // ✅ Brand black
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(AppSizes.spacingM), // ✅ Brand spacing
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight, // ✅ Brand primary light
                            borderRadius: BorderRadius.circular(AppSizes.radiusM),
                          ),
                          child: Icon(
                            Icons.directions_car_rounded,
                            color: AppColors.primary, // ✅ Brand primary (yellow)
                            size: 24,
                          ),
                        ),
                        SizedBox(width: AppSizes.spacingM), // ✅ Brand spacing
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                carModel,
                                style: AppTypography.body1.copyWith( // ✅ Brand typography
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: AppSizes.spacingXS / 2),
                              Row(
                                children: [
                                  Icon(
                                    Icons.speed_rounded,
                                    size: 16,
                                    color: AppColors.textSecondary, // ✅ Brand text secondary
                                  ),
                                  SizedBox(width: AppSizes.spacingXS),
                                  Text(
                                    speed,
                                    style: AppTypography.body2, // ✅ Brand typography
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSizes.spacingM,
                            vertical: AppSizes.spacingXS,
                          ),
                          decoration: BoxDecoration(
                            color: isSocketConnected
                                ? AppColors.success.withOpacity(0.1) // ✅ Brand success light
                                : AppColors.warning.withOpacity(0.1), // ✅ Brand warning light
                            borderRadius: BorderRadius.circular(AppSizes.radiusL),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isSocketConnected
                                      ? AppColors.success // ✅ Brand success
                                      : AppColors.warning, // ✅ Brand warning
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: AppSizes.spacingXS),
                              Text(
                                isSocketConnected ? 'Live' : 'Polling',
                                style: AppTypography.caption.copyWith( // ✅ Brand typography
                                  color: isSocketConnected
                                      ? AppColors.success // ✅ Brand success
                                      : AppColors.warning, // ✅ Brand warning
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSizes.spacingS), // ✅ Brand spacing
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSizes.spacingM,
                        vertical: AppSizes.spacingXS,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.background, // ✅ Brand background
                        borderRadius: BorderRadius.circular(AppSizes.spacingS),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSocketConnected ? Icons.cloud_done : Icons.cloud_off,
                            size: 14,
                            color: AppColors.textSecondary, // ✅ Brand text secondary
                          ),
                          SizedBox(width: AppSizes.spacingXS),
                          Text(
                            connectionSource,
                            style: AppTypography.caption.copyWith( // ✅ Brand typography
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Loading Indicator
          if (isLoading)
            Container(
              color: AppColors.white.withOpacity(0.9), // ✅ Brand white
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary), // ✅ Brand primary
                    SizedBox(height: AppSizes.spacingM), // ✅ Brand spacing
                    Text(
                      "Loading vehicle location...",
                      style: AppTypography.body1.copyWith( // ✅ Brand typography
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Error Card
          if (hasError && !isLoading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: AppColors.white.withOpacity(0.95), // ✅ Brand white
                child: Center(
                  child: Container(
                    padding: EdgeInsets.all(AppSizes.spacingL), // ✅ Brand spacing
                    margin: EdgeInsets.all(AppSizes.spacingL),
                    decoration: BoxDecoration(
                      color: AppColors.white, // ✅ Brand white
                      borderRadius: BorderRadius.circular(AppSizes.radiusL), // ✅ Brand radius
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.black.withOpacity(0.1), // ✅ Brand black
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: EdgeInsets.all(AppSizes.spacingM), // ✅ Brand spacing
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.1), // ✅ Brand error light
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.error_outline,
                            color: AppColors.error, // ✅ Brand error
                            size: 48,
                          ),
                        ),
                        SizedBox(height: AppSizes.spacingL), // ✅ Brand spacing
                        Text(
                          'Location Unavailable',
                          style: AppTypography.subtitle1, // ✅ Brand typography
                        ),
                        SizedBox(height: AppSizes.spacingS), // ✅ Brand spacing
                        Text(
                          errorMessage,
                          style: AppTypography.body2, // ✅ Brand typography
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: AppSizes.spacingL), // ✅ Brand spacing
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: fetchVehicleLocation,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary, // ✅ Brand primary (yellow)
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppSizes.radiusM),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              "Try Again",
                              style: AppTypography.button.copyWith( // ✅ Brand typography
                                color: AppColors.black, // ✅ Black text on yellow
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.white, // ✅ Brand white
              borderRadius: BorderRadius.circular(AppSizes.radiusM), // ✅ Brand radius
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.1), // ✅ Brand black
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                IconButton(
                  icon: Icon(Icons.add, color: AppColors.black), // ✅ Brand black
                  onPressed: () {
                    _mapController?.animateCamera(CameraUpdate.zoomIn());
                  },
                ),
                Container(
                  height: 1,
                  width: 30,
                  color: AppColors.border, // ✅ Brand border
                ),
                IconButton(
                  icon: Icon(Icons.remove, color: AppColors.black), // ✅ Brand black
                  onPressed: () {
                    _mapController?.animateCamera(CameraUpdate.zoomOut());
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: AppSizes.spacingM), // ✅ Brand spacing
          FloatingActionButton.extended(
            onPressed: () {
              _moveCamera(_currentPosition);
            },
            backgroundColor: AppColors.primary, // ✅ Brand primary (yellow)
            elevation: 4,
            label: Text(
              "Center",
              style: AppTypography.button.copyWith( // ✅ Brand typography
                color: AppColors.black, // ✅ Black text on yellow
              ),
            ),
            icon: Icon(Icons.my_location_rounded, color: AppColors.black), // ✅ Black icon
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}