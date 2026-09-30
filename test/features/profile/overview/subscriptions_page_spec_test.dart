// L1 结构对等测试 —— 订阅页 SubscriptionsPage 1:1 对照 NekoBox 订阅管理面。
// 断言基准 zh-CN。规格与词值：.workbuddy/spec-subscriptions-page-tests.md
// - AppBar：mobile leading=ShellDrawerButton（<600dp），desktop=null；title=订阅；
//   actions=update_rounded（tooltip=更新所有订阅，词对齐 NekoBox update_all_subscription）
//   + add_rounded（tooltip=添加订阅）+ Gap8；
// - 空态：rss_feed 图标 48 + 添加配置文件按钮；
// - 列表：groupOrderProvider（prefs key `profile_group_order`）持久化排序，
//   未上榜 id 回退 order.length+indexOf（subscriptions_page.dart:73-78）；
// - 删除：Dismissible endToStart → deleteProfile → SnackBar 配置文件删除成功 + 撤销。
// 刻意不测：onReorder 手势、NkProfileTile 内部（nk_profile_tile_spec_test 已覆盖）、
// updateAll 真实链路（onPressed 仅 ref.read，不点不 build）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/overview/subscriptions_page.dart';
import 'package:hiddify/features/profile/widget/nk_profile_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

RemoteProfileEntity _remote(String id) => RemoteProfileEntity(
      id: id,
      active: false,
      name: '订阅$id',
      url: 'https://example.com/$id',
      lastUpdate: DateTime(2026, 9, 30, 12),
    );

/// fake：profilesNotifierProvider 不走真实 build——真实 build 依赖
/// profileRepositoryProvider（drift 数据库）。deleteProfile 记账 no-op。
class _FakeProfilesNotifier extends ProfilesNotifier {
  _FakeProfilesNotifier(this.profiles);

  final List<ProfileEntity> profiles;
  final List<ProfileEntity> deleted = [];

  @override
  Stream<List<ProfileEntity>> build() => Stream.value(profiles);

  @override
  Future<void> deleteProfile(ProfileEntity profile) async => deleted.add(profile);
}

/// 标准测试泵：zh-CN 翻译 + mock 偏好（profile_group_order 经 sharedPreferencesProvider 注入，
/// groupOrderProvider 是 PreferencesNotifier.create，无需 provider override。
/// 注意：`List<String>` 型偏好持久化为 `;` 连接字符串（preferences_utils.dart:27-29 getString+split），
/// 预置须用 'p2;p1' 形式而非 StringList）。
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<ProfileEntity> profiles = const [],
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
  final fake = _FakeProfilesNotifier(List.of(profiles));
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
      profilesNotifierProvider.overrideWith(() => fake),
    ],
  );
  addTearDown(container.dispose);
  await container.read(translationsProvider.future);
  await container.read(sharedPreferencesProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63))),
        home: const SubscriptionsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('SubscriptionsPage L1（zh-CN）', () {
    testWidgets('①桌面骨架：title=订阅 + 两 action tooltip 词值 + 无 ShellDrawerButton', (tester) async {
      await _pump(tester, profiles: [_remote('p1')]);

      expect(find.text('订阅'), findsOneWidget);
      expect(find.byIcon(Icons.update_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.byTooltip('更新所有订阅'), findsOneWidget, reason: 'tooltip = t.pages.groups.updateAll');
      expect(find.byTooltip('添加订阅'), findsOneWidget, reason: 'tooltip = t.pages.proxies.addMenu.addSubscription');
      expect(find.byType(ShellDrawerButton), findsNothing, reason: 'desktop leading=null（左侧常驻 rail）');
      expect(find.byType(NkProfileTile), findsOneWidget);
    });

    testWidgets('②空态：rss_feed 图标 + 添加配置文件按钮', (tester) async {
      await _pump(tester);

      expect(find.byIcon(Icons.rss_feed_rounded), findsOneWidget);
      expect(find.text('添加配置文件'), findsOneWidget, reason: '词值 t.pages.profiles.add');
    });

    testWidgets('③排序：order=[p2,p1] → p2 卡在 p1 之前', (tester) async {
      await _pump(
        tester,
        profiles: [_remote('p1'), _remote('p2')],
        prefs: {'profile_group_order': 'p2;p1'},
      );

      expect(find.byType(NkProfileTile), findsNWidgets(2));
      final p2Top = tester.getTopLeft(find.text('订阅p2')).dy;
      final p1Top = tester.getTopLeft(find.text('订阅p1')).dy;
      expect(p2Top < p1Top, isTrue, reason: '持久化顺序 profile_group_order=p2;p1 应生效');
    });

    testWidgets('④排序回退：order 只含 p2 → 未上榜的 p1 排其后', (tester) async {
      await _pump(
        tester,
        profiles: [_remote('p1'), _remote('p2')],
        prefs: {'profile_group_order': 'p2'},
      );

      expect(find.byType(NkProfileTile), findsNWidgets(2));
      final p2Top = tester.getTopLeft(find.text('订阅p2')).dy;
      final p1Top = tester.getTopLeft(find.text('订阅p1')).dy;
      expect(p2Top < p1Top, isTrue, reason: '未上榜 id 回退 order.length+indexOf 排末尾（subscriptions_page.dart:73-78）');
    });

    testWidgets('⑤删除流：Dismissible 右滑 → deleteProfile 记账 + SnackBar 删除成功+撤销', (tester) async {
      final fake = _FakeProfilesNotifier([_remote('p1')]);
      SharedPreferences.setMockInitialValues(const {});
      final sp = await SharedPreferences.getInstance();
      final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
      final container = ProviderContainer(
        overrides: [
          translationsProvider.overrideWith((ref) => Future.value(t)),
          sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
          profilesNotifierProvider.overrideWith(() => fake),
        ],
      );
      addTearDown(container.dispose);
      await container.read(translationsProvider.future);
      await container.read(sharedPreferencesProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63))),
            home: const SubscriptionsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(fake.deleted.map((e) => e.id), ['p1'], reason: 'onDismissed → deleteProfile 被调用');
      expect(find.text('配置文件删除成功'), findsOneWidget, reason: '词值 t.pages.profiles.msg.delete.success');
      expect(find.text('撤销'), findsOneWidget, reason: 'SnackBarAction = t.common.undo');
    });

    testWidgets('⑥mobile 骨架：<600dp → ShellDrawerButton 存在', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester, profiles: [_remote('p1')]);

      expect(find.byType(ShellDrawerButton), findsOneWidget, reason: 'mobile leading=ShellDrawerButton');
    });
  });
}
