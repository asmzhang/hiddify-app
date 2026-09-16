# 代码审计 —— 代理页 / 连接 / 刷新（2026-09-15）

审计范围：这几天为「切换分组 / 连接开关 / 自动刷新」改动过的全部文件。

- `features/connection/notifier/connection_notifier.dart`
- `features/connection/notifier/system_proxy_notifier.dart`
- `features/connection/model/connection_status.dart`
- `features/proxy/overview/proxies_overview_notifier.dart`
- `features/proxy/overview/proxies_overview_page.dart`
- `features/proxy/data/offline_proxies.dart`
- `features/proxy/active/active_proxy_notifier.dart`
- `core/preferences/general_preferences.dart`

方法：逐条对照真实运行日志（`%APPDATA%\Hiddify\hiddify\app.log`）与真实订阅数据
（`db.sqlite` / `configs/*.json`），并对 riverpod 的不确定语义写复现脚本验证
（`tool/riverpod_repro_test.dart`）；不凭推测下结论。

---

## 一、发现并已修（7 项）

### 1. 仅代理模式下点连接按钮：白重启内核，状态永远不变  **[真 bug]**

`capturingProvider` 在 `ServiceMode.proxy` 下恒为 `false`；但 `setCapture` 只给 TUN 开了特例，
proxy 会一路走到最后的「重启内核」路径 —— 重启后 `capturing` 依旧是 false，
于是**白重启一次、界面还永远停在「未连接」**。

**修**：

- `capturingProvider`：`proxy => coreUp`（仅代理模式下"服务中"= 内核在跑）
- `setCapture`：非 systemProxy 一律「开 = 启内核，关 = 停内核」，不再走重启路径

### 2. 「测试全部」硬编码 `urlTest("select")`  **[真 bug]**

页面菜单里写死了组名 `select`，而真实组名是「节点选择」这类 ⇒ 内核找不到该组，
批量测速**静默失效**（只有兜底平铺的组才正好叫 `select`）。

**修**：改为下发当前 Tab 的组 tag（从选中键解析），空则不发。

### 3. 节点分享只认激活订阅  **[真 bug]**

`outboundJsonProvider` 用 `activeProfileProvider` —— 代理页现在能横切多份订阅，
在**非激活订阅**的节点上点分享必然找不到出站（返回 null）。

**修**：改用「当前列表所属订阅」（从选中键解析，回落激活订阅）。

### 4. data 层反向依赖 overview 层，且构成循环 import  **[分层]**

修复第 3 项时，`offline_proxies.dart`（data）需要 `selectedProxyGroupTagProvider`，
而它定义在 `proxies_overview_notifier.dart`（overview）—— 而 overview 本来就 import data。

**修**：把该 provider 的定义挪到 data 层（`offline_proxies.dart`），overview 从那里引用。

### 5. `_mergeLive` 直接改缓存对象的字段  **[缓存污染]**

`base.items` 里的对象来自 provider 缓存，原代码直接 `matched.isSelected = ...`，
等于**污染缓存**：下次静态显示（未连接/非激活订阅）会残留上一次的高亮与延迟。

**修**：一律 `deepCopy()` 后再写字段。

### 6. 静态分支原地重排缓存  **[缓存污染]**

`_sortOutbounds(offline, ...)` 内部会 `items.clear() + addAll()` **原地重排**，
而 `offline` 就是缓存里的那个分组对象。

**修**：传 `offline.deepCopy()`。

### 7. 高亮可能标错组  **[正确性]**

`merged.selected` 取的是**内核第一个组**的选中项，而 `base` 可能是用户在看的另一个组
（如「自动选择」）⇒ 高亮标到别的组的节点上。

**修**：只有 `live.tag == base.tag`（同一个组）时才采信内核的 `selected`，否则用 base 的。

---

## 二、记录待处理（未修，影响面小）

| # | 问题 | 说明 | 建议 |
|---|---|---|---|
| 8 | `offlineAllProfilesProxyGroupsProvider` 每份订阅都 `generateConfig` | 订阅列表（db）一变就重算**全部**订阅，开销随订阅数线性增长；订阅更新检查（几分钟一次）会触发它 | 按 `profile.id + lastUpdate` 做结果缓存，只重算变化的那份 |
| 9 | `Preferences.startedByUser` 是死字段 | 只有写入，唯一读取（`connection_wrapper.dart:52`）被注释掉了 | 要么删掉，要么恢复其用途（自动重连/恢复上次状态） |
| 10 | `toggleConnection` 先写 `startedByUser` 再 `setCapture` | 后者可能幂等早退，导致两者不一致（因第 9 项当前无影响） | 与第 9 项一并处理 |
| 11 | `IpInfoNotifier` 的前置条件是 `serviceRunning`（接管语义） | 查 IP 只需内核能出网，其实不要求接管；未接管时按此条件查不了 | 若希望"不接管也能查 IP"，条件改用 `coreRunningProvider` |
| 12 | `urlTest` 对**非激活订阅**的组会失败 | 内核只加载激活订阅的配置，测速请求会被拒 | 失败时给一次提示（或在非激活 Tab 上禁用「测试全部」） |

---

## 三、验证

- `flutter analyze --no-pub` → **No issues found!**
- `flutter build windows --release` → 成功
- 逻辑层面用真实数据核对：订阅「云霄」（48 节点 / 0 分组 → 兜底）、
  「一分机场」（39 节点 / 2 分组：`节点选择` selector + `自动选择` urltest）
