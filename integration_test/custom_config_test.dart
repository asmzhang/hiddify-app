// custom_config 实机集成验证（Task #33）—— 跑在真实 Windows 构建上（真内核 FFI）。
//
// 验证目标（挂起清单：批次 8 raw 通道 + 切片 8.5 节点级覆写的实机验证）：
//   1. raw 通道：global customConfig 非空 ⇒ 连接管线走
//      `generateFullConfigByPath → deepMergeJson → startRawContent(EnableRawConfig=true)`
//   2. 节点覆写：customConfig 列（drift）⇒ 启动时经 nodeByTagAnyGroup 取到并入合并
//   3. 深合并产物语法必须合法（坏合并会以 invalid config 类失败暴露）
//
// 设计取舍：
// - **不断言真实出口流量**——节点可用性受外部网络影响，测试必须可重复。断言点 =
//   「启动管线级证据」：App 全链路启动（真内核 Parse/Start FFI）+ 仓库层读回覆写值
//   + 连接不因 raw 合并产物非法而失败。
// - global customConfig 用 `{"log":{"level":"trace"}}`（NekoBox 裸键替换语义，
//   deepMergeJson 已有 13 个单测；这里验证的是**管线真的走通**）。
// - profile 用 addLocal 注入**本地 sing-box JSON**（单 socks 出站），
//   不依赖订阅远端（无网络也能建组；validateConfig 走真内核 Parse FFI）。
// - prefs 直写 `custom-config`（PreferencesNotifier 底层就是 SharedPreferences
//   该键），与用户从设置页写入路径逐字节一致。
//
// 坑位提醒（沿用 main_test.dart）：
// - lazyBootstrap 必须在 testWidgets 体内；pump 用 tester；
// - 常驻动画要 settleBounded；跑前 ensure_plugin_junctions.ps1 + unset 代理。
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/db/provider/db_providers.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hiddify_app.dart';

/// 本地 profile 内容：单 socks 出站 + 注释头（profile-title 决定显示名）。
/// 节点可用性无关紧要——断言的是管线证据，不是出口 IP。
const _localProfileContent = '''
#profile-title: raw-channel-test
{"outbounds":[{"type":"socks","tag":"raw-test-node","server":"127.0.0.1","server_port":1080}]}
''';

/// global customConfig 观测标记：裸键替换（deepMergeJson 已有 13 单测），
/// trace 级日志对内核无害。
const _globalCustomConfig = '{"log":{"level":"trace"}}';

