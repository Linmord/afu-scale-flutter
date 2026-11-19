import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/models.dart';
import 'data/store.dart';
import 'data/debug_log.dart';
import 'sync/sync_client.dart' as sync;
import 'ble/comm_log.dart';
import 'package:afu_scale/i18n/l10n.dart';
import 'package:afu_scale/ui/theme.dart' as th;
import 'package:afu_scale/ui/measure_page.dart';
import 'package:afu_scale/ui/data_page.dart';
import 'package:afu_scale/ui/settings_page.dart';
import 'package:afu_scale/ui/onboarding_page.dart';
import 'package:afu_scale/ui/profile_editor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final locale = await AppLocale.instance.init();
  runApp(AfuApp(locale: locale));
}

class AfuApp extends StatefulWidget {
  final AppLocale locale;
  const AfuApp({super.key, required this.locale});
  @override
  State<AfuApp> createState() => _AfuAppState();
}

class _AfuAppState extends State<AfuApp> {
  int _tab = 0; // 0=数据 1=设置
  bool _measuring = false;
  final GlobalKey<MeasurePageState> _measureKey =
      GlobalKey<MeasurePageState>(); // 测量全屏页
  bool _profileReady = false;
  String _themeMode = 'system';
  bool _dark = false;
  List<UserProfile> _profiles = [];
  UserProfile? _active;

  @override
  void initState() {
    super.initState();
    _load();
    _autoPushOnStart();
  }

  /// App 启动时把所有未同步记录（syncedAt 为空）推到电脑。
  /// 静默后台：无地址 / 无网络 / 服务端不可达都不提示、不抛错、不阻塞启动。
  /// 补上「测量时推送失败、下次打开补推」的漏。成功才标记 syncedAt。
  Future<void> _autoPushOnStart() async {
    try {
      final url = await getSyncUrl();
      if (url.isEmpty) return;
      final all = await getRecords();
      final unsynced = all.where((r) => r.syncedAt == null || r.syncedAt!.isEmpty).toList();
      if (unsynced.isEmpty) return;
      final received = await sync.pushRecords(unsynced, url);
      if (received > 0) {
        await markSynced(unsynced.map((r) => r.id).toSet());
      }
    } catch (_) {
      // 启动自动推送失败不影响 App 使用，忽略。
    }
  }

  Future<void> _load() async {
    final profiles = await getProfiles();
    final activeName = await getActiveProfile();
    final active = profiles.where((p) => p.name == activeName).firstOrNull ??
        (profiles.isNotEmpty ? profiles.first : null);
    final mode = await getThemeMode();
    final sysDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    final dark = mode == 'dark' || (mode == 'system' && sysDark);
    th.AppColors.isDark = dark;
    if (mounted) {
      setState(() {
        _profiles = profiles;
        _active = active;
        _profileReady = true;
        _themeMode = mode;
        _dark = dark;
      });
    }
  }

  Future<void> _setTheme(String mode) async {
    await setThemeMode(mode);
    final sysDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    final dark = mode == 'dark' || (mode == 'system' && sysDark);
    th.AppColors.isDark = dark;
    setState(() {
      _themeMode = mode;
      _dark = dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.locale,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: widget.locale.locale,
        supportedLocales: AppLocale.supported,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: _dark ? th.AppTheme.dark : th.AppTheme.light,
        home: Builder(
          builder: (rootCtx) => !_profileReady
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : (_active == null
                  ? OnboardingPage(onDone: _load)
                  : _buildMain(rootCtx)),
        ),
      ),
    );
  }

  Widget _buildMain(BuildContext ctx) {
    return PopScope(
      // 测量页打开时拦截系统返回键/侧滑手势：关闭测量页而不是退出 App
      canPop: !_measuring,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_measuring) return;
        final ok = await _measureKey.currentState?.confirmClose() ?? true;
        if (ok && mounted) _setMeasuring(false);
      },
      child: Scaffold(
        backgroundColor: th.AppColors.bg,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _topBar(ctx),
                  Expanded(
                    // IndexedStack 保持两个页面的 State：切到设置再回数据页不丢已加载的数据
                    child: IndexedStack(
                      index: _tab,
                      children: [
                        DataPage(
                          key: ValueKey('data_' + _active!.name),
                          active: _active!,
                        ),
                        SettingsPage(
                          key: ValueKey('settings_' + _active!.name),
                          active: _active!,
                          profiles: _profiles,
                          onChanged: _load,
                          themeMode: _themeMode,
                          onThemeMode: _setTheme,
                        ),
                      ],
                    ),
                  ),
                  _bottomNav(ctx),
                ],
              ),
              // 测量页从底部滑入，盖住整个主页
              if (_measuring)
                AnimatedSlide(
                  offset: _measuring ? Offset.zero : const Offset(0, 1),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: MeasurePage(
                    key: _measureKey,
                    active: _active!,
                    profiles: _profiles,
                    onClose: () => _setMeasuring(false),
                    onProfilesChanged: _load,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _setMeasuring(bool v) => setState(() => _measuring = v);

  /// 新顶栏：左边用户胶囊（选身份），右边开始称量按钮。
  Widget _topBar(BuildContext ctx) {
    final s = S.of(ctx);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          // 左边：身份胶囊
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showUserMenu(ctx),
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
              decoration: BoxDecoration(
                color: th.AppColors.surface,
                borderRadius: BorderRadius.circular(th.AppRadius.pill),
                border: Border.all(color: th.AppColors.border),
                boxShadow: th.AppShadows.soft,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: th.AppColors.primarySoft,
                    child: Text(
                      _active!.name.substring(0, 1),
                      style: TextStyle(
                        color: th.AppColors.primaryDeep,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 88),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _active!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: th.AppColors.text,
                          ),
                        ),
                        Text(
                          (_active!.isMale ? s.sexMale : s.sexFemale) +
                              ' · ' +
                              _active!.age.toString() +
                              s.ageSuffix,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 9, color: th.AppColors.textHint),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: th.AppColors.textHint,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // 右边：开始称量
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _setMeasuring(true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3FC0A4), Color(0xFF2A9D83)],
                ),
                borderRadius: BorderRadius.circular(th.AppRadius.pill),
                boxShadow: [
                  BoxShadow(
                    color: th.AppColors.primary.withOpacity(0.32),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.monitor_weight_rounded,
                      size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    s.startWeighing,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
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

  Future<void> _showUserMenu(BuildContext ctx) async {
    try {
      await showProfileManager(
        ctx,
        profiles: _profiles,
        activeName: _active?.name,
        onChanged: _load,
      );
    } catch (e) {
      DebugLog.instance.log('成员管理异常: ' + e.toString());
      CommLog.instance.rx([], note: 'UI异常: 成员管理 ' + e.toString());
    }
  }

  /// 底部只剩两个 tab：数据 / 设置
  Widget _bottomNav(BuildContext ctx) {
    final s = S.of(ctx);
    final icons = [Icons.insights_rounded, Icons.tune_rounded];
    final labels = [s.tabData, s.tabSettings];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      decoration: BoxDecoration(
        color: th.AppColors.surface,
        border: Border(top: BorderSide(color: th.AppColors.border)),
      ),
      child: Row(
        children: List.generate(icons.length, (i) {
          final active = _tab == i;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _tab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                decoration: BoxDecoration(
                  color: active ? th.AppColors.primarySoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(th.AppRadius.md),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icons[i],
                      size: 21,
                      color: active
                          ? th.AppColors.primaryDeep
                          : th.AppColors.textHint,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      labels[i],
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                        color: active
                            ? th.AppColors.primaryDeep
                            : th.AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
