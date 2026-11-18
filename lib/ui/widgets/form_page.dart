import 'package:flutter/material.dart';
import '../theme.dart' as th;

/// 带输入的表单统一用【全屏页面】而不是底部弹窗。
/// 原因：底部弹窗避让键盘在 Android edge-to-edge 下不稳（试过 viewInsets+AnimatedPadding 仍被遮），
/// 而 Scaffold 的 resizeToAvoidBottomInset 默认 true，全屏页面天生不会被键盘挡住。
Future<T?> showFormPage<T>(
  BuildContext context, {
  required String title,
  required List<Widget> children,
  String? confirmLabel,
  Future<bool> Function()? onConfirm,
  Widget? bottomBar,
}) {
  return Navigator.push<T>(
    context,
    MaterialPageRoute<T>(
      builder: (pageCtx) => Scaffold(
        backgroundColor: th.AppColors.bg,
        appBar: AppBar(
          backgroundColor: th.AppColors.bg,
          title: Text(title),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(pageCtx),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: children,
        ),
        bottomNavigationBar: bottomBar ??
            (confirmLabel == null
                ? null
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                      child: FilledButton(
                        onPressed: () async {
                          if (onConfirm == null) { Navigator.pop(pageCtx); return; }
                          final ok = await onConfirm();
                          if (ok && pageCtx.mounted) Navigator.pop(pageCtx, true);
                        },
                        child: Text(confirmLabel),
                      ),
                    ),
                  )),
      ),
    ),
  );
}

/// 表单里统一的分组标题。
Widget formLabel(String text) => Padding(
  padding: const EdgeInsets.only(top: 18, bottom: 8),
  child: Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: th.AppColors.textHint,
      letterSpacing: 0.3,
    ),
  ),
);

/// 表单里的说明文字。
Widget formHint(String text) => Padding(
  padding: const EdgeInsets.only(top: 6),
  child: Text(
    text,
    style: TextStyle(fontSize: 11, color: th.AppColors.textHint, height: 1.6),
  ),
);