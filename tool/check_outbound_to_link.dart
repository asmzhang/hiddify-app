// 分享链接生成的**可执行校验**（同 check_entity_import.dart 的理由：纯 Dart，不走 flutter_tester）。
//
// 运行（仓库根目录）：
//   go build -o build/ray2sing_check.exe ./raycheck   # 在 hiddify-core/ 里执行一次
//   dart run tool/check_outbound_to_link.dart
//
// 验收标准（设计文档 §5.3 定案）：自己生成 → **hiddify 内核自带的 ray2sing 解析** → 出站等价。
// 解析端不是移植版，而是 `hiddify-core/raycheck/main.go` 编译出的真实依赖
// （与应用订阅导入共用同一份 ray2sing）——它怎么理解链接，我们就必须生成它怎么理解。
//
// 白名单（链接无损、解析端产物有损，均为 ray2sing 既有行为，非本功能引入）：
//   - ss plugin 的 opts（SIP003 合并值被整塞进 plugin 字段，plugin_opts 恒空）
//   - tuic alpn（恒被换成默认 ["h3","spdy/3.1"]）
//   - hy2 obfs-password（ray2sing 用含 `-` 的字面键取参，而参数键归一化后 `-` 变空格，永远查不到）
//   - reality 无 fp 时注入 utls chrome；ws/grpc/httpupgrade 强制 alpn
//
// ignore_for_file: avoid_print — 校验脚本，print 就是它的输出方式
import 'dart:convert';
import 'dart:io';

import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';
import 'package:hiddify/features/proxy/data/outbound_to_link.dart';

/// 解析端 harness 的构建产物（相对仓库根，go build 命令见文件头）。
const harnessPath = 'build/ray2sing_check.exe';

