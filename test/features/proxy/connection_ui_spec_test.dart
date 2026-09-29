import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/connection/widget/connection_fab.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

void main() {
  test('FAB 状态矩阵对齐 NekoBox ServiceButton', () {
    expect(
      connectionFabSpec(null),
      const ConnectionFabSpec(visual: ConnectionFabVisual.stopped, action: ConnectionFabAction.connect, enabled: false),
      reason: 'Idle/UI 尚未绑定服务时按钮禁用',
    );
    expect(
      connectionFabSpec(const Disconnected()),
      const ConnectionFabSpec(visual: ConnectionFabVisual.stopped, action: ConnectionFabAction.connect, enabled: true),
    );
    expect(
      connectionFabSpec(const Connecting()),
      const ConnectionFabSpec(visual: ConnectionFabVisual.connecting, action: ConnectionFabAction.stop, enabled: true),
      reason: 'Connecting.canStop=true，用户可以取消连接',
    );
    expect(
      connectionFabSpec(const Connected()),
      const ConnectionFabSpec(visual: ConnectionFabVisual.connected, action: ConnectionFabAction.stop, enabled: true),
    );
    expect(
      connectionFabSpec(const Disconnecting()),
      const ConnectionFabSpec(
        visual: ConnectionFabVisual.stopping,
        action: ConnectionFabAction.connect,
        enabled: false,
      ),
    );
  });

  test('当前节点操作限制只覆盖服务 started 状态', () {
    expect(connectionNodeInUse(const Connecting()), isTrue);
    expect(connectionNodeInUse(const Connected()), isTrue);
    expect(connectionNodeInUse(const Disconnecting()), isFalse);
    expect(connectionNodeInUse(const Disconnected()), isFalse);
    expect(connectionNodeInUse(null), isFalse);
  });

  test('主列表重复点当前节点判定为 no-op', () {
    final selectedByGroup = OutboundGroup(
      selected: 'A',
      items: [OutboundInfo(tag: 'A')],
    );
    expect(proxySelectionAlreadyActive(selectedByGroup, 'A'), isTrue);
    expect(proxySelectionAlreadyActive(selectedByGroup, 'B'), isFalse);

    final selectedByItem = OutboundGroup(items: [OutboundInfo(tag: 'B', isSelected: true)]);
    expect(proxySelectionAlreadyActive(selectedByItem, 'B'), isTrue);
  });

  test('SingleCall 的 Future 等到启动任务真正结束，并拒绝并发重入', () async {
    final gate = SingleCall();
    final started = Completer<void>();
    final finish = Completer<void>();
    var completed = false;

    final first = gate.run(() async {
      started.complete();
      await finish.future;
      completed = true;
    }, onIgnored: null);
    await started.future;

    expect(completed, isFalse);
    expect(await gate.run(() async => fail('并发任务不应执行'), onIgnored: 'ignored'), 'ignored');
    finish.complete();
    await first;
    expect(completed, isTrue, reason: '调用方 await SingleCall 必须等到底层启动完成');
  });

  testWidgets('ConnectionFab 实际渲染、tooltip 与点击门控', (tester) async {
    var taps = 0;
    final t = AppLocale.en.buildSync();

    Future<void> pump(ConnectionStatus? status) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: ConnectionFab(status: status, onPressed: () => taps++, t: t),
        ),
      ),
    );

    await pump(null);
    expect(tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNull);
    expect(find.byIcon(FluentIcons.send_24_regular), findsOneWidget);

    await pump(const Disconnected());
    expect(find.byTooltip('Connect'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    expect(taps, 1);

    await pump(const Connecting());
    expect(find.byTooltip('Stop'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    expect(taps, 2, reason: 'Connecting 必须可点击取消');

    await pump(const Connected());
    expect(find.byTooltip('Stop'), findsOneWidget);
    expect(find.byIcon(FluentIcons.send_24_filled), findsOneWidget);

    await pump(const Disconnecting());
    expect(tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
