import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/app/routing/routing_config_notifier.dart';
import 'package:hiddify/core/router/go_router/refresh_listenable.dart';
import 'package:hiddify/core/router/navigation_keys.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'go_router_notifier.g.dart';

/// GoRouter 实例 —— **组合根**：它把"路由表"（[routingConfigNotifierProvider]，
/// 里面有 feature 页面）与 core 的基础设施（[rootNavKey]、[RefreshListenable]）缝起来。
///
/// 为什么不放在 `core/router`：它必然 import feature 页面，留在 core 就成了
/// "基础设施反向依赖业务"。见 docs/audit。
@Riverpod(keepAlive: true)
class GoRouterNotifer extends _$GoRouterNotifer {
  static final rConfig = ValueNotifier<RoutingConfig>(loadingConfig);
  @override
  GoRouter build() {
    ref.listen(routingConfigNotifierProvider, (_, next) => rConfig.value = next);
    return GoRouter.routingConfig(
      initialLocation: '/home',
      navigatorKey: rootNavKey,
      routingConfig: rConfig,
      refreshListenable: RefreshListenable(ref),
      errorBuilder: (context, state) {
        WidgetsBinding.instance.addPostFrameCallback((_) => context.goNamed('home'));
        return const Material();
      },
    );
  }
}
