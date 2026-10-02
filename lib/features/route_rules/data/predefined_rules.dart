import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

/// NekoBox 首次进入路由页时自动种下的预置规则（1:1 移植）。
///
/// 权威源：`S:\test\NekoBoxForAndroid`
///   `app/src/main/java/io/nekohasekai/sagernet/database/ProfileManager.kt:184-237 getRules()`
/// 逐行对照表：`docs/design/nekobox-parity.md` §3.5.1
///
/// 三条必须保真的语义：
/// 1. **顺序**：屏蔽 QUIC → 屏蔽广告 → 逐国（Play 商店仅 `cn` → 域名绕过 → IP 绕过）；
/// 2. **全部默认关闭**：`RuleEntity.kt:18 var enabled: Boolean = false`，且
///    `ProfileManager.kt:188-232` 建这 5 条时从不传 `enabled` ⇒ 预置可见但需用户逐条开启；
///    只有用户新建才默认开（`ui/RouteSettingsActivity.kt:97-99`）。
/// 3. **国家清单二元**：`Country` 固定 `["cn:中国"]`；当设备地区不是中国时追加
///    `ir:Iran` / `ru:Russia`（`ProfileManager.kt:203-208`）。hiddify 没有「设备地区」这一
///    概念，改用设置里的 `ConfigOptions.region`（`Region.other` 为默认值）做等价判断。
///
/// 出站值映射（NekoBox `0`=proxy / `-1`=bypass / `-2`=block → proto 枚举）：
/// - `-2` ⇒ [Outbound.block]；`-1` ⇒ [Outbound.direct]；
/// - Play 商店那条**不传 outbound**，走 `RuleEntity.kt:26` 默认 `0` ⇒ [Outbound.proxy]。
///
/// 国家名字面量（`中国` / `Iran` / `Russia`）**照抄 NekoBox 的硬编码**，不接 i18n ——
/// 上游就是这么写的（en 模板 + 中文字面量 ⇒ 「Domain rule for 中国」这种混合语言怪癖），
/// 要 1:1 就一并保留。
///
/// 每条都**显式**传 `enabled: false`（而非省略）：proto3 只在显式赋值时才置 has-bit，
/// 而编辑已有规则走的是 `RuleNotifier.update` 的 `writeToJsonMap()` → `Rule.fromJson`
/// 往返（`rule_notifier.dart:103-109`），has-bit 一旦缺失就会踩
/// `rule_notifier.dart:115 assert(state.hasListOrder() && state.hasEnabled())`。
/// 落盘/下发给内核的语义不受影响 —— `route_rule_json.dart:31` 只在 enabled 为 true
/// 时才输出该键，Go 侧零值 false 与显式 false 等价。
List<Rule> buildNekoBoxPresetRules(Translations t, Region region) {
  final tRules = t.pages.settings.routing.predefinedRules;

  // ProfileManager.kt:203-208 —— 设备地区非中国时追加的「受干扰国家」。
  final countries = <({String code, String display})>[
    (code: 'cn', display: '中国'),
    if (region != Region.cn) ...[
      (code: 'ir', display: 'Iran'),
      (code: 'ru', display: 'Russia'),
    ],
  ];

  return [
    // :188-195 屏蔽 QUIC —— port="443", network="udp", outbound=-2。
    Rule(name: tRules.blockQuic.name, outbound: Outbound.block, network: Network.udp, portRanges: ['443'], enabled: false),
    // :196-202 屏蔽广告 —— domains="geosite:category-ads-all", outbound=-2。
    Rule(name: tRules.ads.name, outbound: Outbound.block, domains: ['geosite:category-ads-all'], enabled: false),
    for (final country in countries) ...[
      // :213-218 仅中国有条 Play 商店规则；不传 outbound ⇒ 默认 0 = proxy。
      if (country.code == 'cn')
        Rule(name: tRules.playStore.name(country: country.display), outbound: Outbound.proxy, domains: ['googleapis.cn'], enabled: false),
      // :219-225 域名绕过 —— domains="geosite:$country", outbound=-1。
      Rule(name: tRules.domain.name(country: country.display), outbound: Outbound.direct, domains: ['geosite:${country.code}'], enabled: false),
      // :226-232 IP 绕过 —— ip="geoip:$country", outbound=-1。
      Rule(name: tRules.ip.name(country: country.display), outbound: Outbound.direct, ipCidrs: ['geoip:${country.code}'], enabled: false),
    ],
  ];
}
