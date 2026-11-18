import 'package:flutter/material.dart';
import '../core/models.dart';
import '../ble/scale_ble.dart';
import '../data/store.dart';
import 'package:afu_scale/i18n/l10n.dart';
import 'theme.dart' as th;
import 'widgets/form_page.dart';

/// 独立的全屏扫描/绑定页：返回选中的或新绑定的 [BoundDevice]。
Future<BoundDevice?> openDeviceScanner(BuildContext context) {
  return Navigator.push<BoundDevice>(
    context,
    MaterialPageRoute<BoundDevice>(
      builder: (_) => const DeviceScannerPage(),
    ),
  );
}

class DeviceScannerPage extends StatelessWidget {
  const DeviceScannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: th.AppColors.bg,
      appBar: AppBar(
        backgroundColor: th.AppColors.bg,
        title: Text(s.bindScaleTitle),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          DeviceScanPanel(
            autoStart: true,
            onSelected: (dev) => Navigator.pop(context, dev),
          ),
        ],
      ),
    );
  }
}

/// 可复用的扫描与绑定面板（用于引导页第二步 + 独立扫描页）。
/// 已绑定设备会按 MAC 自动匹配并显示备注名 + 「已绑定」标记，避免与原始广播名混淆。
class DeviceScanPanel extends StatefulWidget {
  final bool autoStart;
  final void Function(BoundDevice device) onSelected;
  const DeviceScanPanel({super.key, this.autoStart = true, required this.onSelected});
  @override State<DeviceScanPanel> createState() => _DeviceScanPanelState();
}

class _DeviceScanPanelState extends State<DeviceScanPanel> {
  final _ble = ScaleBle.instance;
  List<BoundDevice> _bound = [];

