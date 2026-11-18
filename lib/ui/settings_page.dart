import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/units.dart';
import '../data/store.dart';
import '../data/debug_log.dart';
import '../sync/sync_client.dart' as sync;
import 'package:afu_scale/i18n/l10n.dart';
import 'pending_page.dart';
import 'profile_editor.dart';
import 'device_scanner_page.dart';
import 'widgets/app_sheet.dart';
import 'widgets/form_page.dart';
import 'theme.dart' as th;

class SettingsPage extends StatefulWidget {
  final UserProfile active;
  final List<UserProfile> profiles;
  final VoidCallback onChanged;
  final String themeMode;
  final Future<void> Function(String) onThemeMode;
  /// 每次从别的 tab 切回设置页时递增，用于重新读取可能被测量页改过的设置。
  final int refreshToken;
  const SettingsPage({
    super.key,
    required this.active,
    required this.profiles,
    required this.onChanged,
    this.themeMode = 'system',
    required this.onThemeMode,
    this.refreshToken = 0,
  });
  @override State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  DisplayUnit _unit = DisplayUnit.kg;
  String _syncUrl = '';
  int _pendingCount = 0;
  String? _status;
  String _incompletePolicy = 'ask';
  bool _debugMode = false;
  int _versionTapCount = 0; // 关于页连点版本号的计数（彩蛋）

