// 实体落库：把订阅的配置派生为「分组 + 节点实体」并写进数据库。
//
// 这是 docs/design/nekobox-parity.md §8.6 的第 3 步。规格来源（NekoBox）：
//   · `group/GroupUpdater.kt` + `database/GroupManager.kt` —— 订阅更新时创建/维护分组与节点
//   · 一份订阅 = 一个 group（`GroupType.SUBSCRIPTION`），组内节点即 `proxy_entities` 的行
//
// 与 NekoBox 的差异（本项目特有，已记档）：NekoBox 的订阅信息整体存在 `SubscriptionBean`
// 里，本项目仍保留 `ProfileEntries` 作为订阅源，所以把 `profileId` 与 `lastUpdate` 一并记在
// `proxy_groups.subscription` 这段 JSON 里，用它反查"这份订阅对应哪个分组"。
// 这样不必为了一个外键再动一次 schema。
//
// 失败策略：**只记日志、绝不抛出** —— 实体派生失败不能让订阅导入/更新失败
// （导入的成功标准是订阅可用，实体是附加物）。
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/model/proxy_group.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/proxy/data/config_assembly.dart';
import 'package:hiddify/features/proxy/data/proxy_entity_import.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/utils/custom_loggers.dart';

class ProxyEntityRepository with InfraLogger {
  ProxyEntityRepository({required Db db, required ProfilePathResolver pathResolver, required HiddifyCoreService singbox})
    : _db = db,
      _pathResolver = pathResolver,
      _singbox = singbox;

  final Db _db;
  final ProfilePathResolver _pathResolver;
  final HiddifyCoreService _singbox;

  /// 取"要被派生为实体"的那份配置文本 —— 也就是**内核要读的那份输入** `configs/<id>.json`。
  ///
  /// 优先直接读盘，而不是调内核的 `Parse`：
  /// - 那个文件本身就是 `Parse` 的产物（`validateConfig()` 在导入/更新时让内核把解析结果
  ///   写在这里），所以内容等价；
  /// - **不需要内核在跑** ⇒ 回填才能在应用启动时安全执行（`Parse` 走内核里那段不可重入的
  ///   注册表，见 parity §8.6.9，不该在启动路径上排队）；
  /// - 真机实测（2026-09-15，两份订阅 36/48 个节点）：用它派生的实体再覆盖回同一份基准，
  ///   结果是**逐字节相同**，即"没有编辑时启动 .entities.json 与启动订阅基准完全等价"。
  ///
  /// 仅在文件缺失/为空时才回落到内核 `Parse`（旧路径，保持对老数据的兼容）。
  /// 两条路都失败时返回 null，调用方只记日志（[syncFromProfile] 的既有策略）。
  Future<String?> _sourceConfigTextFor({required String profileId, required String profileName}) async {
    final configFile = _pathResolver.file(profileId);
    if (configFile.existsSync()) {
      final text = await configFile.readAsString();
      if (text.trim().isNotEmpty) return text;
    }

    loggy.debug("entity sync: baseline config missing for [$profileName], falling back to core parse");
    final generated = await _singbox.generateFullConfigByPath(configFile.path).run();
    return generated.match((err) {
      loggy.warning("entity sync: no config text for [$profileName]: $err");
      return null;
    }, (content) => content.isEmpty ? null : content);
  }

  /// 把一份订阅的配置派生成分组 + 节点实体并落库（**replace 语义**）。
  ///
  /// 同一份订阅重复导入/更新不会产生重复分组 —— 靠 `subscription` JSON 里的 `profileId` 认领。
  /// 组内的用户属性（`userOrder`/`order`）在更新时**保留**，只刷新名字与节点集合。
  Future<void> syncFromProfile({
    required String profileId,
    required String profileName,
    DateTime? lastUpdate,
    bool isSelector = true,
  }) async {
    try {
      final configJson = await _sourceConfigTextFor(profileId: profileId, profileName: profileName);
      if (configJson == null) return;

      final derived = deriveProxyGroupFromConfig(profileName: profileName, configJson: configJson, isSelector: isSelector);
      if (derived == null) {
        loggy.warning("entity sync: no nodes derived for [$profileName]");
        return;
      }

      final subscriptionJson = encodeSubscriptionPayload(
        profileId: profileId,
        profileName: profileName,
        lastUpdate: lastUpdate,
      );

      final groupId = await _db.transaction(() async {
        final existing = await _db.select(_db.proxyGroups).get();
        final group = existing.where((g) => profileIdOfSubscription(g.subscription) == profileId).firstOrNull;

        if (group == null) {
          final id = await _db
              .into(_db.proxyGroups)
              .insert(
                ProxyGroupsCompanion.insert(
                  type: ProxyGroupType.subscription,
                  name: Value(profileName),
                  subscription: Value(subscriptionJson),
                  isSelector: Value(derived.isSelector),
                ),
              );
          // 新组没有旧覆写可保留 —— 与"整组替换"的其余路径汇合
          return (groupId: id, overrides: const <String, ({String customOutbound, String customConfig})>{});
        }

        // 节点级自定义覆写要跨订阅更新保留（切片 8.5，照 NekoBox
        // `RawUpdater.kt:165-166`：bean.customOutboundJson / customConfigJson
        // 从旧 bean 抄回新 bean）。整组替换前先把它们捞出来，按 tag 回填。
        final preserved = await (_db.select(_db.proxyEntities)
              ..where((t) => t.groupId.equals(group.id))
              ..where((t) => t.customOutbound.equals('').not() | t.customConfig.equals('').not()))
            .get();
        final overridesByTag = <String, ({String customOutbound, String customConfig})>{
          for (final row in preserved)
            row.tag: (customOutbound: row.customOutbound, customConfig: row.customConfig),
        };

        // 更新：保留 order/userOrder 等用户属性，只刷新名字与订阅信息
        await (_db.update(_db.proxyGroups)..where((t) => t.id.equals(group.id))).write(
          ProxyGroupsCompanion(name: Value(profileName), subscription: Value(subscriptionJson)),
        );
        // 节点集合整组替换（replace 语义），避免残留已下线的节点
        await (_db.delete(_db.proxyEntities)..where((t) => t.groupId.equals(group.id))).go();
        return (groupId: group.id, overrides: overridesByTag);
      });

      await _db.batch((batch) {
        batch.insertAll(_db.proxyEntities, [
          for (final (index, entity) in derived.entities.indexed)
            ProxyEntitiesCompanion.insert(
              groupId: groupId.groupId,
              tag: entity.tag,
              type: entity.type,
              displayName: entity.displayName,
              payload: entity.payload,
              userOrder: Value(index),
              // 用户覆写按 tag 回填（订阅更新不丢，NekoBox RawUpdater 同语义）；
              // 该 tag 没有覆写就是默认空串
              customOutbound: Value(groupId.overrides[entity.tag]?.customOutbound ?? ''),
              customConfig: Value(groupId.overrides[entity.tag]?.customConfig ?? ''),
            ),
        ]);
      });

      loggy.info("entity sync: [$profileName] -> group #$groupId with ${derived.entities.length} nodes");
    } catch (e, stackTrace) {
      // 绝不抛出：实体是附加物，订阅导入本身不能因此失败
      loggy.warning("entity sync failed for [$profileName]", e, stackTrace);
    }
  }

