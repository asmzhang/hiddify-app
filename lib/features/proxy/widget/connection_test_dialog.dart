// 连接测试进度对话框（NekoBox `layout_progress_list.xml` + TestDialog 的 1:1 复刻）。
//
// 规格对照（`ConfigurationFragment.kt:597-690`）：
//   · 布局三件套：indeterminate 转圈 + now_testing（节点名 + 结果行）+ progress 计数
//   · 按钮：最小化 / 取消（**没有确认键**）——本项目无系统通知基建，最小化不可做，
//     只保留取消（照它的 `setNegativeButton(android.R.string.cancel)`）
//   · `setCancelable(false)`：点对话框外部/按返回不关闭 —— 这里用
//     `PopScope(canPop: false)` 等价实现（必须显式点取消）
//   · 取消语义：dialogStatus=2 → 测试停下 → **已测结果照常落库** → 复位 runningTest
//   · 对话框关闭时机：NekoBox 测完也走 `test.cancel()`（dismiss + 落库）——
//     本项目由 [runConnectionTest] 在测试收尾时关框。
//
// 关框纪律（审计修正）：**pop 只允许发生一次，且只移除本对话框自己的路由**。
// 旧实现用"读 state.cancelled 猜对话框还在不在"，存在竞态——用户点取消（框已 pop）
// 之后 body 抛错，收尾路径的无脑 pop 会把**底层页面**顶掉。
// 修法：取消按钮 pop(route: true) 上报"用户取消"；收尾统一走
// [_safeRemoveDialog]（removeRoute 只删自己 + isActive 防重）。
import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/widget/nekobox/nk_theme.dart';
import 'package:hiddify/features/proxy/notifier/connection_test_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// ⋮ 菜单入口：弹框 → 开测 → 收尾关框 → 透传节点数。
///
/// 流程照 NekoBox `pingTest` / `urlTest`（`ConfigurationFragment.kt:694-901`）：
/// 先弹对话框（`test.builder.show()`）→ 调 [start] 开测 → 测试收尾关框。
///
/// [start] 返回值语义：
///   · null = 防重入拒绝（已有测试在跑，NekoBox `if (runningTest) return`）
///     —— 对话框随即退回；
///   · 非空 = 测过的节点数（-1 = 落库失败，调用方提示）。
///
/// 关框的三个来源互斥（`_safeRemoveDialog` 的 isActive 保证只生效一次）：
///   1. 用户点取消 → 按钮 pop(true)，本函数**不等待测试**直接返回 null
///      （NekoBox 的 cancel 也是立即 dismiss，落库在后台协程完成）；
///   2. 测试正常收尾 → 本函数关框后返回计数；
///   3. 测试抛错 → 关框后 rethrow（提示交给调用方 toast）。
Future<int?> runConnectionTest(
  BuildContext context,
  WidgetRef ref, {
  required Future<int?> Function() start,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  ModalRoute<Object?>? dialogRoute;

  // 用户取消 → push 返回 true（按钮 pop 带的值）。
  final userCancelled = await navigator.push<bool>(
    DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (routeContext) {
        dialogRoute ??= ModalRoute.of(routeContext);
        return const _ConnectionTestDialog();
      },
    ),
  );
  if (userCancelled == true) {
    // 框已被取消按钮关掉；测试在后台收尾落库（worker 池的 isCancelled 链路）。
    // NekoBox 的 cancel 同样立即返回，不阻塞在 mainJob.joinAll() 上。
    return null;
  }

  // 走到这里 = 对话框不是被取消按钮关的（正常收尾 / 抛错 / 防重入拒绝）。
  // 测试本体跑完后由这里关框；框已不在栈上时 removeRoute 是空操作。
  try {
    final count = await start();
    _safeRemoveDialog(navigator, dialogRoute);
    return count;
  } catch (e) {
    _safeRemoveDialog(navigator, dialogRoute);
    rethrow;
  }
}

/// 只移除本对话框自己的路由；已离栈（用户取消路径）时是空操作。
///
/// 为什么用 removeRoute 而不是 pop：pop 作用于**栈顶**——收尾时栈顶未必还是
/// 本对话框（理论上用户可以取消后立刻打开别的对话框）；removeRoute 精确指定路由，
/// `isActive` 同时充当"是否已经关过"的防重标记。
void _safeRemoveDialog(NavigatorState navigator, ModalRoute<Object?>? route) {
  if (route == null || !route.isActive) return;
  navigator.removeRoute(route);
}

class _ConnectionTestDialog extends ConsumerWidget {
  const _ConnectionTestDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final state = ref.watch(connectionTestNotifierProvider);

    // 最近完成节点的结果行（NekoBox update() 的 status→颜色映射）：
    // 纯数字 = 成功延迟（三档色照 NkColors.latencyColor），否则 = 错误文案（红）。
    final parsedDelay = state.currentResult == null ? null : int.tryParse(state.currentResult!);
    final resultColor = parsedDelay != null
        ? NkColors.latencyColor(context, parsedDelay) ?? theme.colorScheme.onSurfaceVariant
        : state.currentResult == null
        ? theme.colorScheme.onSurfaceVariant
        : NkColors.latencyBad;
    final resultText = state.currentResult ?? '—';

    return PopScope(
      canPop: false,
      child: AlertDialog(
        // NekoBox 标题 `R.string.connection_test`（"Connection test" / 连接测试）。
        title: Text(t.pages.proxies.connectionTest.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ① layout_progress_list.xml 的 progress_circular（indeterminate）
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: CircularProgressIndicator(),
            ),
            // ② now_testing：节点名一行 + 结果一行（update() 的两段式文案）
            Text(
              state.currentNode ?? t.pages.proxies.connectionTest.testing,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(resultText, style: theme.textTheme.bodySmall?.copyWith(color: resultColor)),
            const SizedBox(height: 12),
            // ③ progress 计数（"$progress / $proxyN"）；urlTest 无逐条进度，total=0 不显示
            if (state.total > 0)
              Text(
                '${state.finished} / ${state.total}',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
          ],
        ),
        actions: [
          // NekoBox 有 取消 + 最小化 两个键；最小化需要系统通知续报进度，
          // 本项目无通知基建，不可做 —— 只保留取消。
          TextButton(
            onPressed: () {
              // 照 test.cancel：置取消标记 → worker 池停下 → 已测结果照落库（notifier 侧）→
              // 关框（pop(true) 上报"用户取消"，runConnectionTest 据此不等待收尾）。
              ref.read(connectionTestNotifierProvider.notifier).requestCancel();
              Navigator.of(context).pop(true);
            },
            child: Text(t.common.cancel),
          ),
        ],
      ),
    );
  }
}
