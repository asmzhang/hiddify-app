import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/bootstrap.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 启动真实应用（lazyBootstrap 全链路），Environment 钉在 dev。
/// **必须在 testWidgets 体内调用**——test 开始时 binding 用占位页接管树，
/// 体外 runApp 的树会被顶掉（表现：树里只剩 "Test starting..."）。
///
/// 注意：bootstrap 里的 runApp 由 lazyBootstrap 自己调；pump 一律交给
/// testWidgets 的 tester（LiveTestWidgetsFlutterBinding.pump 有 inTest 断言，
/// 在 test 体外调用会炸）。
///
/// 启动前直接写 SharedPreferences 的两个键——集成测试验收主界面与交互，
/// 不测首启引导页（静态页 + 偏好写入，无逻辑可测）：
/// 1. `intro_completed=true`：跳过 Intro。
/// 2. `locale='en'`：钉住界面语言。app 无持久化 locale 时走
///    `AppLocaleUtils.findDeviceLocale()` 跟随系统（本机是中文），而菜单断言
///    是 en 文案——上轮失败「menu 缺项」的真因是 UI 全中文，不是按钮缺失。
///
/// 两个键都必须用 app 同款 API 写：app 走 SharedPreferences.getInstance()
/// （旧式单例，含缓存前缀机制），用 SharedPreferencesAsync 会写到不同
/// 后备存储上读不到。
Future<void> startHiddifyApp() async {
  final binding = IntegrationTestWidgetsFlutterBinding.instance;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('intro_completed', true);
  await prefs.setString('locale', 'en');
  await lazyBootstrap(binding, Environment.dev);
}

/// 判断当前是否显示 Intro（Intro 页特有的 rocket_launch FAB + 「Start」主按钮）。
/// 按 en 断言（startHiddifyApp 已预写 locale='en'）。
bool introShown(WidgetTester tester) {
  return tester.any(find.byIcon(Icons.rocket_launch)) ||
      tester.any(find.text('Start')) ||
      tester.any(find.textContaining('Get Started')) ||
      tester.any(find.textContaining('Next'));
}

/// 安全导航：如果 Intro 在展示，点「Start」主按钮完成它（写 introCompleted 偏好）。
/// 之后测试直接进主界面。Intro 完成跳转带 profile 引导页时也一并走出。
Future<void> completeIntroIfPresent(WidgetTester tester) async {
  var guard = 0;
  while (introShown(tester) && guard < 6) {
    guard++;
    await tester.tap(find.byIcon(Icons.rocket_launch));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    // Start 点击后可能弹「添加配置」引导，尝试关闭/跳过（跳过按钮或关闭图标）。
    for (final skip in [
      find.text('Skip'),
      find.textContaining('skip'),
      find.byIcon(Icons.close),
      find.byIcon(Icons.arrow_back),
    ]) {
      if (tester.any(skip)) {
        await tester.tap(skip.last);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        break;
      }
    }
  }
}