  /// 已经在库里有分组的订阅 id 集合（用于判断"这个订阅是否已同步过实体"）。
  Future<Set<String>> syncedProfileIds() async {
    final groups = await _db.select(_db.proxyGroups).get();
    final ids = <String>{};
    for (final group in groups) {
      final id = profileIdOfSubscription(group.subscription);
      if (id != null) ids.add(id);
    }
    return ids;
  }

  /// **回填**：给"还没有实体分组"的订阅补一次同步（幂等）。
  ///
  /// 存在的理由：实体落库挂在订阅写入的咽喉上，所以**在实体表出现之前就已导入的订阅**
  /// 不会自己长出实体 —— 于是第 3/4 步那条链路从来没被真正走过（DB 里两张表是空的）。
  /// 这不是"额外功能"，是新表对既有数据的**一次性补齐**（等价于一次数据迁移）。
  ///
  /// 只处理缺失的（判据见 [missingEntityProfileIds]），因此第二次调用只是一次 DB 读。
  /// 逐条**串行**执行：内核那段注册表不可重入（见 parity §8.6.9），而 `Parse` 正好走那条路，
  /// `HiddifyCoreService` 内部的串行锁会保证顺序，这里不并发发起。
  ///
  /// 返回**尝试**同步的数量（`syncFromProfile` 自身吞异常，所以不等于成功数）。
  /// **绝不抛出**：回填失败不该影响应用启动。
  Future<int> ensureEntitiesForProfiles(List<({String id, String name, DateTime? lastUpdate})> targets) async {
    try {
      final synced = await syncedProfileIds();
      final missing = missingEntityProfileIds(allIds: [for (final t in targets) t.id], synced: synced);
      if (missing.isEmpty) return 0;

      loggy.info("entity backfill: ${missing.length}/${targets.length} profiles have no entities yet");
      var attempted = 0;
      for (final target in targets) {
        if (!missing.contains(target.id)) continue;
        await syncFromProfile(profileId: target.id, profileName: target.name, lastUpdate: target.lastUpdate);
        attempted++;
      }
      loggy.info("entity backfill done: attempted $attempted");
      return attempted;
    } catch (e, stackTrace) {
      loggy.warning("entity backfill failed", e, stackTrace);
      return 0;
    }
  }

  /// 删除某份订阅的实体分组：**组 + 它的全部节点 + `<id>.entities.json`**。
  ///
  /// 为什么需要（审计 F5）：`ProfileRepositoryImpl.deleteById` 原来只删
  /// `profile_entries` 与 `<id>.json`，于是组、节点、`.entities.json` 全成了孤儿 ——
  /// 它们既不显示、也不再更新，却会污染 `syncedProfileIds()` 之类的判断。
  /// 对应 NekoBox 的组级删除语义（组没了，组内节点也不该留下）。
  ///
  /// 失败只记日志（同本文件其他写操作）：订阅删除本身不该因此失败。
  Future<bool> removeGroupForProfile(String profileId) async {
    try {
      final groups = await _db.select(_db.proxyGroups).get();
      final group = groups.where((g) => profileIdOfSubscription(g.subscription) == profileId).firstOrNull;

      if (group != null) {
        await _db.transaction(() async {
          await (_db.delete(_db.proxyEntities)..where((t) => t.groupId.equals(group.id))).go();
          await (_db.delete(_db.proxyGroups)..where((t) => t.id.equals(group.id))).go();
        });
        loggy.info("entity group removed for [$profileId] (group #${group.id})");
      }

      final entityFile = _pathResolver.entityFile(profileId);
      if (entityFile.existsSync()) {
        entityFile.deleteSync();
        loggy.debug("entity assembly file removed for [$profileId]");
      }
      return true;
    } catch (e, stackTrace) {
      loggy.warning("failed to remove entity group for [$profileId]", e, stackTrace);
      return false;
    }
  }

