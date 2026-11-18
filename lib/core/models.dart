// 核心数据模型 —— 全 App 共享契约
class UserProfile {
  final String name;
  final String sex;      // male / female
  final int age;
  final double heightCm;
  final double? weightKg;
  const UserProfile({
    required this.name, required this.sex, required this.age,
    required this.heightCm, this.weightKg,
  });
  Map<String, dynamic> toJson() => {
    'name': name, 'sex': sex, 'age': age,
    'heightCm': heightCm, 'weightKg': weightKg,
  };
  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    name: j['name'] as String,
    sex: j['sex'] as String? ?? 'female',
    age: (j['age'] as num?)?.toInt() ?? 24,
    heightCm: (j['heightCm'] as num?)?.toDouble() ?? 163,
    weightKg: (j['weightKg'] as num?)?.toDouble(),
  );
  bool get isMale => sex == 'male';
}

class BodyComposition {
  final String model;
  final double? resistanceOhm;
  final double bodyFatPercent, fatMassKg, fatFreeMassKg;
  final double musclePercent, muscleMassKg, waterPercent, waterMassKg;
  final double proteinPercent, proteinMassKg, bonePercent, boneMassKg;
  final double skeletalMusclePercent, skeletalMuscleMassKg;
  final double subcutaneousFatPercent, subcutaneousFatMassKg;
  const BodyComposition({
    required this.model, this.resistanceOhm,
    required this.bodyFatPercent, required this.fatMassKg, required this.fatFreeMassKg,
    required this.musclePercent, required this.muscleMassKg,
    required this.waterPercent, required this.waterMassKg,
    required this.proteinPercent, required this.proteinMassKg,
    required this.bonePercent, required this.boneMassKg,
    required this.skeletalMusclePercent, required this.skeletalMuscleMassKg,
    required this.subcutaneousFatPercent, required this.subcutaneousFatMassKg,
  });
  Map<String, dynamic> toJson() => {
    'model': model, 'resistance_ohm': resistanceOhm,
    'body_fat_percent': bodyFatPercent, 'fat_mass_kg': fatMassKg,
    'fat_free_mass_kg': fatFreeMassKg, 'muscle_percent': musclePercent,
    'muscle_mass_kg': muscleMassKg, 'water_percent': waterPercent,
    'water_mass_kg': waterMassKg, 'protein_percent': proteinPercent,
    'protein_mass_kg': proteinMassKg, 'bone_percent': bonePercent,
    'bone_mass_kg': boneMassKg,
    'skeletal_muscle_percent': skeletalMusclePercent,
    'skeletal_muscle_mass_kg': skeletalMuscleMassKg,
    'subcutaneous_fat_percent': subcutaneousFatPercent,
    'subcutaneous_fat_mass_kg': subcutaneousFatMassKg,
  };
}

