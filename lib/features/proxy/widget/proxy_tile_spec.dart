import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/widget/nekobox/nk_theme.dart';
import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';

/// 节点卡**状态位**规格（NekoBox `ConfigurationFragment.kt:1565-1592` 的纯函数投影）：
///
/// - 组行（sing-box 分组出站，NekoBox 无此形态）→ 显示当前选中项（架构差异，已记档）。
/// - 测速错误编码（<0）→ `connection_test_*` 文案 + 红色（spec status==3 分支的
///   本地化对应：不可用/拒绝/超时/DNS）。
/// - 未测速（delay<=0）→ **流量文本挪到状态位**（spec L1565-1572：`profileStatus.text =
///   trafficText.text`，行2 清空）；无流量 = **空字符串**（不是 "—"）。
/// - 已测速（delay>0）→ 延迟毫秒（绿/黄/红由调用方按阈值解析）；超时阈值 = '×'。
({String text, Color color}) nkProxyStatus(
  Translations t, {
  required bool isGroup,
  required String groupSelectedTagDisplay,
  required int delay,
  required String? traffic,
  required Color errorColor,
  required Color testedColor,
  required Color neutralColor,
}) {
  if (isGroup) {
    return (text: groupSelectedTagDisplay, color: neutralColor);
  }
  final errorKey = offlineTestErrorKey(delay);
  if (errorKey != null) {
    final text = switch (errorKey) {
      'testRefused' => t.pages.proxies.msg.testRefused,
      'testTimeout' => t.pages.proxies.msg.testTimeout,
      'testDomainNotFound' => t.pages.proxies.msg.testDomainNotFound,
      _ => t.pages.proxies.msg.testUnreachable,
    };
    return (text: text, color: errorColor);
  }
  if (delay <= 0) {
    return (text: traffic ?? '', color: neutralColor);
  }
  return (
    text: delay > NkColors.latencyTimeoutMs ? '×' : '$delay',
    color: testedColor,
  );
}

/// 行2 流量显隐：`showTraffic && status > 0`（spec L1543 + L1567-1569：
/// 未测速时流量文本搬去状态位，行2 置空 —— 两处只显示一处）。
bool nkProxyShowTrafficInAddressRow({required bool hasTraffic, required bool tested}) =>
    hasTraffic && tested;
