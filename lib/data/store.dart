// 存储层 —— 基于 shared_preferences 的 JSON 持久化
// 键名与默认值集中在此，全 App 共用。
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import '../core/bodycomp.dart';

/// 存储键常量。
class StoreKeys {
  static const themeMode = 'afu_theme_mode';
  static const preferredDevice = 'afu_preferred_device';
  static const incompletePolicy = 'afu_incomplete_policy';
  static const bfAlgo = 'afu_bf_algo';
  static const customRanges = 'afu_custom_ranges';
  static const debugMode = 'afu_debug_mode';
  static const autoAssignHistory = 'afu_auto_assign_history';
  static const profiles = 'afu_profiles';
  static const activeProfile = 'afu_active_profile';
  static const records = 'afu_records';
  static const goals = 'afu_goals';
  static const displayUnit = 'afu_display_unit';
  static const pending = 'afu_pending';
  static const devices = 'afu_devices';
  static const syncUrl = 'afu_sync_url';

  /// 默认同步地址。
  static const defaultSyncUrl = 'http://192.168.1.100:8765/records';
}

/// 目标体重 JSON 结构：{ weightKg: double, enabled: bool }
class GoalWeight {
  final double weightKg;
  final bool enabled;
  const GoalWeight({required this.weightKg, this.enabled = false});
  Map<String, dynamic> toJson() => {'weightKg': weightKg, 'enabled': enabled};
  factory GoalWeight.fromJson(Map<String, dynamic> j) => GoalWeight(
        weightKg: (j['weightKg'] as num?)?.toDouble() ?? 0,
        enabled: j['enabled'] as bool? ?? false,
      );
}

/// 从 SharedPreferences 读 JSON 并解码为 [T] 列表。
List<T> _decodeList<T>(
  SharedPreferences prefs,
  String key,
  T Function(Map<String, dynamic>) fromJson,
) {
  final raw = prefs.getString(key);
  if (raw == null || raw.isEmpty) return <T>[];
  try {
    final data = jsonDecode(raw);
    if (data is! List) return <T>[];
    return data
        .whereType<Map>()
        .map((m) => fromJson(Map<String, dynamic>.from(m)))
        .toList();
  } catch (_) {
    return <T>[];
  }
}

/// 将 [list] 编码为 JSON 字符串并写入 [key]。
Future<void> _writeList<T>(
  SharedPreferences prefs,
  String key,
  List<T> list,
  Map<String, dynamic> Function(T) toJson,
) async {
  final encoded = jsonEncode(list.map(toJson).toList());
  await prefs.setString(key, encoded);
}

/// 用户档案。
Future<List<UserProfile>> getProfiles() async {
  final prefs = await SharedPreferences.getInstance();
  return _decodeList(prefs, StoreKeys.profiles, UserProfile.fromJson);
}

/// 保存整个用户档案列表。
Future<void> saveProfiles(List<UserProfile> profiles) async {
  final prefs = await SharedPreferences.getInstance();
  await _writeList(prefs, StoreKeys.profiles, profiles, (p) => p.toJson());
}

/// 新增或更新一个档案（按 name 匹配）。
Future<void> upsertProfile(UserProfile profile) async {
  final profiles = await getProfiles();
  final idx = profiles.indexWhere((p) => p.name == profile.name);
  if (idx >= 0) {
    profiles[idx] = profile;
  } else {
    profiles.add(profile);
  }
  await saveProfiles(profiles);
}

/// 按名字删除档案。
Future<void> removeProfile(String name) async {
  final profiles = await getProfiles();
  profiles.removeWhere((p) => p.name == name);
  await saveProfiles(profiles);
  // 若删除的是当前激活档案，清除激活标记。
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(StoreKeys.activeProfile) == name) {
    await prefs.remove(StoreKeys.activeProfile);
  }
}

/// 当前激活档案名（无则 null）。
Future<String?> getActiveProfile() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(StoreKeys.activeProfile);
}

/// 设置激活档案。
Future<void> setActive(String? name) async {
  final prefs = await SharedPreferences.getInstance();
  if (name == null) {
    await prefs.remove(StoreKeys.activeProfile);
  } else {
    await prefs.setString(StoreKeys.activeProfile, name);
  }
}

