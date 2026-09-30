// L1 结构对等测试 —— 底部状态条 NkCaptureStatusBar 1:1 对照 NekoBox `widget/StatsBar.kt`
// + `layout_main.xml:46-99`（规格侦察记录 .workbuddy/connection-link-recon-2026-09-30.md）。
// 断言基准 zh-CN（vpn_connected = 「已连接 , 点击此处测试连接」，词面与 NekoBox 一致）。
// 覆盖面：状态条可见性矩阵（changeState performHide 等价）/ 单行结构（状态文案+节点名+▲▼速率）
// / 点击触发连接测试（MainActivity.kt:94 门控的页面侧等价）。
// 刻意差异（部件头注释同源）：单行 Row vs NekoBox 三行竖排（宽屏观察点定案维持单行）；
// 点击走进度弹窗（Throne 形态）而非内联文案变化。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_summary.dart';
import 'package:hiddify/features/proxy/widget/nk_capture_status_bar.dart';

void main() {
  test('状态条可见性矩阵对齐 NekoBox StatsBar.changeState', () {
    // StatsBar.changeState：仅 Connected → performShow（+hideOnScroll）；
    // Connecting/Stopping/NotConnected → performHide + updateSpeed(0,0)。
    // 本项目等价物：captureStatsBarVisible 纯映射（100ms 延迟在页面 Timer 侧）。
    expect(captureStatsBarVisible(const Connected()), isTrue);
    expect(captureStatsBarVisible(const Connecting()), isFalse);
    expect(captureStatsBarVisible(const Disconnecting()), isFalse);
    expect(captureStatsBarVisible(const Disconnected()), isFalse);
    expect(
      captureStatsBarVisible(const Disconnected(UnexpectedConnectionFailure('x'))),
      isFalse,
      reason: 'error 态同样不显示状态条（NekoBox not_connected → performHide）',
    );
  });

  testWidgets('状态条渲染：状态文案 + 节点名 + ▲▼ 速率', (tester) async {
    final t = AppLocale.en.buildSync();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: NkCaptureStatusBar(
            t: t,
            summary: const ConnectionSummary(
              state: NkConnectionState.connected,
              nodeName: 'hk-01',
              capturing: false,
            ),
            uplink: 0,
            downlink: 0,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.connection.statsConnected), findsOneWidget,
        reason: 'Connected 态状态文案 = statsConnected（en 词面 "Connected, tap here to test the connection" == NekoBox vpn_connected）');
    expect(find.text('hk-01'), findsOneWidget, reason: '节点名 = connectionSummaryProvider 归一口径');
    expect(find.textContaining('▲'), findsOneWidget);
    expect(find.textContaining('▼'), findsOneWidget);
  });

  testWidgets('点击状态条触发连接测试', (tester) async {
    final t = AppLocale.en.buildSync();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: NkCaptureStatusBar(
            t: t,
            summary: const ConnectionSummary(
              state: NkConnectionState.connected,
              nodeName: 'hk-01',
              capturing: false,
            ),
            uplink: 0,
            downlink: 0,
            onTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NkCaptureStatusBar));
    expect(taps, 1, reason: '点击 = testConnection 对应物（runConnectionTest 进度弹窗由页面薄壳承担）');
  });
}
