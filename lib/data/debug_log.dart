// DebugLog —— 进程内环形缓冲，供调试 UI 读取最近 N 条日志。
import 'dart:collection';

/// 单例调试日志。
/// 使用 [log] 追加，[entries] 读取最近 [capacity] 条。
class DebugLog {
  static final DebugLog instance = DebugLog._();

  static const int defaultCapacity = 200;

  final int capacity = defaultCapacity;
  final ListQueue<Map<String, dynamic>> _buffer;

  DebugLog._()
      : _buffer = ListQueue<Map<String, dynamic>>();

  /// 追加一条日志。
  /// [level] 可选：info / warn / error，默认 info。
  void log(String message,
      {String level = 'info', Map<String, dynamic>? data}) {
    final entry = <String, dynamic>{
      'time': DateTime.now().toIso8601String(),
      'level': level,
      'message': message,
      if (data != null) 'data': data,
    };
    _buffer.addLast(entry);
    while (_buffer.length > capacity) {
      _buffer.removeFirst();
    }
  }

  /// 最近日志（最多 [count] 条，默认全部缓冲）。
  List<Map<String, dynamic>> entries({int? count}) {
    final all = _buffer.toList();
    if (count == null || count >= all.length) return all;
    return all.sublist(all.length - count);
  }

  /// 最近日志的文本行。
  List<String> lines({int? count}) =>
      entries(count: count).map((e) => e.toString()).toList();

  /// 清空缓冲。
  void clear() => _buffer.clear();
}
