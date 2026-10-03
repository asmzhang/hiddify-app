// L1 结构对等测试 —— 分应用代理页 ⋮ 菜单 1:1 对照 NekoBox
// `res/menu/per_app_proxy_menu.xml`（权威顺序，本文件的核心断言）：
//
//   1. action_invert_selections  @string/invert_selections       zh-rCN「反选」
//   2. action_clear_selections   @string/clear_selections        zh-rCN「清空」
//   3. action_export_clipboard   @string/action_export_clipboard zh-rCN「导出到剪切板」
//   4. action_import_clipboard   @string/action_import           zh-rCN「从剪切板导入」
//
// NekoBox 是**扁平四项**（无子菜单、无分隔线）。本项目保留两处既有形态差异
// （记录在 docs/design/nekobox-parity.md，不改）：
//   · 导出/导入各有「剪贴板 / 文件」两个子项（NekoBox 的 action_import_file /
//     action_export_file 在另一处菜单，本项目并进同一子菜单）；
//   · 末尾多一项 region 门控的「分享给所有人」（本项目特有，NekoBox 无）。
// 所以断言分两层：**前四项的文案与相对顺序必须逐字等于 NekoBox 词表**，
// 本项目特有项只要求排在规格四项之后。
//
// 被测组件 = 真实 `PerAppProxyPage`（不是抽出来的替身）。页面依赖：
//   · translations（zh-CN，必须 runAsync 预构建 —— slang 非 base 语言是 deferred 库，
//     见 test/features/proxy/proxies_menu_test.dart:20-23 的坑说明）；
//   · Preferences.perAppProxyMode / Preferences.autoAppsSelectionRegion（PreferencesNotifier.create
//     → 只读 sharedPreferencesProvider，mock 初值即可，无需 override 具体 provider）；
//   · ConfigOptions.region（决定 shareToAll 是否渲染，默认 Region.other ⇒ 不渲染）；
//   · PerAppProxyProvider(mode) —— 用 fake notifier 覆写，避免碰 InstalledApps 插件
//     与 drift；fake 的 build 直接吐一个固定 map，页面即可渲染列表；
//   · getApps() 只在 PlatformUtils.isAndroid 时查插件 —— 默认测试平台即 android，
//     但 `InstalledApps` 是 MethodChannel('installed_apps')，widget 测试里没有宿主
//     ⇒ 在 setUp 里拦掉该 channel 返回空列表（对齐"设备上没装应用"的合法状态）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/per_app_proxy_mode.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/per_app_proxy/model/pkg_flag.dart';
import 'package:hiddify/features/per_app_proxy/overview/per_app_proxy_notifier.dart';
import 'package:hiddify/features/per_app_proxy/overview/per_app_proxy_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记录型 fake：不碰 InstalledApps/drift，直接给定选中态；记录反选调用次数。
class FakePerAppProxy extends PerAppProxy {
  FakePerAppProxy(this._selected);

  final Map<String, int> _selected;
  final List<String> calls = [];

  @override
  Stream<Map<String, int>> build(AppProxyMode? mode) => Stream.value(_selected);

  @override
  Future<void> invertSelections() async {
    calls.add('invertSelections');
  }

  @override
  Future<void> clearAll() async {
    calls.add('clearAll');
  }
}

/// 标准测试泵：zh-CN + mock 偏好 + fake 反选记录器 + 真实页面。
Future<({ProviderContainer container, FakePerAppProxy notifier})> _pump(
  WidgetTester tester, {
  Map<String, Object> prefs = const {'per_app_proxy_mode': 'include'},
  Map<String, int> selected = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
  final notifier = FakePerAppProxy(selected);
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
      PerAppProxyProvider(AppProxyMode.include).overrideWith(() => notifier),
    ],
  );
  addTearDown(container.dispose);
  await container.read(translationsProvider.future);
  await container.read(sharedPreferencesProvider.future);
  await container.read(PerAppProxyProvider(AppProxyMode.include).future);

  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: PerAppProxyPage())));
  await tester.pumpAndSettle();
  return (container: container, notifier: notifier);
}

