// L1 语义对等测试 —— 预置规则 1:1 对照 NekoBox。
//
// 权威源：`S:\test\NekoBoxForAndroid`
//   app/src/main/java/io/nekohasekai/sagernet/database/ProfileManager.kt:184-237 getRules()
// 规格与逐行对照：docs/design/nekobox-parity.md §3.5.1
//
// 三条不可动摇的语义（本文件的核心断言）：
//  1. 顺序固定 = 屏蔽 QUIC → 屏蔽广告 → 逐国（Play 商店仅 cn → 域名 → IP）；
//  2. 全部落库即 **enabled=false**（RuleEntity.kt:18 默认 false，ProfileManager 从不传）；
//  3. 国家清单二元：Region.cn ⇒ 仅 cn（5 条）；否则 cn+ir+ru（9 条）。
//
// 断言基准 en（纯函数无需 widget 泵）；另有 zh-CN 文案组。
// 运行：flutter test test/features/route_rules/predefined_rules_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/features/route_rules/data/predefined_rules.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final en = AppLocale.en.buildSync();

  group('buildNekoBoxPresetRules（en）', () {
    test('Region.cn ⇒ 5 条，顺序 = QUIC / 广告 / Play 商店 / 域名 / IP', () {
      final rules = buildNekoBoxPresetRules(en, Region.cn);

      expect(rules, hasLength(5), reason: 'ProfileManager.kt:203 fuckedCountry 仅 ["cn:中国"]');
      expect(
        rules.map((r) => r.name),
        ['Block QUIC', 'Block ADs', 'Play store rule for 中国', 'Domain rule for 中国', 'IP rule for 中国'],
        reason: 'ProfileManager.kt:188/196/213/219/226 的创建顺序',
      );
    });

    test('Region.other ⇒ 9 条，cn 之后追加 Iran / Russia 两组', () {
      final rules = buildNekoBoxPresetRules(en, Region.other);

      expect(rules, hasLength(9), reason: 'ProfileManager.kt:204-208 非中国地区追加 ir:Iran / ru:Russia');
      expect(rules.map((r) => r.name), [
        'Block QUIC',
        'Block ADs',
        'Play store rule for 中国',
        'Domain rule for 中国',
        'IP rule for 中国',
        'Domain rule for Iran',
        'IP rule for Iran',
        'Domain rule for Russia',
        'IP rule for Russia',
      ], reason: 'Play 商店仅 cn（ProfileManager.kt:213 if (country == "cn")）');
    });

    test('全部默认关闭 —— 每条 enabled 都是 false', () {
      for (final region in [Region.cn, Region.other]) {
        final rules = buildNekoBoxPresetRules(en, region);
        expect(
          rules.every((r) => !r.enabled),
          isTrue,
          reason: 'RuleEntity.kt:18 `var enabled: Boolean = false`；ProfileManager.kt:188-232 建条目时从不传 enabled',
        );
      }
    });

    test('每条都有 name + outbound（addRule 的 assert 前置条件）', () {
      for (final rule in buildNekoBoxPresetRules(en, Region.other)) {
        expect(rule.hasName(), isTrue, reason: '${rule.name} 缺 name');
        expect(rule.hasOutbound(), isTrue, reason: '${rule.name} 缺 outbound ⇒ addRule 的 assert 会炸');
      }
    });

    test('①屏蔽 QUIC：block + network=udp + portRanges=["443"]', () {
      final rule = buildNekoBoxPresetRules(en, Region.cn).first;

      expect(rule.outbound, Outbound.block, reason: 'ProfileManager.kt:193 outbound = -2 (block)');
      expect(rule.hasNetwork(), isTrue);
      expect(rule.network, Network.udp, reason: 'ProfileManager.kt:192 network = "udp"');
      expect(rule.portRanges, ['443'], reason: 'ProfileManager.kt:191 port = "443"');
      expect(rule.domains, isEmpty);
      expect(rule.ipCidrs, isEmpty);
    });

    test('②屏蔽广告：block + domains=["geosite:category-ads-all"]', () {
      final rule = buildNekoBoxPresetRules(en, Region.cn)[1];

      expect(rule.outbound, Outbound.block, reason: 'ProfileManager.kt:200 outbound = -2 (block) —— 不是 direct');
      expect(rule.domains, ['geosite:category-ads-all'], reason: 'ProfileManager.kt:199');
      expect(rule.hasNetwork(), isFalse, reason: '未设 network');
      expect(rule.portRanges, isEmpty);
    });

    test('③Play 商店：proxy（不写 outbound ⇒ NekoBox 默认 0）+ domains=["googleapis.cn"]', () {
      final rule = buildNekoBoxPresetRules(en, Region.cn)[2];

      expect(rule.outbound, Outbound.proxy, reason: 'ProfileManager.kt:213-218 不传 outbound ⇒ RuleEntity.kt:26 默认 0 = proxy');
      expect(rule.domains, ['googleapis.cn'], reason: 'ProfileManager.kt:216');
      expect(rule.ipCidrs, isEmpty);
    });

    test('④域名绕过的每国形态：direct + domains=["geosite:<cc>"]', () {
      final rules = buildNekoBoxPresetRules(en, Region.other);

      expect(rules[3].outbound, Outbound.direct, reason: 'ProfileManager.kt:223 outbound = -1 (bypass)');
      expect(rules[3].domains, ['geosite:cn'], reason: r'ProfileManager.kt:222 domains = "geosite:$country"');
      expect(rules[5].domains, ['geosite:ir']);
      expect(rules[7].domains, ['geosite:ru']);
    });

    test('⑤IP 绕过的每国形态：direct + ipCidrs=["geoip:<cc>"]', () {
      final rules = buildNekoBoxPresetRules(en, Region.other);

      expect(rules[4].outbound, Outbound.direct, reason: 'ProfileManager.kt:230 outbound = -1 (bypass)');
      expect(rules[4].ipCidrs, ['geoip:cn'], reason: r'ProfileManager.kt:229 ip = "geoip:$country"');
      expect(rules[4].domains, isEmpty, reason: 'IP 规则不带 domains');
      expect(rules[6].ipCidrs, ['geoip:ir']);
      expect(rules[8].ipCidrs, ['geoip:ru']);
    });

    test('纯函数：同一输入连调两次结果等价，且不共享可变实例', () {
      final a = buildNekoBoxPresetRules(en, Region.cn);
      final b = buildNekoBoxPresetRules(en, Region.cn);

      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(identical(a[i], b[i]), isFalse, reason: '每次都要造新实例，避免调用方改坏共享状态');
        expect(a[i].name, b[i].name);
      }
    });

    test('每条都带 enabled has-bit —— 否则「编辑预置规则 → 保存」会踩 assert', () {
      for (final rule in buildNekoBoxPresetRules(en, Region.other)) {
        expect(
          rule.hasEnabled(),
          isTrue,
          reason: 'rule_notifier.dart:115 assert(state.hasListOrder() && state.hasEnabled())；'
              ' 未显式设 enabled 时 proto3 不置 has-bit（protobuf field_set.dart:463-468）',
        );
      }
    });

    test('编辑往返不变形：writeToJsonMap → Rule.fromJson 后 hasListOrder/hasEnabled 仍在', () {
      // 精确复刻 RuleNotifier.update 的往返路径（rule_notifier.dart:103-109）。
      final rule = buildNekoBoxPresetRules(en, Region.cn).first..listOrder = 0;

      final roundTripped = Rule.fromJson(jsonEncode(rule.writeToJsonMap()));

      expect(roundTripped.hasListOrder(), isTrue, reason: 'listOrder 会随 json 一起传下去');
      expect(roundTripped.hasEnabled(), isTrue, reason: 'has-bit 丢了 ⇒ 保存时 assert 炸');
      expect(roundTripped.enabled, isFalse, reason: '预置规则默认关，往返后依然是关');
      expect(roundTripped.name, rule.name);
      expect(roundTripped.outbound, Outbound.block);
    });
  });

  group('buildNekoBoxPresetRules（zh-CN 文案）', () {
    testWidgets('文案逐条对齐 values-zh-rCN/strings.xml', (tester) async {
      // slang 非 base 语言是 deferred 库 ⇒ 必须 runAsync 里 build()，不能 buildSync()。
      final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;

      final cn = buildNekoBoxPresetRules(t, Region.cn);
      expect(cn.map((r) => r.name), [
        '屏蔽 QUIC', // strings.xml:179 route_opt_block_quic
        '屏蔽广告', // :178 route_opt_block_ads
        '中国 Play 商店规则', // :406 route_play_store = "%s Play 商店规则"
        '中国 域名规则', // :219 route_bypass_domain = "%s 域名规则"
        '中国 IP 规则', // :220 route_bypass_ip = "%s IP 规则"
      ]);

      final other = buildNekoBoxPresetRules(t, Region.other);
      expect(other[5].name, 'Iran 域名规则', reason: '国家名字面量照抄 NekoBox，不接 i18n');
      expect(other[8].name, 'Russia IP 规则');
    });
  });
}