  /// 某份订阅的分组 + 它的节点行（按 `userOrder` 顺序）；没有该订阅的分组时返回 null。
  ///
  /// 对应 NekoBox 的 `proxyDao.getByGroup(group.id)` —— **代理页列表的权威来源**。
  /// 列表以实体为准，节点级的删除/编辑才能立刻在界面上看见。
  Future<({int groupId, List<ProxyEntityEntry> nodes})?> groupForProfile(String profileId) async {
    final groups = await _db.select(_db.proxyGroups).get();
    final group = groups.where((g) => profileIdOfSubscription(g.subscription) == profileId).firstOrNull;
    if (group == null) return null;
    final nodes =
        await (_db.select(_db.proxyEntities)
              ..where((t) => t.groupId.equals(group.id))
              ..orderBy([(t) => OrderingTerm.asc(t.userOrder)]))
            .get();
    return (groupId: group.id, nodes: nodes);
  }

  /// 删除一个节点（按 tag 定位）。返回被删掉的那一行，供撤回时原样放回。
  ///
  /// 对应 NekoBox `ui/ConfigurationFragment.kt` 节点行的 `removeButton`
  /// （`R.id.remove` → 从组里移除，并进 `UndoSnackbarManager` 的回收站）。
  ///
  /// 归属组用 `profileId`（订阅派生的组）或 `groupId`（手动组）指定，二者取其一。
  ///
  /// 语义说明：**订阅更新会把它带回来** —— `syncFromProfile` 是整组替换（NekoBox 同样），
  /// 所以这是"移除"而不是"永久删除"。失败只记日志并返回 null（调用方提示）。
  Future<ProxyEntityEntry?> removeNode({String? profileId, int? groupId, required String tag}) async {
    try {
      final row = (await _nodesOf(profileId: profileId, groupId: groupId)).where((n) => n.tag == tag).firstOrNull;
      if (row == null) return null;

      await (_db.delete(_db.proxyEntities)..where((t) => t.id.equals(row.id))).go();
      loggy.info("node removed: [${row.displayName}] from group #${row.groupId}");
      return row;
    } catch (e, stackTrace) {
      loggy.warning("failed to remove node [$tag]", e, stackTrace);
      return null;
    }
  }

  /// 归属组给 `profileId` 或 `groupId` 都行 —— 它们的取数形状不同，统一在这里归一。
  Future<List<ProxyEntityEntry>> _nodesOf({String? profileId, int? groupId}) async {
    if (groupId != null) return (await groupWithNodes(groupId))?.nodes ?? const [];
    if (profileId != null) return (await groupForProfile(profileId))?.nodes ?? const [];
    return const [];
  }

  /// 按 tag 跨组查节点（启动管线用：选中偏好只存了 tag，启动时取它的节点级覆写）。
  /// tag 在配置里全局唯一（内核按 tag 建索引，重名节点进不来），所以"跨组"不会撞。
  /// 失败返回 null。
  Future<ProxyEntityEntry?> nodeByTagAnyGroup(String tag) async {
    try {
      return (await (_db.select(_db.proxyEntities)..where((t) => t.tag.equals(tag))).get()).firstOrNull;
    } catch (e, stackTrace) {
      loggy.warning("failed to read node [$tag]", e, stackTrace);
      return null;
    }
  }

  /// 撤回上一步删除（NekoBox `UndoSnackbarManager.undo`）：把那一行按原顺序放回。
  Future<bool> restoreNode(ProxyEntityEntry row) async {
    try {
      await _db
          .into(_db.proxyEntities)
          .insert(
            ProxyEntitiesCompanion.insert(
              groupId: row.groupId,
              tag: row.tag,
              type: row.type,
              displayName: row.displayName,
              payload: row.payload,
              userOrder: Value(row.userOrder),
            ),
          );
      loggy.info("node restored: [${row.displayName}]");
      return true;
    } catch (e, stackTrace) {
      loggy.warning("failed to restore node [${row.tag}]", e, stackTrace);
      return false;
    }
  }

