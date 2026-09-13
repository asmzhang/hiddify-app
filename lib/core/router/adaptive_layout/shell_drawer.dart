import 'package:flutter/material.dart';

/// Shell 抽屉的全局 key。
/// 顶级页面（首页 / 设置）在手机端通过 [ShellDrawerButton] 打开左侧导航抽屉。
/// PC 端不使用抽屉（左侧是常驻 NavigationRail），该 key 在此无副作用。
final GlobalKey<ScaffoldState> rootDrawerScaffoldKey = GlobalKey<ScaffoldState>();

/// 手机端顶级页面 AppBar 的汉堡键：打开左侧导航抽屉。
/// 非手机端页面不需要它（用 `Breakpoint(context).isMobile() ? const ShellDrawerButton() : null` 控制）。
class ShellDrawerButton extends StatelessWidget {
  const ShellDrawerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.menu_rounded),
      tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
      onPressed: () => rootDrawerScaffoldKey.currentState?.openDrawer(),
    );
  }
}
