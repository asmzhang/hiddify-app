/// 串行执行异步任务的锁（Dart 没有内置 mutex）。
///
/// ## 为什么需要它
///
/// 因为存在**不可重入**的底层：hiddify-core 里"重建 sing-box 注册表"的路径
/// （`include.OutboundRegistry()` → `protocol/hiddify/dnstt/tools.go:26` 无锁写包级 map）
/// 被两个并发调用就会让 **Go 进程直接 abort**（`internal/runtime/maps.fatal`），
/// 而且这个 fatal 不可恢复 —— 应用整个消失。
///
/// 实测崩溃（`crash_reports/2026-09-15T05-37-20/go.log`）：一份 dump 里**恰好 2 个**
/// goroutine 停在 `loadResolvers`，一个来自 `Parse`、一个来自 `Start`。详见
/// `lib/hiddifycore/hiddify_core_service.dart` 的 `_serializeRegistryAccess` 与
/// `docs/design/nekobox-parity.md` §8.6.9。
///
/// ## 三个必须成立的性质（`tool/check_async_lock.dart` 逐条断言）
///
/// 1. **不重叠** —— 同一时刻最多一个任务在跑。
/// 2. **保序（FIFO）** —— 先请求先执行。
/// 3. **一次失败不破坏锁** —— 锁链上只记"上一个跑完了"，错误只交给调用方。
///    这条最容易被漏：若把失败的 Future 直接当作链尾，后续任务会永远在
///    "等待一个已失败的 future" 上排队，表现为**整个功能无声无息地卡死** ——
///    比崩溃更难查。
library;

class SerialAsyncLock {
  /// 链尾：只表示"之前排队的都跑完了"，**永不携带错误**。
  Future<void> _tail = Future.value();

  /// 把 [action] 排进队列，返回它自己的结果（成功或失败都原样交给调用方）。
  Future<T> run<T>(Future<T> Function() action) {
    // 前一个任务失败也要继续跑（onError 分支），这是性质 3
    final result = _tail.then((_) => action(), onError: (_) => action());
    // 链尾吞掉错误，保证下一次排队不会被"已失败的 future"挡住
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
