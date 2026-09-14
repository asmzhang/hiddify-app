import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/app/shell/my_adaptive_layout.dart';
import 'package:hiddify/app/shell/nav_items.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/custom_transition.dart';
import 'package:hiddify/core/router/go_router/refresh_listenable.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:hiddify/features/intro/widget/intro_page.dart';
import 'package:hiddify/features/log/overview/logs_page.dart';
import 'package:hiddify/features/per_app_proxy/overview/per_app_proxy_page.dart';
import 'package:hiddify/features/profile/details/profile_details_page.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_page.dart';
import 'package:hiddify/features/profile/overview/subscriptions_page.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_page.dart';
import 'package:hiddify/features/route_rules/notifier/rule_notifier.dart';
import 'package:hiddify/features/route_rules/overview/generic_list_page.dart';
import 'package:hiddify/features/route_rules/overview/rule_page.dart';
import 'package:hiddify/features/settings/overview/sections/chain_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/dns_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/features/settings/overview/sections/inbound_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/routing_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/tls_tricks_page.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hiddify/features/stats/overview/stats_overview_page.dart';
import 'package:hiddify/features/tools/overview/tools_page.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'routing_config_notifier.g.dart';

// 每个 shell 分支各有一个 FocusScope。键直接由 navMetas 推导，避免手写漏项/错位。
final branchesScope = <String, FocusScopeNode>{
  for (final meta in navMetas(true)) meta.key: FocusScopeNode(),
};

// when the routing config is not yet initialized, this config is used
final loadingConfig = RoutingConfig(
  routes: <RouteBase>[GoRoute(path: '/home', builder: (context, state) => const Material())],
);

// 导航项顺序 = navMetas 的顺序（唯一数据源）。导航栏/抽屉用 currentIndex 索引分支，
// FocusScope 靠这张表映射回分支名。
List<String> navBranchNames(bool showProfilesAction) => navMetas(showProfilesAction).map((m) => m.key).toList();

String getNameOfBranch(bool showProfilesAction, int index) {
  final names = navBranchNames(showProfilesAction);
  return (index >= 0 && index < names.length) ? names[index] : 'home';
}

