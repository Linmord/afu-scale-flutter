import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/bodycomp.dart';
import '../core/units.dart';
import '../data/store.dart';
import 'package:afu_scale/i18n/l10n.dart';
import 'theme.dart' as th;

class PendingPage extends StatefulWidget {
  final UserProfile active;
  final List<UserProfile> profiles;
  final VoidCallback onChanged;
  const PendingPage({super.key, required this.active, required this.profiles, required this.onChanged});
  @override State<PendingPage> createState() => _PendingPageState();
}

class _PendingPageState extends State<PendingPage> {
  List<PendingHistory> _items = [];
  final Set<String> _sel = {};
  DisplayUnit _unit = DisplayUnit.kg;
  String _bfAlgo = 'officialAnt';

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    _items = await getPending();
    _unit = await getDisplayUnit();
    _bfAlgo = await getBfAlgo();
    if (mounted) setState(() {});
  }

  @override Widget build(BuildContext context) {
    final s = S.of(context);
    final visible = _items.length > 10 ? _items.sublist(0, 10) : _items;
    return Scaffold(
      backgroundColor: th.AppColors.bg,
      appBar: AppBar(
        backgroundColor: th.AppColors.bg,
        title: Text(s.pendingTitle),
      ),
      body: _items.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.history, size: 40, color: th.AppColors.textHint),
                const SizedBox(height: 12),
                Text(s.pendingEmpty, style: TextStyle(color: th.AppColors.textHint)),
              ]),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(s.pendingHint, style: TextStyle(color: th.AppColors.textHint, fontSize: 12, height: 1.5)),
                const SizedBox(height: 12),
                ...visible.map((it) => _item(it, s)),
              ],
            ),
      bottomNavigationBar: _sel.isEmpty ? null : _bar(s),
    );
  }

  /// 卡片：所有文字都放进 Expanded 的 Column 里。
  /// 右侧绝不放无宽度约束的 Text——否则长语言（日语/德语）会把左侧挤到只剩一个字宽，
  /// 日期被压成竖排并与提示文字重叠。
  Widget _item(PendingHistory it, S s) {
    final sel = _sel.contains(it.key);
    final hasImp = (it.impedance1 ?? 0) > 0;
    final h = widget.active.heightCm / 100;
    final bmi = h > 0 ? it.weightKg / (h * h) : null;
    final bf = hasImp
        ? BodyCompositionCalc.estimate(
            weightKg: it.weightKg,
            heightCm: widget.active.heightCm,
            age: widget.active.age,
            sex: widget.active.sex,
            impedances: [it.impedance1 ?? 0, it.impedance2 ?? 0],
            algo: _bfAlgo,
          )?.bodyFatPercent
        : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => sel ? _sel.remove(it.key) : _sel.add(it.key)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sel
              ? th.AppColors.soft(th.AppColors.primarySoft, th.AppColors.primarySoftD)
              : th.AppColors.surface,
          borderRadius: BorderRadius.circular(th.AppRadius.md),
          border: Border.all(color: sel ? th.AppColors.primary : th.AppColors.border),
          boxShadow: th.AppShadows.soft,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20, height: 20,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: sel ? th.AppColors.primary : Colors.transparent,
                border: Border.all(color: sel ? th.AppColors.primary : th.AppColors.borderStrong),
              ),
              child: sel ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _unit.fmt(it.weightKg),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: th.AppColors.text),
                      ),
                      if (bmi != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          'BMI ' + bmi.toStringAsFixed(1),
                          style: TextStyle(fontSize: 11, color: th.AppColors.textSub, fontWeight: FontWeight.w600),
                        ),
                      ],
                      if (it.lowWeight) ...[
                        const SizedBox(width: 8),
                        Flexible(child: _tag(s.lowWeightTag)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    it.timeStr,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: th.AppColors.textHint),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasImp
                        ? (it.impedance1 ?? 0).toStringAsFixed(0)
                                + ' / '
                                + (it.impedance2 ?? 0).toStringAsFixed(0)
                                + ' Ω'
                        : s.impedanceFailed,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      fontFamily: hasImp ? 'monospace' : null,
                      color: hasImp ? th.AppColors.primary : th.AppColors.textHint,
                    ),
                  ),
                  if (bf != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      s.bfEstimate + ' ' + bf.toStringAsFixed(1) + '%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: th.AppColors.warn),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: th.AppColors.soft(th.AppColors.warnSoft, th.AppColors.warnSoftD),
      borderRadius: BorderRadius.circular(th.AppRadius.pill),
    ),
    child: Text(
      t,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: th.AppColors.warn),
    ),
  );

  Widget _bar(S s) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(
      color: th.AppColors.surface,
      border: Border(top: BorderSide(color: th.AppColors.border)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                s.assignTo + ' (' + _sel.length.toString() + ')',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: th.AppColors.textSub, fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () async {
                await removePending(_sel);
                _sel.clear();
                await _load();
              },
              child: Text(
                s.discardSelected,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: th.AppColors.danger, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 60,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: widget.profiles.map((p) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _assign(p),
              child: Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                constraints: const BoxConstraints(maxWidth: 170),
                decoration: BoxDecoration(
                  color: th.AppColors.soft(th.AppColors.primarySoft, th.AppColors.primarySoftD),
                  borderRadius: BorderRadius.circular(th.AppRadius.md),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: th.AppColors.soft(th.AppColors.primaryDeep, th.AppColors.primary),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      (p.isMale ? s.sexMale : s.sexFemale) + ' · ' + p.heightCm.toStringAsFixed(0) + 'cm',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: th.AppColors.textHint, fontSize: 10),
                    ),
                  ],
                ),
              ),
            )).toList(),
          ),
        ),
      ],
    ),
  );

  Future<void> _assign(UserProfile p) async {
    final picked = _items.where((i) => _sel.contains(i.key)).toList();
    double? newestKg;
    String newestTime = '';
    for (final it in picked) {
      if (it.timeStr.compareTo(newestTime) >= 0 && it.weightKg > 20) {
        newestTime = it.timeStr;
        newestKg = it.weightKg;
      }
    }
    for (final it in picked) {
      final hasImp = (it.impedance1 ?? 0) > 0;
      final comp = hasImp
          ? BodyCompositionCalc.estimate(
              weightKg: it.weightKg,
              heightCm: p.heightCm,
              age: p.age,
              sex: p.sex,
              impedances: [it.impedance1 ?? 0, it.impedance2 ?? 0],
              algo: _bfAlgo,
            )
          : null;
      await appendRecord(MeasurementRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        time: it.timeStr,
        unit: p.name,
        weightKg: it.weightKg,
        impedance1: it.impedance1,
        impedance2: it.impedance2,
        adcs: hasImp ? [it.impedance1 ?? 0, it.impedance2 ?? 0] : null,
        electrodeOn: hasImp,
        bodyComposition: comp,
        profile: p,
      ));
    }
    await removePending(_sel);
    _sel.clear();
    if (newestKg != null && (p.weightKg == null || (p.weightKg! - newestKg).abs() >= 0.001)) {
      await upsertProfile(UserProfile(
        name: p.name, sex: p.sex, age: p.age,
        heightCm: p.heightCm, weightKg: newestKg,
      ));
    }
    await _load();
    widget.onChanged();
  }
}