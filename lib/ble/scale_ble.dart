// BLE 管理器 —— flutter_blue_plus，已实测 1 秒扫到秤
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/models.dart';
import '../core/protocol.dart';
import '../data/debug_log.dart';
import '../data/store.dart';
import 'comm_log.dart';

class ScanHit {
  final BluetoothDevice device;
  final String name;
  final int rssi;
  final String realMac;
  ScanHit({required this.device, required this.name, required this.rssi, required this.realMac});
}

class ScaleBle extends ChangeNotifier {
  static final ScaleBle instance = ScaleBle._();
  ScaleBle._();

  BluetoothDevice? _connected;
  BluetoothCharacteristic? _writeChar;
  StreamSubscription? _scanSub;
  StreamSubscription? _isScanningSub;
  StreamSubscription? _notifySub;
  StreamSubscription? _stateSub;
  bool _scanning = false;
  bool _stopped = false;
  Timer? _reconnectTimer;
  Timer? _commFlushTimer;
  ScaleInfo? _devInfo;
  int _batteryVote = 0;
  int _batteryVoteCount = 0;
  DateTime? _measureStart;

  final _hits = <String, ScanHit>{};
  List<ScanHit> get hits => _hits.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
  bool get scanning => _scanning;
  BluetoothDevice? get connected => _connected;

  // 回调
  Function(MeasurementTick)? onTick;
  Function(HistoryEvent)? onHistory;
  Function(String state, String detail)? onState;
  Function(ScaleInfo)? onDeviceInfo;
  /// 档案体重被实测值回填后触发，供 UI 提示。
  Function(double kg)? onProfileWeightUpdated;
  /// 语义化通讯事件流，供测量页做可视化。
  Function(CommEvent)? onComm;

  Future<bool> requestPerms() async {
    final res = await [
      Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse,
    ].request();
    return res.values.every((s) => s.isGranted);
  }

  String? scanError;

