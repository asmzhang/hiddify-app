// K-1 同形残差回归：分组页数据层出错 ⇒ **不整页替换已渲染的分组列表**，错误改走 toast。
//
// 规格依据（NekoBox `app/src/main/java/io/nekohasekai/sagernet/ui/GroupFragment.kt`）：
//   分组清单由 DAO 驱动（`:168` `SagerDatabase.groupDao.allGroups()`），
//   布局 `res/layout/layout_group.xml:17-27` **只有一个 RecyclerView + appbar**，
//   没有空态/错误态/ViewStub；`reload()` 无 try/catch，**没有任何"用整页错误替换列表"
//   的分支**（`:172-174` 对加载结果唯一的反应是 `notifyDataSetChanged()`）。
//   全类错误一律 snackbar / dialog（`group/GroupInterfaceAdapter.kt:86`、
//   `GroupFragment.kt:152-154`）；空列表就是零行。
//
// 本项目缺陷（K-1 同形，与配置页 `proxies_overview_page.dart:350` 同一形状）：
//   `groups_page.dart:170` 的 `error:` 分支整页替换内容。riverpod 语义见
//   riverpod-2.6.1 `lib/src/common.dart:528-539`（`AsyncError.copyWithPrevious`
//   保留上一份数据的 `hasValue`）与 `:738`（`.when` 的 `skipError` 默认 false）。
//
// 判据（照 test/features/proxy/proxies_overview_error_spec_test.dart 的 K-1 模板）：
//   ① 出错后列表仍在（NkGroupTile 数量不变）；② 屏上无整页错误文案；
//   ③ 错误经 `inAppNotificationControllerProvider`（NekoBox snackbar 的等价物）报出；
//   ④ 首次加载即失败（没有旧数据）回落本页空态 `t.pages.groups.empty`（「空」），只走 toast；
//   ⑤ 出错后重新加载成功，列表恢复。
//
// 基建照抄 test/features/proxy/groups_page_appbar_spec_test.dart（泵真页面的最小底座）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/proxy_group.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/overview/groups_page.dart';
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

/// 数据层失败：走 `ErrorPresenter.errorToPair` 的 `_` 兜底 ⇒ `errors.unexpected`（「意外错误」）。
class _DbFailure implements Exception {
  const _DbFailure();

  @override
  String toString() => 'db failure';
}

typedef _Rows = List<({ProxyGroupEntry group, int nodeCount})>;

ProxyGroupEntry _entry(int id, String name) => ProxyGroupEntry(
  id: id,
  userOrder: id,
  ungrouped: false,
  name: name,
  type: ProxyGroupType.basic,
  order: ProxyGroupOrder.origin,
  isSelector: false,
  frontProxy: -1,
  landingProxy: -1,
);

class _Fixture {
  final notifications = _FakeNotificationController();
  late ProviderContainer container;

  /// 造错开关：`invalidate` 后生效（模拟 DB/仓储层在下一次读取时失败）。
  bool fail = false;
  _Rows rows = const [];
}

Future<_Fixture> _pump(WidgetTester tester, {_Rows rows = const []}) async {
  SharedPreferences.setMockInitialValues(const {});
  final sp = await SharedPreferences.getInstance();
  // slang 非 base 语言是 deferred 库：必须在 runAsync 里 build（HANDOVER §4#13）。
  final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
  final f = _Fixture()..rows = rows;

  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
      // 仓储层读取是 Future：错误必须**异步**到达，才等价于真实路径
      // （同步抛错会在 provider 创建时立即成为初始态，反而绕开"状态变化"事件）。
      proxyGroupListProvider.overrideWith((ref) {
        if (f.fail) return Future<_Rows>.error(const _DbFailure());
        return Future.value(f.rows);
      }),
      inAppNotificationControllerProvider.overrideWith((ref) => f.notifications),
    ],
  );
  f.container = container;
  addTearDown(container.dispose);
  await container.read(translationsProvider.future);
  await container.read(sharedPreferencesProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GroupsPage()),
    ),
  );
  await tester.pumpAndSettle();
  return f;
}

void main() {
  group('K-1 同形 · 分组页数据层出错（NekoBox 对齐：列表不换页、错误走 toast）', () {
    testWidgets('已有列表时出错：列表仍在，屏上无整页错误文案，错误改走 toast', (tester) async {
      final f = await _pump(
        tester,
        rows: [
          (group: _entry(1, '一组'), nodeCount: 2),
          (group: _entry(2, '二组'), nodeCount: 0),
        ],
      );
      expect(find.byType(NkGroupTile), findsNWidgets(2));
      expect(find.text('一组'), findsOneWidget);

      f.fail = true;
      f.container.invalidate(proxyGroupListProvider);
      await tester.pumpAndSettle();

      expect(
        find.byType(NkGroupTile),
        findsNWidgets(2),
        reason: 'NekoBox 的分组列表来自 DAO，任何时候都不被错误页替换',
      );
      expect(find.text('一组'), findsOneWidget);
      expect(find.text('意外错误'), findsNothing, reason: '错误文案不该占满页面');
      expect(tester.takeException(), isNull);
      expect(f.notifications.errors, ['意外错误'], reason: '错误要有出口 —— 等价 NekoBox 的 snackbar');
    });

    testWidgets('首次加载即出错（没有旧数据）：回落本页空态，不出现整页错误页', (tester) async {
      final f = await _pump(tester);
      f.fail = true;
      f.container.invalidate(proxyGroupListProvider);
      await tester.pumpAndSettle();

      expect(find.text('意外错误'), findsNothing, reason: '不把错误当页面文案');
      expect(find.text('空'), findsOneWidget, reason: '回落 t.pages.groups.empty');
      expect(find.byType(NkGroupTile), findsNothing);
      expect(f.notifications.errors, ['意外错误']);
    });

    testWidgets('出错后重新加载成功：列表恢复，不卡在错误态', (tester) async {
      final f = await _pump(tester, rows: [(group: _entry(1, '一组'), nodeCount: 2)]);
      expect(find.byType(NkGroupTile), findsOneWidget);

      f.fail = true;
      f.container.invalidate(proxyGroupListProvider);
      await tester.pumpAndSettle();
      expect(find.byType(NkGroupTile), findsOneWidget, reason: '错误期间保留上一份列表');

      f.fail = false;
      f.rows = [
        (group: _entry(1, '一组'), nodeCount: 2),
        (group: _entry(2, '二组'), nodeCount: 0),
      ];
      f.container.invalidate(proxyGroupListProvider);
      await tester.pumpAndSettle();

      expect(find.byType(NkGroupTile), findsNWidgets(2), reason: 'invalidate 后重新读取，列表恢复');
      expect(find.text('二组'), findsOneWidget);
      expect(find.text('意外错误'), findsNothing);
    });
  });
}
