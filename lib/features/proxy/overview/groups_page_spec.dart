import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';

/// 分组页规格投影 —— NekoBox `GroupFragment.kt` + `add_group_menu.xml` +
/// `group_action_menu.xml` 的 1:1 唯一数据源（词表 zh-rCN 实证核对，
/// zh-rTW 缺键回退 en 与 NekoBox 行为一致）。widget 层直接渲染这里的数据；
/// L1 结构测试（`groups_page_spec_test.dart`）也打这里。

/// 卡片 ⋮ 菜单的叶子动作（页面据此接线到具体执行器）。
enum NkGroupMenuAction { shareUrlToClipboard, shareQr, exportToClipboard, exportToFile, clearNodes }

/// 工具栏动作（add_group_menu.xml：两枚 showAsAction=always；**无 FAB**）。
enum NkGroupToolbarAction { updateAllSubscriptions, createGroup }

class NkGroupToolbarActionSpec {
  const NkGroupToolbarActionSpec(this.icon, this.label, this.action);
  final IconData icon;
  final String Function(Translations t) label;
  final NkGroupToolbarAction action;
}

List<NkGroupToolbarActionSpec> nkGroupToolbarActions() => [
      const NkGroupToolbarActionSpec(Icons.update_rounded, _updateAllLabel, NkGroupToolbarAction.updateAllSubscriptions),
      const NkGroupToolbarActionSpec(Icons.playlist_add_rounded, _createLabel, NkGroupToolbarAction.createGroup),
    ];

String _updateAllLabel(Translations t) => t.pages.groups.updateAll;
String _createLabel(Translations t) => t.pages.groups.create;

/// 卡片 ⋮ 菜单树（group_action_menu.xml）：children == null 表示叶子动作。
/// 订阅组才有「分享订阅」组（GroupFragment.kt:406-408 removeItem 同判定）；
/// PopupMenu 纯文本（无 leading 图标）。
class NkGroupMenuSpec {
  const NkGroupMenuSpec(this.label, {this.children, this.action})
      : assert(children == null || action == null, '叶子必须有 action，组必须有 children');
  final String Function(Translations t) label;
  final List<NkGroupMenuSpec>? children;
  final NkGroupMenuAction? action;
}

List<NkGroupMenuSpec> nkGroupActionMenu({required bool isSubscription}) => [
      if (isSubscription)
        const NkGroupMenuSpec(_shareSubscriptionLabel, children: [
          NkGroupMenuSpec(_exportToClipboardLabel, action: NkGroupMenuAction.shareUrlToClipboard),
          NkGroupMenuSpec(_shareQrLabel, action: NkGroupMenuAction.shareQr),
        ]),
      const NkGroupMenuSpec(_exportLabel, children: [
        NkGroupMenuSpec(_exportToClipboardLabel, action: NkGroupMenuAction.exportToClipboard),
        NkGroupMenuSpec(_exportToFileLabel, action: NkGroupMenuAction.exportToFile),
      ]),
      const NkGroupMenuSpec(_clearLabel, action: NkGroupMenuAction.clearNodes),
    ];

String _shareSubscriptionLabel(Translations t) => t.pages.groups.shareSubscription;
String _exportToClipboardLabel(Translations t) => t.pages.groups.exportToClipboard;
String _shareQrLabel(Translations t) => t.pages.groups.shareQr;
String _exportLabel(Translations t) => t.common.export;
String _exportToFileLabel(Translations t) => t.pages.groups.exportToFile;
String _clearLabel(Translations t) => t.pages.groups.clearProfiles;

/// 卡片「更新」按钮显隐：仅订阅组（GroupFragment.kt:387 `isInvisible` 同判定；
/// invisible 保占位）。
bool nkGroupCardShowsUpdate({required bool isSubscription}) => isSubscription;

/// 编辑按钮显隐：ungrouped 组无编辑（GroupFragment.kt:386 `isGone` 同判定）。
bool nkGroupCardShowsEdit({required bool ungrouped}) => !ungrouped;

/// 右滑删除可用性：ungrouped 不可滑（GroupFragment.kt:65-72；「更新中」guard
/// 本项目不建——更新走前台通知通道，无进度回流到本页卡片）。
bool nkGroupCardSwipable({required bool ungrouped}) => !ungrouped;
