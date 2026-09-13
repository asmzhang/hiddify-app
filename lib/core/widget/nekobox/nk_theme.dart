import 'package:flutter/material.dart';

/// NekoBox 风格组件层 · 调色板与度量。
///
/// 只放"设计常量"，不含任何业务逻辑。页面/组件统一从这里取色与尺寸，
/// 避免各处硬编码导致视觉不统一。
abstract class NkColors {
  /// 协议 → 颜色（对标 NekoBox `getProtocolColor`）。键为 sing-box 的 outbound type（小写）。
  static const Map<String, Color> protocol = {
    'vmess': Color(0xFF7E57C2),
    'vless': Color(0xFF26A69A),
    'trojan': Color(0xFFEF6C00),
    'trojan-go': Color(0xFFEF6C00),
    'shadowsocks': Color(0xFF42A5F5),
    'shadowsocksr': Color(0xFF42A5F5),
    'ss': Color(0xFF42A5F5),
    'ssr': Color(0xFF42A5F5),
    'socks': Color(0xFF8D6E63),
    'http': Color(0xFF78909C),
    'wireguard': Color(0xFF66BB6A),
    'wg': Color(0xFF66BB6A),
    'hysteria': Color(0xFF26C6DA),
    'hysteria2': Color(0xFF26C6DA),
    'tuic': Color(0xFFEC407A),
    'naive': Color(0xFFAB47BC),
    'ssh': Color(0xFF5C6BC0),
    'mieru': Color(0xFF8D6E63),
    'shadowtls': Color(0xFF7E57C2),
    'direct': Color(0xFF9E9E9E),
    'block': Color(0xFFC62828),
    'dns': Color(0xFF9E9E9E),
    'selector': Color(0xFF546E7A),
    'urltest': Color(0xFF546E7A),
  };

  static const Color protocolFallback = Color(0xFF78909C);

  static Color protocolColor(String type) => protocol[type.trim().toLowerCase()] ?? protocolFallback;

  /// 延迟三档（绿/黄/红）——亮/暗主题各一套，和 NekoBox 的延迟配色语义一致。
  static const Color latencyOk = Color(0xFF2E9E5B);
  static const Color latencyMid = Color(0xFFE0A106);
  static const Color latencyBad = Color(0xFFD9483B);
  static const Color latencyOkDark = Color(0xFF81C995);
  static const Color latencyMidDark = Color(0xFFFFB74D);
  static const Color latencyBadDark = Color(0xFFFF6B5E);

  /// timeout 阈值：超过即视为"不可用"。
  static const int latencyTimeoutMs = 65000;

  /// 未测速返回 null；超时返回 latencyBad；其余按档返回。
  static Color? latencyColor(BuildContext context, int delayMs) {
    if (delayMs <= 0) return null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (delayMs > latencyTimeoutMs) return dark ? latencyBadDark : latencyBad;
    if (delayMs < 800) return dark ? latencyOkDark : latencyOk;
    if (delayMs < 1500) return dark ? latencyMidDark : latencyMid;
    return dark ? latencyBadDark : latencyBad;
  }
}

/// 统一度量（圆角 / 间距 / 内边距），避免各页参差。
abstract class NkMetrics {
  static const double radius = 14;
  static const double radiusSmall = 10;
  static const double gap = 12;
  static const double gapSmall = 8;
  static const double pad = 14;
  static const double chipRadius = 999;
}
