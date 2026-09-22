// L1 结构对等测试 —— 分组页 1:1 对照 NekoBox `GroupFragment.kt` +
// `add_group_menu.xml` + `group_action_menu.xml`。
//
// 断言基准 = **zh-CN**（values-zh-rCN/strings.xml 词表）：
//   update_all_subscription=更新所有订阅  group_create=创建分组
//   share_subscription=分享订阅  action_export=导出
//   action_export_clipboard=导出到剪切板  action_export_file=导出到文件
//   share_qr_nfc=二维码  clear_profiles=清空  group_update=更新
//   undo=还原
//
// 规格事实（grep 实证，2026-09-22）：
//   ① 工具栏两枚常驻动作 + **无 FAB**（GroupFragment 无 FloatingActionButton）
//   ② 更新所有订阅带确认框（GroupFragment.kt:116-128）
//   ③ 卡片「更新」仅订阅组（L387 invisible）、「编辑」ungrouped 隐藏（L386）
//   ④ 卡片点击无动作（L384）——本页不提供"点卡片切分组"
//   ⑤ 删除 = 右滑 + 还原 snackbar（L85-88 + UndoSnackbarManager），无 🗑 按钮
//   ⑥ ⋮ 菜单：订阅组才有「分享订阅」组（L406-408 removeItem 同判定）
//
// 被测对象 = `groups_page_spec.dart`（分组页规格投影的唯一数据源，
// widget 层直接渲染它），数据级断言即结构断言。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/proxy/overview/groups_page_spec.dart';

Future<Translations?> _loadZhCn(WidgetTester tester) =>
    tester.runAsync(() => AppLocale.zhCn.build());

void main() {
  testWidgets('工具栏 = add_group_menu 两枚常驻动作（顺序/图标/文案）', (tester) async {
    final t = (await _loadZhCn(tester))!;
    final actions = nkGroupToolbarActions();

    expect(actions.map((a) => a.action),
        [NkGroupToolbarAction.updateAllSubscriptions, NkGroupToolbarAction.createGroup],
        reason: '工具栏顺序权威 = add_group_menu.xml');
    expect(actions.map((a) => a.label(t)), ['更新所有订阅', '创建分组'], reason: '文案逐词 = zh-rCN 词表');
    expect(actions.map((a) => a.icon), [Icons.update_rounded, Icons.playlist_add_rounded],
        reason: '图标 = ic_baseline_update_24 / ic_av_playlist_add 的 Material 对应');
  });

  testWidgets('卡片 ⋮ 菜单 = group_action_menu 树（订阅组才有分享组）', (tester) async {
    final t = (await _loadZhCn(tester))!;

    final subMenu = nkGroupActionMenu(isSubscription: true);
    // 结构：分享订阅[导出到剪切板, 二维码] | 导出[导出到剪切板, 导出到文件] | 清空
    expect(subMenu.length, 3, reason: 'group_action_menu.xml 顶层三项');
    expect(subMenu[0].label(t), '分享订阅');
    expect(subMenu[0].children!.map((c) => c.label(t)), ['导出到剪切板', '二维码']);
    expect(subMenu[0].children!.map((c) => c.action),
        [NkGroupMenuAction.shareUrlToClipboard, NkGroupMenuAction.shareQr]);
    expect(subMenu[1].label(t), '导出');
    expect(subMenu[1].children!.map((c) => c.label(t)), ['导出到剪切板', '导出到文件']);
    expect(subMenu[1].children!.map((c) => c.action),
        [NkGroupMenuAction.exportToClipboard, NkGroupMenuAction.exportToFile]);
    expect(subMenu[2].label(t), '清空');
    expect(subMenu[2].action, NkGroupMenuAction.clearNodes);
    expect(subMenu[2].children, isNull, reason: '清空是叶子（无子菜单）');

    // 非订阅组：无「分享订阅」组（GroupFragment.kt:406-408 removeItem 同判定）。
    final basicMenu = nkGroupActionMenu(isSubscription: false);
    expect(basicMenu.length, 2);
    expect(basicMenu.map((m) => m.label(t)), ['导出', '清空']);
  });

  test('卡片规则：更新按钮仅订阅组；编辑 ungrouped 隐藏；右滑除 ungrouped 外可用', () {
    expect(nkGroupCardShowsUpdate(isSubscription: true), isTrue,
        reason: 'GroupFragment.kt:387 isInvisible 判定');
    expect(nkGroupCardShowsUpdate(isSubscription: false), isFalse);
    expect(nkGroupCardShowsEdit(ungrouped: true), isFalse, reason: 'GroupFragment.kt:386 isGone');
    expect(nkGroupCardShowsEdit(ungrouped: false), isTrue);
    expect(nkGroupCardSwipable(ungrouped: true), isFalse, reason: 'GroupFragment.kt:65-72');
    expect(nkGroupCardSwipable(ungrouped: false), isTrue);
  });
}
