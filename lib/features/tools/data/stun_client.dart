import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// NAT 类型的粗略判定结果。
enum NatType { open, cone, symmetric, unknown }

class StunResult {
  const StunResult({required this.address, required this.port, required this.natType});

  final String address;
  final int port;
  final NatType natType;
}

/// 极简 STUN 客户端（RFC 5389 Binding Request）。仅用 `dart:io` 的 UDP，无第三方依赖。
///
/// 用途：拿到本机出口的**映射公网地址**，并据此粗略判断 NAT 类型：
/// - 映射地址 + 端口都等于本机地址 → 公网直连（open）
/// - 映射 IP 等于本机、端口不同 → 端口受限 / 对称（symmetric）
/// - 映射 IP 与本机不同 → 锥形 NAT（cone）
///
/// 注意：这是"单服务器"近似判定，够用于"我在 NAT 后吗 / NAT 类型大概是什么"，
/// 不等价于 RFC 3489 的双服务器完整分类。
class StunClient {
  static const int _magicCookie = 0x2112A442;

  static Future<StunResult> test({
    String server = 'stun.l.google.com',
    int port = 19302,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      final localPort = socket.port;
      final txId = Uint8List.fromList(List<int>.generate(12, (_) => Random.secure().nextInt(256)));

      final request = Uint8List(20);
      final bd = ByteData.view(request.buffer);
      bd.setUint16(0, 0x0001); // Binding Request
      bd.setUint16(2, 0x0000); // message length
      bd.setUint32(4, _magicCookie);
      request.setRange(8, 20, txId);

      final lookup = await InternetAddress.lookup(server);
      if (lookup.isEmpty) throw const SocketException('STUN 服务器解析失败');
      final target = lookup.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => lookup.first,
      );

      final completer = Completer<Uint8List>();
      final sub = socket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        final dg = socket.receive();
        if (dg == null) return;
        completer.complete(Uint8List.fromList(dg.data));
      });

      socket.send(request, target, port);
      final data = await completer.future.timeout(timeout);
      await sub.cancel();

      final mapped = _parseMapped(data, txId);
      final local = await _firstLocalIPv4();
      final natType = _classify(local, localPort, mapped.address, mapped.port);
      return StunResult(address: mapped.address, port: mapped.port, natType: natType);
    } finally {
      socket.close();
    }
  }

  static NatType _classify(String? local, int localPort, String mappedAddress, int mappedPort) {
    if (local == null) return NatType.unknown;
    if (local == mappedAddress && localPort == mappedPort) return NatType.open;
    if (local == mappedAddress) return NatType.symmetric;
    return NatType.cone;
  }

  static ({String address, int port}) _parseMapped(Uint8List data, Uint8List txId) {
    if (data.length < 20) throw const FormatException('STUN 响应过短');
    final bd = ByteData.view(data.buffer, data.offsetInBytes, data.length);
    final type = bd.getUint16(0);
    if (type != 0x0101) throw FormatException('非预期 STUN 类型: 0x${type.toRadixString(16)}');
    final length = bd.getUint16(2);
    final end = min(20 + length, data.length);
    var offset = 20;
    while (offset + 4 <= end) {
      final attrType = bd.getUint16(offset);
      final attrLen = bd.getUint16(offset + 2);
      final valueStart = offset + 4;
      if ((attrType == 0x0020 || attrType == 0x0001) && valueStart + attrLen <= data.length) {
        final family = data[valueStart + 1];
        final rawPort = bd.getUint16(valueStart + 2);
        final port = attrType == 0x0020 ? rawPort ^ (_magicCookie >> 16) : rawPort;
        final String address;
        if (family == 0x01) {
          final raw = bd.getUint32(valueStart + 4);
          address = _ipv4(attrType == 0x0020 ? raw ^ _magicCookie : raw);
        } else {
          final bytes = Uint8List(16);
          for (var i = 0; i < 16; i++) {
            final v = data[valueStart + 4 + i];
            final xor = i < 4 ? ((_magicCookie >> (8 * (3 - i))) & 0xff) : txId[i - 4];
            bytes[i] = attrType == 0x0020 ? v ^ xor : v;
          }
          address = _ipv6(bytes);
        }
        return (address: address, port: port);
      }
      offset = valueStart + ((attrLen + 3) & ~3);
    }
    throw const FormatException('STUN 响应缺少 MAPPED-ADDRESS');
  }

  static String _ipv4(int v) => '${(v >> 24) & 0xff}.${(v >> 16) & 0xff}.${(v >> 8) & 0xff}.${v & 0xff}';

  static String _ipv6(Uint8List b) {
    final parts = <String>[];
    for (var i = 0; i < 16; i += 2) {
      parts.add(((b[i] << 8) | b[i + 1]).toRadixString(16));
    }
    return parts.join(':');
  }

  static Future<String?> _firstLocalIPv4() async {
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in ifaces) {
        for (final a in iface.addresses) {
          return a.address;
        }
      }
    } on Object catch (_) {
      // ignore
    }
    return null;
  }
}