/// 节点级覆写观测标记：clash api 控制器端口改到 16990（最后改卷权验证点）。
const _nodeCustomConfig = '{"experimental":{"clash_api":{"external_controller":"127.0.0.1:16990"}}}';

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('custom_config：raw 通道连接 + 节点覆写读回', (tester) async {
    // ── 0. 预写 prefs：global customConfig（与设置页同键） ──
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_completed', true);
    await prefs.setString('locale', 'en');
    await prefs.setString('custom-config', _globalCustomConfig);

    // ── 1. 启动真 App ──
    await startHiddifyApp();
    try {
      await tester.pumpAndSettle(const Duration(seconds: 5));
    } catch (_) {}

    final element = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(element, listen: false);

    // ── 2. 确认 ConfigOptions.customConfig 从 prefs 读到标记 ──
    final customConfigValue = container.read(ConfigOptions.customConfig);
    expect(customConfigValue, _globalCustomConfig, reason: 'PreferencesNotifier 必须从 prefs 读到 global customConfig');

    // ── 3. addLocal 建本地 profile（走真内核 validateConfig = Parse FFI） ──
    final profilesRepo = await container.read(profileRepositoryProvider.future);
    final failure = await profilesRepo.addLocal(_localProfileContent).run().then(
          (r) => r.match((l) => l, (r) => null),
        );
    expect(failure, isNull, reason: 'addLocal 不应失败：$failure');

    // 拿到刚建的 profile 并设为 active
    final profilesEither = await profilesRepo.watchAll().first;
    final profiles = profilesEither.match((l) => <Never>[], (ps) => ps,);
    expect(profiles, isNotEmpty, reason: '本地 profile 必须建成功');
    final profile = profiles.first;
    await profilesRepo.setAsActive(profile.id).run();

    // ── 4. DB 直写节点级 customConfig（模拟节点编辑页保存） ──
    final db = container.read(dbProvider);
    final node = await (db.select(db.proxyEntities)..where((t) => t.tag.equals('raw-test-node'))).get();
    expect(node, isNotEmpty, reason: 'addLocal 后实体同步必须产出 raw-test-node');
    await (db.update(db.proxyEntities)..where((t) => t.tag.equals('raw-test-node'))).write(
      const ProxyEntitiesCompanion(customConfig: drift.Value(_nodeCustomConfig)),
    );

    // 验证启动管线用的读取路径（nodeByTagAnyGroup）能拿到覆写
    final entityRepo = container.read(proxyEntityRepositoryProvider);
    final nodeAfter = await entityRepo.nodeByTagAnyGroup('raw-test-node');
    expect(nodeAfter?.customConfig, _nodeCustomConfig, reason: '节点级覆写必须经 nodeByTagAnyGroup 读回');

    // ── 5. 连接：global 非空 ⇒ 必走 raw 通道 ──
    // SelectedProxyStore：期望选中 raw-test-node（管线会取它的节点覆写）
    await prefs.setString('pending_proxy_outbound', 'raw-test-node');
    await prefs.setString('pending_proxy_profile', profile.id);

    final connectionRepo = container.read(connectionRepositoryProvider);
    final connectFailure = await connectionRepo.reconnect(profile, false).run().then(
          (r) => r.match((l) => l, (r) => null),
        );
    if (connectFailure != null) {
      final msg = connectFailure.toString();
      // socks 127.0.0.1:1080 拨不通不影响内核启动成功（内核按配置起监听，不预拨节点）。
      // 但 raw 合并产物若语法非法会以 invalid config 类失败暴露——那才是真 bug。
      final isInvalidConfig = msg.toLowerCase().contains('invalid');
      expect(isInvalidConfig, isFalse, reason: 'raw 合并产物语法必须合法（deepMergeJson 管线证据）：$msg');
      debugPrint('CUSTOM-CONFIG-TEST: 连接返回非致命失败（预期内，socks 拨不通）: $msg');
    }

    // ── 5.5 硬证据：内核 raw 模式真实启动 + 节点覆写真实生效 ──
    // 节点覆写把 clash_api 挪到 16990（内核默认 16756）。16990 若响应 HTTP，
    // 同时证明两件事：① 内核以 raw 合并产物启动成功（EnableRawConfig=true 路径）；
    // ② 节点级覆写真的被合并进了最终配置（「最后改卷权」落在运行态）。
    // 给足启动时间：内核 Start 是异步的，reconnect 返回≠监听已就绪。
    Object? probeErr;
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:16990/version'));
        final res = await req.close().timeout(const Duration(seconds: 2));
        final body = await res.transform(utf8.decoder).join();
        client.close(force: true);
        debugPrint('CUSTOM-CONFIG-TEST: clash API @16990 响应 HTTP ${res.statusCode}：$body');
        probeErr = null;
        break;
      } catch (e) {
        probeErr = e;
      }
    }
    expect(probeErr, isNull, reason: '节点覆写 clash_api 16990 必须响应——内核 raw 启动 + 节点覆写生效的硬证据：$probeErr');

    // ── 6. 断开（清理内核状态） ──
    await container.read(connectionRepositoryProvider).disconnect().run();

    debugPrint('CUSTOM-CONFIG-TEST: raw 通道管线 + 节点覆写读回全部通过');
  });
}
