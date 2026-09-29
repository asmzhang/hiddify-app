import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/proxy/data/protocol_form.dart';

/// 配置页「＋」菜单规格 —— NekoBox `add_profile_menu.xml` 的 `action_add` 子树。
///
/// 顶层顺序：扫码 / 剪贴板 / 文件 / 手动设置（二级协议菜单）。「添加订阅」是
/// Hiddify 订阅一等实体带来的追加入口，固定放在 NekoBox 原始项之后。
enum NkAddProfileAction { scanQr, importClipboard, importFile, manualNode, addSubscription }

class NkAddProfileMenuEntry {
  const NkAddProfileMenuEntry({required this.label, this.action, this.protocol, this.children})
    : assert((children == null) != (action == null), '菜单组必须有 children，叶子必须有 action'),
      assert(action == NkAddProfileAction.manualNode || protocol == null, '只有手动节点动作携带 protocol');

  final String Function(Translations t) label;
  final NkAddProfileAction? action;
  final String? protocol;
  final List<NkAddProfileMenuEntry>? children;
}

List<NkAddProfileMenuEntry> nkAddProfileMenu({required bool showScanQr}) => [
  if (showScanQr) const NkAddProfileMenuEntry(label: _scanQrLabel, action: NkAddProfileAction.scanQr),
  const NkAddProfileMenuEntry(label: _importClipboardLabel, action: NkAddProfileAction.importClipboard),
  const NkAddProfileMenuEntry(label: _importFileLabel, action: NkAddProfileAction.importFile),
  NkAddProfileMenuEntry(label: _manualInputLabel, children: nkManualProtocolMenu()),
  const NkAddProfileMenuEntry(label: _addSubscriptionLabel, action: NkAddProfileAction.addSubscription),
];

/// NekoBox 原菜单顺序；Trojan-Go 因 sing-box 1.13 无对应出站而不移植。
/// NekoBox 的单个 Hysteria 表单内切版本；当前实体 type 分为 hysteria/hysteria2，
/// 因此在菜单层显式列 Hysteria 1/2，避免两个同名项且保留两种内核能力。
List<NkAddProfileMenuEntry> nkManualProtocolMenu() => [
  for (final protocol in kManualCreatableProtocols)
    NkAddProfileMenuEntry(
      label: (_) => manualProtocolDisplayName(protocol),
      action: NkAddProfileAction.manualNode,
      protocol: protocol,
    ),
];

String manualProtocolDisplayName(String type) => switch (type) {
  'hysteria' => 'Hysteria 1',
  'hysteria2' => 'Hysteria 2',
  _ => protocolDisplayName(type),
};

String _scanQrLabel(Translations t) => t.pages.proxies.addMenu.scanQr;
String _importClipboardLabel(Translations t) => t.pages.proxies.addMenu.importClipboard;
String _importFileLabel(Translations t) => t.pages.proxies.addMenu.importFile;
String _manualInputLabel(Translations t) => t.pages.proxies.addMenu.manualInput;
String _addSubscriptionLabel(Translations t) => t.pages.proxies.addMenu.addSubscription;