/// 测量记录。
Future<List<MeasurementRecord>> getRecords() async {
  final prefs = await SharedPreferences.getInstance();
  return _decodeList(prefs, StoreKeys.records, MeasurementRecord.fromJson);
}

/// 保存整个记录列表。
Future<void> saveRecords(List<MeasurementRecord> records) async {
  final prefs = await SharedPreferences.getInstance();
  await _writeList(
      prefs, StoreKeys.records, records, (r) => r.toJson());
}

/// 追加一条记录（按 id 去重）。
Future<void> appendRecord(MeasurementRecord record) async {
  final records = await getRecords();
  records.removeWhere((r) => r.id == record.id);
  records.add(record);
  await saveRecords(records);
}

/// 删除记录（按 id 集合）。
Future<void> deleteRecords(Set<String> ids) async {
  final records = await getRecords();
  records.removeWhere((r) => ids.contains(r.id));
  await saveRecords(records);
}

/// 将 [records] 转移到目标档案（改 unit 为 [targetUnit]）。
/// 成员改名后，把所有史记录的归属（unit）与内嵌 profile.name 同步到新名字。
/// 不做这一步会导致改名后数据页按新名字过滤不到任何记录（数据"消失"）。
/// 成员档案（性别/年龄/身高）变更后，按新档案重算该成员所有记录的体成分。
/// 不重算的话历史记录会一直显示旧性别算出的体脂率（BMI 不受性别影响，无需动）。
Future<int> recalcRecordsForProfile(UserProfile p) async {
  final all = await getRecords();
  var n = 0;
  for (var i = 0; i < all.length; i++) {
    final r = all[i];
    if (r.unit != p.name) continue;
    // 先无条件同步档案：身高影响 BMI，即使这条没有阻抗也要跟着改
    r.profile = p;
    if ((r.impedance1 ?? 0) <= 0) { n++; continue; } // 无阻抗只更新档案，不算体成分
    final comp = BodyCompositionCalc.estimate(
      weightKg: r.weightKg,
      heightCm: p.heightCm,
      age: p.age,
      sex: p.sex,
      impedances: [r.impedance1 ?? 0, r.impedance2 ?? 0],
      algo: await getBfAlgo(),
    );
    if (comp == null) continue;
    r.bodyComposition = comp;
    r.profile = p;
    n++;
  }
  if (n > 0) await saveRecords(all);
  return n;
}
Future<void> renameRecordOwner(String oldName, String newName) async {
  if (oldName == newName || oldName.isEmpty || newName.isEmpty) return;
  final all = await getRecords();
  var changed = false;
  for (var i = 0; i < all.length; i++) {
    final r = all[i];
    if (r.unit != oldName) continue;
    r.unit = newName;
    final pr = r.profile;
    if (pr != null && pr.name == oldName) {
      r.profile = UserProfile(
        name: newName,
        sex: pr.sex,
        age: pr.age,
        heightCm: pr.heightCm,
        weightKg: pr.weightKg,
      );
    }
    changed = true;
  }
  if (changed) await saveRecords(all);
}
Future<void> transferRecords(
  List<MeasurementRecord> records,
  String targetUnit,
) async {
  final all = await getRecords();
  for (final r in records) {
    r.unit = targetUnit;
    final idx = all.indexWhere((x) => x.id == r.id);
    if (idx >= 0) {
      all[idx] = r;
    } else {
      all.add(r);
    }
  }
  await saveRecords(all);
}

/// 标记已同步：写 syncedAt 为 [syncedAt]（默认当前 ISO 时间）。
Future<void> markSynced(Set<String> ids, {String? syncedAt}) async {
  final records = await getRecords();
  final stamp = syncedAt ?? DateTime.now().toIso8601String();
  for (final r in records) {
    if (ids.contains(r.id)) {
      r.syncedAt = stamp;
    }
  }
  await saveRecords(records);
}

/// 目标体重。
Future<GoalWeight?> getGoal() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(StoreKeys.goals);
  if (raw == null || raw.isEmpty) return null;
  try {
    final data = jsonDecode(raw);
    if (data is Map) {
      return GoalWeight.fromJson(Map<String, dynamic>.from(data));
    }
    // 兼容旧格式：直接是数字。
    if (data is num) {
      return GoalWeight(weightKg: data.toDouble(), enabled: true);
    }
  } catch (_) {}
  return null;
}

