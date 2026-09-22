// 连接测试守卫的语义钉死 —— 2026-09-22 真实 bug 的回归锚点。
//
// 背景：节点列表的「URL 测试（测速）」曾"点了毫无反应"——页面层已经包了一层
// `connectionTestNotifier.runUrlTest`，而 `proxiesOverviewNotifier.urlTest()` 内部
// **又包了一层** ⇒ 内层守卫读到 `running == true` 直接 return，**RPC 从不发出**。
// 界面表现：对话框秒开秒关、无进度、无报错、无 toast（外层拿到 true 还以为是成功）。
//
// 判据（本文件钉死）：**一次用户动作 = 恰好一层守卫**。嵌套调用必然被拒。
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/notifier/connection_test_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('嵌套 runUrlTest 被守卫拒绝 —— 测试体永不执行（"没反应"的真实机制）', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(connectionTestNotifierProvider.notifier);

    var innerBodyRan = false;
    final outer = await notifier.runUrlTest(
      body: () async {
        final inner = await notifier.runUrlTest(body: () async => innerBodyRan = true);
        expect(inner, isNull, reason: '内层被拒：外层已把 running 置 true');
      },
    );

    expect(outer, isTrue, reason: '外层照常"成功"——这正是它难以察觉的原因');
    expect(innerBodyRan, isFalse, reason: 'RPC 从未执行 = 用户看到的"没反应"');
    expect(
      container.read(connectionTestNotifierProvider).running,
      isFalse,
      reason: '收尾必须复位防重入，否则之后每次点击都失灵',
    );
  });

  test('单层守卫：正常调用会真的执行测试体、并在收尾复位', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(connectionTestNotifierProvider.notifier);

    var ran = false;
    final ok = await notifier.runUrlTest(body: () async => ran = true);

    expect(ok, isTrue);
    expect(ran, isTrue);
    expect(container.read(connectionTestNotifierProvider).running, isFalse);
  });

  test('runTcpPing：并发逐条进度计数不丢（本地计数器而非 state.finished+1）', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(connectionTestNotifierProvider.notifier);

    // 逐条进度在过程中抓快照：收尾状态是新建的（按设计不保留 currentNode/
    // currentResult——那时对话框已经关了，留着没有意义）。
    String? nodeAfterFirst;
    String? resultAfterLast;
    final count = await notifier.runTcpPing(
      total: 3,
      body: (isCancelled, onProgress) async {
        onProgress('n1', '12');
        nodeAfterFirst = container.read(connectionTestNotifierProvider).currentNode;
        onProgress('n2', '34');
        onProgress('n3', 'timeout');
        resultAfterLast = container.read(connectionTestNotifierProvider).currentResult;
        return 3;
      },
    );

    expect(count, 3);
    expect(nodeAfterFirst, 'n1');
    expect(resultAfterLast, 'timeout');
    final state = container.read(connectionTestNotifierProvider);
    expect(state.running, isFalse);
    expect(state.finished, 3);
    expect(state.total, 3);
  });

  test('测试体抛错也复位防重入（否则一次异常后入口永久失灵）', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(connectionTestNotifierProvider.notifier);

    await expectLater(
      notifier.runUrlTest(body: () async => throw StateError('boom')),
      throwsA(isA<StateError>()),
    );
    expect(container.read(connectionTestNotifierProvider).running, isFalse);
  });
}
