import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';

/// 一个顶层导航项 == 一个 shell 分支。
///
/// **这是导航的唯一数据源**：分支顺序、导航栏/抽屉条目、FocusScope 键全部从这张表推导，
/// 从根上消除"加一个导航项要改 4 处"造成的错位 / 重名问题。
///
/// 新增导航项时：只在 [navMetas] 里加一条，并到 `routing_config_notifier.dart` 的
/// `_branchFor(key)` 里补上该分支的内容；其余（navBranchNames / branchesScope / _actions）
/// 全自动跟进。
class NavMeta {
  const NavMeta({
    required this.key,
    required this.routeName,
    required this.path,
    required this.icon,
    required this.label,
    required this.group,
    this.navVisible = true,
  });

  /// shell 分支 key（同时用作 branchesScope / navBranchNames 的键）。
  final String key;

  /// go_router 路由名（**全局唯一**）。
  final String routeName;

  /// 顶层路径（以 `/` 开头）。
  final String path;

  final IconData icon;

  /// 导航标签。
  final String Function(Translations t) label;

  /// 是否出现在导航栏/抽屉里。`false` = 仅路由可达（导航中隐藏），但仍是一个 shell 分支。
  final bool navVisible;

  /// NekoBox 复刻 · 抽屉分组（对应 main_drawer_menu.xml 的三段，
  /// 组与组之间画分隔线）。Rail（桌面）不分组，平铺。
  final NkNavGroup group;
}

/// 抽屉的三段分组（对标 NekoBox main_drawer_menu.xml）：
/// ① 配置/分组/路由/设置 ② 日志/仪表盘/工具 ③ 关于。
enum NkNavGroup { configs, tools, about }

/// 导航项（唯一数据源）。`profiles` 只在存在 profile 时出现。
///
/// 顺序即导航栏/抽屉的显示顺序，必须与 `_branchFor` 提供的内容一一对应。
List<NavMeta> navMetas(bool showProfilesAction) => [
  const NavMeta(
    key: 'home',
    routeName: 'home',
    path: '/home',
    icon: Icons.description_rounded,
    label: _homeLabel,
    group: NkNavGroup.configs,
  ),
  if (showProfilesAction)
    const NavMeta(
      key: 'profiles',
      routeName: 'profiles',
      path: '/profiles',
      icon: Icons.view_list_rounded,
      label: _profilesLabel,
      // 「订阅」页已覆盖配置管理，节点列表不再进导航；页面/路由保留（从首页订阅摘要等进入）。
      navVisible: false,
      group: NkNavGroup.configs,
    ),
  // NekoBox 抽屉第 2 项 `nav_group`（`main_drawer_menu.xml`）：分组管理页。
  // 顺序照它放在"配置"之后、"路由"之前。
  const NavMeta(
    key: 'groups',
    routeName: 'groups',
    path: '/groups',
    icon: Icons.view_list_rounded,
    label: _groupsLabel,
    group: NkNavGroup.configs,
  ),
  const NavMeta(
    key: 'subscriptions',
    routeName: 'subscriptions',
    path: '/subscriptions',
    icon: Icons.rss_feed_rounded,
    label: _subscriptionsLabel,
    // NekoBox 抽屉无「订阅」项（订阅管理在分组设置 + ⋮ 更新当前组订阅，
    // main_drawer_menu.xml grep 实证）——导航隐藏（退役不删码），页面/路由保留。
    // TODO(feature-2+): 分组页补订阅管理入口（对位 GroupSettingsActivity）。
    navVisible: false,
    group: NkNavGroup.configs,
  ),
  const NavMeta(
    key: 'route',
    routeName: 'routingOptions',
    path: '/route',
    icon: Icons.directions_rounded,
    label: _routeLabel,
    group: NkNavGroup.configs,
  ),
  const NavMeta(
    key: 'settings',
    routeName: 'settings',
    path: '/settings',
    icon: Icons.settings_rounded,
    label: _settingsLabel,
    group: NkNavGroup.configs,
  ),
  const NavMeta(
    key: 'logs',
    routeName: 'logs',
    path: '/logs',
    icon: Icons.bug_report_rounded,
    label: _logsLabel,
    group: NkNavGroup.tools,
  ),
  const NavMeta(
    key: 'traffic',
    routeName: 'traffic',
    path: '/traffic',
    icon: Icons.transform_rounded,
    label: _trafficLabel,
    group: NkNavGroup.tools,
  ),
  const NavMeta(
    key: 'tools',
    routeName: 'tools',
    path: '/tools',
    icon: Icons.construction_rounded,
    label: _toolsLabel,
    group: NkNavGroup.tools,
  ),
  const NavMeta(
    key: 'about',
    routeName: 'about',
    path: '/about',
    icon: Icons.info_rounded,
    label: _aboutLabel,
    group: NkNavGroup.about,
  ),
];