  Future<void> startScan() async {
    scanError = null;
    developer.log("SCAN_STEP: begin");
    try {
      developer.log("SCAN_STEP: requesting perms");
      final granted = await requestPerms();
      developer.log("SCAN_STEP: perms=" + granted.toString());
      if (!granted) {
        scanError = '蓝牙/定位权限未授予，请在系统设置中开启';
        DebugLog.instance.log(scanError!);
        notifyListeners();
        return;
      }
      // 注意：adapterState.first 在某些机型启动时永不发值会永久挂起，必须加超时兜底
      BluetoothAdapterState adapter = BluetoothAdapterState.unknown;
      try {
        adapter = await FlutterBluePlus.adapterState
            .first
            .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);
      } catch (_) {}
      if (adapter == BluetoothAdapterState.off) {
        scanError = '系统蓝牙未开启';
        DebugLog.instance.log(scanError!);
        notifyListeners();
        return;
      }
      if (_scanning) return;
    _hits.clear();
    _scanning = true;
    DebugLog.instance.log('扫描启动');
    notifyListeners();
    // 扫描自然结束（超时/系统停止）时复位状态。
    // 注意：isScanning 是 BehaviorSubject，订阅会立刻回放当前值 false，
    // 若直接监听会把刚设为 true 的 _scanning 打回 false（动画消失的根因）。
    // 因此先跳过第一个回放值。
    _isScanningSub?.cancel();
    var skipFirstReplay = true;
    _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (skipFirstReplay) {
        skipFirstReplay = false;
        return;
      }
      if (!scanning && _scanning) {
        _scanning = false;
        DebugLog.instance.log('扫描已结束');
        notifyListeners();
      }
    });
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 180));
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName : (r.advertisementData.localName ?? '');
        List<int> afu = [];
        r.advertisementData.serviceData.forEach((k, v) {
          if (k.toString().toLowerCase().contains('27ac')) afu = v;
        });
        final isScale = name.toUpperCase().contains('AFU-WL') || afu.isNotEmpty;
        if (!isScale) continue;
        developer.log("SCAN_STEP: FOUND " + name);
        String mac = '-';
        if (afu.length >= 6) {
          mac = afu.sublist(0, 6).reversed
              .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
        }
        final key = r.device.remoteId.toString();
        final isNew = !_hits.containsKey(key);
        _hits[key] = ScanHit(device: r.device, name: name, rssi: r.rssi, realMac: mac);
        if (isNew) {
          DebugLog.instance.log('发现秤 ' + key + ' name=' + name + ' MAC=' + mac);
          notifyListeners();
        }
      }
    });
    } catch (e) {
      _scanning = false;
      scanError = '扫描启动失败: ' + e.toString();
      DebugLog.instance.log(scanError!);
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    if (!_scanning) return;
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _scanSub = null;
    _isScanningSub?.cancel();
    _isScanningSub = null;
    _scanning = false;
    DebugLog.instance.log('停止扫描');
    notifyListeners();
  }

  bool _connecting = false;

  Future<void> connect(ScanHit hit, UserProfile profile) async {
    // 防并发：断线重连定时器可能在握手期间再次触发，导致同一会话发两遍握手，
    // 秤会把它当作新的同步会话从而反复重推历史。
    if (_connecting) {
      DebugLog.instance.log('已在连接中，忽略重复 connect');
      return;
    }
    _connecting = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await stopScan();
    _stopped = false;
    _weightSyncedThisSession = false;
    final useId = hit.realMac != '-' ? hit.realMac : hit.device.remoteId.toString();
    onState?.call('connecting', '连接 $useId');
    DebugLog.instance.log('连接 $useId');
    try {
      final dev = BluetoothDevice.fromId(useId);
      await dev.connect(timeout: const Duration(seconds: 12));
      _connected = dev;
      await dev.discoverServices();
      BluetoothCharacteristic? writeC;
      for (final s in dev.servicesList) {
        for (final c in s.characteristics) {
          final cu = c.uuid.toString().toLowerCase();
          if (cu.contains('ffb2')) {
            await c.setNotifyValue(true);
            _notifySub?.cancel();
            _notifySub = c.onValueReceived.listen((v) => _handleNotify(Uint8List.fromList(v)));
            DebugLog.instance.log('订阅通知成功');
          }
          if (cu.contains('ffb1')) writeC = c;
        }
      }
      DebugLog.instance.log('特征: write=' + (writeC != null ? 'OK' : 'MISSING') + ' notify=' + (_notifySub != null ? 'OK' : 'MISSING') + ' 服务数=' + dev.servicesList.length.toString());
      CommLog.instance.rx([], note: '特征发现 write=' + (writeC != null ? 'OK' : 'MISSING') + ' services=' + dev.servicesList.length.toString());
      onState?.call('listening', '');
      // 通讯日志自动落盘（每 3 秒），保证完整记录不丢失
      _commFlushTimer?.cancel();
      _commFlushTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        CommLog.instance.exportToFile();
      });
      // 450ms 后发握手（vitaloop 策略），deviceType 0x29
      await Future.delayed(const Duration(milliseconds: 450));
      _writeChar = writeC;
      if (writeC != null) {
        await _sendHandshake(writeC, profile);
      } else {
        DebugLog.instance.log('错误: 未找到可写特征 FFB1，无法发送用户参数');
        CommLog.instance.rx([], note: 'ABORT: 无 FFB1');
        onState?.call('error', '未找到写入特征');
      }
      // 读 DIS 设备信息
      _readDeviceInfo(dev);
      // 断线监听
      _stateSub?.cancel();
      _stateSub = dev.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && !_stopped) {
          // 连接刚建立时的状态抖动会误报 disconnected；延迟复查真实连接状态，
          // 只有确实断开才重连，否则会导致同一个会话重复握手。
          _reconnectTimer?.cancel();
          _reconnectTimer = Timer(const Duration(seconds: 2), () async {
            if (_stopped || _connecting) return;
            bool stillUp = false;
            try {
              stillUp = await dev.isConnected;
            } catch (_) {}
            if (stillUp) {
              DebugLog.instance.log('状态抖动，实际仍连接，跳过重连');
              return;
            }
            onState?.call('disconnected', '自动重连中');
            DebugLog.instance.log('确认断线，重连');
            connect(hit, profile);
          });
        }
      });
    } catch (e) {
      onState?.call('error', e.toString());
      DebugLog.instance.log('连接失败: ' + e.toString());
    } finally {
      _connecting = false;
    }
  }

  /// 解析写秤用的参考体重：优先档案体重 → 最近一条记录 → 60kg
  Future<double> _resolveRefWeight(UserProfile p) async {
    if (p.weightKg != null && p.weightKg! > 20) return p.weightKg!;
    try {
      final recs = await getRecords();
      if (recs.isNotEmpty) {
        final mine = recs.where((r) => r.unit == p.name).toList();
        final pool = mine.isNotEmpty ? mine : recs;
        final last = pool.reduce((a, b) => a.time.compareTo(b.time) > 0 ? a : b);
        if (last.weightKg > 20) return last.weightKg;
      }
    } catch (_) {}
    return 60.0;
  }

  /// 解析目标体重：优先用户设定，否则用参考体重 × 0.75（与官方 80→50 比例接近）
  Future<double> _resolveTarget(double refWeight) async {
    try {
      final g = await getGoal();
      if (g != null && g.weightKg > 20) return g.weightKg;
    } catch (_) {}
    final t = refWeight * 0.75;
    return t.clamp(20.0, 200.0);
  }

  /// 统一写入封装：先记录 TX（保证即使写失败也能看到要发的字节），
  /// 再尝试无响应写，失败则改用有响应写重试一次。
  Future<void> _write(BluetoothCharacteristic c, List<int> bytes, String note) async {
    CommLog.instance.tx(bytes, note: note);
    onComm?.call(CommEvent(time: DateTime.now(), isTx: true, label: note));
    // FFB1 只声明 WRITE（带响应），不支持 WRITE_NO_RESPONSE —— 实测 8/8 条无响应写全部报错。
    // 因此直接走有响应写，避免每次多一次失败往返。
    try {
      await c.write(bytes, withoutResponse: false);
    } catch (e) {
      DebugLog.instance.log('写入失败(' + note + '): ' + e.toString());
      CommLog.instance.rx([], note: 'TX失败: ' + e.toString());
    }
  }

  Future<void> _sendHandshake(BluetoothCharacteristic c, UserProfile p) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final tz = (-(DateTime.now().timeZoneOffset.inMinutes) ~/ 15) & 0xFF;
    final height = p.heightCm.round() & 0xFF;
    final age = p.age & 0xFF;
    final sexVal = p.isMale ? 1 : 2;
    final refW = await _resolveRefWeight(p);
    final targetW = await _resolveTarget(refW);
    final profWeight = (refW * 100).round().clamp(0, 0xFFFF);
    final targetEnc = (targetW * 100).round().clamp(0, 0xFFFF);
    DebugLog.instance.log('用户参数: 身高' + height.toString() + 'cm 体重' + refW.toStringAsFixed(1) + 'kg 年龄' + age.toString() + ' 性别' + (p.isMale ? '男' : '女') + ' 目标' + targetW.toStringAsFixed(1) + 'kg');
    // deviceType 用 0x27 —— 与官方 HCI 抓包 / RN 实测版一致（0x29 不触发阻抗）
    const dt = 0x27;
    try {
      // 顺序严格对齐 RN 已验证版本：08 对时 → 01 用户 → 完整握手 → 06 → 04d6 → 04d8×2
      await _write(c, ScaleProtocol.cmdTime(now, tz, deviceType: dt), '08 对时');
      await Future.delayed(const Duration(milliseconds: 400));
      await _write(c, ScaleProtocol.frame([
        0x01, 0x00, 0x01, height,
        (profWeight >> 8) & 0xFF, profWeight & 0xFF,
        age, sexVal,
      ], deviceType: dt, tail: 0xD1), '01 用户');
      await Future.delayed(const Duration(milliseconds: 400));
      // 02 = 写两个用户槽位。多成员时分别写不同参数，秤按体重接近度认人。
      final roster = await getProfiles();
      final s1 = roster.isNotEmpty ? roster[0] : p;
      final s2 = roster.length > 1 ? roster[1] : s1;
      int slotHeight(UserProfile u) => u.heightCm.round() & 0xFF;
      int slotWeight(UserProfile u) {
        final w = (u.weightKg != null && u.weightKg! > 20) ? u.weightKg! : refW;
        return (w * 100).round().clamp(0, 0xFFFF);
      }
      final h1 = slotHeight(s1), w1 = slotWeight(s1);
      final h2 = slotHeight(s2), w2 = slotWeight(s2);
      await _write(c, ScaleProtocol.frame([
        0x02, 0x00, 0x01, h1,
        (w1 >> 8) & 0xFF, w1 & 0xFF,
        s1.age & 0xFF, s1.isMale ? 1 : 2,
        0x00,
        0x02, h2,
        (w2 >> 8) & 0xFF, w2 & 0xFF,
        s2.age & 0xFF, s2.isMale ? 1 : 2, 0x00,
      ], deviceType: dt, tail: 0xD1), '02 槽位(slot1=' + s1.name + ' ' + h1.toString() + 'cm/' + (w1/100).toStringAsFixed(2) + 'kg, slot2=' + s2.name + ' ' + h2.toString() + 'cm/' + (w2/100).toStringAsFixed(2) + 'kg)');
      await Future.delayed(const Duration(milliseconds: 400));
      await _write(c, ScaleProtocol.frame([
        (now >> 24) & 0xFF, (now >> 16) & 0xFF, (now >> 8) & 0xFF, now & 0xFF,
        tz, 0x00, 0x01, height,
        (profWeight >> 8) & 0xFF, profWeight & 0xFF,
        age, sexVal,
        (targetEnc >> 8) & 0xFF, targetEnc & 0xFF,
        0x03, 0x00,
      ], deviceType: dt, tail: 0xD0), 'D0 完整握手');
      await Future.delayed(const Duration(milliseconds: 400));
      await _write(c, ScaleProtocol.frame([0x06], deviceType: dt, tail: 0xDF), '06 查询');
      await Future.delayed(const Duration(milliseconds: 400));
      await _write(c, ScaleProtocol.cmdData(0xD6, deviceType: dt), '04d6 ADC');
      await Future.delayed(const Duration(milliseconds: 400));
      await _write(c, ScaleProtocol.cmdData(0xD8, deviceType: dt), '04d8 拉历史#1');
      await Future.delayed(const Duration(milliseconds: 400));
      await _write(c, ScaleProtocol.cmdData(0xD8, deviceType: dt), '04d8 拉历史#2');
      DebugLog.instance.log('命令序列完成(08/01/握手/06/04d6/04d8x2, deviceType=0x27)');
    } catch (e) { DebugLog.instance.log('握手失败: ' + e.toString()); }
  }

  bool _weightSyncedThisSession = false;

  Future<void> _maybeUpdateProfileWeight(double kg) async {
    // 不限制"每连接一次"：同一会话里多次测量也应刷新档案，
    // 重复锁定包由 0.05kg 阈值挡住。
    try {
      final activeName = await getActiveProfile();
      if (activeName == null) return;
      final list = await getProfiles();
      final idx = list.indexWhere((p) => p.name == activeName);
      if (idx < 0) return;
      final cur = list[idx];
      final old = cur.weightKg;
      // 实测值总是覆盖档案。
      // 曾经的 1kg / 0.05kg 阈值都出过问题：1kg 把 80.80→80.70 挡掉；
      // 0.05kg 又被浮点误差(80.80-80.85=0.0499...)挡掉。
      // 只有完全相同的值（<1g）才跳过，避免同一次测量的重复锁定包反复写盘。
      if (old != null && (old - kg).abs() < 0.001) return;
      final updated = UserProfile(
        name: cur.name, sex: cur.sex, age: cur.age,
        heightCm: cur.heightCm, weightKg: kg,
      );
      await upsertProfile(updated);
      DebugLog.instance.log('档案体重已回填: ' + kg.toStringAsFixed(2) + 'kg (原 ' + (old?.toStringAsFixed(2) ?? '空') + ')');
      onProfileWeightUpdated?.call(kg);
      CommLog.instance.rx([], note: '体重回填档案 ' + kg.toStringAsFixed(2) + 'kg');
    } catch (e) {
      DebugLog.instance.log('回填体重失败: ' + e.toString());
    }
  }

  /// 把收到的包翻译成人类可读事件（节流由 UI 侧处理）。
  void _pushRxEvent(Uint8List d, MeasurementTick tick) {
    final type = d.length > 2 ? d[2] : 0;
    String label;
    switch (type) {
      case 0x00: label = '实时体重'; break;
      case 0x80: label = '稳定'; break;
      case 0x02: label = '锁定完成'; break;
      case 0x06: label = '配置块'; break;
      default: label = '包0x' + type.toRadixString(16); break;
    }
    final parts = <String>[];
    if (tick.weightKg > 0) parts.add(tick.weightKg.toStringAsFixed(2) + " kg");
    if ((tick.impedance1 ?? 0) > 0) {
      parts.add(tick.impedance1!.toStringAsFixed(0) + '/' + (tick.impedance2 ?? 0).toStringAsFixed(0) + ' Ω');
    }
    if (tick.battery != null) parts.add('电量 ' + tick.battery.toString() + '%');
    if (tick.locked) parts.add('阶段:完成');
    onComm?.call(CommEvent(
      time: DateTime.now(),
      isTx: false,
      label: label,
      detail: parts.join(' · '),
    ));
  }

  void _handleNotify(Uint8List d) {
    // 每个收到的包都记入通讯日志（原始字节）
    CommLog.instance.rx(d, note: 'type=0x' + (d.length > 2 ? d[2].toRadixString(16).padLeft(2, '0') : '??'));
    // 历史包
    final hist = ScaleProtocol.parseHistory(d);
    if (hist != null && hist.weightKg >= 10) {
      DebugLog.instance.log('历史: ' + hist.weightKg.toStringAsFixed(2) + 'kg');
      onComm?.call(CommEvent(time: DateTime.now(), isTx: false, label: '历史记录', detail: hist.weightKg.toStringAsFixed(2) + ' kg' + (hist.adcs.isNotEmpty && hist.adcs[0] > 0 ? ' · ' + hist.adcs[0].toStringAsFixed(0) + '/' + hist.adcs[1].toStringAsFixed(0) + ' Ω' : '')));
      onHistory?.call(hist);
      return;
    }
    // 45秒超时
    bool timedOut = false;
    if (_measureStart != null && DateTime.now().difference(_measureStart!).inSeconds > 45) {
      timedOut = true;
    }
    final tick = ScaleProtocol.parseNotify(d, timedOut: timedOut);
    if (tick == null) return;
    _pushRxEvent(d, tick);
    if (tick.weightKg > 5 && _measureStart == null) _measureStart = DateTime.now();
    if (tick.locked) _measureStart = null;
    // 电量众数：连续 3 次同值才采信，写回设备信息缓存
    if (tick.battery != null) {
      if (tick.battery == _batteryVote) {
        _batteryVoteCount++;
        if (_batteryVoteCount == 3 && _devInfo != null && _devInfo!.battery != _batteryVote) {
          _devInfo!.battery = _batteryVote;
          onDeviceInfo?.call(_devInfo!);
          notifyListeners();
        }
      } else {
        _batteryVote = tick.battery!;
        _batteryVoteCount = 1;
      }
    }
    onTick?.call(tick);

  }

  Future<void> _readDeviceInfo(BluetoothDevice dev) async {
    final info = ScaleInfo();
    final disSvc = Guid('0000180a-0000-1000-8000-00805f9b34fb');
    for (final s in dev.servicesList) {
      if (s.uuid == disSvc) {
        for (final c in s.characteristics) {
          final u = c.uuid.toString();
          try {
            final v = await c.read();
            final str = utf8.decode(v, allowMalformed: true).trim();
            if (u.contains('2a29')) info.manufacturer = str;
            if (u.contains('2a24')) info.model = str;
            if (u.contains('2a26')) info.firmware = str;
            if (u.contains('2a28')) info.software = str;
          } catch (_) {}
        }
      }
    }
    info.updatedAt = DateTime.now().toIso8601String();
    _devInfo = info;
    onDeviceInfo?.call(info);
  }

  /// 主动连接已绑定设备：若不在当前扫描缓存中，先尝试直连，失败则启动扫描等待发现再连。
  Future<void> connectToBound(BoundDevice device, UserProfile profile) async {
    if (_connected != null && _connected!.remoteId.toString().toUpperCase() != device.id.toUpperCase()) {
      await disconnect();
    }
    final hit = _hits.values.where((h) =>
      (h.realMac != '-' ? h.realMac : h.device.remoteId.toString()).toUpperCase() == device.id.toUpperCase()
    ).firstOrNull;
    if (hit != null) {
      await connect(hit, profile);
      return;
    }
    onState?.call('connecting', '正在寻找 ' + device.name);
    // 先用 MAC 直接构造设备尝试连接；若 5s 内连不上（如地址未在系统缓存），启动扫描寻找
    final dev = BluetoothDevice.fromId(device.id);
    await connect(ScanHit(device: dev, name: device.name, rssi: -60, realMac: device.id), profile);
  }

  /// 在已连接状态下切换身份时，立即把新用户的参数发给秤。
  Future<void> updateUserProfile(UserProfile p) async {
    final c = _writeChar;
    if (c == null || _connected == null) return;
    await _sendHandshake(c, p);
  }
  Future<void> disconnect() async {
    _stopped = true;
    _commFlushTimer?.cancel();
    _commFlushTimer = null;
    await CommLog.instance.exportToFile(force: true);
    _reconnectTimer?.cancel();
    _notifySub?.cancel();
    _stateSub?.cancel();
    if (_connected != null) {
      try { await _connected!.disconnect(); } catch (_) {}
    }
    _connected = null;
    _writeChar = null;
    _measureStart = null;
    onState?.call('idle', '');
    DebugLog.instance.log('已断开');
  }

  void destroy() {
    _stopped = true;
    stopScan();
    disconnect();
  }
}