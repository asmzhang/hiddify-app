import 'package:flutter/material.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/navigation_keys.dart';

/// 在**根 Navigator** 上弹一个底部弹窗 —— 纯基础设施，不含任何业务内容。
///
/// 与 [showRootDialog] 对称：弹窗内容属于各 feature，但"弹在根 Navigator 上、
/// 套上统一的圆角/约束"是 core 的能力。
Future<T?> showRootBottomSheet<T>({required Widget child, bool isScrollControlled = false}) async {
  final context = rootNavKey.currentContext;
  if (context == null) return null;
  return await Navigator.of(context).push<T>(
    ModalBottomSheetRoute(
      constraints: BottomSheetConst.boxConstraints,
      isScrollControlled: isScrollControlled,
      builder: (context) => ClipRRect(
        borderRadius: BottomSheetConst.borderRadius,
        child: Material(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: child,
          ),
        ),
      ),
    ),
  );
}
