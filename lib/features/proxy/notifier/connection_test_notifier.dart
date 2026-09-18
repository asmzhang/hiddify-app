// 连接测试进度中心（NekoBox `ConfigurationFragment.kt:597-690` TestDialog 的应用侧对应物）。
//
// NekoBox 的进度三件套挂在**对话框内部类**上（`proxyN / finishedN / nowTesting`），
// 但它同时要求"最小化后进度不能丢"——进度数据本质上是**独立于对话框生命周期**的状态。
// 本项目没有系统通知基建（NekoBox 靠 ConnectionTestNotification 在最小化后续报），
// 最小化不可做；但"状态独立于对话框"这个结构照搬：进度放 Riverpod notifier，
// 对话框只是它的一个视图，弹窗/关窗都不会打断测试。
//
// 防重入照 NekoBox `DataStore.runningTest`（`pingTest`/`urlTest` 入口第一行）：
// `if (DataStore.runningTest) return else DataStore.runningTest = true`。
// 这里收敛为 [ConnectionTestState.running] 单一布尔，两个入口共用。
import 'dart:async';

import 'package:hiddify/features/proxy/data/tcp_ping.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connection_test_notifier.g.dart';

/// 一次连接测试的进度快照（NekoBox TestDialog 三件套的数据形态）。
///
/// [currentNode] 展示照 `update()`（ConfigurationFragment.kt:618-688）：
/// 节点名一行、结果一行；这里简化为"最近完成的一个节点 + 其结果描述"，
/// 因为 Flutter 侧对话框可以直接 watch provider 逐条重绘。
class ConnectionTestState {
  const ConnectionTestState({
    this.running = false,
    this.total = 0,
    this.finished = 0,
    this.currentNode,
    this.currentResult,
    this.cancelled = false,
  });

  /// 是否有测试在跑（NekoBox `DataStore.runningTest`）。**防重入守卫**。
  final bool running;

  /// 参与本轮测试的节点总数（NekoBox `proxyN`）。
  final int total;

  /// 已完成数（NekoBox `finishedN`）。对话框显示 `"$finished / $total"`。
  final int finished;

  /// 最近完成的节点名（NekoBox `now_testing` 的第一行）。
  final String? currentNode;

  /// 最近完成节点的结果摘要（NekoBox `update()` 按 status 上色那段的文本部分）。
  final String? currentResult;

  /// 本轮是否被用户取消（NekoBox `dialogStatus == 2`）。取消时已测结果照落库。
  final bool cancelled;

  ConnectionTestState copyWith({
    bool? running,
    int? total,
    int? finished,
    String? currentNode,
    String? currentResult,
    bool? cancelled,
  }) {
    return ConnectionTestState(
      running: running ?? this.running,
      total: total ?? this.total,
      finished: finished ?? this.finished,
      currentNode: currentNode ?? this.currentNode,
      currentResult: currentResult ?? this.currentResult,
      cancelled: cancelled ?? this.cancelled,
    );
  }
}

/// 测试进度的**唯一数据源**。
///
/// worker 池每完成一条就 `state = ...` 推一次；对话框 watch 本 provider 即得逐条刷新。
/// 取消语义照 NekoBox `test.cancel`（ConfigurationFragment.kt:807-823）：
/// 置取消标记 → worker 池停下 → 已完成结果照常落库 → 复位 runningTest。
@Riverpod(keepAlive: true)
class ConnectionTestNotifier extends _$ConnectionTestNotifier with AppLogger {
  /// 当前这轮的取消开关（NekoBox `dialogStatus` 的 2 态）。
  /// 简化为布尔：0/1 态（显示/最小化）对 Flutter 无意义——没有系统通知，不存在最小化。
  Completer<void>? _cancel;

  @override
  ConnectionTestState build() => const ConnectionTestState();

  /// 请求当前测试停止（正常结束后调用是空操作）。
  void requestCancel() {
    loggy.debug("connection test cancel requested");
    _cancel?.complete();
  }

