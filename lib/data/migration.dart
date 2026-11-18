// 数据迁移 —— 从 RN 版 AsyncStorage 键转换到 Flutter shared_preferences 键。
// RN 键：
//   afu_user_profiles / afu_records / afu_goal_weights /
//   afu_display_unit / afu_pending_history / afu_bound_devices
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import 'store.dart';

/// 从 RN 迁移数据。返回成功迁移的条目数。
/// 已存在的 Flutter 键不覆盖（迁移只写空目标键）。
Future<int> migrateFromJson(Map<String, dynamic> rnData) async {
  final prefs = await SharedPreferences.getInstance();
  var migrated = 0;

  // 用户档案
  if (rnData['afu_user_profiles'] is List && !prefs.containsKey(StoreKeys.profiles)) {
    final list = (rnData['afu_user_profiles'] as List)
        .whereType<Map>()
        .map((m) => UserProfile.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    await prefs.setString(StoreKeys.profiles, jsonEncode(list.map((p) => p.toJson()).toList()));
    migrated += list.length;
  }

  // 测量记录
  if (rnData['afu_records'] is List && !prefs.containsKey(StoreKeys.records)) {
    final list = (rnData['afu_records'] as List)
        .whereType<Map>()
        .map((m) => MeasurementRecord.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    await prefs.setString(StoreKeys.records, jsonEncode(list.map((r) => r.toJson()).toList()));
    migrated += list.length;
  }

  // 目标体重（RN 存的是目标值数字）
  if (rnData['afu_goal_weights'] != null && !prefs.containsKey(StoreKeys.goals)) {
    final raw = rnData['afu_goal_weights'];
    if (raw is num) {
      final goal = GoalWeight(weightKg: raw.toDouble(), enabled: true);
      await prefs.setString(StoreKeys.goals, jsonEncode(goal.toJson()));
      migrated += 1;
    } else if (raw is Map) {
      final goal = GoalWeight.fromJson(Map<String, dynamic>.from(raw));
      await prefs.setString(StoreKeys.goals, jsonEncode(goal.toJson()));
      migrated += 1;
    }
  }

  // 显示单位
  if (rnData['afu_display_unit'] != null && !prefs.containsKey(StoreKeys.displayUnit)) {
    final raw = rnData['afu_display_unit'];
    String name;
    if (raw is String) {
      name = raw;
    } else if (raw is Map) {
      // RN 可能存了 { name: 'kg' }
      name = (raw['name'] as String?) ?? 'kg';
    } else {
      name = 'kg';
    }
    await prefs.setString(StoreKeys.displayUnit, name);
    migrated += 1;
  }

  // 待同步历史
  if (rnData['afu_pending_history'] is List && !prefs.containsKey(StoreKeys.pending)) {
    final list = (rnData['afu_pending_history'] as List)
        .whereType<Map>()
        .map((m) => PendingHistory.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    await prefs.setString(StoreKeys.pending, jsonEncode(list.map((p) => p.toJson()).toList()));
    migrated += list.length;
  }

  // 已绑定设备
  if (rnData['afu_bound_devices'] is List && !prefs.containsKey(StoreKeys.devices)) {
    final list = (rnData['afu_bound_devices'] as List)
        .whereType<Map>()
        .map((m) => BoundDevice.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    await prefs.setString(StoreKeys.devices, jsonEncode(list.map((d) => d.toJson()).toList()));
    migrated += list.length;
  }

  return migrated;
}