void main(List<String> args) async {
  final harness = File(harnessPath);
  if (!harness.existsSync()) {
    print('缺少解析端 harness：$harnessPath');
    print('先执行：cd hiddify-core && go build -o ../build/ray2sing_check.exe ./raycheck');
    exitCode = 2;
    return;
  }

  var failures = 0;
  var passed = 0;

  // 往返一条用例：生成链接 → 真实 ray2sing 解析 → 按字段投影断言。
  // [facts] 的键是解析产物出站 JSON 的点路径（如 "tls.server_name"）；
  // 期望值统一经 [_norm] 归一（alpn 的 String/List 双形态等）。
  Future<void> roundTrip(String label, Map<String, dynamic> outbound, Map<String, Object?> facts,
      {String? expectSchemePrefix}) async {
    final link = outboundToLink(outbound);
    if (link == null) {
      failures++;
      print('FAIL  $label：outboundToLink 返回 null（应为链接）');
      return;
    }
    if (expectSchemePrefix != null && !link.startsWith(expectSchemePrefix)) {
      failures++;
      print('FAIL  $label：scheme 不符\n  链接：$link\n  期望前缀：$expectSchemePrefix');
      return;
    }
    final result = await Process.run(harness.absolute.path, [link], stdoutEncoding: utf8);
    if (result.exitCode != 0) {
      failures++;
      print('FAIL  $label：解析端报错\n  链接：$link\n  stderr：${result.stderr}'.trim());
      return;
    }
    final decoded = jsonDecode(result.stdout as String);
    final parsed = ((decoded as Map)['outbounds'] as List).first as Map<String, dynamic>;
    // 解析端给 tag 追加 " § 0" 去重后缀（Ray2Singbox 多链接管线），与实体层
    // 同口径剥掉再比（trimTagName，见 offline_proxy_parser.dart）
    if (parsed['tag'] is String) parsed['tag'] = trimTagName(parsed['tag'] as String);
    final problems = <String>[];
    facts.forEach((path, expected) {
      final actual = _get(parsed, path);
      if (_norm(actual) != _norm(expected)) {
        problems.add('  $path\n    expected: ${_norm(expected)}\n    actual:   ${_norm(actual)}');
      }
    });
    if (problems.isEmpty) {
      passed++;
      print('PASS  $label');
      print('      $link');
    } else {
      failures++;
      print('FAIL  $label\n  链接：$link\n${problems.join("\n")}');
    }
  }

  // ── shadowsocks ──────────────────────────────────────────────────────────
  // 注：ss 密码含 `:` 时（如 "p@ss:word"）ray2sing 解析端硬性要求
  // method:password 恰好两段（strings.Split 后 len==2），三段会整体放弃——
  // 链接本身按 SIP002 标准无损生成，此为解析端既有限制，白名单记录。
  await roundTrip('ss 基础', {
    'type': 'shadowsocks',
    'tag': 'SS 节点',
    'server': 'ss.example.com',
    'server_port': 8388,
    'method': 'aes-128-gcm',
    'password': 'p@ss-word',
  }, {
    'tag': 'SS 节点',
    'server': 'ss.example.com',
    'server_port': 8388,
    'method': 'aes-128-gcm',
    'password': 'p@ss-word',
  }, expectSchemePrefix: 'ss://');

  await roundTrip('ss + obfs 插件（SIP003 合并式）', {
    'type': 'shadowsocks',
    'tag': 'SS-obfs',
    'server': 'ss2.example.com',
    'server_port': 443,
    'method': 'chacha20-ietf-poly1305',
    'password': 'secret',
    'plugin': 'obfs-local',
    'plugin_opts': 'obfs=http;obfs-host=cdn.example.com',
  }, {
    // 白名单：合并值整塞进 plugin，plugin_opts 恒空（链接本身无损，NekoBox 可完整还原）
    'plugin': 'obfs-local;obfs=http;obfs-host=cdn.example.com',
    'plugin_opts': null,
  }, expectSchemePrefix: 'ss://');

  // ── vless ────────────────────────────────────────────────────────────────
  await roundTrip('vless ws+tls+早数据', {
    'type': 'vless',
    'tag': 'VL-ws',
    'server': 'vl.example.com',
    'server_port': 443,
    'uuid': '25da296e-1d96-48ae-9867-4342796cd742',
    'packet_encoding': 'xudp',
    'tls': {
      'enabled': true,
      'server_name': 'vl.example.com',
      'insecure': false,
      'utls': {'enabled': true, 'fingerprint': 'chrome'},
    },
    'transport': {
      'type': 'ws',
      'path': '/ws',
      'headers': {'Host': 'cdn.example.com'},
      'max_early_data': 2048,
      'early_data_header_name': 'Sec-WebSocket-Protocol',
    },
  }, {
    'uuid': '25da296e-1d96-48ae-9867-4342796cd742',
    'packet_encoding': 'xudp',
    'tls.enabled': true,
    'tls.server_name': 'vl.example.com',
    'tls.utls.fingerprint': 'chrome',
    // 白名单：ws 强制 alpn=http/1.1
    'tls.alpn': 'http/1.1',
    'transport.type': 'ws',
    'transport.path': '/ws',
    'transport.headers.Host': 'cdn.example.com',
    'transport.max_early_data': 2048,
    'transport.early_data_header_name': 'Sec-WebSocket-Protocol',
  }, expectSchemePrefix: 'vless://');

  await roundTrip('vless reality+grpc+packetaddr', {
    'type': 'vless',
    'tag': 'VL-reality',
    'server': '198.51.100.7',
    'server_port': 2053,
    'uuid': '409f106a-b2f2-4416-b186-5429c9979cd9',
    'flow': '',
    'packet_encoding': 'packetaddr',
    'tls': {
      'enabled': true,
      'server_name': 'discordapp.com',
      'reality': {'enabled': true, 'public_key': 'SbVKOEMjK0s', 'short_id': '0123abcd'},
    },
    'transport': {'type': 'grpc', 'service_name': 'grpc-svc'},
  }, {
    'uuid': '409f106a-b2f2-4416-b186-5429c9979cd9',
    'packet_encoding': 'packetaddr',
    'tls.reality.enabled': true,
    'tls.reality.public_key': 'SbVKOEMjK0s',
    'tls.reality.short_id': '0123abcd',
    'tls.server_name': 'discordapp.com',
    // 白名单：reality 无 fp 时解析端注入 utls chrome
    'tls.utls.fingerprint': 'chrome',
    // 白名单：grpc 强制 alpn=h2
    'tls.alpn': 'h2',
    'transport.type': 'grpc',
    'transport.service_name': 'grpc-svc',
  }, expectSchemePrefix: 'vless://');

  // ── vmess ────────────────────────────────────────────────────────────────
  const vmessJsonBase = {
    'type': 'vmess',
    'tag': 'VM-ws',
    'server': 'vm.example.com',
    'server_port': 8080,
    'uuid': 'd43ee5e3-1b07-56d7-b2ea-8d22c44fdc66',
    'security': 'chacha20-poly1305',
    'alter_id': 0,
    'packet_encoding': 'xudp',
  };
  await roundTrip('vmess ws+tls', {
    ...vmessJsonBase,
    'tls': {
      'enabled': true,
      'server_name': 'vm.example.com',
      'utls': {'enabled': true, 'fingerprint': 'chrome'},
    },
    'transport': {
      'type': 'ws',
      'path': '/vmtv',
      'headers': {'Host': 'vmhost.example.com'},
    },
  }, {
    'uuid': 'd43ee5e3-1b07-56d7-b2ea-8d22c44fdc66',
    'security': 'chacha20-poly1305',
    // sing-box 的 alter_id 缺省 0，序列化时省略 —— 行为等价
    'alter_id': null,
    'packet_encoding': 'xudp',
    'tls.enabled': true,
    'tls.server_name': 'vm.example.com',
    'tls.utls.fingerprint': 'chrome',
    'transport.type': 'ws',
    'transport.path': '/vmtv',
    'transport.headers.Host': 'vmhost.example.com',
  }, expectSchemePrefix: 'vmess://');

  await roundTrip('vmess tcp 明文（无传输层/无 TLS）', {
    ...vmessJsonBase,
    'tag': 'VM-tcp',
    'server': '203.0.113.9',
    'server_port': 12345,
    'tls': null,
    'transport': null,
  }, {
    'server': '203.0.113.9',
    'server_port': 12345,
    'security': 'chacha20-poly1305',
  }, expectSchemePrefix: 'vmess://');

  // ── trojan ───────────────────────────────────────────────────────────────
  await roundTrip('trojan ws+tls', {
    'type': 'trojan',
    'tag': 'TJ-ws',
    'server': 'tj.example.com',
    'server_port': 443,
    'password': 'hunter2',
    'tls': {'enabled': true, 'server_name': 'tj.example.com'},
    'transport': {
      'type': 'ws',
      'path': '/trojan',
      'headers': {'Host': 'tjcdn.example.com'},
    },
  }, {
    'password': 'hunter2',
    'tls.enabled': true,
    'tls.server_name': 'tj.example.com',
    'transport.type': 'ws',
    'transport.path': '/trojan',
    'transport.headers.Host': 'tjcdn.example.com',
  }, expectSchemePrefix: 'trojan://');

  // ── hysteria2 ────────────────────────────────────────────────────────────
  await roundTrip('hy2 auth 拆 user:pass + salamander 混淆', {
    'type': 'hysteria2',
    'tag': 'HY2',
    'server': 'hy.example.com',
    'server_port': 8443,
    'password': 'user1:pass1',
    'obfs': {'type': 'salamander', 'password': 'obfsPass'},
    'tls': {'enabled': true, 'server_name': 'hy.example.com', 'insecure': true},
  }, {
    'password': 'user1:pass1',
    'obfs.type': 'salamander',
    // 白名单：ray2sing 用含 `-` 的字面键取参，归一化后永远查不到（链接本身无损，
    // sing-box 端字段缺省 = null）
    'obfs.password': null,
    'tls.server_name': 'hy.example.com',
    'tls.insecure': true,
  }, expectSchemePrefix: 'hy2://');

  await roundTrip('hy2 无冒号 auth', {
    'type': 'hysteria2',
    'tag': 'HY2-simple',
    'server': 'hy2.example.com',
    'server_port': 443,
    'password': 'token123',
    'tls': {'enabled': true, 'server_name': 'hy2.example.com'},
  }, {
    'password': 'token123',
    'tls.server_name': 'hy2.example.com',
  }, expectSchemePrefix: 'hy2://');

  // ── tuic ─────────────────────────────────────────────────────────────────
  await roundTrip('tuic 完整参数（双写键）', {
    'type': 'tuic',
    'tag': 'TUIC',
    'server': 'tu.example.com',
    'server_port': 23450,
    'uuid': '3618921b-adeb-4bd3-a2a0-f98b72a674b1',
    'password': 'dongtaiwang',
    'congestion_control': 'bbr',
    'udp_relay_mode': 'native',
    'disable_sni': false,
    'tls': {
      'enabled': true,
      'server_name': 'www.google.com',
      'insecure': true,
      'alpn': ['h3'],
    },
  }, {
    'uuid': '3618921b-adeb-4bd3-a2a0-f98b72a674b1',
    'password': 'dongtaiwang',
    'congestion_control': 'bbr',
    'udp_relay_mode': 'native',
    'tls.server_name': 'www.google.com',
    'tls.insecure': true,
    // 白名单：解析端恒用默认 alpn
    'tls.alpn': 'h3,spdy/3.1',
  }, expectSchemePrefix: 'tuic://');

  // ── socks ────────────────────────────────────────────────────────────────
  await roundTrip('socks 带凭据', {
    'type': 'socks',
    'tag': 'SOCKS',
    'server': '192.0.2.1',
    'server_port': 1080,
    'version': '5',
    'username': 'user',
    'password': 'p@ss',
  }, {
    'username': 'user',
    'password': 'p@ss',
    // sing-box socks 的 version 默认 "5"，序列化时省略 —— 行为等价
    'version': null,
  }, expectSchemePrefix: 'socks://');

  // ── http ─────────────────────────────────────────────────────────────────
  await roundTrip('http + TLS（https scheme）', {
    'type': 'http',
    'tag': 'HTTP-TLS',
    'server': 'proxy.example.com',
    'server_port': 3128,
    'username': 'alice',
    'password': 'wonderland',
    'tls': {'enabled': true, 'server_name': 'proxy.example.com', 'insecure': true},
  }, {
    'username': 'alice',
    'password': 'wonderland',
    'tls.enabled': true,
    'tls.server_name': 'proxy.example.com',
    'tls.insecure': true,
  }, expectSchemePrefix: 'https://');

  await roundTrip('http 明文（http scheme）', {
    'type': 'http',
    'tag': 'HTTP-plain',
    'server': '192.0.2.50',
    'server_port': 8080,
  }, {
    'server': '192.0.2.50',
    'server_port': 8080,
  }, expectSchemePrefix: 'http://');

  // ── 边界：不支持/字段残缺 → null（分享按钮回落复制 JSON）─────────────────
  void checkNull(String label, Map<String, dynamic> outbound) {
    final link = outboundToLink(outbound);
    if (link == null) {
      passed++;
      print('PASS  $label');
    } else {
      failures++;
      print('FAIL  $label：应返回 null，实际 $link');
    }
  }

  checkNull('不支持协议（ssh）', {'type': 'ssh', 'tag': 'x', 'server': 's', 'server_port': 22});
  checkNull('ss 缺 method', {'type': 'shadowsocks', 'tag': 'x', 'server': 's', 'server_port': 1, 'password': 'p'});
  checkNull('端口缺失', {'type': 'vless', 'tag': 'x', 'server': 's', 'uuid': 'u'});

  print('\n$passed passed, $failures failed');
  print(failures == 0 ? 'ALL PASS' : '$failures FAILED');
  exitCode = failures == 0 ? 0 : 1;
}

/// 点路径取值（用于解析产物投影）。
Object? _get(Map<String, dynamic> json, String dottedPath) {
  Object? cur = json;
  for (final part in dottedPath.split('.')) {
    if (cur is Map) {
      cur = cur[part];
    } else {
      return null;
    }
  }
  return cur;
}

/// 归一：alpn 等 Listable 字段解析产物可能是 String 也可能是 List；
/// 统一转成逗号串。数字统一 int（1 vs 1.0）。
Object? _norm(Object? v) {
  if (v is List) return v.map((e) => '$e').join(',');
  if (v is num) return v.toInt();
  return v;
}
