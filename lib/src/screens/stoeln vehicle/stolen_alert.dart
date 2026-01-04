// lib/src/screens/stolen_vehicle/stolen_alert.dart

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utility/app_theme.dart';

class StolenAlertScreen extends StatefulWidget {
  final int vehicleId;
  final double vehicleLat;
  final double vehicleLng;
  final String vehicleName;
  final List<dynamic>? nearbyPolice;

  const StolenAlertScreen({
    Key? key,
    required this.vehicleId,
    required this.vehicleLat,
    required this.vehicleLng,
    required this.vehicleName,
    this.nearbyPolice,
  }) : super(key: key);

  @override
  State<StolenAlertScreen> createState() => _StolenAlertScreenState();
}

class _StolenAlertScreenState extends State<StolenAlertScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _buildMarkers();
  }

  void _buildMarkers() {
    _markers.clear();

    // Vehicle marker (RED - STOLEN)
    _markers.add(
      Marker(
        markerId: const MarkerId('vehicle'),
        position: LatLng(widget.vehicleLat, widget.vehicleLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: '🚨 STOLEN VEHICLE',
          snippet: widget.vehicleName,
        ),
      ),
    );

    // Police station markers (BLUE)
    if (widget.nearbyPolice != null) {
      for (var i = 0; i < widget.nearbyPolice!.length; i++) {
        final police = widget.nearbyPolice![i];
        _markers.add(
          Marker(
            markerId: MarkerId('police_$i'),
            position: LatLng(
              (police['latitude'] as num).toDouble(),
              (police['longitude'] as num).toDouble(),
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueBlue),
            infoWindow: InfoWindow(
              title: police['name'],
              snippet: '${police['distance']} km away',
            ),
          ),
        );
      }
    }

    setState(() {});
  }

  Future<void> _callPolice(String? phoneNumber) async {
    if (phoneNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Phone number not available')),
      );
      return;
    }

    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    }
  }

  Future<void> _openInMaps(double lat, double lng, String name) async {
    final Uri mapsUri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(mapsUri)) {
      await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Stack(
                children: [
                  // Map
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(widget.vehicleLat, widget.vehicleLng),
                      zoom: 14,
                    ),
                    markers: _markers,
                    onMapCreated: (controller) {
                      _mapController = controller;
                    },
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                  ),

                  // Police stations list
                  if (widget.nearbyPolice != null &&
                      widget.nearbyPolice!.isNotEmpty)
                    _buildPoliceList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(AppSizes.spacingL),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.error, AppColors.error.withOpacity(0.8)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.arrow_back, color: Colors.white),
              ),
              SizedBox(width: AppSizes.spacingM),
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 32),
              SizedBox(width: AppSizes.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🚨 VEHICLE STOLEN',
                      style: AppTypography.h3.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Engine Disabled',
                      style: AppTypography.body2.copyWith(
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSizes.spacingM),
          Container(
            padding: EdgeInsets.all(AppSizes.spacingM),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
            child: Row(
              children: [
                Icon(Icons.directions_car, color: Colors.white, size: 20),
                SizedBox(width: AppSizes.spacingS),
                Expanded(
                  child: Text(
                    widget.vehicleName,
                    style: AppTypography.body1.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
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

  Widget _buildPoliceList() {
    return DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.15,
      maxChildSize: 0.7,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: EdgeInsets.symmetric(vertical: AppSizes.spacingM),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingL),
                child: Row(
                  children: [
                    Icon(Icons.local_police, color: AppColors.primary, size: 24),
                    SizedBox(width: AppSizes.spacingM),
                    Text(
                      'Nearby Police Stations',
                      style: AppTypography.h3,
                    ),
                  ],
                ),
              ),

              SizedBox(height: AppSizes.spacingM),

              // Police list
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingL),
                  itemCount: widget.nearbyPolice!.length,
                  separatorBuilder: (context, index) =>
                      Divider(height: 1, thickness: 1),
                  itemBuilder: (context, index) {
                    final police = widget.nearbyPolice![index];
                    return _buildPoliceCard(police);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPoliceCard(Map<String, dynamic> police) {
    final bool? isOpen = police['isOpen'];
    final String distance = '${police['distance']} km';

    return Container(
      padding: EdgeInsets.symmetric(vertical: AppSizes.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(AppSizes.spacingM),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                ),
                child: Icon(
                  Icons.local_police,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              SizedBox(width: AppSizes.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      police['name'],
                      style: AppTypography.body1.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: AppSizes.spacingXS),
                    Text(
                      police['address'],
                      style: AppTypography.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: AppSizes.spacingS),
                    Row(
                      children: [
                        Icon(Icons.my_location,
                            size: 14, color: AppColors.textSecondary),
                        SizedBox(width: 4),
                        Text(
                          distance,
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isOpen != null) ...[
                          SizedBox(width: AppSizes.spacingM),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppSizes.spacingS,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isOpen
                                  ? AppColors.success.withOpacity(0.1)
                                  : AppColors.error.withOpacity(0.1),
                              borderRadius:
                              BorderRadius.circular(AppSizes.radiusS),
                            ),
                            child: Text(
                              isOpen ? 'OPEN' : 'CLOSED',
                              style: AppTypography.caption.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isOpen ? AppColors.success : AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSizes.spacingM),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openInMaps(
                    (police['latitude'] as num).toDouble(),
                    (police['longitude'] as num).toDouble(),
                    police['name'],
                  ),
                  icon: Icon(Icons.directions, size: 18),
                  label: Text('Directions'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusM),
                    ),
                  ),
                ),
              ),
              SizedBox(width: AppSizes.spacingM),
              ElevatedButton.icon(
                onPressed: () => _callPolice('117'), // Emergency number Cameroon
                icon: Icon(Icons.phone, size: 18),
                label: Text('Call'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}