import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/proxy_group.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_entity_repository.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _log = _OfflineLogs();

class _OfflineLogs with AppLogger {}

/// 代理页**当前在看哪份订阅的哪个分组**（落盘，照 nekoray 的"当前分组"）。
///
/// 存的是**复合键** `<profileId>::<groupTag>`（见 [groupKeyOf] / [parseGroupKey]）：
/// 多份订阅并存时组名会撞车（两份都可能叫 `select`），只存组名无法区分。
///
/// 定义放在 data 层（而不是 notifier 那边）是为了**避免反向依赖**：
/// `offlineAllProfilesProxyGroupsProvider`、`outboundJsonProvider` 都要读它，
/// 而 overview 层本来就 import 本文件 —— 反过来 import 会绕成环。
final selectedProxyGroupTagProvider = PreferencesNotifier.createAutoDispose("selected_proxy_group", "");

/// **代理页横向切换里的一列** —— 也就是 NekoBox 的一个「分组」。
///
/// 两类来源（NekoBox `GroupType` 的两个取值，见 `database/ProxyGroup.kt`）：
/// - **订阅分组**（`SUBSCRIPTION`）：一份订阅 = 一个组，组名 = 订阅名，[profileId] 非空；
/// - **手动分组**（`BASIC`）：用户在手动入口建的，[profileId] 为空、[groupId] 非空。
///
/// Tab 键：订阅用 `<profileId>::<组名>`（[groupKeyOf]），手动用 `#group:<id>`
/// （[manualGroupTabKey]）。两者格式天然不冲突 —— `parseGroupKey` 对手动键返回 null，
/// 而"这个键属于哪份订阅"这种问题只对订阅分组有意义。
class ProxyGroupTab {
  const ProxyGroupTab({
    required this.key,
    required this.label,
    required this.group,
    this.profileId = '',
    this.groupId,
  });

  final String key;

  /// Tab 文案。
  final String label;

  /// 该 Tab 展示的节点清单（`tag` / `type` / 地址来源都在里面）。
  final OutboundGroup group;

  /// 订阅 id；手动分组为空串。
  final String profileId;

  /// 分组主键；订阅派生的组也有，但调用方用 [profileId] 就够。
  final int? groupId;
}

/// 手动分组的 Tab 键前缀。
String manualGroupTabKey(int groupId) => "#group:$groupId";

/// 从 Tab 键还原手动分组的主键；不是手动键时返回 null。
int? manualGroupIdOf(String key) {
  if (!key.startsWith("#group:")) return null;
  return int.tryParse(key.substring("#group:".length));
}

/// **代理页 Tab 的数据源** —— 订阅分组 + 手动分组，统一成一个列表。
///
/// **以实体表为准**（NekoBox `ConfigBuilder.kt:131` 的 `proxyDao.getByGroup`）：
/// 组名 = 订阅名（或分组名）、成员 = 该组全部节点（按库里 `userOrder`）。
/// 这样"删除节点 / 编辑节点 / 新建节点"立刻可见，而不必等下一轮订阅解析。
///
/// **回落**：该订阅还没有实体分组时（订阅刚导入且回填还没跑、或实体派生失败），
/// 退回到"离线解析它的配置文本"这条老路 —— 行为与引入实体层之前完全一致，
/// 最坏情况只是看不见新能力，不会让页面空掉。
///
/// **空的未分组组不进 Tab**（照 NekoBox `ConfigurationFragment.kt:923-924` 与 `:1031`）：
/// 那个组是懒创建出来的容器（`DataStore.kt:56`），没有内容时出现在 Tab 栏里只是噪声。
/// 命名的手动分组不受此限 —— 用户刚建出来就是空的，藏起来会让人以为没建成功。
final proxyGroupTabsProvider = FutureProvider<List<ProxyGroupTab>>((ref) async {
  final profiles = await ref.watch(profilesNotifierProvider.future);
  final entities = ref.watch(proxyEntityRepositoryProvider);
  final repo = await ref.watch(profileRepositoryProvider.future);
  // 只为"名字为空的分组"取回落文案（NekoBox `R.string.group_default`）。
  final t = ref.watch(translationsProvider).requireValue;

  final result = <ProxyGroupTab>[];
  for (final profile in profiles) {
    var group = await _groupFromEntities(entities, profile);
    var source = "entities";

    if (group == null) {
      final either = await repo.generateConfig(profile.id).run();
      group = either.match(
        (err) {
          _log.loggy.warning("offline proxies: generateConfig failed for [${profile.name}]", err);
          return null;
        },
        (configJson) => parseSubscriptionGroup(configJson, groupName: profile.name, log: _log.loggy.warning),
      );
      source = "config";
    }
    if (group == null) continue;

    // 来源打进日志，且**两条路径用同一句格式**（只差 from 的值）——
    // 这样"列表到底以谁为准"在真机上可直接读出来，不必猜。
    _log.loggy.info("offline proxies: [${profile.name}] ${group.items.length} nodes (from $source)");
    result.add(
      ProxyGroupTab(
        key: groupKeyOf(profile.id, group.tag),
        label: profile.name,
        group: group,
        profileId: profile.id,
      ),
    );
  }

  // 手动分组：按库里的顺序排在订阅之后（`userOrder` 已在 SQL 里排过）
  for (final entry in await entities.listGroups()) {
    final group = entry.group;
    if (group.type != ProxyGroupType.basic) continue;
    if (group.ungrouped && entry.nodeCount == 0) {
      _log.loggy.debug("offline proxies: ungrouped group #${group.id} is empty - hidden from tabs");
      continue;
    }
    final name = groupDisplayName(group, ungroupedLabel: t.pages.groups.defaultName);
    final tabId = group.id;
    final nodes = await entities.groupWithNodes(tabId);
    final outboundGroup = nodes == null
        ? null
        : buildGroupFromEntityNodes(
            groupName: name,
            nodes: [
              for (final node in nodes.nodes)
                (
                  tag: node.tag,
                  type: node.type,
                  displayName: node.displayName,
                  payload: node.payload,
                  status: node.status,
                  ping: node.ping,
                  error: node.error,
                ),
            ],
          );
    _log.loggy.info(
      "offline proxies: manual group [$name] ${outboundGroup?.items.length ?? 0} nodes (from entities)",
    );
    result.add(
      ProxyGroupTab(
        key: manualGroupTabKey(tabId),
        label: name,
        group: outboundGroup ?? (OutboundGroup(tag: name, type: 'selector', selectable: true)),
        groupId: tabId,
      ),
    );
  }

  return result;
});

