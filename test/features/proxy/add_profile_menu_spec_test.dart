// L1 结构对等测试 —— 配置页「＋」添加菜单。
// 权威源：NekoBox `add_profile_menu.xml` action_add 子树 + zh-rCN 词表。
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/proxy/data/protocol_form.dart';
import 'package:hiddify/features/proxy/overview/add_profile_menu_spec.dart';

Future<Translations?> _loadZhCn(WidgetTester tester) => tester.runAsync(() => AppLocale.zhCn.build());

void main() {
  testWidgets('移动端顶层：NekoBox 四项在前，添加订阅差异项殿后', (tester) async {
    final t = (await _loadZhCn(tester))!;
    final menu = nkAddProfileMenu(showScanQr: true);

    expect(menu.map((e) => e.action), [
      NkAddProfileAction.scanQr,
      NkAddProfileAction.importClipboard,
      NkAddProfileAction.importFile,
      null,
      NkAddProfileAction.addSubscription,
    ]);
    expect(menu.map((e) => e.label(t)), ['扫描二维码', '从剪切板导入', '从文件中导入', '手动输入', '添加订阅']);
    expect(menu[3].children, isNotNull, reason: '手动设置必须是协议二级菜单，不再弹通用选择对话框');
  });

  testWidgets('桌面顶层隐藏扫码，但保留手动协议子菜单', (tester) async {
    final t = (await _loadZhCn(tester))!;
    final menu = nkAddProfileMenu(showScanQr: false);

    expect(menu.map((e) => e.label(t)), ['从剪切板导入', '从文件中导入', '手动输入', '添加订阅']);
    expect(menu.map((e) => e.action), [
      NkAddProfileAction.importClipboard,
      NkAddProfileAction.importFile,
      null,
      NkAddProfileAction.addSubscription,
    ]);
  });

  test('手动协议菜单顺序完整：补回 VMess，Hysteria 两版本不重名', () {
    final manual = nkManualProtocolMenu();
    expect(manual.map((e) => e.protocol), [
      'socks',
      'http',
      'shadowsocks',
      'vmess',
      'vless',
      'trojan',
      'mieru',
      'naive',
      'hysteria',
      'hysteria2',
      'tuic',
      'shadowtls',
      'anytls',
      'ssh',
      'wireguard',
      'config',
      'chain',
    ]);
    expect(manual.map((e) => e.label(AppLocale.en.buildSync())), [
      'SOCKS',
      'HTTP',
      'Shadowsocks',
      'VMess',
      'VLESS',
      'Trojan',
      'Mieru',
      'Naïve',
      'Hysteria 1',
      'Hysteria 2',
      'TUIC',
      'ShadowTLS',
      'AnyTLS',
      'SSH',
      'WireGuard',
      'Custom Config',
      'Proxy Chain',
    ]);
    expect(manual.every((e) => e.action == NkAddProfileAction.manualNode), isTrue);
    expect(protocolFormSpecFor('vmess')?.type, 'vmess', reason: 'VMess 新建不能复用成 VLESS type');
  });
}