  @override
  void initState() {
    super.initState();
    _loadBound();
    _ble.addListener(_onBleChanged);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _ble.startScan(); });
    }
  }

  void _onBleChanged() { if (mounted) setState(() {}); }

  Future<void> _loadBound() async {
    _bound = await getDevices();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ble.removeListener(_onBleChanged);
    _ble.stopScan();
    super.dispose();
  }

  Future<void> _bindHit(ScanHit h) async {
    final mac = (h.realMac != '-' ? h.realMac : h.device.remoteId.toString()).toUpperCase();
    final existing = _bound.where((d) => d.id.toUpperCase() == mac).firstOrNull;
    if (existing != null) {
      await _ble.stopScan();
      widget.onSelected(existing);
      return;
    }
    // 默认名统一「体脂秤 + 序号」，不再用「我的体脂秤」（第一个也算 1）
    final defaultName = S.of(context).myScale + ' ' + (_bound.length + 1).toString();
    final nameCtrl = TextEditingController(text: defaultName);
    final ok = await showFormPage<bool>(
      context,
      title: S.of(context).addDevice,
      confirmLabel: S.of(context).confirm,
      onConfirm: () async => nameCtrl.text.trim().isNotEmpty,
      children: [
        // 绑定对话框里把「广播名」和「蓝牙 MAC」分开显示，MAC 用等宽加粗
        if (h.name.isNotEmpty)
          Text(
            h.name,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: th.AppColors.text),
          ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: th.AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(th.AppRadius.sm),
          ),
          child: Row(
            children: [
              Icon(Icons.bluetooth_rounded, size: 14, color: th.AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  mac,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: th.AppColors.textSub,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        formLabel(S.of(context).devName),
        TextField(
          controller: nameCtrl,
          autofocus: true,
          style: TextStyle(color: th.AppColors.text),
        ),
      ],
    );
    if (ok != true || !mounted) return;
    final dev = BoundDevice(
      id: mac,
      name: nameCtrl.text.trim().isEmpty ? defaultName : nameCtrl.text.trim(),
      model: h.name.isNotEmpty ? h.name : 'AFU-WL-TZ-A1',
      boundAt: DateTime.now().toIso8601String().substring(0, 10),
    );
    await addDevice(dev);
    await _loadBound();
    await _ble.stopScan();
    if (mounted) widget.onSelected(dev);
  }

  Future<void> _manualAdd() async {
    final macCtrl = TextEditingController();
    // 默认名统一「体脂秤 + 序号」，不再用「我的体脂秤」（第一个也算 1）
    final defaultName = S.of(context).myScale + ' ' + (_bound.length + 1).toString();
    final nameCtrl = TextEditingController(text: defaultName);
    String? err;
    final ok = await showFormPage<bool>(
      context,
      title: S.of(context).manualMac,
      confirmLabel: S.of(context).connectDirect,
      onConfirm: () async {
        final clean = macCtrl.text.trim().toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
        if (clean.length != 12) {
          err = S.of(context).macFormat;
          return false;
        }
        return true;
      },
      children: [
        Text(S.of(context).macHint, style: TextStyle(color: th.AppColors.textHint, fontSize: 12, height: 1.5)),
        formLabel(S.of(context).macLabel),
        TextField(
          controller: macCtrl,
          autofocus: true,
          style: TextStyle(color: th.AppColors.text, fontFamily: 'monospace'),
          decoration: const InputDecoration(hintText: 'AA:BB:CC:DD:EE:FF'),
        ),
        if (err != null) formHint(err!),
        formLabel(S.of(context).devName),
        TextField(
          controller: nameCtrl,
          style: TextStyle(color: th.AppColors.text),
        ),
      ],
    );
    if (ok != true || !mounted) return;
    final clean = macCtrl.text.trim().toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    if (clean.length != 12) return;
    final mac = clean.replaceAllMapped(RegExp(r'.{2}'), (m) => m.group(0)! + ':').substring(0, 17);
    final existing = _bound.where((d) => d.id.toUpperCase() == mac).firstOrNull;
    final dev = existing ?? BoundDevice(
      id: mac,
      name: nameCtrl.text.trim().isEmpty ? defaultName : nameCtrl.text.trim(),
      model: 'AFU-WL-TZ-A1',
      boundAt: DateTime.now().toIso8601String().substring(0, 10),
    );
    if (existing == null) await addDevice(dev);
    await _ble.stopScan();
    if (mounted) widget.onSelected(dev);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final hits = _ble.hits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: th.AppColors.surface,
            borderRadius: BorderRadius.circular(th.AppRadius.lg),
            border: Border.all(color: th.AppColors.border),
            boxShadow: th.AppShadows.soft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _ScanPulse(active: _ble.scanning),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _ble.scanning ? s.scanningNew : s.scanAndAdd,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: th.AppColors.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.bindScaleHint,
                          style: TextStyle(fontSize: 11, color: th.AppColors.textHint, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_ble.scanError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: th.AppColors.soft(th.AppColors.warnSoft, th.AppColors.warnSoftD), borderRadius: BorderRadius.circular(th.AppRadius.sm)),
                  child: Text(_ble.scanError!, style: TextStyle(color: th.AppColors.warn, fontSize: 12)),
                ),
              ],
              const SizedBox(height: 14),
              if (hits.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: Text(
                      _ble.scanning ? s.searchingNearby : s.noDeviceFound,
                      style: TextStyle(fontSize: 12, color: th.AppColors.textHint),
                    ),
                  ),
                )
              else
                ...hits.take(8).map((h) {
                  final mac = (h.realMac != '-' ? h.realMac : h.device.remoteId.toString()).toUpperCase();
                  final bound = _bound.where((d) => d.id.toUpperCase() == mac).firstOrNull;
                  final title = bound != null ? bound.name : (h.name.isNotEmpty ? h.name : mac);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: bound != null ? th.AppColors.primarySoft.withOpacity(th.AppColors.isDark ? 0.25 : 0.65) : th.AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(th.AppRadius.md),
                      border: Border.all(color: bound != null ? th.AppColors.primary : th.AppColors.border),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: bound != null ? th.AppColors.primarySoft : th.AppColors.surface,
                        child: Icon(
                          bound != null ? Icons.check_rounded : Icons.monitor_weight_outlined,
                          size: 18,
                          color: bound != null ? th.AppColors.primaryDeep : th.AppColors.textSub,
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: th.AppColors.text, fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (bound != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: th.AppColors.primary,
                                borderRadius: BorderRadius.circular(th.AppRadius.pill),
                              ),
                              child: Text(
                                s.boundTag,
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                      // MAC 用更亮的颜色 + 等宽字体突出显示，信号强度弱化
                      subtitle: Text.rich(
                        TextSpan(
                          children: [
                            if (bound != null && h.name.isNotEmpty)
                              TextSpan(
                                text: h.name + '\n',
                                style: TextStyle(fontSize: 10, color: th.AppColors.textHint),
                              ),
                            TextSpan(
                              text: mac,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                                color: th.AppColors.textSub,
                              ),
                            ),
                            TextSpan(
                              text: '   ' + h.rssi.toString() + ' dBm',
                              style: TextStyle(fontSize: 10, color: th.AppColors.textHint),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: th.AppColors.textHint),
                      onTap: () => _bindHit(h),
                    ),
                  );
                }),
              const SizedBox(height: 8),
              // 竖排：德语/英语的「手动输入 MAC」很长，并排会被压到换行
              OutlinedButton(
                onPressed: _ble.scanning ? () => _ble.stopScan() : () => _ble.startScan(),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                child: Text(
                  _ble.scanning ? s.stopScan : s.scanAndAdd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _manualAdd,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                child: Text(
                  s.manualMac,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScanPulse extends StatefulWidget {
  final bool active;
  const _ScanPulse({required this.active});
  @override State<_ScanPulse> createState() => _ScanPulseState();
}

class _ScanPulseState extends State<_ScanPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    if (widget.active) _ctrl.repeat();
  }
  @override
  void didUpdateWidget(covariant _ScanPulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ctrl.isAnimating) _ctrl.repeat();
    if (!widget.active && _ctrl.isAnimating) _ctrl.stop();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42, height: 42,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) {
          final t = widget.active ? _ctrl.value : 0.0;
          return Stack(alignment: Alignment.center, children: [
            if (widget.active)
              Container(
                width: 42 * (0.45 + t * 0.55),
                height: 42 * (0.45 + t * 0.55),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: th.AppColors.primary.withOpacity((1 - t) * 0.7), width: 2),
                ),
              ),
            Container(
              width: 24, height: 24,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: th.AppColors.primary),
              child: const Icon(Icons.bluetooth_rounded, size: 14, color: Colors.white),
            ),
          ]);
        },
      ),
    );
  }
}