/// 设置目标体重。
Future<void> setGoal(GoalWeight goal) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(StoreKeys.goals, jsonEncode(goal.toJson()));
}

/// 显示单位（默认 kg）。
Future<DisplayUnit> getDisplayUnit() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(StoreKeys.displayUnit);
  return switch (raw) {
    'lb' => DisplayUnit.lb,
    'jin' => DisplayUnit.jin,
    _ => DisplayUnit.kg,
  };
}

/// 设置显示单位。
Future<void> setDisplayUnit(DisplayUnit unit) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(StoreKeys.displayUnit, unit.name);
}

/// 待同步历史。
Future<List<PendingHistory>> getPending() async {
  final prefs = await SharedPreferences.getInstance();
  return _decodeList(prefs, StoreKeys.pending, PendingHistory.fromJson);
}

/// 追加待同步项（按 key 去重）。
Future<void> addPending(PendingHistory item) async {
  final pending = await getPending();
  pending.removeWhere((p) => p.key == item.key);
  pending.add(item);
  final prefs = await SharedPreferences.getInstance();
  await _writeList(prefs, StoreKeys.pending, pending, (p) => p.toJson());
}

/// 删除待同步项（按 key 集合）。
Future<void> removePending(Set<String> keys) async {
  final pending = await getPending();
  pending.removeWhere((p) => keys.contains(p.key));
  final prefs = await SharedPreferences.getInstance();
  await _writeList(prefs, StoreKeys.pending, pending, (p) => p.toJson());
}

/// 已绑定设备。
Future<List<BoundDevice>> getDevices() async {
  final prefs = await SharedPreferences.getInstance();
  return _decodeList(prefs, StoreKeys.devices, BoundDevice.fromJson);
}

/// 添加设备（按 id 去重）。
Future<void> addDevice(BoundDevice device) async {
  final devices = await getDevices();
  devices.removeWhere((d) => d.id == device.id);
  devices.add(device);
  final prefs = await SharedPreferences.getInstance();
  await _writeList(prefs, StoreKeys.devices, devices, (d) => d.toJson());
}

/// 删除设备（按 id）。
Future<void> removeDevice(String id) async {
  final devices = await getDevices();
  devices.removeWhere((d) => d.id == id);
  final prefs = await SharedPreferences.getInstance();
  await _writeList(prefs, StoreKeys.devices, devices, (d) => d.toJson());
}

/// 重命名设备。
Future<void> renameDevice(String id, String name) async {
  final devices = await getDevices();
  final idx = devices.indexWhere((d) => d.id == id);
  if (idx >= 0) {
    devices[idx] = BoundDevice(
      id: devices[idx].id,
      name: name,
      model: devices[idx].model,
      boundAt: devices[idx].boundAt,
    );
  }
  final prefs = await SharedPreferences.getInstance();
  await _writeList(prefs, StoreKeys.devices, devices, (d) => d.toJson());
}

/// 同步地址（无则默认）。
Future<String> getSyncUrl() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(StoreKeys.syncUrl) ?? StoreKeys.defaultSyncUrl;
}

/// 设置同步地址。
Future<void> setSyncUrl(String url) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(StoreKeys.syncUrl, url);
}

/// 历史记录是否自动归属当前成员（默认 true）。
Future<bool> getAutoAssignHistory() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(StoreKeys.autoAssignHistory) ?? true;
}

Future<void> setAutoAssignHistory(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(StoreKeys.autoAssignHistory, value);
}
/// 主题模式：system / light / dark。
Future<String> getThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(StoreKeys.themeMode) ?? 'system';
}

Future<void> setThemeMode(String mode) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(StoreKeys.themeMode, mode);
}
/// 上次在测量页选中的设备 MAC（切换后记住，下次默认连它）。
Future<String?> getPreferredDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(StoreKeys.preferredDevice);
}

Future<void> setPreferredDeviceId(String id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(StoreKeys.preferredDevice, id);
}
/// 不完整测量（无阻抗）处理策略：
/// - ask   每次询问用户（默认，第一次会问并可选择记住）
/// - save  总是只保存体重
/// - skip  总是不保存
/// 体脂率算法选择：officialAnt（默认，对齐官方 App）/ paperDeurenberg / paperSegal。
Future<String> getBfAlgo() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(StoreKeys.bfAlgo) ?? 'officialAnt';
}

