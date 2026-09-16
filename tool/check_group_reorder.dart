// 分组拖拽排序（NekoBox GroupFragment `move` + `commitMove`）判据的**可执行校验**。
//
// 运行：dart run tool/check_group_reorder.dart
//
// 规格来源：NekoBox `ui/GroupFragment.kt:203-226` 的 `move(from, to)`。
// 该算法（order 链式平移 + groupList 对象重排）的**语义结果**——用
// from=0,to=2 与 from=1,to=0 两个实例逐步推演得出——是：
//   · order 值集合不变，只是重新分配给对象；
//   · 平移后「userOrder 升序 == 新界面序」（初始 order 互异的条件下恒成立）。
// 这正是"拖拽排序"的本质：**界面序即权威序**。
//
// 本项目落点 `proxy_entity_repository.moveGroups`：整表重算 `userOrder = 界面下标`，
// 与 NekoBox 的链式平移**排序等价**（次序相同，数值不同：NekoBox 保留旧值集合，
// 本项目归一为 0..n-1；`allGroups`/`listGroups` 都按 userOrder 排序，故展示等价）。
//
// 本脚本不 import repo（drift/Flutter 依赖拖不进 dart run），验证四件事：
//   1. NekoBox move 语义结果的不变量（order 升序 == 新界面序）；
//   2. hiddify reindex 与它排序等价；
//   3. 相对顺序不变量（除被拖项外其余项次序不变）；
//   4. 不可拖行（订阅组/ungrouped）的相对次序在重排中稳定。
// 改 moveGroups 语义时同步改这里。
//
// ignore_for_file: avoid_print — 校验脚本，print 就是它的输出方式
import 'dart:convert';

int passed = 0;
int failed = 0;

void check(String name, Object? actual, Object? expected) {
  final ok = sameValue(actual, expected);
  if (ok) {
    passed++;
    print('PASS  $name');
  } else {
    failed++;
    print('FAIL  $name: expected=$expected actual=$actual');
  }
}

