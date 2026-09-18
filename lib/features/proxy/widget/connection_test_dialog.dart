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
//     本项目由 [showConnectionTestDialogWithCount] 在测试收尾时 pop 对话框。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/widget/nekobox/nk_theme.dart';
import 'package:hiddify/features/proxy/notifier/connection_test_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 弹出连接测试进度对话框并驱动一轮测试（⋮ 菜单入口）。
///
/// 流程照 NekoBox `pingTest` / `urlTest`（`ConfigurationFragment.kt:694-901`）：
/// 先弹对话框 → 调 [start] 开测 → 测试收尾（成功/失败/取消）后关框。
/// [start] 返回 null = 防重入拒绝（已有测试在跑，NekoBox `if (runningTest) return`
/// ——此时立即退回刚弹出的框）；其非空值（测过的节点数）原样透传给调用方，
/// 供错误提示判断（-1 = 落库失败）。
///
/// 测试本体抛错时同样关框后 rethrow，错误提示由调用方 toast。
Future<int?> showConnectionTestDialogWithCount(
  BuildContext context,
  WidgetRef ref, {
  required Future<int?> Function() start,
}) async {
  // 先弹框（NekoBox：`val dialog = test.builder.show()` 在测试逻辑之前）。
  final navigator = Navigator.of(context, rootNavigator: true);
  navigator.push(
    DialogRoute<int?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ConnectionTestDialog(),
    ),
  );
  try {
    final count = await start();
    if (count == null) {
      // 防重入拒绝：没有新测试在跑，对话框没有存在意义——退回刚弹的框。
      navigator.pop();
    } else {
      // 测试结束（含取消路径——取消在对话框里 pop 过一次，这里再 pop 会把
      // 下面的页面顶掉，所以取消场景下 start 的 count 也能正常返回，
      // 但框已关，须防双重 pop）。
      // _ConnectionTestDialog 的取消按钮自己 pop 过了；此处只在没有取消时关。
      final cancelled = ref.read(connectionTestNotifierProvider).cancelled;
      if (!cancelled) navigator.pop();
    }
    return count;
  } catch (e) {
    // 测试抛错：关框，错误提示交给调用方 toast。
    navigator.pop();
    rethrow;
  }
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
              // 关框（pop 根 Navigator 上的 DialogRoute）。
              ref.read(connectionTestNotifierProvider.notifier).requestCancel();
              context.pop();
            },
            child: Text(t.common.cancel),
          ),
        ],
      ),
    );
  }
}
