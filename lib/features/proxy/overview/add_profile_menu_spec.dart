import 'package:hiddify/core/localization/translations.dart';

/// 配置页「＋」菜单规格 —— NekoBox `add_profile_menu.xml` 的 `action_add` 子树
/// 1:1 投影（词表 zh-rCN 实证：扫描二维码/从剪切板导入/从文件中导入/手动输入）。
/// widget 层渲染这里的数据 + 按动作接线执行器。
///
/// 架构差异条目（记档）：**添加订阅** —— NekoBox 的订阅添加在分组设置
/// （`GroupSettingsActivity` 的订阅链接字段，因为分组=订阅同实体）；本项目订阅是
/// 一等实体（RemoteProfileEntity），添加订阅走独立的订阅表单 —— 所以在 spec 四项
/// **之后**追加本条（保持 spec 顺序在前）。
enum NkAddProfileAction { scanQr, importClipboard, importFile, manualNode, addSubscription }

class NkAddProfileMenuEntry {
  const NkAddProfileMenuEntry(this.label, this.action);
  final String Function(Translations t) label;
  final NkAddProfileAction action;
}

/// [showScanQr] = 移动端才有摄像头扫码（桌面隐藏 —— 与既有 FixBtns 同规则；
/// NekoBox 是安卓-only，无桌面口径可循）。
List<NkAddProfileMenuEntry> nkAddProfileMenu({required bool showScanQr}) => [
      if (showScanQr)
        const NkAddProfileMenuEntry(_scanQrLabel, NkAddProfileAction.scanQr),
      const NkAddProfileMenuEntry(_importClipboardLabel, NkAddProfileAction.importClipboard),
      const NkAddProfileMenuEntry(_importFileLabel, NkAddProfileAction.importFile),
      const NkAddProfileMenuEntry(_manualInputLabel, NkAddProfileAction.manualNode),
      const NkAddProfileMenuEntry(_addSubscriptionLabel, NkAddProfileAction.addSubscription),
    ];

String _scanQrLabel(Translations t) => t.pages.proxies.addMenu.scanQr;
String _importClipboardLabel(Translations t) => t.pages.proxies.addMenu.importClipboard;
String _importFileLabel(Translations t) => t.pages.proxies.addMenu.importFile;
String _manualInputLabel(Translations t) => t.pages.proxies.addMenu.manualInput;
String _addSubscriptionLabel(Translations t) => t.pages.proxies.addMenu.addSubscription;
