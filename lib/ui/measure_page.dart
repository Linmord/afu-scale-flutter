import 'package:flutter/material.dart';
import 'dart:async';
import '../core/models.dart';
import '../core/bodycomp.dart';
import '../core/protocol.dart';
import '../core/units.dart';
import '../ble/scale_ble.dart';
import '../ble/comm_log.dart';
import '../data/store.dart';
import '../data/debug_log.dart';
import 'package:afu_scale/i18n/l10n.dart';
import 'theme.dart' as th;
import 'widgets/scale_ring.dart';
import 'widgets/app_sheet.dart';
import 'profile_editor.dart';
import 'device_scanner_page.dart';
import 'comm_log_page.dart';

/// 全屏测量页：从底部滑入，主动寻找并连接已绑定设备。
class MeasurePage extends StatefulWidget {
  final UserProfile active;
  final List<UserProfile> profiles;
  final VoidCallback onClose;
  final Future<void> Function() onProfilesChanged;
  const MeasurePage({
    super.key,
    required this.active,
    required this.profiles,
    required this.onClose,
    required this.onProfilesChanged,
  });
  @override State<MeasurePage> createState() => MeasurePageState();
}

class MeasurePageState extends State<MeasurePage> with TickerProviderStateMixin {
  final _ble = ScaleBle.instance;
  late UserProfile _active;
  late List<UserProfile> _profiles;
  MeasurementTick? _tick;
  String _state = 'idle';
  String _detail = '';
  String? _toast;
  ScaleInfo? _devInfo;
  DisplayUnit _unit = DisplayUnit.kg;
  final _weightAnim = ValueNotifier<double>(0);
  Timer? _toastTimer;
  bool _historySyncing = false;
  int _historyCount = 0;
  Timer? _historyTimer;
  Timer? _connectTimer;
  int _connectWatchToken = 0;
  bool _debugMode = false; // 彩蛋：默认隐藏通讯入口
  String _bfAlgo = 'officialAnt';
  late final AnimationController _cardsIn;
  late final AnimationController _deviceCardIn;
  BoundDevice? _device;
  List<BoundDevice> _devices = [];
  MeasurementTick? _pendingNoImpulse;
  bool _hasUnsaved = false; // 有测量数据但未落库
  double? _lastSavedKg;
  DateTime? _lastSavedAt;

  @override
  void initState() {
    super.initState();
    _active = widget.active;
    _profiles = List.of(widget.profiles);
    _cardsIn = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _deviceCardIn = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    _loadUnit();
    _loadDebugMode();
    _setupBle();
    _initDevices();
  }

  Future<void> _loadDebugMode() async {
    final v = await getDebugMode();
    final a = await getBfAlgo();
    if (mounted) setState(() { _debugMode = v; _bfAlgo = a; });
  }

  Future<void> _loadUnit() async {
    final u = await getDisplayUnit();
    if (mounted) setState(() => _unit = u);
  }

  Future<void> _initDevices() async {
    _devices = await getDevices();
    if (_devices.isEmpty) {
      if (mounted) {
        setState(() => _detail = S.of(context).noDeviceTitle);
        _deviceCardIn.forward(from: 0);
      }
      return;
    }
    // 默认设备：优先上次切换记住的 MAC，否则第一个
    final prefId = await getPreferredDeviceId();
    final pref = prefId == null
        ? null
        : _devices.where((d) => d.id.toUpperCase() == prefId.toUpperCase()).firstOrNull;
    if (mounted) {
      setState(() => _device = pref ?? _devices.first);
      _deviceCardIn.forward(from: 0);
    }
    // 不自动连接：由用户点击圆环开始（见 _onRingTap）
  }

