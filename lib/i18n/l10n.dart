// lib/i18n/l10n.dart
// 5 语言 i18n —— 从 RN 版 src/i18n/dict.ts 移植（201 键）。
// 语言：zh-Hans / zh-Hant / ja / de / en，fallback = ja。
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 支持的语言代码（顺序即设置页显示顺序）。
const List<String> supportedLangCodes = [
  'zh-Hans',
  'zh-Hant',
  'ja',
  'de',
  'en',
];

/// 回退语言。
const String fallbackLangCode = 'ja';

/// 把系统语言标签归一到我们支持的 5 种；不支持则返回 null。
String? normalizeLang(String? languageCode, [String? countryCode]) {
  final tag = '${languageCode ?? ''}-${countryCode ?? ''}';
  final t = tag.toLowerCase();
  if (t.startsWith('zh')) {
    if (RegExp(r'hant|tw|hk|mo').hasMatch(t)) return 'zh-Hant';
    return 'zh-Hans';
  }
  if (t.startsWith('ja')) return 'ja';
  if (t.startsWith('de')) return 'de';
  if (t.startsWith('en')) return 'en';
  return null;
}

/// 读取设备首选语言；不在支持列表则返回日语。
String detectDeviceLang() {
  try {
    final locales = PlatformDispatcher.instance.locales;
    for (final l in locales) {
      final n = normalizeLang(l.languageCode, l.countryCode);
      if (n != null) return n;
    }
  } catch (_) {
    // 平台不支持时回退
  }
  return fallbackLangCode;
}

/// 语言状态控制器。
///
/// 继承 [ChangeNotifier]，语言切换时通知监听者（UI 自动重建）。
/// 持久化键：`afu_lang`，值：`system` 或语言码（zh-Hans/zh-Hant/ja/de/en）。
class AppLocale extends ChangeNotifier {
  AppLocale._();

  /// 单例实例。
  static final AppLocale instance = AppLocale._();

  /// shared_preferences 键。
  static const String prefsKey = 'afu_lang';

  /// 供 MaterialApp.supportedLocales 使用的 Locale 列表。
  static const List<Locale> supported = [
    Locale('zh', 'Hans'),
    Locale('zh', 'Hant'),
    Locale('ja'),
    Locale('de'),
    Locale('en'),
  ];

  String _langCode = 'system';

  /// 当前设置：`system` 或具体语言码。
  String get langCode => _langCode;

  /// 是否跟随系统。
  bool get isSystem => _langCode == 'system';

  /// 解析后的具体语言码（system 时解析为设备语言）。
  String get resolvedCode =>
      _langCode == 'system' ? detectDeviceLang() : _langCode;

  /// 供 MaterialApp.locale 使用。
  Locale get locale {
    final code = resolvedCode;
    return _localeFromCode(code);
  }

  static Locale _localeFromCode(String code) {
    switch (code) {
      case 'zh-Hans': return const Locale('zh', 'Hans');
      case 'zh-Hant': return const Locale('zh', 'Hant');
      case 'ja': return const Locale('ja');
      case 'de': return const Locale('de');
      case 'en': return const Locale('en');
      default: return const Locale('ja');
    }
  }

  /// 初始化：读取持久化设置并返回自身（便于 `await AppLocale.instance.init()`）。
  Future<AppLocale> init() async {
    await load();
    return this;
  }

  /// 从 shared_preferences 读取已保存的语言设置。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(prefsKey);
      if (stored != null && (stored == 'system' || supportedLangCodes.contains(stored))) {
        _langCode = stored;
        notifyListeners();
      }
    } catch (_) {
      // 读取失败保持默认 system
    }
  }

  /// 设置语言。`code` 为 `system` 或支持的语言码，并持久化。
  Future<void> setLang(String code) async {
    if (code != 'system' && !supportedLangCodes.contains(code)) return;
    if (code == _langCode) return;
    _langCode = code;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, code);
    } catch (_) {
      // 持久化失败不阻断语言切换
    }
  }

  /// 从 widget 树获取 [AppLocale] 实例（依赖订阅，语言变化时重建）。
  /// 树中无 AppLocaleScope 时回退到单例（兼容 ChangeNotifierProvider 用法）。
  static AppLocale of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppLocaleScope>();
    if (scope?.notifier != null) return scope!.notifier!;
    return instance;
  }
}

/// 把 [AppLocale] 注入 widget 树的 InheritedNotifier。
/// 语言变化时，依赖它的 widget 自动重建。
class AppLocaleScope extends InheritedNotifier<AppLocale> {
  const AppLocaleScope({
    super.key,
    required AppLocale locale,
    required super.child,
  }) : super(notifier: locale);

  /// 获取当前 [AppLocale]。
  static AppLocale of(BuildContext context) => AppLocale.of(context);

  @override
  bool updateShouldNotify(AppLocaleScope oldWidget) =>
      oldWidget.notifier != notifier;
}

/// 翻译表映射：语言码 → 键值表。
const Map<String, Map<String, String>> _allStrings = {
  'ja': _ja,
  'zh-Hans': _zhHans,
  'zh-Hant': _zhHant,
  'de': _de,
  'en': _en,
};

