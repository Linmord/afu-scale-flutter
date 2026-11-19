// BIA 体脂公式 —— 提供三种可切换的算法（用户可在设置里选择）。
//
// officialAnt : 对齐蚂蚁健康 App 显示值（实测反推系数，与官方逐项一致）。
//              男性不含阻抗（官方行为），女性含阻抗。
// paperDeurenberg : Deurenberg 1991 论文原式（1.20×BMI + 0.23×年龄 − 10.8×性别 − 5.4），
//              纯 BMI 型，不使用阻抗；独立于官方 App。
// paperSegal  : Segal 1988 阻抗式（男女都用阻抗）。男性专属系数无法可靠取得，
//              男女统一用实测验证过的女性回归式；男性读数偏高，仅供看趋势。
import 'dart:math';
import 'models.dart';

class BodyCompositionCalc {
  static bool _isMale(String sex) =>
      ['male','m','man','男','1'].contains(sex.trim().toLowerCase());
  static double _clamp(double v, double lo, double hi) => v.clamp(lo, hi).toDouble();
  static double _r1(double v) => (v * 10).roundToDouble() / 10;

  /// 算法标识：officialAnt / paperDeurenberg / paperSegal
  static String normalizeAlgo(String? v) {
    if (v == 'paperDeurenberg') return 'paperDeurenberg';
    if (v == 'paperSegal') return 'paperSegal';
    return 'officialAnt';
  }

  /// Deurenberg 1991 论文原式：BF% = 1.20×BMI + 0.23×age − 10.8×sex − 5.4（男=1 女=0）
  static double _deurenbergPaper(double bmi, int age, bool male) {
    return 1.20 * bmi + 0.23 * age - 10.8 * (male ? 1 : 0) - 5.4;
  }


  /// Segal 1988（女性式，含肥胖分支）
  static double _segalFemaleFFM(double hCm, double wKg, int age, double r) {
    final h2 = hCm * hCm;
    final first = 10.43485 + 0.00064602 * h2 - 0.01397 * r + 0.42087 * wKg;
    final bfGuess = 100 * (wKg - first) / wKg;
    if (bfGuess < 30) return first;
    return 9.37938 + 0.00091186 * h2 - 0.01466 * r + 0.29990 * wKg - 0.07012 * age;
  }

  // 阻抗合成：两个 ADC 之和 ×0.675（实测命中蚂蚁体脂率）
  static double? _resistance(List<double>? imps) {
    if (imps == null || imps.isEmpty) return null;
    final valid = imps.where((v) => v > 0).toList();
    if (valid.isEmpty) return null;
    if (valid.length >= 2) return (valid[0] + valid[1]) * 0.675;
    return valid[0] >= 100 && valid[0] <= 1500 ? valid[0] : null;
  }

  static BodyComposition? estimate({
    required double weightKg, required double heightCm,
    required int age, required String sex, List<double>? impedances,
    String algo = 'officialAnt',
  }) {
    if (weightKg <= 0 || heightCm <= 0 || age <= 0) return null;
    final male = _isMale(sex);
    final res = _resistance(impedances);
    final bmi = weightKg / (heightCm / 100 * heightCm / 100);

    late double bf;
    String model;
    final algoN = normalizeAlgo(algo);
    if (algoN == 'paperDeurenberg') {
      // 论文原式：男女同一式，不用阻抗
      bf = _deurenbergPaper(bmi, age, male);
      model = male ? 'deurenberg1991_male' : 'deurenberg1991_female';
    } else if (algoN == 'paperSegal' && res != null && res >= 100 && res <= 1500) {
      // 论文 Segal（阻抗参与，男女通用）。
      // 注：Segal 1988 的男性专属回归系数无法从公开渠道可靠取得，
      // 这里男女统一使用经实测验证的女性回归式（3C/3D 双分支）。
      // 男性读数会系统性偏高（约 +5~13pp），适合观察趋势而非绝对值。
      final ffm = _segalFemaleFFM(heightCm, weightKg, age, res);
      final ffmClamped = ffm.clamp(weightKg*0.35, weightKg*0.97).toDouble();
      bf = 100 * (weightKg - ffmClamped) / weightKg;
      model = male ? 'segal1988_shared' : (100*(weightKg-ffm)/weightKg < 30 ? 'segal1988_3c' : 'segal1988_3d');
    } else if (male) {
      // 官方蚂蚁：男性不含阻抗（实测反推校准版）
      bf = 1.10 * bmi + 0.23 * age - 11.22;
      model = 'deurenberg_jp_male';
    } else if (res != null && res >= 100 && res <= 1500) {
      // 女性：Segal + 合成阻抗（实测 79.95kg→37.7%）
      final h2 = heightCm * heightCm;
      double ffm;
      final first = 10.43485 + 0.00064602*h2 - 0.01397*res + 0.42087*weightKg;
      if (100 * (weightKg - first) / weightKg < 30) {
        ffm = first; model = 'segal_3c_female_lt30';
      } else {
        ffm = 9.37938 + 0.00091186*h2 - 0.01466*res + 0.29990*weightKg - 0.07012*age;
        model = 'segal_3d_female_ge30';
      }
      ffm = ffm.clamp(weightKg*0.35, weightKg*0.97).toDouble();
      bf = 100 * (weightKg - ffm) / weightKg;
    } else {
      bf = 1.10 * bmi + 0.23 * age - 5.4;
      model = 'deurenberg_jp_female';
    }

    bf = _clamp(bf, male ? 3.0 : 8.0, 60.0);
    final fatMass = weightKg * bf / 100;
    final ffmMass = weightKg - fatMass;
    final bonePct = male ? 4.5 : 4.0;
    final musclePct = _clamp(100 - bf - bonePct, 20, 95);
    final leanPct = 100 - bf;
    final waterPct = _clamp(leanPct * (male ? 0.7185 : 0.8475), 25, 80);
    final proteinMass = weightKg * (male ? 0.163 : 0.05);
    final skeletalPct = _clamp(musclePct * (male ? 0.548 : 0.651), 10, 70);
    final subcutPct = _clamp(bf * (male ? 0.7165 : 0.72), 1, bf);

    return BodyComposition(
      model: model,
      resistanceOhm: res != null ? (res*100).roundToDouble()/100 : null,
      bodyFatPercent: _r1(bf), fatMassKg: _r1(fatMass), fatFreeMassKg: _r1(ffmMass),
      musclePercent: _r1(musclePct), muscleMassKg: _r1(weightKg*musclePct/100),
      waterPercent: _r1(waterPct), waterMassKg: _r1(weightKg*waterPct/100),
      proteinPercent: _r1(proteinMass/weightKg*100), proteinMassKg: _r1(proteinMass),
      bonePercent: _r1(bonePct), boneMassKg: _r1(weightKg*bonePct/100),
      skeletalMusclePercent: _r1(skeletalPct), skeletalMuscleMassKg: _r1(weightKg*skeletalPct/100),
      subcutaneousFatPercent: _r1(subcutPct), subcutaneousFatMassKg: _r1(weightKg*subcutPct/100),
    );
  }
}