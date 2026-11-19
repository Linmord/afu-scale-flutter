import 'package:flutter/material.dart';
import '../core/models.dart';
import '../data/store.dart';
import 'package:afu_scale/i18n/l10n.dart';
import 'theme.dart' as th;
import 'widgets/app_sheet.dart';
import 'widgets/birthday_field.dart';

/// 成员新增/编辑全屏表单页（避免底部弹窗被输入法遮挡）。返回 true 表示已保存。
Future<bool> showProfileEditor(BuildContext ctx, {UserProfile? existing}) async {
  final result = await Navigator.push<bool>(
    ctx,
    MaterialPageRoute<bool>(
      builder: (_) => _ProfileEditorPage(existing: existing),
    ),
  );
  return result == true;
}

class _ProfileEditorPage extends StatefulWidget {
  final UserProfile? existing;
  const _ProfileEditorPage({this.existing});
  @override State<_ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<_ProfileEditorPage> {
  late final TextEditingController _name;
  String _birthday = ''; // 由选择器写入；空=沿用原年龄
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late String _sex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _height = TextEditingController(text: (e?.heightCm ?? 163).toString());
    _weight = TextEditingController(text: e?.weightKg?.toString() ?? '');
    _sex = e?.sex ?? 'female';
  }

  @override
  void dispose() {
    _name.dispose(); _height.dispose(); _weight.dispose();
    super.dispose();
  }


  /// 生效年龄：填了生日用换算值，留空沿用原年龄（编辑时），新增留空则无效。
  int? get _effectiveAge =>
      UserProfile.ageFromBirthday(_birthday) ?? widget.existing?.age;