const Map<String, String> _ja = {
  'about': 'このアプリについて',
  'activeProfileLabel': '接続に使うユーザー',
  'adaptation': '対応モデル：AFU-WL-TZ-A1（ICOMON / 蟻阿福沃莱）',
  'add': '追加',
  'addDevice': 'デバイスを追加',
  'addProfile': 'ユーザーを追加',
  'ageLabel': '年齢',
  'algorithm': 'アルゴリズム',
  'all': 'すべて',
  'appTagline': '体重・体組成計',
  'applyRange': '適用',
  'assignTo': '割り当て先',
  'back': '戻る',
  'batteryLabel': 'バッテリー',
  'bcBone': '骨量',
  'bcFat': '体脂肪率',
  'bcMuscle': '筋肉率',
  'bcProtein': 'タンパク質',
  'bcSkeletal': '骨格筋',
  'bcWater': '水分率',
  'bodyComp': '体組成',
  'bodyCompLocal': '体組成（ローカル BIA 推定）',
  'boundDevices': '登録済みデバイス',
  'boundTag': '登録済み',
  'brand': 'AFU',
  'brandSub': '体組成計',
  'byDate': '日付',
  'cancel': 'キャンセル',
  'change': '増減',
  'clear': 'クリア',
  'clearDateFilter': '日付フィルタを解除',
  'clearGoal': 'クリア',
  'close': '閉じる',
  'collapse': '閉じる',
  'compUnavailable': '体組成は利用できません（電極未接触）',
  'confirm': '確定',
  'connFail': '接続失敗',
  'connOk': '接続 OK',
  'connectDirect': 'このアドレスに接続',
  'connectState': '接続状態',
  'connecting': '接続中…',
  'copiedMac': 'MAC をコピーしました',
  'credits': '謝辞',
  'creditsDesc': '本プロジェクトのプロトコル詳細は、以下の公開リバース成果と相互検証を行いました。感謝します：',
  'creditsLicense': '各プロジェクトは MIT ライセンスです。本アプリも同じオープンソースの精神に従います。',
  'customRange': 'カスタム',
  'days': '日',
  'debugLog': 'デバッグログ',
  'delete': '削除',
  'deselectAll': '選択解除',
  'detailTitle': '測定の詳細',
  'devBoundAt': '登録日',
  'devMac': 'MAC',
  'devModel': 'モデル',
  'devName': '名前',
  'deviceInfo': 'デバイス情報',
  'deviceInfoHint': '接続時に自動取得・ローカル保存（次回同期時に更新）',
  'deviceInfoTitle': 'デバイス情報',
  'discardSelected': '選択を破棄',
  'editProfile': '編集',
  'electrodeOff': '⚠ 電極が未接触 · 素足で 4 つの電極すべてを踏んでください',
  'electrodeOffShort': '未接触（インピーダンスなし）',
  'electrodeOn': '接触あり',
  'estimateLine': '体脂肪率などはローカル BIA 式による推定値です（参考値）',
  'expandMore': 'もっと見る',
  'filterByRange': '期間',
  'filterByUnit': 'ユーザーで絞り込み',
  'firmwareLabel': 'ファームウェア',
  'followSystem': 'システムに追従',
  'ghRepo': 'GitHub リポジトリ',
  'goalHint': '目標はご自身で設定でき、端末内にのみ保存されます。空欄にすると目標線は表示されません。',
  'goalLabel': '目標',
  'goalPlaceholder': '例 60',
  'goalReached': '達成',
  'goalSheetTitle': '目標体重を設定',
  'goalUnset': '目標未設定',
  'grantPerm': '権限を許可',
  'heightLabel': '身長 (cm)',
  'historySynced': '計りから履歴を{n}件取り込みました',
  'impedanceFailed': '今回の体阻抗は取得できませんでした',
  'impedanceRaw': 'インピーダンス生値',
  'language': '言語',
  'languageHint': 'システム言語に追従するか、手動で選択できます',
  'latest': '最新',
  'latestRecord': '最新',
  'localEstimate': 'ローカル推定',
  'lowWeightTag': '軽踏み？',
  'macFormat': 'MAC の形式が不正です (XX:XX:XX:XX:XX:XX)',
  'macHint': 'システムの Bluetooth 設定で確認できます。MAC が分かれば直接接続できます。',
  'macLabel': 'デバイスの MAC アドレス',
  'manualInput': 'MAC を入力',
  'manualMac': 'MAC アドレスを入力',
  'manufacturerLabel': 'メーカー',
  'measuringWait': '計りに乗ってください',
  'modelLabel': 'モデル',
  'myDevices': 'マイデバイス',
  'nameLabel': '名前',
  'namePlaceholder': '例：本人',
  'needPermDesc': '「付近のデバイス / 位置情報」が未許可のためスキャンできません',
  'needPermTitle': 'Bluetooth 権限が必要です',
  'newUnitPlaceholder': '新しいユーザー名',
  'noData': 'データがありません',
  'noDataDesc': 'デバイス画面で測定して保存してください',
  'noDeviceDesc': 'スキャンして追加するか、MAC アドレスを直接入力してください',
  'noDeviceTitle': '体組成計が未登録です',
  'none': 'なし',
  'notSynced': '未送信',
  'open': '開く',
  'openSource': 'オープンソース',
  'openSourceDesc': '本プロジェクトはオープンソースです。ソースとビルド（GitHub Actions）は公開されています。',
  'optional': '（任意）',
  'pendingEmpty': '未処理の履歴はありません',
  'pendingEmptyHint': '計りに新しい測定がたまると、ここに表示されます',
  'pendingEntry': '未割り当て履歴',
  'pendingHint': '計りから取り込んだ測定です。誰のデータか選んでください',
  'pendingTitle': '未割り当ての履歴',
  'phaseDone': '測定完了',
  'phaseImpedance': '体阻抗測定中',
  'phaseWeighing': '体重測定中',
  'privacyLine': 'データは端末内のみに保存され、第三者に送信されません',
  'profileHint': '体脂肪率の計算に必要です（性別・年齢・身長）',
  'profileRequired': 'すべて入力してください',
  'profileSave': '保存して開始',
  'profileTitle': 'プロフィール設定',
  'profilesHint': '計りに送信する身体データです。接続に使うユーザーを選べます',
  'profilesTitle': 'ユーザー管理',
  'pullFromPc': 'PC から取得',
  'pullResult': '取得結果',
  'pulling': '取得中…',
  'pushFail': '送信失敗',
  'pushOk': '送信成功',
  'pushSelected': '送信',
  'pushStatus': '送信状態',
  'pushUrl': '送信先 URL',
  'pushUrlHint': 'PC 側で server_receiver.py を起動し、同じ Wi-Fi に接続してください。URL は自由に変更できます。',
  'pushing': '送信中…',
  'range24h': '24時間',
  'range30d': '30日',
  'range7d': '7日',
  'rangeAll': 'すべて',
  'rangeFrom': '開始日',
  'rangeHint': '開始日と終了日を入力、または下の日付をタップ',
  'rangeTo': '終了日',
  'rangeToday': '今日',
  'recordCountSuffix': '件',
  'recordWriteFail': '記録の保存に失敗',
  'records': '記録',
  'refresh': '更新',
  'rename': '名前変更',
  'save': '保存',
  'saveFail': '保存失敗',
  'saveGoal': '目標を保存',
  'saveMeasurement': 'この測定を保存',
  'saveUrl': 'URL を保存',
  'saved': '保存済み:',
  'saving': '保存中…',
  'scanAndAdd': 'スキャンして追加',
  'scanningHint': '初回登録では、体脂計を軽く踏んで画面を点灯させ、そのまま動かさずに置いてください。計りが起動してアドバタイズを始めるまで約3〜5分かかります。蓝牙MACアドレスをご存じでしたら、手動接続をお勧めします。',
  'scanningNew': '新しいデバイスを検索中…',
  'selectAll': 'すべて選択',
  'selectAllUnsynced': '未送信を全選択',
  'selectDate': '日付を選択',
  'selectFirst': '送信する項目を選択してください',
  'setGoal': '目標設定',
  'sexFemale': '女性',
  'sexLabel': '性別',
  'sexMale': '男性',
  'standOnScale': '計りに乗ると測定が始まります',
  'start': '開始',
  'stateConnected': '接続済み',
  'stateConnecting': '接続中…',
  'stateError': '接続エラー',
  'stateIdle': '未接続',
  'stopScan': 'スキャン停止',
  'syncSettings': '同期設定',
  'synced': '送信済み',
  'tabData': 'データ',
  'tabDevice': 'デバイス',
  'tabSettings': '設定',
  'testConn': '接続テスト',
  'testing': 'テスト中…',
  'toGoal': '目標まで',
  'totalRecords': '記録数',
  'transferHint': '選択したデータを誰に割り当てますか？（体成分は再計算が必要です）',
  'transferTo': '所有者を変更',
  'trend': '体重の推移',
  'unbind': 'バインド解除',
  'unitDisplayHint': '表示・送信する単位（保存は常に kg）',
  'unitJin': '斤（中国の両）',
  'unitKg': 'kg（キログラム）',
  'unitLb': 'lb（ポンド）',
  'unitSection2': '単位',
  'unitsHint': '1 台の計りを複数人で使う場合、保存時に割り当てを選べます',
  'unitsLabel': 'ユーザー',
  'unitsSection': 'ユーザー',
  'unofficial': 'メーカー公式アプリではありません',
  'unselectAll': '選択解除',
  'unsynced': '未送信',
  'weightLabel': '体重 (kg)',
  'weightUnit': 'kg',
  'whoIsThis': 'この測定は誰のもの？',
  'startWeighing': '測定開始',
  'measuringTitle': '体重測定',
  'currentMeasurer': '測定者',
  'switchLabel': '切替',
  'selectDevice': '体重計を選択',
  'rescanDevice': '再スキャン',
  'appearance': '外観',
  'darkMode': 'ダークモード',
  'themeLight': 'ライト',
  'themeDark': 'ダーク',
  'themeSystem': '自動',
  'setGoalShort': '目標設定',
  'nextStep': '次へ',
  'skipForNow': 'スキップ',
  'bindScaleTitle': '体重計を連携',
  'bindScaleHint': '体重計を軽く踏んで起動し、検出されたデバイスをタップして連携します。',
  'noImpedanceTitle': '体組成未取得 · 体重のみ',
  'noImpedanceDesc': '素足で4つの電極にしっかり乗るか、体重のみ保存できます。',
  'remeasure': '乗り直す',
  'saveWeightOnly': '体重のみ保存',
  'placeFeetHint': '素足で4つの電極に乗ってください',
  'electrodeReadyHint': '電極接続完了 · 動かないでください',
  'ageSuffix': '歳',
  'listView': 'リスト',
  'filterShort': '絞込',
  'incompleteSection': '不完全な測定',
  'incompleteHint': 'インピーダンス未取得時の扱い（測定画面で長押しすると既定になります）',
  'policyAsk': '毎回確認',
  'policySave': '体重のみ',
  'policySkip': '保存しない',
  'fixOwnership': '記録の帰属を修復',
  'noOrphan': '修復が必要な記録はありません',
  'fixOwnershipHint': '存在しないメンバーに紐づく記録です。帰属先を選ぶと再表示されます。',
  'assignToWhom': '誰に帰属しますか',
  'unnamed': '(名称なし)',
  'recordsUnit': '件',
  'tapToStart': 'タップして測定開始',
  'exitUnsavedTitle': '今回の測定は未保存',
  'keepMeasuring': '測定を続ける',
  'exitApp': '終了',
  'scanNotFoundTitle': '体重計に接続できません',
  'scanNotFoundDesc': '5秒以内に登録済みの体重計が見つかりませんでした。近くの体重計を検索しますか？',
  'searchDevice': '検索する',
  'longPressDefault': '長押しで以後の既定に設定',
  'setDefaultSave': '既定に設定：体重のみ',
  'setDefaultSkip': '既定に設定：保存しない',
  'filterRangeTitle': '期間を絞り込む',
  'noSavedRanges': '保存された期間はまだありません。下の「日付を選択」で新規作成でき、選んだ期間は自動保存されます。',
  'plsCreateProfile': '先にメンバーを作成してください',
  'exitUnsavedDesc': 'インピーダンス未取得のため保存していません。終了しますか？',
  'doneRetry': '測定完了 · もう一度タップで再測定',
  'needBind': '先に体重計を登録してください',
  'savedMsg': '記録しました',
  'bfEstimate': '体脂肪(推定)',
  'myScale': '体重計',
  'searchingNearby': '近くの AFU 体重計を検索中…',
  'noDeviceFound': 'デバイスが見つかりません。体重計を軽く踏んで起こしてから再試行してください',
  'calcModel': '計算モデル',
  'calcModelValue': '公式非公開・独自推計',
  'calcModelHint': '体脂肪率などの身体組成は、本アプリ独自の推定式で計算しています。公式アプリの算出方法は非公開のため、表示値が公式と異なる場合があります（通常は数ポイント以内）。体重とBMIは実測値どおりです。',
  'birthdayLabel': '生年月日',
  'birthdayHint': 'タップして生年月日を選択',
  'ageAutoCalc': '年齢は自動計算：{n} 歳',
  'birthdayKeepHint': '未入力の場合は現在の年齢を保持します',
  'birthdayCurrentAge': '現在 {n} 歳',
  'birthdayTapToChange': 'タップで生年月日を再設定',
};