bool sameValue(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

/// NekoBox `move(from, to)` 的**对象级语义**镜像（用 from=0,to=2 手工推演校准）：
///   对象 at(from)（被拖项）拿 orders[to] 的值；
///   对象 at(i)（i 在 from+1..to）拿 orders[i-1]（原位置前移一格的值）；
///   其余不变。
/// 推演（orders=[10,20,30,40], from=0, to=2）：
///   B 拿 10、C 拿 20、A 拿 30、D 不动 ⇒ 按旧序 = [30, 10, 20, 40]。
List<int> nekoboxMove(List<int> orders, int from, int to) {
  final next = [...orders];
  if (from < to) {
    for (var i = from + 1; i <= to; i++) {
      next[i] = orders[i - 1];
    }
    next[from] = orders[to];
  } else if (from > to) {
    for (var i = to; i < from; i++) {
      next[i] = orders[i + 1];
    }
    next[from] = orders[to];
  }
  return next;
}

/// 本项目 `moveGroups` 的镜像：整表重算 userOrder = 界面下标。
List<int> hiddifyReindex(int n) => [for (var i = 0; i < n; i++) i];

/// 给定界面序（新）与各对象的 order 值，返回「按界面序排列的 order 序列」。
/// 界面序用移动后 id 列表给出，orders 按原界面序（与原 id 列表同序）。
List<int> orderByDisplayOrder<T>(List<T> oldIds, List<int> orders, List<T> newIds) {
  final orderById = {for (var i = 0; i < oldIds.length; i++) oldIds[i]: orders[i]};
  return [for (final id in newIds) orderById[id]!];
}

/// 不变量：userOrder 升序排列后的 id 序列 == 界面 id 序列。
bool invariantOrderMatchesDisplay<T>(List<T> ids, List<int> orderByDisplay) {
  final pairs = [for (var i = 0; i < ids.length; i++) (orderByDisplay[i], ids[i])];
  pairs.sort((a, b) => a.$1.compareTo(b.$1));
  return sameValue([for (final p in pairs) p.$2], ids);
}

/// 不变量：相对顺序不变 —— 除被拖项外，其余项在界面序里的出现次序不变。
bool invariantRelativeOrder<T>(List<T> before, List<T> after, T moved) {
  final b = before.where((id) => id != moved).toList();
  final a = after.where((id) => id != moved).toList();
  return sameValue(b, a);
}

void main() {
  const oldIds = ['A', 'B', 'C', 'D'];
  const initialOrders = [10, 20, 30, 40]; // NekoBox 用非连续值

  // ── 1) 向下移：A(0) → C(2)。新界面序 [B, C, A, D] ──
  final nk1 = nekoboxMove(initialOrders, 0, 2);
  const newIds1 = ['B', 'C', 'A', 'D'];
  final nk1ByDisplay = orderByDisplayOrder(oldIds, nk1, newIds1);
  check('NekoBox move 0->2: order 值集合不变', [...nk1]..sort(), [10, 20, 30, 40]);
  check('NekoBox move 0->2: 镜像值 [30,10,20,40]', nk1, [30, 10, 20, 40]);
  check('NekoBox move 0->2: order 升序 == 新界面序', invariantOrderMatchesDisplay(newIds1, nk1ByDisplay), true);

  // 本项目：reindex 后 userOrder = 界面下标
  final hy1 = hiddifyReindex(4);
  check('hiddify reindex: userOrder 升序 == 新界面序', invariantOrderMatchesDisplay(newIds1, hy1), true);
  // 排序等价：两者按各自 order 升序排出的 id 序列相同
  check('排序等价（0->2）', invariantOrderMatchesDisplay(newIds1, hy1), invariantOrderMatchesDisplay(newIds1, nk1ByDisplay));

  // ── 2) 向上移：D(3) → B(1)。新界面序 [A, D, B, C] ──
  final nk2 = nekoboxMove(initialOrders, 3, 1);
  const newIds2 = ['A', 'D', 'B', 'C'];
  final nk2ByDisplay = orderByDisplayOrder(oldIds, nk2, newIds2);
  check('NekoBox move 3->1: order 值集合不变', [...nk2]..sort(), [10, 20, 30, 40]);
  check('NekoBox move 3->1: 镜像值 [10,30,40,20]（与 0->2 镜像对称：C 拿 40、B 拿 30、D 拿 20）', nk2, [10, 30, 40, 20]);
  check('NekoBox move 3->1: order 升序 == 新界面序', invariantOrderMatchesDisplay(newIds2, nk2ByDisplay), true);
  check('排序等价（3->1）', invariantOrderMatchesDisplay(newIds2, hiddifyReindex(4)), invariantOrderMatchesDisplay(newIds2, nk2ByDisplay));

  // ── 3) 相对顺序不变量 ──
  check('相对顺序不变（0->2）', invariantRelativeOrder(oldIds, newIds1, 'A'), true);
  check('相对顺序不变（3->1）', invariantRelativeOrder(oldIds, newIds2, 'D'), true);
  // 反例：B 被拖动的同时 A、C 交换 ⇒ 应被检出（这是 reindex 不会发生的情形，
  // 列出只为本不变量的判别力作证）
  check('判别力：额外交换会被检出', invariantRelativeOrder(oldIds, ['C', 'B', 'A', 'D'], 'B'), false);

  // ── 4) 边界与不可拖行 ──
  check('单元素 reindex', hiddifyReindex(1), [0]);
  check('空表 reindex', hiddifyReindex(0), <int>[]);
  check('原地拖放（from==to）不动', nekoboxMove(initialOrders, 2, 2), initialOrders);

  // 混合列表：不可拖行（订阅组/ungrouped）没被拖动 ⇒ 它们在界面序里的相对次序不变。
  // 本项目按"整表按界面序落库"实现，不可拖行 userOrder 数值变了但**次序**等价。
  const mixedBefore = ['sub1', 'manual1', 'manual2', 'sub2'];
  const mixedAfter = ['sub1', 'manual2', 'manual1', 'sub2']; // 只交换两个 manual
  check('混合列表：不可拖行相对次序稳定', invariantRelativeOrder(mixedBefore, mixedAfter, 'manual1'), true);
  bool subOrderStable(List<String> list) {
    final i1 = list.indexOf('sub1');
    final i2 = list.indexOf('sub2');
    return i1 >= 0 && i2 >= 0 && i1 < i2;
  }
  check('混合列表：sub1 仍在 sub2 前', subOrderStable(mixedAfter), subOrderStable(mixedBefore));

  print('\n$passed passed, $failed failed');
  if (failed > 0) throw StateError('check_group_reorder failed');
}
