// lib/models/vehicle_model.dart

class Vehicle {
  final int id;
  final String model;
  final String immatriculation;
  final bool isOnline;
  final String color;
  final String brand;
  final String nickname;

  Vehicle({
    required this.id,
    required this.model,
    required this.immatriculation,
    required this.isOnline,
    required this.color,
    required this.brand,
    required this.nickname,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json["id"],
      model: json["model"] ?? "Unknown Model",
      immatriculation: json["immatriculation"] ?? "",
      isOnline: json["is_online"] ?? false,
      color: json["couleur"] ?? json["color"] ?? "#3B82F6",
      brand: json["marque"] ?? json["brand"] ?? "Unknown",
      nickname: json["nickname"] ?? "",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "model": model,
      "immatriculation": immatriculation,
      "is_online": isOnline,
      "color": color,
      "brand": brand,
      "nickname": nickname,
    };
  }

  Vehicle copyWith({
    int? id,
    String? model,
    String? immatriculation,
    bool? isOnline,
    String? color,
    String? brand,
    String? nickname,
  }) {
    return Vehicle(
      id: id ?? this.id,
      model: model ?? this.model,
      immatriculation: immatriculation ?? this.immatriculation,
      isOnline: isOnline ?? this.isOnline,
      color: color ?? this.color,
      brand: brand ?? this.brand,
      nickname: nickname ?? this.nickname,
    );
  }

  @override
  String toString() {
    return 'Vehicle(id: $id, brand: $brand, model: $model, nickname: $nickname, immatriculation: $immatriculation, isOnline: $isOnline)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Vehicle && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}