// K-1 回归：数据层出错 ⇒ **不整页替换已渲染的节点列表**，错误改走 toast。
//
// 规格依据（NekoBox `app/src/main/java/io/nekohasekai/sagernet/ui/ConfigurationFragment.kt`）：
//   列表由 DB 流驱动（`ConfigBuilder.kt:131` 的 `proxyDao.getByGroup`），本身没有失败态；
//   全类错误一律 snackbar / alert（`:317` / `:324` / `:337` / `:451` / `:1588` / `:1678`
//   / `:1704` / `:1729` …），**没有任何"用整页错误替换列表"的分支**。
//
// 本项目缺陷（记为 K-1，取证见 `.workbuddy/acceptance_checklist.md`）：
//   `ProxiesOverviewNotifier.build()` 是 `async*` 生成器，流一报错生成器即终止；
//   riverpod 把状态留在 `AsyncError` 但**带着上一份数据**（`hasValue: true` —— 见
//   riverpod-2.6.1 `lib/src/common.dart:528-539` 的 `AsyncError.copyWithPrevious`），
//   而 `.when` 的 `skipError` 默认 false（同文件 `:738`
//   `if (hasError && (!hasValue || !skipError))`）⇒ 已渲染列表被一行错误文案顶掉，
//   且状态不自愈 ⇒ 错误页永久停留。Windows 560×900 两次复现：`win_23_document.png`、
//   `narrow2_01_config.png`（同构建 1.5 分钟后的 `win_20c_config_recheck.png` 正常）。
//
// 判据：① 出错后列表仍在（ProxyTile 数量不变）；② 屏上不再有整页错误文案；
//       ③ 错误经 `inAppNotificationControllerProvider`（NekoBox 的 snackbar 等价物）报出；
//       ④ 首次加载即失败（没有旧数据）回落空态，同样只走 toast；
//       ⑤ 出错后流继续发数据时列表恢复更新（不卡在错误态）。
//
// 基建照抄 test/features/proxy/groups_page_appbar_spec_test.dart（泵真页面的最小底座）：
//   zh-CN 由 `tester.runAsync` 构建（非基础语言包是 deferred library，FakeAsync 里永不完成），
//   override 只给页面真正 watch 的那几个 provider，其余一个字都不碰。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_page.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

/// 记账版通知控制器：不碰 overlay，直接记下 toast 文本供断言。
class _FakeNotificationController extends InAppNotificationController {
  final errors = <String>[];
  final successes = <String>[];

  @override
  ToastificationItem? showErrorToast(String message) {
    errors.add(message);
    return null;
  }

  @override
  ToastificationItem? showSuccessToast(String message) {
    successes.add(message);
    return null;
  }
}

/// 脚本化列表 notifier：build() 直接给现成 Stream，由用例决定"先出数据、后报错"。
/// 一次 `_pump` 一个新实例（同一实例挂进第二个 ProviderContainer 会炸 LateError）。
class _ScriptedOverviewNotifier extends ProxiesOverviewNotifier {
  _ScriptedOverviewNotifier(this.controller);

  final StreamController<OutboundGroup?> controller;

  @override
  Stream<OutboundGroup?> build() => controller.stream;
}

/// 假连接 notifier：真 `ConnectionNotifier.build()` 会碰连接仓库 / 内核 / InAppReview。
class _FakeConnectionNotifier extends ConnectionNotifier {
  @override
  Stream<ConnectionStatus> build() => Stream<ConnectionStatus>.value(const ConnectionStatus.disconnected());
}

/// 假激活订阅：页面只用 `.valueOrNull?.id`。
class _FakeActiveProfile extends ActiveProfile {
  @override
  Stream<ProfileEntity?> build() => Stream<ProfileEntity?>.value(null);
}

class _Fixture {
  final controller = StreamController<OutboundGroup?>();
  final notifications = _FakeNotificationController();
}