const Map<String, String> _zhHans = {
  'about': '关于',
  'activeProfileLabel': '连接秤使用的用户',
  'adaptation': '适配型号：AFU-WL-TZ-A1（ICOMON / 蚂蚁阿福沃莱）',
  'add': '添加',
  'addDevice': '添加设备',
  'addProfile': '添加用户',
  'ageLabel': '年龄',
  'algorithm': '算法模型',
  'all': '全部',
  'appTagline': '体脂秤',
  'applyRange': '应用',
  'assignTo': '分配给',
  'back': '返回',
  'batteryLabel': '电量',
  'bcBone': '骨量',
  'bcFat': '体脂率',
  'bcMuscle': '肌肉率',
  'bcProtein': '蛋白质',
  'bcSkeletal': '骨骼肌',
  'bcWater': '水分率',
  'bodyComp': '身体成分',
  'bodyCompLocal': '身体成分（本地 BIA 估算）',
  'boundDevices': '已绑定设备',
  'boundTag': '已绑定',
  'brand': 'AFU',
  'brandSub': '体脂秤',
  'byDate': '按日期',
  'cancel': '取消',
  'change': '变化',
  'clear': '清空',
  'clearDateFilter': '清除日期筛选',
  'clearGoal': '清除',
  'close': '关闭',
  'collapse': '收起',
  'compUnavailable': '体脂等数据不可用（电极未导通）',
  'confirm': '确定',
  'connFail': '连接失败',
  'connOk': '连接正常',
  'connectDirect': '直接连接',
  'connectState': '连接状态',
  'connecting': '连接中…',
  'copiedMac': '已复制 MAC',
  'credits': '致谢',
  'creditsDesc': '本项目的协议细节与以下公开逆向成果做过交叉验证，特此致谢：',
  'creditsLicense': '以上项目均为 MIT 许可。本应用遵循同样的开源精神。',
  'customRange': '自定义',
  'days': '天',
  'debugLog': '调试日志',
  'delete': '删除',
  'deselectAll': '取消全选',
  'detailTitle': '测量详情',
  'devBoundAt': '绑定时间',
  'devMac': 'MAC',
  'devModel': '型号',
  'devName': '名称',
  'deviceInfo': '设备信息',
  'deviceInfoHint': '连接后自动读取并本地缓存，下次同步时更新',
  'deviceInfoTitle': '设备信息',
  'discardSelected': '丢弃所选',
  'editProfile': '编辑',
  'electrodeOff': '⚠ 电极未导通 · 请赤脚同时踩满四个电极',
  'electrodeOffShort': '未导通（无阻抗）',
  'electrodeOn': '已导通',
  'estimateLine': '体脂/肌肉等为本地 BIA 公式估算，仅供参考',
  'expandMore': '展开更多',
  'filterByRange': '时间范围',
  'filterByUnit': '按单位筛选',
  'firmwareLabel': '固件版本',
  'followSystem': '跟随系统',
  'ghRepo': 'GitHub 仓库',
  'goalHint': '目标由你自己定，仅保存在本机。留空则不显示目标线。',
  'goalLabel': '目标',
  'goalPlaceholder': '例如 60',
  'goalReached': '已达标',
  'goalSheetTitle': '设置目标体重',
  'goalUnset': '目标未设',
  'grantPerm': '授予权限',
  'heightLabel': '身高 (cm)',
  'historySynced': '已从秤上补收 {n} 条历史记录',
  'impedanceFailed': '本次未测得体阻抗',
  'impedanceRaw': '阻抗原始值',
  'language': '语言',
  'languageHint': '可跟随系统语言，也可手动切换',
  'latest': '最新',
  'latestRecord': '最近一次',
  'localEstimate': '本地估算',
  'lowWeightTag': '疑似轻踩',
  'macFormat': 'MAC 格式不正确，应为 XX:XX:XX:XX:XX:XX',
  'macHint': '可在系统蓝牙设置中查看。已知 MAC 可直接连接，无需扫描。',
  'macLabel': '设备 MAC 地址',
  'manualInput': '手动输入',
  'manualMac': '手动输入 MAC 地址',
  'manufacturerLabel': '制造商',
  'measuringWait': '站上秤即可开始测量',
  'modelLabel': '型号',
  'myDevices': '我的设备',
  'nameLabel': '名字',
  'namePlaceholder': '例如：本人',
  'needPermDesc': '未授予「附近设备 / 位置」权限，无法扫描体脂秤',
  'needPermTitle': '需要蓝牙权限',
  'newUnitPlaceholder': '新单位名称',
  'noData': '暂无数据',
  'noDataDesc': '去设备页测量并保存',
  'noDeviceDesc': '扫描添加，或手动输入 MAC 地址直接连接',
  'noDeviceTitle': '还没有绑定体脂秤',
  'none': '无',
  'notSynced': '未推送',
  'open': '打开',
  'openSource': '开源',
  'openSourceDesc': '本项目开源，源码与构建（GitHub Actions）公开可查。',
  'optional': '（可选）',
  'pendingEmpty': '暂无待处理记录',
  'pendingEmptyHint': '秤上有新测量时会出现在这里',
  'pendingEntry': '待分配历史',
  'pendingHint': '从秤上补收的测量记录，请选择归属单位',
  'pendingTitle': '待分配历史',
  'phaseDone': '测量完成',
  'phaseImpedance': '阻抗测量',
  'phaseWeighing': '正在测量',
  'privacyLine': '数据仅存本机，不上传任何第三方',
  'profileHint': '体脂率计算必需（性别 / 年龄 / 身高），未填写则无法得到准确体脂',
  'profileRequired': '请完整填写后再开始',
  'profileSave': '保存并开始',
  'profileTitle': '身体数据',
  'profilesHint': '发送给秤的身体数据，可选择用哪个用户连接',
  'profilesTitle': '用户管理',
  'pullFromPc': '从电脑拉取数据',
  'pullResult': '拉取完成',
  'pulling': '拉取中…',
  'pushFail': '推送失败',
  'pushOk': '推送成功',
  'pushSelected': '推送',
  'pushStatus': '推送状态',
  'pushUrl': '推送地址',
  'pushUrlHint': '电脑端需运行 server_receiver.py，保持同一 WiFi。地址可自由修改。',
  'pushing': '推送中…',
  'range24h': '24H',
  'range30d': '30天',
  'range7d': '7天',
  'rangeAll': '全部',
  'rangeFrom': '开始日期',
  'rangeHint': '输入起止日期，或点选下方日期',
  'rangeTo': '结束日期',
  'rangeToday': '今天',
  'recordCountSuffix': '条',
  'recordWriteFail': '记录写入失败',
  'records': '记录',
  'refresh': '刷新',
  'rename': '重命名',
  'save': '保存',
  'saveFail': '保存失败',
  'saveGoal': '保存目标',
  'saveMeasurement': '保存这次测量',
  'saveUrl': '保存地址',
  'saved': '已保存到',
  'saving': '保存中…',
  'scanAndAdd': '扫描并添加设备',
  'scanningHint': '首次绑定请将体脂秤轻踩亮屏后放置不动，需要3-5分钟左右等待体脂秤唤醒发起广播，若您了解设备的蓝牙MAC地址建议直接手动连接。',
  'scanningNew': '正在搜索新设备…',
  'selectAll': '全选',
  'selectAllUnsynced': '全选未推送',
  'selectDate': '选择日期',
  'selectFirst': '请先勾选要推送的记录',
  'setGoal': '设目标',
  'sexFemale': '女',
  'sexLabel': '性别',
  'sexMale': '男',
  'standOnScale': '站上秤即可开始测量',
  'start': '起始',
  'stateConnected': '已连接',
  'stateConnecting': '连接中…',
  'stateError': '连接失败',
  'stateIdle': '未连接',
  'stopScan': '停止扫描',
  'syncSettings': '同步设置',
  'synced': '已推送',
  'tabData': '数据',
  'tabDevice': '设备',
  'tabSettings': '设置',
  'testConn': '测试连接',
  'testing': '测试中…',
  'toGoal': '距目标',
  'totalRecords': '总记录',
  'transferHint': '把选中的数据分配给谁？（转移后体成分需重新测量）',
  'transferTo': '转移给',
  'trend': '体重趋势',
  'unbind': '解除绑定',
  'unitDisplayHint': '显示与发送给秤的单位（数据库始终以 kg 存）',
  'unitJin': '斤',
  'unitKg': 'kg（公斤）',
  'unitLb': 'lb（磅）',
  'unitSection2': '单位',
  'unitsHint': '多人共用一台秤时，测量保存可选择归属',
  'unitsLabel': '单位',
  'unitsSection': '分配单位',
  'unofficial': '非小米/厂商官方应用',
  'unselectAll': '取消全选',
  'unsynced': '未推送',
  'weightLabel': '体重 (kg)',
  'weightUnit': 'kg',
  'whoIsThis': '这次测量属于谁？',
  'startWeighing': '开始称量',
  'measuringTitle': '称重测量',
  'currentMeasurer': '本次测量者',
  'switchLabel': '切换',
  'selectDevice': '选择设备',
  'rescanDevice': '重新搜索设备',
  'appearance': '外观',
  'darkMode': '深色模式',
  'themeLight': '浅色',
  'themeDark': '深色',
  'themeSystem': '系统',
  'setGoalShort': '设目标',
  'nextStep': '下一步',
  'skipForNow': '跳过，稍后绑定',
  'bindScaleTitle': '搜索并绑定体脂秤',
  'bindScaleHint': '轻踩体脂秤唤醒屏幕，点击下方搜索到的设备即可完成绑定。',
  'noImpedanceTitle': '未测到阻抗 · 仅读到体重',
  'noImpedanceDesc': '请抬脚后光脚重新站好，让双脚踩住四个电极片；若只需体重也可手动保存。',
  'remeasure': '抬脚重测',
  'saveWeightOnly': '仅保存体重',
  'placeFeetHint': '请将双脚赤脚放在四个电极片上',
  'electrodeReadyHint': '电极已导通 · 请保持站稳',
  'ageSuffix': '岁',
  'listView': '列表',
  'filterShort': '筛选',
  'incompleteSection': '不完整测量',
  'incompleteHint': '没测到阻抗时如何处理（长按测量页选项也可设为默认）',
  'policyAsk': '每次询问',
  'policySave': '仅存体重',
  'policySkip': '不保存',
  'fixOwnership': '修复记录归属',
  'noOrphan': '没有需要修复的记录',
  'fixOwnershipHint': '这些记录挂在已不存在的成员名下，选择要归给谁即可恢复显示。',
  'assignToWhom': '归给谁',
  'unnamed': '(未命名)',
  'recordsUnit': '条',
  'tapToStart': '轻触圆环开始测量',
  'exitUnsavedTitle': '本次测量未保存',
  'keepMeasuring': '继续测量',
  'exitApp': '退出',
  'scanNotFoundTitle': '未连接到体脂秤',
  'scanNotFoundDesc': '5 秒内没有发现已绑定设备。是否搜索附近的体脂秤？',
  'searchDevice': '搜索设备',
  'longPressDefault': '长按选项可设为以后默认',
  'setDefaultSave': '已设为默认：仅保存体重',
  'setDefaultSkip': '已设为默认：不保存',
  'filterRangeTitle': '筛选日期区间',
  'noSavedRanges': '还没有保存过区间。点下方「选择日期」新建，选过的区间会自动保存。',
  'plsCreateProfile': '请先创建成员',
  'exitUnsavedDesc': '这次没测到完整阻抗，数据没有保存。确定要退出吗？',
  'doneRetry': '测量完成 · 再按一次可重新测量',
  'needBind': '请先绑定设备',
  'savedMsg': '已记录',
  'bfEstimate': '体脂预估',
  'myScale': '体脂秤',
  'searchingNearby': '正在搜索附近的 AFU 体脂秤…',
  'noDeviceFound': '未发现设备，可轻踩唤醒体脂秤后重试',
  'calcModel': '计算模型',
  'calcModelValue': '自研公式 · 与官方不同',
  'calcModelHint': '体脂率等身体成分由本 App 的独立估算公式计算。官方算法的具体实现未公开，因此显示数值可能与官方 App 存在差异（通常在几个百分点内）。体重与 BMI 为实测值，不受影响。',
  'birthdayLabel': '出生日期',
  'birthdayHint': '点击选择出生日期',
  'ageAutoCalc': '自动换算年龄：{n} 岁',
  'birthdayKeepHint': '留空则沿用当前年龄',
  'birthdayCurrentAge': '当前 {n} 岁',
  'birthdayTapToChange': '点击可重设出生日期',
};

