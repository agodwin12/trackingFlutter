// lib/models/safe_zone_model.dart
class SafeZone {
  final int id;
  final int userId;
  final int vehicleId;
  final String name;
  final double centerLatitude;
  final double centerLongitude;
  final int radiusMeters;
  final bool isActive;
  final bool alertTriggered;
  final DateTime? lastAlertAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  SafeZone({
    required this.id,
    required this.userId,
    required this.vehicleId,
    required this.name,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.radiusMeters,
    required this.isActive,
    required this.alertTriggered,
    this.lastAlertAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SafeZone.fromJson(Map<String, dynamic> json) {
    return SafeZone(
      id: json['id'],
      userId: json['user_id'],
      vehicleId: json['vehicle_id'],
      name: json['name'] ?? 'Safe Zone',
      centerLatitude: double.parse(json['center_latitude'].toString()),
      centerLongitude: double.parse(json['center_longitude'].toString()),
      radiusMeters: json['radius_meters'],
      isActive: json['is_active'],
      alertTriggered: json['alert_triggered'] ?? false,
      lastAlertAt: json['last_alert_at'] != null
          ? DateTime.parse(json['last_alert_at'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'vehicle_id': vehicleId,
      'name': name,
      'center_latitude': centerLatitude,
      'center_longitude': centerLongitude,
      'radius_meters': radiusMeters,
      'is_active': isActive,
      'alert_triggered': alertTriggered,
      'last_alert_at': lastAlertAt?.toIso8601String(),
    };
  }

  SafeZone copyWith({
    int? id,
    int? userId,
    int? vehicleId,
    String? name,
    double? centerLatitude,
    double? centerLongitude,
    int? radiusMeters,
    bool? isActive,
    bool? alertTriggered,
    DateTime? lastAlertAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SafeZone(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      vehicleId: vehicleId ?? this.vehicleId,
      name: name ?? this.name,
      centerLatitude: centerLatitude ?? this.centerLatitude,
      centerLongitude: centerLongitude ?? this.centerLongitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      isActive: isActive ?? this.isActive,
      alertTriggered: alertTriggered ?? this.alertTriggered,
      lastAlertAt: lastAlertAt ?? this.lastAlertAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}