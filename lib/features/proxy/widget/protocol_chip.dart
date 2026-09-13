import 'package:flutter/material.dart';

/// 协议色标签（对标 NekoBox 的 `getProtocolColor` / layout_profile 里的 type chip）。
///
/// 输入是 sing-box 的 outbound type（如 `vmess`/`vless`/`trojan`/`shadowsocks`…），
/// 输出一个固定配色的圆角小标签。颜色只编码**协议种类**，不随主题变，方便一眼分辨。
class ProtocolChip extends StatelessWidget {
  const ProtocolChip(this.protocol, {super.key, this.compact = false});

  /// outbound 类型（大小写不敏感）。
  final String protocol;

  /// 紧凑模式：更小的内边距与字号。
  final bool compact;

  static const Map<String, (String label, Color color)> _map = {
    'vmess': ('VMess', Color(0xFF7E57C2)),
    'vless': ('VLESS', Color(0xFF26A69A)),
    'trojan': ('Trojan', Color(0xFFEF6C00)),
    'trojan-go': ('Trojan', Color(0xFFEF6C00)),
    'shadowsocks': ('SS', Color(0xFF42A5F5)),
    'shadowsocksr': ('SSR', Color(0xFF42A5F5)),
    'ss': ('SS', Color(0xFF42A5F5)),
    'ssr': ('SSR', Color(0xFF42A5F5)),
    'socks': ('SOCKS', Color(0xFF8D6E63)),
    'http': ('HTTP', Color(0xFF78909C)),
    'wireguard': ('WG', Color(0xFF66BB6A)),
    'wg': ('WG', Color(0xFF66BB6A)),
    'hysteria': ('HY', Color(0xFF26C6DA)),
    'hysteria2': ('HY2', Color(0xFF26C6DA)),
    'tuic': ('TUIC', Color(0xFFEC407A)),
    'naive': ('Naive', Color(0xFFAB47BC)),
    'ssh': ('SSH', Color(0xFF5C6BC0)),
    'mieru': ('Mieru', Color(0xFF8D6E63)),
    'shadowtls': ('STLS', Color(0xFF7E57C2)),
    'direct': ('DIRECT', Color(0xFF9E9E9E)),
    'block': ('BLOCK', Color(0xFFC62828)),
    'dns': ('DNS', Color(0xFF9E9E9E)),
    'selector': ('组', Color(0xFF546E7A)),
    'urltest': ('测速', Color(0xFF546E7A)),
  };

  @override
  Widget build(BuildContext context) {
    final normalized = protocol.trim().toLowerCase();
    final entry = _map[normalized] ?? (normalized.isEmpty ? '—' : protocol.toUpperCase(), const Color(0xFF78909C));
    final (label, color) = entry;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 7, vertical: compact ? 1 : 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
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
