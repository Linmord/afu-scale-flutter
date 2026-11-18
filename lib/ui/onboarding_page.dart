import 'package:flutter/material.dart';
import '../core/models.dart';
import '../data/store.dart';
import 'package:afu_scale/i18n/l10n.dart';
import 'theme.dart' as th;
import 'device_scanner_page.dart';

/// 首次安装引导页（两步）：1. 创建成员资料 → 2. 搜索并绑定体脂秤 → 进入数据主页。
class OnboardingPage extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingPage({super.key, required this.onDone});
  @override State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _step = 0;
  final _name = TextEditingController();
  String _sex = 'female';
  final _age = TextEditingController(text: '24');
  final _height = TextEditingController(text: '163');
  final _weight = TextEditingController(text: '55.75');
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose(); _age.dispose(); _height.dispose(); _weight.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty
      && (int.tryParse(_age.text) ?? 0) > 0
      && (double.tryParse(_height.text) ?? 0) > 50;

  Future<void> _saveProfileAndNext() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    final profile = UserProfile(
      name: _name.text.trim(),
      sex: _sex,
      age: int.tryParse(_age.text) ?? 24,
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
    return Scaffold(
      backgroundColor: th.AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
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
              _stepIndicator(s),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: _step == 0 ? _buildProfileStep(s) : _buildBindStep(s),
              ),
            ],
          ),
        ),
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
        _label(s.ageLabel),
        _field(_age, '24', true, 3),
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