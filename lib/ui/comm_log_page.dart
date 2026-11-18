import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ble/comm_log.dart';
import 'package:afu_scale/i18n/l10n.dart';
import 'theme.dart' as th;

class CommLogPage extends StatefulWidget {
  const CommLogPage({super.key});
  @override State<CommLogPage> createState() => _CommLogPageState();
}

class _CommLogPageState extends State<CommLogPage> {
  bool _autoScroll = true;
  final _ctrl = ScrollController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final entries = CommLog.instance.entries;
    return Scaffold(
      backgroundColor: th.AppColors.bg,
      appBar: AppBar(
        backgroundColor: th.AppColors.bg,
        title: Text(s.debugLog),
        actions: [
          IconButton(
            tooltip: '导出到文件',
            icon: Icon(Icons.save_alt_rounded, color: th.AppColors.primary),
            onPressed: () async {
              final path = await CommLog.instance.exportToFile(force: true);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                duration: const Duration(seconds: 6),
                content: Text(path == null ? '导出失败' : '已导出到\n' + path),
              ));
            },
          ),
          IconButton(
            tooltip: s.clear,
            icon: Icon(Icons.delete_outline_rounded, color: th.AppColors.danger),
            onPressed: () { CommLog.instance.clear(); setState(() {}); },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: th.AppColors.surface,
              borderRadius: BorderRadius.circular(th.AppRadius.md),
              border: Border.all(color: th.AppColors.border),
            ),
            child: Row(
              children: [
                Text(
                  entries.length.toString() + ' 条',
                  style: TextStyle(color: th.AppColors.text, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 10),
                _legend('→ 发送', th.AppColors.accent),
                const SizedBox(width: 8),
                _legend('← 接收', th.AppColors.primaryDeep),
                const Spacer(),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: _autoScroll,
                    activeThumbColor: th.AppColors.primary,
                    onChanged: (v) => setState(() => _autoScroll = v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.terminal_rounded, size: 38, color: th.AppColors.textHint),
                        const SizedBox(height: 10),
                        Text('连接秤后自动记录通讯', style: TextStyle(color: th.AppColors.textHint, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _ctrl,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: entries.length,
                    itemBuilder: (ctx, i) {
                      final e = entries[i];
                      final isTx = e.dir == 'TX';
                      final color = isTx ? th.AppColors.accent : th.AppColors.primaryDeep;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: th.AppColors.surface,
                          borderRadius: BorderRadius.circular(th.AppRadius.sm),
                          border: Border(left: BorderSide(color: color, width: 3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  e.line.split(' ')[0],
                                  style: TextStyle(fontSize: 10, color: th.AppColors.textHint, fontFamily: 'monospace'),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isTx ? '→ ' + e.note : '← ' + (e.note.isEmpty ? '数据' : e.note),
                                  style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            if (e.hex.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                e.hex,
                                style: TextStyle(fontSize: 9.5, color: th.AppColors.textSub, fontFamily: 'monospace', height: 1.5),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _legend(String txt, Color c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(txt, style: TextStyle(fontSize: 10, color: th.AppColors.textHint)),
    ],
  );
}