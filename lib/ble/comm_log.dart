// 蓝牙通讯日志：完整记录每一条发送/接收的原始字节，供测量时排查。
import 'dart:collection';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CommEntry {
  final DateTime time;
  final String dir;   // TX = 发出，RX = 收到
  final String hex;   // 原始 20 字节（空格分隔）
  final String note;  // 命令名 / 解析结果
  const CommEntry({required this.time, required this.dir, required this.hex, this.note = ''});

  String get line {
    final t = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}.${(time.millisecond ~/ 10).toString().padLeft(2, '0')}';
    final d = dir == 'TX' ? '→' : '←';
    return '$t $d $hex${note.isEmpty ? '' : '  [$note]'}';
  }
}

/// 进程内环形缓冲，容量 600 条（足够覆盖一次完整连接+测量）。
class CommLog {
  static final CommLog instance = CommLog._();
  static const int capacity = 600;

  final ListQueue<CommEntry> _buf = ListQueue<CommEntry>();
  CommLog._();

  void add(String dir, List<int> bytes, {String note = ''}) {
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    _buf.addLast(CommEntry(time: DateTime.now(), dir: dir, hex: hex, note: note));
    while (_buf.length > capacity) {
      _buf.removeFirst();
    }
  }

  void tx(List<int> bytes, {String note = ''}) => add('TX', bytes, note: note);
  void rx(List<int> bytes, {String note = ''}) => add('RX', bytes, note: note);

  List<CommEntry> get entries => _buf.toList();
  List<String> get lines => _buf.map((e) => e.line).toList();
  int get length => _buf.length;
  void clear() => _buf.clear();

  /// 导出成可复制的纯文本。
  String dump() => _buf.map((e) => e.line).join('\n');

  /// 自动落盘节流：每 3 秒最多写一次。
  DateTime? _lastFlush;

  /// 写到手机文件（Android/data/<包名>/files/comm_latest.txt），返回路径。
  /// 供 adb pull 或分享，避免剪贴板长度限制。
  Future<String?> exportToFile({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastFlush != null &&
        now.difference(_lastFlush!).inSeconds < 3) {
      return null;
    }
    _lastFlush = now;
    try {
      final dir = await getExternalStorageDirectory();
      final target = dir ?? await getApplicationDocumentsDirectory();
      final header = [
        '# AFU 体脂秤通讯日志',
        '# 导出时间: ' + now.toIso8601String(),
        '# 条目数: ' + _buf.length.toString(),
        '# 格式: 时间 方向(→发出/←收到) 原始字节 [命令名]',
        '',
      ].join('\n');
      final body = header + dump();
      await File(target.path + '/comm_latest.txt').writeAsString(body);
      return target.path + '/comm_latest.txt';
    } catch (_) {
      return null;
    }
  }
}
/// 语义化通讯事件——给 UI 显示用，不暴露原始字节。
class CommEvent {
  final DateTime time;
  final bool isTx;
  final String label;   // 对时 / 用户参数 / 槽位 / 握手 / 实时体重 / 锁定 / 历史
  final String detail;  // 80.75 kg · 430/387 Ω · 体脂 26.1%
  const CommEvent({required this.time, required this.isTx, required this.label, this.detail = ''});

  String get clock {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    final ms = (time.millisecond ~/ 100).toString();
    return h + ':' + m + ':' + s + '.' + ms;
  }
}