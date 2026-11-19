/// 应用版本号 —— 与 pubspec.yaml 的 version 保持一致。
///
/// 没有引入 package_info_plus（避免额外依赖与网络拉取），
/// 因此这里是唯一来源：改 pubspec 时同步改这一行。
const String kAppVersion = '0.3.2';
