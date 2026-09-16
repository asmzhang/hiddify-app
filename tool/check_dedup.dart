// 去重判重的**可执行校验**（纯 Dart，同 check_entity_import.dart 的理由：
// flutter test 需要 flutter_tester，换机/CI 跑不起来）。
//
// 运行：dart run tool/check_dedup.dart
//
// 规格来源：NekoBox `Protocols.Deduplication.hash()` = serverAddress + serverPort + type
//（名字不参与、凭据不参与），`ConfigurationFragment.kt:534` 首见保留、后续出现即重复。
//
// ignore_for_file: avoid_print — 校验脚本，print 就是它的输出方式
import 'dart:convert';

import 'package:hiddify/features/proxy/data/proxy_entity_import.dart';

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

  void checkNe(String label, Object? actual, Object? notExpected) {
    final ok = !sameValue(actual, notExpected);
    if (!ok) failures++;
    print('${ok ? "PASS" : "FAIL"}  $label${ok ? "" : "\n  should differ from: $notExpected\n  actual:            $actual"}');
  }

  // ── 1) 判重键的基本口径 ──────────────────────────────────────────────────
  final keyA = dedupKeyOf(payload: '{"server":"a.com","server_port":443}', type: 'vless');
  check('地址+端口+类型全同 ⇒ 同键', keyA, dedupKeyOf(payload: '{"server":"a.com","server_port":443}', type: 'vless'));
  checkNe('地址不同 ⇒ 不同键', keyA, dedupKeyOf(payload: '{"server":"b.com","server_port":443}', type: 'vless'));
  checkNe('端口不同 ⇒ 不同键', keyA, dedupKeyOf(payload: '{"server":"a.com","server_port":8443}', type: 'vless'));
  checkNe(
    '协议类型不同 ⇒ 不同键（NekoBox 的 type 参与 hash）',
    keyA,
    dedupKeyOf(payload: '{"server":"a.com","server_port":443}', type: 'trojan'),
  );
  check(
    '凭据不同 ⇒ 同键（NekoBox 口径：密码不参与）',
    dedupKeyOf(payload: '{"server":"a.com","server_port":443,"password":"x"}', type: 'vless'),
    keyA,
  );
  check(
    'payload 里多余字段（tag 名等）不影响判重键',
    dedupKeyOf(payload: '{"server":"a.com","server_port":443,"tag":"名字随便"}', type: 'vless'),
    keyA,
  );

  // ── 2) 分隔符防拼接撞车（NekoBox 直接字符串拼接，这里有歧义风险，特意更强） ──
  checkNe(
    '"1.2.3.4":5 与 "1.2.3":45 不撞车',
    dedupKeyOf(payload: '{"server":"1.2.3.4","server_port":5}', type: 'ss'),
    dedupKeyOf(payload: '{"server":"1.2.3","server_port":45}', type: 'ss'),
  );

  // ── 3) 解析失败 ⇒ null（判重时放行，不误删） ─────────────────────────────
  check('payload 非 JSON ⇒ null', dedupKeyOf(payload: 'not-json', type: 'vless'), null);
  check('payload 非 Map ⇒ null', dedupKeyOf(payload: '[1,2]', type: 'vless'), null);
  check('缺 server ⇒ null', dedupKeyOf(payload: '{"server_port":443}', type: 'vless'), null);
  check('缺 server_port ⇒ null', dedupKeyOf(payload: '{"server":"a.com"}', type: 'vless'), null);
  check('server 非字符串 ⇒ null', dedupKeyOf(payload: '{"server":1,"server_port":443}', type: 'vless'), null);
  check('port 非整数 ⇒ null', dedupKeyOf(payload: '{"server":"a.com","server_port":"443"}', type: 'vless'), null);
  check('空 server ⇒ null', dedupKeyOf(payload: '{"server":"","server_port":443}', type: 'vless'), null);

  if (failures > 0) {
    print('\n$failures check(s) FAILED');
    throw StateError('dedup checks failed: $failures');
  }
  print('\nAll dedup checks passed.');
}
