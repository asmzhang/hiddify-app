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
}

/// 导航项（唯一数据源）。`profiles` 只在存在 profile 时出现。
///
/// 顺序即导航栏/抽屉的显示顺序，必须与 `_branchFor` 提供的内容一一对应。
List<NavMeta> navMetas(bool showProfilesAction) => [
  const NavMeta(key: 'home', routeName: 'home', path: '/home', icon: Icons.public_rounded, label: _homeLabel),
  if (showProfilesAction)
    const NavMeta(
      key: 'profiles',
      routeName: 'profiles',
      path: '/profiles',
      icon: Icons.view_list_rounded,
      label: _profilesLabel,
    ),
  const NavMeta(
    key: 'subscriptions',
    routeName: 'subscriptions',
    path: '/subscriptions',
    icon: Icons.rss_feed_rounded,
    label: _subscriptionsLabel,
  ),
  const NavMeta(
    key: 'route',
    routeName: 'routingOptions',
    path: '/route',
    icon: Icons.alt_route_rounded,
    label: _routeLabel,
  ),
  const NavMeta(
    key: 'settings',
    routeName: 'settings',
    path: '/settings',
    icon: Icons.settings_rounded,
    label: _settingsLabel,
  ),
  const NavMeta(
    key: 'traffic',
    routeName: 'traffic',
    path: '/traffic',
    icon: Icons.monitor_heart_rounded,
    label: _trafficLabel,
  ),
  const NavMeta(key: 'tools', routeName: 'tools', path: '/tools', icon: Icons.build_rounded, label: _toolsLabel),
  const NavMeta(
    key: 'logs',
    routeName: 'logs',
    path: '/logs',
    icon: Icons.description_rounded,
    label: _logsLabel,
  ),
  const NavMeta(key: 'about', routeName: 'about', path: '/about', icon: Icons.info_rounded, label: _aboutLabel),
];

String _homeLabel(Translations t) => t.pages.proxies.title;
String _profilesLabel(Translations t) => t.pages.profiles.title;
String _subscriptionsLabel(Translations t) => t.pages.subscriptions.title;
String _routeLabel(Translations t) => t.pages.settings.routing.title;
String _settingsLabel(Translations t) => t.pages.settings.title;
String _trafficLabel(Translations t) => t.components.stats.traffic;
String _toolsLabel(Translations t) => t.pages.tools.title;
String _logsLabel(Translations t) => t.pages.logs.title;
String _aboutLabel(Translations t) => t.pages.about.title;
