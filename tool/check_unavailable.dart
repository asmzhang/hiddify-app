// 删不可用（action_connection_test_delete_unavailable）判据的**可执行校验**。
//
// 运行：dart run tool/check_unavailable.dart
//
// 规格来源：NekoBox `ConfigurationFragment.kt:495-532`：
//   `if (profile.status != 0 && profile.status != 1) toClear.add(profile)`
// 安全属性：**未测速（status=0）绝不能被删** —— 这是"清理"动作最常见的误删来源。
//
// 注意：判据的权威实现在 `proxy_entity_repository.findUnavailableNodes`
// （那一句过滤表达式）。本脚本**不 import repo**（它依赖 drift/Flutter，纯
// dart run 编译不过），而是镜像同一句表达式验证真值表；repo 侧的一致性由
// `flutter analyze` + 这份真值表共同保证。改 repo 判据时必须同步改这里。
//
// ignore_for_file: avoid_print — 校验脚本，print 就是它的输出方式
import 'dart:convert';

/// repo `findUnavailableNodes` 的镜像判据（两处必须逐字一致）。
bool isUnavailable(int status) => status != 0 && status != 1;

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

  // ── 1) NekoBox 判据的真值表 ─────────────────────────────────────────────
  check('status=0（未测速）→ 保留（安全属性）', isUnavailable(0), false);
  check('status=1（可用）→ 保留', isUnavailable(1), false);
  check('status=2（不可用）→ 删', isUnavailable(2), true);
  check('status=3（不可用·原始错误）→ 删', isUnavailable(3), true);
  check('负数（越界防御）→ 删（NekoBox 同口径：!=0 且 !=1）', isUnavailable(-1), true);

  // ── 2) 批量过滤语义（首见保留、顺序不变）────────────────────────────────
  const statuses = [0, 2, 1, 3, 0, 2];
  final kept = [for (final s in statuses) if (isUnavailable(s)) s];
  check('批量过滤保序', kept, [2, 3, 2]);

  if (failures > 0) {
    print('\n$failures check(s) FAILED');
    throw StateError('check_unavailable: $failures failure(s)');
  }
  print('\nAll checks passed.');
}
