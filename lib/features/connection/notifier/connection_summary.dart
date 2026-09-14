import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/connection/notifier/system_proxy_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 当前连接摘要 —— **底部状态栏与抽屉头共用同一份口径**（归一原则）。
///
/// 这两处要回答的是同一组问题："连上了吗 / 走的是哪个节点 / 延迟多少 / 流量被接管了吗"。
/// 以前只有配置页底部的状态栏自己算（内联在 `proxies_overview_page` 里），抽屉头拿不到，
/// 于是"抽屉头显示连接状态"这件事一直做不了；抽到这里之后两边都不再各写一遍。
class ConnectionSummary {
  const ConnectionSummary({required this.state, this.nodeName, this.delayMs = 0, required this.capturing});

  final NkConnectionState state;

  /// 当前节点显示名：已连接 = 实际节点；未连接 = 清单里的预选节点（用户点过 / 分组默认值）。
  final String? nodeName;

  /// 延迟毫秒（0 = 未测速，显示为 "—"）。
  final int delayMs;

  /// 流量是否已被接管（**不等于**"内核在不在跑"）。
  final bool capturing;

  bool get connected => state == NkConnectionState.connected;

  /// 状态文案（这里只给 switch 用的分支键，语言由调用方决定）。
  static String stateKey(NkConnectionState state) => switch (state) {
    NkConnectionState.connected => 'connected',
    NkConnectionState.connecting => 'connecting',
    NkConnectionState.error => 'disconnected',
    NkConnectionState.disconnected => 'disconnected',
  };
}

final connectionSummaryProvider = Provider<ConnectionSummary>((ref) {
  final status = ref.watch(connectionNotifierProvider).valueOrNull;

  final NkConnectionState state;
  if (status is Connected) {
    state = NkConnectionState.connected;
  } else if (status is Connecting || status is Disconnecting) {
    state = NkConnectionState.connecting;
  } else if (status is Disconnected && status.connectionFailure != null) {
    state = NkConnectionState.error;
  } else {
    state = NkConnectionState.disconnected;
  }

  // 节点名有两个来源，优先级明确：
  //  1. **运行中**：内核回报的当前活跃出站（[activeProxyNotifierProvider]）—— 这是事实，
  //     连上以后才知道真正走的是谁（balancer 之类的组会自己挑成员，清单里看不出来）；
  //  2. **未连接**：离线清单里被标记为选中的**真实节点**（预选）。
  //
  // 刻意**不**回退到"组出站当前指向"（`groupSelectedTagDisplay`）：那个字段对 balancer
  // 会给出 `round-robin` / `balance` 这类**策略名而不是节点名**，显示出来是误导。
  // 找不到就留空，宁可只说"未连接"。
  final activeProxy = ref.watch(activeProxyNotifierProvider).valueOrNull;
  final group = ref.watch(proxiesOverviewNotifierProvider).valueOrNull;

  String? nodeName;
  var delay = 0;
  if (state == NkConnectionState.connected && activeProxy != null && activeProxy.tag.isNotEmpty) {
    nodeName = activeProxy.tagDisplay;
    delay = activeProxy.urlTestDelay;
  } else if (group != null) {
    for (final item in group.items.where((e) => !e.isGroup)) {
      if (item.isSelected) {
        nodeName = item.tagDisplay;
        delay = item.urlTestDelay;
        break;
      }
    }
  }

  return ConnectionSummary(state: state, nodeName: nodeName, delayMs: delay, capturing: ref.watch(capturingProvider));
});
