import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/adaptive_layout/my_adaptive_layout.dart';
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

// each branch in go router has its own focus scope
final branchesScope = <String, FocusScopeNode>{
  'home': FocusScopeNode(),
  'profiles': FocusScopeNode(),
  'route': FocusScopeNode(),
  'settings': FocusScopeNode(),
  'traffic': FocusScopeNode(),
  'tools': FocusScopeNode(),
  'logs': FocusScopeNode(),
  'about': FocusScopeNode(),
};

// when the routing config is not yet initialized, this config is used
final loadingConfig = RoutingConfig(
  routes: <RouteBase>[GoRoute(path: '/home', builder: (context, state) => const Material())],
);

// 导航项顺序必须和 routes 里 branches 的顺序严格一致：
// 导航栏/抽屉用 currentIndex 索引 branches，而 FocusScope 靠这张表映射回分支名。
// 手机端和 PC 端现在使用**同一套**导航项（NekoBox 的做法）。
// （首页和代理页合并后已经不再有独立的 'proxies' 分支。）
List<String> navBranchNames(bool showProfilesAction) =>
    ['home', if (showProfilesAction) 'profiles', 'route', 'settings', 'traffic', 'tools', 'logs', 'about'];

String getNameOfBranch(bool showProfilesAction, int index) {
  final names = navBranchNames(showProfilesAction);
  return (index >= 0 && index < names.length) ? names[index] : 'home';
}

int getIndexOfBranch(bool showProfilesAction, String name) => navBranchNames(showProfilesAction).indexOf(name);

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
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'home',
                  path: '/home',
                  builder: (_, _) => FocusScope(node: branchesScope['home'], child: const ProxiesOverviewPage()),
                ),
              ],
            ),
            // 首页和代理页**已合并**：原来的 proxies 分支取消，那一页由 home 分支承担。
            // （它同时是"开关 + 现状 + 挑选"，所以不需要两个页面。）
            if (showProfilesAction)
              StatefulShellBranch(
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
              ),
            // 「路由规则」提为顶层导航分支（NekoBox 里就是顶层入口）。
            // 路由名保持 'routingOptions' 不变，只把父路径从 settings 下提到 /route，调用方无需改。
            StatefulShellBranch(
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
                          ref
                              .read(inAppNotificationControllerProvider)
                              .showSuccessToast(t.common.msg.autoSave.success);
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
            ),
            StatefulShellBranch(
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
                    // 「路由规则」已提为顶层分支 'routingOptions'（见上方 branches）。
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
                    // logs / about 现在是顶层导航分支（见下方 branches），不再嵌在设置里。
                  ],
                ),
              ],
            ),
            // 「流量面板」：用现有 stats 组件融合出的整页仪表盘（非 NekoBox 的 Clash 网页）。
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'traffic',
                  path: '/traffic',
                  builder: (_, _) => FocusScope(node: branchesScope['traffic'], child: const StatsOverviewPage()),
                ),
              ],
            ),
            // 「工具」：融合现有备份/恢复/重置能力（NekoBox 工具=网络+备份）。
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'tools',
                  path: '/tools',
                  builder: (_, _) => FocusScope(node: branchesScope['tools'], child: const ToolsPage()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'logs',
                  path: '/logs',
                  builder: (_, _) => FocusScope(node: branchesScope['logs'], child: const LogsPage()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'about',
                  path: '/about',
                  builder: (_, _) => FocusScope(node: branchesScope['about'], child: const AboutPage()),
                ),
              ],
            ),
          ],
        ),
        GoRoute(name: 'intro', path: '/intro', builder: (_, _) => const IntroPage()),
      ],
    );
  }
}