  /// 开始一轮测试（进度逐条回报）。[body] 是测试本体，返回值原样透传
  /// （tcpPing 用它回传"测过的节点数"；-1 = 落库失败；null 不经这里产生）。
  ///
  /// 返回 null = 防重入拒绝（已有测试在跑，NekoBox `if (DataStore.runningTest) return`）。
  Future<int?> runTcpPing({
    required int total,
    required Future<int?> Function(bool Function() isCancelled, void Function(String node, String result) onProgress) body,
  }) async {
    if (state.running) {
      loggy.warning("connection test already running, ignored");
      return null;
    }
    final cancel = Completer<void>();
    _cancel = cancel;
    state = ConnectionTestState(running: true, total: total);
    // 本地计数（审计修正）：worker 池并发回调 onProgress 时，若用
    // `state.finished + 1` 做递增，两个回调读到同一个 state 会互相覆盖丢计数。
    var finished = 0;
    try {
      final result = await body(() => cancel.isCompleted, (node, result) {
        finished += 1;
        state = ConnectionTestState(
          running: true,
          total: total,
          finished: finished,
          currentNode: node,
          currentResult: result,
          cancelled: cancel.isCompleted,
        );
      });
      // 收尾：复位防重入 + 保留计数（NekoBox 测完对话框关掉，但进度快照无意义，
      // 这里保留 finished 是为了取消防重入后调用方还能读到本轮计数）。
      // running: false 是本行的语义核心，显式写出（lint 对默认值报冗余，已豁免）。
      // ignore: avoid_redundant_argument_values
      state = ConnectionTestState(running: false, total: total, finished: finished, cancelled: cancel.isCompleted);
      return result;
    } catch (e, stackTrace) {
      loggy.warning("connection test failed", e, stackTrace);
      // 失败也要复位防重入——否则一次异常后测试入口永久失灵。
      // ignore: avoid_redundant_argument_values
      state = ConnectionTestState(running: false, total: total, finished: finished, cancelled: cancel.isCompleted);
      rethrow;
    } finally {
      _cancel = null;
    }
  }

  /// 开始一轮内核 URL test（无逐条进度——内核 RPC 空 tag 一次测全部）。
  ///
  /// NekoBox 的 urlTest 同样是应用侧逐节点 HTTP 探测所以有逐条 update；
  /// 本项目的对应实现是内核 `UrlTestActive()`（见 ProxiesOverviewNotifier.urlTest），
  /// 拿不到逐条回调。对话框对这种测试只显示转圈 + 提示文案（计数不显示）。
  ///
  /// 返回 null = 防重入拒绝；true = 正常结束（不存在 false 分支）。
  /// 不可中途取消（内核侧无该 RPC）——requestCancel 对它无效。
  Future<bool?> runUrlTest({required Future<void> Function() body}) async {
    if (state.running) {
      loggy.warning("connection test already running, ignored");
      return null;
    }
    // URL test 不可中途取消（内核侧无该 RPC）——cancel completer 不接。
    state = const ConnectionTestState(running: true);
    try {
      await body();
      state = const ConnectionTestState();
      return true;
    } catch (e, stackTrace) {
      loggy.warning("url test failed", e, stackTrace);
      state = const ConnectionTestState();
      rethrow;
    }
  }
}

/// TCP ping 单条结果的展示文案生成（挂在 data 层的 [TcpPingResult] 上做 UI 翻译）。
///
/// 照 NekoBox `update()` 的 status 分支（ConfigurationFragment.kt:639-666）：
/// 1 → 绿色 `$ping`；2 → 红色错误文案（refused/unreachable/timeout/domain_not_found
/// 已由 tcpPingHost 分类，这里直接用分类键查翻译）；3 → 红色原始错误。
/// 文案在 UI 层用 translations 查，这里只输出**分类键或延迟值**。
String connectionTestResultKey(TcpPingResult result) {
  return switch (result.status) {
    1 => '${result.ping}',
    _ => result.error ?? 'unavailable',
  };
}
