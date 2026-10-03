// K-1 同形残差回归：规则编辑页的「安卓应用」清单数据层出错 ⇒ **不整页替换**，
// 错误改走 toast；没有旧数据时回落本页的空渲染（空白内容区）。
//
// 规格依据（NekoBox `app/src/main/java/io/nekohasekai/sagernet/ui/AppListActivity.kt`）：
//   `loadApps()`（`:175-189`）先 `loading.crossFadeFrom(binding.list)`，
//   再 `if (apps.isEmpty()) { binding.list.visibility = View.GONE;
//   binding.appPlaceholder.root.crossFadeFrom(loading) } else { binding.list.crossFadeFrom(loading) }`
//   —— **只有"空清单"才切占位视图，没有任何"用错误页替换列表"的分支**；
//   `adapter.reload()`（`:102-108`）无 try/catch，错误一律 Snackbar
//   （`:274`/`:290`/`:299`）。占位布局 `res/layout/layout_app_placeholder.xml` 是
//   「权限被拒 + 去设置按钮」，本项目无此 widget/文案 ⇒ 记为形态分化，不在此处新增。
//
// 本项目缺陷（K-1 同形，与配置页 `proxies_overview_page.dart:350`、
// 分组页 `groups_page.dart:170` 同一形状）：
//   `android_apps_page.dart:133` `error: (error, stack) => Center(child: Text('Error: $error'))`
//   —— 整页替换 + 硬编码英文 + 裸异常文本。riverpod 语义见 riverpod-2.6.1
//   `lib/src/common.dart:528-539`（`AsyncError.copyWithPrevious` 保留上一份数据的
//   `hasValue`）与 `:738`（`.when` 的 `skipError` 默认 false）。
//
// 判据（照 test/features/proxy/groups_page_error_spec_test.dart 的 K-1 模板）：
//   ① 出错后清单仍在（CheckboxListTile 数量不变）；② 屏上无错误文案（`Error:` / 原始异常）；
//   ③ 错误经 `inAppNotificationControllerProvider`（NekoBox snackbar 的等价物）报出；
//   ④ 首次加载即失败（没有旧数据）不出现整页错误文案，只走 toast；
//   ⑤ 出错后重新加载成功，清单恢复。
//
// 夹具要点：`installed_apps` / `PlatformUtils.isAndroid` 在 `flutter test` 下会被强制为
// android（asserts 打开）⇒ 必须覆盖 `appPackagesProvider`，否则打插件。
// `SelectedPackagesNotifier.build` 读 `ruleNotifierProvider`（碰 DB）⇒ 必须换假实现。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/route_rules/notifier/android_apps_notifier.dart';
import 'package:hiddify/features/route_rules/overview/android_apps_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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

/// 数据层失败：走 `ErrorPresenter.errorToPair` 的 `_` 兜底 ⇒ `errors.unexpected`（「意外错误」）。
class _ListFailure implements Exception {
  const _ListFailure();

  @override
  String toString() => 'list failure';
}

/// 假的已选集合：真实实现 `build` 会读 `ruleNotifierProvider`（碰 DB）。
class _FakeSelectedPackages extends SelectedPackagesNotifier {
  @override
  List<String> build(int? ruleListOrder) => const [];
}

class _Fixture {
  final notifications = _FakeNotificationController();
  late ProviderContainer container;

  /// 造错开关：`invalidate` 后生效（模拟插件/数据层在下一次读取时失败）。
  bool fail = false;
  List<dynamic> items = const [];
}

Future<_Fixture> _pump(WidgetTester tester, {List<dynamic> items = const [], bool fail = false}) async {
  // slang 非 base 语言是 deferred 库：必须在 runAsync 里 build（HANDOVER §4#13）。
  final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
  final f = _Fixture()
    ..items = items
    ..fail = fail;

  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      // 打插件会 MissingPluginException；本页 `:21` 只 watch 不用结果。
      appPackagesProvider.overrideWith((ref) => const <String>[]),
      selectedPackagesNotifierProvider(null).overrideWith(() => _FakeSelectedPackages()),
      // 数据层读取是 Future：错误必须**异步**到达，才等价于真实路径。
      filterBySearchProvider(null).overrideWith((ref) {
        if (f.fail) return Future<List<dynamic>>.error(const _ListFailure());
        return Future<List<dynamic>>.value(f.items);
      }),
      inAppNotificationControllerProvider.overrideWith((ref) => f.notifications),
    ],
  );
  f.container = container;
  addTearDown(container.dispose);
  await container.read(translationsProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AndroidAppsPage()),
    ),
  );
  await tester.pumpAndSettle();
  return f;
}

void main() {
  group('K-1 同形 · 安卓应用清单数据层出错（NekoBox 对齐：清单不换页、错误走 toast）', () {
    testWidgets('已有清单时出错：清单仍在，屏上无错误文案，错误改走 toast', (tester) async {
      final f = await _pump(tester, items: const ['com.example.a', 'com.example.b']);
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      expect(find.text('com.example.a'), findsOneWidget);

      f.fail = true;
      f.container.invalidate(filterBySearchProvider(null));
      await tester.pumpAndSettle();

      expect(
        find.byType(CheckboxListTile),
        findsNWidgets(2),
        reason: 'NekoBox 的清单来自 adapter，出错时不被错误视图替换',
      );
      expect(find.text('com.example.a'), findsOneWidget);
      expect(find.textContaining('Error:'), findsNothing, reason: '错误文案不该占满页面');
      expect(find.textContaining('list failure'), findsNothing, reason: '裸异常不该上屏');
      expect(tester.takeException(), isNull);
      expect(f.notifications.errors, ['意外错误'], reason: '错误要有出口 —— 等价 NekoBox 的 snackbar');
    });

    testWidgets('首次加载即出错（没有旧数据）：不出现整页错误页，只走 toast', (tester) async {
      final f = await _pump(tester, fail: true);

      expect(find.textContaining('Error:'), findsNothing, reason: '不把错误当页面文案');
      expect(find.textContaining('list failure'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(tester.takeException(), isNull);
      expect(f.notifications.errors, ['意外错误']);
    });

    testWidgets('出错后重新加载成功：清单恢复，不卡在错误态', (tester) async {
      final f = await _pump(tester, items: const ['com.example.a']);
      expect(find.byType(CheckboxListTile), findsOneWidget);

      f.fail = true;
      f.container.invalidate(filterBySearchProvider(null));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsOneWidget, reason: '错误期间保留上一份清单');

      f.fail = false;
      f.items = const ['com.example.a', 'com.example.b', 'com.example.c'];
      f.container.invalidate(filterBySearchProvider(null));
      await tester.pumpAndSettle();

      expect(find.byType(CheckboxListTile), findsNWidgets(3), reason: 'invalidate 后重新读取，清单恢复');
      expect(find.text('com.example.c'), findsOneWidget);
      expect(find.textContaining('Error:'), findsNothing);
    });
  });
}