  /// 某个节点的**出站定义**（节点「分享」/「编辑」的数据源）。
  ///
  /// 必须与列表**同源**：列表以实体为准之后，从订阅配置文本里找 tag 会漏（刚加的节点）
  /// 或给出旧内容（被编辑过的节点）。找不到实体时返回 null，调用方回落到配置文本。
  ///
  /// 归属组用 `profileId` 或 `groupId` 指定（同 [removeNode]）。
  Future<String?> payloadOfNode({String? profileId, int? groupId, required String tag}) async {
    try {
      return (await _nodesOf(profileId: profileId, groupId: groupId)).where((n) => n.tag == tag).firstOrNull?.payload;
    } catch (e, stackTrace) {
      loggy.warning("failed to read payload of [$tag]", e, stackTrace);
      return null;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 分组实体能力（批次 3）
  //
  // 规格来源（NekoBox）：
  //   · `database/ProxyGroup.kt` —— 字段与默认值（userOrder=0 / ungrouped=false /
  //     name=null / type=BASIC / order=ORIGIN / isSelector=false / front=-1 / landing=-1）
  //   · `database/DataStore.kt:47-85` —— `currentGroup()` 在**一个组都没有**时懒创建一个
  //     `ProxyGroup(ungrouped = true)`（type 取默认 BASIC）；`selectedGroupForImport()`
  //     把新节点落到"当前组（若为 BASIC）否则第一个 BASIC 组"
  //   · `database/GroupManager.kt:82-107` —— createGroup / updateGroup / deleteGroup
  //   · `ui/ConfigurationFragment.kt:918-924 / :1031` —— **空的 ungrouped 组不进 Tab**
  // ───────────────────────────────────────────────────────────────────────────

  /// 全部分组（按 `userOrder`，再按 id 破平）+ 每个组的节点数。
  Future<List<({ProxyGroupEntry group, int nodeCount})>> listGroups() async {
    final rows =
        await (_db.select(_db.proxyGroups)
              ..orderBy([(t) => OrderingTerm.asc(t.userOrder), (t) => OrderingTerm.asc(t.id)]))
            .get();
    final counts = <int, int>{};
    for (final entity in await _db.select(_db.proxyEntities).get()) {
      counts[entity.groupId] = (counts[entity.groupId] ?? 0) + 1;
    }
    return [for (final row in rows) (group: row, nodeCount: counts[row.id] ?? 0)];
  }

  /// 确保存在一个「未分组」组（NekoBox `DataStore.kt:56` 的懒创建），返回它的 id。
  ///
  /// 为什么需要：手动新建的节点**必须**有归属组（照 `selectedGroupForImport()`，
  /// 找不到 BASIC 组时 NekoBox 直接 `!!` 崩），而当前库里只有订阅派生的组。
  Future<int?> ensureUngroupedGroup() async {
    try {
      final existing = await _db.select(_db.proxyGroups).get();
      final ungrouped = existing.where((g) => g.ungrouped && g.type == ProxyGroupType.basic).firstOrNull;
      if (ungrouped != null) return ungrouped.id;
      return await createGroup(ungrouped: true);
    } catch (e, stackTrace) {
      loggy.warning("failed to ensure the ungrouped group", e, stackTrace);
      return null;
    }
  }

  /// 新建分组。`ungrouped = true` 时是"未分组"那个系统组（NekoBox 也是这么建的：
  /// 只置 `ungrouped`，`type` 用默认 BASIC）。
  ///
  /// `userOrder` 取当前最大值 +1（NekoBox `GroupManager` 由界面拖拽维护，
  /// 我们只保证新建的排在最后）。
  Future<int?> createGroup({String? name, bool ungrouped = false, bool isSelector = false}) async {
    try {
      final rows = await _db.select(_db.proxyGroups).get();
      final nextOrder = rows.isEmpty ? 0 : rows.map((g) => g.userOrder).reduce((a, b) => a > b ? a : b) + 1;
      final id = await _db
          .into(_db.proxyGroups)
          .insert(
            ProxyGroupsCompanion.insert(
              type: ProxyGroupType.basic,
              name: Value(name),
              ungrouped: Value(ungrouped),
              isSelector: Value(isSelector),
              userOrder: Value(nextOrder),
            ),
          );
      loggy.info("group created: #$id (ungrouped=$ungrouped)");
      return id;
    } catch (e, stackTrace) {
      loggy.warning("failed to create group", e, stackTrace);
      return null;
    }
  }

  /// 拖拽移动分组（NekoBox `GroupFragment.kt:203-226` 的 `move` + `commitMove`）。
  ///
  /// NekoBox 的算法是**链式平移**而非交换：`from` 的位置插入后，中间的组依次把自己的
  /// `userOrder` 往后接力，`from` 拿走链尾的 order。`[from, to]` 是界面前后两次
  /// `onReorder` 的位置（from < to 向下移 / from > to 向上移，语义一致）。
  ///
  /// [ids] 必须是**当前界面顺序**（即 `listGroups()` 的返回序，`userOrder` 升序 +
  /// id 破平），一次拖拽结束后整表重算 `userOrder = 界面下标`，中间态（长按拖着
  /// 连续滑过几行）天然被吸收 —— 这比逐次接力更稳，且对库而言结果等价
  /// （NekoBox 需要接力是因为它只 update 被碰过的行；我们整表落库，行数 ≤ 组数）。
  ///
  /// `ungrouped` 组**不参与**拖拽（NekoBox `getDragDirs` 返回 0 的语义）：
  /// 调用方必须把它排除在重排集合之外；这里只做防御性断言（它若在 [ids] 里，
  /// 它的 order 不被改动，但整表重算会把它挤回原位 —— 所以正确用法是调用方过滤）。
  Future<bool> moveGroups({required List<int> idsInDisplayOrder}) async {
    try {
      await _db.transaction(() async {
        for (final (index, id) in idsInDisplayOrder.indexed) {
          await (_db.update(_db.proxyGroups)..where((t) => t.id.equals(id))).write(
            ProxyGroupsCompanion(userOrder: Value(index)),
          );
        }
      });
      loggy.info("groups reordered: $idsInDisplayOrder");
      return true;
    } catch (e, stackTrace) {
      loggy.warning("failed to reorder groups", e, stackTrace);
      return false;
    }
  }

  /// 改分组名（null / 空 = 回到 NekoBox 的 `R.string.group_default`「未分组」）。
  Future<bool> renameGroup({required int groupId, required String? name}) async {
    try {
      await (_db.update(_db.proxyGroups)..where((t) => t.id.equals(groupId))).write(
        ProxyGroupsCompanion(name: Value((name ?? '').trim().isEmpty ? null : name!.trim())),
      );
      return true;
    } catch (e, stackTrace) {
      loggy.warning("failed to rename group #$groupId", e, stackTrace);
      return false;
    }
  }

  /// 删除分组：**组 + 组内全部节点**（NekoBox `GroupManager.deleteGroup` 同语义）。
  ///
  /// 订阅派生的组不走这里（那由订阅删除驱动，见 [removeGroupForProfile]）。
  Future<bool> removeGroup(int groupId) async {
    try {
      await _db.transaction(() async {
        await (_db.delete(_db.proxyEntities)..where((t) => t.groupId.equals(groupId))).go();
        await (_db.delete(_db.proxyGroups)..where((t) => t.id.equals(groupId))).go();
      });
      loggy.info("group removed: #$groupId (with its nodes)");
      return true;
    } catch (e, stackTrace) {
      loggy.warning("failed to remove group #$groupId", e, stackTrace);
      return false;
    }
  }

  /// 清空分组：**只删节点、保留组行**（NekoBox `GroupManager.clearGroup` 的语义：
  /// `deleteAll(group.id)`，组本身不动 —— 用户要的是"清掉里面的节点"，不是"删掉这个分组"）。
  ///
  /// 与 [removeGroup]（组 + 节点都删）的分工照 NekoBox：
  ///   · `deleteGroup` → [removeGroup]（分组页 🗑）
  ///   · 动作菜单 "清空分组" → 本函数（分组页 ⋮）
  /// 订阅组的节点会被下次订阅更新带回来 —— 这也是"清空 ≠ 删除"语义的一部分
  /// （NekoBox 同样如此：订阅更新会重建节点）。
  /// 返回被清掉的节点数；失败返回 -1（调用方提示）。
  Future<int> clearGroupNodes(int groupId) async {
    try {
      final count = await (_db.delete(_db.proxyEntities)..where((t) => t.groupId.equals(groupId))).go();
      loggy.info("group cleared: #$groupId ($count nodes removed, group kept)");
      return count;
    } catch (e, stackTrace) {
      loggy.warning("failed to clear group #$groupId", e, stackTrace);
      return -1;
    }
  }

  /// 按主键取组 + 它的节点行（按 `userOrder`）。
  Future<({ProxyGroupEntry group, List<ProxyEntityEntry> nodes})?> groupWithNodes(int groupId) async {
    try {
      final group = await (_db.select(_db.proxyGroups)..where((t) => t.id.equals(groupId))).getSingleOrNull();
      if (group == null) return null;
      final nodes =
          await (_db.select(_db.proxyEntities)
                ..where((t) => t.groupId.equals(groupId))
                ..orderBy([(t) => OrderingTerm.asc(t.userOrder), (t) => OrderingTerm.asc(t.id)]))
              .get();
      return (group: group, nodes: nodes);
    } catch (e, stackTrace) {
      loggy.warning("failed to read group #$groupId", e, stackTrace);
      return null;
    }
  }

  /// 全局重名检查 —— 节点 `tag` 是**内核配置里的身份**，重名会让组装层按 tag 建的索引
  /// 互相覆盖（`applyEntitiesToOutbounds` 的 `payloadByTag`）。NekoBox 靠 DB 主键区分，
  /// 但它的配置 tag 也是显示名，所以同样存在这个约束。
  Future<bool> tagExists(String tag) async {
    final rows = await (_db.select(_db.proxyEntities)..where((t) => t.tag.equals(tag))).get();
    return rows.isNotEmpty;
  }

  /// 清除测试结果（NekoBox `ConfigurationFragment` ⋮ 菜单的 `Clear test results`）。
  ///
  /// 语义与范围说明（为什么只清实体、不碰内核）：
  /// - 列表行的延迟显示来自内核 `OutboundsInfo` 的实时贴值（`joinLiveIntoGroup`），
  ///   **不是**实体列；但内核的延迟历史持久在 `outbound_monitoring_history` 缓存里，
  ///   应用侧没有"清历史"的 RPC。连接状态下重测一遍即可覆盖；**断开状态下**
  ///   列表显示的就是实体的 `ping`/`status`/`error` 列（离线骨架无实时值可贴），
  ///   清这三列对断开态立竿见影。
  /// - 范围：按 [profileId]（订阅派生组）或 [groupId]（手动组）清；都空则全清
  ///   （NekoBox 的菜单动作也是"当前组"，UI 层负责传当前 Tab）。
  /// 返回受影响行数；失败返回 -1（调用方提示）。
  Future<int> clearTestResults({String? profileId, int? groupId}) async {
    try {
      final nodes = await _nodesOf(profileId: profileId, groupId: groupId);
      if (nodes.isEmpty) return 0;
      final count = await (_db.update(_db.proxyEntities)..where((t) => t.id.isIn(nodes.map((e) => e.id)))).write(
        const ProxyEntitiesCompanion(status: Value(0), ping: Value(0), error: Value(null)),
      );
      loggy.info("test results cleared for $count nodes");
      return count;
    } catch (e, stackTrace) {
      loggy.warning("failed to clear test results", e, stackTrace);
      return -1;
    }
  }

  /// 清空流量统计（NekoBox `ConfigurationFragment.kt:460-475`
  /// `action_clear_traffic_statistics`）。
  ///
  /// 规格原文：遍历组内节点，`tx != 0 || rx != 0` 者清零后 `ProfileManager.updateProfile`
  /// 落库——**无确认框、无 toast、不碰内核**。NekoBox 的节点流量增量由
  /// `TrafficMonitor` 贴回实体，故实体列即流量真相；本项目 tx/rx 列暂无写入方
  /// （未来接流量统计时用），先照规格把动作补齐。
  /// 范围约定同 [clearTestResults]：[profileId]（订阅组）或 [groupId]（手动组）。
  /// 返回受影响行数；失败返回 -1（调用方提示）。
  Future<int> clearTrafficStats({String? profileId, int? groupId}) async {
    try {
      final nodes = await _nodesOf(profileId: profileId, groupId: groupId);
      // 照 NekoBox：只碰 tx/rx 非零者，零值行不进 update（节省写放大）。
      final toClear = nodes.where((e) => e.tx != 0 || e.rx != 0).toList();
      if (toClear.isEmpty) return 0;
      final count = await (_db.update(_db.proxyEntities)..where((t) => t.id.isIn(toClear.map((e) => e.id)))).write(
        const ProxyEntitiesCompanion(tx: Value(0), rx: Value(0)),
      );
      loggy.info("traffic stats cleared for $count nodes");
      return count;
    } catch (e, stackTrace) {
      loggy.warning("failed to clear traffic stats", e, stackTrace);
      return -1;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 去重（NekoBox `ConfigurationFragment.kt:534-580` 的 `action_remove_duplicate`
  // + `Protocols.Deduplication`）。
  //
  // 判重口径（照 `Deduplication.hash()`）：**serverAddress + serverPort + type** ——
  // 名字不参与（NekoBox 的两个重名节点只要地址端口一样就算重复），凭据不参与
  // （同地址同端口换了密码在 NekoBox 口径下也是重复）。
  // hiddify 的对应物：payload（出站 JSON）里的 `server` + `server_port` + `type`。
  // ───────────────────────────────────────────────────────────────────────────

  // ───────────────────────────────────────────────────────────────────────────
  // TCP ping（NekoBox `ConfigurationFragment.kt:694-832` 的 `pingTest(false)`）。
  //
  // 应用侧直连测速（dart:io Socket，见 tcp_ping.dart），不碰内核 —— 但结果要
  // 落到实体的 `status`/`ping`/`error` 列（NekoBox `ProfileManager.updateProfile`
  // 同落点），断开状态下列表显示的就是这三列。
  // ───────────────────────────────────────────────────────────────────────────

  /// 批量写回测速结果。返回受影响行数；失败返回 -1（调用方提示）。
  Future<int> updateTestResults(List<({int id, int status, int ping, String? error})> results) async {
    try {
      var count = 0;
      await _db.transaction(() async {
        for (final r in results) {
          count += await (_db.update(_db.proxyEntities)..where((t) => t.id.equals(r.id))).write(
            ProxyEntitiesCompanion(status: Value(r.status), ping: Value(r.ping), error: Value(r.error)),
          );
        }
      });
      loggy.info("test results written for $count nodes");
      return count;
    } catch (e, stackTrace) {
      loggy.warning("failed to write test results", e, stackTrace);
      return -1;
    }
  }

  /// 找出一组节点里的重复者：首次出现的保留，后续出现的算重复。
  ///
  /// 返回 (duplicates, keys)：duplicates 是要删的行；keys 是 tag → 判重键
  /// （UI 确认框要展示重复者名单，用 tag 定位）。解析不出地址/端口的节点
  /// （如手动构造的怪 payload）判为**不重复** —— 判重键拿不到就别误删。
  ({List<ProxyEntityEntry> duplicates, Map<String, String> keys}) findDuplicateNodes(List<ProxyEntityEntry> nodes) {
    final keys = <String, String>{};
    final seen = <String>{};
    final duplicates = <ProxyEntityEntry>[];
    for (final node in nodes) {
      final key = dedupKeyOf(payload: node.payload, type: node.type);
      // 键为空 = 解析失败 ⇒ 不参与判重，直接当作"没见过"放行
      if (key == null || seen.add(key)) {
        if (key != null) keys[node.tag] = key;
        continue;
      }
      duplicates.add(node);
    }
    return (duplicates: duplicates, keys: keys);
  }

  /// 找出一组节点里的**测速失败者**（NekoBox `ConfigurationFragment.kt:495-532`
  /// 的 `action_connection_test_delete_unavailable`）。
  ///
  /// 判据照抄 NekoBox：`status != 0 && status != 1` —— 测过且失败（status>=2）
  /// 的才删；未测速（status=0）的**不算**不可用，不能误删。
  /// 返回要删的行；空列表 = 没有失败者（UI 照 NekoBox 不弹确认框）。
  List<ProxyEntityEntry> findUnavailableNodes(List<ProxyEntityEntry> nodes) =>
      [for (final node in nodes) if (node.status != 0 && node.status != 1) node];

  /// 批量删除节点（去重的执行端）。返回实际删除的行数；失败返回 -1。
  Future<int> deleteNodes(Iterable<ProxyEntityEntry> nodes) async {
    try {
      final ids = nodes.map((e) => e.id).toList();
      if (ids.isEmpty) return 0;
      final count = await (_db.delete(_db.proxyEntities)..where((t) => t.id.isIn(ids))).go();
      loggy.info("nodes deleted: $count");
      return count;
    } catch (e, stackTrace) {
      loggy.warning("failed to delete ${nodes.length} nodes", e, stackTrace);
      return -1;
    }
  }

  /// 手动新建一个节点（NekoBox `ProfileSettingsActivity.saveAndExit` 的 `editingId == 0` 分支 →
  /// `ProfileManager.createProfile(groupId, bean)`）。
  ///
  /// `displayName` 与 `tag` 同值：本项目里 tag 就是用户填的名字（NekoBox 的
  /// `displayName()` 返回 `name`，配置 tag 也由它来），所以两者一致；
  /// 拆分这两列是为了给将来的"改名"留出空间（改名要迁移 tag，见 parity §5）。
  ///
  /// 失败（含重名）只记日志并返回 null，调用方提示。
  Future<ProxyEntityEntry?> createNode({
    required int groupId,
    required String tag,
    required String type,
    required String payload,
  }) async {
    try {
      // `chain:` 是 chain 落地出站的保留前缀（组装层用它命名选中入口，设计
      // chain-2026-09-20.md §4）；普通节点占用会让 chain 落地撞名。
      if (tag.startsWith(kChainTagPrefix)) {
        loggy.warning("node tag [$tag] uses the reserved chain prefix - rejected");
        return null;
      }
      final existing = await (_db.select(_db.proxyEntities)..where((t) => t.tag.equals(tag))).get();
      if (existing.isNotEmpty) {
        loggy.warning("node tag already exists: [$tag]");
        return null;
      }
      final siblings = await (_db.select(_db.proxyEntities)..where((t) => t.groupId.equals(groupId))).get();
      final nextOrder = siblings.isEmpty ? 0 : siblings.map((e) => e.userOrder).reduce((a, b) => a > b ? a : b) + 1;
      final id = await _db
          .into(_db.proxyEntities)
          .insert(
            ProxyEntitiesCompanion.insert(
              groupId: groupId,
              tag: tag,
              type: type,
              displayName: tag,
              payload: payload,
              userOrder: Value(nextOrder),
            ),
          );
      loggy.info("node created: [$tag] into group #$groupId");
      return (_db.select(_db.proxyEntities)..where((t) => t.id.equals(id))).getSingle();
    } catch (e, stackTrace) {
      loggy.warning("failed to create node [$tag]", e, stackTrace);
      return null;
    }
  }

  /// 手动（非订阅）组的全部节点 —— 它们要被**追加**进任何一份订阅的出站表，
  /// 因为它们不属于任何订阅配置，内核跑哪份都该带上。
  Future<List<ProxyEntityEntry>> manualNodes() async {
    final groups = await _db.select(_db.proxyGroups).get();
    final basicIds = {for (final g in groups) if (g.type == ProxyGroupType.basic) g.id};
    if (basicIds.isEmpty) return const [];
    return (_db.select(_db.proxyEntities)
          ..where((t) => t.groupId.isIn(basicIds))
          ..orderBy([(t) => OrderingTerm.asc(t.userOrder), (t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  /// 全部 chain 实体（type=='chain'）。chain 落手动组 ⇒ 它天然在 [manualNodes]
  /// 里，这里只是给 UI/校验用的便捷视图。
  Future<List<ProxyEntityEntry>> chainNodes() async {
    final rows = await (_db.select(_db.proxyEntities)..where((t) => t.type.equals(kChainEntityType))).get();
    return rows;
  }

  /// 保存一条 chain 的成员定义（ChainSettings 页保存按钮的落点）。
  ///
  /// [proxies] 是**有序成员 tag**（UI 序 = 流量经过顺序：第一行入口、最后一行落地），
  /// 序列化成 `{"proxies":[…]}` 存 payload（设计 chain-2026-09-20.md D1）。
  /// 新建（库里无此 tag）走创建；已有（编辑）走 payload 整段替换 —— 与
  /// [updateNodePayload] 同语义（tag 是身份，不改名）。
  /// 失败返回 null（调用方提示，不落库）。
  Future<ProxyEntityEntry?> saveChain({
    required int groupId,
    required String tag,
    required List<String> proxies,
    String? displayName,
  }) async {
    final payload = jsonEncode({'proxies': proxies});
    final existing = await (_db.select(_db.proxyEntities)..where((t) => t.tag.equals(tag))).get();
    if (existing.isNotEmpty) {
      final row = existing.first;
      await (_db.update(_db.proxyEntities)..where((t) => t.id.equals(row.id))).write(
        ProxyEntitiesCompanion(payload: Value(payload), displayName: Value(displayName ?? row.displayName)),
      );
      return (_db.select(_db.proxyEntities)..where((t) => t.id.equals(row.id))).getSingle();
    }
    return createNode(groupId: groupId, tag: tag, type: kChainEntityType, payload: payload);
  }

  /// 供 ChainSettings 的成员选择对话框用：可选成员 = 全部实体里**能当跳点**的
  /// （排除 endpoint 型 —— 内核 stub 拒收；chain 实体可嵌套引用，保留）。
  Future<List<ProxyEntityEntry>> selectableChainMembers() async {
    final rows = await _db.select(_db.proxyEntities).get();
    return rows.where((r) => r.type != 'wireguard').toList();
  }

  /// 改写一个节点的**出站定义**（节点行 ✎ 的落点）。
  ///
  /// 对应 NekoBox `ui/profile/*SettingsActivity` 的保存：改的是实体的那份配置。
  /// NekoBox 存的是 Bean（`ProxyEntity` 的每协议列），本项目存的是整条出站 JSON
  /// （差异已在 parity §8.6 记档），所以这里就是整段替换。
  ///
  /// **不改 `tag`**：`tag` 是节点身份（内核配置、选中偏好、`staleNodeTags` 都用它），
  /// 改名是独立功能（NekoBox `name_preferences.xml`），不混进编辑表单。
  /// 失败只记日志并返回 false（调用方提示，不落库）。
  /// 归属组用 `profileId` 或 `groupId` 指定（同 [removeNode] —— 手动组的节点也要能编辑）。
  /// 失败只记日志并返回 false（调用方提示，不落库）。
  Future<bool> updateNodePayload({String? profileId, int? groupId, required String tag, required String payload}) async {
    try {
      final row = (await _nodesOf(profileId: profileId, groupId: groupId)).where((n) => n.tag == tag).firstOrNull;
      if (row == null) return false;

      await (_db.update(_db.proxyEntities)..where((t) => t.id.equals(row.id))).write(
        ProxyEntitiesCompanion(payload: Value(payload)),
      );
      loggy.info("node payload updated: [$tag]");
      return true;
    } catch (e, stackTrace) {
      loggy.warning("failed to update payload of [$tag]", e, stackTrace);
      return false;
    }
  }

  /// 保存节点行的**节点级覆写**（切片 8.5，NekoBox `ProfileSettingsActivity.kt:298-312`
  /// 两个 ⋮ 菜单项的落点：`bean.customOutboundJson = …` / `bean.customConfigJson = …`）。
  ///
  /// 空串 = 停用该覆写。只动覆写列、不碰 `payload` —— 两者是 NekoBox Bean 的两个
  /// 独立字段（`AbstractBean.java:24-25`），编辑协议字段不该动覆写，反之亦然。
  /// 失败只记日志并返回 false。
  Future<bool> updateNodeOverrides({
    String? profileId,
    int? groupId,
    required String tag,
    String? customOutbound,
    String? customConfig,
  }) async {
    try {
      final row = (await _nodesOf(profileId: profileId, groupId: groupId)).where((n) => n.tag == tag).firstOrNull;
      if (row == null) return false;

      await (_db.update(_db.proxyEntities)..where((t) => t.id.equals(row.id))).write(
        ProxyEntitiesCompanion(
          customOutbound: Value(customOutbound ?? row.customOutbound),
          customConfig: Value(customConfig ?? row.customConfig),
        ),
      );
      loggy.info("node overrides updated: [$tag]");
      return true;
    } catch (e, stackTrace) {
      loggy.warning("failed to update overrides of [$tag]", e, stackTrace);
      return false;
    }
  }

  /// 组装**要交给内核启动的出站表**：实体层覆盖订阅基准的节点段。
  ///
  /// 为什么要这么做（docs/design/nekobox-parity.md §8.6 第 4 步）：内核真正读的是
  /// `configs/<id>.json`，而它**只有 `{"outbounds":[…]}`` —— 节点集合的所有权原本在"订阅原文"手里。
  /// 把这一段的产出改由实体表决定，"节点可编辑"才有落脚点。
  ///
  /// 只动节点：组（selector/urltest/balancer）一律原样透传 —— 内核 `builder.go:130-371`
  /// 每次都会丢弃输入里的组并重建 `select`/`balance`/`lowest`，所以应用管组是无意义的。
  ///
  /// 返回写入 [`ProfilePathResolver.entityFile`] 的内容；无法组装时返回 **null**，
  /// 调用方回落订阅基准文件。**只记日志、绝不抛出**（同 [syncFromProfile]：
  /// 组装失败不该让用户连不上网）。
  Future<String?> assembleOutboundsForProfile(String profileId) async {
    try {
      final group = (await _db.select(_db.proxyGroups).get())
          .where((g) => profileIdOfSubscription(g.subscription) == profileId)
          .firstOrNull;
      if (group == null) {
        loggy.debug("entity assembly: no group for [$profileId]");
        return null;
      }

      final rows = await (_db.select(_db.proxyEntities)
            ..where((t) => t.groupId.equals(group.id))
            ..orderBy([(t) => OrderingTerm.asc(t.userOrder)]))
          .get();
      if (rows.isEmpty) {
        loggy.debug("entity assembly: no entities for [$profileId]");
        return null;
      }

      final baselineFile = _pathResolver.file(profileId);
      if (!baselineFile.existsSync()) {
        loggy.warning("entity assembly: baseline config missing for [$profileId]");
        return null;
      }
      // 直接读盘：这份文件正是内核要读的输入，且导入/更新时已由 Parse 规范化并写入
      final baselineJson = await baselineFile.readAsString();

      // 订阅组自己的节点（基准里同名的那一段由实体说了算）
      final subscriptionTags = [for (final row in rows) row.tag];
      final entities = <ImportedProxyEntity>[
        for (final row in rows)
          ImportedProxyEntity(
            tag: row.tag,
            type: row.type,
            payload: row.payload,
            displayName: row.displayName,
            // 节点级覆写（切片 8.5）：组装层据此做出站深合并
            customOutbound: row.customOutbound,
            customConfig: row.customConfig,
          ),
      ];

      // **手动组（type=basic）的节点要被追加进任何一份订阅的出站表。**
      //
      // 为什么必须合并：NekoBox 的配置由整个 DB 现场构建（`ConfigBuilder.kt`），
      // 所有组的节点天然在同一份配置里；本项目是"一份订阅一份配置"，手动节点不属于
      // 任何订阅 ⇒ 不合并的话它永远进不了内核，"选中它"就无从谈起。
      //
      // tag 撞车时**订阅侧优先**并告警：基准里那个 tag 的所有权在订阅，
      // 且 `applyEntitiesToOutbounds` 按 tag 建索引（后者覆盖前者），不挡会产生
      // "配置里的节点与界面上的不是同一个"这种最难查的状态。
      for (final row in await manualNodes()) {
        if (subscriptionTags.contains(row.tag)) {
          loggy.warning("entity assembly: manual node [${row.tag}] shadows a subscription node - skipped");
          continue;
        }
        entities.add(
          ImportedProxyEntity(
            tag: row.tag,
            type: row.type,
            payload: row.payload,
            displayName: row.displayName,
            customOutbound: row.customOutbound,
            customConfig: row.customConfig,
          ),
        );
      }

      final assembled = applyEntitiesToOutbounds(
        baselineConfigJson: baselineJson,
        entities: entities,
        // 基准是订阅原文的快照，里面**留着被删除的节点** —— 不点名移除就等于
        // "删除只在界面生效"（审计 F1）。判据与派生/解析同一份。
        // 只拿订阅组的 tag 算 stale：手动节点本来就不在基准里，加进来不影响结果。
        staleTags: staleNodeTags(
          baselineConfigJson: baselineJson,
          entityTags: subscriptionTags,
        ),
      );
      if (assembled == null) {
        loggy.warning("entity assembly: apply failed for [$profileId], falling back to subscription config");
        return null;
      }

      loggy.info("entity assembly: [$profileId] $assembled");
      return assembled.configJson;
    } catch (e, stackTrace) {
      loggy.warning("entity assembly failed for [$profileId]", e, stackTrace);
      return null;
    }
  }
}
