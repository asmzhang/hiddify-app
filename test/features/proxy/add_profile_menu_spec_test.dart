// L1 结构对等测试 —— 配置页「＋」添加菜单（NekoBox `add_profile_menu.xml`
// 的 `action_add` 子树，词表 zh-rCN 实证）：
//   扫描二维码 / 从剪切板导入 / 从文件中导入 / 手动输入（→ 16 协议创建流）
//   + 架构差异追加项「添加订阅」（NekoBox 走分组设置；本项目订阅是一等实体）。
// 桌面无摄像头扫码 —— 扫码条目按既有 FixBtns 平台规则隐藏。
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/proxy/overview/add_profile_menu_spec.dart';

Future<Translations?> _loadZhCn(WidgetTester tester) =>
    tester.runAsync(() => AppLocale.zhCn.build());

void main() {
  testWidgets('移动端：五条目 + spec 顺序 + 文案', (tester) async {
    final t = (await _loadZhCn(tester))!;
    final menu = nkAddProfileMenu(showScanQr: true);

    expect(menu.map((e) => e.action), [
      NkAddProfileAction.scanQr,
      NkAddProfileAction.importClipboard,
      NkAddProfileAction.importFile,
      NkAddProfileAction.manualNode,
      NkAddProfileAction.addSubscription,
    ], reason: 'spec 顺序在前，架构差异追加项殿后');
    expect(menu.map((e) => e.label(t)), [
      '扫描二维码',
      '从剪切板导入',
      '从文件中导入',
      '手动输入',
      '添加订阅',
    ], reason: '文案逐词 = zh-rCN 词表（末项为本项目差异键）');
  });

  testWidgets('桌面：无扫码条目', (tester) async {
    final t = (await _loadZhCn(tester))!;
    final menu = nkAddProfileMenu(showScanQr: false);

    expect(menu.map((e) => e.action),
        [NkAddProfileAction.importClipboard, NkAddProfileAction.importFile, NkAddProfileAction.manualNode, NkAddProfileAction.addSubscription]);
    expect(menu.map((e) => e.label(t)), ['从剪切板导入', '从文件中导入', '手动输入', '添加订阅']);
  });
}