String _homeLabel(Translations t) => t.pages.proxies.title;
String _profilesLabel(Translations t) => t.pages.profiles.title;
String _subscriptionsLabel(Translations t) => t.pages.subscriptions.title;
String _groupsLabel(Translations t) => t.pages.groups.title;
String _routeLabel(Translations t) => t.pages.settings.routing.title;
String _settingsLabel(Translations t) => t.pages.settings.title;
String _trafficLabel(Translations t) => t.pages.traffic.title;
String _toolsLabel(Translations t) => t.pages.tools.title;
String _logsLabel(Translations t) => t.pages.logs.title;
String _aboutLabel(Translations t) => t.pages.about.title;

/// 导航栏/抽屉**可见**的项（过滤掉 `navVisible == false`）。
List<NavMeta> navVisibleMetas(bool showProfilesAction) =>
    navMetas(showProfilesAction).where((m) => m.navVisible).toList();

/// 分支索引 → 可见导航索引（该分支被隐藏时返回 -1）。
int navIndexForBranch(bool showProfilesAction, int branchIndex) {
  final all = navMetas(showProfilesAction);
  if (branchIndex < 0 || branchIndex >= all.length) return -1;
  return navVisibleMetas(showProfilesAction).indexWhere((m) => m.key == all[branchIndex].key);
}

/// 可见导航索引 → 分支索引（越界返回 -1）。
int branchIndexForNav(bool showProfilesAction, int navIndex) {
  final visible = navVisibleMetas(showProfilesAction);
  if (navIndex < 0 || navIndex >= visible.length) return -1;
  final key = visible[navIndex].key;
  return navMetas(showProfilesAction).indexWhere((m) => m.key == key);
}

/// 抽屉条目（NekoBox main_drawer_menu.xml 的 1:1 投影）。
///
/// 三段结构 = [配置 分组 路由 设置] | [日志 仪表板 工具] | [文档(faq 动作) 关于]，
/// 组间画分隔线。faq 在 about **之前**（spec：nav_faq 先于 nav_about）；
/// nav_tuiguang（推广）不移植（§3.0#8）。抽屉**无头**（NekoBox NavigationView
/// 无 headerLayout——此前实现的「dhead」规格引用不存在，2026-09-22 grep 实证）。
sealed class NkDrawerEntry {
  const NkDrawerEntry();
}

/// 导航项（路由分支）。
class NkNavEntry extends NkDrawerEntry {
  const NkNavEntry(this.meta);
  final NavMeta meta;
}

/// 组间分隔线。
class NkDividerEntry extends NkDrawerEntry {
  const NkDividerEntry();
}

/// 抽屉动作项（NekoBox nav_faq → 外部浏览器打开文档站），不是路由分支。
class NkFaqEntry extends NkDrawerEntry {
  const NkFaqEntry(this.label, this.icon);
  final String Function(Translations t) label;
  final IconData icon;
}

/// 抽屉条目序列（唯一数据源；widget 层直接渲染，不二次推导）。
List<NkDrawerEntry> nkDrawerEntries(bool showProfilesAction) {
  final entries = <NkDrawerEntry>[];
  NkNavGroup? last;
  for (final meta in navVisibleMetas(showProfilesAction)) {
    if (last != null && meta.group != last) entries.add(const NkDividerEntry());
    last = meta.group;
    // spec：关于组 = [nav_faq, nav_about] —— faq 是该组第一个条目。
    if (meta.group == NkNavGroup.about && !entries.any((e) => e is NkFaqEntry)) {
      entries.add(const NkFaqEntry(_faqLabel, Icons.data_usage_rounded));
    }
    entries.add(NkNavEntry(meta));
  }
  return entries;
}

String _faqLabel(Translations t) => t.pages.about.faq;

/// faq 在抽屉**目标**（NavigationDrawerDestination）序列里的索引（分隔线不占位）。
int nkFaqDestinationIndex(bool showProfilesAction) {
  final entries = nkDrawerEntries(showProfilesAction);
  var destIndex = 0;
  for (final e in entries) {
    if (e is NkDividerEntry) continue;
    if (e is NkFaqEntry) return destIndex;
    destIndex++;
  }
  return -1;
}

/// navSel（可见 metas 索引）→ 抽屉目标索引：faq 之后的项顺移 +1；隐藏分支 = null。
int? nkDrawerSelectedIndex(bool showProfilesAction, int navSel) {
  if (navSel < 0) return null;
  final faqPos = nkFaqDestinationIndex(showProfilesAction);
  return navSel >= faqPos ? navSel + 1 : navSel;
}
