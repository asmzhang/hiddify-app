// 添加配置流 L1 spec 测试（spec：.workbuddy/spec-add-profile-flow-tests.md）。
//
// 被测 = AddProfileModal 两页路由 + 手动订阅表单 + 校验闸门 + ProfileLoading。
// 权威源 = lib/features/profile/add/add_profile_modal.dart（288 行）及其 widgets。
// 菜单词表/顺序已由 test/features/proxy/add_profile_menu_spec_test.dart 覆盖——不重复。
//
// 刻意不测：
// - qr 按钮（仅移动端分支，菜单词表已覆盖）；
// - clipboard/file/manual node 的 onTap（原生通道 / GoRouter 依赖）；
// - showAddProfileFromDeepLink 的 SSRF 确认流（dialogNotifier+导航重依赖，集成面覆盖）；
// - addManual 成功链（真实 repo/DB；导入逻辑由 node_import_test 等覆盖）。
//
// 平台分支：FixBtns 用 PlatformUtils.isDesktop（defaultTargetPlatform），
// 测试宿主默认 android（isMobile）→ qr 分支出现；用例 4 显式切 windows（桌面四键）
// 并在用例末尾复位（flutter_test 在用例结束时做不变量检查）。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hiddify/features/profile/add/widgets/loading.dart';
import 'package:hiddify/features/profile/add/widgets/nav_bar.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Translations?> _loadZhCn(WidgetTester tester) =>
    tester.runAsync(() => AppLocale.zhCn.build());

/// 标准泵（对齐 nk_profile_tile_spec_test.pumpTile）：zh-CN 同步翻译 + mock prefs。
/// addProfilePageNotifier / freeSwitchNotifier / addProfileNotifier 的 build
/// 均为纯内存（options / false / AsyncData(null)），无需 fake。
///
/// [settle]=false 用于不定态动画面（ProfileLoading 的 LinearProgressIndicator
/// 永不收敛，pumpAndSettle 会超时）——调用方自行 pump 推进。
/// 泵序列先显式推进 300ms fake 时钟：AddProfileModal.build 的 useMemoized
/// 里有 200ms Future.delayed（剪贴板深链延迟入口），不留 pending timer 给
/// fake_async 的用例末检查。
Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  Map<String, Object> prefs = const {},
  List<Override> overrides = const [],
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final t = (await _loadZhCn(tester))!;
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
      _idleOverride,
      ...overrides,
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
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300)); // 触发 200ms 延迟 Timer（url=null 时为 no-op）
  if (settle) await tester.pumpAndSettle();
  return container;
}

/// fake：addProfileNotifierProvider 不走真实 build——真实 build 有
/// ref.disposeDelay(1min)（lib/utils/riverpod_utils.dart:6），container.dispose
/// 时 onCancel 留 60s pending Timer，晚于 binding 不变量检查触发 fake_async 断言。
/// 方法体 no-op：本测试只断言结构/路由，不触 repo。
class _FakeIdleAddProfileNotifier extends AddProfileNotifier {
  @override
  AsyncValue<Unit?> build() => const AsyncData<Unit?>(null);

  @override
  Future<void> addClipboard(String rawInput) async {}

  @override
  Future<void> addManual({required String url, required UserOverride userOverride}) async {}
}

/// 加载态版（用例⑥）：恒 AsyncLoading → ProfileLoading 面。
class _FakeLoadingAddProfileNotifier extends _FakeIdleAddProfileNotifier {
  @override
  AsyncValue<Unit?> build() => const AsyncLoading<Unit?>();
}

/// 所有用例统一挂 fake（默认空转版；覆盖时传加载版）。
final _idleOverride = addProfileNotifierProvider.overrideWith(_FakeIdleAddProfileNotifier.new);

void main() {
  group('AddProfileModal L1（zh-CN）', () {
    testWidgets('①默认进入选项页：AddProfileOptions + NavBar 可见，手动页不可见', (tester) async {
      await _pump(tester, const AddProfileModal());
      expect(find.byType(AddProfileOptions), findsOneWidget);
      expect(find.byType(AddProfileManual), findsNothing);
      expect(find.byType(NavBar), findsOneWidget);
    });

    testWidgets('②startInManual 直达手动订阅表单页', (tester) async {
      await _pump(tester, const AddProfileModal(startInManual: true));
      await tester.pumpAndSettle();
      expect(find.byType(AddProfileManual), findsOneWidget);
      expect(find.byType(AddProfileOptions), findsNothing);
    });

    testWidgets('③手动表单结构：标题行/名称/URL/开关默认关/自动文案/添加按钮', (tester) async {
      await _pump(tester, const AddProfileModal(startInManual: true));
      final zh = (await _loadZhCn(tester))!;
      expect(find.text(zh.common.manually), findsOneWidget); // 标题行「手动」+ close IconButton
      expect(find.byType(TextFormField), findsNWidgets(2)); // name + url
      expect(find.text(zh.common.name), findsOneWidget);
      expect(find.text(zh.common.url), findsOneWidget);
      expect(find.text(zh.pages.profileDetails.form.disableAutoUpdate), findsOneWidget);
      // 开关默认关 → 自动更新间隔滑杆区展开，初始文案 = 「自动」。
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches, isNotEmpty);
      expect(switches.first.value, isFalse);
      expect(find.text(zh.common.auto), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text(zh.common.add), findsOneWidget);
    });

    testWidgets('④校验闸门：空名→emptyName；名+非法URL→invalidUrl；校验挡住不触 repo', (tester) async {
      await _pump(tester, const AddProfileModal(startInManual: true));
      final zh = (await _loadZhCn(tester))!;
      final button = find.byType(FilledButton);
      // a) 全空点添加 → 「名称为必填项」。
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text(zh.pages.profileDetails.form.emptyName), findsOneWidget);
      // b) 名称 + 非法 URL → 「无效的 URL」。
      await tester.enterText(find.byType(TextFormField).at(0), '测试订阅');
      await tester.enterText(find.byType(TextFormField).at(1), 'not-a-url');
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text(zh.pages.profileDetails.form.invalidUrl), findsOneWidget);
      expect(find.text(zh.pages.profileDetails.form.emptyName), findsNothing);
    });

    testWidgets('⑤桌面 FixBtns 四键 + manually 键交互进手动页（qr 仅移动端）', (tester) async {
      // 平台切换复位必须在测试体末尾手动做——addTearDown 晚于 binding 的
      // foundation 不变量检查（见 test/features/route_rules/test_helpers.dart 同注）。
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await _pump(tester, const AddProfileModal());
      expect(find.byKey(const ValueKey('add_from_clipboard_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('add_from_file_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('add_manually_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('add_manual_node_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('add_by_qr_code_button')), findsNothing, reason: 'qr 仅移动端');
      // 点 manually → goManual（纯内存 provider 切换，无路由依赖）。
      await tester.tap(find.byKey(const ValueKey('add_manually_button')));
      await tester.pumpAndSettle();
      expect(find.byType(AddProfileManual), findsOneWidget);
      debugDefaultTargetPlatformOverride = null; // 测试体末尾复位（不变量检查前）
    });

    testWidgets('⑥加载态：AsyncLoading → ProfileLoading + 取消按钮', (tester) async {
      await _pump(
        tester,
        const AddProfileModal(),
        settle: false,
        overrides: [
          addProfileNotifierProvider.overrideWith(_FakeLoadingAddProfileNotifier.new),
        ],
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ProfileLoading), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget, reason: '取消按钮（invalidate addProfileNotifierProvider），不点');
    });
  });
}
