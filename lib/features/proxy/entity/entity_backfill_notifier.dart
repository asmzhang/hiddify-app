// 实体回填：应用启动后，把"已导入但还没有实体"的订阅补一遍。
//
// 对应 NekoBox 的哪一环：`group/GroupUpdater.kt` + `database/GroupManager.kt` 在**订阅更新时**
// 维护「分组 + 节点」。本项目把这条链路挂在订阅写入的咽喉上（`ProfileRepositoryImpl._syncEntities`），
// 于是**在实体表出现之前就已导入的订阅**不会自己长出实体 —— 表是空的，第 3/4 步那条链路
// 实际上从未被走过。回填就是新表对既有数据的一次性补齐（等价于一次数据迁移），
// 此后完全由导入/更新驱动，这里就只剩一次廉价的 DB 读。
//
// 为什么不放进 bootstrap 的 await：一条订阅要读一次配置并派生（可能还要回落内核 Parse），
// 不该挡住启动；而且它也不是"能不能用"的前提 —— 拿不到实体时组装会回落到订阅基准
// （见 parity §8.6 第 4 步），行为不会更差。
import 'dart:async';

import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'entity_backfill_notifier.g.dart';

@Riverpod(keepAlive: true)
class EntityBackfillNotifier extends _$EntityBackfillNotifier with InfraLogger {
  var _running = false;

  @override
  void build() {
    // 订阅清单一变（导入/更新/删除/恢复）就检查一遍缺哪些。
    // 判据是"库里有没有该订阅的分组"，所以正常情况下只有第一次运行会有实际动作。
    ref.listen(profilesNotifierProvider, (previous, next) {
      final profiles = next.valueOrNull;
      if (profiles == null || profiles.isEmpty) return;
      unawaited(_backfill(profiles));
    }, fireImmediately: true);
  }

  Future<void> _backfill(List<ProfileEntity> profiles) async {
    if (_running) return; // 上一次还没跑完就别叠上去（串行由内核服务侧的锁保证）
    _running = true;
    try {
      await ref.read(proxyEntityRepositoryProvider).ensureEntitiesForProfiles([
        for (final profile in profiles) (id: profile.id, name: profile.name, lastUpdate: profile.lastUpdate),
      ]);
    } catch (e, stackTrace) {
      loggy.warning("entity backfill crashed", e, stackTrace);
    } finally {
      _running = false;
    }
  }
}
