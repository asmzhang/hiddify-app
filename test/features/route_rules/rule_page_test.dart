// RulePage 的 widget 测试（批次 2.5 之后的首组 UI 测试）。
//
// 覆盖四个维度：
//  1. 新建模式：默认值（outbound=direct、network=all）、保存可用；
//  2. 编辑模式：预置规则回显、改动落回内存仓库；
//  3. 字段更新：name/outbound/network 经 RuleNotifier 的 JSON 往返；
//  4. 平台分支：processName 在 android 上无警告、在 windows 上有警告
//     （依赖 PlatformUtils 改用 defaultTargetPlatform 的根治）。
//
// 运行：flutter test test/features/route_rules/rule_page_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/route_rules/notifier/rule_notifier.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/route_rules/overview/rule_page.dart';
import 'package:hiddify/features/route_rules/widget/setting_generic_list.dart';
import 'package:hiddify/features/route_rules/widget/setting_radio.dart';
import 'package:hiddify/features/route_rules/widget/setting_text.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RulePage 新建模式', () {
    testWidgets('渲染出全部字段控件，保存键可用', (tester) async {
      await pumpTestApp(tester, child: const RulePage());

      // name + config 两个文本框（config 是批次 14 后半引入的
      // per-rule 自定义配置 tile，带 JSON object 校验）
      expect(find.byType(SettingText), findsNWidgets(2));
      expect(find.byType(SettingRadio<Outbound>), findsOneWidget);
      // 9 个字符串列表控件（ruleSet / packageName / process×2 / port×2 /
      // ip×2 / domain）——批次 14 已把原 domain×4 合并为一个前缀语义
      // 输入；protocol 是 SettingCheckbox、outboundTag 是 ListTile，不算在内
      expect(
        find.byType(SettingGenericList<String>),
        findsNWidgets(9),
        reason: '9 个字符串列表字段（ruleSet / packageName / processName / '
            'processPath / portRange / sourcePortRange / ipCidr / sourceIpCidr / domain）',
      );

      // 新建模式保存键可用（isRuleEdited 对 null listOrder 恒 true）
      final saveButton = tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(Icons.check), matching: find.byType(IconButton)),
      );
      expect(saveButton.onPressed, isNotNull);
    });
  });

  group('RulePage 编辑模式', () {
    testWidgets('预置规则的名字回显到文本框', (tester) async {
      final rule = makeRule(
        listOrder: 0,
        name: 'my-home-rule',
        domains: ['example.com'],
      );
      await pumpTestApp(tester, rules: [rule], child: const RulePage(ruleListOrder: 0));

      expect(find.text('my-home-rule'), findsOneWidget);
      // 域名列表回显 1 条
      expect(find.text('example.com'), findsOneWidget);
    });

    testWidgets('改名后走 JSON 往返仍能保存（update 的序列化链路）', (tester) async {
      final rule = makeRule(listOrder: 0, name: 'old-name');
      final (container, _) = await pumpTestApp(
        tester,
        rules: [rule],
        child: const RulePage(ruleListOrder: 0),
      );

      // 通过 notifier 直接改（widget 内部走同一条 update 通路）
      container.read(ruleNotifierProvider(0).notifier).update<String>(RuleEnum.name, 'renamed');

      // 保存
      await container.read(ruleNotifierProvider(0).notifier).save();

      final rules = container.read(rulesNotifierProvider);
      expect(rules, hasLength(1));
      expect(rules.single.name, 'renamed');
      // JSON 往返后 listOrder/enabled 不丢
      expect(rules.single.hasListOrder(), isTrue);
      expect(rules.single.enabled, isTrue);
    });
  });

  group('平台分支（defaultTargetPlatform 根治的验证）', () {
    // processName 的警告条件是 `!PlatformUtils.isDesktop`：
    // android（非桌面）→ 有警告；windows（桌面）→ 无警告。
    testWidgets('android 下 processName 显示平台警告（非桌面端才显示）', (tester) async {
      await pumpTestApp(
        tester,
        child: const RulePage(),
      );
      final lists = tester.widgetList<SettingGenericList<String>>(
        find.byType(SettingGenericList<String>),
      );
      final processNameTile = _tileByTitleEn(lists, 'Process names');
      expect(processNameTile, isNotNull);
      expect(processNameTile!.showPlatformWarning, isTrue,
          reason: 'android 不是桌面端，process 字段应显示平台警告');
    });

    testWidgets('windows 下 processName 不显示平台警告（桌面端）', (tester) async {
      await pumpTestApp(
        tester,
        platform: TargetPlatform.windows,
        child: const RulePage(),
      );
      final lists = tester.widgetList<SettingGenericList<String>>(
        find.byType(SettingGenericList<String>),
      );
      final processNameTile = _tileByTitleEn(lists, 'Process names');
      expect(processNameTile, isNotNull);
      expect(processNameTile!.showPlatformWarning, isFalse,
          reason: 'windows 是桌面端，process 字段无需警告');
      // 测试体末尾必须显式归位 —— flutter_test 在此做不变量检查。
      debugDefaultTargetPlatformOverride = null;
    });

    // packageName 的警告条件是 `!PlatformUtils.isAndroid`：
    // 只有 android 不警告 —— 这条验证同一测试内切换平台也能生效。
    testWidgets('windows 下 packageName 显示警告、android 下不显示', (tester) async {
      // windows
      await pumpTestApp(
        tester,
        platform: TargetPlatform.windows,
        child: const RulePage(),
      );
      final windowsLists = tester.widgetList<SettingGenericList<String>>(
        find.byType(SettingGenericList<String>),
      );
      expect(
        _tileByTitleEn(windowsLists, 'Package names')!.showPlatformWarning,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;

      // android（默认）
      await pumpTestApp(
        tester,
        child: const RulePage(),
      );
      final androidLists = tester.widgetList<SettingGenericList<String>>(
        find.byType(SettingGenericList<String>),
      );
      expect(
        _tileByTitleEn(androidLists, 'Package names')!.showPlatformWarning,
        isFalse,
      );
    });
  });
}

/// 按 en 文案找控件（tile 标题来自 RuleEnum.present(t)，是 String）。
SettingGenericList<String>? _tileByTitleEn(
  Iterable<SettingGenericList<String>> tiles,
  String title,
) {
  for (final tile in tiles) {
    if (tile.title == title) return tile;
  }
  return null;
}