/// 分组显示名 —— 照 NekoBox `ProxyGroup.displayName()`：
/// `name` 为空时回落到 `R.string.group_default`（「未分组」/ "Ungrouped"）。
String groupDisplayName(ProxyGroupEntry group, {String? ungroupedLabel}) {
    final name = group.name?.trim() ?? '';
    if (name.isNotEmpty) return name;
    // 名字为空时回落到 `R.string.group_default`。文案由调用方给（这里不 import 语言包，
    // 保持 data 层不依赖 UI 层）。
    return ungroupedLabel ?? (group.ungrouped ? 'Ungrouped' : 'Group');
}

/// **Group 页的数据源** —— 全部组 + 每个组的节点数。
///
/// 不区分类型：NekoBox `GroupFragment` 用的就是 `groupDao.allGroups()`（订阅组也列在里面，
/// 因为对 NekoBox 来说订阅只是一个 `type = SUBSCRIPTION` 的分组）。
final proxyGroupListProvider = FutureProvider<List<({ProxyGroupEntry group, int nodeCount})>>(
  (ref) => ref.watch(proxyEntityRepositoryProvider).listGroups(),
);

/// 从实体表取该订阅的节点清单；没有实体分组（或读取失败）时返回 null，由调用方回落。
Future<OutboundGroup?> _groupFromEntities(ProxyEntityRepository entities, ProfileEntity profile) async {
  try {
    final rows = await entities.groupForProfile(profile.id);
    if (rows == null || rows.nodes.isEmpty) return null;
    return buildGroupFromEntityNodes(
      groupName: profile.name,
      nodes: [
        for (final node in rows.nodes)
          (
            tag: node.tag,
            type: node.type,
            displayName: node.displayName,
            payload: node.payload,
            status: node.status,
            ping: node.ping,
            error: node.error,
          ),
      ],
    );
  } catch (err) {
    _log.loggy.warning("offline proxies: entity read failed for [${profile.name}]", err);
    return null;
  }
}

/// Tab 的复合键：`<profileId>::<groupTag>`。
///
/// 必须带订阅 id —— 多份订阅并存时组名会撞车（两份都可能有 `select`），
/// 只存组名无法区分"切到哪一份的哪个组"。
String groupKeyOf(String profileId, String groupTag) => "$profileId::$groupTag";

/// 解析 [groupKeyOf] 产出的键；格式不对（含历史遗留的纯组名）时返回 null。
({String profileId, String groupTag})? parseGroupKey(String key) {
  final i = key.indexOf("::");
  if (i <= 0 || i + 2 >= key.length) return null;
  return (profileId: key.substring(0, i), groupTag: key.substring(i + 2));
}

/// 取某个节点（按 tag）的**出站 JSON** —— 节点卡「分享」动作的数据源。
///
/// **必须先看实体**（列表已经以实体为准）：从订阅配置文本里找 tag 会漏（手动新增的节点）
/// 或给出旧内容（被删除/编辑过的节点）。实体里没有才回落到配置文本，
/// 保证"列表里能点到的节点，这里一定找得到对应出站"这条不变式仍然成立。
///
/// **订阅要用"当前列表所属的那一份"**，不能一律用激活订阅 ——
/// 代理页现在能横切多份订阅，在非激活订阅的节点上点分享时，
/// 用激活订阅的配置去找必然找不到（审计发现的老问题）。
///
/// **手动分组的节点只可能在实体表里**：它们不出现在任何订阅配置文本中，
/// 所以手动 Tab 下直接按 `groupId` 取实体，不做配置回落。
final outboundJsonProvider = FutureProvider.family<String?, String>((ref, tag) async {
  final selectedKey = ref.watch(selectedProxyGroupTagProvider);
  final entities = ref.watch(proxyEntityRepositoryProvider);

  final manualGroupId = manualGroupIdOf(selectedKey);
  if (manualGroupId != null) {
    final payload = await entities.payloadOfNode(groupId: manualGroupId, tag: tag);
    return payload == null ? null : prettyOutboundJson(payload);
  }

  final selectedProfileId = parseGroupKey(selectedKey)?.profileId;
  final profileId = selectedProfileId ?? (await ref.watch(activeProfileProvider.future))?.id;
  if (profileId == null) return null;

  final fromEntity = await entities.payloadOfNode(profileId: profileId, tag: tag);
  if (fromEntity != null) return prettyOutboundJson(fromEntity);

  final repo = await ref.watch(profileRepositoryProvider.future);
  final either = await repo.generateConfig(profileId).run();
  return either.match((err) {
    _log.loggy.warning("node share: generateConfig failed", err);
    return null;
  }, (configJson) => extractOutboundJson(configJson, tag));
});
