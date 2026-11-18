// 显示单位换算。内部一律存 kg，只在展示层换算。
import 'models.dart';

const double _lbPerKg = 2.2046226218;
const double _jinPerKg = 2.0;

extension DisplayUnitX on DisplayUnit {
  /// kg → 当前单位。
  double fromKg(double kg) {
    switch (this) {
      case DisplayUnit.kg: return kg;
      case DisplayUnit.lb: return kg * _lbPerKg;
      case DisplayUnit.jin: return kg * _jinPerKg;
    }
  }

  /// 当前单位 → kg。
  double toKg(double value) {
    switch (this) {
      case DisplayUnit.kg: return value;
      case DisplayUnit.lb: return value / _lbPerKg;
      case DisplayUnit.jin: return value / _jinPerKg;
    }
  }

  /// 单位后缀（斤用中文，kg/lb 用符号）。
  String get suffix {
    switch (this) {
      case DisplayUnit.kg: return 'kg';
      case DisplayUnit.lb: return 'lb';
      case DisplayUnit.jin: return '斤';
    }
  }

  /// 小数位：kg/lb 两位，斤一位（斤本身精度低）。
  int get digits => this == DisplayUnit.jin ? 1 : 2;

  /// 格式化数值（不含单位）。
  String num(double kg) => fromKg(kg).toStringAsFixed(digits);

  /// 格式化带单位，如 '176.60 lb'。
  String fmt(double kg) => num(kg) + ' ' + suffix;
}