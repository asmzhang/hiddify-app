// TCP Ping（应用侧直连测速，**不走内核**）。
//
// 规格来源：NekoBox `ui/ConfigurationFragment.kt:694-832` 的 `pingTest(tcp: true)`：
//   · 应用侧 `Socket.connect(InetSocketAddress, 3000)` + `soTimeout=3000`
//   · 并发 `connectionTestConcurrent = 5`
//   · 域名先 `InetAddress.getByName` 解析，失败 → `connection_test_domain_not_found`
//   · 成功：`status = 1`，`ping = 耗时 ms`
//   · 异常分类（照 `pingTest` 的 catch 链）：
//       ECONNREFUSED  → status=2, error=refused 文案
//       ENETUNREACH   → status=2, error=unreachable 文案
//       超时（"failed:" / timeout）→ status=2, error=timeout 文案
//       其余          → status=3, error=原始 message
//   · 结果写实体列并 `GroupManager.postReload`（本文件只管测，落库在 repo/notifier）
//
// 为什么这是零内核风险项：`Socket.connect` 直接连目标地址:端口，连接成功即认为
// "TCP 层可达" —— NekoBox 不经内核（不经 VPN 内部路由），hiddify 用 `dart:io`
// 等价实现，不发起任何内核 RPC。
import 'dart:async';
import 'dart:io';

/// 一次 TCP ping 的结果（与实体列 `status`/`ping`/`error` 一一对应）。
///
/// status 语义照 NekoBox `ProxyEntity.status`：
///   0 = 未测 / 1 = 可用（ping 为耗时 ms）/ 2 = 不可用（error 为分类文案）/
///   3 = 不可用（error 为原始错误文本）
class TcpPingResult {
  const TcpPingResult({required this.status, required this.ping, this.error});

  final int status;
  final int ping;
  final String? error;

  @override
  String toString() => 'TcpPingResult(status=$status, ping=$ping, error=$error)';
}

// ───────────────────────────────────────────────────────────────────────────
// 错误分类（纯函数，可被 dart run 直接校验）。
//
// NekoBox 按 **异常对象类型** 分类（IOException 家族），Dart 侧拿到的是
// `SocketException` 的 `message`/`osError` —— 按错误文本判别（Windows 与
// Android 的 errno 文本不同，但 ECONNREFUSED/ENETUNREACH 的关键词稳定）。
// ───────────────────────────────────────────────────────────────────────────

/// 把一条错误文本分类成 NekoBox 的三档文案键（refused / unreachable / timeout）。
///
/// 返回 null = 无法归类（NekoBox 的 status=3 分支：保留原始文本）。
/// 匹配口径：
///   · refused     —— ECONNREFUSED / "Connection refused"（主动拒绝）
///   · unreachable —— ENETUNREACH / EHOSTUNREACH / "Network is unreachable" /
///                    "No route to host"（路由不可达）
///   · timeout     —— "timed out" / "Timeout" / SocketException 的
///                    "Software caused connection abort"（连接被本侧超时中断）
String? classifyTcpPingError(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('refused')) return 'refused';
  if (lower.contains('unreachable') || lower.contains('no route to host')) return 'unreachable';
  if (lower.contains('timed out') || lower.contains('timeout') || lower.contains('connection abort')) {
    return 'timeout';
  }
  return null;
}

/// 域名解析失败（NekoBox 的 `UnknownHostException` → `connection_test_domain_not_found`）。
class DomainNotFoundException implements Exception {
  const DomainNotFoundException(this.host);

  final String host;

  @override
  String toString() => 'DomainNotFoundException($host)';
}

/// 对单个 host:port 做一次 TCP 连接测速（NekoBox `pingTest` 单节点等价物）。
///
/// 域名先 `InternetAddress.lookup`（NekoBox 的 `InetAddress.getByName`；
/// 失败抛 [DomainNotFoundException]），再 `Socket.connect`（超时 [timeout]）。
/// 连接建立即算成功 —— 不读不写直接销毁（NekoBox 只 `connect` 不发包）。
Future<TcpPingResult> tcpPingHost(
  String host,
  int port, {
  Duration timeout = const Duration(milliseconds: 3000),
}) async {
  final stopwatch = Stopwatch()..start();
  try {
    // NekoBox 先 DNS 再 connect；纯 IP 的 lookup 是本机零开销的解析（无网络往返）
    final addresses = await InternetAddress.lookup(host).timeout(timeout);
    if (addresses.isEmpty) throw const DomainNotFoundException('');
    final socket = await Socket.connect(
      addresses.first,
      port,
      timeout: timeout,
    );
    stopwatch.stop();
    socket.destroy();
    return TcpPingResult(status: 1, ping: stopwatch.elapsedMilliseconds);
  } on SocketException catch (e) {
    stopwatch.stop();
    final message = e.osError?.message ?? e.message;
    return switch (classifyTcpPingError(message)) {
      'refused' => const TcpPingResult(status: 2, ping: 0, error: 'refused'),
      'unreachable' => const TcpPingResult(status: 2, ping: 0, error: 'unreachable'),
      'timeout' => const TcpPingResult(status: 2, ping: 0, error: 'timeout'),
      _ => TcpPingResult(status: 3, ping: 0, error: message),
    };
  } on TimeoutException {
    stopwatch.stop();
    return const TcpPingResult(status: 2, ping: 0, error: 'timeout');
  } on DomainNotFoundException {
    stopwatch.stop();
    return const TcpPingResult(status: 2, ping: 0, error: 'domain_not_found');
  }
}

// ───────────────────────────────────────────────────────────────────────────
// canTCPing 白名单（NekoBox `AbstractBean.canTCPing()`：默认 true，
// hysteria / tuic / wireguard / neko / internal 覆写为 false）。
//
// hiddify 的对应物是出站 `type`。映射口径：
//   · hysteria/hysteria2/tuic/wireguard —— QUIC/UDP 系，TCP 握手无意义（NekoBox 同判）
//   · `internal`（hiddify 内核的 internal 出站）—— 非 TCP 协议
// 其余（vless/vmess/trojan/shadowsocks/anytls 等）保持 true。
// ───────────────────────────────────────────────────────────────────────────

/// 该协议类型是否可做 TCP ping。照 NekoBox `AbstractBean.canTCPing()` 的覆写名单。
bool canTcpPing(String type) {
  switch (type) {
    case 'hysteria':
    case 'hysteria2':
    case 'tuic':
    case 'wireguard':
    case 'internal':
      return false;
    default:
      return true;
  }
}
