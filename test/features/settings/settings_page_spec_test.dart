// L1 结构对等测试 —— 设置主表 SettingsPage 1:1 对照 NekoBox global_preferences.xml 五类。
// 断言基准 zh-CN。规格与词值：.workbuddy/spec-settings-page-tests.md
// （侦察固化 recon-settings-page-2026-09-30.md；批次 7 = 39f6075a 已做 38 项映射归一）。
// - 五段卡（NkSectionHeader+NkSettingCard）：基础/路由/DNS/入站/其他；
// - 注入面：configOptionNotifierProvider/hasAnyProfileProvider 必须 fake
//   （真实 build 碰 connectionRepository/profileDataSource），其余 mock prefs；
// - 「开机自启」不在此页（桌面规格源 nekoray 把它放在托盘菜单，归一原则）：断言 findsNothing，
//   见 tray_menu_spec_test.dart；
// - 行可见性按 OS（PlatformUtils.isDesktop）而非视口；AppBar 抽屉键/日志关于行按视口
//   （Breakpoint.isMobile() = 逻辑宽 <600）——Windows 宿主 = desktop OS + 可放大视口；
// - 导入菜单两级 SubmenuButton（more_vert → 导入 → 从剪贴板导入选项）；确认框
//   ConfirmationDialog（取消/确定，context.pop 需 GoRouter，同 ③ 路由页坑）；
// - showSettingInput 对话框按钮用 MaterialLocalizations（测试裸 MaterialApp = 英文 CANCEL/OK）。
// 刻意不测：真实导入/导出 IO、LanSharing 按钮流（碰 core 服务）、主题/语言 tile 内部弹窗、
// showSettingPicker 内部、resetOption 全量重置链、connectionNotifier.setCapture 链。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/core/router/navigation_keys.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeConfigOptionNotifier extends ConfigOptionNotifier {
  final List<String> importLog = [];

  @override
  Future<bool> build() async => false;

  @override
  Future<bool> importFromClipboard() async {
    importLog.add('clipboard');
    return true;
  }

  @override
  Future<bool> importFromJsonFile() async {
    importLog.add('file');
    return true;
  }

  @override
  Future<bool> exportJsonClipboard({bool excludePrivate = true}) async => true;

  @override
  Future<bool> exportJsonFile({bool excludePrivate = true}) async => true;

  @override
  Future<void> resetOption() async {}
}

