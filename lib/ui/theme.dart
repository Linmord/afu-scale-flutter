import 'package:flutter/material.dart';

/// 双主题色板：浅色（健康）+ 深色（夜间）。
/// 所有字段都是 getter，按 [AppColors.isDark] 返回当前主题色，
/// 页面里写 `th.AppColors.text` 即可自动跟随主题切换，无需改调用点。
class AppColors {
  static bool isDark = false;

  // ── 浅色 ──
  static const _bgL = Color(0xFFF7F9FB);
  static const _bgDeepL = Color(0xFFEDF2F6);
  static const _surfaceL = Color(0xFFFFFFFF);
  static const _surfaceAltL = Color(0xFFEEF3F7);
  static const _elevatedL = Color(0xFFFFFFFF);
  static const _textL = Color(0xFF1B2733);
  static const _textSubL = Color(0xFF66798C);
  static const _textHintL = Color(0xFF9BABBB);
  static const _borderL = Color(0xFFE6EDF3);
  static const _borderStrongL = Color(0xFFD2DEE9);

  // ── 深色 ──
  static const _bgD = Color(0xFF0E1420);
  static const _bgDeepD = Color(0xFF121A28);
  static const _surfaceD = Color(0xFF18212F);
  static const _surfaceAltD = Color(0xFF1F2A3A);
  static const _elevatedD = Color(0xFF243043);
  static const _textD = Color(0xFFF2F6FA);
  static const _textSubD = Color(0xFF9DAEBF);
  static const _textHintD = Color(0xFF6B7C8F);
  static const _borderD = Color(0xFF25303F);
  static const _borderStrongD = Color(0xFF344357);

  static Color get bg => isDark ? _bgD : _bgL;
  static Color get bgDeep => isDark ? _bgDeepD : _bgDeepL;
  static Color get surface => isDark ? _surfaceD : _surfaceL;
  static Color get surfaceAlt => isDark ? _surfaceAltD : _surfaceAltL;
  static Color get elevated => isDark ? _elevatedD : _elevatedL;
  static Color get text => isDark ? _textD : _textL;
  static Color get textSub => isDark ? _textSubD : _textSubL;
  static Color get textHint => isDark ? _textHintD : _textHintL;
  static Color get border => isDark ? _borderD : _borderL;
  static Color get borderStrong => isDark ? _borderStrongD : _borderStrongL;

  // 品牌色两套都亮一点，深色下更透气
  static const primary = Color(0xFF3FC0A4);
  static const primaryDeep = Color(0xFF2A9D83);
  static const primarySoft = Color(0xFFDCF4EE);
  static const primarySoftD = Color(0xFF17352F);
  static const accent = Color(0xFF4EA8FF);
  static const accentSoft = Color(0xFFE2F0FF);
  static const accentSoftD = Color(0xFF132A42);
  static const warn = Color(0xFFF5A623);
  static const warnSoft = Color(0xFFFFF3DF);
  static const warnSoftD = Color(0xFF3A2C12);
  static const danger = Color(0xFFF05A67);
  static const dangerSoft = Color(0xFFFFE8EA);
  static const dangerSoftD = Color(0xFF3A1A1F);

  // 指标色（两种模式下都保持可辨识）
  static const fat = Color(0xFFFF9F6B);
  static const fatSoft = Color(0xFFFFEFE5);
  static const fatSoftD = Color(0xFF3A2519);
  static const muscle = Color(0xFF38C7BE);
  static const muscleSoft = Color(0xFFDFF6F4);
  static const muscleSoftD = Color(0xFF122E2C);
  static const water = Color(0xFF5B9BFF);
  static const waterSoft = Color(0xFFE4EEFF);
  static const waterSoftD = Color(0xFF16263F);
  static const protein = Color(0xFFA78BFA);
  static const proteinSoft = Color(0xFFF0EBFE);
  static const proteinSoftD = Color(0xFF241E3B);
  static const bone = Color(0xFFE9B23D);
  static const boneSoft = Color(0xFFFCF2DC);
  static const boneSoftD = Color(0xFF362C13);
  static const skeletal = Color(0xFF34D399);
  static const skeletalSoft = Color(0xFFDFF7EC);
  static const skeletalSoftD = Color(0xFF122E22);

  /// 柔和背景按当前主题取色。
  static Color soft(Color light, Color dark) => isDark ? dark : light;
}

class AppRadius {
  static const sm = 12.0;
  static const md = 18.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const pill = 999.0;
}

class AppSpacing {
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 22.0;
  static const xl = 30.0;
}

class AppShadows {
  static List<BoxShadow> get soft => AppColors.isDark
      ? const [BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 6))]
      : const [BoxShadow(color: Color(0x0F1B2733), blurRadius: 20, offset: Offset(0, 6))];
  static List<BoxShadow> get card => AppColors.isDark
      ? const [BoxShadow(color: Color(0x44000000), blurRadius: 28, offset: Offset(0, 10))]
      : const [BoxShadow(color: Color(0x141B2733), blurRadius: 28, offset: Offset(0, 10))];
  static List<BoxShadow> get float => AppColors.isDark
      ? const [BoxShadow(color: Color(0x55000000), blurRadius: 40, offset: Offset(0, 16))]
      : const [BoxShadow(color: Color(0x1F1B2733), blurRadius: 40, offset: Offset(0, 16))];
}

/// 保持旧 API 名以便现有页面继续工作。
class AppTheme {
  static Color get bg => AppColors.bg;
  static Color get surface => AppColors.surface;
  static Color get surfaceAlt => AppColors.surfaceAlt;
  static Color get elevated => AppColors.elevated;
  static const primary = AppColors.primary;
  static const primaryDeep = AppColors.primaryDeep;
  static const primarySoft = AppColors.primarySoft;
  static const accent = AppColors.accent;
  static const accentSoft = AppColors.accentSoft;
  static const warn = AppColors.warn;
  static const warnSoft = AppColors.warnSoft;
  static const danger = AppColors.danger;
  static Color get text => AppColors.text;
  static Color get textSub => AppColors.textSub;
  static Color get textHint => AppColors.textHint;
  static Color get border => AppColors.border;
  static Color get borderStrong => AppColors.borderStrong;

  static ThemeData get dark => _build(true);
  static ThemeData get light => _build(false);

  static ThemeData _build(bool dark) {
    AppColors.isDark = dark;
    final brightness = dark ? Brightness.dark : Brightness.light;
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: brightness,
        surface: AppColors.surface,
      ),
    );
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.text),
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        hintStyle: TextStyle(color: AppColors.textHint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: BorderSide(color: AppColors.borderStrong),
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.text,
        contentTextStyle: TextStyle(color: AppColors.surface, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      dividerTheme: DividerThemeData(color: AppColors.border, thickness: 1),
    );
  }
}