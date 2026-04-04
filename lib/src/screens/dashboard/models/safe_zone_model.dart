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
    // ── Helpers ──────────────────────────────────────────────────────────────
    // Sequelize returns camelCase (createdAt) from direct model responses
    // but snake_case (created_at) from raw SQL / some serializers.
    // Both are handled here so fromJson is robust regardless of source.

    String? _str(dynamic v) => v?.toString();

    double _double(dynamic v) =>
        v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

    int _int(dynamic v) =>
        v == null ? 0 : int.tryParse(v.toString()) ?? 0;

    bool _bool(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      if (v is num) return v != 0;
      return v.toString() == '1' || v.toString().toLowerCase() == 'true';
    }

    DateTime _date(dynamic v) {
      if (v == null) return DateTime.now();
      final s = v.toString();
      return DateTime.tryParse(s) ?? DateTime.now();
    }

    DateTime? _dateNullable(dynamic v) {
      if (v == null) return null;
      final s = v.toString();
      return DateTime.tryParse(s);
    }

    // ── Field resolution — camelCase first, snake_case fallback ──────────────
    return SafeZone(
      id:              _int(json['id']),
      userId:          _int(json['user_id']     ?? json['userId']),
      vehicleId:       _int(json['vehicle_id']  ?? json['vehicleId']),
      name:            _str(json['name'])        ?? 'Safe Zone',
      centerLatitude:  _double(json['center_latitude']  ?? json['centerLatitude']),
      centerLongitude: _double(json['center_longitude'] ?? json['centerLongitude']),
      radiusMeters:    _int(json['radius_meters']       ?? json['radiusMeters']),
      isActive:        _bool(json['is_active']          ?? json['isActive']),
      alertTriggered:  _bool(json['alert_triggered']    ?? json['alertTriggered']),
      lastAlertAt:     _dateNullable(json['last_alert_at']  ?? json['lastAlertAt']),
      createdAt:       _date(json['created_at']             ?? json['createdAt']),
      updatedAt:       _date(json['updated_at']             ?? json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id':               id,
      'user_id':          userId,
      'vehicle_id':       vehicleId,
      'name':             name,
      'center_latitude':  centerLatitude,
      'center_longitude': centerLongitude,
      'radius_meters':    radiusMeters,
      'is_active':        isActive,
      'alert_triggered':  alertTriggered,
      'last_alert_at':    lastAlertAt?.toIso8601String(),
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
      id:              id              ?? this.id,
      userId:          userId          ?? this.userId,
      vehicleId:       vehicleId       ?? this.vehicleId,
      name:            name            ?? this.name,
      centerLatitude:  centerLatitude  ?? this.centerLatitude,
      centerLongitude: centerLongitude ?? this.centerLongitude,
      radiusMeters:    radiusMeters    ?? this.radiusMeters,
      isActive:        isActive        ?? this.isActive,
      alertTriggered:  alertTriggered  ?? this.alertTriggered,
      lastAlertAt:     lastAlertAt     ?? this.lastAlertAt,
      createdAt:       createdAt       ?? this.createdAt,
      updatedAt:       updatedAt       ?? this.updatedAt,
    );
  }
}