Future<void> setBfAlgo(String algo) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(StoreKeys.bfAlgo, algo);
}

Future<String> getIncompletePolicy() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(StoreKeys.incompletePolicy) ?? 'ask';
}

Future<void> setIncompletePolicy(String policy) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(StoreKeys.incompletePolicy, policy);
}
/// 用户保存过的自定义日期区间（最多保留 5 条，最近使用的排前面）。
/// 每条：{'from': '2026-11-01', 'to': '2026-11-15', 'label': '11-01 ~ 11-15'}
Future<List<Map<String, String>>> getCustomRanges() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getStringList(StoreKeys.customRanges) ?? const <String>[];
  final out = <Map<String, String>>[];
  for (final item in raw) {
    try {
      final m = jsonDecode(item) as Map<String, dynamic>;
      out.add({
        'from': (m['from'] ?? '') as String,
        'to': (m['to'] ?? '') as String,
        'label': (m['label'] ?? '') as String,
      });
    } catch (_) {}
  }
  return out;
}

Future<void> addCustomRange(String from, String to) async {
  final label = _rangeLabel(from, to);
  final list = await getCustomRanges();
  list.removeWhere((e) => e['from'] == from && e['to'] == to);
  list.insert(0, {'from': from, 'to': to, 'label': label});
  final trimmed = list.take(5).toList();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(
    StoreKeys.customRanges,
    trimmed.map((e) => jsonEncode(e)).toList(),
  );
}

Future<void> removeCustomRange(String from, String to) async {
  final list = await getCustomRanges();
  list.removeWhere((e) => e['from'] == from && e['to'] == to);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(
    StoreKeys.customRanges,
    list.map((e) => jsonEncode(e)).toList(),
  );
}

String _rangeLabel(String from, String to) {
  String short(String d) => d.length >= 10 ? d.substring(5) : d;
  return short(from) + ' ~ ' + short(to);
}
/// 孤儿记录分组：条数 + 记录里残留的旧档案（可能为 null）。
class OrphanUnitInfo {
  final int count;
  final UserProfile? profile;
  const OrphanUnitInfo({required this.count, this.profile});
}

/// 找出「记录归属名不在现有成员列表里」的孤儿分组。
/// 返回：{旧名字: 记录条数}。用于改名后修复历史数据归属。
Future<Map<String, OrphanUnitInfo>> getOrphanRecordUnits() async {
  final profiles = await getProfiles();
  final names = profiles.map((p) => p.name).toSet();
  final recs = await getRecords();
  final out = <String, OrphanUnitInfo>{};
  for (final r in recs) {
    if (r.unit.isEmpty || names.contains(r.unit)) continue;
    final prev = out[r.unit];
    out[r.unit] = OrphanUnitInfo(
      count: (prev?.count ?? 0) + 1,
      // 记录里保存了测量当时的档案 → 能还原旧成员的性别/身高/年龄，
      // 方便用户判断这批记录原本属于谁。
      profile: prev?.profile ?? r.profile,
    );
  }
  return out;
}

/// 把所有挂在该名字下的记录转移给新成员（含内嵌 profile.name）。
Future<int> reassignRecords(String fromUnit, String toName) async {
  final all = await getRecords();
  var n = 0;
  for (var i = 0; i < all.length; i++) {
    final r = all[i];
    if (r.unit != fromUnit) continue;
    r.unit = toName;
    final pr = r.profile;
    if (pr != null) {
      r.profile = UserProfile(
        name: toName, sex: pr.sex, age: pr.age,
        heightCm: pr.heightCm, weightKg: pr.weightKg,
      );
    }
    n++;
  }
  if (n > 0) await saveRecords(all);
  return n;
}
/// 调试模式（彩蛋解锁）：默认关闭。开启后设置页「调试日志」、
/// 测量页右上角通讯按钮才出现。
Future<bool> getDebugMode() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(StoreKeys.debugMode) ?? false;
}

Future<void> setDebugMode(bool v) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(StoreKeys.debugMode, v);
}