@Riverpod(keepAlive: true)
class RoutingConfigNotifier extends _$RoutingConfigNotifier {
  @override
  RoutingConfig build() {
    final isMobileBreakpoint = ref.watch(isMobileBreakpointProvider);
    // 手机端与 PC 端使用同一套导航项：都按是否存在 profile 决定是否显示「节点列表」。
    final showProfilesAction = ref.watch(hasAnyProfileProvider).value ?? false;
    if (isMobileBreakpoint == null) return loadingConfig;
    return RoutingConfig(
      redirect: (context, state) {
        // fix path-parameters for deep link
        String? url;
        if (LinkParser.protocols.contains(state.uri.scheme)) {
          // Android & iOS deep link
          url = state.uri.toString();
        } else if (PlatformUtils.isDesktop && newUrlFromAppLink.isNotEmpty) {
          // Desktops deep link
          url = newUrlFromAppLink;
          newUrlFromAppLink = '';
        } else if (state.uri.queryParameters['url'] != null) {
          // Get the configured URL for intro
          url = state.uri.queryParameters['url'];
        }

        if (!ref.read(Preferences.introCompleted)) {
          // Intro is not completed
          return url != null ? '/intro?url=$url' : '/intro';
        } else if (state.matchedLocation == '/intro') {
          // Intro is completed
          // Current page in '/intro'
          if (url != null && Uri.parse(url).host == 'import') {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) =>
                  ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(url: url, triggeredByDeepLink: true),
            );
          }
          return '/home';
        } else if (url != null && Uri.parse(url).host == 'import') {
          // Auto import profile from url
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(url: url, triggeredByDeepLink: true),
          );
          return '/home';
        } else if (url != null) {
          final uri = Uri.parse(url);
          final path = uri.path + (uri.hasQuery ? "?${uri.query}" : "");
          return path;
        } else if (state.matchedLocation.contains('chain-options') &&
            (ref.watch(hasAnyProfileProvider).value == false)) {
          // Prevent showing chainOptions while hasAnyProfile == false
          return '/settings';
        }
        return null;
      },
      routes: <RouteBase>[
        StatefulShellRoute.indexedStack(
          builder: (_, _, navigationShell) => MyAdaptiveLayout(
            navigationShell: navigationShell,
            isMobileBreakpoint: isMobileBreakpoint,
            showProfilesAction: showProfilesAction,
          ),
          // 分支**顺序完全由 navMetas 决定**；每个分支的内容按 key 在 _branchFor 里定义。
          branches: <StatefulShellBranch>[
            for (final meta in navMetas(showProfilesAction)) _branchFor(meta.key),
          ],
        ),
        GoRoute(name: 'intro', path: '/intro', builder: (_, _) => const IntroPage()),
      ],
    );
  }

  /// 按 key 返回分支内容。key 来自 [navMetas]；**顺序由调用方（navMetas）决定**，与这里无关。
  /// 新增导航项：在 nav_items.dart 的 navMetas 里加一条，然后在这里加一个 case。
  StatefulShellBranch _branchFor(String key) {
    switch (key) {
      case 'home':
        return StatefulShellBranch(
          routes: <GoRoute>[
            GoRoute(
              name: 'home',
              path: '/home',
              builder: (_, _) => FocusScope(node: branchesScope['home'], child: const ProxiesOverviewPage()),
            ),
          ],
        );
      case 'profiles':
        return StatefulShellBranch(
          routes: <GoRoute>[
            GoRoute(
              name: 'profiles',
              path: '/profiles',
              builder: (_, _) => FocusScope(node: branchesScope['profiles'], child: const ProfilesPage()),
              routes: <GoRoute>[
                GoRoute(
                  name: 'profileDetails',
                  path: 'profile-details/:id',
                  pageBuilder: (_, state) => customTransition(
                    TransitionType.fade,
                    state.pageKey,
                    ProfileDetailsPage(id: state.pathParameters['id']!),
                  ),
                ),
              ],
            ),
          ],
        );
      case 'subscriptions':
        return StatefulShellBranch(
          routes: <GoRoute>[
            GoRoute(
              name: 'subscriptions',
              path: '/subscriptions',
              builder: (_, _) => FocusScope(node: branchesScope['subscriptions'], child: const SubscriptionsPage()),
            ),
          ],
        );
      case 'route':
        return StatefulShellBranch(
          routes: <GoRoute>[
            GoRoute(
              name: 'routingOptions',
              path: '/route',
              builder: (context, state) => FocusScope(
                node: branchesScope['route'],
                child: RoutingOptionsPage(routeRule: state.uri.queryParameters['routeRule']),
              ),
              routes: <GoRoute>[
                GoRoute(
                  name: 'rule',
                  path: 'rule/:orderId',
                  pageBuilder: (_, state) {
                    final orderIdString = state.pathParameters['orderId']!;
                    return customTransition(
                      TransitionType.slide,
                      state.pageKey,
                      RulePage(ruleListOrder: orderIdString != 'new' ? int.tryParse(orderIdString) : null),
                    );
                  },
                  onExit: (context, state) async {
                    final t = ref.read(translationsProvider).requireValue;
                    final orderId = int.tryParse(state.pathParameters['orderId']!);
                    final isRuleEdited = ref.read(IsRuleEditedProvider(orderId));
                    if (orderId != null && isRuleEdited) {
                      await ref.read(ruleNotifierProvider(orderId).notifier).save();
                      ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.autoSave.success);
                    }
                    return true;
                  },
                  routes: <GoRoute>[
                    GoRoute(
                      name: 'genericList',
                      path: 'generic-list/:ruleEnum',
                      pageBuilder: (_, state) {
                        final orderId = int.tryParse(state.pathParameters['orderId']!);
                        final ruleEnum = RuleEnum.values.byName(state.pathParameters['ruleEnum']!);
                        return customTransition(
                          TransitionType.slide,
                          state.pageKey,
                          GenericListPage(ruleListOrder: orderId, ruleEnum: ruleEnum),
                        );
                      },
                    ),
                  ],
                ),
                GoRoute(
                  name: 'perAppProxy',
                  path: 'per-app-proxy',
                  pageBuilder: (_, state) =>
                      customTransition(TransitionType.slide, state.pageKey, const PerAppProxyPage()),
                ),
              ],
            ),
          ],
        );
      case 'settings':
        return StatefulShellBranch(
          routes: <GoRoute>[
            GoRoute(
              name: 'settings',
              path: '/settings',
              builder: (context, _) => FocusScope(
                node: branchesScope['settings'],
                child: PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (_, _) => context.goNamed('home'),
                  child: SettingsPage(),
                ),
              ),
              routes: <GoRoute>[
                GoRoute(
                  name: 'general',
                  path: 'general',
                  pageBuilder: (_, state) =>
                      customTransition(TransitionType.slide, state.pageKey, const GeneralPage()),
                ),
                GoRoute(
                  name: 'dnsOptions',
                  path: 'dns-options',
                  pageBuilder: (_, state) =>
                      customTransition(TransitionType.slide, state.pageKey, const DnsOptionsPage()),
                ),
                GoRoute(
                  name: 'inboundOptions',
                  path: 'inbound-options',
                  pageBuilder: (_, state) =>
                      customTransition(TransitionType.slide, state.pageKey, const InboundOptionsPage()),
                ),
                GoRoute(
                  name: 'tlsTricks',
                  path: 'tls-tricks',
                  pageBuilder: (_, state) =>
                      customTransition(TransitionType.slide, state.pageKey, const TlsTricksPage()),
                ),
                GoRoute(
                  name: 'chainOptions',
                  path: 'chain-options',
                  pageBuilder: (_, state) =>
                      customTransition(TransitionType.slide, state.pageKey, const ChainOptionsPage()),
                ),
              ],
            ),
          ],
        );
      case 'traffic':
        return StatefulShellBranch(
          routes: <GoRoute>[
            GoRoute(
              name: 'traffic',
              path: '/traffic',
              builder: (_, _) => FocusScope(node: branchesScope['traffic'], child: const StatsOverviewPage()),
            ),
          ],
        );
      case 'tools':
        return StatefulShellBranch(
          routes: <GoRoute>[
            GoRoute(
              name: 'tools',
              path: '/tools',
              builder: (_, _) => FocusScope(node: branchesScope['tools'], child: const ToolsPage()),
            ),
          ],
        );
      case 'logs':
        return StatefulShellBranch(
          routes: <GoRoute>[
            GoRoute(
              name: 'logs',
              path: '/logs',
              builder: (_, _) => FocusScope(node: branchesScope['logs'], child: const LogsPage()),
            ),
          ],
        );
      case 'about':
        return StatefulShellBranch(
          routes: <GoRoute>[
            GoRoute(
              name: 'about',
              path: '/about',
              builder: (_, _) => FocusScope(node: branchesScope['about'], child: const AboutPage()),
            ),
          ],
        );
      default:
        throw ArgumentError('unknown nav key: $key');
    }
  }
}
