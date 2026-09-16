// 「期望选中的节点」+「它属于哪份订阅」的持久存储。
//
// 对应 NekoBox 的两条**持久偏好**：
//   · `database/DataStore.kt:36` `var selectedProxy by configurationStore.long(Key.PROFILE_ID)`
//     —— 选中的实体 id
//   · `ui/MainActivity.kt:419` `DataStore.currentProfile = id`
//     —— 它属于哪份配置
//
// **是持久的"期望值"，不是"待应用一次的临时值"。** 这条区别很关键：
// NekoBox 的选中项重启后仍然有效，因为构建期就把它写成了 selector 的 `default`
// （`fmt/ConfigBuilder.kt:471` `default_ = tagMap[proxy.id]`），
// 且 `ConfigurationFragment.kt:1504-1517` 在用户点节点时是**先落盘、再通知服务**
// （`DataStore.selectedProxy = id` → `SagerNet.reloadService()`），从不清空。
//
// hiddify 内核把那个 `default` 写死成 `balance`（`builder.go:311-341`），应用拿不到口子，
// 所以只能每次内核 ready 后补一次下发 —— 见 `selection_reconcile.dart`
// 与 `ActiveProxyNotifier`。
import 'package:shared_preferences/shared_preferences.dart';

class SelectedProxyStore {
  const SelectedProxyStore(this._prefs);

  final SharedPreferences _prefs;

  /// 键名沿用历史（曾用作"pending"），语义已改为持久期望值。
  /// 不改键名是为了不丢掉用户已经存下的选择。
  static const _outboundKey = 'pending_proxy_outbound';
  static const _profileKey = 'pending_proxy_profile';

  /// 期望选中的节点 tag；空串 = 还没选过（此时内核的默认选中就是当前事实）。
  String get outboundTag => _prefs.getString(_outboundKey) ?? '';

  /// 这个节点属于哪份订阅；空串 = 不做归属校验。
  String get profileId => _prefs.getString(_profileKey) ?? '';

  Future<void> save({required String outboundTag, required String profileId}) async {
    await _prefs.setString(_outboundKey, outboundTag);
    await _prefs.setString(_profileKey, profileId);
  }
}