const Map<String, String> _zhHant = {
  'about': '關於',
  'activeProfileLabel': '連線秤使用的使用者',
  'adaptation': '適用型號：AFU-WL-TZ-A1（ICOMON / 螞蟻阿福沃萊）',
  'add': '新增',
  'addDevice': '新增裝置',
  'addProfile': '新增使用者',
  'ageLabel': '年齡',
  'algorithm': '演算法模型',
  'all': '全部',
  'appTagline': '體脂秤',
  'applyRange': '應用',
  'assignTo': '分配給',
  'back': '返回',
  'batteryLabel': '電量',
  'bcBone': '骨量',
  'bcFat': '體脂率',
  'bcMuscle': '肌肉率',
  'bcProtein': '蛋白質',
  'bcSkeletal': '骨骼肌',
  'bcWater': '水分率',
  'bodyComp': '身體組成',
  'bodyCompLocal': '身體組成（本機 BIA 估算）',
  'boundDevices': '已綁定裝置',
  'boundTag': '已綁定',
  'brand': 'AFU',
  'brandSub': '體脂計',
  'byDate': '依日期',
  'cancel': '取消',
  'change': '變化',
  'clear': '清除',
  'clearDateFilter': '清除日期篩選',
  'clearGoal': '清除',
  'close': '關閉',
  'collapse': '收合',
  'compUnavailable': '體脂等資料不可用（電極未導通）',
  'confirm': '確定',
  'connFail': '連線失敗',
  'connOk': '連線正常',
  'connectDirect': '直接連線',
  'connectState': '連線狀態',
  'connecting': '連線中…',
  'copiedMac': '已複製 MAC',
  'credits': '致謝',
  'creditsDesc': '本專案的協定細節與以下公開逆向成果做過交叉驗證，特此致謝：',
  'creditsLicense': '以上專案均為 MIT 授權。本應用遵循同樣的開源精神。',
  'customRange': '自訂',
  'days': '天',
  'debugLog': '除錯記錄',
  'delete': '刪除',
  'deselectAll': '取消全選',
  'detailTitle': '測量詳情',
  'devBoundAt': '綁定時間',
  'devMac': 'MAC',
  'devModel': '型號',
  'devName': '名稱',
  'deviceInfo': '裝置資訊',
  'deviceInfoHint': '連線後自動讀取並本機快取，下次同步時更新',
  'deviceInfoTitle': '裝置資訊',
  'discardSelected': '丟棄所選',
  'editProfile': '編輯',
  'electrodeOff': '⚠ 電極未導通 · 請赤腳同時踩滿四個電極',
  'electrodeOffShort': '未導通（無阻抗）',
  'electrodeOn': '已導通',
  'estimateLine': '體脂／肌肉等為本機 BIA 公式估算，僅供參考',
  'expandMore': '展開更多',
  'filterByRange': '時間範圍',
  'filterByUnit': '依單位篩選',
  'firmwareLabel': '韌體版本',
  'followSystem': '跟隨系統',
  'ghRepo': 'GitHub 儲存庫',
  'goalHint': '目標由你自己設定，僅儲存在本機。留空則不顯示目標線。',
  'goalLabel': '目標',
  'goalPlaceholder': '例如 60',
  'goalReached': '已達標',
  'goalSheetTitle': '設定目標體重',
  'goalUnset': '目標未設',
  'grantPerm': '授予權限',
  'heightLabel': '身高 (cm)',
  'historySynced': '已從秤上補收 {n} 筆歷史紀錄',
  'impedanceFailed': '本次未測得體阻抗',
  'impedanceRaw': '阻抗原始值',
  'language': '語言',
  'languageHint': '可跟隨系統語言，也可手動切換',
  'latest': '最新',
  'latestRecord': '最近一次',
  'localEstimate': '本機估算',
  'lowWeightTag': '疑似輕踩',
  'macFormat': 'MAC 格式錯誤，應為 XX:XX:XX:XX:XX:XX',
  'macHint': '可在系統藍牙設定中查看。已知 MAC 可直接連線，無需掃描。',
  'macLabel': '裝置 MAC 位址',
  'manualInput': '手動輸入',
  'manualMac': '手動輸入 MAC 位址',
  'manufacturerLabel': '製造商',
  'measuringWait': '站上體脂計即可開始測量',
  'modelLabel': '型號',
  'myDevices': '我的裝置',
  'nameLabel': '名字',
  'namePlaceholder': '例如：本人',
  'needPermDesc': '未授予「鄰近裝置 / 位置」權限，無法掃描體脂計',
  'needPermTitle': '需要藍牙權限',
  'newUnitPlaceholder': '新單位名稱',
  'noData': '尚無資料',
  'noDataDesc': '至裝置頁測量並儲存',
  'noDeviceDesc': '掃描新增，或手動輸入 MAC 位址直接連線',
  'noDeviceTitle': '尚未綁定體脂計',
  'none': '無',
  'notSynced': '未推送',
  'open': '開啟',
  'openSource': '開源',
  'openSourceDesc': '本專案開源，原始碼與建置（GitHub Actions）公開可查。',
  'optional': '（可選）',
  'pendingEmpty': '暫無待處理紀錄',
  'pendingEmptyHint': '秤上有新測量時會出現在這裡',
  'pendingEntry': '待分配歷史',
  'pendingHint': '從秤上補收的測量紀錄，請選擇歸屬單位',
  'pendingTitle': '待分配歷史',
  'phaseDone': '測量完成',
  'phaseImpedance': '阻抗測量',
  'phaseWeighing': '正在測量',
  'privacyLine': '資料僅儲存於本機，不上傳任何第三方',
  'profileHint': '體脂率計算必需（性別 / 年齡 / 身高），未填寫則無法得到準確體脂',
  'profileRequired': '請完整填寫後再開始',
  'profileSave': '儲存並開始',
  'profileTitle': '身體資料',
  'profilesHint': '發送給秤的身體資料，可選擇用哪個使用者連線',
  'profilesTitle': '使用者管理',
  'pullFromPc': '從電腦拉取資料',
  'pullResult': '拉取完成',
  'pulling': '拉取中…',
  'pushFail': '推送失敗',
  'pushOk': '推送成功',
  'pushSelected': '推送',
  'pushStatus': '推送狀態',
  'pushUrl': '推送位址',
  'pushUrlHint': '電腦端需執行 server_receiver.py，保持同一 WiFi。位址可自由修改。',
  'pushing': '推送中…',
  'range24h': '24H',
  'range30d': '30天',
  'range7d': '7天',
  'rangeAll': '全部',
  'rangeFrom': '開始日期',
  'rangeHint': '輸入起止日期，或點選下方日期',
  'rangeTo': '結束日期',
  'rangeToday': '今天',
  'recordCountSuffix': '筆',
  'recordWriteFail': '記錄寫入失敗',
  'records': '記錄',
  'refresh': '重新整理',
  'rename': '重新命名',
  'save': '儲存',
  'saveFail': '儲存失敗',
  'saveGoal': '儲存目標',
  'saveMeasurement': '儲存這次測量',
  'saveUrl': '儲存位址',
  'saved': '已儲存到',
  'saving': '儲存中…',
  'scanAndAdd': '掃描並新增裝置',
  'scanningHint': '首次綁定請將體脂秤輕踩亮屏後放置不動，需要3-5分鐘左右等待體脂秤喚醒發起廣播，若您了解設備的藍牙MAC地址建議直接手動連接。',
  'scanningNew': '正在搜尋新裝置…',
  'selectAll': '全選',
  'selectAllUnsynced': '全選未推送',
  'selectDate': '選擇日期',
  'selectFirst': '請先勾選要推送的記錄',
  'setGoal': '設目標',
  'sexFemale': '女',
  'sexLabel': '性別',
  'sexMale': '男',
  'standOnScale': '站上體脂計即可開始測量',
  'start': '起始',
  'stateConnected': '已連線',
  'stateConnecting': '連線中…',
  'stateError': '連線失敗',
  'stateIdle': '未連線',
  'stopScan': '停止掃描',
  'syncSettings': '同步設定',
  'synced': '已推送',
  'tabData': '資料',
  'tabDevice': '裝置',
  'tabSettings': '設定',
  'testConn': '測試連線',
  'testing': '測試中…',
  'toGoal': '距目標',
  'totalRecords': '總記錄',
  'transferHint': '把選取的資料分配給誰？（轉移後體成分需重新測量）',
  'transferTo': '轉移給',
  'trend': '體重趨勢',
  'unbind': '解除綁定',
  'unitDisplayHint': '顯示與發送給秤的單位（資料庫始終以 kg 存）',
  'unitJin': '斤',
  'unitKg': 'kg（公斤）',
  'unitLb': 'lb（磅）',
  'unitSection2': '單位',
  'unitsHint': '多人共用一台體脂計時，測量儲存可選擇歸屬',
  'unitsLabel': '單位',
  'unitsSection': '分配單位',
  'unofficial': '非小米／廠商官方應用程式',
  'unselectAll': '取消全選',
  'unsynced': '未推送',
  'weightLabel': '體重 (kg)',
  'weightUnit': 'kg',
  'whoIsThis': '這次測量屬於誰？',
  'startWeighing': '開始秤量',
  'measuringTitle': '秤重測量',
  'currentMeasurer': '本次測量者',
  'switchLabel': '切換',
  'selectDevice': '選擇裝置',
  'rescanDevice': '重新搜尋裝置',
  'appearance': '外觀',
  'darkMode': '深色模式',
  'themeLight': '淺色',
  'themeDark': '深色',
  'themeSystem': '系統',
  'setGoalShort': '設目標',
  'nextStep': '下一步',
  'skipForNow': '跳過，稍後綁定',
  'bindScaleTitle': '搜尋並綁定體脂秤',
  'bindScaleHint': '輕踩體脂秤喚醒螢幕，點擊下方搜尋到的裝置即可完成綁定。',
  'noImpedanceTitle': '未測到阻抗 · 僅讀到體重',
  'noImpedanceDesc': '請抬腳後光腳重新站好，讓雙腳踩住四個電極片；若只需體重也可手動儲存。',
  'remeasure': '抬腳重測',
  'saveWeightOnly': '僅儲存體重',
  'placeFeetHint': '請將雙腳赤腳放在四個電極片上',
  'electrodeReadyHint': '電極已導通 · 請保持站穩',
  'ageSuffix': '歲',
  'listView': '列表',
  'filterShort': '篩選',
  'incompleteSection': '不完整測量',
  'incompleteHint': '沒測到阻抗時如何處理（長按測量頁選項也可設為預設）',
  'policyAsk': '每次詢問',
  'policySave': '僅存體重',
  'policySkip': '不儲存',
  'fixOwnership': '修復記錄歸屬',
  'noOrphan': '沒有需要修復的記錄',
  'fixOwnershipHint': '這些記錄掛在已不存在的成員名下，選擇要歸給誰即可恢復顯示。',
  'assignToWhom': '歸給誰',
  'unnamed': '(未命名)',
  'recordsUnit': '條',
  'tapToStart': '輕觸圓環開始測量',
  'exitUnsavedTitle': '本次測量未儲存',
  'keepMeasuring': '繼續測量',
  'exitApp': '退出',
  'scanNotFoundTitle': '未連接到體脂秤',
  'scanNotFoundDesc': '5 秒內沒有發現已綁定裝置。是否搜尋附近的體脂秤？',
  'searchDevice': '搜尋裝置',
  'longPressDefault': '長按選項可設為以後預設',
  'setDefaultSave': '已設為預設：僅存體重',
  'setDefaultSkip': '已設為預設：不儲存',
  'filterRangeTitle': '篩選日期區間',
  'noSavedRanges': '還沒有儲存過區間。點下方「選擇日期」新建，選過的區間會自動儲存。',
  'plsCreateProfile': '請先建立成員',
  'exitUnsavedDesc': '這次沒測到完整阻抗，資料沒有儲存。確定要退出嗎？',
  'doneRetry': '測量完成 · 再按一次可重新測量',
  'needBind': '請先綁定裝置',
  'savedMsg': '已記錄',
  'bfEstimate': '體脂預估',
  'myScale': '體脂秤',
  'searchingNearby': '正在搜尋附近的 AFU 體脂秤…',
  'noDeviceFound': '未發現裝置，可輕踩喚醒體脂秤後重試',
  'calcModel': '計算模型',
  'calcModelValue': '自研公式 · 與官方不同',
  'calcModelHint': '體脂率等身體成分由本 App 的獨立估算公式計算。官方演算法的具體實作未公開，因此顯示數值可能與官方 App 存在差異（通常在幾個百分點內）。體重與 BMI 為實測值，不受影響。',
  'birthdayLabel': '出生日期',
  'birthdayHint': '點擊選擇出生日期',
  'ageAutoCalc': '自動換算年齡：{n} 歲',
  'birthdayKeepHint': '留空則沿用目前年齡',
  'birthdayCurrentAge': '目前 {n} 歲',
  'birthdayTapToChange': '點擊可重設出生日期',
};

