import 'package:flutter/material.dart';
import '../theme.dart' as th;

/// 统一的底部弹窗容器：自动避让键盘、顶部拖动条、圆角、可滚动。
/// 关键点：viewInsets 必须取【弹窗内部 context】的值，用外层页面 context 永远拿到 0。
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required List<Widget> children,
  bool autofocusKeyboard = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetCtx) {
      final insets = MediaQuery.viewInsetsOf(sheetCtx).bottom;
      final maxH = MediaQuery.sizeOf(sheetCtx).height * 0.86;
      return AnimatedPadding(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: insets),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: th.AppColors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(th.AppRadius.xl),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: th.AppColors.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: th.AppColors.text,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}