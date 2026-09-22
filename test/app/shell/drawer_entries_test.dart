// L1 结构对等测试 —— 抽屉 1:1 对照 NekoBox `res/menu/main_drawer_menu.xml`。
//
// 断言基准 = **zh-CN**（values-zh-rCN/strings.xml 词表）：
//   menu_configuration=配置  menu_group=分组  menu_route=路由  settings=设置
//   menu_log=日志  menu_dashboard=sing-box 仪表板  menu_tools=工具
//   document=文档  menu_about=关于  ads=推广（不移植，§3.0#8）
//
// 三个 grep 实证的规格事实（2026-09-22）：
//   ① 抽屉无「订阅」项 —— NekoBox 订阅管理在 GroupSettingsActivity 与 ⋮ 菜单，
//      无独立抽屉入口。我方订阅页/路由保留，仅 navVisible=false（退役不删码）。
//   ② 关于组顺序 = [文档(nav_faq), 关于(nav_about)] —— faq 在 about **之前**；
//      nav_tuiguang 不移植。faq 是动作（外部浏览器），不是路由分支。
//   ③ 无抽屉头 —— layout_main.xml 的 NavigationView 只有 app:menu，无
//      headerLayout，Kotlin 无 addHeaderView（此前实现的「dhead」规格引用不存在）。
//
// 被测对象 = [nkDrawerEntries]（抽屉结构的唯一数据源，widget 层直接渲染它），
// 因此数据级断言即结构断言。图标断言用 IconData 恒等（spec drawable 的
// Material 对应：description/view_list/directions/bug_report/transform/
// construction/data_usage）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/app/shell/nav_items.dart';
import 'package:hiddify/core/localization/translations.dart';

Future<Translations?> _loadZhCn(WidgetTester tester) =>
    tester.runAsync(() => AppLocale.zhCn.build());

void main() {
  testWidgets('抽屉条目序列 = NekoBox 规格顺序（三组 + 分隔线 + faq 位置）', (tester) async {
    final t = (await _loadZhCn(tester))!;
    final entries = nkDrawerEntries(false);

    // 1. 结构骨架：4 项 | 分隔 | 3 项 | 分隔 | faq + 1 项。
    //    类型序列：nav×4, divider, nav×3, divider, faq, nav。
    final types = entries.map((e) => e.runtimeType).toList();
    expect(types, <Type>[
      NkNavEntry, NkNavEntry, NkNavEntry, NkNavEntry,
      NkDividerEntry,
      NkNavEntry, NkNavEntry, NkNavEntry,
      NkDividerEntry,
      NkFaqEntry, NkNavEntry,
    ], reason: '抽屉结构必须 = main_drawer_menu.xml 的三段（含分隔线位置）');

    // 2. zh-rCN 词表逐词对齐（含 faq 动作项）。
    final expectedLabels = [
      '配置', '分组', '路由', '设置',
      '日志', 'sing-box 仪表板', '工具',
      '文档', '关于',
    ];
    final labels = entries
        .map((e) => switch (e) {
              NkNavEntry(:final meta) => meta.label(t),
              NkFaqEntry(:final label) => label(t),
              _ => null,
            })
        .whereType<String>()
        .toList();
    expect(labels, expectedLabels, reason: '抽屉文案必须逐词 = NekoBox zh-rCN 词表');

    // 3. 图标 = spec drawable 的 Material 对应（恒等断言）。
    final expectedIcons = [
      Icons.description_rounded, // nav_configuration ic_action_description
      Icons.view_list_rounded, // nav_group ic_baseline_view_list_24
      Icons.directions_rounded, // nav_route ic_maps_directions
      Icons.settings_rounded, // nav_settings ic_action_settings
      Icons.bug_report_rounded, // nav_logcat ic_baseline_bug_report_24
      Icons.transform_rounded, // nav_traffic ic_baseline_transform_24
      Icons.construction_rounded, // nav_tools baseline_construction_24
      Icons.data_usage_rounded, // nav_faq ic_device_data_usage
      Icons.info_rounded, // nav_about ic_baseline_info_24
    ];
    final icons = entries
        .map((e) => switch (e) {
              NkNavEntry(:final meta) => meta.icon,
              NkFaqEntry(:final icon) => icon,
              _ => null,
            })
        .whereType<IconData>()
        .toList();
    expect(icons, expectedIcons, reason: '抽屉图标必须对应 spec drawable 语义');

    // 4. 「订阅」不在抽屉（回归：navVisible=false，页面/路由保留）。
    final navKeys = entries.whereType<NkNavEntry>().map((e) => e.meta.key).toList();
    expect(navKeys, isNot(contains('subscriptions')), reason: 'NekoBox 抽屉无订阅项');
    expect(navMetas(true).map((m) => m.key), contains('subscriptions'),
        reason: '订阅分支必须保留（仅导航隐藏）');

    // 5. 推广位永不回流。
    expect(navMetas(true).map((m) => m.key), isNot(contains('tuiguang')));
  });

  testWidgets('抽屉选中态映射：faq 插入后 about 的目标索引顺移', (tester) async {
    await _loadZhCn(tester);

    // 可见 metas（hide subscriptions 后）= 8 项，faq 在第 8 个目标位（0-based 7）。
    expect(nkFaqDestinationIndex(false), 7, reason: 'faq = [配置 分组 路由 设置 日志 仪表板 工具] 之后的第 8 个目标');
    expect(nkFaqDestinationIndex(true), 7, reason: 'profiles 本就 navVisible=false，两态一致');

    // navSel → drawer 目标索引：faq 之后的项顺移 +1。
    expect(nkDrawerSelectedIndex(false, 0), 0, reason: 'faq 之前不变');
    expect(nkDrawerSelectedIndex(false, 6), 6, reason: 'faq 之前不变（工具）');
    expect(nkDrawerSelectedIndex(false, 7), 8, reason: '关于在 faq 之后，目标索引 +1');
    expect(nkDrawerSelectedIndex(false, -1), isNull, reason: '隐藏分支无高亮');
  });
}
