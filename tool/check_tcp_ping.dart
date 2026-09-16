// TCP ping 纯函数部分的**可执行校验**（纯 Dart，同 check_dedup.dart 的理由：
// flutter test 需要 flutter_tester，换机/CI 跑不起来）。
//
// 运行：dart run tool/check_tcp_ping.dart
//
// 规格来源：NekoBox `ui/ConfigurationFragment.kt:694-832` 的 `pingTest(tcp: false)`
// + `AbstractBean.canTCPing()` + `values[-zh-rCN]/strings.xml` 的 `connection_test_*`。
//
// ignore_for_file: avoid_print — 校验脚本，print 就是它的输出方式
import 'dart:convert';

import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';
import 'package:hiddify/features/proxy/data/tcp_ping.dart';

/// Dart 的 `==` 对 List/Map 是同一性比较，统一按 JSON 规范化后比较（既有约定）。
bool sameValue(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List || b is List || a is Map || b is Map) {
    try {
      return jsonEncode(a) == jsonEncode(b);
    } catch (_) {
      return false;
    }
  }
  return a == b;
}

void main() {
  var failures = 0;

  void check(String label, Object? actual, Object? expected) {
    final ok = sameValue(actual, expected);
    if (!ok) failures++;
    print('${ok ? "PASS" : "FAIL"}  $label${ok ? "" : "\n  expected: $expected\n  actual:   $actual"}');
  }

  // ── 1) 错误分类（NekoBox `pingTest` 的 catch 链）────────────────────────
  check('ECONNREFUSED → refused', classifyTcpPingError('Connection refused (os error 111)'), 'refused');
  check('小写 refused 命中', classifyTcpPingError('socket refused'), 'refused');
  check('ENETUNREACH → unreachable', classifyTcpPingError('Network is unreachable (os error 101)'), 'unreachable');
  check('No route to host → unreachable', classifyTcpPingError('No route to host (os error 113)'), 'unreachable');
  check('EHOSTUNREACH 文本 → unreachable', classifyTcpPingError('Host is unreachable'), 'unreachable');
  check('timed out → timeout', classifyTcpPingError('Connection timed out (os error 110)'), 'timeout');
  check('Timeout 大小写不敏感', classifyTcpPingError('Operation Timeout'), 'timeout');
  check('connection abort → timeout', classifyTcpPingError('Software caused connection abort'), 'timeout');
  check('未知错误 → null（status=3 保留原文）', classifyTcpPingError('Some weird SSL error'), null);
  check('domain_not_found 分类不经过此函数（直接 status=2）', classifyTcpPingError('domain_not_found'), null);

  // ── 2) canTCPing 白名单（NekoBox `AbstractBean.canTCPing()` 覆写名单）──
  check('默认可测', canTcpPing('vless'), true);
  check('anytls 可测', canTcpPing('anytls'), true);
  check('shadowsocks 可测', canTcpPing('shadowsocks'), true);
  check('trojan 可测', canTcpPing('trojan'), true);
  check('hysteria 不可测', canTcpPing('hysteria'), false);
  check('hysteria2 不可测', canTcpPing('hysteria2'), false);
  check('tuic 不可测', canTcpPing('tuic'), false);
  check('wireguard 不可测', canTcpPing('wireguard'), false);
  check('internal 不可测', canTcpPing('internal'), false);

  // ── 3) 测速结果 → urlTestDelay 编码（实体三列的显示口径）────────────────
  check('未测速 → 0', encodeOfflineTestResult(status: 0, ping: 0), 0);
  check('成功 → 延迟正数', encodeOfflineTestResult(status: 1, ping: 233), 233);
  check('refused → -1', encodeOfflineTestResult(status: 2, ping: 0, error: 'refused'), -1);
  check('unreachable → -2', encodeOfflineTestResult(status: 2, ping: 0, error: 'unreachable'), -2);
  check('timeout → -3', encodeOfflineTestResult(status: 2, ping: 0, error: 'timeout'), -3);
  check('domain_not_found → -4', encodeOfflineTestResult(status: 2, ping: 0, error: 'domain_not_found'), -4);
  check('未分类错误 → -5', encodeOfflineTestResult(status: 3, ping: 0, error: 'weird ssl error'), -5);
  check('status=2 无 error 文本 → -5 兜底', encodeOfflineTestResult(status: 2, ping: 0), -5);
  check('status=1 ping=0 → 0（边界：成功但耗时 0）', encodeOfflineTestResult(status: 1, ping: 0), 0);

  // ── 4) 编码 → 文案键（NekoBox `connection_test_*` 的本地化键）────────────
  check('-1 → testRefused', offlineTestErrorKey(-1), 'testRefused');
  check('-2 → testUnreachable', offlineTestErrorKey(-2), 'testUnreachable');
  check('-3 → testTimeout', offlineTestErrorKey(-3), 'testTimeout');
  check('-4 → testDomainNotFound', offlineTestErrorKey(-4), 'testDomainNotFound');
  check('-5 → 归入不可达一档', offlineTestErrorKey(-5), 'testUnreachable');
  check('正数/0 → null（走正常延迟显示）', offlineTestErrorKey(233), null);
  check('正数/0 → null（未测）', offlineTestErrorKey(0), null);

  // ── 5) 端到端：实体行 → 分组 → urlTestDelay 编码（buildGroupFromEntityNodes）──
  final group = buildGroupFromEntityNodes(
    groupName: 'g',
    nodes: [
      (
        tag: 'A',
        type: 'vless',
        displayName: 'A',
        payload: '{"type":"vless","tag":"A","server":"a.com","server_port":443}',
        status: 1,
        ping: 88,
        error: null,
      ),
      (
        tag: 'B',
        type: 'trojan',
        displayName: 'B',
        payload: '{"type":"trojan","tag":"B","server":"b.com","server_port":443}',
        status: 2,
        ping: 0,
        error: 'timeout',
      ),
      (
        tag: 'C',
        type: 'anytls',
        displayName: 'C',
        payload: '{"type":"anytls","tag":"C","server":"c.com","server_port":443}',
        status: 0,
        ping: 0,
        error: null,
      ),
    ],
  );
  check('status=1 → 显示延迟', group.items[0].urlTestDelay, 88);
  check('status=2 timeout → 编码 -3', group.items[1].urlTestDelay, -3);
  check('status=0 → 未测 0', group.items[2].urlTestDelay, 0);

  if (failures > 0) {
    print('\n$failures check(s) FAILED');
    throw StateError('check_tcp_ping: $failures failure(s)');
  }
  print('\nAll checks passed.');
}
