// 校验「订阅更新允许不安全连接」(allowInsecureOnRequest) 的核心逻辑。
//
// 规格（NekoBox）：
//   · RawUpdater.kt:59-71 —— 订阅更新 HTTP 客户端：
//       - appTLSVersion == "1.3" 时 restrictedTLS()（Dart SDK 无此 API，不做，见 parity §8）
//       - allowInsecureOnRequest == true 时 allowInsecure()（仅订阅链路）
//   · 其余请求（应用更新、行展开以外的下载）不受影响。
//
// hiddify 落点：DioHttpClient 的 mode 路由。本脚本镜像 `_resolveMode` 的判定表达式
// （dio_http_client.dart）——两边必须逐字一致，改这里时必须同步改那边。
//
// 纯 Dart：不 import 任何项目文件（repo 依赖会拖进 drift/Flutter，dart run 编不过）。
// 运行：dart run tool/check_insecure_request.dart

// ignore_for_file: avoid_print — 校验脚本，print 就是它的输出方式
import 'dart:convert';

int passed = 0;
int failed = 0;

void check(String name, Object? actual, Object? expected) {
  final ok = sameValue(actual, expected);
  if (ok) {
    passed++;
    print('PASS  $name');
  } else {
    failed++;
    print('FAIL  $name: expected=$expected actual=$actual');
  }
}

/// List/Map 用 jsonEncode 按值比较（Dart `==` 对集合是同一性比较）
bool sameValue(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

/// 镜像 DioHttpClient._resolveMode 的 mode 选择（dio_http_client.dart）。
/// 前置约定：port==0（内核未跑）时 isPortOpen("127.0.0.1", 0) 恒为 false。
String resolveMode({
  required bool allowInsecure,
  required bool proxyOnly,
  required bool portOpen,
}) {
  final mode = allowInsecure
      ? "insecure"
      : proxyOnly
      ? "proxy"
      : portOpen
      ? "both"
      : "direct";
  return mode;
}

void main() {
  // 1) 开关开 ⇒ 无论端口状态，一律走 insecure 实例（NekoBox：订阅链路无条件 allowInsecure）
  check('开关开+内核跑 → insecure', resolveMode(allowInsecure: true, proxyOnly: false, portOpen: true), 'insecure');
  check('开关开+内核停 → insecure', resolveMode(allowInsecure: true, proxyOnly: false, portOpen: false), 'insecure');
  // 2) 开关优先级最高：NekoBox 里 allowInsecure() 只是给订阅客户端加能力，
  //    但订阅下载没有 proxyOnly 语义；若两者同时给出，订阅链路语义优先。
  check('开关开+proxyOnly → insecure', resolveMode(allowInsecure: true, proxyOnly: true, portOpen: true), 'insecure');
  // 3) 开关关 ⇒ 原有行为完全不变（回归保护）
  check('关+proxyOnly → proxy', resolveMode(allowInsecure: false, proxyOnly: true, portOpen: true), 'proxy');
  check('关+端口开 → both', resolveMode(allowInsecure: false, proxyOnly: false, portOpen: true), 'both');
  check('关+端口停 → direct', resolveMode(allowInsecure: false, proxyOnly: false, portOpen: false), 'direct');

  // 4) insecure 实例的 HttpClient 行为镜像：badCertificateCallback 放行 ⇔ mode=insecure。
  //    （真 Socket 行为无法在纯 Dart 下验证，这里验证判定表达式本身。）
  bool? badCertCallback(String mode) => switch (mode) {
        "insecure" => true, // (cert, host, port) => true
        _ => null, // 默认 = 不放行
      };
  check('insecure 实例放行坏证书', badCertCallback('insecure'), true);
  check('both 实例不放行', badCertCallback('both'), null);
  check('proxy 实例不放行', badCertCallback('proxy'), null);
  check('direct 实例不放行', badCertCallback('direct'), null);

  print('\n$passed passed, $failed failed');
  if (failed > 0) throw StateError('check_insecure_request failed');
}