  void _setupBle() {
    _ble.onTick = (t) {
      if (!mounted) return;
      final wasNotLocked = _tick?.locked != true;

      setState(() => _tick = t);
      _animateWeight(t.weightKg);
      if (t.locked && wasNotLocked) _cardsIn.forward(from: 0);
      if (t.locked) _onLocked(t);
    };
    _ble.onState = (state, detail) {
      if (!mounted) return;
      if (state == 'listening' || state == 'error') {
        _connectTimer?.cancel();
        _connectWatchToken++;
      }
      setState(() { _state = state; _detail = detail; });
    };
    _ble.onDeviceInfo = (info) { if (mounted) setState(() => _devInfo = info); };
    _ble.onHistory = (h) async {
      await addPending(PendingHistory(
        key: h.time.toString() + '_' + h.weightKg.round().toString(),
        timeStr: DateTime.fromMillisecondsSinceEpoch(h.time * 1000).toString().substring(0, 19),
        weightKg: h.weightKg,
        impedance1: h.adcs.isNotEmpty && h.adcs[0] > 0 ? h.adcs[0] : null,
        impedance2: h.adcs.length > 1 && h.adcs[1] > 0 ? h.adcs[1] : null,
        lowWeight: h.weightKg < 30,
      ));
      _historyCount++;
      _historySyncing = true;
      if (mounted) setState(() {});
      _historyTimer?.cancel();
      _historyTimer = Timer(const Duration(milliseconds: 2600), () {
        if (mounted) setState(() => _historySyncing = false);
      });
    };
  }

  Future<void> _connectTo(BoundDevice device) async {
    await setPreferredDeviceId(device.id); // 记住，下次默认连它
    setState(() {
      _device = device;
      _state = 'connecting';
      _detail = '';
      _tick = null;
      _pendingNoImpulse = null;
    });
    _deviceCardIn.forward(from: 0);
    await _ble.connectToBound(device, _active);
  }