const Map<String, String> _de = {
  'about': 'Über',
  'activeProfileLabel': 'Benutzer für Verbindung',
  'adaptation': 'Modell: AFU-WL-TZ-A1 (ICOMON / Ant Afu Welland)',
  'add': 'Hinzufügen',
  'addDevice': 'Gerät hinzufügen',
  'addProfile': 'Benutzer hinzufügen',
  'ageLabel': 'Alter',
  'algorithm': 'Algorithmus',
  'all': 'Alle',
  'appTagline': 'Körperanalysewaage',
  'applyRange': 'Anwenden',
  'assignTo': 'Zuordnen an',
  'back': 'Zurück',
  'batteryLabel': 'Akku',
  'bcBone': 'Knochen',
  'bcFat': 'Körperfett',
  'bcMuscle': 'Muskeln',
  'bcProtein': 'Protein',
  'bcSkeletal': 'Skelettmuskeln',
  'bcWater': 'Wasser',
  'bodyComp': 'Körperzusammensetzung',
  'bodyCompLocal': 'Körperzusammensetzung (lokale BIA-Schätzung)',
  'boundDevices': 'Verknüpfte Geräte',
  'boundTag': 'Verknüpft',
  'brand': 'AFU',
  'brandSub': 'Körperanalysewaage',
  'byDate': 'Nach Datum',
  'cancel': 'Abbrechen',
  'change': 'Änderung',
  'clear': 'Leeren',
  'clearDateFilter': 'Datumsfilter löschen',
  'clearGoal': 'Löschen',
  'close': 'Schließen',
  'collapse': 'Schließen',
  'compUnavailable': 'Körperdaten nicht verfügbar (keine Elektrodenkontakt)',
  'confirm': 'OK',
  'connFail': 'Verbindung fehlgeschlagen',
  'connOk': 'Verbindung OK',
  'connectDirect': 'Direkt verbinden',
  'connectState': 'Verbindung',
  'connecting': 'Verbinde…',
  'copiedMac': 'MAC kopiert',
  'credits': 'Danksagung',
  'creditsDesc': 'Die Protokolldetails dieses Projekts wurden mit den folgenden öffentlichen Reverse-Engineering-Ergebnissen gegengeprüft. Vielen Dank:',
  'creditsLicense': 'Alle Projekte stehen unter MIT-Lizenz. Diese App folgt demselben Open-Source-Gedanken.',
  'customRange': 'Benutzerdefiniert',
  'days': 'Tage',
  'debugLog': 'Debug-Log',
  'delete': 'Löschen',
  'deselectAll': 'Auswahl aufheben',
  'detailTitle': 'Messdetails',
  'devBoundAt': 'Verknüpft am',
  'devMac': 'MAC',
  'devModel': 'Modell',
  'devName': 'Name',
  'deviceInfo': 'Geräteinfo',
  'deviceInfoHint': 'Beim Verbinden gelesen und lokal gespeichert',
  'deviceInfoTitle': 'Geräteinfo',
  'discardSelected': 'Auswahl verwerfen',
  'editProfile': 'Bearbeiten',
  'electrodeOff': '⚠ Elektroden ohne Kontakt · barfuß alle vier Elektroden treten',
  'electrodeOffShort': 'Kein Kontakt (keine Impedanz)',
  'electrodeOn': 'Kontakt',
  'estimateLine': 'Körperfett etc. sind lokale BIA-Schätzwerte (nur zur Orientierung)',
  'expandMore': 'Mehr anzeigen',
  'filterByRange': 'Zeitraum',
  'filterByUnit': 'Nach Person filtern',
  'firmwareLabel': 'Firmware',
  'followSystem': 'System folgen',
  'ghRepo': 'GitHub-Repository',
  'goalHint': 'Das Ziel bestimmst du selbst; es wird nur lokal gespeichert. Leer lassen blendet die Ziellinie aus.',
  'goalLabel': 'Ziel',
  'goalPlaceholder': 'z. B. 60',
  'goalReached': 'Erreicht',
  'goalSheetTitle': 'Zielgewicht festlegen',
  'goalUnset': 'Kein Ziel',
  'grantPerm': 'Berechtigung erteilen',
  'heightLabel': 'Größe (cm)',
  'historySynced': '{n} Verlaufsmessungen von der Waage übernommen',
  'impedanceFailed': 'Keine Impedanzmessung erhalten',
  'impedanceRaw': 'Impedanz-Rohwert',
  'language': 'Sprache',
  'languageHint': 'Systemsprache folgen oder manuell wählen',
  'latest': 'Aktuell',
  'latestRecord': 'Letzte',
  'localEstimate': 'Lokale Schätzung',
  'lowWeightTag': 'Leichter Tritt?',
  'macFormat': 'MAC-Format ungültig (XX:XX:XX:XX:XX:XX)',
  'macHint': 'In den Bluetooth-Einstellungen sichtbar. Mit bekannter MAC ist kein Scan nötig.',
  'macLabel': 'MAC-Adresse des Geräts',
  'manualInput': 'Manuell',
  'manualMac': 'MAC-Adresse eingeben',
  'manufacturerLabel': 'Hersteller',
  'measuringWait': 'Auf die Waage stellen zum Messen',
  'modelLabel': 'Modell',
  'myDevices': 'Meine Geräte',
  'nameLabel': 'Name',
  'namePlaceholder': 'z. B. Ich',
  'needPermDesc': 'Ohne „Geräte in der Nähe / Standort“ ist kein Scan möglich',
  'needPermTitle': 'Bluetooth-Berechtigung nötig',
  'newUnitPlaceholder': 'Neuer Name',
  'noData': 'Keine Daten',
  'noDataDesc': 'Auf der Geräteseite messen und speichern',
  'noDeviceDesc': 'Scannen und hinzufügen oder MAC-Adresse manuell eingeben',
  'noDeviceTitle': 'Noch keine Waage verknüpft',
  'none': 'Keine',
  'notSynced': 'Nicht gesendet',
  'open': 'Öffnen',
  'openSource': 'Open Source',
  'openSourceDesc': 'Dieses Projekt ist Open Source; Quellcode und Build (GitHub Actions) sind öffentlich.',
  'optional': '(optional)',
  'pendingEmpty': 'Keine offenen Messungen',
  'pendingEmptyHint': 'Neue Messungen der Waage erscheinen hier',
  'pendingEntry': 'Offene Messungen',
  'pendingHint': 'Von der Waage übernommene Messungen – bitte Person zuordnen',
  'pendingTitle': 'Nicht zugeordnete Messungen',
  'phaseDone': 'Messung fertig',
  'phaseImpedance': 'Impedanzmessung',
  'phaseWeighing': 'Wiegen läuft',
  'privacyLine': 'Daten bleiben lokal und gehen an keine Dritten',
  'profileHint': 'Für die Körperfettberechnung nötig (Geschlecht/Alter/Größe)',
  'profileRequired': 'Bitte vollständig ausfüllen',
  'profileSave': 'Speichern & starten',
  'profileTitle': 'Körperdaten',
  'profilesHint': 'Körperdaten für die Waage – Benutzer für die Verbindung wählen',
  'profilesTitle': 'Benutzerverwaltung',
  'pullFromPc': 'Vom PC laden',
  'pullResult': 'Laden abgeschlossen',
  'pulling': 'Lade…',
  'pushFail': 'Senden fehlgeschlagen',
  'pushOk': 'Senden erfolgreich',
  'pushSelected': 'Senden',
  'pushStatus': 'Sendestatus',
  'pushUrl': 'Ziel-URL',
  'pushUrlHint': 'Am PC server_receiver.py starten und im selben WLAN sein. Die URL ist frei änderbar.',
  'pushing': 'Sende…',
  'range24h': '24H',
  'range30d': '30 Tage',
  'range7d': '7 Tage',
  'rangeAll': 'Alle',
  'rangeFrom': 'Startdatum',
  'rangeHint': 'Start- und Enddatum eingeben oder unten wählen',
  'rangeTo': 'Enddatum',
  'rangeToday': 'Heute',
  'recordCountSuffix': 'Einträge',
  'recordWriteFail': 'Speichern fehlgeschlagen',
  'records': 'Einträge',
  'refresh': 'Aktualisieren',
  'rename': 'Umbenennen',
  'save': 'Speichern',
  'saveFail': 'Speichern fehlgeschlagen',
  'saveGoal': 'Ziel speichern',
  'saveMeasurement': 'Messung speichern',
  'saveUrl': 'URL speichern',
  'saved': 'Gespeichert:',
  'saving': 'Speichern…',
  'scanAndAdd': 'Scannen & hinzufügen',
  'scanningHint': 'Bei der ersten Kopplung die Waage kurz antippen, bis das Display angeht, dann ruhig liegen lassen. Es dauert ca. 3–5 Minuten, bis sie aufwacht und sendet. Wenn Sie die Bluetooth-MAC-Adresse kennen, empfiehlt sich die manuelle Verbindung.',
  'scanningNew': 'Suche nach neuen Geräten…',
  'selectAll': 'Alle wählen',
  'selectAllUnsynced': 'Alle ungesendeten',
  'selectDate': 'Datum wählen',
  'selectFirst': 'Bitte Einträge zum Senden auswählen',
  'setGoal': 'Ziel setzen',
  'sexFemale': 'Weiblich',
  'sexLabel': 'Geschlecht',
  'sexMale': 'Männlich',
  'standOnScale': 'Auf die Waage stellen zum Messen',
  'start': 'Start',
  'stateConnected': 'Verbunden',
  'stateConnecting': 'Verbinde…',
  'stateError': 'Verbindungsfehler',
  'stateIdle': 'Nicht verbunden',
  'stopScan': 'Scan stoppen',
  'syncSettings': 'Synchronisierung',
  'synced': 'Gesendet',
  'tabData': 'Daten',
  'tabDevice': 'Gerät',
  'tabSettings': 'Einstellungen',
  'testConn': 'Verbindung testen',
  'testing': 'Teste…',
  'toGoal': 'Bis Ziel',
  'totalRecords': 'Einträge',
  'transferHint': 'Ausgewählte Daten wem zuordnen? (Körperfett neu messen nötig)',
  'transferTo': 'Übertragen an',
  'trend': 'Gewichtsverlauf',
  'unbind': 'Verknüpfung lösen',
  'unitDisplayHint': 'Anzeige- und Sende-Einheit (DB speichert immer kg)',
  'unitJin': 'Jin (chinesisches Pfund)',
  'unitKg': 'kg (Kilogramm)',
  'unitLb': 'lb (Pfund)',
  'unitSection2': 'Einheit',
  'unitsHint': 'Bei mehreren Nutzern kann beim Speichern zugeordnet werden',
  'unitsLabel': 'Personen',
  'unitsSection': 'Personen',
  'unofficial': 'Keine offizielle Hersteller-App',
  'unselectAll': 'Auswahl aufheben',
  'unsynced': 'Ungesendet',
  'weightLabel': 'Gewicht (kg)',
  'weightUnit': 'kg',
  'whoIsThis': 'Zu wem gehört diese Messung?',
  'startWeighing': 'Wiegen',
  'measuringTitle': 'Messung',
  'currentMeasurer': 'Messperson',
  'switchLabel': 'Wechseln',
  'selectDevice': 'Waage wählen',
  'rescanDevice': 'Neu suchen',
  'appearance': 'Darstellung',
  'darkMode': 'Dunkelmodus',
  'themeLight': 'Hell',
  'themeDark': 'Dunkel',
  'themeSystem': 'System',
  'setGoalShort': 'Ziel setzen',
  'nextStep': 'Weiter',
  'skipForNow': 'Überspringen',
  'bindScaleTitle': 'Waage koppeln',
  'bindScaleHint': 'Kurz auf die Waage treten, um sie zu wecken, und Gerät auswählen.',
  'noImpedanceTitle': 'Keine Impedanz · Nur Gewicht',
  'noImpedanceDesc': 'Barfuß auf alle 4 Elektroden stellen oder nur Gewicht speichern.',
  'remeasure': 'Neu messen',
  'saveWeightOnly': 'Nur Gewicht',
  'placeFeetHint': 'Barfuß auf die 4 Elektroden stellen',
  'electrodeReadyHint': 'Elektroden aktiv · Ruhig stehen',
  'ageSuffix': 'J.',
  'listView': 'Liste',
  'filterShort': 'Filter',
  'incompleteSection': 'Unvollständige Messung',
  'incompleteHint': 'Verhalten ohne Impedanz (langes Drücken in der Messung setzt Standard)',
  'policyAsk': 'Immer fragen',
  'policySave': 'Nur Gewicht',
  'policySkip': 'Nicht speichern',
  'fixOwnership': 'Zuordnung reparieren',
  'noOrphan': 'Nichts zu reparieren',
  'fixOwnershipHint': 'Diese Messungen gehören zu einem gelöschten Mitglied. Ziel wählen zum Wiederherstellen.',
  'assignToWhom': 'Wem zuordnen',
  'unnamed': '(ohne Name)',
  'recordsUnit': 'Einträge',
  'tapToStart': 'Zum Starten tippen',
  'exitUnsavedTitle': 'Messung nicht gespeichert',
  'keepMeasuring': 'Weiter messen',
  'exitApp': 'Beenden',
  'scanNotFoundTitle': 'Waage nicht verbunden',
  'scanNotFoundDesc': 'Keine verknüpfte Waage in 5 s gefunden. In der Nähe suchen?',
  'searchDevice': 'Suchen',
  'longPressDefault': 'Lange drücken setzt den Standard',
  'setDefaultSave': 'Standard: nur Gewicht',
  'setDefaultSkip': 'Standard: nicht speichern',
  'filterRangeTitle': 'Zeitraum filtern',
  'noSavedRanges': 'Noch keine Zeiträume gespeichert. Unten „Datum wählen“ erstellt einen; gewählte Zeiträume werden automatisch gespeichert.',
  'plsCreateProfile': 'Zuerst ein Mitglied anlegen',
  'exitUnsavedDesc': 'Keine vollständige Impedanz – nichts gespeichert. Beenden?',
  'doneRetry': 'Fertig · erneut tippen für neue Messung',
  'needBind': 'Zuerst eine Waage verknüpfen',
  'savedMsg': 'Gespeichert',
  'bfEstimate': 'Körperfett (geschätzt)',
  'myScale': 'Waage',
  'searchingNearby': 'Suche AFU-Waagen in der Nähe…',
  'noDeviceFound': 'Kein Gerät gefunden – Waage kurz antippen und erneut suchen',
  'calcModel': 'Berechnungsmodell',
  'calcModelValue': 'Eigene Formel, abweichend',
  'calcModelHint': 'Körperzusammensetzung wie Körperfett wird mit einer eigenen Schätzformel dieser App berechnet. Die offizielle App veröffentlicht ihren Algorithmus nicht, daher können die Werte von der offiziellen App abweichen (meist wenige Prozentpunkte). Gewicht und BMI sind Messwerte und nicht betroffen.',
  'birthdayLabel': 'Geburtsdatum',
  'birthdayHint': 'Tippen, um das Geburtsdatum zu wählen',
  'ageAutoCalc': 'Alter automatisch berechnet: {n} Jahre',
  'birthdayKeepHint': 'Leer lassen, um das aktuelle Alter zu behalten',
  'birthdayCurrentAge': 'Aktuell {n} Jahre',
  'birthdayTapToChange': 'Tippen, um das Geburtsdatum neu zu setzen',
};

