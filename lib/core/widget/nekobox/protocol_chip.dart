import 'package:flutter/material.dart';
import 'package:hiddify/core/widget/nekobox/nk_theme.dart';

/// 协议色标签（对标 NekoBox `layout_profile` 里的 type chip）。
///
/// 输入 sing-box 的 outbound type（`vmess`/`vless`/`trojan`/`shadowsocks`…），
/// 输出固定配色的圆角小标签。颜色只编码**协议种类**，不随主题变，方便一眼分辨。
class ProtocolChip extends StatelessWidget {
  const ProtocolChip(this.protocol, {super.key, this.compact = false});

  /// outbound 类型（大小写不敏感）。
  final String protocol;

  /// 紧凑模式：更小的内边距与字号。
  final bool compact;

  static const Map<String, String> _labels = {
    'vmess': 'VMess',
    'vless': 'VLESS',
    'trojan': 'Trojan',
    'trojan-go': 'Trojan',
    'shadowsocks': 'SS',
    'shadowsocksr': 'SSR',
    'ss': 'SS',
    'ssr': 'SSR',
    'socks': 'SOCKS',
    'http': 'HTTP',
    'wireguard': 'WG',
    'wg': 'WG',
    'hysteria': 'HY',
    'hysteria2': 'HY2',
    'tuic': 'TUIC',
    'naive': 'Naive',
    'ssh': 'SSH',
    'mieru': 'Mieru',
    'shadowtls': 'STLS',
    'direct': 'DIRECT',
    'block': 'BLOCK',
    'dns': 'DNS',
    'selector': 'GRP',
    'urltest': 'URL',
  };

  @override
  Widget build(BuildContext context) {
    final key = protocol.trim().toLowerCase();
    final label = _labels[key] ?? (key.isEmpty ? '—' : protocol.toUpperCase());
    final color = NkColors.protocolColor(protocol);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 7, vertical: compact ? 1 : 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(NkMetrics.chipRadius)),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }
}
