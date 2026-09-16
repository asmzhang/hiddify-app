import 'package:flutter/material.dart';
import 'package:hiddify/core/router/navigation_keys.dart';

/// 在**根 Navigator** 上弹一个对话框 —— 纯基础设施，不含任何业务内容。
///
/// 为什么单独抽出来：对话框内容往往属于某个 feature（排序配置、新版本、窗口关闭…），
/// 但"弹在根 Navigator 上"这件事是 core 的能力。各 feature 自己写一个薄薄的
/// `showXxxDialog()` 调本函数即可，core 不必反过来 import feature。
Future<T?> showRootDialog<T>(Widget child) async {
  final context = rootNavKey.currentContext;
  if (context == null) return null;
  return await Navigator.of(context).push<T>(DialogRoute(context: context, builder: (_) => child));
}