  @override
  void initState() {
    super.initState();
    _load();
    _reloadProfiles();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      // 设置页常驻在 IndexedStack 中，initState 只跑一次；
      // 测量页长按改过策略后必须在这里重读，否则显示的是旧值。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _load();
          _reloadProfiles();
        }
      });
    }
  }

  List<UserProfile> _liveProfiles = [];
  Future<void> _reloadProfiles() async {
    final list = await getProfiles();
    if (mounted) setState(() => _liveProfiles = list);
  }

  Future<void> _load() async {
    _unit = await getDisplayUnit();
    _syncUrl = await getSyncUrl();
    _pendingCount = (await getPending()).length;
    _incompletePolicy = await getIncompletePolicy();
    _debugMode = await getDebugMode();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final loc = AppLocale.of(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (_status != null)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: th.AppTheme.accentSoft, borderRadius: BorderRadius.circular(10)),
          child: Text(_status!, style: TextStyle(color: th.AppTheme.accent, fontSize: 12)),
        ),
      _group(s.appearance, [
        _themeRow(s),
      ]),
      _group(s.language, [
        _row(Icons.translate, s.language, loc.isSystem ? s.followSystem : S(loc.resolvedCode).nativeName, () => _langSheet(s, loc)),
      ]),
      _group(s.unitSection2, [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(child: _unitTab(DisplayUnit.kg)),
              const SizedBox(width: 8),
              Expanded(child: _unitTab(DisplayUnit.lb)),
              const SizedBox(width: 8),
              Expanded(child: _unitTab(DisplayUnit.jin)),
            ],
          ),
        ),
      ]),
      _group(s.goalSheetTitle, [
      FutureBuilder<GoalWeight?>(
        future: getGoal(),
        builder: (ctx, snap) => _row(
          Icons.flag,
          s.goalLabel,
          (snap.data == null || !snap.data!.enabled) ? s.goalUnset : _unit.fmt(snap.data!.weightKg),
          () => _goalSheet(s),
        ),
      ),
      ]),
      _group(s.incompleteSection, [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Text(
            s.incompleteHint,
            style: TextStyle(color: th.AppColors.textHint, fontSize: 11, height: 1.5),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              _policyTab(s.policyAsk, 'ask'),
              const SizedBox(width: 8),
              _policyTab(s.policySave, 'save'),
              const SizedBox(width: 8),
              _policyTab(s.policySkip, 'skip'),
            ],
          ),
        ),
      ]),

      _group(s.profilesTitle, [
        _row(Icons.person, s.profilesTitle, (_liveProfiles.isEmpty ? widget.profiles : _liveProfiles).length.toString(), () async { await showProfileManager(context, profiles: (_liveProfiles.isEmpty ? widget.profiles : _liveProfiles), activeName: widget.active.name, onChanged: () async { widget.onChanged(); await _load(); }); }),
        _row(Icons.merge_type_rounded, s.fixOwnership, '', () async {
          final orphans = await getOrphanRecordUnits();
          if (!mounted) return;
          if (orphans.isEmpty) {
            setState(() => _status = s.noOrphan);
            return;
          }
          await _fixOrphansSheet(s, orphans);
        }),
        _row(Icons.history, s.pendingTitle, _pendingCount.toString(), () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => PendingPage(active: widget.active, profiles: widget.profiles, onChanged: () { widget.onChanged(); _load(); })));
          _load();
        }),
      ]),
      _group(s.syncSettings, [
        _row(Icons.settings_ethernet, s.pushUrl, _syncUrl, () => _syncSheet(s)),
        _row(Icons.wifi_tethering, s.testConn, '', () => _testConn(s)),
        _row(Icons.cloud_download, s.pullFromPc, '', () => _pull(s)),
      ]),
      _group(s.boundDevices, [
        _row(Icons.scale, s.boundDevices, '', () => _devicesSheet(s)),
        if (_debugMode) _row(Icons.bug_report, s.debugLog, '', () => _logSheet(s)),
      ]),
      _group(s.about, [
        _row(Icons.info_outline, s.about, 'v0.2.0', () => _aboutSheet(s)),
      ]),
      const SizedBox(height: 24),
      // 底部版权（固定文案，不随语言变化）
      Center(
        child: Text(
          '© 2026 Lingaiyue. All rights reserved.',
          style: TextStyle(color: th.AppTheme.textHint, fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 12),
    ]);
  }

  /// 单位选择：只用「符号 + 数字换算」两行，避免任何语言下文字过长溢出。
  Widget _policyTab(String label, String value) {
    final active = _incompletePolicy == value;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          await setIncompletePolicy(value);
          setState(() { _incompletePolicy = value; });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? th.AppColors.soft(th.AppColors.primarySoft, th.AppColors.primarySoftD) : th.AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(th.AppRadius.sm),
            border: Border.all(color: active ? th.AppColors.primary : th.AppColors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              color: active ? th.AppColors.soft(th.AppColors.primaryDeep, th.AppColors.primary) : th.AppColors.textSub,
            ),
          ),
        ),
      ),
    );
  }

  Widget _unitTab(DisplayUnit unit) {
    final active = _unit == unit;
    final symbol = unit.suffix;
    final sample = unit.num(70.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await setDisplayUnit(unit);
        setState(() => _unit = unit);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: active ? th.AppColors.primarySoft : th.AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(th.AppRadius.sm),
          border: Border.all(
            color: active ? th.AppColors.primary : th.AppColors.border,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (active) ...[
                  Icon(Icons.check_rounded, size: 13, color: th.AppColors.primaryDeep),
                  const SizedBox(width: 3),
                ],
                Text(
                  symbol,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: active ? th.AppColors.primaryDeep : th.AppColors.textSub,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              sample,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 10,
                color: active ? th.AppColors.primaryDeep.withOpacity(0.65) : th.AppColors.textHint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 外观：只有图标 + 三段选择器，不再重复一行「深色模式」文字。
  Widget _themeRow(S s) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.dark_mode_rounded, size: 18, color: th.AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: th.AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(th.AppRadius.pill),
              ),
              child: Row(
                children: [
                  _modeTab(s.themeLight, 'light'),
                  _modeTab(s.themeDark, 'dark'),
                  _modeTab(s.themeSystem, 'system'),
                ],
              ),
            ),
          ),
        ],
      ),
    );

  Widget _modeTab(String label, String mode) {
    final active = widget.themeMode == mode;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onThemeMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: active ? th.AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(th.AppRadius.pill),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : th.AppColors.textHint,
            ),
          ),
        ),
      ),
    );
  }

  Widget _group(String title, List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.only(left: 4, bottom: 6, top: 8), child: Text(title, style: TextStyle(color: th.AppTheme.textHint, fontSize: 12, fontWeight: FontWeight.w700))),
    Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: th.AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: th.AppTheme.border)),
      child: Column(children: children),
    ),
  ]);

  Widget _row(IconData icon, String title, String value, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        Icon(icon, size: 18, color: th.AppTheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: TextStyle(color: th.AppTheme.text, fontSize: 14))),
        if (value.isNotEmpty)
          Flexible(child: Text(value, overflow: TextOverflow.ellipsis, style: TextStyle(color: th.AppTheme.textHint, fontSize: 11))),
        Icon(Icons.chevron_right, size: 18, color: th.AppTheme.textHint),
      ]),
    ),
  );

  Future<void> _sheet(String title, List<Widget> body) =>
      showAppSheet(context, title: title, children: body);

  void _langSheet(S s, AppLocale loc) {
    _sheet(s.language, [
      ListTile(
        title: Text(s.followSystem, style: TextStyle(color: th.AppTheme.text)),
        trailing: loc.isSystem ? Icon(Icons.check, color: th.AppTheme.accent) : null,
        onTap: () async { await loc.setLang('system'); Navigator.pop(context); setState(() {}); },
      ),
      ...supportedLangCodes.map((code) => ListTile(
        title: Text(S(code).nativeName, style: TextStyle(color: th.AppTheme.text)),
        trailing: (!loc.isSystem && loc.resolvedCode == code) ? Icon(Icons.check, color: th.AppTheme.accent) : null,
        onTap: () async { await loc.setLang(code); Navigator.pop(context); setState(() {}); },
      )),
    ]);
  }

  void _goalSheet(S s) {
    final ctrl = TextEditingController();
    getGoal().then((g) {
      if (g != null && g.enabled) ctrl.text = g.weightKg.toStringAsFixed(1);
    });
    showFormPage(
      context,
      title: s.goalSheetTitle,
      confirmLabel: s.saveGoal,
      onConfirm: () async {
        final v = double.tryParse(ctrl.text.trim());
        if (v == null || v <= 20) return false;
        await setGoal(GoalWeight(weightKg: v, enabled: true));
        await _load();
        return true;
      },
      children: [
        Text(s.goalHint, style: TextStyle(color: th.AppColors.textHint, fontSize: 12, height: 1.6)),
        formLabel(s.goalLabel),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: TextStyle(color: th.AppColors.text, fontSize: 20, fontWeight: FontWeight.w700),
          decoration: InputDecoration(hintText: s.goalPlaceholder, suffixText: 'kg'),
        ),
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: () async {
            await setGoal(GoalWeight(weightKg: 60, enabled: false));
            await _load();
            if (mounted) Navigator.pop(context);
          },
          child: Text(s.clearGoal, style: TextStyle(color: th.AppColors.danger)),
        ),
      ],
    );
  }

  void _syncSheet(S s) async {
    final current = await getSyncUrl();
    final ctrl = TextEditingController(text: current);
    if (!mounted) return;
    showFormPage(
      context,
      title: s.pushUrl,
      confirmLabel: s.saveUrl,
      onConfirm: () async {
        await setSyncUrl(ctrl.text.trim());
        await _load();
        return true;
      },
      children: [
        Text(s.pushUrlHint, style: TextStyle(color: th.AppColors.textHint, fontSize: 12, height: 1.6)),
        formLabel(s.pushUrl),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          autofocus: true,
          style: TextStyle(color: th.AppColors.text, fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(hintText: 'http://192.168.1.5:8765/records'),
        ),
      ],
    );
  }

  Future<void> _testConn(S s) async {
    setState(() => _status = s.testing);
    final r = await sync.testConnection(_syncUrl);
    if (!mounted) return;
    final okFlag = r['ok'] == true;
    final ms = r['ms'];
    setState(() { _status = (okFlag ? s.connOk : s.connFail) + (ms != null ? ' ' + ms.toString() + 'ms' : ''); });
  }

  Future<void> _pull(S s) async {
    setState(() => _status = s.pulling);
    final remote = await sync.fetchRemote(_syncUrl);
    if (!mounted) return;
    final local = await getRecords();
    final ids = local.map((r) => r.id).toSet();
    final added = remote.where((r) => !ids.contains(r.id)).toList();
    if (added.isNotEmpty) await saveRecords([...local, ...added]);
    setState(() { _status = s.pullResult + ': ' + added.length.toString(); });
    widget.onChanged();
  }

  /// 修复改名等原因造成的「记录归属名已不存在」问题。
  Future<void> _fixOrphansSheet(S s, Map<String, OrphanUnitInfo> orphans) async {
    final profiles = await getProfiles();
    if (!mounted) return;
    await _sheet(s.fixOwnership, [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          s.fixOwnershipHint,
          style: TextStyle(color: th.AppColors.textHint, fontSize: 12, height: 1.5),
        ),
      ),
      ...orphans.entries.map((e) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: th.AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(th.AppRadius.md),
          border: Border.all(color: th.AppColors.border),
        ),
        child: ListTile(
          leading: Icon(Icons.help_outline_rounded, color: th.AppColors.warn, size: 20),
          title: Text(
            e.key.isEmpty ? s.unnamed : e.key,
            style: TextStyle(color: th.AppColors.text, fontWeight: FontWeight.w700, fontSize: 13),
          ),
          subtitle: Text(
            _orphanSubtitle(e.value, s),
            style: TextStyle(color: th.AppColors.textHint, fontSize: 11),
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: th.AppColors.textHint),
          onTap: () async {
            if (profiles.isEmpty) {
              Navigator.pop(context);
              setState(() => _status = s.plsCreateProfile);
              return;
            }
            Navigator.pop(context);
            await _pickTargetFor(s, e.key, profiles);
          },
        ),
      )),
    ]);
  }

  Future<void> _pickTargetFor(S s, String fromUnit, List<UserProfile> profiles) async {
    if (!mounted) return;
    await _sheet(s.assignToWhom, [
      ...profiles.map((p) => ListTile(
        leading: CircleAvatar(
          backgroundColor: th.AppColors.soft(th.AppColors.primarySoft, th.AppColors.primarySoftD),
          child: Text(p.name.substring(0, 1), style: TextStyle(color: th.AppColors.soft(th.AppColors.primaryDeep, th.AppColors.primary))),
        ),
        title: Text(p.name, style: TextStyle(color: th.AppColors.text)),
        subtitle: Text(
          _profileSubtitle(p, s),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: th.AppColors.textHint, fontSize: 11),
        ),
        onTap: () async {
          final n = await reassignRecords(fromUnit, p.name);
          widget.onChanged(); // VoidCallback，不可 await
          await _load();
          if (!mounted) return;
          Navigator.pop(context);
          setState(() => _status = s.fixOwnership + ' · ' + n.toString() + ' ' + s.recordsUnit + ' → ' + p.name);
        },
      )),
    ]);
  }

  /// 成员档案摘要：「女 · 163cm · 24岁」
  String _profileSubtitle(UserProfile p, S s) {
    final parts = <String>[p.isMale ? s.sexMale : s.sexFemale];
    if (p.heightCm > 0) parts.add(p.heightCm.toStringAsFixed(1) + 'cm');
    if (p.age > 0) parts.add(p.age.toString() + s.ageSuffix);
    return parts.join(' · ');
  }

  /// 孤儿记录摘要：「女 · 163cm · 24岁 · 12 条记录」（旧档案缺失时只显示条数）
  String _orphanSubtitle(OrphanUnitInfo info, S s) {
    final parts = <String>[];
    final p = info.profile;
    if (p != null) {
      parts.add(p.isMale ? s.sexMale : s.sexFemale);
      if (p.heightCm > 0) parts.add(p.heightCm.toStringAsFixed(1) + 'cm');
      if (p.age > 0) parts.add(p.age.toString() + s.ageSuffix);
      if (p.weightKg != null && p.weightKg! > 0) {
        parts.add(p.weightKg!.toStringAsFixed(1) + 'kg');
      }
    }
    parts.add(info.count.toString() + ' ' + s.recordsUnit);
    return parts.join(' · ');
  }

  void _devicesSheet(S s) async {
    final devices = await getDevices();
    if (!mounted) return;
    await _sheet(s.boundDevices, [
      if (devices.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(s.noDeviceTitle, style: TextStyle(color: th.AppColors.textHint)),
        ),
      ...devices.map((d) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: th.AppColors.primarySoft,
          child: Icon(Icons.monitor_weight_outlined, size: 18, color: th.AppColors.primaryDeep),
        ),
        title: Text(
          d.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: th.AppColors.text, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          d.model + ' · ' + d.id,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: th.AppColors.textHint, fontFamily: 'monospace', fontSize: 10),
        ),
        // 操作只用图标：德语/英语的「解绑」文字会把标题挤成竖排、卡片拉得很高
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: s.rename,
              icon: Icon(Icons.edit_outlined, size: 18, color: th.AppColors.textSub),
              onPressed: () async {
                Navigator.pop(context);
                final ctrl = TextEditingController(text: d.name);
                final ok = await showFormPage<bool>(
                  context,
                  title: s.rename,
                  confirmLabel: s.save,
                  onConfirm: () async {
                    if (ctrl.text.trim().isEmpty) return false;
                    await renameDevice(d.id, ctrl.text.trim());
                    return true;
                  },
                  children: [
                    formLabel(s.devName),
                    TextField(controller: ctrl, autofocus: true, style: TextStyle(color: th.AppColors.text)),
                  ],
                );
                if (ok == true && mounted) setState(() {});
              },
            ),
            IconButton(
              tooltip: s.unbind,
              onPressed: () async {
                await removeDevice(d.id);
                if (mounted) { Navigator.pop(context); setState(() {}); }
              },
              icon: Icon(Icons.link_off_rounded, size: 18, color: th.AppColors.danger),
            ),
          ],
        ),
      )),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: () async {
          Navigator.pop(context);
          await openDeviceScanner(context);
          if (mounted) setState(() {});
        },
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(s.addDevice),
      ),
    ]);
  }

  void _logSheet(S s) {
    final lines = DebugLog.instance.lines(count: 100);
    _sheet(s.debugLog, [
      SizedBox(
        height: 320,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines.map((l) => Text(l, style: TextStyle(color: th.AppTheme.textSub, fontSize: 10, fontFamily: 'monospace'))).toList()),
        ),
      ),
      TextButton(onPressed: () { DebugLog.instance.clear(); Navigator.pop(context); }, child: Text(s.clear)),
    ]);
  }

  void _aboutSheet(S s) {
    const repos = <(String, String)>[
      ('Fatpandac/AFUScale', 'iOS 协议参考'),
      ('Mzdyl/ant-afu-welland-scale', 'Python 实现'),
      ('monkey-wenjun/vitaloop-app', 'Android BLE'),
      ('Xuan-lprk/WeighTrace', '广播解析与扫描策略'),
      ('ZeroOneCN/AntAF', '体重编码与 BIA 公式'),
    ];
    _sheet(s.about, [
      // ── 品牌 + 版本（彩蛋：连点 7 次切换调试模式）──
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          _versionTapCount++;
          if (_versionTapCount < 7) return;
          _versionTapCount = 0;
          _debugMode = !_debugMode;
          await setDebugMode(_debugMode);
          if (!mounted) return;
          setState(() {});
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_debugMode ? '调试模式已开启' : '调试模式已关闭'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        child: Center(
          child: Column(
            children: [
              Container(
                width: 58, height: 58,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3FC0A4), Color(0xFF4EA8FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: th.AppShadows.card,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.monitor_weight_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 10),
              Text('AFU', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: th.AppColors.text, letterSpacing: 2)),
              const SizedBox(height: 2),
              Text('v0.2.0 · Flutter', style: TextStyle(fontSize: 11, color: th.AppColors.textHint, letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 22),
      // ── 设备与仓库信息 ──
      _aboutRow(s.adaptation, 'AFU-WL-TZ-A1'),
      _aboutRow('ICOMON / Welland', 'FG2313UWB-D'),
      _aboutRow(s.ghRepo, 'github.com/Linmord/afu-scale-app'),
      const SizedBox(height: 22),
      // ── 致谢 ──
      _sectionLabel(s.credits),
      const SizedBox(height: 12),
      Text(
        s.creditsDesc,
        style: TextStyle(fontSize: 11.5, color: th.AppColors.textSub, height: 1.65),
      ),
      const SizedBox(height: 12),
      ...repos.map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 5, height: 5,
                  margin: const EdgeInsets.only(top: 5, right: 9),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: th.AppColors.primary,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: th.AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        r.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: th.AppColors.textHint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )),
      const SizedBox(height: 6),
      Center(
        child: Text(
          s.creditsLicense,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: th.AppColors.textHint, height: 1.5),
        ),
      ),
    ]);
  }

  /// 关于页的信息行：左灰标签 + 右值，两端对齐。
  Widget _aboutRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          flex: 4,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: th.AppColors.textHint),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: th.AppColors.textSub,
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );

  /// 小节标题：两侧细线夹住居中的小字。
  Widget _sectionLabel(String text) => Row(
    children: [
      Expanded(child: Divider(color: th.AppColors.border, thickness: 1)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: th.AppColors.textSub,
            letterSpacing: 1.2,
          ),
        ),
      ),
      Expanded(child: Divider(color: th.AppColors.border, thickness: 1)),
    ],
  );
}
