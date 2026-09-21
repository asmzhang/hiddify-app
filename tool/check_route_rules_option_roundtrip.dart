// SingboxConfigOption 序列化层的 rules 字段往返校验（批次 13 补充）：
// 证明 rules 数组经 toJson → fromJson 无损（profileOverride 流会走这条路），
// 且最终发往内核的 HiddifySettingsJson 顶层键形态正确。
//
// 运行：dart run tool/check_route_rules_option_roundtrip.dart
//
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:hiddify/features/route_rules/data/route_rule_json.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/features/log/model/log_level.dart';
import 'package:hiddify/core/model/optional_range.dart';

void main() {
  final rules = [
    Rule()
      ..listOrder = 1
      ..enabled = true
      ..name = 'r1'
      ..outbound = Outbound.direct
      ..domainSuffixes.addAll(['.cn']),
  ];
  final converted = routeRuleToCoreJson(rules);

  final option = SingboxConfigOption(
    region: 'other',
    balancerStrategy: BalancerStrategy.roundRobin,
    useXrayCoreWhenPossible: false,
    executeConfigAsIs: false,
    logLevel: LogLevel.warn,
    resolveDestination: false,
    ipv6Mode: IPv6Mode.disable,
    remoteDnsAddress: 'tcp://8.8.8.8',
    remoteDnsDomainStrategy: DomainStrategy.auto,
    directDnsAddress: 'local',
    directDnsDomainStrategy: DomainStrategy.auto,
    mixedPort: 12334,
    tproxyPort: 12335,
    directPort: 12337,
    redirectPort: 12336,
    enableMixedPort: true,
    enableTproxyPort: false,
    enableDirectPort: false,
    enableRedirectPort: false,
    tunImplementation: TunImplementation.gvisor,
    mtu: 9000,
    strictRoute: true,
    connectionTestUrl: 'http://cp.cloudflare.com/',
    urlTestInterval: const Duration(seconds: 600),
    enableClashApi: true,
    clashApiPort: 16756,
    enableTun: false,
    setSystemProxy: false,
    bypassLan: false,
    allowConnectionFromLan: false,
    lanSharingPassword: '',
    enableFakeDns: false,
    independentDnsCache: false,
    rules: converted['rules'] as List<Map<String, dynamic>>,
    tlsTricks: SingboxTlsTricks(
      enableFragment: false,
      fragmentSize: OptionalRange.parse('10-100', allowEmpty: true),
      fragmentSleep: OptionalRange.parse('50-200', allowEmpty: true),
      mixedSniCase: false,
      enablePadding: false,
      paddingSize: OptionalRange.parse('1200-1500', allowEmpty: true),
    ),
    chainStatus: ChainStatus.off,
    extraSecurity: SingboxExtraSecurityOption(
      mode: ChainMode.psiphon,
      warp: SingboxExtraSecurityWarpOption(licenseKey: ''),
      psiphon: SingboxExtraSecurityPsiphonOption(region: PsiphonRegion.auto, conduitPairingId: ''),
      profile: SingboxExtraSecurityProfileOption(id: null),
    ),
    unblocker: SingboxUnblockerOption(
      mode: ChainMode.psiphon,
      warp: SingboxUnblockerWarpOption(
        licenseKey: '',
        cleanIp: '',
        cleanPort: 0,
        noise: OptionalRange.parse('', allowEmpty: true),
        noiseSize: OptionalRange.parse('', allowEmpty: true),
        noiseDelay: OptionalRange.parse('', allowEmpty: true),
        noiseMode: '',
      ),
      psiphon: SingboxUnblockerPsiphonOption(region: PsiphonRegion.auto, conduitPairingId: ''),
      profile: SingboxUnblockerProfileOption(id: null),
    ),
  );

  // toJson 顶层键 = "rules"（kebab rename 对单词 rules 无变换）
  final encoded = option.toJson();
  if (!encoded.containsKey('rules')) {
    throw StateError('top-level "rules" key missing in toJson output');
  }

  // fromJson 往返无损（profileOverride 流：fromJson → applyProfileOverride → toJson）
  final decoded = SingboxConfigOption.fromJson(encoded);
  if (jsonEncode(decoded.rules) != jsonEncode(option.rules)) {
    throw StateError('rules not round-trip stable through fromJson/toJson');
  }

  // 最终 HiddifySettingsJson 的 rules 片段形态 = Go 契约
  final goPayload = jsonEncode(encoded);
  final idx = goPayload.indexOf('"rules"');
  if (idx < 0) throw StateError('no rules in payload');
  print('goPayload rules fragment: ${goPayload.substring(idx, goPayload.indexOf('"tls-tricks"'))}');
  print('OPTION ROUND-TRIP OK');
}
