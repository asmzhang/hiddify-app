// 「期望选中 ↔ 内核选中」校准决策的可执行校验。
//
// 运行：dart run tool/check_selection_reconcile.dart
//
// 要证明的核心：**判断顺序即优先级**（归属校验 → 幂等 → 节点是否在内核配置里 → 默认值指纹 → 采纳）。
// 顺序错了会出两类真 bug：① 内核还没加载到那个节点就硬下发（对不存在的 tag 反复重试）；
// ② 把外部改选按回去（机器人行为）。
//
// ignore_for_file: avoid_print — 校验脚本，print 就是它的输出方式
import 'package:hiddify/features/proxy/data/runtime_outbound_tags.dart';
import 'package:hiddify/features/proxy/data/selection_reconcile.dart';

void main() {
  var failures = 0;

  void check(String label, Object? actual, Object? expected) {
    final ok = actual == expected;
    if (!ok) failures++;
    print('${ok ? "PASS" : "FAIL"}  $label${ok ? "" : "\n  expected: $expected\n  actual:   $actual"}');
  }

  const nodes = ['HK-01', 'JP-02', 'US-04'];

  // kernelSelected 不给默认值：每条用例都要明说"内核此刻选中什么"。
  // 整件事最关键的分叉就是"内核停在默认值（= 刚起来）"与"内核已选了具体节点（= 有人选过）"。
  SelectionReconcileAction decide({
    required String kernelSelected,
    String desired = 'HK-01',
    String desiredProfile = 'p1',
    String? active = 'p1',
    List<String> kernelNodes = nodes,
  }) => decideSelectionReconcile(
    desiredTag: desired,
    desiredProfileId: desiredProfile,
    activeProfileId: active,
    kernelSelectedTag: kernelSelected,
    kernelNodeTags: kernelNodes,
  );

  // ---- 1) 没有期望值 → 不动（内核默认即当前事实） ----
  check('没选过 → none', decide(desired: '', kernelSelected: kRuntimeBalanceTag), SelectionReconcileAction.none);

  // ---- 2) 归属：期望值属于别的订阅 → 等内核换配置（即使内核已停在默认值） ----
  check(
    '期望值属于别的订阅 → waitForProfile',
    decide(desiredProfile: 'p2', kernelSelected: kRuntimeBalanceTag),
    SelectionReconcileAction.waitForProfile,
  );
  check(
    '归属为空 = 不校验 → 正常下发',
    decide(desiredProfile: '', kernelSelected: kRuntimeBalanceTag),
    SelectionReconcileAction.applyDesired,
  );
  check(
    '归属校验优先于"已一致"判断',
    decide(desiredProfile: 'p2', kernelSelected: 'HK-01'),
    SelectionReconcileAction.waitForProfile,
  );

  // ---- 3) 幂等：内核已经选中期望值 → 什么都不做（所以每次事件都跑也不会重复下发） ----
  check('内核已选中期望值 → none', decide(kernelSelected: 'HK-01'), SelectionReconcileAction.none);

  // ---- 4) 内核节点集合里没有这个 tag → 只是等待（**不能**因为内核在默认值就硬下发） ----
  check(
    '期望值不在内核配置里（内核停在默认值）→ none',
    decide(desired: 'GONE-99', kernelSelected: kRuntimeBalanceTag),
    SelectionReconcileAction.none,
  );
  check(
    '期望值不在内核配置里（内核已选了别的）→ none',
    decide(desired: 'GONE-99', kernelSelected: 'JP-02'),
    SelectionReconcileAction.none,
  );
  check(
    '内核还没返回任何节点 → none',
    decide(kernelSelected: kRuntimeBalanceTag, kernelNodes: const []),
    SelectionReconcileAction.none,
  );

  // ---- 5) 内核停在它自己的默认值 = "刚起来 / 没人选过" → 下发期望值 ----
  check(
    '内核在 balance（默认）→ applyDesired',
    decide(kernelSelected: kRuntimeBalanceTag),
    SelectionReconcileAction.applyDesired,
  );
  check(
    '内核在 lowest（WARP 模式的默认）→ applyDesired',
    decide(kernelSelected: kRuntimeLowestTag),
    SelectionReconcileAction.applyDesired,
  );

  // ---- 6) 内核选中是个具体节点且与期望不同 → 外部改的，采纳并回写 ----
  check('外部改选 → adoptKernel', decide(kernelSelected: 'JP-02'), SelectionReconcileAction.adoptKernel);
  check(
    '外部改选成隐藏出站也采纳（下一轮就幂等了）',
    decide(kernelSelected: kRuntimeDirectTag),
    SelectionReconcileAction.adoptKernel,
  );
  check(
    '采纳之后下一轮幂等',
    decide(kernelSelected: kRuntimeDirectTag, desired: kRuntimeDirectTag),
    SelectionReconcileAction.none,
  );

  // ---- 7) 边界：期望值本身就是内核默认值（UI 不该选到，但逻辑要自洽） ----
  check(
    '期望值 == 内核默认值且内核正停在它上面 → none',
    decide(desired: kRuntimeBalanceTag, kernelSelected: kRuntimeBalanceTag),
    SelectionReconcileAction.none,
  );
  check(
    '期望值 == balance 但内核选了具体节点 → 不在内核节点集里 → none',
    decide(desired: kRuntimeBalanceTag, kernelSelected: 'HK-01'),
    SelectionReconcileAction.none,
  );

  print(failures == 0 ? '\nALL PASS' : '\n$failures FAILED');
}
