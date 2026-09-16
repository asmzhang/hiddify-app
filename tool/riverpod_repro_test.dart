// 复现「切换分组无效」的真实条件。
//
// 关键：先前的脚本失真——假 notifier 不写盘、也没人订阅，autoDispose provider
// 在重建窗口被销毁，状态只能回到默认空串。真实项目里
//   ① PreferencesNotifier 真写盘（重建能读回）
//   ② 页面一直 watch 着 selectedProxyGroupTagProvider（不会被销毁）
// 所以必须把这两个条件补上，才能判断 watch 位置到底是不是根因。
import 'dart:async';

import 'package:riverpod/riverpod.dart';

// 模拟 SharedPreferences 落盘
final disk = <String, String>{};

class PrefsNotifier extends StateNotifier<String> {
  PrefsNotifier(Ref ref) : super(disk['selected_proxy_group'] ?? '');

  Future<void> update(String v) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    disk['selected_proxy_group'] = v; // ① 真落盘
    state = v;
  }
}

final selectedProvider = StateNotifierProvider.autoDispose<PrefsNotifier, String>(PrefsNotifier.new);
final flagProvider = Provider<bool>((ref) => true);

class AwaitWatch extends StreamNotifier<String> {
  @override
  Stream<String> build() async* {
    final dep0 = ref.watch(flagProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final selected = ref.watch(selectedProvider); // 原写法：await 之后
    yield 'dep0=$dep0 selected=[$selected]';
  }
}

class SyncWatch extends StreamNotifier<String> {
  @override
  Stream<String> build() async* {
    final dep0 = ref.watch(flagProvider);
    final selected = ref.watch(selectedProvider); // 修复写法：同步段
    await Future<void>.delayed(const Duration(milliseconds: 10));
    yield 'dep0=$dep0 selected=[$selected]';
  }
}

final awaitProvider = StreamNotifierProvider<AwaitWatch, String>(AwaitWatch.new);
final syncProvider = StreamNotifierProvider<SyncWatch, String>(SyncWatch.new);

Future<void> scenario(String name, StreamNotifierProvider<StreamNotifier<String>, String> p, {required bool pageWatches}) async {
  disk.clear();
  final container = ProviderContainer();
  ProviderSubscription<String>? pageSub;
  if (pageWatches) {
    // ② 模拟页面一直 watch（保住 autoDispose provider 不被销毁）
    pageSub = container.listen(selectedProvider, (_, __) {}, fireImmediately: true);
  }
  final sub = container.listen(p, (_, __) {}, fireImmediately: true);
  await Future<void>.delayed(const Duration(milliseconds: 100));
  final before = container.read(p).value;

  await container.read(selectedProvider.notifier).update('groupB');
  await Future<void>.delayed(const Duration(milliseconds: 200));
  final after = container.read(p).value;

  final ok = after != null && after.contains('selected=[groupB]');
  print('[$name] pageWatches=$pageWatches');
  print('   before: $before');
  print('   after : $after');
  print('   => ${ok ? "PASS" : "FAIL"}   盘上值=[${disk['selected_proxy_group']}]');
  pageSub?.close();
  sub.close();
  container.dispose();
}

Future<void> main() async {
  // 场景 1：原写法 + 无页面订阅（= 先前失真脚本）
  await scenario('原写法', awaitProvider, pageWatches: false);
  // 场景 2：原写法 + 有页面订阅（≈ 真实项目）
  await scenario('原写法', awaitProvider, pageWatches: true);
  // 场景 3：修复写法 + 有页面订阅（≈ 修复后项目）
  await scenario('修复写法', syncProvider, pageWatches: true);
}