class MeasurementRecord {
  String id;
  String time;           // YYYY-MM-DD HH:MM:SS 本地时间
  String unit;           // 所有者名
  double weightKg;
  double? impedance1, impedance2;
  List<double>? adcs;
  bool electrodeOn;
  String? syncedAt;
  BodyComposition? bodyComposition;
  UserProfile? profile;
  MeasurementRecord({
    required this.id, required this.time, required this.unit, required this.weightKg,
    this.impedance1, this.impedance2, this.adcs, this.electrodeOn = false,
    this.syncedAt, this.bodyComposition, this.profile,
  });
  Map<String, dynamic> toJson() => {
    'id': id, 'time': time, 'unit': unit, 'weight_kg': weightKg,
    'impedance_1': impedance1, 'impedance_2': impedance2, 'adcs': adcs,
    'electrode_on': electrodeOn, 'syncedAt': syncedAt,
    'body_composition': bodyComposition?.toJson(),
    'profile': profile?.toJson(),
  };
  factory MeasurementRecord.fromJson(Map<String, dynamic> j) => MeasurementRecord(
    id: j['id'] as String,
    time: j['time'] as String,
    unit: j['unit'] as String? ?? '',
    weightKg: (j['weight_kg'] as num?)?.toDouble() ?? 0,
    impedance1: (j['impedance_1'] as num?)?.toDouble(),
    impedance2: (j['impedance_2'] as num?)?.toDouble(),
    adcs: (j['adcs'] as List?)?.map((x) => (x as num).toDouble()).toList(),
    electrodeOn: j['electrode_on'] as bool? ?? false,
    syncedAt: j['syncedAt'] as String?,
    bodyComposition: j['body_composition'] != null
        ? _bcFromJson(j['body_composition'] as Map<String, dynamic>) : null,
    profile: j['profile'] != null ? UserProfile.fromJson(j['profile'] as Map<String, dynamic>) : null,
  );
  static BodyComposition _bcFromJson(Map<String, dynamic> j) => BodyComposition(
    model: j['model'] as String? ?? '',
    resistanceOhm: (j['resistance_ohm'] as num?)?.toDouble(),
    bodyFatPercent: (j['body_fat_percent'] as num?)?.toDouble() ?? 0,
    fatMassKg: (j['fat_mass_kg'] as num?)?.toDouble() ?? 0,
    fatFreeMassKg: (j['fat_free_mass_kg'] as num?)?.toDouble() ?? 0,
    musclePercent: (j['muscle_percent'] as num?)?.toDouble() ?? 0,
    muscleMassKg: (j['muscle_mass_kg'] as num?)?.toDouble() ?? 0,
    waterPercent: (j['water_percent'] as num?)?.toDouble() ?? 0,
    waterMassKg: (j['water_mass_kg'] as num?)?.toDouble() ?? 0,
    proteinPercent: (j['protein_percent'] as num?)?.toDouble() ?? 0,
    proteinMassKg: (j['protein_mass_kg'] as num?)?.toDouble() ?? 0,
    bonePercent: (j['bone_percent'] as num?)?.toDouble() ?? 0,
    boneMassKg: (j['bone_mass_kg'] as num?)?.toDouble() ?? 0,
    skeletalMusclePercent: (j['skeletal_muscle_percent'] as num?)?.toDouble() ?? 0,
    skeletalMuscleMassKg: (j['skeletal_muscle_mass_kg'] as num?)?.toDouble() ?? 0,
    subcutaneousFatPercent: (j['subcutaneous_fat_percent'] as num?)?.toDouble() ?? 0,
    subcutaneousFatMassKg: (j['subcutaneous_fat_mass_kg'] as num?)?.toDouble() ?? 0,
  );
}

class PendingHistory {
  final String key, timeStr;
  final double weightKg;
  final double? impedance1, impedance2;
  final bool lowWeight;
  const PendingHistory({
    required this.key, required this.timeStr, required this.weightKg,
    this.impedance1, this.impedance2, this.lowWeight = false,
  });
  Map<String, dynamic> toJson() => {
    'key': key, 'timeStr': timeStr, 'weight_kg': weightKg,
    'impedance_1': impedance1, 'impedance_2': impedance2, 'lowWeight': lowWeight,
  };
  factory PendingHistory.fromJson(Map<String, dynamic> j) => PendingHistory(
    key: j['key'] as String, timeStr: j['timeStr'] as String,
    weightKg: (j['weight_kg'] as num?)?.toDouble() ?? 0,
    impedance1: (j['impedance_1'] as num?)?.toDouble(),
    impedance2: (j['impedance_2'] as num?)?.toDouble(),
    lowWeight: j['lowWeight'] as bool? ?? false,
  );
}

class BoundDevice {
  final String id, name, model, boundAt;
  const BoundDevice({
    required this.id, required this.name, required this.model, required this.boundAt,
  });
  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'model': model, 'boundAt': boundAt,
  };
  factory BoundDevice.fromJson(Map<String, dynamic> j) => BoundDevice(
    id: j['id'] as String, name: j['name'] as String? ?? '',
    model: j['model'] as String? ?? 'AFU-WL-TZ-A1',
    boundAt: j['boundAt'] as String? ?? '',
  );
}

enum DisplayUnit { kg, lb, jin }

class ScaleInfo {
  String? manufacturer, model, firmware, software;
  int? battery;
  String? updatedAt;
  ScaleInfo();
  Map<String, dynamic> toJson() => {
    'manufacturer': manufacturer, 'model': model, 'firmware': firmware,
    'software': software, 'battery': battery, 'updatedAt': updatedAt,
  };
  factory ScaleInfo.fromJson(Map<String, dynamic> j) => ScaleInfo()
    ..manufacturer = j['manufacturer'] as String?
    ..model = j['model'] as String?
    ..firmware = j['firmware'] as String?
    ..software = j['software'] as String?
    ..battery = (j['battery'] as num?)?.toInt()
    ..updatedAt = j['updatedAt'] as String?;
}