const Map<String, String> _en = {
  'about': 'About',
  'activeProfileLabel': 'User for scale connection',
  'adaptation': 'Model: AFU-WL-TZ-A1 (ICOMON / Ant Afu Welland)',
  'add': 'Add',
  'addDevice': 'Add Device',
  'addProfile': 'Add user',
  'ageLabel': 'Age',
  'algorithm': 'Algorithm',
  'all': 'All',
  'appTagline': 'Body Composition Scale',
  'applyRange': 'Apply',
  'assignTo': 'Assign to',
  'back': 'Back',
  'batteryLabel': 'Battery',
  'bcBone': 'Bone',
  'bcFat': 'Body fat',
  'bcMuscle': 'Muscle',
  'bcProtein': 'Protein',
  'bcSkeletal': 'Skeletal muscle',
  'bcWater': 'Water',
  'bodyComp': 'Body Composition',
  'bodyCompLocal': 'Body Composition (local BIA estimate)',
  'boundDevices': 'Bound Devices',
  'boundTag': 'Bound',
  'brand': 'AFU',
  'brandSub': 'Body Scale',
  'byDate': 'By date',
  'cancel': 'Cancel',
  'change': 'Change',
  'clear': 'Clear',
  'clearDateFilter': 'Clear date filter',
  'clearGoal': 'Clear',
  'close': 'Close',
  'collapse': 'Collapse',
  'compUnavailable': 'Body data unavailable (electrodes not in contact)',
  'confirm': 'OK',
  'connFail': 'Connection failed',
  'connOk': 'Connection OK',
  'connectDirect': 'Connect Directly',
  'connectState': 'Connection',
  'connecting': 'Connecting…',
  'copiedMac': 'MAC copied',
  'credits': 'Credits',
  'creditsDesc': 'The protocol details of this project were cross-validated against the following public reverse-engineering work. With thanks:',
  'creditsLicense': 'All projects are MIT licensed. This app follows the same open-source spirit.',
  'customRange': 'Custom',
  'days': 'days',
  'debugLog': 'Debug Log',
  'delete': 'Delete',
  'deselectAll': 'Deselect all',
  'detailTitle': 'Measurement Detail',
  'devBoundAt': 'Bound on',
  'devMac': 'MAC',
  'devModel': 'Model',
  'devName': 'Name',
  'deviceInfo': 'Device Info',
  'deviceInfoHint': 'Read on connect and cached locally',
  'deviceInfoTitle': 'Device Info',
  'discardSelected': 'Discard selected',
  'editProfile': 'Edit',
  'electrodeOff': '⚠ Electrodes not in contact · stand barefoot on all four',
  'electrodeOffShort': 'No contact (no impedance)',
  'electrodeOn': 'In contact',
  'estimateLine': 'Body fat etc. are local BIA estimates, for reference only',
  'expandMore': 'Show more',
  'filterByRange': 'Time Range',
  'filterByUnit': 'Filter by person',
  'firmwareLabel': 'Firmware',
  'followSystem': 'Follow system',
  'ghRepo': 'GitHub Repository',
  'goalHint': 'You decide the goal; it is stored locally only. Leave empty to hide the goal line.',
  'goalLabel': 'Goal',
  'goalPlaceholder': 'e.g. 60',
  'goalReached': 'Reached',
  'goalSheetTitle': 'Set Goal Weight',
  'goalUnset': 'No goal',
  'grantPerm': 'Grant Permission',
  'heightLabel': 'Height (cm)',
  'historySynced': 'Imported {n} history records from the scale',
  'impedanceFailed': 'No impedance measured this time',
  'impedanceRaw': 'Raw impedance',
  'language': 'Language',
  'languageHint': 'Follow the system language or pick one manually',
  'latest': 'Latest',
  'latestRecord': 'Latest',
  'localEstimate': 'Local estimate',
  'lowWeightTag': 'Light step?',
  'macFormat': 'Invalid MAC format (XX:XX:XX:XX:XX:XX)',
  'macHint': 'Visible in system Bluetooth settings. A known MAC needs no scan.',
  'macLabel': 'Device MAC Address',
  'manualInput': 'Manual',
  'manualMac': 'Enter MAC Address',
  'manufacturerLabel': 'Manufacturer',
  'measuringWait': 'Step on the scale to measure',
  'modelLabel': 'Model',
  'myDevices': 'My Devices',
  'nameLabel': 'Name',
  'namePlaceholder': 'e.g. Me',
  'needPermDesc': 'Scanning needs "Nearby devices / Location" permission',
  'needPermTitle': 'Bluetooth permission required',
  'newUnitPlaceholder': 'New person name',
  'noData': 'No data',
  'noDataDesc': 'Measure and save on the Device page',
  'noDeviceDesc': 'Scan to add, or enter the MAC address manually',
  'noDeviceTitle': 'No scale bound yet',
  'none': 'None',
  'notSynced': 'Not synced',
  'open': 'Open',
  'openSource': 'Open Source',
  'openSourceDesc': 'This project is open source; code and CI build (GitHub Actions) are public.',
  'optional': '(optional)',
  'pendingEmpty': 'No pending records',
  'pendingEmptyHint': 'New scale measurements will appear here',
  'pendingEntry': 'Pending history',
  'pendingHint': 'Measurements imported from the scale — choose who they belong to',
  'pendingTitle': 'Unassigned History',
  'phaseDone': 'Complete',
  'phaseImpedance': 'Measuring impedance',
  'phaseWeighing': 'Weighing',
  'privacyLine': 'Data stays on this device; nothing is sent to third parties',
  'profileHint': 'Required for body-fat calculation (sex / age / height)',
  'profileRequired': 'Please fill in all fields to start',
  'profileSave': 'Save & Start',
  'profileTitle': 'Body Data',
  'profilesHint': 'Body data sent to the scale — pick who connects',
  'profilesTitle': 'User Profiles',
  'pullFromPc': 'Pull from PC',
  'pullResult': 'Pull finished',
  'pulling': 'Pulling…',
  'pushFail': 'Push failed',
  'pushOk': 'Pushed successfully',
  'pushSelected': 'Push',
  'pushStatus': 'Push status',
  'pushUrl': 'Push URL',
  'pushUrlHint': 'Run server_receiver.py on your PC and stay on the same Wi-Fi. The URL is editable.',
  'pushing': 'Pushing…',
  'range24h': '24H',
  'range30d': '30 days',
  'range7d': '7 days',
  'rangeAll': 'All',
  'rangeFrom': 'Start date',
  'rangeHint': 'Enter start/end date or tap a date below',
  'rangeTo': 'End date',
  'rangeToday': 'Today',
  'recordCountSuffix': 'items',
  'recordWriteFail': 'Failed to write record',
  'records': 'Records',
  'refresh': 'Refresh',
  'rename': 'Rename',
  'save': 'Save',
  'saveFail': 'Save failed',
  'saveGoal': 'Save Goal',
  'saveMeasurement': 'Save Measurement',
  'saveUrl': 'Save URL',
  'saved': 'Saved:',
  'saving': 'Saving…',
  'scanAndAdd': 'Scan & Add Device',
  'scanningHint': 'For first-time pairing, lightly tap the scale to light the screen and leave it still. It takes about 3-5 minutes to wake and start advertising. If you know the Bluetooth MAC address, manual connection is recommended.',
  'scanningNew': 'Searching for new devices…',
  'selectAll': 'Select all',
  'selectAllUnsynced': 'Select all unsent',
  'selectDate': 'Select date',
  'selectFirst': 'Select records to push first',
  'setGoal': 'Set Goal',
  'sexFemale': 'Female',
  'sexLabel': 'Sex',
  'sexMale': 'Male',
  'standOnScale': 'Step on the scale to measure',
  'start': 'Start',
  'stateConnected': 'Connected',
  'stateConnecting': 'Connecting…',
  'stateError': 'Connection failed',
  'stateIdle': 'Not connected',
  'stopScan': 'Stop Scan',
  'syncSettings': 'Sync Settings',
  'synced': 'Synced',
  'tabData': 'Data',
  'tabDevice': 'Device',
  'tabSettings': 'Settings',
  'testConn': 'Test Connection',
  'testing': 'Testing…',
  'toGoal': 'To Goal',
  'totalRecords': 'Records',
  'transferHint': 'Assign selected records to whom? (body composition will need remeasuring)',
  'transferTo': 'Transfer to',
  'trend': 'Weight Trend',
  'unbind': 'Unbind',
  'unitDisplayHint': 'Display & send unit (database always stores kg)',
  'unitJin': 'jin (Chinese pound)',
  'unitKg': 'kg (kilogram)',
  'unitLb': 'lb (pound)',
  'unitSection2': 'Unit',
  'unitsHint': 'When several people share a scale, pick the owner when saving',
  'unitsLabel': 'People',
  'unitsSection': 'People',
  'unofficial': 'Not an official vendor app',
  'unselectAll': 'Deselect all',
  'unsynced': 'Unsent',
  'weightLabel': 'Weight (kg)',
  'weightUnit': 'kg',
  'whoIsThis': 'Who is this measurement for?',
  'startWeighing': 'Weigh',
  'measuringTitle': 'Measure',
  'currentMeasurer': 'Measurer',
  'switchLabel': 'Switch',
  'selectDevice': 'Select Scale',
  'rescanDevice': 'Scan Again',
  'appearance': 'Appearance',
  'darkMode': 'Dark Mode',
  'themeLight': 'Light',
  'themeDark': 'Dark',
  'themeSystem': 'System',
  'setGoalShort': 'Set Goal',
  'nextStep': 'Next',
  'skipForNow': 'Skip for now',
  'bindScaleTitle': 'Bind Your Scale',
  'bindScaleHint': 'Tap the scale to wake it, then select the discovered device below.',
  'noImpedanceTitle': 'No Impedance · Weight Only',
  'noImpedanceDesc': 'Step off and stand barefoot on all 4 electrodes, or save weight only.',
  'remeasure': 'Measure Again',
  'saveWeightOnly': 'Save Weight',
  'placeFeetHint': 'Stand barefoot on all 4 electrodes',
  'electrodeReadyHint': 'Electrodes active · Hold still',
  'ageSuffix': 'y',
  'listView': 'List',
  'filterShort': 'Filter',
  'incompleteSection': 'Incomplete Measurement',
  'incompleteHint': 'What to do when impedance is missing (long-press in Measure to set default)',
  'policyAsk': 'Ask every time',
  'policySave': 'Weight only',
  'policySkip': 'Do not save',
  'fixOwnership': 'Repair Record Owner',
  'noOrphan': 'Nothing to repair',
  'fixOwnershipHint': 'These records belong to a deleted member. Pick a target to restore them.',
  'assignToWhom': 'Assign to',
  'unnamed': '(unnamed)',
  'recordsUnit': 'records',
  'tapToStart': 'Tap to start measuring',
  'exitUnsavedTitle': 'Measurement not saved',
  'keepMeasuring': 'Keep measuring',
  'exitApp': 'Exit',
  'scanNotFoundTitle': 'Scale not connected',
  'scanNotFoundDesc': 'No bound scale found within 5 seconds. Search nearby?',
  'searchDevice': 'Search',
  'longPressDefault': 'Long-press to set as default',
  'setDefaultSave': 'Default set: weight only',
  'setDefaultSkip': 'Default set: do not save',
  'filterRangeTitle': 'Filter by Date Range',
  'noSavedRanges': 'No saved ranges yet. Use “Pick dates” below; chosen ranges are saved automatically.',
  'plsCreateProfile': 'Create a member first',
  'exitUnsavedDesc': 'No full impedance was measured, so nothing was saved. Exit anyway?',
  'doneRetry': 'Done · tap again to re-measure',
  'needBind': 'Bind a scale first',
  'savedMsg': 'Saved',
  'bfEstimate': 'Body fat (est.)',
  'myScale': 'Scale',
  'searchingNearby': 'Searching nearby AFU scales…',
  'noDeviceFound': 'No device found — tap the scale to wake it and retry',
  'calcModel': 'Calculation model',
  'calcModelValue': 'Custom formula, not official',
  'calcModelHint': 'Body composition such as body fat is estimated with this app\'s own formula. The official app does not disclose its algorithm, so values may differ from the official app (usually within a few percentage points). Weight and BMI are measured values and are unaffected.',
  'birthdayLabel': 'Date of birth',
  'birthdayHint': 'Tap to choose date of birth',
  'ageAutoCalc': 'Age calculated automatically: {n}',
  'birthdayKeepHint': 'Leave empty to keep the current age',
  'birthdayCurrentAge': 'Currently {n} years',
  'birthdayTapToChange': 'Tap to set date of birth',
};


