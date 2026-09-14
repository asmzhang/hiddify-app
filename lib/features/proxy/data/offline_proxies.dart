import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _log = _OfflineLogs();

class _OfflineLogs with AppLogger {}

/// **未连接时的节点清单（常驻内容）** —— "没连接也能挑节点、看延迟、测速"的全部依据。
///
/// 核心只有在 `Start` 之后才建出 outbounds，并且只在运行时通过 gRPC 暴露"有哪些节点、
/// 哪些组"。但这份清单**在连接之前就存在** —— `generateConfig(id)` 返回的配置里
/// `outbounds` 已经包含了全部分组（hiddify 自己的 `select`、面板自带分组、urltest/balancer）
/// 以及它们的成员。
///
/// 所以：**清单来源 = 订阅配置，跟连接状态无关**。更新订阅它立刻变；启停内核它不动。
/// 内核只用来补"跑起来才知道"的延迟和用量。
///
/// 解析逻辑在 `offline_proxy_parser.dart`（纯 Dart，可被 `dart run` 直接验证）。
final offlineProxyGroupsProvider = FutureProvider<List<OutboundGroup>>((ref) async {
  final profile = await ref.watch(activeProfileProvider.future);
  if (profile == null) return const [];
  final repo = await ref.watch(profileRepositoryProvider.future);
  final either = await repo.generateConfig(profile.id).run();

  // **绝不吞错**：这条链断掉就等于"必须先连接才有内容"，所以失败一定要能在日志里看见。
  return either.match(
    (err) {
      _log.loggy.warning("offline proxies: generateConfig failed", err);
      return const [];
    },
    (configJson) {
      final groups = parseOfflineProxyGroups(configJson, log: _log.loggy.warning);
      _log.loggy.info(
        "offline proxies: parsed ${groups.length} groups "
        "(${groups.map((g) => "${g.tag}:${g.items.length}").join(", ")})",
      );
      return groups;
    },
  );
});

/// 取某个节点（按 tag）的**出站 JSON** —— 节点卡「分享」动作的数据源。
///
/// 与离线清单同源（同一个 `generateConfig` 结果），所以 tag 口径天然一致：
/// 列表里能点到的节点，这里一定找得到对应出站。
final outboundJsonProvider = FutureProvider.family<String?, String>((ref, tag) async {
  final profile = await ref.watch(activeProfileProvider.future);
  if (profile == null) return null;
  final repo = await ref.watch(profileRepositoryProvider.future);
  final either = await repo.generateConfig(profile.id).run();
  return either.match((err) {
    _log.loggy.warning("node share: generateConfig failed", err);
    return null;
  }, (configJson) => extractOutboundJson(configJson, tag));
});
