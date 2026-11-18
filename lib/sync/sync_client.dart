// 局域网同步客户端 —— 从 RN src/sync/sync.ts 移植，契约保持。
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../data/debug_log.dart';

/// 同步请求超时：8 秒。
const int syncTimeoutMs = 8000;

/// 由主 App 注入的存储抽象。
/// 避免 sync 层直接依赖具体存储实现造成循环依赖。
abstract class SyncStore {
  Future<List<MeasurementRecord>> getRecords();
  Future<void> saveRecords(List<MeasurementRecord> records);
}

/// POST 记录到电脑。返回服务端确认接收的数量。
Future<int> pushRecords(List<MeasurementRecord> records, String url) async {
  final t0 = DateTime.now();
  if (url.isEmpty) {
    DebugLog.instance.log('[同步] 失败：未配置地址', level: 'error');
    return 0;
  }
  if (records.isEmpty) {
    DebugLog.instance.log('[同步] 失败：没有选中记录', level: 'error');
    return 0;
  }
  final body =
      jsonEncode({'records': records.map((r) => r.toJson()).toList()});
  DebugLog.instance.log(
      '[同步] POST $url 共 ${records.length} 条, ${(body.length / 1024).toStringAsFixed(1)}KB');
  try {
    final resp = await http
        .post(Uri.parse(url),
            headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(milliseconds: syncTimeoutMs));
    final ms = DateTime.now().difference(t0).inMilliseconds;
    DebugLog.instance.log('[同步] HTTP ${resp.statusCode} (${ms}ms)');
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      DebugLog.instance
          .log('[同步] 失败：HTTP ${resp.statusCode}', level: 'error');
      return 0;
    }
    final data = _tryDecodeObject(resp.body);
    final sent = (data?['received'] as num?)?.toInt() ?? records.length;
    DebugLog.instance.log('[同步] 成功，服务端接收 $sent 条');
    return sent;
  } catch (e) {
    final ms = DateTime.now().difference(t0).inMilliseconds;
    final msg = _errText(e);
    DebugLog.instance.log('[同步] 异常 (${ms}ms): $msg', level: 'error');
    return 0;
  }
}

/// 测试连通性（GET /ping）。
Future<Map<String, dynamic>> testConnection(String url) async {
  if (url.isEmpty) {
    DebugLog.instance.log('[连通] 失败：未配置地址', level: 'error');
    return {'ok': false, 'ms': 0, 'detail': '未配置推送地址'};
  }
  final pingUrl = url.replaceAll(RegExp(r'/records$'), '/ping');
  final t0 = DateTime.now();
  DebugLog.instance.log('[连通] GET $pingUrl');
  try {
    final resp = await http
        .get(Uri.parse(pingUrl))
        .timeout(const Duration(milliseconds: syncTimeoutMs));
    final ms = DateTime.now().difference(t0).inMilliseconds;
    DebugLog.instance.log('[连通] HTTP ${resp.statusCode} (${ms}ms)');
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return {'ok': true, 'ms': ms, 'detail': 'HTTP ${resp.statusCode}'};
    }
    return {
      'ok': false,
      'ms': ms,
      'detail': 'HTTP ${resp.statusCode}（服务在但返回异常）',
    };
  } catch (e) {
    final ms = DateTime.now().difference(t0).inMilliseconds;
    final msg = _errText(e);
    DebugLog.instance.log('[连通] 异常 (${ms}ms): $msg', level: 'error');
    if (msg.contains('超时')) {
      return {
        'ok': false,
        'ms': ms,
        'detail': '请求超时：手机没连到这个 IP，或电脑服务未监听（${ms}ms）',
      };
    }
    if (msg.contains('Network request failed') ||
        msg.contains('Failed to fetch') ||
        msg.contains('Unable to resolve') ||
        msg.contains('SocketException')) {
      return {
        'ok': false,
        'ms': ms,
        'detail': '网络层拒绝：检查手机与电脑是否同一 WiFi、防火墙是否放行',
      };
    }
    return {'ok': false, 'ms': ms, 'detail': msg};
  }
}

/// 从电脑端拉取远端已有记录。
Future<List<MeasurementRecord>> fetchRemote(String url) async {
  final t0 = DateTime.now();
  if (url.isEmpty) {
    DebugLog.instance.log('[拉取] 失败：未配置地址', level: 'error');
    return <MeasurementRecord>[];
  }
  DebugLog.instance.log('[拉取] GET $url');
  try {
    final resp = await http
        .get(Uri.parse(url))
        .timeout(const Duration(milliseconds: syncTimeoutMs));
    final ms = DateTime.now().difference(t0).inMilliseconds;
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      DebugLog.instance.log('[拉取] HTTP ${resp.statusCode}', level: 'error');
      return <MeasurementRecord>[];
    }
    final data = _tryDecodeObject(resp.body);
    final raw = data?['records'];
    final records = <MeasurementRecord>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          try {
            records.add(
                MeasurementRecord.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {
            // 单条解析失败跳过，不影响整体。
          }
        }
      }
    }
    DebugLog.instance.log('[拉取] 成功 ${records.length} 条 (${ms}ms)');
    return records;
  } catch (e) {
    final ms = DateTime.now().difference(t0).inMilliseconds;
    final msg = _errText(e);
    DebugLog.instance.log('[拉取] 异常 (${ms}ms): $msg', level: 'error');
    return <MeasurementRecord>[];
  }
}

Map<String, dynamic>? _tryDecodeObject(String body) {
  try {
    final data = jsonDecode(body);
    if (data is Map) return Map<String, dynamic>.from(data);
  } catch (_) {}
  return null;
}

String _errText(Object e) {
  if (e is TimeoutException) {
    return '请求超时（$syncTimeoutMs ms 未响应）';
  }
  return e.toString();
}
