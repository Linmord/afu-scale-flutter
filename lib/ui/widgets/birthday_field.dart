import 'package:flutter/material.dart';
import '../../core/models.dart';
import 'package:afu_scale/i18n/l10n.dart';
import '../theme.dart' as th;

/// 生日选择字段：点击弹出日历，不允许手打。
/// 值以 yyyy-MM-dd 字符串回传（空串表示未选），下方实时显示换算出的年龄。
class BirthdayField extends StatefulWidget {
  final void Function(String birthday) onChanged;
  final String? initial;
  const BirthdayField({super.key, required this.onChanged, this.initial});

  @override
  State<BirthdayField> createState() => _BirthdayFieldState();
}

class _BirthdayFieldState extends State<BirthdayField> {
  String _value = '';

  @override
  void initState() {
    super.initState();
    _value = widget.initial ?? '';
  }

  Future<void> _pick() async {
    final s = S.of(context);
    final now = DateTime.now();
    final parsed = DateTime.tryParse(_value);
    final initial = (parsed != null && !parsed.isAfter(now))
        ? parsed
        : DateTime(now.year - 24, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
      helpText: s.birthdayLabel,
      cancelText: s.cancel,
      confirmText: s.save,
      builder: (ctx, child) {
        final dark = th.AppColors.isDark;
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: th.AppColors.primary,
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            dialogBackgroundColor: th.AppColors.surface,
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: th.AppColors.primary),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null) return;
    final v = picked.year.toString().padLeft(4, '0') +
        '-' + picked.month.toString().padLeft(2, '0') +
        '-' + picked.day.toString().padLeft(2, '0');
    setState(() => _value = v);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final age = UserProfile.ageFromBirthday(_value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _pick,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: th.AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(th.AppRadius.sm),
              border: Border.all(color: th.AppColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.cake_outlined, size: 17, color: th.AppColors.textHint),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _value.isEmpty ? s.birthdayHint : _value,
                    style: TextStyle(
                      fontSize: 15,
                      color: _value.isEmpty ? th.AppColors.textHint : th.AppColors.text,
                    ),
                  ),
                ),
                Icon(Icons.calendar_today_rounded, size: 15, color: th.AppColors.textSub),
              ],
            ),
          ),
        ),
        if (age != null)
          Padding(
            padding: const EdgeInsets.only(top: 7, left: 2),
            child: Text(
              s.ageAutoCalc(age),
              style: TextStyle(fontSize: 11.5, color: th.AppColors.textHint),
            ),
          ),
      ],
    );
  }
}
