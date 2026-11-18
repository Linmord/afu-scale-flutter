// Scale27 协议解析 —— 从 TS/Python 移植，实测验证
import 'dart:convert';
import 'dart:typed_data';
import 'models.dart';

class HistoryEvent {
  final int time;        // unix 秒
  final double weightKg;
  final List<double> adcs;
  const HistoryEvent({required this.time, required this.weightKg, required this.adcs});
}

class MeasurementTick {
  final double weightKg;
  final double? impedance1, impedance2;
  final int? battery;
  final String phase;     // weighing / impedance / done
  final bool locked;
  final bool timedOut;
  final List<int> adcs;
  const MeasurementTick({
    required this.weightKg, this.impedance1, this.impedance2, this.battery,
    required this.phase, required this.locked, this.timedOut = false,
    required this.adcs,
  });
}

class ScaleProtocol {
  // ---- 命令帧构造 ac 27/29 + payload + 标识 + 校验 ----
  static Uint8List frame(List<int> payload, {int deviceType = 0x29, int tail = 0xD0}) {
    final p = Uint8List(20);
    p[0] = 0xAC;
    p[1] = deviceType & 0xFF;
    for (var i = 0; i < payload.length && i + 2 < 18; i++) {
      p[2 + i] = payload[i] & 0xFF;
    }
    p[18] = tail & 0xFF;
    var sum = 0;
    for (var i = 2; i < 19; i++) { sum = (sum + p[i]) & 0xFF; }
    p[19] = sum;
    return p;
  }

  // 官方完整握手（vitaloop/AntAF 模式：weight=0, target=0）
  static Uint8List handshake({
    required int nowSec, required int utcQuarters, required int height,
    required int age, required int sexValue, int deviceType = 0x29,
  }) {
    return frame([
      (nowSec >> 24) & 0xFF, (nowSec >> 16) & 0xFF, (nowSec >> 8) & 0xFF, nowSec & 0xFF,
      utcQuarters & 0xFF, 0, 1, height & 0xFF,
      0, 0, age & 0xFF, sexValue & 0xFF,
      0, 0, 0x03, 0,
    ], deviceType: deviceType, tail: 0xD0);
  }

  // 对时 08
  static Uint8List cmdTime(int nowSec, int utcQuarters, {int deviceType = 0x29}) =>
      frame([0x08, (nowSec>>24)&0xFF, (nowSec>>16)&0xFF, (nowSec>>8)&0xFF, nowSec&0xFF, utcQuarters&0xFF],
          deviceType: deviceType, tail: 0xDF);

  // 请求数据 04 d6(ADC) / 04 d8(历史)
  static Uint8List cmdData(int sub, {int deviceType = 0x29}) =>
      frame([0x04, sub], deviceType: deviceType, tail: 0xDF);

  // ---- 通知包解析（20字节 ac xx ...）----
  static MeasurementTick? parseNotify(Uint8List d, {int? stableBattery, bool timedOut = false}) {
    if (d.length < 13 || d[0] != 0xAC) return null;
    final type = d[2];

    // type=01 历史记录（明文）：时间戳 data[3:7]，体重 data[8:11]，阻抗 data[11:15]
    if (type == 0x01 && d.length >= 15) {
      final time = (d[3]<<24 | d[4]<<16 | d[5]<<8 | d[6]) & 0xFFFFFFFF;
      final wRaw = ((d[8]<<16) | (d[9]<<8) | d[10]) - 0x680000;
      final kg = (wRaw / 1000 * 100).roundToDouble() / 100;
      // 历史通过 onHistory 处理，这里不返回 tick
      return null;
    }

    // type=00/80 体重包 / type=02 锁定包
    if (type != 0x00 && type != 0x80 && type != 0x02) return null;
    double kg;
    if (type == 0x02) {
      // 锁定包：体重 data[10:13] - 0x680000
      final wRaw = ((d[10]<<16) | (d[11]<<8) | d[12]) - 0x680000;
      kg = (wRaw / 1000 * 100).roundToDouble() / 100;
    } else {
      // 实时/稳定包：与 RN 实测版一致的公式 (data[3]-0x68)*65536 + data[4]*256 + data[5]
      final wRaw = (d[3] - 0x68) * 65536 + d[4] * 256 + d[5];
      kg = (wRaw / 1000.0 * 100).roundToDouble() / 100;
    }
    if (kg < 0) return null;

    // 阻抗：锁定包 data[4:8] 两组；实时包 data[8:10]
    List<int> adcs = [];
    double? imp1, imp2;
    if (type == 0x02) {
      imp1 = ((d[4]<<8)|d[5]).toDouble();
      imp2 = ((d[6]<<8)|d[7]).toDouble();
      adcs = [d[4]<<8|d[5], d[6]<<8|d[7]];
    } else if (d.length > 9) {
      final v = (d[8]<<8)|d[9];
      adcs = [v];
    }

    // 电量：实时包 data[11] 低7位（排除测量状态 100）；稳定包是状态字节
    int? battery;
    if (type == 0x00 && d.length > 11) {
      final raw = d[11] & 0x7F;
      if (raw > 0 && raw < 100) battery = raw;
    }

    // 阶段：锁定=done；稳定包且状态100=impedance；否则 weighing
    final stateByte = d.length > 11 ? d[11] : 0;
    String phase;
    if (type == 0x02) phase = 'done';
    else if ((type == 0x80 || type == 0x00) && stateByte >= 100) phase = 'impedance';
    else phase = 'weighing';

    return MeasurementTick(
      weightKg: kg, impedance1: imp1, impedance2: imp2, battery: battery,
      phase: phase, locked: type == 0x02, timedOut: timedOut, adcs: adcs,
    );
  }

  // 解析历史包 type01
  static HistoryEvent? parseHistory(Uint8List d) {
    if (d.length < 15 || d[0] != 0xAC || d[2] != 0x01) return null;
    final time = (d[3]<<24 | d[4]<<16 | d[5]<<8 | d[6]) & 0xFFFFFFFF;
    final wRaw = ((d[8]<<16) | (d[9]<<8) | d[10]) - 0x680000;
    final kg = (wRaw / 1000 * 100).roundToDouble() / 100;
    final imp1 = ((d[11]<<8)|d[12]).toDouble();
    final imp2 = ((d[13]<<8)|d[14]).toDouble();
    return HistoryEvent(time: time, weightKg: kg, adcs: [imp1, imp2]);
  }
}