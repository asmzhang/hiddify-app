import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:tray_manager/tray_manager.dart';

/// 托盘右键菜单规格 —— 桌面端（nekoray/Throne）的 `menu_program`。
///
/// 抽成纯数据规格的原因有两层：
/// 1. 托盘菜单此前内联在 `SystemTrayNotifier._trayMenu` 里，只有跑在真机上才看得到，
///    单测无法回归（`trayManager` 是平台通道单例）；
/// 2. 「开机自启」在桌面规格源里**只属于托盘菜单**，不属于设置页 —— 把这个归属写成
///    可断言的规格，才挡得住设置页再长出第二个入口（归一原则）。
///
/// NekoBox 只有 Android 端，没有托盘，故桌面端以 nekoray 为准：
/// `ui/mainwindow.ui` 的 `menu_program`（`:503-517`）里 `actionStart_with_system`
/// 是一个 checkable 项，位置在 `separator` 之后、其余功能项之前
/// （`ui/mainwindow.cpp:233` 把整个 `menu_program` 设为托盘上下文菜单）。
/// 本仓库的托盘菜单是 Hiddify 自己的结构（连接开关 / 服务模式子菜单），
/// 因此「开机自启」按其分组语义落在**连接开关之后、服务模式子菜单之前**。
enum NkTrayMenuAction { dashboard, connection, autoStart, serviceMode, quit }

/// 菜单项 key（同时也是 `nkTrayMenuAction` 的入参口径）。
const String kTrayMenuKeyDashboard = 'dashboard';
const String kTrayMenuKeyConnection = 'connection';
const String kTrayMenuKeyAutoStart = 'autoStart';
const String kTrayMenuKeyQuit = 'quit';

/// key → 动作。**未知 key 返回 null**（调用方负责 log 后返回）。
///
/// 这里替掉的是原先 `onTrayMenuItemClick` 的兜底 `ServiceMode.values.byName(menuItem.key!)`：
/// 那句对任何非服务模式的 key 都会抛 `ArgumentError`，等于「以后往菜单里加一项就崩一次」。
NkTrayMenuAction? nkTrayMenuAction(String? key) {
  switch (key) {
    case kTrayMenuKeyDashboard:
      return NkTrayMenuAction.dashboard;
    case kTrayMenuKeyConnection:
      return NkTrayMenuAction.connection;
    case kTrayMenuKeyAutoStart:
      return NkTrayMenuAction.autoStart;
    case kTrayMenuKeyQuit:
      return NkTrayMenuAction.quit;
  }
  if (key != null && ServiceMode.values.any((e) => e.name == key)) return NkTrayMenuAction.serviceMode;
  return null;
}

/// 服务模式项 key → [ServiceMode]；非服务模式项返回 null。
ServiceMode? trayMenuServiceMode(String? key) {
  if (key == null) return null;
  for (final mode in ServiceMode.values) {
    if (mode.name == key) return mode;
  }
  return null;
}

Menu nkTrayMenu({
  required ConnectionStatus connection,
  required ServiceMode serviceMode,
  required bool autoStart,
  required Translations t,
}) => Menu(
  items: [
    // 「显示主界面」只有 Linux 需要（Windows/macOS 左键单击图标即可，见 notifier 的
    // onTrayIconMouseDown）；沿用既有行为，不在此处改动。
    if (PlatformUtils.isLinux) ...[
      MenuItem(key: kTrayMenuKeyDashboard, label: t.common.dashboard),
      MenuItem.separator(),
    ],
    MenuItem(
      key: kTrayMenuKeyConnection,
      label: switch (connection) {
        Disconnected() => t.connection.connect,
        Connecting() => t.connection.connecting,
        Connected() => t.connection.disconnect,
        Disconnecting() => t.connection.disconnecting,
      },
      disabled: connection.isSwitching,
    ),
    // nekoray `actionStart_with_system`：勾选项，勾选状态 = 平台实际状态
    // （nekoray 在菜单弹出时 `setChecked(AutoRun_IsEnabled())`；此处改为随状态变化重建菜单，
    // 理由见 notifier 的 `_initializeTray`）。
    MenuItem.checkbox(key: kTrayMenuKeyAutoStart, checked: autoStart, label: t.pages.settings.general.autoStart),
    MenuItem.submenu(
      label: t.pages.settings.inbound.serviceMode,
      icon: Assets.images.trayIconIco,
      submenu: Menu(
        items: [
          ...ServiceMode.values.map((e) => MenuItem.checkbox(checked: e == serviceMode, key: e.name, label: e.present(t))),
        ],
      ),
    ),
    MenuItem.separator(),
    MenuItem(key: kTrayMenuKeyQuit, label: t.common.quit),
  ],
);