/// 文案访问器 —— 每个键一个 getter（Dart camelCase）。
///
/// 用法：`S.of(context).brand`。缺翻译回退到日语。
class S {
  /// 当前语言码（已解析，非 `system`）。
  final String langCode;

  /// 当前语言的键值表。
  final Map<String, String> _strings;

  /// 用具体语言码构造；不在支持列表则回退 [fallbackLangCode]。
  S(String code)
      : langCode = supportedLangCodes.contains(code) ? code : fallbackLangCode,
        _strings = _allStrings[supportedLangCodes.contains(code) ? code : fallbackLangCode]!;

  /// 从 widget 树获取当前语言的 [S]。
  static S of(BuildContext context) => S(AppLocale.of(context).resolvedCode);

  /// 当前语言的原生名称（设置页显示用）。
  String get nativeName {
    switch (langCode) {
      case 'zh-Hans': return '简体中文';
      case 'zh-Hant': return '繁體中文';
      case 'ja': return '日本語';
      case 'de': return 'Deutsch';
      case 'en': return 'English';
      default: return '日本語';
    }
  }

  String get about => _strings['about']!;
  String get activeProfileLabel => _strings['activeProfileLabel']!;
  String get adaptation => _strings['adaptation']!;
  String get add => _strings['add']!;
  String get addDevice => _strings['addDevice']!;
  String get addProfile => _strings['addProfile']!;
  String get ageLabel => _strings['ageLabel']!;
  String get birthdayLabel => _strings['birthdayLabel']!;
  String get birthdayHint => _strings['birthdayHint']!;
  String get birthdayKeepHint => _strings['birthdayKeepHint']!;
  String get birthdayTapToChange => _strings['birthdayTapToChange']!;
  String birthdayCurrentAge(int n) => (_strings['birthdayCurrentAge'] ?? '').replaceAll('{n}', '$n');
  String ageAutoCalc(int n) => (_strings['ageAutoCalc'] ?? '').replaceAll('{n}', '$n');
  String get algorithm => _strings['algorithm']!;
  String get all => _strings['all']!;
  String get appTagline => _strings['appTagline']!;
  String get applyRange => _strings['applyRange']!;
  String get assignTo => _strings['assignTo']!;
  String get back => _strings['back']!;
  String get batteryLabel => _strings['batteryLabel']!;
  String get bcBone => _strings['bcBone']!;
  String get bcFat => _strings['bcFat']!;

