class EquipmentMaster {
  final String id;
  final String name;
  final String? iconUrl;
  final String? imageUrl;

  const EquipmentMaster({
    required this.id,
    required this.name,
    this.iconUrl,
    this.imageUrl,
  });

  factory EquipmentMaster.fromJson(Map<String, dynamic> json) {
    return EquipmentMaster(
      id: json['id'],
      name: json['name'],
      iconUrl: json['icon_url'],
      imageUrl: json['image_url'],
    );
  }
}

/// Equipment reference within an instruction step, with placeholder key for template interpolation.
/// Used in instruction templates like: "Heat oil in the {e:pan}"
class StepEquipment {
  final String id;
  final EquipmentMaster master;
  final String placeholderKey; // e.g., "pan", "dutch_oven", "wok"

  const StepEquipment({
    required this.id,
    required this.master,
    required this.placeholderKey,
  });

  factory StepEquipment.fromJson(Map<String, dynamic> json) {
    return StepEquipment(
      id: json['id'] ?? '',
      master: EquipmentMaster.fromJson(json['equipment_master'] ?? json['master'] ?? {}),
      placeholderKey: json['placeholder_key'] ?? '',
    );
  }
}
