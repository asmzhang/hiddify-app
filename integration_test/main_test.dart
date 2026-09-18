// Integration test 入口：跑在**真实 Windows 构建**上（flutter test integration_test -d windows）。
//
// 关键约束（踩过的坑）：
// 1. lazyBootstrap（含 runApp）必须放进 testWidgets 体内——test 开始时 binding
//    会用 "Test starting..." 占位页接管 widget 树，体外 runApp 的树会被顶掉。
// 2. pump 一律用 tester.pump/pumpAndSettle——binding.pump 有 inTest 断言，体外调用会炸。
// 3. 跑前先 tool/ensure_plugin_junctions.ps1（沙箱内 Flutter 建符号链接会失败）。
//
// 覆盖矩阵（对照 NekoBoxForAndroid 复刻批次）见 smoke_test.dart。
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'hiddify_app.dart';
import 'smoke_test.dart';

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('PC 冒烟：启动 → 主界面四要素 → ⋮ 菜单八项', (tester) async {
    // 启动（introCompleted 已在 startHiddifyApp 里预写，直接进主界面）。
    await startHiddifyApp();
    // 带上限等待：连接转圈等常驻动画会让裸 pumpAndSettle 永不返回。
    try {
      await tester.pumpAndSettle(const Duration(seconds: 5));
    } catch (_) {
      // 永不空闲动画：接受。
    }

    await smokeMainScreen(tester);
    await smokeOverflowMenu(tester);
  });
}
