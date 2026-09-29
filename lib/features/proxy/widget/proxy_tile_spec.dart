import 'dart:convert';

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
  return (text: delay >= NkColors.latencyTimeoutMs ? '×' : '${delay}ms', color: testedColor);
}

/// 节点卡协议名 —— 对应 NekoBox `ProxyEntity.displayType()`，独立于“添加节点”菜单文案。
/// 菜单里的 Hysteria 不带版本，而节点实体必须显示 Hysteria1 / Hysteria2。
String nkProxyTypeLabel(Translations t, {required String type, required bool isSecure, String? configPayload}) =>
    switch (type.trim().toLowerCase()) {
      'socks' => 'SOCKS',
      'http' => isSecure ? 'HTTPS' : 'HTTP',
      'shadowsocks' => 'Shadowsocks',
      'vmess' => 'VMess',
      'vless' => 'VLESS',
      'trojan' => 'Trojan',
      'trojan-go' => 'Trojan-Go',
      'mieru' => 'Mieru',
      'naive' => 'Naïve',
      'hysteria' => 'Hysteria1',
      'hysteria2' => 'Hysteria2',
      'ssh' => 'SSH',
      'wireguard' => 'WireGuard',
      'tuic' => 'TUIC',
      'shadowtls' => 'ShadowTLS',
      'anytls' => 'AnyTLS',
      'chain' => t.pages.proxies.chain.proxyChain,
      'config' => nkConfigTypeLabel(configPayload),
      _ => type,
    };

String nkConfigTypeLabel(String? payload) {
  if (payload == null || payload.trim().isEmpty) return 'sing-box config';
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map) {
      final type = decoded['type'];
      if (type is String && type.isNotEmpty) return '$type (sing-box)';
    }
  } catch (_) {
    // Invalid config is surfaced by the editor; the row keeps a stable fallback label.
  }
  return 'sing-box config';
}

/// NekoBox `ConfigurationFragment.kt:1610-1616`：Chain 隐藏分享；
/// 普通协议和 Config 都保留分享入口（Config 仅提供配置导出）。
bool nkProxyShowsShare(String type) => type.trim().toLowerCase() != 'chain';

/// 行2 流量显隐：`showTraffic && status > 0`（spec L1543 + L1567-1569：
/// 未测速时流量文本搬去状态位，行2 置空 —— 两处只显示一处）。
bool nkProxyShowTrafficInAddressRow({required bool hasTraffic, required bool tested}) => hasTraffic && tested;
