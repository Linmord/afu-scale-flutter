import 'package:flutter/material.dart';
import '../core/models.dart';
import '../data/store.dart';
import 'package:afu_scale/i18n/l10n.dart';
import 'theme.dart' as th;
import 'widgets/birthday_field.dart';
import 'device_scanner_page.dart';

/// 首次安装引导页（两步）：1. 创建成员资料 → 2. 搜索并绑定体脂秤 → 进入数据主页。
class OnboardingPage extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingPage({super.key, required this.onDone});
  @override State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  int _step = 0;
  final _name = TextEditingController();
  String _sex = 'female';
  String _birthday = ''; // 生日（yyyy-MM-dd），由选择器写入
  final _height = TextEditingController(text: '163');
  final _weight = TextEditingController(text: '55.75');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _name.dispose(); _height.dispose(); _weight.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty
      && (UserProfile.ageFromBirthday(_birthday) ?? 0) > 0
      && (double.tryParse(_height.text) ?? 0) > 50;

  Future<void> _saveProfileAndNext() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    final profile = UserProfile(
      name: _name.text.trim(),
      sex: _sex,
      age: UserProfile.ageFromBirthday(_birthday) ?? 24,
      heightCm: double.tryParse(_height.text) ?? 163,
      weightKg: double.tryParse(_weight.text),
    );
    await saveProfiles([profile]);
    await setActive(profile.name);
    if (mounted) {
      setState(() { _saving = false; _step = 1; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final eased = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);
    return Scaffold(
      backgroundColor: th.AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: FadeTransition(
            opacity: eased,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.045), end: Offset.zero).animate(eased),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Center(
                child: Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3FC0A4), Color(0xFF4EA8FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: th.AppShadows.card,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.monitor_weight_rounded, color: Colors.white, size: 30),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text('AFU', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: th.AppColors.text, letterSpacing: 3)),
              ),
              Center(
                child: Text(s.appTagline, style: TextStyle(color: th.AppColors.textHint, fontSize: 12)),
              ),
              const SizedBox(height: 18),
              _langCard(s),
              const SizedBox(height: 16),
              _stepIndicator(s),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 340),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
                        .animate(anim),
                    child: child,
                  ),
                ),
                child: _step == 0 ? _buildProfileStep(s) : _buildBindStep(s),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 语言选择卡：首次启动即高亮呈现，双列大按钮，明确是第一步。
  Widget _langCard(S s) {
    final loc = AppLocale.of(context);
    final current = loc.isSystem ? s.followSystem : S(loc.resolvedCode).nativeName;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: th.AppColors.surface,
        borderRadius: BorderRadius.circular(th.AppRadius.lg),
        border: Border.all(color: th.AppColors.primary.withValues(alpha: 0.35), width: 1.2),
        boxShadow: th.AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: th.AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.translate_rounded, size: 15, color: th.AppColors.primary),
              ),
              const SizedBox(width: 9),
              Text(
                s.language,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: th.AppColors.text),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  current,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, color: th.AppColors.primaryDeep, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            s.languageHint,
            style: TextStyle(fontSize: 10.5, height: 1.5, color: th.AppColors.textHint),
          ),
          const SizedBox(height: 11),
          LayoutBuilder(
            builder: (ctx, c) {
              final half = (c.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: supportedLangCodes.map((code) {
                  final active = !loc.isSystem && loc.resolvedCode == code;
                  return SizedBox(
                    width: half,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => loc.setLang(code),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: active ? th.AppColors.primary : th.AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(th.AppRadius.sm),
                          border: Border.all(
                            color: active ? th.AppColors.primary : th.AppColors.border,
                            width: active ? 1.4 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (active) ...[
                              const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                              const SizedBox(width: 5),
                            ],
                            Flexible(
                              child: Text(
                                S(code).nativeName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                                  color: active ? Colors.white : th.AppColors.textSub,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _stepIndicator(S s) => Row(
    children: [
      Expanded(child: _stepPill(1, s.profileTitle, _step == 0, _step > 0)),
      const SizedBox(width: 8),
      Expanded(child: _stepPill(2, s.bindScaleTitle, _step == 1, false)),
    ],
  );

  Widget _stepPill(int num, String label, bool current, bool done) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: current ? th.AppColors.primarySoft : th.AppColors.surface,
      borderRadius: BorderRadius.circular(th.AppRadius.pill),
      border: Border.all(color: current || done ? th.AppColors.primary : th.AppColors.border),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: done || current ? th.AppColors.primary : th.AppColors.surfaceAlt,
          child: done
              ? const Icon(Icons.check, size: 12, color: Colors.white)
              : Text(num.toString(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: current ? Colors.white : th.AppColors.textHint)),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: current ? FontWeight.w700 : FontWeight.w500,
              color: current ? th.AppColors.primaryDeep : th.AppColors.textHint,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildProfileStep(S s) => Container(
    key: const ValueKey('step_profile'),
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
        Text(s.profileTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: th.AppColors.text)),
        const SizedBox(height: 4),
        Text(s.profileHint, style: TextStyle(color: th.AppColors.textHint, fontSize: 12, height: 1.5)),
        _label(s.nameLabel),
        _field(_name, s.namePlaceholder, false, 16),
        _label(s.sexLabel),
        Row(
          children: [
            Expanded(child: _sexChip('male', s.sexMale)),
            const SizedBox(width: 10),
            Expanded(child: _sexChip('female', s.sexFemale)),
          ],
        ),
        _label(s.birthdayLabel),
        BirthdayField(
          onChanged: (v) => setState(() => _birthday = v),
        ),
        _label(s.heightLabel),
        _field(_height, '163', true, 6),
        _label(s.weightLabel + ' ' + s.optional),
        _field(_weight, '55.75', true, 6),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _valid && !_saving ? _saveProfileAndNext : null,
          child: Text(_saving ? s.saving : s.nextStep),
        ),
        if (!_valid)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(child: Text(s.profileRequired, style: TextStyle(color: th.AppColors.warn, fontSize: 12))),
          ),
        // ── 计算模型偏差提示（首次引导即告知）──
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 13, color: th.AppColors.warn),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  s.calcModelHint,
                  style: TextStyle(fontSize: 10.5, height: 1.6, color: th.AppColors.textHint),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildBindStep(S s) => Column(
    key: const ValueKey('step_bind'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DeviceScanPanel(
        autoStart: true,
        onSelected: (_) => widget.onDone(),
      ),
      const SizedBox(height: 14),
      TextButton(
        onPressed: widget.onDone,
        child: Text(s.skipForNow, style: TextStyle(color: th.AppColors.textSub, fontSize: 13)),
      ),
    ],
  );

  Widget _sexChip(String value, String label) {
    final active = _sex == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _sex = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(t, style: TextStyle(fontSize: 12, color: th.AppColors.textHint, fontWeight: FontWeight.w600)),
  );

  Widget _field(TextEditingController c, String hint, bool numeric, int max) => TextField(
    controller: c,
    keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    maxLength: max,
    onChanged: (_) => setState(() {}),
    style: TextStyle(color: th.AppColors.text, fontSize: 15),
    decoration: InputDecoration(hintText: hint, counterText: ''),
  );
}