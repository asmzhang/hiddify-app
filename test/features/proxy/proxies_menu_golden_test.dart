// 视觉层 golden 测试 —— ⋮ 菜单真实渲染基线。
//
// 目的：结构层（proxies_menu_test.dart）只断言"有这几项、次序对、文案对"，
// 不断言"看起来对"。本文件把组件真实光栅化成 PNG 固化为基线（goldens/），
// 之后任何视觉回归（间距/层次/溢出/勾选态丢失）直接红测，人眼复核 =
// 打开 PNG 看——渲染是真实 Skia 光栅，非 mock。
//
// 坑与对策（本文件特定，首跑实证）：
// - 测试默认字体 Ahem（全方块）：中文不可读 → FontLoader 载入本机微软雅黑
//   覆写 'Roboto'（Material 默认族）；图标也不可读（more_vert/箭头/✓ 全 tofu）
//   → 载入 SDK cache 的 MaterialIcons-Regular.otf 覆写 'MaterialIcons'。
//   两者缺失时优雅降级（跳过），golden 退化为方块字形但仍可查布局。
// - MaterialApp 默认带 DEBUG 斜纹横幅（右上角）污染 golden → 本文件自建
//   harness 关闭（不动共享 pumpMenu：结构测试不在乎横幅，golden 自包含）。
// - 文件 IO 在 FakeAsync zone 永不完成 → 一律 tester.runAsync。
// - 固定 surface（400×900 @ dpr 1.0）保证 golden 尺寸稳定可 diff。
// - 基线生成：flutter test 本文件 --update-goldens（只在本机跑；CI 不背书
//   跨平台字形，本机即验收环境）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/proxies_menu_button.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'proxies_menu_test.dart';

/// 字体策略（三次实证后的定案）：
/// - 同族多字体（Roboto+雅黑装一个 FontLoader）**不**按 Unicode 回退 —— 二版
///   与三版渲染字节完全一致，族内实际只留一个字体。故放弃合并。
/// - 雅黑单独注册为 'GoldenCjk' 族并设为应用 fontFamily：雅黑自带拉丁字形，
///   全 UI 一种字体，确定性最好（首版实证 TTC 单族加载有效）。
/// - 图标单独 'MaterialIcons' 族（二版实证有效，tofu 消失）。
Future<void> loadRealFonts(WidgetTester tester) async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  const miseRoot = r'C:\Users\Administrator\AppData\Local\mise\installs\flutter\3.38.5';
  final sdkRoots = [
    if (flutterRoot != null) flutterRoot,
    miseRoot,
  ];
  await tester.runAsync(() async {
    Future<bool> loadSingle(String family, String path) async {
      try {
        final file = File(path);
        if (!file.existsSync()) return false;
        final bytes = await file.readAsBytes();
        final loader = FontLoader(family)
          ..addFont(Future<ByteData>.value(
            ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
          ));
        await loader.load();
        return true;
      } catch (_) {
        return false;
      }
    }

    var loaded = await loadSingle('GoldenCjk', r'C:\Windows\Fonts\msyh.ttc');
    if (!loaded) loaded = await loadSingle('GoldenCjk', r'C:\Windows\Fonts\msyh.ttf');
    for (final r in sdkRoots) {
      if (await loadSingle('MaterialIcons', '$r\\bin\\cache\\artifacts\\material_fonts\\MaterialIcons-Regular.otf')) {
        break;
      }
    }
  });
}

/// 与结构测试同款泵法，但自建 harness：关 DEBUG 横幅 + 真字体 + 固定 surface。
Future<ProviderContainer> pumpGolden(WidgetTester tester, {ProxiesSort initial = ProxiesSort.unsorted}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final t = await tester.runAsync(() => AppLocale.zhCn.build());
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      proxiesSortNotifierProvider.overrideWith(() => SeededFakeProxiesSortNotifier(initial)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(translationsProvider.future);

  await loadRealFonts(tester);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'GoldenCjk'),
        home: const Scaffold(body: Center(child: ProxiesMenuButton())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('golden：⋮ 菜单打开态（八项全貌）', (tester) async {
    await pumpGolden(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/proxies_menu_open.png'),
    );
  });

  testWidgets('golden：排序 radio 子菜单打开态（✓ 勾当前项）', (tester) async {
    await pumpGolden(tester, initial: ProxiesSort.name);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('排序'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/proxies_menu_order_submenu.png'),
    );
  });
}