  void _animateWeight(double target) {
    final start = _weightAnim.value;
    final t0 = DateTime.now().millisecondsSinceEpoch;
    Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) { timer.cancel(); return; }
      final p = (DateTime.now().millisecondsSinceEpoch - t0) / 220.0;
      if (p >= 1) { _weightAnim.value = target; timer.cancel(); return; }
      _weightAnim.value = start + (target - start) * Curves.easeOutCubic.transform(p);
    });
  }

  /// 锁定包到达：有阻抗直接保存；没有阻抗时不直接保存，挂起等用户抬脚重测或确认。
  /// 不完整测量：按用户策略处理。
  /// ask   → 第一次弹询问（可记住选择），之后按记住的做
  /// save  → 直接只存体重
  /// skip  → 直接不存
  Future<void> _handleIncomplete(MeasurementTick t) async {
    final policy = await getIncompletePolicy();
    if (policy == 'save') {
      await _finalizeSave(t, hasImp: false);
      return;
    }
    if (policy == 'skip') {
      if (mounted) {
        setState(() { _pendingNoImpulse = t; _hasUnsaved = true; });
      }
      return;
    }
    // ask：弹一次带「记住选择」的询问
    if (!mounted) return;
    setState(() { _pendingNoImpulse = t; _hasUnsaved = true; });
  }

  void _onLocked(MeasurementTick t) {
    // 已经有待确认的无阻抗读数时，忽略循环广播的重复锁定包
    if (_pendingNoImpulse != null) return;
    final hasImp = (t.impedance1 ?? 0) > 0 || (t.impedance2 ?? 0) > 0;
    // 权重过小（轻踩/未站好）或无阻抗 → 都算「不完整测量」
    final incomplete = t.weightKg < 20 || !hasImp;
    if (incomplete) {
      _handleIncomplete(t);
      return;
    }
    final now = DateTime.now();
    if (_lastSavedKg != null &&
        (t.weightKg - _lastSavedKg!).abs() < 0.02 &&
        _lastSavedAt != null &&
        now.difference(_lastSavedAt!).inSeconds < 10) {
      return;
    }
    _lastSavedKg = t.weightKg;
    _lastSavedAt = now;
    _hasUnsaved = false;
    _finalizeSave(t, hasImp: true);
  }

  /// 供外部（系统返回键）调用：有未保存数据先确认，返回 true 表示可以关闭。
  Future<bool> confirmClose() async {
    if (!_hasUnsaved && _pendingNoImpulse == null) {
      _ble.disconnect();
      return true;
    }
    if (!mounted) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: th.AppColors.surface,
        title: Text(S.of(context).exitUnsavedTitle, style: TextStyle(color: th.AppColors.text)),
        content: Text(
          S.of(context).exitUnsavedDesc,
          style: TextStyle(color: th.AppColors.textSub, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(S.of(context).keepMeasuring)),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(S.of(context).exitApp, style: TextStyle(color: th.AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (leave == true) _ble.disconnect();
    return leave == true;
  }

  Future<void> _finalizeSave(MeasurementTick t, {required bool hasImp}) async {
    final p = _active;
    BodyComposition? comp;
    if (hasImp) {
      comp = BodyCompositionCalc.estimate(
        weightKg: t.weightKg,
        heightCm: p.heightCm,
        age: p.age,
        sex: p.sex,
        impedances: [t.impedance1 ?? 0, t.impedance2 ?? 0],
        algo: _bfAlgo,
      );
    }
    await appendRecord(MeasurementRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      time: DateTime.now().toString().substring(0, 19),
      unit: p.name,
      weightKg: t.weightKg,
      impedance1: hasImp ? t.impedance1 : null,
      impedance2: hasImp ? t.impedance2 : null,
      adcs: hasImp && t.adcs.isNotEmpty ? t.adcs.map((x) => x.toDouble()).toList() : null,
      electrodeOn: hasImp,
      bodyComposition: comp,
      profile: p,
    ));
    if (p.weightKg == null || (p.weightKg! - t.weightKg).abs() >= 0.001) {
      final updated = UserProfile(
        name: p.name, sex: p.sex, age: p.age,
        heightCm: p.heightCm, weightKg: t.weightKg,
      );
      await upsertProfile(updated);
      if (mounted) setState(() => _active = updated);
      await widget.onProfilesChanged();
    }
    _hasUnsaved = false;
    if (mounted) {
      setState(() => _pendingNoImpulse = null);
      final s = S.of(context);
      _showToast(s.savedMsg + ' ' + _unit.fmt(t.weightKg) +
          (comp != null ? ' · ' + s.bcFat + ' ' + comp.bodyFatPercent.toStringAsFixed(1) + '%' : ''));
    }
  }

  void _showToast(String msg) {
    if (!mounted) return;
    setState(() => _toast = msg);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _historyTimer?.cancel();
    _connectTimer?.cancel();
    _cardsIn.dispose();
    _deviceCardIn.dispose();
    _ble.onTick = null;
    _ble.onHistory = null;
    _ble.onState = null;
    _ble.onDeviceInfo = null;
    _ble.disconnect();
    super.dispose();
  }

  RingPhase get _ringPhase {
    if (_tick == null) return RingPhase.idle;
    if (_tick!.locked) return RingPhase.done;
    switch (_tick!.phase) {
      case 'impedance': return RingPhase.impedance;
      case 'done': return RingPhase.done;
      default: return RingPhase.weighing;
    }
  }

  bool get _hasImp => ((_tick?.impedance1 ?? 0) > 0 || (_tick?.impedance2 ?? 0) > 0);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final tick = _tick;
    final comp = (tick != null && tick.locked && _hasImp)
        ? BodyCompositionCalc.estimate(
            weightKg: tick.weightKg,
            heightCm: _active.heightCm,
            age: _active.age,
            sex: _active.sex,
            impedances: [tick.impedance1 ?? 0, tick.impedance2 ?? 0],
            algo: _bfAlgo,
          )
        : null;
    return Scaffold(
      backgroundColor: th.AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            _topBar(s),
            const SizedBox(height: 12),
            _identitySelector(s),
            const SizedBox(height: 10),
            _deviceCard(s),
            const SizedBox(height: 12),
            if (_toast != null) _toastBar(),
            if (_historySyncing) _historyBar(s),
            if (_pendingNoImpulse != null) _noImpulsePrompt(s),
            // 圆环区域点击 = 开始/再来一次测量（核心交互）
            Semantics(
              button: true,
              label: '点击开始测量',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onRingTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _weightAnim,
                    builder: (ctx, v, _) => ScaleRing(
                  weightKg: tick?.weightKg ?? 0,
                  unitNum: tick != null ? _unit.num(v) : '0.00',
                        idleHint: tick == null ? s.tapToStart : '',
                  unitSuffix: _unit.suffix,
                  phase: _ringPhase,
                  electrodeOn: _hasImp,
                      statusText: _statusText(s),
                      timedOut: tick?.timedOut == true,
                    ),
                  ),
                ),
              ),
            ),
            if (_state == 'listening' && tick != null && !tick.locked)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _hasImp ? th.AppColors.primarySoft : th.AppColors.warnSoft,
                      borderRadius: BorderRadius.circular(th.AppRadius.pill),
                    ),
                    child: Text(
                      _hasImp ? s.electrodeReadyHint : s.placeFeetHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: _hasImp ? th.AppColors.primaryDeep : th.AppColors.warn,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            _metricsGrid(comp, s),
          ],
        ),
      ),
    );
  }

  /// 圆环点击：
  /// - 未连接时：开始连接已选设备并进入测量流程
  /// - 测量完成（done）时：清空本轮数据再来一次
  /// - 连接中/测量中：忽略（防止重复触发）
  /// 圆环点击：
  /// - 未开始：自动连接选中设备开始测量；5 秒连不上才弹「是否搜索设备」
  /// - 测量完成：清空本轮数据，已连接则直接重测，未连接则重连
  /// - 连接中/测量中：忽略
  void _onRingTap() async {
    if (_state == 'connecting') return;
    if (_state == 'listening' && _tick != null && !_tick!.locked) return;
    if (_tick?.locked == true || _pendingNoImpulse != null) {
      setState(() {
        _tick = null;
        _pendingNoImpulse = null;
        _weightAnim.value = 0;
        _lastSavedKg = null;
        _lastSavedAt = null;
      });
      _cardsIn.reset();
      if (_ble.connected != null) {
        setState(() => _state = 'listening');
        return;
      }
    }
    if (_device == null) {
      // 没有任何绑定设备 → 直接问是否搜索
      await _promptScan();
      return;
    }
    // 自动连接默认设备（不掐断底层连接）。
    // 5 秒后若仍未进入 listening（onState 会改状态），才弹「是否搜索」。
    setState(() { _state = 'connecting'; _detail = ''; });
    _connectWatchToken++;
    final myToken = _connectWatchToken;
    _connectTimer?.cancel();
    _connectTimer = Timer(const Duration(seconds: 5), () async {
      if (myToken != _connectWatchToken || !mounted) return;
      // 还在连接中且没有任何体重数据 → 认为没连上
      if (_state == 'connecting' && _tick == null) {
        await _promptScan();
      }
    });
    // 直接发起连接；成功由 onState(listening) 更新状态并取消观察
    await _connectTo(_device!);
  }

  Future<bool> _connectWithTimeout(BoundDevice dev, {int seconds = 5}) async {
    try {
      final done = _connectTo(dev).timeout(Duration(seconds: seconds));
      await done;
      if (mounted) setState(() { _state = 'listening'; });
      return true;
    } catch (e) {
      DebugLog.instance.log('连接超时或失败: ' + e.toString());
      if (mounted) setState(() { _state = 'error'; _detail = '连接超时'; });
      return false;
    }
  }

  Future<void> _promptScan() async {
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: th.AppColors.surface,
        title: Text(S.of(context).scanNotFoundTitle, style: TextStyle(color: th.AppColors.text)),
        content: Text(S.of(context).scanNotFoundDesc, style: TextStyle(color: th.AppColors.textSub, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(S.of(context).cancel)),
          TextButton(onPressed: () => Navigator.pop(dctx, true), child: Text(S.of(context).searchDevice, style: TextStyle(color: th.AppColors.primary, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (go == true) await _openScanner();
  }

  String _statusText(S s) {
    switch (_state) {
      case 'connecting': return s.connecting;
      case 'listening':
        if (_tick == null) return s.standOnScale;
        if (_tick!.locked) return s.doneRetry;
        if (_tick!.phase == 'impedance') return s.phaseImpedance;
        return s.phaseWeighing;
      case 'error': return s.stateError;
      default: return '点击开始测量';
    }
  }

  Widget _topBar(S s) => Row(
    children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          if (_hasUnsaved || _pendingNoImpulse != null) {
            final leave = await showDialog<bool>(
              context: context,
              builder: (dctx) => AlertDialog(
                backgroundColor: th.AppColors.surface,
                title: Text('本次测量未保存', style: TextStyle(color: th.AppColors.text)),
                content: Text(
                  '这次只读到体重、没测到阻抗，数据没有保存。确定要退出吗？',
                  style: TextStyle(color: th.AppColors.textSub, fontSize: 13),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text('继续测量')),
                  TextButton(
                    onPressed: () => Navigator.pop(dctx, true),
                    child: Text('退出', style: TextStyle(color: th.AppColors.danger, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            );
            if (leave != true) return;
          }
          _ble.disconnect();
          widget.onClose();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(Icons.keyboard_arrow_down_rounded, size: 24, color: th.AppColors.textSub),
              Text(s.close, style: TextStyle(fontSize: 14, color: th.AppColors.textSub, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
      const Spacer(),
      Text(s.measuringTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: th.AppColors.text)),
      const Spacer(),
      // 彩蛋：通讯日志入口默认隐藏，仅在调试模式下显示
      if (_debugMode)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const CommLogPage()));
            if (mounted) setState(() {});
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: th.AppColors.surface,
              borderRadius: BorderRadius.circular(th.AppRadius.pill),
              border: Border.all(color: th.AppColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal_rounded, size: 13, color: th.AppColors.textSub),
                const SizedBox(width: 4),
                Text(CommLog.instance.length.toString(), style: TextStyle(fontSize: 11, color: th.AppColors.textSub, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        )
      else
        const SizedBox(width: 24),
    ],
  );

  /// 测量页专属身份胶囊（渐变边框+横向快速切换/弹窗选择）
  Widget _identitySelector(S s) {
    final accent = _active.isMale ? th.AppColors.accent : th.AppColors.fat;
    final soft = _active.isMale ? th.AppColors.accentSoft : th.AppColors.fatSoft;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showIdentityPicker(s),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [th.AppColors.primary.withOpacity(0.55), accent.withOpacity(0.55)]),
          borderRadius: BorderRadius.circular(th.AppRadius.lg),
          boxShadow: th.AppShadows.soft,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: th.AppColors.surface,
            borderRadius: BorderRadius.circular(th.AppRadius.lg - 2),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: soft,
                child: Text(
                  _active.name.substring(0, 1),
                  style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.currentMeasurer, style: TextStyle(fontSize: 10, color: th.AppColors.textHint, fontWeight: FontWeight.w600)),
                    Text(
                      _active.name + ' · ' + (_active.isMale ? s.sexMale : s.sexFemale) + ' · ' + _active.heightCm.toStringAsFixed(0) + 'cm',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: th.AppColors.text),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: th.AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(th.AppRadius.pill),
                ),
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz_rounded, size: 14, color: th.AppColors.primaryDeep),
                    const SizedBox(width: 3),
                    Text(s.switchLabel, style: TextStyle(fontSize: 11, color: th.AppColors.primaryDeep, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showIdentityPicker(S s) async {
    _profiles = await getProfiles();
    if (!mounted) return;
    await showAppSheet(
      context,
      title: s.currentMeasurer,
      children: [
        ..._profiles.map((p) {
          final isCur = p.name == _active.name;
          final accent = p.isMale ? th.AppColors.accent : th.AppColors.fat;
          final soft = p.isMale ? th.AppColors.accentSoft : th.AppColors.fatSoft;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isCur ? th.AppColors.primarySoft.withOpacity(th.AppColors.isDark ? 0.25 : 0.7) : th.AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(th.AppRadius.md),
              border: Border.all(color: isCur ? th.AppColors.primary : th.AppColors.border),
            ),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: soft, child: Text(p.name.substring(0, 1), style: TextStyle(color: accent, fontWeight: FontWeight.w800))),
              title: Text(p.name, style: TextStyle(color: th.AppColors.text, fontWeight: isCur ? FontWeight.w800 : FontWeight.w600)),
              subtitle: Text(
                (p.isMale ? s.sexMale : s.sexFemale) + ' · ' + p.age.toString() + ' · ' + p.heightCm.toStringAsFixed(1) + 'cm' + (p.weightKg != null ? ' · ' + _unit.fmt(p.weightKg!) : ''),
                style: TextStyle(fontSize: 11, color: th.AppColors.textHint),
              ),
              trailing: isCur ? Icon(Icons.check_circle_rounded, color: th.AppColors.primary) : null,
              onTap: () async {
                Navigator.pop(context);
                await setActive(p.name);
                if (mounted) setState(() => _active = p);
                await widget.onProfilesChanged();
                if (_ble.connected != null) {
                  await _ble.updateUserProfile(p);
                }
              },
            ),
          );
        }),
        TextButton.icon(
          onPressed: () async {
            Navigator.pop(context);
            final ok = await showProfileEditor(context);
            if (ok) {
              final list = await getProfiles();
              final activeName = await getActiveProfile();
              final picked = list.where((x) => x.name == activeName).firstOrNull;
              if (mounted) {
                setState(() {
                  _profiles = list;
                  if (picked != null) _active = picked;
                });
              }
              await widget.onProfilesChanged();
            }
          },
          icon: Icon(Icons.person_add_alt_1_rounded, size: 17, color: th.AppColors.primary),
          label: Text(s.addProfile, style: TextStyle(color: th.AppColors.primary, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  /// 设备卡：带浮出动画 + 状态点 + 电量 + 切换按钮
  Widget _deviceCard(S s) => AnimatedBuilder(
    animation: _deviceCardIn,
    builder: (ctx, _) {
      final t = Curves.easeOutBack.transform(_deviceCardIn.value.clamp(0.0, 1.0));
      final isUp = _state == 'listening';
      final isErr = _state == 'error';
      final dotColor = isUp ? th.AppColors.primary : (isErr ? th.AppColors.danger : th.AppColors.warn);
      return Transform.translate(
        offset: Offset(0, 18 * (1 - t)),
        child: Transform.scale(
          scale: 0.96 + 0.04 * t,
          child: Opacity(
            opacity: _deviceCardIn.value.clamp(0.0, 1.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: th.AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(th.AppRadius.md),
                border: Border.all(color: isUp ? th.AppColors.primary.withOpacity(0.45) : th.AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 9, height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                      boxShadow: isUp ? [BoxShadow(color: dotColor.withOpacity(0.45), blurRadius: 8)] : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _device?.name ?? s.noDeviceTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: th.AppColors.text),
                        ),
                        Text(
                          _device == null
                              ? s.noDeviceDesc
                              : ((_devInfo?.battery != null ? s.batteryLabel + ' ' + _devInfo!.battery.toString() + '% · ' : '') + (_detail.isNotEmpty ? _detail : _device!.id)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: th.AppColors.textHint),
                        ),
                      ],
                    ),
                  ),
                  if (isErr && _device != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _connectTo(_device!),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                          decoration: BoxDecoration(
                            color: th.AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(th.AppRadius.pill),
                          ),
                          child: Text(s.refresh, style: TextStyle(fontSize: 11, color: th.AppColors.primaryDeep, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _devices.isEmpty ? _openScanner() : _showDeviceSheet(s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: th.AppColors.surface,
                        borderRadius: BorderRadius.circular(th.AppRadius.pill),
                        border: Border.all(color: th.AppColors.borderStrong),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.bluetooth_rounded, size: 13, color: th.AppColors.primary),
                          const SizedBox(width: 4),
                          Text(_devices.isEmpty ? s.scanAndAdd : s.switchLabel, style: TextStyle(fontSize: 11, color: th.AppColors.primaryDeep, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Future<void> _showDeviceSheet(S s) async {
    _devices = await getDevices();
    if (!mounted) return;
    await showAppSheet(
      context,
      title: s.selectDevice,
      children: [
        ..._devices.map((d) {
          final isCur = d.id.toUpperCase() == (_device?.id.toUpperCase() ?? '');
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isCur ? th.AppColors.primarySoft.withOpacity(th.AppColors.isDark ? 0.25 : 0.65) : th.AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(th.AppRadius.md),
              border: Border.all(color: isCur ? th.AppColors.primary : th.AppColors.border),
            ),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: th.AppColors.primarySoft, child: Icon(Icons.monitor_weight_outlined, color: th.AppColors.primaryDeep, size: 18)),
              title: Text(d.name, style: TextStyle(color: th.AppColors.text, fontWeight: isCur ? FontWeight.w800 : FontWeight.w600)),
              subtitle: Text(d.model + ' · ' + d.id, style: TextStyle(fontSize: 10, color: th.AppColors.textHint, fontFamily: 'monospace')),
              trailing: isCur ? Icon(Icons.check_circle_rounded, color: th.AppColors.primary) : null,
              onTap: () { Navigator.pop(context); _connectTo(d); },
            ),
          );
        }),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () { Navigator.pop(context); _openScanner(); },
          icon: Icon(Icons.bluetooth_searching_rounded, size: 17, color: th.AppColors.accent),
          label: Text(s.rescanDevice, style: TextStyle(color: th.AppColors.accent, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Future<void> _openScanner() async {
    await _ble.disconnect();
    if (!mounted) return;
    final picked = await openDeviceScanner(context);
    _devices = await getDevices();
    if (picked != null && mounted) {
      await _connectTo(picked);
    } else if (_device != null && mounted) {
      await _connectTo(_device!);
    }
  }

  Widget _toastBar() => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: th.AppColors.primarySoft, borderRadius: BorderRadius.circular(th.AppRadius.sm)),
    child: Row(
      children: [
        Icon(Icons.check_circle, size: 15, color: th.AppColors.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(_toast!, style: TextStyle(color: th.AppColors.primaryDeep, fontSize: 12, fontWeight: FontWeight.w600))),
      ],
    ),
  );

  Widget _historyBar(S s) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: th.AppColors.accentSoft, borderRadius: BorderRadius.circular(th.AppRadius.sm)),
    child: Row(
      children: [
        SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: th.AppColors.accent)),
        const SizedBox(width: 10),
        Expanded(child: Text(s.historySynced(_historyCount), style: TextStyle(color: th.AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600))),
      ],
    ),
  );

  /// 无阻抗提示：不直接保存，等用户抬脚重测或确认仅保存体重
  Widget _noImpulsePrompt(S s) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: th.AppColors.soft(th.AppColors.warnSoft, th.AppColors.warnSoftD),
      borderRadius: BorderRadius.circular(th.AppRadius.md),
      border: Border.all(color: th.AppColors.warn.withOpacity(0.45)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: th.AppColors.warn),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.noImpedanceTitle + ( _pendingNoImpulse!.weightKg >= 20 ? ' · ' + _unit.fmt(_pendingNoImpulse!.weightKg) : ''),
                style: TextStyle(color: th.AppColors.warn, fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          s.noImpedanceDesc,
          style: TextStyle(color: th.AppColors.textSub, fontSize: 11, height: 1.5),
        ),
        const SizedBox(height: 6),
        Text(
          s.longPressDefault,
          style: TextStyle(color: th.AppColors.textHint, fontSize: 10),
        ),
        const SizedBox(height: 8),
        // 三个动作竖排：任何语言文案变长都不会挤在一起，触控区也更大。
        OutlinedButton(
          onPressed: () {
            setState(() {
              _pendingNoImpulse = null;
              _tick = null;
              _weightAnim.value = 0;
              _hasUnsaved = false;
            });
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: th.AppColors.soft(th.AppColors.primaryDeep, th.AppColors.primary),
            minimumSize: const Size.fromHeight(42),
          ),
          child: Text(
            s.remeasure,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: th.AppColors.soft(th.AppColors.primaryDeep, th.AppColors.primary),
            ),
          ),
        ),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: () async {
            await _finalizeSave(_pendingNoImpulse!, hasImp: false);
          },
          onLongPress: () async {
            await setIncompletePolicy('save');
            await _finalizeSave(_pendingNoImpulse!, hasImp: false);
            if (mounted) _showToast(s.setDefaultSave);
          },
          style: FilledButton.styleFrom(
            backgroundColor: th.AppColors.warn,
            minimumSize: const Size.fromHeight(42),
          ),
          child: Text(
            s.saveWeightOnly,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: () {
            setState(() { _pendingNoImpulse = null; _hasUnsaved = false; });
          },
          onLongPress: () async {
            await setIncompletePolicy('skip');
            setState(() { _pendingNoImpulse = null; _hasUnsaved = false; });
            if (mounted) _showToast(s.setDefaultSkip);
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: th.AppColors.textSub,
            minimumSize: const Size.fromHeight(40),
          ),
          child: Text(
            s.policySkip,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12),
          ),
        ),      ],
    ),
  );

  Widget _metricsGrid(BodyComposition? comp, S s) {
    final items = [
      _M(s.bcFat, comp?.bodyFatPercent, '%', th.AppColors.fat, th.AppColors.soft(th.AppColors.fatSoft, th.AppColors.fatSoftD), Icons.water_drop),
      _M(s.bcMuscle, comp?.muscleMassKg, 'kg', th.AppColors.muscle, th.AppColors.soft(th.AppColors.muscleSoft, th.AppColors.muscleSoftD), Icons.fitness_center),
      _M(s.bcWater, comp?.waterPercent, '%', th.AppColors.water, th.AppColors.soft(th.AppColors.waterSoft, th.AppColors.waterSoftD), Icons.opacity),
      _M(s.bcSkeletal, comp?.skeletalMuscleMassKg, 'kg', th.AppColors.skeletal, th.AppColors.soft(th.AppColors.skeletalSoft, th.AppColors.skeletalSoftD), Icons.accessibility_new),
    ];
    return AnimatedBuilder(
      animation: _cardsIn,
      builder: (ctx, _) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.85,
        children: List.generate(items.length, (i) {
          final start = i * 0.12;
          final t = Curves.easeOutBack.transform(
            ((_cardsIn.value - start) / (1 - start)).clamp(0.0, 1.0),
          );
          return Transform.scale(
            scale: comp == null ? 1.0 : (0.9 + 0.1 * t),
            child: Opacity(opacity: comp == null ? 1.0 : t.clamp(0.0, 1.0), child: _metricCard(items[i])),
          );
        }),
      ),
    );
  }

  Widget _metricCard(_M m) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: th.AppColors.surface,
      borderRadius: BorderRadius.circular(th.AppRadius.md),
      border: Border.all(color: th.AppColors.border),
      boxShadow: th.AppShadows.soft,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(width: 26, height: 26, decoration: BoxDecoration(color: m.soft, borderRadius: BorderRadius.circular(8)), child: Icon(m.icon, size: 15, color: m.color)),
            const SizedBox(width: 8),
            Text(m.label, style: TextStyle(fontSize: 11, color: th.AppColors.textHint, fontWeight: FontWeight.w600)),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              m.value == null ? '—' : m.value!.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: m.value == null ? th.AppColors.textHint : m.color,
                letterSpacing: -0.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 3),
            Text(m.unit, style: TextStyle(fontSize: 11, color: th.AppColors.textHint, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    ),
  );
}

class _M {
  final String label;
  final double? value;
  final String unit;
  final Color color;
  final Color soft;
  final IconData icon;
  _M(this.label, this.value, this.unit, this.color, this.soft, this.icon);
}