  bool get _valid => _name.text.trim().isNotEmpty
      && (_effectiveAge ?? 0) > 0
      && (double.tryParse(_height.text) ?? 0) > 50;

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    final profile = UserProfile(
      name: _name.text.trim(),
      sex: _sex,
      age: _effectiveAge ?? 24,
      heightCm: double.tryParse(_height.text) ?? 163,
      weightKg: double.tryParse(_weight.text),
    );
    final old = widget.existing;
    if (old != null && old.name != profile.name) {
      // 关键：改名必须同步历史记录的归属，否则旧记录仍挂在旧名字下，
      // 数据页按新名字过滤会一条都查不到（表现为"改名后数据消失"）。
      await renameRecordOwner(old.name, profile.name);
      await removeProfile(old.name);
    }
    await upsertProfile(profile);
    // 档案里的性别/年龄/身高会改变体脂率等指标 → 历史记录必须按新档案重算，
    // 否则改了性别数据页体脂率还是旧的（BMI 不含性别，不受影响）。
    await recalcRecordsForProfile(profile);
    final active = await getActiveProfile();
    if (active == null || old?.name == active) {
      await setActive(profile.name);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: th.AppColors.bg,
      appBar: AppBar(
        backgroundColor: th.AppColors.bg,
        title: Text(widget.existing == null ? s.addProfile : s.editProfile),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          _label(s.nameLabel),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: th.AppColors.text),
            decoration: InputDecoration(hintText: s.namePlaceholder),
          ),
          _label(s.sexLabel),
          Row(children: [
            Expanded(child: _sexBtn(s.sexMale, 'male')),
            const SizedBox(width: 10),
            Expanded(child: _sexBtn(s.sexFemale, 'female')),
          ]),
          _label(s.birthdayLabel),
          BirthdayField(
            onChanged: (v) => setState(() => _birthday = v),
          ),
          if (widget.existing != null && _birthday.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text(
                s.birthdayKeepHint + ' · ' + s.ageAutoCalc(widget.existing!.age),
                style: TextStyle(fontSize: 11.5, color: th.AppColors.textHint),
              ),
            ),
          _label(s.heightLabel),
          TextField(
            controller: _height,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: th.AppColors.text),
          ),
          _label(s.weightLabel + ' (' + s.optional + ')'),
          TextField(
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: th.AppColors.text),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: FilledButton(
            onPressed: _valid && !_saving ? _save : null,
            child: Text(_saving ? s.saving : s.save),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: th.AppColors.textHint)),
  );

  Widget _sexBtn(String label, String value) {
    final active = _sex == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _sex = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: active ? th.AppColors.primarySoft : th.AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(th.AppRadius.sm),
          border: Border.all(color: active ? th.AppColors.primary : th.AppColors.border, width: active ? 1.5 : 1),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? th.AppColors.primaryDeep : th.AppColors.textSub,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// 成员选择/管理面板：选择、编辑、删除、新增。
Future<void> showProfileManager(
  BuildContext ctx, {
  required List<UserProfile> profiles,
  required String? activeName,
  required Future<void> Function() onChanged,
}) async {
  await showAppSheet(
    ctx,
    title: S.of(ctx).profilesTitle,
    children: [
      _ManagerBody(profiles: profiles, activeName: activeName, onChanged: onChanged),
    ],
  );
}

class _ManagerBody extends StatefulWidget {
  final List<UserProfile> profiles;
  final String? activeName;
  final Future<void> Function() onChanged;
  const _ManagerBody({required this.profiles, required this.activeName, required this.onChanged});
  @override State<_ManagerBody> createState() => _ManagerBodyState();
}

class _ManagerBodyState extends State<_ManagerBody> {
  late List<UserProfile> _list;
  String? _activeName;

  @override
  void initState() {
    super.initState();
    _list = List.of(widget.profiles);
    _activeName = widget.activeName;
  }

  Future<void> _reload() async {
    _list = await getProfiles();
    _activeName = await getActiveProfile();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              final ok = await showProfileEditor(context);
              if (ok) { await _reload(); await widget.onChanged(); }
            },
            icon: Icon(Icons.add_rounded, size: 18, color: th.AppColors.primary),
            label: Text(s.addProfile, style: TextStyle(color: th.AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ),
        if (_list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(s.profilesHint, textAlign: TextAlign.center, style: TextStyle(color: th.AppColors.textHint, fontSize: 12)),
          ),
        ..._list.map((p) {
          final isCur = p.name == _activeName;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isCur ? th.AppColors.primarySoft.withOpacity(th.AppColors.isDark ? 0.25 : 0.7) : th.AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(th.AppRadius.md),
              border: Border.all(color: isCur ? th.AppColors.primary : th.AppColors.border),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: p.isMale ? th.AppColors.accentSoft : th.AppColors.fatSoft,
                child: Text(
                  p.name.substring(0, 1),
                  style: TextStyle(color: p.isMale ? th.AppColors.accent : th.AppColors.fat, fontWeight: FontWeight.w800),
                ),
              ),
              title: Text(
                p.name,
                style: TextStyle(
                  color: th.AppColors.text,
                  fontWeight: isCur ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              subtitle: Text(
                (p.isMale ? s.sexMale : s.sexFemale) + ' · ' + p.age.toString() + ' · ' + p.heightCm.toStringAsFixed(1) + 'cm' + (p.weightKg != null ? ' · ' + p.weightKg!.toStringAsFixed(1) + 'kg' : ''),
                style: TextStyle(color: th.AppColors.textHint, fontSize: 11),
              ),
              onTap: () async {
                await setActive(p.name);
                await widget.onChanged();
                if (mounted) Navigator.pop(context);
              },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit_outlined, size: 18, color: th.AppColors.textSub),
                    onPressed: () async {
                      final ok = await showProfileEditor(context, existing: p);
                      if (ok) { await _reload(); await widget.onChanged(); }
                    },
                  ),
                  if (_list.length > 1)
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 18, color: th.AppColors.danger),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (dctx) => AlertDialog(
                            backgroundColor: th.AppColors.surface,
                            title: Text(s.delete + ' ' + p.name, style: TextStyle(color: th.AppColors.text)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(s.cancel)),
                              TextButton(onPressed: () => Navigator.pop(dctx, true), child: Text(s.delete, style: TextStyle(color: th.AppColors.danger))),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await removeProfile(p.name);
                          final active = await getActiveProfile();
                          if (active == p.name || active == null) {
                            final rest = await getProfiles();
                            if (rest.isNotEmpty) await setActive(rest.first.name);
                          }
                          await _reload();
                          await widget.onChanged();
                        }
                      },
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}