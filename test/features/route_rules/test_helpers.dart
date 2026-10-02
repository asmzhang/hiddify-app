// Widget 测试公共基建。
//
// 解决三个"不可测根"：
//  1. translationsProvider 链路直通 SharedPreferences（真实设备存储）；
//  2. RulesNotifier 直读文件系统（route_rule.proto）；
//  3. 平台分支（已由 PlatformUtils 改用 defaultTargetPlatform 根治，
//     测试里用 debugDefaultTargetPlatformOverride 切换）。
//
// 用法：
//   await pumpTestApp(tester, child: const RulePage());
//   // 或带预置规则：
//   await pumpTestApp(tester, rules: [myRule], child: const RulePage());
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 造一条测试规则（listOrder 默认 = 在列表里的下标）。
///
/// [enabled] 默认 true —— 这是**用户新建规则**的语义（NekoBox
/// `ui/RouteSettingsActivity.kt:97-99`），也是既有测试的断言前提
/// （`routing_options_page_spec_test.dart` ⑦）。
/// 预置规则的默认关闭语义由 `predefined_rules_test.dart` 单独覆盖。
Rule makeRule({
  int? listOrder,
  String name = 'test-rule',
  Outbound outbound = Outbound.proxy,
  Iterable<String> domains = const [],
  Iterable<String> ipCidrs = const [],
  Iterable<String> portRanges = const [],
  Network network = Network.all,
  bool enabled = true,
}) {
  final rule = Rule(name: name, outbound: outbound, network: network);
  if (listOrder != null) rule.listOrder = listOrder;
  rule.enabled = enabled;
  rule.domains.addAll(domains);
  rule.ipCidrs.addAll(ipCidrs);
  rule.portRanges.addAll(portRanges);
  return rule;
}

/// 内存版 RulesNotifier：不做文件 IO，数据由测试注入。
///
/// [rulesFileExists] 是真实实现里「`route_rule.proto` 是否已落盘」的替身 ——
/// `ensureSeeded` 用它做「是否首次进入」的判据（等价 NekoBox 的
/// `DataStore.rulesFirstCreate`）。默认 **true** = 已有历史存储 ⇒ 不种预置规则，
/// 保持既有 spec 测试的空态/自备规则语义不变；要测自动种子时显式传 false。
/// [resetRules] 会把它翻回 false，因为真实实现里重置就是删掉那个文件。
class InMemoryRulesNotifier extends RulesNotifier {
  InMemoryRulesNotifier(this.initialRules, {this.rulesFileExists = true});

  final List<Rule> initialRules;

  /// 可变：`resetRules()` 删文件 ⇒ 变 false，于是紧接着的 `ensureSeeded` 会重新种下。
  bool rulesFileExists;

  /// ensureSeeded 的调用流水（未种下时为 null，便于区分「没调用」与「调了但跳过」）。
  final List<List<Rule>?> seedLog = [];

  @override
  List<Rule> build() => initialRules
      .asMap()
      .entries
      .map((e) => e.value..listOrder = e.value.hasListOrder() ? e.value.listOrder : e.key)
      .toList();

  @override
  Future<void> addRule(Rule rule) async {
    // 真实实现（rules_notifier.dart:32-40）不再硬写 enabled —— 由调用方（RuleNotifier）
    // 决定。这里保持同一语义，仅补 listOrder。
    rule.listOrder = state.length;
    state = [...state, rule];
    // 故意不落盘 —— 内存态即可。
  }

  @override
  Future<void> ensureSeeded(List<Rule> presets) async {
    if (state.isNotEmpty || rulesFileExists) {
      seedLog.add(null);
      return;
    }
    final seeded = [...presets];
    for (var i = 0; i < seeded.length; i++) {
      seeded[i].listOrder = i;
    }
    state = seeded;
    seedLog.add(seeded);
  }

  @override
  Future<void> resetRules() async {
    // 真实实现（rules_notifier.dart:189+）无条件清空 state，再删文件 ⇒ 下次
    // ensureSeeded 会因为「无历史存储」而重新种下预置规则。
    state = <Rule>[];
    rulesFileExists = false;
  }

  @override
  Future<void> updateRule(Rule rule) async {
    final index = state.indexWhere((element) => element.listOrder == rule.listOrder);
    if (index == -1) return;
    state[index] = rule;
    state = state.toList();
  }

  @override
  Future<void> deleteRule(int listOrder) async {
    final current = [...state]..removeWhere((element) => element.listOrder == listOrder);
    for (var i = 0; i < current.length; i++) {
      current[i].listOrder = i;
    }
    state = current;
  }
}

/// 标准测试泵：Material + riverpod + en 翻译 + 内存规则仓库。
///
/// - [rules]：预置到内存规则仓库的规则（默认空）。
/// - [platform]：默认 **不设** override（widget 测试宿主默认平台即 android）。
///   需要切平台分支时显式传入，并**在测试体末尾**自行把
///   `debugDefaultTargetPlatformOverride` 归零 —— flutter_test 在测试体
///   结束时即做不变量检查，addTearDown 时机太晚，不能依赖它复位。
/// - 返回的 [ProviderContainer] 可用于测试中读 provider 断言状态；
///   测试结束时自动销毁。
Future<(ProviderContainer, T)> pumpTestApp<T extends Widget>(
  WidgetTester tester, {
  required T child,
  List<Rule> rules = const [],
  TargetPlatform? platform,
}) async {
  final container = ProviderContainer(
    overrides: [
      // 1. 翻译：绕开 SharedPreferences 链路，直接给同步 en 实例。
      translationsProvider.overrideWith((ref) => Future.value(AppLocale.en.buildSync())),
      // 2. 规则仓库：内存版，不碰文件系统。
      rulesNotifierProvider.overrideWith(() => InMemoryRulesNotifier([...rules])),
    ],
  );
  addTearDown(container.dispose);

  if (platform != null) {
    debugDefaultTargetPlatformOverride = platform;
    // 不在此处注册 addTearDown 复位 —— 见 [platform] 注释。
  }

  // 预热翻译 provider：RulePage.build 里直接 requireValue，若首帧是
  // AsyncLoading 会抛异常。先 await 到 AsyncData 再挂 widget。
  await container.read(translationsProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: child),
    ),
  );
  await tester.pumpAndSettle();

  return (container, child);
}
