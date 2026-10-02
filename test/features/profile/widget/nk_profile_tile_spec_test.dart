// L1 结构对等测试 —— 配置页节点卡 NkProfileTile 1:1 对照 NekoBox `layout_profile.xml`（179 行）。
// 断言基准 zh-CN。权威源规格（xml 实测）：
// - MaterialCardView：margin 4dp / elevation 2dp / clickable（圆角为 hiddify Nk 卡统一 4dp）；
// - 左缘 4dp selected_view（?selectedColorPrimary，默认 invisible → 未选中透明占位）；
// - 行1 名称（bold）+ 行内 edit/share/remove（remove 在 NekoBox 默认 gone，此处常驻为刻意差异，删除走确认弹窗）；
// - 行2 地址（次色）+ 流量（xml 默认 gone、tools:visible → 紧凑形态双行；hiddify 订阅卡常态显示，本地配置收起整行）；
// - 行3 NekoBox = 协议类型 + 状态；hiddify 行3 左 = 订阅状态（到期/余量着色）+ 右 = 最后更新（协议类型并入名称语义，刻意差异）。
// 其余刻意差异（部件头注释同源）：流量进度条降为文字位、「更新」归页 Toolbar。
// 观察点收口（docs/design/ui-real-device-observations-2026-09-22.md:8-11，2026-09-30 定案）：
//   宽屏留白 —— Throne 为 Qt 桌面端（cmake/core/res 结构），无 Android layout 可对照，
//   按 NekoBox 窄列表原样收口，不做内容最大宽度约束；
//   三行 vs 双行 —— 行2 显隐已按形态分化（订阅显示/本地收起），不再另改行距。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/widget/nekobox/nk_card.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/widget/nk_profile_tile.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mb = 1024 * 1024;

SubscriptionInfo _sub({required int upload, required int download, required int total, required DateTime expire}) =>
    SubscriptionInfo(upload: upload, download: download, total: total, expire: expire);

RemoteProfileEntity _remote({bool active = true, SubscriptionInfo? subInfo}) => RemoteProfileEntity(
      id: 'p1',
      active: active,
      name: '测试订阅',
      url: 'https://example.com/sub',
      lastUpdate: DateTime(2026, 9, 30, 12, 5),
      subInfo: subInfo,
    );

/// 标准测试泵：zh-CN 翻译（runAsync 预构建，deferred 库坑见 proxies_menu_test 头注）
/// + mock 偏好（profileTrafficStatistics 闸门等经 sharedPreferencesProvider 注入）。
Future<void> pumpTile(
  WidgetTester tester,
  ProfileEntity profile, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
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
        home: Scaffold(body: NkProfileTile(profile)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 与 pumpTile 内部一致的种子色（确定性），供选中条/错误色断言取值。
final _scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63));

void main() {
  testWidgets('订阅卡三行结构：卡规格 + 名称/动作 + 地址/流量 + 状态/更新时间', (tester) async {
    await pumpTile(
      tester,
      _remote(
        subInfo: _sub(upload: 1024, download: 2048, total: _mb, expire: DateTime.now().add(const Duration(days: 3650))),
      ),
    );

    // 卡规格：margin 4 / elevation 2 / 圆角 4（layout_profile.xml:8,11）。
    final card = tester.widget<Card>(find.byType(Card));
    expect(card.margin, const EdgeInsets.all(4));
    expect(card.elevation, 2);
    final shape = card.shape;
    expect(shape, isA<RoundedRectangleBorder>());
    expect((shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(4));

    // 行1：名称粗体（profile_name textStyle bold）+ 三动作。
    final name = tester.widget<Text>(find.text('测试订阅'));
    expect(name.style?.fontWeight, FontWeight.w700);
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
    expect(find.byType(NkCardAction), findsNWidgets(3), reason: '行内动作 = 编辑/分享/删除');
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

    // 行2：地址（host）+ 流量文字位（进度条降级刻意差异）。
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text((1024 + 2048).sizeOf(_mb)), findsOneWidget, reason: '行2 右 = 已用/总量');

    // 行3：订阅状态（>365 天 → ∞ 词表 remainingDuration）+ 最后更新。
    expect(find.text('剩余 ∞ 天'), findsOneWidget);
    expect(find.text('2026-09-30 12:05'), findsOneWidget);

    // 左缘 4dp 选中条：active → primary（NekoBox selectedColorPrimary）。
    expect(
      find.byWidgetPredicate((w) => w is ColoredBox && w.color == _scheme.primary),
      findsOneWidget,
      reason: '选中态左缘 4dp 条着 primary',
    );
  });

  testWidgets('状态着色分支：已过期/流量已用尽 → 错误色 + w600', (tester) async {
    await pumpTile(
      tester,
      // DateTime(2020) == 2020-01-01（月/日默认 1），确保订阅已过期。
      _remote(subInfo: _sub(upload: 0, download: 0, total: _mb, expire: DateTime(2020))),
    );
    final expired = tester.widget<Text>(find.text('已过期'));
    expect(expired.style?.color, _scheme.error);
    expect(expired.style?.fontWeight, FontWeight.w600);

    await pumpTile(
      tester,
      _remote(
        subInfo: _sub(upload: _mb, download: 0, total: _mb, expire: DateTime.now().add(const Duration(days: 3650))),
      ),
    );
    final usedUp = tester.widget<Text>(find.text('流量已用尽'));
    expect(usedUp.style?.color, _scheme.error);
  });

  testWidgets('本地配置卡：行2 整行收起、无订阅状态，选中条透明占位', (tester) async {
    await pumpTile(
      tester,
      LocalProfileEntity(id: 'p2', active: false, name: '本地配置', lastUpdate: DateTime(2026, 9, 30, 12, 5)),
    );
    expect(find.text('example.com'), findsNothing);
    expect(find.textContaining('剩余'), findsNothing, reason: '本地配置无订阅信息，行3 左收起');
    expect(find.text('2026-09-30 12:05'), findsOneWidget, reason: '行3 右最后更新仍在');
    expect(find.byType(NkCardAction), findsNWidgets(3));
    // 选中条透明占位（selected_view 默认 invisible）：树里有多个透明 ColoredBox
    // （InkWell/装饰层同色），收窄到唯一一个宽 4 的 —— 即左缘选中条。
    final transparentEdges = tester
        .widgetList<ColoredBox>(find.byWidgetPredicate((w) => w is ColoredBox && w.color == Colors.transparent))
        .where((b) => tester.getSize(find.byWidget(b)).width == 4)
        .toList();
    expect(transparentEdges, hasLength(1), reason: '未选中 → 左缘 4dp 选中条透明占位（selected_view 默认 invisible）');
  });

  testWidgets('流量闸门：profileTrafficStatistics=false 时行2 只剩地址（TrafficLooper 对应物）', (tester) async {
    await pumpTile(
      tester,
      _remote(
        subInfo: _sub(upload: 1024, download: 2048, total: _mb, expire: DateTime.now().add(const Duration(days: 3650))),
      ),
      prefs: {'profile_traffic_statistics': false},
    );
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text((1024 + 2048).sizeOf(_mb)), findsNothing);
  });
}
