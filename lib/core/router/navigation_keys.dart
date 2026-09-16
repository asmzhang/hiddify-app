import 'package:flutter/material.dart';

/// 根 Navigator 的 key —— 对话框与底部弹窗都挂在它上面。
///
/// **放在 core 而不是 app 层**：`core/router/dialog` 与 `core/router/bottom_sheets`
/// 需要它（[rootNavKey.currentContext]），而 `core` 不允许反向依赖 `app` 层的组合根。
/// 路由表本身（routing_config_notifier / go_router_notifier）在 `lib/app/routing/`。
final rootNavKey = GlobalKey<NavigatorState>(debugLabel: 'rootNav');
