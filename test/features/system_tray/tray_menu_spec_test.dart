// L1 结构对等测试 —— 桌面托盘右键菜单。
// 权威源：nekoray `ui/mainwindow.ui` menu_program（actionStart_with_system = 勾选项）+
// zh-CN 词表。NekoBox 只有 Android 端、没有托盘，故桌面能力以 nekoray 为准。
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/system_tray/tray_menu_spec.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:tray_manager/tray_manager.dart';

Future<Translations> _zhCn(WidgetTester tester) async => (await tester.runAsync(() => AppLocale.zhCn.build()))!;

List<MenuItem> _items(Menu menu) => menu.items!;

void main() {
  group('托盘菜单结构（Windows 宿主）', () {
    testWidgets('顺序 = 连接 / 开机自启 / 服务模式 / 分隔 / 退出；Win 无「显示主界面」', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final t = await _zhCn(tester);

      final menu = nkTrayMenu(
        connection: const ConnectionStatus.disconnected(),
        serviceMode: ServiceMode.systemProxy,
        autoStart: false,
        t: t,
      );
      final items = _items(menu);

      expect(
        items.map((e) => e.key),
        [kTrayMenuKeyConnection, kTrayMenuKeyAutoStart, null, null, kTrayMenuKeyQuit],
        reason: '子菜单与分隔线无 key',
      );
      expect(items.map((e) => e.type), ['normal', 'checkbox', 'submenu', 'separator', 'normal']);
      expect(items.map((e) => e.label), ['连接', '开机自启', '服务模式', null, '退出']);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Linux 追加「显示主界面」+ 分隔（沿用既有平台差异）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final t = await _zhCn(tester);

      final menu = nkTrayMenu(
        connection: const ConnectionStatus.disconnected(),
        serviceMode: ServiceMode.proxy,
        autoStart: false,
        t: t,
      );
      final items = _items(menu);

      expect(items[0].key, kTrayMenuKeyDashboard);
      expect(items[0].label, '仪表盘');
      expect(items[1].type, 'separator');
      expect(items[2].key, kTrayMenuKeyConnection);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('连接项四态词值与禁用态随 isSwitching', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final t = await _zhCn(tester);

      Menu build(ConnectionStatus status) => nkTrayMenu(
        connection: status,
        serviceMode: ServiceMode.proxy,
        autoStart: false,
        t: t,
      );

      expect(_items(build(const ConnectionStatus.disconnected()))[0].label, '连接');
      expect(_items(build(const ConnectionStatus.connecting()))[0].label, '正在连接…');
      expect(_items(build(const ConnectionStatus.connected()))[0].label, '断开连接');
      expect(_items(build(const ConnectionStatus.disconnecting()))[0].label, '断开连接中...');

      expect(_items(build(const ConnectionStatus.disconnected()))[0].disabled, isFalse);
      expect(_items(build(const ConnectionStatus.connecting()))[0].disabled, isTrue, reason: '切换中不可再点');
      expect(_items(build(const ConnectionStatus.disconnecting()))[0].disabled, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('开机自启勾选状态 = 传入的平台实际状态（nekoray setChecked 等价物）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final t = await _zhCn(tester);

      final off = _items(
        nkTrayMenu(
          connection: const ConnectionStatus.disconnected(),
          serviceMode: ServiceMode.proxy,
          autoStart: false,
          t: t,
        ),
      ).firstWhere((e) => e.key == kTrayMenuKeyAutoStart);
      final on = _items(
        nkTrayMenu(
          connection: const ConnectionStatus.disconnected(),
          serviceMode: ServiceMode.proxy,
          autoStart: true,
          t: t,
        ),
      ).firstWhere((e) => e.key == kTrayMenuKeyAutoStart);

      expect(off.checked, isFalse);
      expect(on.checked, isTrue);
      // 勾选项必须是 checkbox 类型：Windows 原生菜单只有 checkbox 会画勾。
      expect(off.type, 'checkbox');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('服务模式子菜单：三项、key = ServiceMode.name、勾选当前项', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final t = await _zhCn(tester);

      final submenu = _items(
        nkTrayMenu(
          connection: const ConnectionStatus.disconnected(),
          serviceMode: ServiceMode.tun,
          autoStart: false,
          t: t,
        ),
      ).firstWhere((e) => e.type == 'submenu');

      final children = submenu.submenu!.items!;
      expect(children.map((e) => e.key), ['proxy', 'systemProxy', 'tun']);
      expect(children.map((e) => e.label), ['仅代理服务', '设置系统代理', 'VPN']);
      expect(children.map((e) => e.checked), [false, false, true]);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('key → 动作映射', () {
    test('已知 key 各自映射，服务模式 key 归一到 serviceMode', () {
      expect(nkTrayMenuAction(kTrayMenuKeyDashboard), NkTrayMenuAction.dashboard);
      expect(nkTrayMenuAction(kTrayMenuKeyConnection), NkTrayMenuAction.connection);
      expect(nkTrayMenuAction(kTrayMenuKeyAutoStart), NkTrayMenuAction.autoStart);
      expect(nkTrayMenuAction(kTrayMenuKeyQuit), NkTrayMenuAction.quit);
      for (final mode in ServiceMode.values) {
        expect(nkTrayMenuAction(mode.name), NkTrayMenuAction.serviceMode);
      }
    });

    test('未知 key / null 返回 null，不再抛 ArgumentError', () {
      // 原实现兜底 `ServiceMode.values.byName(menuItem.key!)` 对任何非服务模式项都抛
      // ArgumentError —— 等于「往菜单里加一项就崩一次」。此断言正是那条回归线。
      expect(nkTrayMenuAction(null), isNull);
      expect(nkTrayMenuAction(''), isNull);
      expect(nkTrayMenuAction('somethingNew'), isNull);
      expect(nkTrayMenuAction('system-proxy'), isNull, reason: '存储 key 不是菜单 key（菜单用 ServiceMode.name）');
    });

    test('服务模式 key 反解出对应枚举，非服务模式项为 null', () {
      expect(trayMenuServiceMode('tun'), ServiceMode.tun);
      expect(trayMenuServiceMode('systemProxy'), ServiceMode.systemProxy);
      expect(trayMenuServiceMode(kTrayMenuKeyAutoStart), isNull);
      expect(trayMenuServiceMode(null), isNull);
    });
  });
}