  /// 体脂率别名（= [bcFat]），兼容 UI 层 s.bodyFat 用法。
  String get bodyFat => _strings['bcFat']!;
  String get bcMuscle => _strings['bcMuscle']!;
  String get bcProtein => _strings['bcProtein']!;
  String get bcSkeletal => _strings['bcSkeletal']!;
  String get bcWater => _strings['bcWater']!;
  String get bodyComp => _strings['bodyComp']!;
  String get bodyCompLocal => _strings['bodyCompLocal']!;
  String get boundDevices => _strings['boundDevices']!;
  String get boundTag => _strings['boundTag']!;
  String get brand => _strings['brand']!;
  String get brandSub => _strings['brandSub']!;
  String get byDate => _strings['byDate']!;
  String get cancel => _strings['cancel']!;
  String get change => _strings['change']!;
  String get clear => _strings['clear']!;
  String get clearDateFilter => _strings['clearDateFilter']!;
  String get clearGoal => _strings['clearGoal']!;
  String get close => _strings['close']!;
  String get collapse => _strings['collapse']!;
  String get compUnavailable => _strings['compUnavailable']!;
  String get confirm => _strings['confirm']!;
  String get connFail => _strings['connFail']!;
  String get connOk => _strings['connOk']!;
  String get connectDirect => _strings['connectDirect']!;
  String get connectState => _strings['connectState']!;
  String get connecting => _strings['connecting']!;
  String get copiedMac => _strings['copiedMac']!;
  String get credits => _strings['credits']!;
  String get calcModel => _strings['calcModel']!;
  String get calcModelValue => _strings['calcModelValue']!;
  String get calcModelHint => _strings['calcModelHint']!;
  String get creditsDesc => _strings['creditsDesc']!;
  String get creditsLicense => _strings['creditsLicense']!;
  String get customRange => _strings['customRange']!;
  String get days => _strings['days']!;
  String get debugLog => _strings['debugLog']!;
  String get delete => _strings['delete']!;
  String get deselectAll => _strings['deselectAll']!;
  String get detailTitle => _strings['detailTitle']!;
  String get devBoundAt => _strings['devBoundAt']!;
  String get devMac => _strings['devMac']!;
  String get devModel => _strings['devModel']!;
  String get devName => _strings['devName']!;
  String get deviceInfo => _strings['deviceInfo']!;
  String get deviceInfoHint => _strings['deviceInfoHint']!;
  String get deviceInfoTitle => _strings['deviceInfoTitle']!;
  String get discardSelected => _strings['discardSelected']!;
  String get editProfile => _strings['editProfile']!;
  String get electrodeOff => _strings['electrodeOff']!;
  String get electrodeOffShort => _strings['electrodeOffShort']!;
  String get electrodeOn => _strings['electrodeOn']!;
  String get estimateLine => _strings['estimateLine']!;
  String get expandMore => _strings['expandMore']!;
  String get filterByRange => _strings['filterByRange']!;
  String get filterByUnit => _strings['filterByUnit']!;
  String get firmwareLabel => _strings['firmwareLabel']!;
  String get followSystem => _strings['followSystem']!;
  String get ghRepo => _strings['ghRepo']!;
  String get goalHint => _strings['goalHint']!;
  String get goalLabel => _strings['goalLabel']!;
  String get goalPlaceholder => _strings['goalPlaceholder']!;
  String get goalReached => _strings['goalReached']!;
  String get goalSheetTitle => _strings['goalSheetTitle']!;
  String get goalUnset => _strings['goalUnset']!;
  String get grantPerm => _strings['grantPerm']!;
  String get heightLabel => _strings['heightLabel']!;
  String get impedanceFailed => _strings['impedanceFailed']!;
  String get impedanceRaw => _strings['impedanceRaw']!;
  String get language => _strings['language']!;
  String get languageHint => _strings['languageHint']!;
  String get latest => _strings['latest']!;
  String get latestRecord => _strings['latestRecord']!;
  String get localEstimate => _strings['localEstimate']!;
  String get lowWeightTag => _strings['lowWeightTag']!;
  String get macFormat => _strings['macFormat']!;
  String get macHint => _strings['macHint']!;
  String get macLabel => _strings['macLabel']!;
  String get manualInput => _strings['manualInput']!;
  String get manualMac => _strings['manualMac']!;
  String get manufacturerLabel => _strings['manufacturerLabel']!;
  String get measuringWait => _strings['measuringWait']!;
  String get modelLabel => _strings['modelLabel']!;
  String get myDevices => _strings['myDevices']!;
  String get nameLabel => _strings['nameLabel']!;
  String get namePlaceholder => _strings['namePlaceholder']!;
  String get needPermDesc => _strings['needPermDesc']!;
  String get needPermTitle => _strings['needPermTitle']!;
  String get newUnitPlaceholder => _strings['newUnitPlaceholder']!;
  String get noData => _strings['noData']!;
  String get noDataDesc => _strings['noDataDesc']!;
  String get noDeviceDesc => _strings['noDeviceDesc']!;
  String get noDeviceTitle => _strings['noDeviceTitle']!;
  String get none => _strings['none']!;
  String get notSynced => _strings['notSynced']!;
  String get open => _strings['open']!;
  String get openSource => _strings['openSource']!;
  String get openSourceDesc => _strings['openSourceDesc']!;
  String get optional => _strings['optional']!;
  String get pendingEmpty => _strings['pendingEmpty']!;
  String get pendingEmptyHint => _strings['pendingEmptyHint']!;
  String get pendingEntry => _strings['pendingEntry']!;
  String get pendingHint => _strings['pendingHint']!;
  String get pendingTitle => _strings['pendingTitle']!;
  String get phaseDone => _strings['phaseDone']!;
  String get phaseImpedance => _strings['phaseImpedance']!;
  String get phaseWeighing => _strings['phaseWeighing']!;
  String get privacyLine => _strings['privacyLine']!;
  String get profileHint => _strings['profileHint']!;
  String get profileRequired => _strings['profileRequired']!;
  String get profileSave => _strings['profileSave']!;
  String get profileTitle => _strings['profileTitle']!;
  String get profilesHint => _strings['profilesHint']!;
  String get profilesTitle => _strings['profilesTitle']!;
  String get pullFromPc => _strings['pullFromPc']!;
  String get pullResult => _strings['pullResult']!;
  String get pulling => _strings['pulling']!;
  String get pushFail => _strings['pushFail']!;
  String get pushOk => _strings['pushOk']!;
  String get pushSelected => _strings['pushSelected']!;
  String get pushStatus => _strings['pushStatus']!;
  String get pushUrl => _strings['pushUrl']!;
  String get pushUrlHint => _strings['pushUrlHint']!;
  String get pushing => _strings['pushing']!;
  String get range24h => _strings['range24h']!;
  String get range30d => _strings['range30d']!;
  String get range7d => _strings['range7d']!;
  String get rangeAll => _strings['rangeAll']!;
  String get rangeFrom => _strings['rangeFrom']!;
  String get rangeHint => _strings['rangeHint']!;
  String get rangeTo => _strings['rangeTo']!;
  String get rangeToday => _strings['rangeToday']!;
  String get recordCountSuffix => _strings['recordCountSuffix']!;
  String get recordWriteFail => _strings['recordWriteFail']!;
  String get records => _strings['records']!;
  String get refresh => _strings['refresh']!;
  String get rename => _strings['rename']!;
  String get save => _strings['save']!;
  String get saveFail => _strings['saveFail']!;
  String get saveGoal => _strings['saveGoal']!;
  String get saveMeasurement => _strings['saveMeasurement']!;
  String get saveUrl => _strings['saveUrl']!;
  String get saved => _strings['saved']!;
  String get saving => _strings['saving']!;
  String get scanAndAdd => _strings['scanAndAdd']!;
  String get scanningHint => _strings['scanningHint']!;
  String get scanningNew => _strings['scanningNew']!;
  String get selectAll => _strings['selectAll']!;
  String get selectAllUnsynced => _strings['selectAllUnsynced']!;
  String get selectDate => _strings['selectDate']!;
  String get selectFirst => _strings['selectFirst']!;
  String get setGoal => _strings['setGoal']!;
  String get sexFemale => _strings['sexFemale']!;
  String get sexLabel => _strings['sexLabel']!;
  String get sexMale => _strings['sexMale']!;
  String get standOnScale => _strings['standOnScale']!;
  String get start => _strings['start']!;
  String get stateConnected => _strings['stateConnected']!;
  String get stateConnecting => _strings['stateConnecting']!;
  String get stateError => _strings['stateError']!;
  String get stateIdle => _strings['stateIdle']!;
  String get stopScan => _strings['stopScan']!;
  String get syncSettings => _strings['syncSettings']!;
  String get synced => _strings['synced']!;
  String get tabData => _strings['tabData']!;
  String get tabDevice => _strings['tabDevice']!;
  String get tabSettings => _strings['tabSettings']!;
  String get testConn => _strings['testConn']!;
  String get testing => _strings['testing']!;
  String get toGoal => _strings['toGoal']!;
  String get totalRecords => _strings['totalRecords']!;
  String get transferHint => _strings['transferHint']!;
  String get transferTo => _strings['transferTo']!;
  String get trend => _strings['trend']!;
  String get unbind => _strings['unbind']!;
  String get unitDisplayHint => _strings['unitDisplayHint']!;
  String get unitJin => _strings['unitJin']!;
  String get unitKg => _strings['unitKg']!;
  String get unitLb => _strings['unitLb']!;
  String get unitSection2 => _strings['unitSection2']!;
  String get unitsHint => _strings['unitsHint']!;
  String get unitsLabel => _strings['unitsLabel']!;
  String get unitsSection => _strings['unitsSection']!;
  String get unofficial => _strings['unofficial']!;
  String get unselectAll => _strings['unselectAll']!;
  String get unsynced => _strings['unsynced']!;
  String get weightLabel => _strings['weightLabel']!;
  String get weightUnit => _strings['weightUnit']!;
  String get whoIsThis => _strings['whoIsThis']!;

  String get startWeighing => _strings['startWeighing']!;
  String get measuringTitle => _strings['measuringTitle']!;
  String get currentMeasurer => _strings['currentMeasurer']!;
  String get switchLabel => _strings['switchLabel']!;
  String get selectDevice => _strings['selectDevice']!;
  String get rescanDevice => _strings['rescanDevice']!;
  String get appearance => _strings['appearance']!;
  String get darkMode => _strings['darkMode']!;
  String get themeLight => _strings['themeLight']!;
  String get themeDark => _strings['themeDark']!;
  String get themeSystem => _strings['themeSystem']!;
  String get setGoalShort => _strings['setGoalShort']!;
  String get nextStep => _strings['nextStep']!;
  String get skipForNow => _strings['skipForNow']!;
  String get bindScaleTitle => _strings['bindScaleTitle']!;
  String get bindScaleHint => _strings['bindScaleHint']!;
  String get noImpedanceTitle => _strings['noImpedanceTitle']!;
  String get noImpedanceDesc => _strings['noImpedanceDesc']!;
  String get remeasure => _strings['remeasure']!;
  String get saveWeightOnly => _strings['saveWeightOnly']!;
  String get placeFeetHint => _strings['placeFeetHint']!;
  String get electrodeReadyHint => _strings['electrodeReadyHint']!;

  String get ageSuffix => _strings['ageSuffix']!;
  String get listView => _strings['listView']!;
  String get filterShort => _strings['filterShort']!;
  String get incompleteSection => _strings['incompleteSection']!;
  String get incompleteHint => _strings['incompleteHint']!;
  String get policyAsk => _strings['policyAsk']!;
  String get policySave => _strings['policySave']!;
  String get policySkip => _strings['policySkip']!;
  String get fixOwnership => _strings['fixOwnership']!;
  String get noOrphan => _strings['noOrphan']!;
  String get fixOwnershipHint => _strings['fixOwnershipHint']!;
  String get assignToWhom => _strings['assignToWhom']!;
  String get unnamed => _strings['unnamed']!;
  String get recordsUnit => _strings['recordsUnit']!;
  String get tapToStart => _strings['tapToStart']!;
  String get exitUnsavedTitle => _strings['exitUnsavedTitle']!;
  String get keepMeasuring => _strings['keepMeasuring']!;
  String get exitApp => _strings['exitApp']!;
  String get scanNotFoundTitle => _strings['scanNotFoundTitle']!;
  String get scanNotFoundDesc => _strings['scanNotFoundDesc']!;
  String get searchDevice => _strings['searchDevice']!;
  String get longPressDefault => _strings['longPressDefault']!;
  String get setDefaultSave => _strings['setDefaultSave']!;
  String get setDefaultSkip => _strings['setDefaultSkip']!;
  String get filterRangeTitle => _strings['filterRangeTitle']!;
  String get noSavedRanges => _strings['noSavedRanges']!;
  String get plsCreateProfile => _strings['plsCreateProfile']!;

  String get exitUnsavedDesc => _strings['exitUnsavedDesc']!;
  String get doneRetry => _strings['doneRetry']!;
  String get needBind => _strings['needBind']!;
  String get savedMsg => _strings['savedMsg']!;

  String get bfEstimate => _strings['bfEstimate']!;
  String get myScale => _strings['myScale']!;
  String get searchingNearby => _strings['searchingNearby']!;
  String get noDeviceFound => _strings['noDeviceFound']!;

  /// 带 {n} 占位符的文案：`historySynced`。
  String historySynced(int n) =>
      _strings['historySynced']!.replaceAll('{n}', '$n');
}