/// 打开 ⋮ 菜单（真实页面用 Icons.more_vert_rounded）。
Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert_rounded));
  await tester.pumpAndSettle();
}

/// 菜单里所有可见文本，按渲染顺序。
List<String> _menuTexts(WidgetTester tester) =>
    tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').where((s) => s.isNotEmpty).toList();

void main() {
  // getApps() 在 android 平台会打 MethodChannel('installed_apps')，测试无宿主 ⇒ 拦成空列表
  // （= 「设备上没装应用」的合法状态；页面此时列表为空，但 AppBar 菜单照常渲染）。
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('installed_apps'),
      (call) async => <dynamic>[],
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('installed_apps'),
      null,
    );
  });

  testWidgets('① 规格四项文案齐备（zh-CN 逐字对齐 NekoBox zh-rCN 词表）', (tester) async {
    await _pump(tester);
    await _openMenu(tester);

    // invert_selections = 反选 / clear_selections = 清空 是 NekoBox 逐字词值；
    // 导出/导入在本项目是子菜单标题（NekoBox 是叶子项，词值取 common.export/import）。
    expect(find.text('反选'), findsOneWidget, reason: 'NekoBox @string/invert_selections = 反选');
    expect(find.text('清空'), findsOneWidget, reason: 'NekoBox @string/clear_selections = 清空');
    expect(find.text('导出'), findsOneWidget, reason: 'NekoBox action_export_clipboard 族的入口');
    expect(find.text('导入'), findsOneWidget, reason: 'NekoBox action_import 族的入口');
  });

  testWidgets('② 权威顺序：反选 → 清空 → 导出 → 导入（= per_app_proxy_menu.xml 行序）', (tester) async {
    await _pump(tester);
    await _openMenu(tester);

    final texts = _menuTexts(tester);
    final spec = ['反选', '清空', '导出', '导入'];
    final actual = texts.where(spec.contains).toList();
    expect(
      actual,
      spec,
      reason:
          'per_app_proxy_menu.xml:3-20 的顺序是 invert → clear → export → import； '
          '菜单顺序必须一致（reason 里带上实际全量文本便于定位：$texts）',
    );
  });

  testWidgets('③ 旧顺序回归：导入不再排在反选/清空之前', (tester) async {
    await _pump(tester);
    await _openMenu(tester);

    final texts = _menuTexts(tester);
    expect(
      texts.indexOf('导入') > texts.indexOf('反选'),
      isTrue,
      reason: '改版前「导入」是首项（hiddify 旧序），NekoBox 里它在末位',
    );
    expect(texts.indexOf('导入') > texts.indexOf('清空'), isTrue);
    expect(texts.indexOf('导出') > texts.indexOf('清空'), isTrue);
    expect(texts.indexOf('导出') < texts.indexOf('导入'), isTrue, reason: '导出在导入之前');
  });

  testWidgets('④ 点「反选」= 调 notifier.invertSelections（真实 handler 接线）', (tester) async {
    final pumped = await _pump(tester, selected: {'com.a': PkgFlag.userSelection.value});
    await _openMenu(tester);
    await tester.tap(find.text('反选'));
    await tester.pumpAndSettle();

    expect(pumped.notifier.calls, contains('invertSelections'), reason: '菜单项必须接到 notifier 的反选入口');
  });

  testWidgets('⑤ 点「清空」= 调 notifier.clearAll（既有行为不回归）', (tester) async {
    final pumped = await _pump(tester);
    await _openMenu(tester);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(pumped.notifier.calls, contains('clearAll'));
  });

  testWidgets('⑥ 导入子菜单两级仍在（more_vert → 导入 → 从剪贴板导入选择）', (tester) async {
    await _pump(tester);
    await _openMenu(tester);
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(find.text('从剪贴板导入选择'), findsOneWidget);
    expect(find.text('从文件导入选择'), findsOneWidget);
  });
}