OutboundGroup _group(List<String> names) => OutboundGroup(
  items: [
    for (final name in names) OutboundInfo(tag: 'tag-$name', tagDisplay: name, type: 'anytls', host: 'example.com', port: 443),
  ],
);

Future<_Fixture> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(const {});
  final sp = await SharedPreferences.getInstance();
  final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
  final f = _Fixture();
  addTearDown(f.controller.close);

  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
      // 分组清单走真实现会 await DB / 订阅配置 —— 本用例只关心列表本身，给空清单。
      proxyGroupTabsProvider.overrideWith((ref) => const <ProxyGroupTab>[]),
      proxiesOverviewNotifierProvider.overrideWith(() => _ScriptedOverviewNotifier(f.controller)),
      connectionNotifierProvider.overrideWith(_FakeConnectionNotifier.new),
      activeProfileProvider.overrideWith(_FakeActiveProfile.new),
      hasAnyProfileProvider.overrideWith((ref) => Stream<bool>.value(false)),
      inAppNotificationControllerProvider.overrideWith((ref) => f.notifications),
    ],
  );
  addTearDown(container.dispose);
  await container.read(translationsProvider.future);
  await container.read(sharedPreferencesProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MaterialApp(home: ProxiesOverviewPage())),
  );
  await tester.pump();
  return f;
}

/// 有界泵：页面 build 里有 100ms 的 statsBar Timer（`useEffect` + `Timer`），
/// 加上流是异步投递 —— 固定几拍比 `pumpAndSettle` 稳。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('K-1 · 配置页数据层出错（NekoBox 对齐：列表不换页、错误走 toast）', () {
    testWidgets('已有列表时出错：列表仍在，屏上无整页错误文案，错误改走 toast', (tester) async {
      final f = await _pump(tester);

      f.controller.add(_group(['节点甲', '节点乙']));
      await _settle(tester);
      expect(find.byType(ProxyTile), findsNWidgets(2));
      expect(find.text('节点甲'), findsOneWidget);

      // 数据层报错（内核代理列表流出错 = 生产里 `watchProxies()` 的 Left 重抛）
      f.controller.addError(const ProxyUnexpectedFailure(), StackTrace.current);
      await _settle(tester);

      expect(find.byType(ProxyTile), findsNWidgets(2), reason: 'NekoBox 的列表来自 DB 流，任何时候都不被错误页替换');
      expect(find.text('节点甲'), findsOneWidget);
      expect(find.text('意外错误'), findsNothing, reason: '错误文案不该占满页面');
      expect(tester.takeException(), isNull);
      expect(f.notifications.errors, ['意外错误'], reason: '错误要有出口 —— 等价 NekoBox 的 snackbar');
    });

    testWidgets('首次加载即出错（没有旧数据）：回落空态，不出现整页错误页', (tester) async {
      final f = await _pump(tester);

      f.controller.addError(const ServiceNotRunning(), StackTrace.current);
      await _settle(tester);

      expect(find.text('服务未运行'), findsNothing, reason: '不把错误当页面标题');
      expect(find.text('无可用代理'), findsOneWidget);
      expect(find.byType(ProxyTile), findsNothing);
      expect(f.notifications.errors, ['服务未运行']);
    });

    testWidgets('出错后流继续发数据：列表恢复更新，不卡在错误态', (tester) async {
      final f = await _pump(tester);

      f.controller.add(_group(['节点甲']));
      await _settle(tester);
      expect(find.byType(ProxyTile), findsOneWidget);

      f.controller.addError(const ProxyUnexpectedFailure(), StackTrace.current);
      await _settle(tester);
      expect(find.byType(ProxyTile), findsOneWidget, reason: '错误期间保留上一份列表');

      f.controller.add(_group(['节点甲', '节点乙', '节点丙']));
      await _settle(tester);
      expect(find.byType(ProxyTile), findsNWidgets(3), reason: 'stream 出错不取消订阅（cancelOnError=false），后续数据照收');
      expect(find.text('意外错误'), findsNothing);
    });
  });
}
