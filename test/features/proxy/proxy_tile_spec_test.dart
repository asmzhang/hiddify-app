// L1 结构对等测试 —— 节点卡状态位（NekoBox `ConfigurationFragment.kt:1565-1592`
// 的纯函数投影，见 `proxy_tile_spec.dart`）。词表基准 zh-CN。
//
// 关键规格：
// - 未测速（delay<=0）时**流量文本挪到状态位**（L1565-1572），无流量 = 空字符串
//   （此前实现是 "—" 占位 —— 1:1 修正点）。
// - 错误编码（<0）→ connection_test_* 文案（zh-rCN：连接被拒绝/超时/无法访问/域名不存在）。
// - 已测速 → 延迟毫秒；超时阈值 → '×'。
// - 行2 流量显隐 = hasTraffic && tested（两处只显示一处）。
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/widget/adaptive_menu.dart';
import 'package:hiddify/core/widget/nekobox/nk_card.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile_spec.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Translations?> _loadZhCn(WidgetTester tester) => tester.runAsync(() => AppLocale.zhCn.build());

void main() {
  late Translations t;
  const error = Color(0xFFB3261E);
  const tested = Color(0xFF2E7D32);
  const neutral = Color(0xFF616161);

  testWidgets('状态位分支全表', (tester) async {
    t = (await _loadZhCn(tester))!;

    // 组行：显示当前选中项（架构差异条目，非 spec；trim 在调用点做）。
    expect(
      nkProxyStatus(
        t,
        isGroup: true,
        groupSelectedTagDisplay: 'HK-01',
        delay: 0,
        traffic: null,
        errorColor: error,
        testedColor: tested,
        neutralColor: neutral,
      ),
      (text: 'HK-01', color: neutral),
    );

    // 错误编码 → connection_test_* 文案 + 错误色。
    expect(
      nkProxyStatus(
        t,
        isGroup: false,
        groupSelectedTagDisplay: '',
        delay: -1,
        traffic: null,
        errorColor: error,
        testedColor: tested,
        neutralColor: neutral,
      ).text,
      t.pages.proxies.msg.testRefused,
    );
    expect(
      nkProxyStatus(
        t,
        isGroup: false,
        groupSelectedTagDisplay: '',
        delay: -3,
        traffic: null,
        errorColor: error,
        testedColor: tested,
        neutralColor: neutral,
      ).text,
      t.pages.proxies.msg.testTimeout,
    );
    expect(
      nkProxyStatus(
        t,
        isGroup: false,
        groupSelectedTagDisplay: '',
        delay: -5,
        traffic: null,
        errorColor: error,
        testedColor: tested,
        neutralColor: neutral,
      ).color,
      error,
    );

    // 未测速 + 有流量 → 流量文本挪到状态位。
    expect(
      nkProxyStatus(
        t,
        isGroup: false,
        groupSelectedTagDisplay: '',
        delay: 0,
        traffic: '↑ 1 B ↓ 2 B',
        errorColor: error,
        testedColor: tested,
        neutralColor: neutral,
      ),
      (text: '↑ 1 B ↓ 2 B', color: neutral),
    );

    // 未测速 + 无流量 → **空字符串**（1:1 修正点：此前是 "—"）。
    expect(
      nkProxyStatus(
        t,
        isGroup: false,
        groupSelectedTagDisplay: '',
        delay: 0,
        traffic: null,
        errorColor: error,
        testedColor: tested,
        neutralColor: neutral,
      ).text,
      '',
    );

    // 已测速 → NekoBox `available` 词表的 `%dms`；超时哨兵 → '×'。
    final ok = nkProxyStatus(
      t,
      isGroup: false,
      groupSelectedTagDisplay: '',
      delay: 200,
      traffic: null,
      errorColor: error,
      testedColor: tested,
      neutralColor: neutral,
    );
    expect(ok.text, '200ms');
    expect(ok.color, tested);
    final timeout = nkProxyStatus(
      t,
      isGroup: false,
      groupSelectedTagDisplay: '',
      delay: timeoutOver,
      traffic: null,
      errorColor: error,
      testedColor: tested,
      neutralColor: neutral,
    );
    expect(timeout.text, '×');
  });

  testWidgets('行2 流量显隐：只有已测速才在行2 显示（未测速时流量在状态位）', (tester) async {
    t = (await _loadZhCn(tester))!;
    expect(nkProxyShowTrafficInAddressRow(hasTraffic: true, tested: true), isTrue);
    expect(nkProxyShowTrafficInAddressRow(hasTraffic: true, tested: false), isFalse, reason: '未测速时流量挪到状态位（L1567-1569）');
    expect(nkProxyShowTrafficInAddressRow(hasTraffic: false, tested: true), isFalse);
    expect(nkProxyShowTrafficInAddressRow(hasTraffic: false, tested: false), isFalse);
    expect(nkProxyShowsShare('config'), isTrue, reason: 'Config 保留配置导出菜单');
    expect(nkProxyShowsShare('chain'), isFalse, reason: 'NekoBox Chain 隐藏分享');
    expect(nkProxyTypeLabel(t, type: 'config', isSecure: false, configPayload: '{"route":{}}'), 'sing-box config');
    expect(nkProxyTypeLabel(t, type: 'config', isSecure: false, configPayload: '{"type":"socks"}'), 'socks (sing-box)');
  });

  testWidgets('真实节点卡：320dp 下对齐 NekoBox 文案、颜色和 48dp 操作区', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'always_show_address': true});
    final prefs = await SharedPreferences.getInstance();
    final zhCn = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => Future.value(zhCn)),
        sharedPreferencesProvider.overrideWith((ref) => Future.value(prefs)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(translationsProvider.future);
    await container.read(sharedPreferencesProvider.future);

    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63));
    const longName = '这是一个需要在窄屏换行而不是被截断的节点名称';
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, colorScheme: scheme),
          home: Scaffold(
            body: ProxyTile(
              OutboundInfo(
                tag: 'node-1',
                tagDisplay: longName,
                type: 'anytls',
                host: 'example.com',
                port: 443,
                urlTestDelay: 321,
                upload: Int64(1),
                download: Int64(2),
              ),
              selected: true,
              onTap: () {},
              onEdit: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('AnyTLS'), findsOneWidget);
    expect(find.text('321ms'), findsOneWidget);
    expect(find.text('${1.size()}↑ ${2.size()}↓'), findsOneWidget);
    expect(find.text('example.com:443'), findsOneWidget);

    final name = tester.widget<Text>(find.text(longName));
    final type = tester.widget<Text>(find.text('AnyTLS'));
    final status = tester.widget<Text>(find.text('321ms'));
    expect(name.maxLines, isNull, reason: 'NekoBox profile_name 未限制单行，应允许窄屏换行');
    expect(name.style?.fontSize, type.style?.fontSize);
    expect(type.style?.fontSize, status.style?.fontSize);
    expect(name.style?.fontWeight, FontWeight.w700);
    expect(type.style?.fontWeight, isNot(FontWeight.w600));
    expect(type.style?.color, scheme.secondary);
    expect(status.style?.color, const Color(0xFF4CAF50));

    final actions = find.byType(NkCardAction);
    expect(actions, findsNWidgets(3));
    for (final element in actions.evaluate()) {
      expect(tester.getSize(find.byWidget(element.widget)), const Size.square(48));
    }

    expect(find.byType(AdaptiveMenu), findsOneWidget, reason: '分享按钮必须打开菜单，不能点击即复制');
    await tester.tap(actions.at(1));
    await tester.pumpAndSettle();
    expect(find.text('二维码'), findsOneWidget);
    expect(find.text('导出到剪切板'), findsOneWidget);
    expect(find.text('配置'), findsOneWidget);
  });
}

/// 超过超时阈值的哨兵值（避免测试直接依赖 NkColors 内部阈值常量）。
const timeoutOver = 1 << 30;
