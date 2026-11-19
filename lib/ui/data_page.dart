import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/models.dart';
import '../core/units.dart';
import '../core/bodycomp.dart';
import '../data/store.dart';
import 'package:afu_scale/i18n/l10n.dart';
import 'theme.dart' as th;
import 'widgets/app_sheet.dart';
import 'widgets/form_page.dart';

enum TimeRange { h72, d7, d30, custom }
enum DataView { list, trend }

class DataPage extends StatefulWidget {
  final UserProfile active;
  const DataPage({super.key, required this.active});
  @override State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> with SingleTickerProviderStateMixin {
  List<MeasurementRecord> _all = [];
  TimeRange _range = TimeRange.h72;
  // 自定义区间（筛选）状态
  String _customFrom = '';
  String _customTo = '';
  List<Map<String, String>> _savedRanges = [];
  DataView _view = DataView.list;
  final Set<String> _sel = {};
  DisplayUnit _unit = DisplayUnit.kg;
  double? _goalKg;
  bool _expanded = false;
  String? _detail;
  String _bfAlgo = 'officialAnt'; // 体脂算法（设置页可切）
  // 可选指标：默认显示 4 个，用户在芯片里切换
  final Set<String> _shown = {'fat', 'muscle', 'water', 'skeletal'};
  String _trendMetric = 'weight'; // weight | fat | muscle | water
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 700), value: 1.0);
    _load();
    _loadPrefs();
    _loadSavedRanges();
  }

  Future<void> _loadSavedRanges() async {
    final list = await getCustomRanges();
    if (mounted) setState(() => _savedRanges = list);
  }

  @override
  void didUpdateWidget(covariant DataPage old) {
    super.didUpdateWidget(old);
    if (old.active.name != widget.active.name) {
      _sel.clear();
      _load();
      _loadPrefs();
    }
  }

  @override
  void dispose() { _enter.dispose(); super.dispose(); }

  Future<void> _loadPrefs() async {
    final u = await getDisplayUnit();
    final g = await getGoal();
    final a = await getBfAlgo();
    if (mounted) {
      setState(() {
        _unit = u;
        _goalKg = (g != null && g.enabled) ? g.weightKg : null;
        _bfAlgo = a;
      });
    }
  }

  Future<void> _load({bool animate = true}) async {
    final list = await getRecords();
    _all = list.where((r) => r.unit == widget.active.name).toList();
    _all.sort((a, b) => b.time.compareTo(a.time));
    // 不再用入场动画控制透明度：AnimationController 没有监听者时
    // forward(from: 0) 会让卡片 opacity 恒为 0（历史 bug：打开 App 列表不显示）。
    _enter.value = 1.0;
    if (mounted) setState(() {});
  }

  List<MeasurementRecord> get filtered {
    final now = DateTime.now();
    return _all.where((r) {
      final t = DateTime.tryParse(r.time.replaceAll(' ', 'T'));
      if (t == null) return false;
      switch (_range) {
        case TimeRange.h72: return now.difference(t).inHours < 72;
        case TimeRange.d7: return now.difference(t).inDays < 7;
        case TimeRange.d30: return now.difference(t).inDays < 30;
        case TimeRange.custom:
          if (_customFrom.isEmpty || _customTo.isEmpty) return true;
          final from = DateTime.tryParse(_customFrom);
          final to = DateTime.tryParse(_customTo);
          if (from == null || to == null) return true;
          final start = DateTime(from.year, from.month, from.day);
          final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
          return !t.isBefore(start) && !t.isAfter(end);
      }
    }).toList();
  }

  BodyComposition? _bcOf(MeasurementRecord r) {
    if ((r.impedance1 ?? 0) <= 0) return null; // 无阻抗无论怎样都算不出体成分
    final pr = _profileFor(r);
    final stored = r.bodyComposition;
    final sp = r.profile;
    // 存量体成分只在「记录的档案与当前档案一致」时复用；
    // 改过性别/年龄/身高就按新档案重算，否则改了也不会有变化。
    final sameProfile = sp != null &&
        sp.sex == pr.sex &&
        sp.age == pr.age &&
        (sp.heightCm - pr.heightCm).abs() < 0.01;
    if (stored != null && sameProfile) return stored;
    return BodyCompositionCalc.estimate(
      weightKg: r.weightKg, heightCm: pr.heightCm, age: pr.age, sex: pr.sex,
      impedances: [r.impedance1 ?? 0, r.impedance2 ?? 0],
      algo: _bfAlgo,
    );
  }

  /// 记录该用谁的档案算指标：
  /// 属于当前选中的成员时，一律用**最新档案**——否则改了身高/性别/年龄，
  /// 记录里内嵌的旧 profile 会让 BMI 和体脂率纹丝不动。
  UserProfile _profileFor(MeasurementRecord r) {
    if (r.unit == widget.active.name) return widget.active;
    return r.profile ?? widget.active;
  }

  double? _bmiOf(MeasurementRecord r) {
    final h = _profileFor(r).heightCm;
    if (h <= 0) return null;
    final m = h / 100;
    return r.weightKg / (m * m);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final list = filtered;
    final visible = _expanded || list.length <= 12 ? list : list.sublist(0, 12);
    return Stack(
      children: [
        RefreshIndicator(
          color: th.AppColors.primary,
          backgroundColor: th.AppColors.surface,
          onRefresh: () async {
            await _load(animate: false);
            await _loadPrefs();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
            children: [
            _header(s),
            const SizedBox(height: 14),
            if (list.isNotEmpty) _hero(list.first, s),
            const SizedBox(height: 14),
            _rangeChips(s),
            const SizedBox(height: 14),
            Row(
              children: [
                _viewSwitchPill(s),
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _goalSheet(s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: _goalKg != null ? th.AppColors.soft(th.AppColors.warnSoft, th.AppColors.warnSoftD) : th.AppColors.surface,
                      borderRadius: BorderRadius.circular(th.AppRadius.pill),
                      border: Border.all(color: _goalKg != null ? th.AppColors.warn : th.AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flag_rounded, size: 13, color: _goalKg != null ? th.AppColors.warn : th.AppColors.textHint),
                        const SizedBox(width: 4),
                        Text(
                          _goalKg != null ? _unit.fmt(_goalKg!) : s.setGoalShort,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _goalKg != null ? th.AppColors.warn : th.AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        if (_sel.length == filtered.length && filtered.isNotEmpty) { _sel.clear(); }
                        else { _sel.addAll(filtered.map((r) => r.id)); }
                      });
                    },
                    child: Text(
                      _sel.isNotEmpty && _sel.length == filtered.length ? s.unselectAll : s.selectAllUnsynced,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, color: th.AppColors.primary, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _metricPickerRow(s),
            const SizedBox(height: 12),
            if (list.isEmpty) _empty(s)
            else if (_view == DataView.trend) _trendCard(list, s)
            else ..._recordCards(visible, s),
            if (list.length > 12 && _view == DataView.list) _expandBtn(s),
            ],
          ),
        ),
        if (_sel.isNotEmpty) _batchBar(s),
      ],
    );
  }

  /// 顶部不再放「数据」大标题（底部导航已经强调过），只留当前成员 + 条数。
  /// 顶部只保留右对齐的条数徽章；
  /// 姓名/性别/年龄已由顶栏用户胶囊呈现，重复一遍只会被截成省略号。
  /// 顶部信息条：左「目标进度」，右「N 条」。
  /// 进度 = (本周期最高体重 − 最新体重) ÷ (最高体重 − 目标体重)，
  /// 也就是「从最重到现在，朝目标走了多少」。没有目标或没有记录时只显示条数。
  Widget _header(S s) {
    final list = filtered;
    double? progress;
    if (_goalKg != null && list.isNotEmpty) {
      final newest = list.first.weightKg;
      final maxW = list.map((r) => r.weightKg).reduce((a, b) => a > b ? a : b);
      final span = maxW - _goalKg!;
      progress = span <= 0.01 ? 1.0 : ((maxW - newest) / span).clamp(0.0, 1.0);
    }
    return Row(
      children: [
        if (progress != null) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _unit.fmt(list.first.weightKg),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: th.AppColors.text,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.arrow_right_alt_rounded,
                      size: 13,
                      color: th.AppColors.textHint,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        s.goalLabel + ' ' + _unit.fmt(_goalKg!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: th.AppColors.textHint),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress < 0.04 ? 0.04 : progress,
                    minHeight: 5,
                    backgroundColor: th.AppColors.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation<Color>(th.AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
        ] else
          const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: th.AppColors.soft(th.AppColors.primarySoft, th.AppColors.primarySoftD),
            borderRadius: BorderRadius.circular(th.AppRadius.pill),
          ),
          child: Text(
            _all.length.toString() + ' ' + s.recordsUnit,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: th.AppColors.soft(th.AppColors.primaryDeep, th.AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _hero(MeasurementRecord latest, S s) {
    final bc = _bcOf(latest);
    final bmi = _bmiOf(latest);
    final delta = _all.length > 1 ? latest.weightKg - _all[1].weightKg : null;
    final goalDelta = _goalKg != null ? latest.weightKg - _goalKg! : null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3FC0A4), Color(0xFF4EA8FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(th.AppRadius.lg),
        boxShadow: th.AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _fullTime(latest.time),
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.85)),
              ),
              const Spacer(),
              if (bmi != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(th.AppRadius.pill),
                  ),
                  child: Text('BMI ' + bmi.toStringAsFixed(1), style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _unit.num(latest.weightKg),
                style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w800, color: Colors.white, height: 1, letterSpacing: -1.5),
              ),
              const SizedBox(width: 5),
              Text(_unit.suffix, style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              if (delta != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    (delta >= 0 ? '+' : '') + _unit.num(delta) + ' ' + _unit.suffix,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ),
            ],
          ),
          if (goalDelta != null) ...[
            const SizedBox(height: 8),
            Text(
              s.toGoal + ' ' + _unit.fmt(_goalKg!) + ' · ' + _unit.fmt(goalDelta.abs()),
              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.85)),
            ),
          ],
          if (bc == null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 13, color: Colors.white70),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      s.impedanceFailed,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          if (bc != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              children: [
                _heroMetric(s.bcFat, bc.bodyFatPercent, '%'),
                _heroMetric(s.bcMuscle, bc.muscleMassKg, 'kg'),
                _heroMetric(s.bcWater, bc.waterPercent, '%'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroMetric(String label, double value, String unit) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label + ' ', style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.8))),
      Text(
        value.toStringAsFixed(1) + unit,
        style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w800),
      ),
    ],
  );

  Widget _rangeChips(S s) {
    final items = <({String label, TimeRange? range, bool isFilter})>[
      (label: '72H', range: TimeRange.h72, isFilter: false),
      (label: '7d', range: TimeRange.d7, isFilter: false),
      (label: '30day', range: TimeRange.d30, isFilter: false),
      (label: s.filterShort, range: null, isFilter: true),
    ];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final it = items[i];
          final active = it.isFilter
              ? _range == TimeRange.custom
              : _range == it.range;
          final label = it.isFilter && _range == TimeRange.custom && _customFrom.isNotEmpty
              ? _customRangeLabel()
              : it.label;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (it.isFilter) {
                _openFilterSheet();
              } else {
                setState(() => _range = it.range!);
              }
            },
            onLongPress: it.isFilter ? _pickDateRange : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: active ? th.AppColors.primary : th.AppColors.surface,
                borderRadius: BorderRadius.circular(th.AppRadius.pill),
                border: Border.all(color: active ? th.AppColors.primary : th.AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (it.isFilter) ...[
                    Icon(
                      Icons.tune_rounded,
                      size: 13,
                      color: active ? Colors.white : th.AppColors.textSub,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: active ? Colors.white : th.AppColors.textSub,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _customRangeLabel() {
    String short(String d) => d.length >= 10 ? d.substring(5) : d;
    return short(_customFrom) + '~' + short(_customTo);
  }

  /// 点「筛选」：列出保存过的区间，可选用或新建。
  Future<void> _openFilterSheet() async {
    final s = S.of(context);
    await _loadSavedRanges();
    if (!mounted) return;
    await showAppSheet(
      context,
      title: s.filterRangeTitle,
      children: [
        if (_savedRanges.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              s.noSavedRanges,
              style: TextStyle(color: th.AppColors.textHint, fontSize: 12, height: 1.5),
            ),
          )
        else
          ..._savedRanges.map((r) {
            final active = _range == TimeRange.custom &&
                _customFrom == r['from'] &&
                _customTo == r['to'];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: active
                    ? th.AppColors.soft(th.AppColors.primarySoft, th.AppColors.primarySoftD)
                    : th.AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(th.AppRadius.md),
                border: Border.all(
                  color: active ? th.AppColors.primary : th.AppColors.border,
                ),
              ),
              child: ListTile(
                leading: Icon(
                  Icons.date_range_rounded,
                  size: 20,
                  color: active
                      ? th.AppColors.soft(th.AppColors.primaryDeep, th.AppColors.primary)
                      : th.AppColors.textSub,
                ),
                title: Text(
                  r['label'] ?? '',
                  style: TextStyle(
                    color: th.AppColors.text,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  (r['from'] ?? '') + ' → ' + (r['to'] ?? ''),
                  style: TextStyle(color: th.AppColors.textHint, fontSize: 10),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.close_rounded, size: 16, color: th.AppColors.textHint),
                  onPressed: () async {
                    await removeCustomRange(r['from']!, r['to']!);
                    if (mounted) Navigator.pop(context);
                    await _loadSavedRanges();
                  },
                ),
                onTap: () {
                  setState(() {
                    _range = TimeRange.custom;
                    _customFrom = r['from'] ?? '';
                    _customTo = r['to'] ?? '';
                  });
                  Navigator.pop(context);
                },
              ),
            );
          }),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context);
            _pickDateRange();
          },
          icon: const Icon(Icons.edit_calendar_rounded, size: 17),
          label: Text(s.selectDate),
        ),
      ],
    );
  }

  /// 长按「筛选」或点「选择日期」：弹出日期区间选择器，选完自动保存。
  Future<void> _pickDateRange() async {
    final s = S.of(context);
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: DateTime(now.year, now.month, now.day - 6),
        end: DateTime(now.year, now.month, now.day),
      ),
      helpText: s.filterRangeTitle,
      saveText: s.applyRange,
      builder: (ctx, child) => Theme(
        data: (th.AppColors.isDark ? th.AppTheme.dark : th.AppTheme.light),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    String fmt(DateTime d) =>
        d.year.toString().padLeft(4, '0') +
        '-' +
        d.month.toString().padLeft(2, '0') +
        '-' +
        d.day.toString().padLeft(2, '0');
    final from = fmt(picked.start);
    final to = fmt(picked.end);
    await addCustomRange(from, to);
    await _loadSavedRanges();
    if (!mounted) return;
    setState(() {
      _range = TimeRange.custom;
      _customFrom = from;
      _customTo = to;
    });
  }

  Widget _viewSwitchPill(S s) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: th.AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(th.AppRadius.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _viewTab(s.listView, DataView.list),
        _viewTab(s.trend, DataView.trend),
      ],
    ),
  );

  Widget _metricPickerRow(S s) {
    if (_view == DataView.trend) {
      final opts = [
        ('weight', s.weightLabel.split(' ').first, th.AppColors.primary),
        ('fat', s.bcFat, th.AppColors.fat),
        ('muscle', s.bcMuscle, th.AppColors.muscle),
        ('water', s.bcWater, th.AppColors.water),
      ];
      return SizedBox(
        height: 30,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: opts.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (ctx, i) {
            final id = opts[i].$1;
            final label = opts[i].$2;
            final color = opts[i].$3;
            final active = _trendMetric == id;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _trendMetric = id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: active ? color.withOpacity(0.16) : th.AppColors.surface,
                  borderRadius: BorderRadius.circular(th.AppRadius.pill),
                  border: Border.all(color: active ? color : th.AppColors.border),
                ),
                child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? color : th.AppColors.textHint)),
              ),
            );
          },
        ),
      );
    }
    final chips = [
      ('fat', s.bcFat, th.AppColors.fat),
      ('muscle', s.bcMuscle, th.AppColors.muscle),
      ('water', s.bcWater, th.AppColors.water),
      ('skeletal', s.bcSkeletal, th.AppColors.skeletal),
      ('protein', s.bcProtein, th.AppColors.protein),
      ('bone', s.bcBone, th.AppColors.bone),
    ];
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final id = chips[i].$1;
          final label = chips[i].$2;
          final color = chips[i].$3;
          final active = _shown.contains(id);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() { if (active) { if (_shown.length > 1) _shown.remove(id); } else { _shown.add(id); } }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: active ? color.withOpacity(0.15) : th.AppColors.surface,
                borderRadius: BorderRadius.circular(th.AppRadius.pill),
                border: Border.all(color: active ? color : th.AppColors.border),
              ),
              child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: active ? color : th.AppColors.textHint)),
            ),
          );
        },
      ),
    );
  }

  Widget _viewTab(String label, DataView v) {
    final active = _view == v;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _view = v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? th.AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(th.AppRadius.pill),
          boxShadow: active ? const [BoxShadow(color: Color(0x0F000000), blurRadius: 6)] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? th.AppColors.text : th.AppColors.textHint,
          ),
        ),
      ),
    );
  }

  Widget _empty(S s) => Container(
    padding: const EdgeInsets.symmetric(vertical: 46),
    child: Column(
      children: [
        Icon(Icons.insights_outlined, size: 40, color: th.AppColors.textHint),
        const SizedBox(height: 12),
        Text(s.noData, style: TextStyle(color: th.AppColors.textHint, fontSize: 13)),
        const SizedBox(height: 4),
        Text(s.noDataDesc, style: TextStyle(color: th.AppColors.textHint, fontSize: 11)),
      ],
    ),
  );

  double? _metricValue(MeasurementRecord r) {
    if (_trendMetric == 'weight') return _unit.fromKg(r.weightKg);
    final bc = _bcOf(r);
    if (bc == null) return null;
    switch (_trendMetric) {
      case 'fat': return bc.bodyFatPercent;
      case 'muscle': return bc.muscleMassKg;
      case 'water': return bc.waterPercent;
      default: return _unit.fromKg(r.weightKg);
    }
  }

  Color get _trendColor {
    switch (_trendMetric) {
      case 'fat': return th.AppColors.fat;
      case 'muscle': return th.AppColors.muscle;
      case 'water': return th.AppColors.water;
      default: return th.AppColors.primary;
    }
  }

  String _trendUnit() => (_trendMetric == 'fat' || _trendMetric == 'water') ? '%' : (_trendMetric == 'muscle' ? 'kg' : _unit.suffix);

  Widget _trendCard(List<MeasurementRecord> list, S s) {
    final valid = <({MeasurementRecord rec, double val})>[];
    for (final r in list.reversed) {
      if (r.weightKg < 10 || r.weightKg > 250) continue;
      final v = _metricValue(r);
      if (v != null && v > 0) valid.add((rec: r, val: v));
    }
    if (valid.length < 2) return _empty(s);
    final spots = <FlSpot>[];
    for (var i = 0; i < valid.length; i++) {
      spots.add(FlSpot(i.toDouble(), valid[i].val));
    }
    final maxY = spots.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    final minY = spots.map((e) => e.y).reduce((a, b) => a < b ? a : b);
    final pad = (maxY - minY) * 0.25 + 1;
    final lineColor = _trendColor;
    final uStr = _trendUnit();
    final goalY = (_trendMetric == 'weight' && _goalKg != null) ? _unit.fromKg(_goalKg!) : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      decoration: BoxDecoration(
        color: th.AppColors.surface,
        borderRadius: BorderRadius.circular(th.AppRadius.md),
        border: Border.all(color: th.AppColors.border),
        boxShadow: th.AppShadows.soft,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(s.trend, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: th.AppColors.text)),
              const Spacer(),
              Text(
                valid.first.val.toStringAsFixed(1) + ' → ' + valid.last.val.toStringAsFixed(1) + ' ' + uStr,
                style: TextStyle(fontSize: 10, color: th.AppColors.textHint),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: minY - pad,
                maxY: maxY + pad,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(color: th.AppColors.border, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (v, _) => Text(
                        v.toStringAsFixed(1),
                        style: TextStyle(fontSize: 9, color: th.AppColors.textHint),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: (valid.length / 4).clamp(1, 20).toDouble(),
                      getTitlesWidget: (v, _) {
                        final idx = v.round();
                        if (idx < 0 || idx >= valid.length) return const SizedBox.shrink();
                        final t = valid[idx].rec.time;
                        final label = t.length >= 10 ? t.substring(5, 10) : t;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(label, style: TextStyle(fontSize: 9, color: th.AppColors.textHint)),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: goalY == null
                    ? const ExtraLinesData()
                    : ExtraLinesData(horizontalLines: [
                        HorizontalLine(
                          y: goalY,
                          color: th.AppColors.warn.withOpacity(0.75),
                          strokeWidth: 1.5,
                          dashArray: [6, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: TextStyle(fontSize: 9, color: th.AppColors.warn, fontWeight: FontWeight.w700),
                            labelResolver: (_) => s.goalLabel,
                          ),
                        ),
                      ]),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => th.AppColors.text,
                    getTooltipItems: (items) => items.map((it) {
                      final idx = it.spotIndex.clamp(0, valid.length - 1);
                      final e = valid[idx];
                      return LineTooltipItem(
                        _fullTime(e.rec.time) + '\n' + e.val.toStringAsFixed(1) + ' ' + uStr,
                        TextStyle(color: th.AppColors.surface, fontSize: 11, fontWeight: FontWeight.w600),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.28,
                    color: lineColor,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (sp, p, b, i) => FlDotCirclePainter(
                        radius: 3.5,
                        color: th.AppColors.surface,
                        strokeWidth: 2,
                        strokeColor: lineColor,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          lineColor.withOpacity(0.22),
                          lineColor.withOpacity(0.02),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _recordCards(List<MeasurementRecord> list, S s) {
    return List.generate(list.length, (i) {
      final start = (i * 0.06).clamp(0.0, 0.6);
      final t = Curves.easeOutCubic.transform(
        ((_enter.value - start) / (1 - start)).clamp(0.0, 1.0),
      );
      return Transform.translate(
        offset: Offset(0, 14 * (1 - t)),
        child: Opacity(opacity: t, child: _recordCard(list[i], s)),
      );
    });
  }

  Widget _recordCard(MeasurementRecord r, S s) {
    final sel = _sel.contains(r.id);
    final hasImp = (r.impedance1 ?? 0) > 0;
    final bc = _bcOf(r);
    final bmi = _bmiOf(r);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 已进入多选模式时，点击卡片切换选中（避免误弹详情）；普通模式点击才看详情
      onTap: () {
        if (_sel.isNotEmpty) {
          setState(() => sel ? _sel.remove(r.id) : _sel.add(r.id));
        } else {
          _detailSheet(r, s);
        }
      },
      onLongPress: () => setState(() => sel ? _sel.remove(r.id) : _sel.add(r.id)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sel ? th.AppColors.soft(th.AppColors.primarySoft, th.AppColors.primarySoftD) : th.AppColors.surface,
          borderRadius: BorderRadius.circular(th.AppRadius.md),
          border: Border.all(color: sel ? th.AppColors.primary : th.AppColors.border),
          boxShadow: th.AppShadows.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _unit.num(r.weightKg),
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: th.AppColors.text, letterSpacing: -1, height: 1),
                        ),
                        const SizedBox(width: 3),
                        Text(_unit.suffix, style: TextStyle(fontSize: 12, color: th.AppColors.textHint, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(_fullTime(r.time), style: TextStyle(fontSize: 10, color: th.AppColors.textHint)),
                  ],
                ),
                const Spacer(),
                if (bmi != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: th.AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(th.AppRadius.pill),
                    ),
                    child: Text(
                      'BMI ' + bmi.toStringAsFixed(1),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: th.AppColors.primaryDeep),
                    ),
                  ),
                if (!hasImp)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.warning_amber_rounded, size: 15, color: th.AppColors.warn),
                  ),
              ],
            ),
            // 没有阻抗 → 明确写出「体成分未测得」，别让用户以为指标丢了
            if (bc == null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 13, color: th.AppColors.warn),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      s.impedanceFailed,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: th.AppColors.warn,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (bc != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (_shown.contains('fat')) _chip(s.bcFat, bc.bodyFatPercent, '%', th.AppColors.fat, th.AppColors.soft(th.AppColors.fatSoft, th.AppColors.fatSoftD)),
                  if (_shown.contains('muscle')) _chip(s.bcMuscle, bc.muscleMassKg, 'kg', th.AppColors.muscle, th.AppColors.soft(th.AppColors.muscleSoft, th.AppColors.muscleSoftD)),
                  if (_shown.contains('water')) _chip(s.bcWater, bc.waterPercent, '%', th.AppColors.water, th.AppColors.soft(th.AppColors.waterSoft, th.AppColors.waterSoftD)),
                  if (_shown.contains('protein')) _chip(s.bcProtein, bc.proteinMassKg, 'kg', th.AppColors.protein, th.AppColors.soft(th.AppColors.proteinSoft, th.AppColors.proteinSoftD)),
                  if (_shown.contains('bone')) _chip(s.bcBone, bc.boneMassKg, 'kg', th.AppColors.bone, th.AppColors.soft(th.AppColors.boneSoft, th.AppColors.boneSoftD)),
                  if (_shown.contains('skeletal')) _chip(s.bcSkeletal, bc.skeletalMuscleMassKg, 'kg', th.AppColors.skeletal, th.AppColors.soft(th.AppColors.skeletalSoft, th.AppColors.skeletalSoftD)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, double value, String unit, Color color, Color soft) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(th.AppRadius.pill)),
    child: Text(
      label + ' ' + value.toStringAsFixed(1) + unit,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
    ),
  );

  Widget _expandBtn(S s) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _expanded = !_expanded),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: th.AppColors.surface,
        borderRadius: BorderRadius.circular(th.AppRadius.md),
        border: Border.all(color: th.AppColors.border),
      ),
      child: Center(
        child: Text(
          _expanded ? s.collapse : s.expandMore,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: th.AppColors.primary),
        ),
      ),
    ),
  );

  Widget _batchBar(S s) => Positioned(
    bottom: 14, left: 20, right: 20,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: th.AppColors.elevated,
        borderRadius: BorderRadius.circular(th.AppRadius.lg),
        border: Border.all(color: th.AppColors.borderStrong),
        boxShadow: th.AppShadows.float,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: th.AppColors.soft(th.AppColors.primarySoft, th.AppColors.primarySoftD),
              borderRadius: BorderRadius.circular(th.AppRadius.pill),
            ),
            child: Text(
              _sel.length.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: th.AppColors.soft(th.AppColors.primaryDeep, th.AppColors.primary),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: () => _push(s),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(40)),
              child: Text(s.pushSelected, style: const TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _transfer(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
              child: Text(
                s.transferTo,
                style: TextStyle(
                  fontSize: 12,
                  color: th.AppColors.soft(th.AppColors.primaryDeep, th.AppColors.primary),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _delete(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
              child: Text(
                s.delete,
                style: TextStyle(fontSize: 12, color: th.AppColors.danger, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _push(S s) async {
    setState(() => _detail = s.pushing);
    await Future.delayed(const Duration(milliseconds: 400));
    setState(() => _detail = null);
  }

  Future<void> _delete(S s) async {
    await deleteRecords(_sel);
    _sel.clear();
    await _load();
  }

  Future<void> _transfer(S s) async {
    final profiles = await getProfiles();
    final others = profiles.where((p) => p.name != widget.active.name).toList();
    if (others.isEmpty) { setState(() => _detail = '没有其他成员'); return; }
    if (!mounted) return;
    await showAppSheet(context, title: s.transferTo, children: [
      Text(s.transferHint, style: TextStyle(color: th.AppColors.textHint, fontSize: 12)),
      const SizedBox(height: 10),
      ...others.map((p) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(backgroundColor: th.AppColors.primarySoft, child: Text(p.name[0], style: TextStyle(color: th.AppColors.primaryDeep))),
        title: Text(p.name, style: TextStyle(color: th.AppColors.text)),
        // 转移时最需要区分的是性别/身高/年龄，体重不是选人的依据
        subtitle: Text(
          (p.isMale ? s.sexMale : s.sexFemale) +
              ' · ' +
              p.heightCm.toStringAsFixed(1) +
              'cm · ' +
              p.age.toString() +
              s.ageSuffix,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: th.AppColors.textHint, fontSize: 11),
        ),
        onTap: () async {
          final all = await getRecords();
          final picked = all.where((r) => _sel.contains(r.id)).toList();
          await transferRecords(picked, p.name);
          _sel.clear();
          await _load();
          if (mounted) Navigator.pop(context);
        },
      )),
    ]);
  }

  /// 目标体重设置（从数据页直接进，全屏表单页确保键盘不遮挡）。
  void _goalSheet(S s) async {
    final current = await getGoal();
    final ctrl = TextEditingController(
      text: (current != null && current.enabled) ? current.weightKg.toStringAsFixed(1) : '',
    );
    if (!mounted) return;
    showFormPage(
      context,
      title: s.goalSheetTitle,
      confirmLabel: s.saveGoal,
      onConfirm: () async {
        final v = double.tryParse(ctrl.text.trim());
        if (v == null || v <= 20) return false;
        await setGoal(GoalWeight(weightKg: v, enabled: true));
        await _loadPrefs();
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
            await _loadPrefs();
            if (mounted) Navigator.pop(context);
          },
          child: Text(s.clearGoal, style: TextStyle(color: th.AppColors.danger)),
        ),
      ],
    );
  }

  void _detailSheet(MeasurementRecord r, S s) {
    final bc = _bcOf(r);
    final bmi = _bmiOf(r);
    final hasImp = (r.impedance1 ?? 0) > 0;
    showAppSheet(
      context,
      title: _fullTime(r.time),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(_unit.num(r.weightKg), style: TextStyle(color: th.AppColors.text, fontSize: 40, fontWeight: FontWeight.w800, height: 1, letterSpacing: -1.5)),
            const SizedBox(width: 4),
            Text(_unit.suffix, style: TextStyle(color: th.AppColors.textSub, fontSize: 15, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (bmi != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: th.AppColors.primarySoft, borderRadius: BorderRadius.circular(th.AppRadius.pill)),
                child: Text('BMI ' + bmi.toStringAsFixed(1), style: TextStyle(color: th.AppColors.soft(th.AppColors.primaryDeep, th.AppColors.primary), fontSize: 12, fontWeight: FontWeight.w800)),
              ),
          ],
        ),
        if (r.unit.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('成员 · ' + r.unit, style: TextStyle(color: th.AppColors.textSub, fontSize: 12)),
          ),
        const SizedBox(height: 18),
        if (bc == null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: th.AppColors.soft(th.AppColors.warnSoft, th.AppColors.warnSoftD), borderRadius: BorderRadius.circular(th.AppRadius.sm)),
            child: Text(hasImp ? s.compUnavailable : s.impedanceFailed, style: TextStyle(color: th.AppColors.warn, fontSize: 12)),
          )
        else ...[
          _detailGroup('体成分', [
            ('体脂率', bc.bodyFatPercent.toStringAsFixed(1) + '%'),
            ('脂肪量', bc.fatMassKg.toStringAsFixed(1) + ' kg'),
            ('去脂体重', bc.fatFreeMassKg.toStringAsFixed(1) + ' kg'),
            ('肌肉量', bc.muscleMassKg.toStringAsFixed(1) + ' kg'),
            ('肌肉率', bc.musclePercent.toStringAsFixed(1) + '%'),
            ('骨骼肌量', bc.skeletalMuscleMassKg.toStringAsFixed(1) + ' kg'),
            ('骨骼肌率', bc.skeletalMusclePercent.toStringAsFixed(1) + '%'),
            ('蛋白质量', bc.proteinMassKg.toStringAsFixed(1) + ' kg'),
            ('骨量', bc.boneMassKg.toStringAsFixed(1) + ' kg'),
            ('水分率', bc.waterPercent.toStringAsFixed(1) + '%'),
            ('水分量', bc.waterMassKg.toStringAsFixed(1) + ' kg'),
            ('皮下脂肪率', bc.subcutaneousFatPercent.toStringAsFixed(1) + '%'),
            ('皮下脂肪量', bc.subcutaneousFatMassKg.toStringAsFixed(1) + ' kg'),
          ]),
          const SizedBox(height: 14),
          _detailGroup('测量原始值', [
            ('阻抗 1', (r.impedance1 ?? 0) > 0 ? (r.impedance1!).toStringAsFixed(0) + ' Ω' : '—'),
            ('阻抗 2', (r.impedance2 ?? 0) > 0 ? (r.impedance2!).toStringAsFixed(0) + ' Ω' : '—'),
            ('合成阻抗', bc.resistanceOhm != null ? bc.resistanceOhm!.toStringAsFixed(0) + ' Ω' : '—'),
            ('算法', bc.model),
            ('电极', hasImp ? '导通' : '未导通'),
          ]),
        ],
        const SizedBox(height: 14),
        Text(s.estimateLine, style: TextStyle(color: th.AppColors.textHint, fontSize: 10)),
      ],
    );
  }

  Widget _detailGroup(String title, List<(String, String)> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: TextStyle(color: th.AppColors.textHint, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(color: th.AppColors.surfaceAlt, borderRadius: BorderRadius.circular(th.AppRadius.sm)),
        child: Column(
          children: rows.map((e) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                Text(e.$1, style: TextStyle(color: th.AppColors.textSub, fontSize: 12)),
                const Spacer(),
                Text(e.$2, style: TextStyle(color: th.AppColors.text, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          )).toList(),
        ),
      ),
    ],
  );

  String _fullTime(String raw) {
    final t = raw.replaceAll('T', ' ');
    return t.length >= 19 ? t.substring(0, 19) : t;
  }
}