/// 标准测试泵：zh-CN + mock 偏好 + 两个 fake provider + GoRouter（确认框/输入框 context.pop 需要）。
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  bool hasAnyProfile = false,
}) async {
  // PlatformUtils 按 defaultTargetPlatform 判平台（可测试版设计），
  // widget 测试默认 android → 钉 Windows 对齐"Windows 宿主 = desktop OS"前提。
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  // 重置不能走 addTearDown：flutter_test 在 test body 内跑 foundation
  // invariant 检查（binding.dart:1062 → :1073-1078），addTearDown 晚于它，
  // 会炸 "The value of a foundation debug variable was changed by the test."
  // → 每个用例 body 末尾显式调 _resetPlatformOverride()（用例中途断言炸时
  // invariant 整段跳过，不会引入假错）。

  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
      configOptionNotifierProvider.overrideWith(() => _FakeConfigOptionNotifier()),
      hasAnyProfileProvider.overrideWith((ref) => Stream.value(hasAnyProfile)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(translationsProvider.future);
  await container.read(sharedPreferencesProvider.future);

  final router = GoRouter(
    initialLocation: '/',
    navigatorKey: rootNavKey,
    routes: [
      GoRoute(path: '/', builder: (_, _) => SettingsPage()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// 菜单路径：more_vert → 导入（SubmenuButton）→ [item]。
Future<void> _openImportMenu(WidgetTester tester, String item) async {
  await tester.tap(find.byIcon(Icons.more_vert_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.text('导入'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

/// test body 末尾重置平台钉定（原因见 _pump 顶部注释：addTearDown 晚于 invariant 检查）。
void _resetPlatformOverride() {
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  group('SettingsPage L1（zh-CN，desktop 宿主）', () {
    testWidgets('①desktop 骨架：五段头 + 五卡关键行 + 默认值 + 平台/视口分支行', (tester) async {
      // 视口放大：ListView 懒加载，默认 800×600 只 build 可见项。
      tester.view.physicalSize = const Size(1080, 4400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester);

      expect(find.text('设置'), findsOneWidget, reason: 'AppBar title = t.pages.settings.title');
      expect(find.byType(ShellDrawerButton), findsNothing, reason: 'desktop 视口无抽屉按钮');

      // 五段头（NkSectionHeader 直接渲染标题文本）。
      expect(find.text('通用'), findsWidgets);
      expect(find.text('路由'), findsWidgets);
      expect(find.text('DNS'), findsOneWidget);
      expect(find.text('入站'), findsNWidgets(2), reason: '段头 + 入站导航行 title（NkNavRow inbound.title）同词');
      expect(
        find.text('其他'),
        findsNWidgets(2),
        reason: '段头（NkSectionHeader misc）+ 路由卡地区行当前值 trailing（Region.other → regions.other 同词）',
      );

      // 基础卡（Windows 宿主 = desktop OS，desktop 分支行全渲染）。
      expect(
        find.text('开机自启'),
        findsNothing,
        reason: '归一原则：开机自启只在托盘右键菜单（nekoray menu_program），设置页不再有入口',
      );
      expect(find.text('主题色'), findsOneWidget);
      expect(find.text('主题模式'), findsOneWidget);
      expect(find.text('服务模式'), findsOneWidget);
      expect(find.text('MTU'), findsOneWidget);
      expect(find.text('配置流量统计'), findsOneWidget);
      expect(find.text('始终显示地址'), findsOneWidget);
      expect(find.text('日志级别'), findsOneWidget);
      expect(find.text('语言'), findsOneWidget);
      expect(find.text('TUN 实现'), findsNWidgets(2), reason: '基础卡 + 入站卡各一处（归一原则）');
      expect(find.text('关闭时操作'), findsOneWidget);
      expect(find.text('静默启动'), findsOneWidget);
      expect(find.text('在通知中显示速度'), findsNothing, reason: 'android 分支（dynamicNotification），desktop OS 不渲染');
      expect(find.text('触觉反馈'), findsNothing, reason: 'android 分支（hapticFeedback），desktop OS 不渲染');
      expect(find.text('内存限制'), findsOneWidget);

      // 路由卡（perAppProxy = android 分支不渲染）。
      expect(find.text('地区'), findsOneWidget);
      expect(find.text('规则'), findsOneWidget);
      expect(find.text('分应用代理'), findsNothing, reason: 'android 分支，desktop OS 不渲染');
      expect(find.text('解析目的地'), findsOneWidget);
      expect(find.text('在核心中绕过 LAN'), findsOneWidget);
      expect(find.text('IPv6 路由'), findsOneWidget);
      expect(find.text('严格路由'), findsOneWidget);
      expect(find.text('Balancer 策略'), findsOneWidget);

      // DNS 卡 + 默认值。
      expect(find.text('远程 DNS'), findsOneWidget);
      expect(find.text('tcp://8.8.8.8'), findsOneWidget, reason: 'remote-dns-address 默认值');
      expect(find.text('远程 DNS 域名策略'), findsOneWidget);
      expect(find.text('出站服务器解析器（直连）'), findsOneWidget);
      expect(
        find.text('1.1.1.1'),
        findsOneWidget,
        reason: 'direct-dns-address 默认值：defaultValueFunction 按 region 覆盖静态默认（Region.other → "1.1.1.1"，config_option_repository.dart:98）',
      );
      expect(find.text('出站域名策略'), findsOneWidget);
      expect(find.text('启用伪造 DNS'), findsOneWidget);

      // 入站卡 + 默认值。
      expect(find.text('混合端口'), findsOneWidget);
      expect(find.text('12334'), findsOneWidget, reason: 'mixed-port 默认值');
      expect(find.text('接管流量'), findsOneWidget);
      expect(find.text('VPN 共享'), findsOneWidget);
      expect(find.text('透明代理端口 / 重定向端口 / 本地 Direct 端口'), findsOneWidget, reason: '入站导航行 subtitle');

      // 其他卡 + 默认值。
      expect(find.text('连接测试 URL'), findsOneWidget);
      expect(find.textContaining('captive.apple.com'), findsOneWidget, reason: 'connection-test-url 默认值');
      expect(find.text('URL 测试间隔'), findsOneWidget);
      expect(find.text('Clash API'), findsOneWidget);
      expect(find.text('Clash API 端口'), findsOneWidget);
      expect(find.text('16756'), findsOneWidget, reason: 'clash-api-port 默认值');
      expect(find.text('TLS 技巧'), findsOneWidget);
      expect(find.text('尽可能使用 xray-core'), findsOneWidget);
      expect(find.text('更新订阅时允许不安全连接'), findsOneWidget);
      expect(find.text('自定义配置'), findsOneWidget);
      expect(find.text('JSON'), findsNothing, reason: 'custom-config 默认空 → 无 JSON 徽标');

      // mobile 视口分支行（desktop 视口不渲染）。
      expect(find.text('重置 VPN 配置文件'), findsNothing, reason: 'iOS 分支');
      expect(find.text('日志'), findsNothing, reason: 'Breakpoint mobile 分支');
      expect(find.text('关于'), findsNothing, reason: 'Breakpoint mobile 分支');
      _resetPlatformOverride();
    });

    testWidgets('②开机自启在设置页无入口（归一原则：只在托盘菜单）', (tester) async {
      tester.view.physicalSize = const Size(1080, 4400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester);

      // 设置主表与「通用」子页都不得再出现该开关（原 settings_page.dart:147-154
      // 与 general_page.dart:49-56 两处重复入口已删）。词值 zh-CN「开机自启」。
      expect(find.text('开机自启'), findsNothing);
      expect(
        find.byWidgetPredicate((w) {
          if (w is! SwitchListTile) return false;
          final title = w.title;
          return title is Text && title.data == '开机自启';
        }),
        findsNothing,
        reason: '通用子页的 SwitchListTile 入口同样不得存在',
      );
      _resetPlatformOverride();
    });

    testWidgets('③导入确认流：两级菜单 → 确认导入对话框 → 取消不执行 / 确定执行', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = await _pump(tester);
      final fake = container.read(configOptionNotifierProvider.notifier) as _FakeConfigOptionNotifier;

      // 开菜单：一级 = 导入/导出/重置选项；二级导入子菜单 = 两项。
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('导入'), findsOneWidget);
      expect(find.text('导出'), findsOneWidget);
      expect(find.text('重置选项'), findsOneWidget);
      expect(find.text('从剪贴板导入选项'), findsNothing, reason: '子菜单未展开');
      await tester.tap(find.text('导入'));
      await tester.pumpAndSettle();
      expect(find.text('从剪贴板导入选项'), findsOneWidget);
      expect(find.text('从文件导入选项'), findsOneWidget);
      // 关闭菜单（再点 more_vert toggle）。
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      // 从剪贴板导入 → 确认对话框 → 取消。
      await _openImportMenu(tester, '从剪贴板导入选项');
      expect(find.text('确认导入'), findsOneWidget, reason: 'title = t.common.msg.import.confirm');
      expect(find.textContaining('这将用提供的值覆盖所有配置选项'), findsOneWidget, reason: 'msg 词值');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(fake.importLog, isEmpty, reason: '取消后不导入');

      // 再走一遍 → 确定（t.common.ok）→ importFromClipboard。
      await _openImportMenu(tester, '从剪贴板导入选项');
      expect(find.text('确认导入'), findsOneWidget);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(fake.importLog, ['clipboard'], reason: '确认后执行 importFromClipboard');
      _resetPlatformOverride();
    });

    testWidgets('④Clash API 联动：端口行 enabled 随开关（关闭后 tap 不弹输入框）', (tester) async {
      tester.view.physicalSize = const Size(1080, 4400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester, prefs: {'enable-clash-api': true});

      final clashTile = find.ancestor(of: find.text('Clash API'), matching: find.byType(ListTile)).first;
      final initSwitch = tester.widget<Switch>(
        find.descendant(of: clashTile, matching: find.byType(Switch)).first,
      );
      expect(initSwitch.value, isTrue, reason: 'enable-clash-api 默认 true');

      // 端口行可点 → showSettingInput 对话框（row 标题 + dialog 标题同名 → 2 个）。
      final portTile = find.ancestor(of: find.text('Clash API 端口'), matching: find.byType(ListTile)).first;
      await tester.tap(portTile);
      await tester.pumpAndSettle();
      expect(find.text('Clash API 端口'), findsNWidgets(3), reason: '行标题 + 对话框标题 + 输入框 hint（showSettingInput）');
      // 对话框按钮 = MaterialLocalizations（裸 MaterialApp = 英文）。
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(find.text('Clash API 端口'), findsOneWidget, reason: '对话框关闭');

      // 关 Clash API 开关 → 端口行 enabled=false → tap 无效。
      await tester.tap(clashTile);
      await tester.pumpAndSettle();
      final offSwitch = tester.widget<Switch>(
        find.descendant(of: clashTile, matching: find.byType(Switch)).first,
      );
      expect(offSwitch.value, isFalse);

      await tester.tap(portTile);
      await tester.pumpAndSettle();
      expect(find.text('Clash API 端口'), findsOneWidget, reason: 'enabled=false → ListTile.onTap 被忽略');
      _resetPlatformOverride();
    });

    testWidgets('⑤链行门控：hasAnyProfile=false 隐藏 / =true 显示（subtitle=额外安全与解锁器）', (tester) async {
      tester.view.physicalSize = const Size(1080, 4400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester);
      expect(find.text('链'), findsNothing, reason: '无配置文件时链导航行不渲染');

      await _pump(tester, hasAnyProfile: true);
      expect(find.text('链'), findsOneWidget);
      expect(find.text('额外安全与解锁器'), findsOneWidget, reason: '链行 subtitle');
      _resetPlatformOverride();
    });

    testWidgets('⑥customConfig trailing：非空 → JSON 徽标；空 → 无', (tester) async {
      tester.view.physicalSize = const Size(1080, 4400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester, prefs: {'custom-config': '{"a":1}'});
      expect(find.text('JSON'), findsOneWidget, reason: 'customConfig 非空 → trailing Text JSON');

      await _pump(tester);
      final customTile = find.ancestor(of: find.text('自定义配置'), matching: find.byType(ListTile)).first;
      expect(
        find.descendant(of: customTile, matching: find.text('JSON')),
        findsNothing,
        reason: 'customConfig 空 → 无 trailing',
      );
      _resetPlatformOverride();
    });

    testWidgets('⑦mobile 视口：抽屉键 + 日志/关于行出现（desktop OS 行仍渲染）', (tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester);

      expect(find.byType(ShellDrawerButton), findsOneWidget, reason: 'Breakpoint mobile → 抽屉键');
      expect(find.text('静默启动'), findsOneWidget, reason: '行可见性按 OS：Windows 宿主 desktop 行仍渲染');
      expect(find.text('开机自启'), findsNothing, reason: '归一原则：该能力只在托盘右键菜单，任何视口都不在设置页');

      // 日志/关于在页面底部——滚动到可见。
      await tester.scrollUntilVisible(find.text('日志'), 400, scrollable: find.byType(Scrollable).first);
      expect(find.text('日志'), findsOneWidget);
      expect(find.text('关于'), findsOneWidget);
      _resetPlatformOverride();
    });
  });
}
