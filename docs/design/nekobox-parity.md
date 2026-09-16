# NekoBox 功能对照清单（规格源：NekoBoxForAndroid 源码）

> 2026-09-15 建。**本文件是规格清单，不是设计方案** —— 每一行都以
> `S:\test\NekoBoxForAndroid` 的源码文件为准，标注 hiddify-app 的现状。
> 原则：**完全对照 NekoBox，功能也对照**（用户要求，勿按个人偏好裁剪）。
>
> 状态图例：✅ 已对齐 ｜ 🟡 部分（注明差异）｜ ❌ 缺失 ｜ 🟠 硬充 ｜ ⚪ 非功能面（框架基类）｜ ⛔ 既有约定不移植
>
> **另见 `docs/audit/2026-09-15-nekobox-function-matrix.md`** —— 把本文件的每一项重判为
> 「1:1 完成 / 硬充 / 没有完成 / 完全漏」四类（含 7 条口径纠正：磁贴是硬充而非缺失、
> 备份 tab 存在但缺分类勾选、6 个"页面"其实是框架基类等）。**要做功能盘点看那份，要查规格看这份。**
>
> 规格源文件：`res/xml/*.xml`（设置与协议表单）、`res/menu/*.xml`（菜单动作）、
> `AndroidManifest.xml`（平台组件）、`database/`（实体）、`ui/*.kt`（页面）。

---

## 1. 导航抽屉（规格：`res/menu/main_drawer_menu.xml`）

| # | NekoBox 项 | id | hiddify 现状 |
|---|---|---|---|
| 1 | Configuration | `nav_configuration` | ✅ `proxies_overview_page.dart` |
| 2 | Group | `nav_group` | 🟡 `profiles_page.dart`：只有订阅列表，无「分组」实体与手动分组 |
| 3 | Route | `nav_route` | ✅ `rule_page.dart`（含 domain/ip/port 细粒度字段） |
| 4 | Settings | `nav_settings` | ✅ `settings_page.dart`（五类内联） |
| 5 | Logs | `nav_logcat` | ✅ `logs_page.dart` |
| 6 | sing-box Dashboard | `nav_traffic` | 🟠 **硬充**：hiddify 自研统计页（3 张卡），NekoBox 是内嵌 yacd 面板（连接列表/按连接操作/建规则/面板 URL）—— 同名不同物，见 `docs/audit/2026-09-15-nekobox-function-matrix.md` §3 |
| 7 | Tools | `nav_tools` | ✅ `tools_page.dart` |
| 8 | Ads | `nav_tuiguang` | ⛔ 推广位，不移植 |
| 9 | Document | `nav_faq` | ⛔ 文档页，不移植 |
| 10 | About | `nav_about` | ✅ `about_page.dart` |

---

## 2. 节点页工具栏（规格：`res/menu/add_profile_menu.xml`，32 项）

### 2.1 订阅/导入类

| NekoBox 项 | id | hiddify 现状 |
|---|---|---|
| Update all subscriptions | `action_update_all` | ✅ `profiles_page` 批量更新 |
| Create group | `action_new_group` | ❌ 无分组实体，无法手动建组 |
| Add Profile | `action_add` | ✅ |
| Scan QR code | `action_scan_qr_code` | ✅ 已确认可用：`fix_btns.dart:60-67` → `showQrCodeScanner()` → `QrCodeScannerDialog`（`qr_code_scanner_screen.dart:403-464`）。该文件 403 行以前是**被注释的历史实现**，别再当成"不可用" |
| Import from Clipboard | `action_import_clipboard` | ✅ |
| Import from file | `action_import_file` | 🟡 需确认 |
| **Manual Settings**（手动新建节点） | 15 个协议子项 | 🟡 **依赖已就绪、待做**：节点实体表 + 组装 + 列表 + 删除均已自测通过；缺 ① 协议表单（批次 1/2）② 手动分组（手动节点要有归属组，批次 3）。协议清单：SOCKS/HTTP/Shadowsocks/VMess/VLESS/Trojan/Trojan Go/Mieru/Naïve/Hysteria/TUIC/ShadowTLS/AnyTLS/SSH/WireGuard |
| Custom Config | `action_new_config` | ❌ 无「新建自定义配置」入口 |
| Proxy Chain | `action_new_chain` | 🟡 hiddify 的 chain 在设置里（extraSecurity/unblocker），不是可新建的实体 |

### 2.2 订阅维护类

| NekoBox 项 | id | hiddify 现状 |
|---|---|---|
| Update current Group's subscription | `action_update_subscription` | ✅ |
| Clear traffic statistics | `action_clear_traffic_statistics` | ❌ |
| Remove duplicate servers | `action_remove_duplicate` | ❌（全库 0 命中） |

### 2.3 测速类

| NekoBox 项 | id | hiddify 现状 |
|---|---|---|
| TCPing | `action_connection_tcp_ping` | ❌（全库 0 命中） |
| URL Test | `action_connection_url_test` | ✅ 菜单「测试全部」，按当前组下发 |
| Clear test results | `action_connection_test_clear_results` | ❌ |
| Clear unavailable | `action_connection_test_delete_unavailable` | ❌ |

### 2.4 排序类

| NekoBox 项 | id | hiddify 现状 |
|---|---|---|
| Order → Origin | `action_order_origin` | ✅ `ProxiesSort.unsorted` |
| Order → By Name | `action_order_by_name` | ✅ `ProxiesSort.name` |
| Order → By Delay | `action_order_by_delay` | ✅ `ProxiesSort.delay` |
| （hiddify 额外） | — | ➕ `ProxiesSort.usage`（NekoBox 没有） |

---

## 3. 动作菜单（4 份规格）

### 3.1 `profile_config_menu.xml`（节点/配置项菜单）

| NekoBox 项 | id | hiddify 现状 |
|---|---|---|
| Remove | `action_delete` | ✅ 删除订阅 |
| Apply | `action_apply` | ✅ 设为激活订阅 |
| Create Shortcut | `action_create_shortcut` | 🟡 有 `features/shortcut/`（Android） |
| Move | `action_move` | ✅ 拖拽排序 |
| Custom outbound JSON | `action_custom_outbound_json` | ❌ |
| Custom config JSON | `action_custom_config_json` | 🟡 `json_editor.dart`（在详情页，非此菜单） |

### 3.2 `profile_share_menu.xml`（分享，9 项）

| NekoBox 项 | hiddify 现状 |
|---|---|
| QR code → Group / Standard / SN Link | 🟡 有 QR 对话框（`qr_code_dialog.dart`），无 SN Link |
| Export to Clipboard → Group / Standard / SN Link | ❌ 订阅级分享缺失（全库 0 命中） |
| Configuration → Export to Clipboard / Export to file | ❌ |

> 现状：hiddify 只有**节点级**「复制出站 JSON」（`extractOutboundJson`），没有订阅级分享。
> 参考：NekoBox 的 SN Link = `UniversalFmt`（`fmt/UniversalFmt.kt`）。

### 3.3 `group_action_menu.xml`（分组右键）

| NekoBox 项 | hiddify 现状 |
|---|---|
| Share Subscription | ❌ |
| Export to Clipboard / QR | ❌ |
| Export / Export to file / Clear | ❌ |

### 3.4 `traffic_item_menu.xml`（仪表盘按连接项）

| NekoBox 项 | hiddify 现状 |
|---|---|
| Copy / Copy Name / Copy Package Name | ❌ |
| Open App / Open Settings / Open Market | ❌ |
| Create Rule | ❌ |

### 3.5 其他菜单

| 规格文件 | 内容 | hiddify 现状 |
|---|---|---|
| `app_list_menu.xml` / `per_app_proxy_menu.xml` | 反选 / 清空 / 导出剪贴板 / 导入剪贴板 | 🟡 `per_app_proxy` 有备份模型（`per_app_proxy_backup.dart`），菜单形态待对齐 |
| `logcat_menu.xml` | Update / Export debug info / Clear Logcat | ❌ 清空与导出缺失 |
| `route menu` | Create Route / Reset / Manage Route Assets | 🟡 有规则与预设规则；**无 Assets 管理** |
| `yacd_menu.xml` | Set panel URL / close | ❌ 无内嵌面板 |

---

## 4. 设置（规格：`res/xml/global_preferences.xml`，5 类 29 项）

### 4.1 App Settings（15 项）

| NekoBox key | 标题 | hiddify 现状 |
|---|---|---|
| `isAutoConnect` | Auto Connect | 🟡 hiddify 是 `silent_start` + 自动起内核，语义不同 |
| `appTheme` | Theme | ✅ 5 色板 |
| `nightTheme` | Night Mode | ✅ 日/夜/AMOLED |
| `serviceMode` | Service Mode | ✅ |
| `tunImplementation` | TUN Implementation | ✅ |
| `mtu` | MTU | ✅ |
| `speedInterval` | 通知速率刷新间隔 | ❌ |
| `profileTrafficStatistics` | 订阅流量统计 | 🟡 有流量条展示，无独立开关 |
| `showDirectSpeed` | 显示直连速率 | ❌ |
| `showGroupInNotification` | 通知显示分组名 | ❌ |
| `alwaysShowAddress` | 始终显示地址 | ❌ |
| `meteredNetwork` | 计费网络提示 | ❌ |
| `acquireWakeLock` | 保持唤醒锁 | ❌（Android 特有） |
| `logLevel` | Log Level | ✅ |
| `globalCustomConfig` | 全局自定义配置 | ❌ |

### 4.2 Route Settings（7 项）

| NekoBox key | 标题 | hiddify 现状 |
|---|---|---|
| `proxyApps` | Apps VPN mode | ✅ `per_app_proxy`（Android） |
| `bypassLan` | Bypass LAN（应用侧分流规则） | 🟡 形态不同：hiddify 走「预设规则 → Bypass LAN」；**内核侧那一半由下一行的 `bypassLanInCore` 承担** |
| `bypassLanInCore` | Bypass LAN in Core | ✅ 已实施（`d672db7e`；设置页「路由」卡开关 → 内核 `bypass-lan` → `builder.go:677-695` 追加 `IPIsPrivate → direct`） |
| `trafficSniffing` | Enable Traffic Sniffing | ❌（core 无该配置项） |
| `resolveDestination` | Resolve Destination | ✅ |
| `ipv6Mode` | IPv6 Route | ✅ |
| `rulesProvider` | Rule Assets Provider | ❌ 无 Assets 源选择 |

### 4.3 DNS Settings（7 项）

| NekoBox key | 标题 | hiddify 现状 |
|---|---|---|
| `remoteDns` | Remote DNS | ✅ `remote-dns-address` |
| `domain_strategy_for_remote` | Remote 域名策略 | ✅ |
| `directDns` | Direct DNS | ✅ |
| `domain_strategy_for_direct` | Direct 域名策略 | ✅ |
| `domain_strategy_for_server` | 服务器地址域名策略 | ❌ |
| `enableDnsRouting` | Enable DNS Routing | ❌（`enable-dns-routing` 键被注释） |
| `enableFakeDns` | Enable FakeDNS | ✅ |

### 4.4 Inbound Settings（3 项）

| NekoBox key | 标题 | hiddify 现状 |
|---|---|---|
| `mixedPort` | Proxy Port | ✅ `mixedPort` |
| `appendHttpProxy` | Append HTTP Proxy to VPN | ❌ |
| `allowAccess` | 允许局域网连接 | ✅ `allowConnectionFromLan` + `lan_sharing_password` |

### 4.5 Misc Settings（8 项）

| NekoBox key | 标题 | hiddify 现状 |
|---|---|---|
| `connectionTestURL` | Connection Test URL | ✅ |
| `enableClashAPI` | Enable Clash API | ✅ + `clash-api-port` |
| `networkChangeResetConnections` | 换网重置连接 | ❌ |
| `wakeResetConnections` | 唤醒重置连接 | ❌ |
| `globalAllowInsecure` | 全局允许不安全 | ⛔ 内核卡住：NekoBox 在 4 个 Fmt.kt 组装层做 `bean.allowInsecure \|\| globalAllowInsecure`，hiddify 出站组装在内核 Parse（`HiddifyOptions` 无此字段），需重建内核库才能做 |
| `allowInsecureOnRequest` | 更新订阅时跳过证书检查 | ✅ `DioHttpClient` 增加订阅专用 insecure 实例（`badCertificateCallback` 放行），`ProfileParser` 订阅下载按开关路由；其余请求不受影响（`tool/check_insecure_request.dart` 10 项校验） |
| `appTLSVersion` | 订阅最低 TLS 版本 | ⛔ SDK 卡住：NekoBox 的 `restrictedTLS()` 是 Libcore(Go) 能力，dart:io 无最低 TLS 版本 API（仅 ALPN） |
| `showBottomBar` | SagerNet 式底部栏 | ✅ hiddify StatsBar（形态不同） |

### 4.6 hiddify 独有（NekoBox 没有，保留不删）

`use-xray-core-when-possible`、`balancer-strategy`、`region`、`strict-route`、`url-test-interval`、
`independent-dns-cache`、TLS 分片/填充/mixed-SNI 共 7 项、`mux-*` 4 项、
`chain`（extraSecurity / unblocker + WARP / Psiphon）共 15 项、tproxy/redirect/direct 端口 4 项、
`auto_apps_selection_*`、窗口位置/尺寸、`action_at_close` 等。

---

### 4.7 桌面形态映射（nekoray 参照，2026-09-16）

> 原则：**规格以 NekoBox（Android）为主，nekoray（桌面孪生，`S:/test/nekoray` 4.0.1）
> 只用来回答"Android 特有能力在桌面端的正统形态是什么"**。不做第二套界面。
> 此前被归入 B 档"Android 管线、桌面无意义"的项，经 nekoray 对照后重新分档：

| NekoBox Android 项 | nekoray 桌面形态（源码依据） | hiddify 桌面现状 | 结论 |
|---|---|---|---|
| `speedInterval`（通知速率刷新间隔） | `traffic_loop_interval`（500-5000ms，0=禁用），`TrafficLooper::Loop()` 线程 | 内核 `GetSystemInfoStream` 每秒推（`hcore commands.go`），托盘 tooltip 每秒更新 | ✅ 桌面固定 1s 已够用，不做独立开关 |
| `showDirectSpeed` | 主窗 `label_speed` "Proxy: x\nDirect: y" | 仪表盘/侧栏/代理页速率条已有；**托盘 tooltip 已加速率行**（↑↓，2026-09-16） | ✅ |
| `showGroupInNotification`（通知显示分组/节点） | tray tooltip：`[Tun]/[System Proxy]` + `节点@分组`（`mainwindow.cpp make_title`） | **托盘 tooltip 已加**：`[模式短名] 节点名` + 延迟 + 速率（2026-09-16） | ✅ |
| `acquireWakeLock`（保持唤醒） | nekoray 无对应（防睡眠未实现） | — | ⛔ 参考实现都没有，不做 |
| 快捷方式 / 磁贴 | nekoray：全局热键（`dialog_hotkey`）+ 托盘菜单 | 托盘菜单已有（连接切换/服务模式/退出）；热键缺 | 🟡 热键留待需要时做 |
| `alwaysShowAddress`（列表始终显示地址） | nekoray 列表设置 | 待查 proxy_tile | 🟡 缓 |
| per-node 流量统计（Android TrafficLooper 逐 profile） | nekoray 走自家 core 的 v2rayapi `QueryStats(tag)`（`db/traffic/TrafficLooper.cpp`） | hiddify-core 未启用 V2Ray stats、hcore gRPC 无 per-outbound 统计 RPC（只有总速率 `GetSystemInfoStream`） | ⛔ 内核卡住不变 |

**技术事实**：hcore 的 `SystemInfo.uplink/downlink` 是**每秒速率**（UI 以 `.speed()` 直接格式化，
两次采样差值），`OutboundInfo.tagDisplay` 是节点显示名 —— 托盘 tooltip 的数据源全在 Dart 侧现成。

## 5. 协议编辑表单（规格：`res/xml/*_preferences.xml`）

**hiddify 现状：4/12 已实施**（anytls / shadowsocks / standard_v2ray(VLESS) / hysteria2），
其余 8 份仍 ❌（只有 `profile_details_page` 的 JSON 编辑器）。

> **依赖已就绪**（2026-09-15）：节点实体表（含凭据 payload）、组装成 `<id>.entities.json`、
> 列表以实体为准、删除+撤销 —— 全部已实施并**真机自测通过**。所以"表单改完写回实体 →
> 重组装 → 重载内核"这条链路**不需要再新建任何东西**，只差表单本身。
> 分批见 `nekobox-priority.md` 批次 1（4 个主力协议，**已完成**）/ 批次 2（其余 8 个 + 自定义配置）。

**已实施的 4 份**（规格驱动的可执行版本 = `lib/features/proxy/data/protocol_form.dart`；
字段 → sing-box JSON 的映射在文件内逐条注明，判据是 `fmt/*/*Fmt.kt` 的
`buildSingBoxOutbound*`，不是 Bean 属性名 —— 两处 key 名不一致，按**行为**对齐）：

| 表单 | 已覆盖字段（NekoBox key → payload 路径） | 未纳入（如实） |
|---|---|---|
| `anytls` | serverAddress→`server` / serverPort→`server_port` / password→`password` / sni→`tls.server_name` / allowInsecure→`tls.insecure` / alpn→`tls.alpn`(数组) / certificates→`tls.certificate` / utlsFingerprint→`tls.utls.fingerprint`(+`enabled`) | ECH（真机 0 节点用到） |
| `standard_v2ray`（VLESS；VMess 复用同一规格） | 上述全部 ＋ uuid→`uuid` / encryption(对 VLESS＝**flow**)→`flow` / packetEncoding→`packet_encoding` / type→`transport.type` / host / path（**按传输方式换路径**） / wsMaxEarlyData / earlyDataHeaderName / security→`tls.enabled` / realityPubKey→`tls.reality.public_key`(+`enabled`) / realityShortId | alterId / encryption(VMess 语义) / mux 4 项 / ECH |
| `hysteria`（v2） | serverAddress / serverPorts→`server_port` / serverPassword→`password` / serverSNI / serverALPN / serverCertificates / serverAllowInsecure / serverObfs→`obfs`(+`type:"salamander"`) / serverUploadSpeed→`up_mbps` / serverDownloadSpeed→`down_mbps` / serverStreamReceiveWindow / serverConnectionReceiveWindow / hopInterval | protocolVersion / serverProtocol / serverAuthType / serverDisableMtuDiscovery（v1 概念或 NekoBox 自己注释掉） |
| `shadowsocks` | serverAddress / serverPort / method（18 项取值照 `@array/ss_enc_method_value`）/ password / pluginName→`plugin` / pluginConfig→`plugin_opts` | sUoT（sing-box 侧是 `{enabled,version}` 对象，表单只有一个布尔） |

**跨全部协议的未纳入项**：
- **改名**（`name_preferences.xml`）：`tag` 是节点身份（内核配置 / 选中偏好 / 删除基线三处都用它）
  ⇒ 要跨三处迁移，与"手动新建节点"是同一套机制，应一起做（见 `nekobox-priority.md` §8.3）。
- **网络可见性**：本批只做"编辑已有节点"，不做"新建"（新建要各协议的 `tls.enabled` 等**种子键**，
  因为现在这些键是靠"原样保留"活下来的）。

各表单的字段明细（按 NekoBox 的 key，直接作为实现规格）：

| 表单 | 字段（key） |
|---|---|
| `anytls` | name / serverAddress / serverPort / password ｜ sni / allowInsecure / alpn / certificates / utlsFingerprint |
| `shadowtls` | name / serverAddress / serverPort / version / password ｜ sni / alpn / certificates / allowInsecure / utlsFingerprint |
| `shadowsocks` | name / serverAddress / serverPort / method / password ｜ pluginName / pluginConfig ｜ sUoT |
| `standard_v2ray`（VMess/VLESS） | name / serverAddress / serverPort / username / password / uuid / alterId / encryption / packetEncoding / type / host / path / security ｜ wsMaxEarlyData / earlyDataHeaderName ｜ sni / alpn / certificates / allowInsecure ｜ utlsFingerprint / realityPubKey / realityShortId ｜ enableMux / muxType / muxConcurrency / muxPadding ｜ enableECH / echConfig |
| `trojan_go` | profileName / serverAddress / serverPort / serverPassword / serverSNI / serverAllowInsecure / serverNetwork / serverEncryption ｜ serverHost / serverPath ｜ serverMethod / serverPassword1 |
| `tuic` | profileName / serverAddress / serverPort / serverUsername / serverPassword / serverALPN / serverCertificates / serverUDPRelayMode / serverCongestionController / serverDisableSNI / serverSNI / serverReduceRTT / serverAllowInsecure |
| `hysteria` | profileName / protocolVersion ｜ serverAddress / serverPorts / serverObfs / serverAuthType / serverPassword / serverProtocol / serverSNI / serverALPN / serverCertificates / serverAllowInsecure / serverUploadSpeed / serverDownloadSpeed / serverStreamReceiveWindow / serverConnectionReceiveWindow / serverDisableMtuDiscovery / hopInterval |
| `mieru` | profileName ｜ serverAddress / serverPort / serverProtocol / serverUsername / serverPassword / serverMTU |
| `naive` | profileName ｜ serverAddress / serverPort / serverUsername / serverPassword / serverProtocol / serverHeaders / serverSNI / serverCertificates / serverInsecureConcurrency ｜ sUoT |
| `socks` | profileName ｜ serverProtocol / serverAddress / serverPort / serverUsername / serverPassword ｜ sUoT |
| `ssh` | profileName ｜ serverAddress / serverPort / serverUsername / serverAuthType / serverPassword / serverPrivateKey / serverPassword1 / serverCertificates |
| `wireguard` | name ｜ serverAddress / serverPort / localAddress / privateKey / peerPublicKey / peerPreSharedKey / mtu / reserved |
| `config`（自定义配置） | profileName / isOutboundOnly / serverConfig |
| `balancer` | profileName / balancerType / balancerStrategy / balancerGroup |
| `group` | groupName / groupType / groupOrder / groupIsSelector / groupFrontProxy / groupLandingProxy ＋ 订阅（subscriptionLink / subscriptionForceResolve / subscriptionDeduplication）＋ 更新（subscriptionUpdateWhenConnectedOnly / subscriptionUserAgent / subscriptionAutoUpdate / subscriptionAutoUpdateDelay=1440） |
| `route` | routeName / serverConfig ｜ routePackages / routeDomain / routeIP / routePort / routeSource / routeSourcePort / routeNetwork / routeProtocol / routeOutbound |

---

## 6. 平台组件（规格：`AndroidManifest.xml`）

| 组件 | 类型 | hiddify 现状 |
|---|---|---|
| `MainActivity` | activity | ✅ |
| `BlankActivity` / `ThemedActivity` / `VpnRequestActivity` / `ToolbarFragment` / `SettingsPreferenceFragment` / `NamedFragment` | 框架基类 | ⚪ **不是功能面**（不计入缺口核对） |
| **16 个 `profile/*SettingsActivity`** | activity | ❌ 对应 §5 缺失 |
| `GroupSettingsActivity` | activity | ❌ |
| `RouteSettingsActivity` | activity | 🟡 有规则编辑 |
| `AssetsActivity`（geo 资源管理） | activity | ❌ |
| `AppListActivity` | activity | ✅ 每应用代理 |
| `AppManagerActivity` | activity | ✅ 每应用代理（`per_app_proxy_page` + `android_apps_page`） |
| `ScannerActivity`（扫码） | activity | ✅ 已确认可用且接线（`fix_btns.dart:60-67` → `QrCodeScannerDialog`） |
| `ProfileSelectActivity` | activity | ⚪ 复用配置页的选择模式，代理页本身即覆盖（非独立缺口） |
| `StunActivity` / `NetworkFragment` | activity / fragment | ✅ `tools_page._NetworkTab` STUN |
| `SwitchActivity` | activity | ⚪ 同 `ProfileSelectActivity`（选择器） |
| `QuickToggleShortcut` / `QuickEnableShortcut` / `QuickDisableShortcut` | activity（桌面快捷方式） | 🟡 **没有完成**：`shortcuts.xml` 只有 1 个（toggle） |
| `ProxyService` / `VpnService` | service | ✅ 内核/接管机制（平台实现不同） |
| `TileService`（快捷磁贴） | service | 🟠 **硬充**：manifest 已注册 `.bg.TileService` + `TOGGLEABLE_TILE`，但 `android_quick_settings_tile.dart` **57 行全被注释** ⇒ 点了没反应 |
| `BootReceiver`（开机自启） | receiver | 🟠 **硬充**：无 receiver，靠系统 always-on（`SUPPORTS_ALWAYS_ON`）+ `autoStart` 替代 |
| `FileProvider` | provider | 🟡 机制不同（FilePicker/导出文件），能力等价 |
| `BackupFragment`（备份/恢复） | fragment | 🟡 **没有完成**：`tools_page._BackupTab` 有备份 tab（与 NekoBox 同为"网络+备份"两 tab），但只有"匿名/全部"两档，**缺"配置/规则/设置"分类勾选** |
| `WebviewFragment`（yacd 面板） | fragment | ❌ 无内嵌面板；hiddify 的 Dashboard 是自研统计（硬充） |

---

## 7. 数据库实体（规格：`database/`, `app/schemas/`）

| NekoBox 实体/表 | 作用 | hiddify 现状 |
|---|---|---|
| `ProxyEntity` + `ProxyEntity.groupId` | 节点（含全部凭据） | ✅ `ProxyEntities`（drift v7；`payload` 存完整出站 JSON 含凭据，真机已落库 84 行） |
| `ProxyGroup` | 分组（type/ungrouped/isSelector/order/userOrder） | ✅ `ProxyGroups`（drift v7；另含 front/landing 两列）。**但"手动建组"未做** —— 当前组只由订阅派生，见 `nekobox-priority.md` 批次 3 |
| `RuleEntity` | 路由规则 | ✅ hiddify 自己的规则模型 |
| `SubscriptionBean` | 订阅元数据 | ✅ `ProfileEntries` |
| `DataStore`（PublicDatabase） | 全局偏好 | ✅ shared_preferences |
| `TempDatabase` | 临时（导入流程） | ❌ 未移植（导入流程走应用内存，未用临时库） |

---

## 8. 缺口总表（已按**内核支持情况**核实，2026-09-15）

核实方法：读 `hiddify-core/v2/config/hiddify_option.go`（内核实际接受的 JSON 字段）与
`v2/hiddifyoptions/hiddify_options.proto`，逐项确认"内核是否已支持"。

### 8.1 ✅ 内核已支持、app 侧整链被注释（**最省事，仅需接线**）

| 项 | 内核证据 | app 侧现状 |
|---|---|---|
| **Bypass LAN in Core**（NekoBox `bypassLanInCore`） | `RouteOptions.BypassLAN` `json:"bypass-lan"` **在册可用**；内核确有实现 —— `v2/config/builder.go:677-695`：`BypassLAN` 为真时追加路由规则 `IPIsPrivate: true → outbound: direct` | ✅ **已接线（提交 8 项改动）**：`config_option_repository` 的选项定义 / `preferences` 映射 / 装配三处取消注释；`singbox_config_option.dart` 字段恢复；设置页「路由」卡新增 `NkSwitchRow`（复用 NekoBox 文案 `bypass_lan_in_core` = "Bypass LAN in Core" / "在核心中绕过 LAN"） |
| **TUN service 模式（`vpn-service`）** | `InboundOptions.EnableTunService` `json:"enable-tun-service"` 在册 | ⚠️ **不是 NekoBox 项** —— 核实后 NekoBox 的 `serviceMode` 取值是 `[vpn, proxy, transproxy]`（`res/values/arrays.xml`），**没有 tunService**。hiddify 的 `tunService` 是它自己的东西（且被注释）。→ 改按 NekoBox 的口径处理：**hiddify 缺的是 `transproxy`**（见 8.5） |
| **Block QUIC** | `RouteOptions.BlockQuic` `json:"block-quic"` 在册 | ⚠️ 不是 NekoBox 项（两侧都无入口），属 hiddify 侧遗漏 → 暂不做 |

### 8.5 ✅ serviceMode 已实质对齐（先前误判，已撤销）

核实过程（先资源、后代码）：

| 证据 | 结果 |
|---|---|
| `res/values/arrays.xml` `service_mode_values` | `[vpn, proxy, transproxy]` |
| `Constants.kt:15-17` | 只声明 `SERVICE_MODE` / `MODE_VPN` / `MODE_PROXY` —— **没有 transproxy 常量** |
| `bg/SagerConnection.kt:25-29` | `when (serviceMode) { MODE_PROXY -> ProxyService; MODE_VPN -> VpnService; else -> throw UnknownError() }` |
| 全仓库搜 `transproxy` | 16 个命中**全是资源文件**（arrays + 各语言 strings），**Java/Kotlin 里 0 处** |

→ NekoBox 实际只有 **2 种模式**，`transproxy` 是资源里的死项（选到会 `throw UnknownError()`）。

对照结果：

| NekoBox | hiddify | 判定 |
|---|---|---|
| `vpn`（VPN） | `tun`（"VPN"） | ✅ 对齐 |
| `proxy`（"Proxy only"） | `proxy`（"仅代理服务"） | ✅ 对齐 |
| `transproxy` | — | ⛔ **NekoBox 自己也没实现，无需补** |
| — | `systemProxy`（"设置系统代理"） | ➕ 桌面端增强，保留 |

**结论：8.5 结案，serviceMode 不用改。** （我先前据 arrays 里的死项判定"hiddify 缺 transproxy"是错的 —— 记在此以免重犯。）

---

## 8.6 8.4 移植规格：NekoBox 的实体层（**下一步的主体工作**）

> 规格取自 NekoBox 源码实测，**照抄结构，不做设计发挥**。

### 8.6.1 NekoBox 的表结构（`database/`，SagerDatabase version 6，3 张表）

**`proxy_groups`**（`database/ProxyGroup.kt`）
```
id, userOrder, ungrouped:Boolean, name, type:Int(GroupType.BASIC|SUBSCRIPTION),
subscription:SubscriptionBean?,      // 订阅详情（Kryo 序列化）
order:Int(GroupOrder.ORIGIN|BY_NAME|BY_DELAY),
isSelector:Boolean,
frontProxy:Long, landingProxy:Long   // 前置/落地代理（链式）
```

**`proxy_entities`**（`database/ProxyEntity.kt`，索引 `groupId`）
```
id, groupId, type:Int, userOrder, tx, rx, status, ping, uuid, error,
+ 每个协议一个列：socksBean / httpBean / shadowsocksBean / vmessBean / trojanBean /
  trojanGoBean / mieruBean / naiveBean / hysteriaBean / tuicBean / sshBean /
  wireGuardBean / shadowTLSBean / anyTLSBean / configBean / chainBean …
  （各 Bean 用 Kryo 序列化成二进制列）
```

**`rules`**（`database/RuleEntity.kt`）
```
id, name, config, userOrder, enabled, domains, ip, port, sourcePort,
network, source, protocol, outbound:Long(0=proxy/-1=bypass/-2=block/其他=指定的配置 id),
packages:Set<String>
```

关键机制（`fmt/ConfigBuilder.kt`，756 行）：**从 DB 读 entities/groups → 拼 sing-box 配置**；
`GroupManager.createGroup` 只在「导入订阅」与「手动新建」时调用。

### 8.6.2 映射到 hiddify（drift + 现有内核接口）

| NekoBox | hiddify 侧对应 | 说明 |
|---|---|---|
| `proxy_groups` 表 | **新增 drift 表** `ProxyGroups` | 字段照抄；`subscription` 存 JSON（hiddify 是 JSON 栈，不引入 Kryo）；`frontProxy`/`landingProxy` 改为引用 node 主键 |
| `proxy_entities` 表 | **新增 drift 表** `ProxyEntities` | 协议字段不用 15 个列，改为**一个 `payload` JSON 列**（等价于 NekoBox 的 Bean，序列化方式不同，语义相同） |
| `rules` 表 | hiddify 已有自己的规则模型（`rule_page.dart` + route rules） | 不移植，只补字段（§5 的 route 表单） |
| 订阅导入建组 | `ProfileEntries` 保留为"订阅源"，导入后**派生** group + entities | 与 NekoBox 一致：订阅 = group |
| `ConfigBuilder.kt`（DB→配置） | **需应用侧生成配置** → 内核已留口子：`Start(config_content, enable_raw_config=true)`（`v2/hcore/buildconfighelper.go:28-44`） | ⚠️ **这是 8.4 的关键决定：配置生成权从内核收回到应用** |
| 节点凭据来源 | `Parse` 返回的**完整配置文本**里含每个出站的完整定义（应用已用它实现「复制出站 JSON」） | 导入时解析落库即可拿到凭据 |

### 8.6.3 补充核实（本轮新增，两条都很关键）

**① NekoBox 的订阅导入 = 逐行解析分享链接，忽略订阅内的分组。**

| 证据 | 结果 |
|---|---|
| `ktx/Formats.kt:106 parseProxies(text)` | 按行/空格切分，逐条 `parseSOCKS` / `parseHttp` / `parseUniversal`(`sn://`) … → `AbstractBean` |
| 全代码搜 `proxy-groups` / `proxyGroups` | **0 处命中** ⇒ 订阅里的 clash proxy-group **不产生实体、不占 Tab** |
| `GroupManager.createGroup` | 只在「导入订阅」与「手动新建」时调用 ⇒ **一份订阅 = 一个 group** |

**② 由此确认"Tab 粒度"应按 NekoBox 口径：一份订阅 = 一个分组 = 一个 Tab。**
当前实现的「订阅 × 配置内分组」是 hiddify 内核能力带来的额外维度，**与 NekoBox 不一致**（见本文档 §5 `group_preferences` 与 `docs/design/connection-model.md` 第六节的"未对齐项"）。

### 8.6.4 实施进度

- ✅ **第 1 步（已完成）：凭据可落库验证**
  - 产出 `lib/features/proxy/data/proxy_entity_import.dart`：`deriveProxyGroupFromConfig()` —— 从内核 `Parse`/`generateConfig` 的**配置文本**派生「订阅分组 + 节点实体」，实体含**完整出站 JSON（凭据在内）**
  - 产出 `tool/check_entity_import.dart`：24 项断言 **ALL PASS**（实体集合排除规则、密码/UUID/TLS/uTLS/端口保留、payload 可原地拼回、四种边界 → null）
  - 排除规则照 NekoBox 口径：配置内的 selector/urltest/balancer **不成为实体**（它们由 `isSelector` 生成），`direct`/`block`/`dns` 与 `§hide§` 内部出站不算节点
- ⬜ 第 2 步（**已完成**）：drift schema v6 → v7
  - 新增 `lib/core/model/proxy_group.dart`：`ProxyGroupType{basic,subscription}`、`ProxyGroupOrder{origin,byName,byDelay}`（照 NekoBox `GroupType`/`GroupOrder`；NekoBox 用 Int 存，此处用 `textEnum`，与既有表一致）
  - `lib/core/db/db.dart`：新增 `ProxyGroups`（10 列，字段逐一对照 `database/ProxyGroup.kt`）与 `ProxyEntities`（12 列，对照 `ProxyEntity.kt`，含 `groupId` 索引 `proxy_entities_group_id`）；`schemaVersion 6 → 7` + `from6To7` 迁移（**纯新增，不动既有表**）
  - 工具链：`build.yaml` 的 drift `schema_dir` 已就位 ⇒ ① `dart run build_runner build --delete-conflicting-outputs`（生成 `db.g.dart`）② **`dart run drift_dev make-migrations`**（生成 `db.steps.dart` 的 `Schema7` + 导出 `drift_schema_v7.json` + 重生成测试 schema `schema_v7.dart`）
  - 迁移测试无需改：`migration_test.dart` 遍历 `GeneratedHelper.versions`，版本列表已自动扩为 `[1..7]`，v1→v7…v6→v7 全覆盖
  - 踩坑：drift 不允许 `autoIncrement()` 与 `@override primaryKey` 同时使用（会出警告并可能不生成 steps）—— 两处 override 已删
  - ⚠️ 本项目既有约定是「排序/设置类小状态优先 shared_preferences，别轻易动 drift schema」（HANDOVER §5）。本次动 schema 是因为**实体层无法用偏好模拟**（需要关联关系、索引、迁移能力），属 8.4 的必要前提
  - ⚠️ 本环境跑不了 `flutter test`（缺 flutter_tester），**迁移测试未在本机执行**；`analyze` 0 issue、schema 导出与 steps 生成均已验证
- ⬜ 第 3 步（**已完成**）：导入管线（订阅写入 → 派生实体落库）
  - 新增 `lib/features/proxy/data/proxy_entity_repository.dart`：`ProxyEntityRepository.syncFromProfile()` —— 内核 `generateFullConfigByPath` 取配置文本 → `deriveProxyGroupFromConfig` 派生 → **事务内**按 `profileId` 认领分组（无则建、有则更新并整组替换节点）+ 批量插入实体
  - 挂钩点：`ProfileRepositoryImpl` 的**订阅写入咽喉**（`upsertRemote` 的 insert/edit、`addLocal` 的 insert、`offlineUpdate` 的 edit 共 4 处，统一调 `_syncEntities(id)`）—— 于是新增订阅、手动添加、批量更新、撤销删除重拉、编辑内容保存**全部覆盖**，无需改动 notifier
  - 反查键：`profileId` 记在 `proxy_groups.subscription` 这段 JSON 里（**不额外动 schema**），读写函数 `encodeSubscriptionPayload`/`profileIdOfSubscription` 放在**纯 Dart** 的 `proxy_entity_import.dart`，以便脚本校验
  - **失败策略**：`syncFromProfile` 内部吞掉所有异常只记日志 ⇒ 实体派生失败**不会**让订阅导入/更新失败
  - 依赖方向：`profileRepository → proxyEntityRepository →(db / 路径解析 / 内核)`，单向不成环
  - 校验：`tool/check_entity_import.dart` 扩到 **34 项断言 ALL PASS**（含反查键的 10 项边界）；`flutter analyze` 0 issue、release 构建通过
  - ⚠️ 未验证：DB 写入路径需真机运行才能观察（本环境无 flutter_tester，且沙箱不能常驻 GUI）
- ✅ 第 4 步（**已完成**）：出站表归应用 —— 见 §8.6.8（**含对 4a 前提的推翻与重做**）
  - 4a 重写：`lib/features/proxy/data/config_assembly.dart` 的 `applyEntitiesToOutbounds()`
    - 基准 = **应用写下的 `configs/<id>.json`**（`{"outbounds":[…]}`，也就是内核读的那份输入）
    - 规则只有三条：实体覆盖同名节点出站（含凭据）、基准里没有的实体追加、`staleTags` 里的移除
    - **不再重建组、不再设 default、不再识别"主 selector"** —— 内核每次都会丢弃输入里的组并自建（见 §8.6.8）
    - 校验 `tool/check_config_assembly.dart`：**24 项断言 ALL PASS**，核心是"只动节点、组一律原样透传"
  - 4b：`ProxyEntityRepository.assembleOutboundsForProfile(profileId)` → 写 `configs/<id>.entities.json` → `ConnectionRepository._start()` 优先用它启动
    - **失败回落**：组装失败 / 文件缺失 / 启动失败 → 一律回落到订阅基准文件（就是改动前的行为，不会更差）
    - **未用 `enable_raw_config`** —— 理由见 §8.6.8；那条路会丢掉内核从 HiddifyOptions 生成的 inbounds/dns/route/log
  - 4c（映射，本轮）：新增 `runtime_outbound_tags.dart`（内核 tag 常量的 Dart 镜像）+ `live_proxy_join.dart`（按**节点 tag** 贴实时值），修掉三处"拿订阅组名去对内核说话"的实质错误（切节点 / 测整组 / 仪表盘活跃出站）。见 §8.6.8.1
  - 4d（选中持久化，本轮）：新增 `selected_proxy_store.dart` + `selection_reconcile.dart`（纯函数决策，15 项断言），校准挂在 `ActiveProxyNotifier`（对应 NekoBox 的 `BaseService.reload()`）。见 §8.6.8.2
  - 4e（节点行写路径，本轮）：实体层写接口 + **列表以实体为准**（配置文本回落）+ 节点行 🗑（带撤销）/ ⤴ 改为实体优先。**✎ 编辑仍缺**（要协议表单）。见 §8.6.13
- ⬜ 第 5 步：14 份协议表单（约 150 字段）← **下一步的主体工作**（✎ 编辑按钮要等它）

### 8.6.5 与 NekoBox 的差异清单（实体层）

| 维度 | NekoBox | 本项目（8.4 目标） |
|---|---|---|
| 节点来源 | 逐行解析分享链接 → Bean | 从内核 `Parse` 的配置文本派生（复用既有链路，免造链接解析器） |
| Bean 序列化 | Kryo 二进制列（每协议一列） | 单个 `payload` JSON 列（语义等价，栈一致） |
| 分组来源 | 订阅（1 个 group）+ 手动新建 | 同左（**不再**把配置内 proxy-group 当 Tab） |
| 配置生成 | `ConfigBuilder.kt` 从 DB 拼**整份**配置 | 只接管**出站表那一段**（`{"outbounds":[…]}`），其余（inbounds/dns/route/log/experimental）由内核从 HiddifyOptions 生成 —— 见 §8.6.8 |
| 规则 | `rules` 表 | 沿用 hiddify 既有规则模型（只补字段） |

### 8.6.7 NekoBox `ConfigBuilder.kt` 实测对照（"再次对照"的结果）

按用户要求重读源码逐项核对（行号为 `fmt/ConfigBuilder.kt`）：

| 维度 | NekoBox（源码位置） | 我的 4a | 判定 |
|---|---|---|---|
| 构建粒度 | `buildConfig(proxy, forTest, forExport)`（:62）—— **以单个选中节点为入口** | 全量实体 + 覆盖 | 差异（下同） |
| **selector 组是否含全部节点** | **含**：`buildSelector = !forTest && group?.isSelector == true && !forExport`（:131）；为真时 `proxyDao.getByGroup(group.id)` 取**该组全部节点**逐个 `buildChain`，再 `outbounds.add(0, Selector{tag: TAG_PROXY, default: 选中节点, outbounds: 全部成员})`（:463-473） | 含全部实体 | ✅ **思路一致** |
| 非 selector 组 | 只编选中节点：`buildChain(0, proxy)`（:475） | 不分情况一律全量 | 差异 —— hiddify 内核一次只加载一份 profile，必须全量才能在运行期切换 |
| selector tag | 固定常量 `TAG_PROXY = "proxy"`（:44） | 沿用基准（订阅组名「节点选择」或 profile 名「冲上云霄」） | 差异 —— 我**不重命名**是为了保住 `route.final`、`dns.servers[].detour` 的引用（NekoBox 的配置**没有** `route.final`） |
| 成员 tag | 节点显示名（`tagOut = selectorName(bean.displayName())`，:297） | 配置里的 tag | 差异（hiddify 的 tag 通常等于显示名） |
| urltest / balancer | **没有**（自己测速：`TestInstance` → `buildConfig(profile, true)`，`bg/proto/TestInstance.kt:43-44`） | 保留内核 urltest | hiddify 特有 |
| direct / bypass 出站 | `arrayOf(TAG_DIRECT, TAG_BYPASS)` 追加（:611） | 沿用基准（`direct §hide§` 等） | ✅ 一致 |
| `route.final` | **不设置**（靠 rules 的 outbound 指定） | 保留基准的 final → 主 selector | hiddify 特有 |
| 原始配置透传 | `ConfigBean.type == 0` 直接返回 `bean.config`（:64-75） | — | 对应内核的 `enable_raw_config` |

**两条纠正（我先前说错/做错的地方）**：

1. **4a 提交信息里"NekoBox 从 DB 白手起家拼整份配置"不完整**：它对**selector 组**是把该组**全部节点**都编进配置、并加一个 selector（tag 固定为 `proxy`）—— 与 hiddify 的 selector 思路一致；只有非 selector 组才只编选中节点。已更正。
2. **删除规则改了**：原先实现按"看起来像节点"（非组/非内部/不带 `§hide§`）推断删除 —— 这属自我发挥，且有真风险：内核会加 `🔒 WARP` 这类出站（实测确认既不是组也不是内部类型、也不带 `§hide§`），会被误删。现在**删什么只由调用方给 `staleTags`**：事实归属上，"哪些 tag 属于实体层"由实体层说了算（`ProxyEntityRepository` 在整组替换前知道旧实体集合）。校验脚本已加"`🔒 WARP` 必须保留"与"不传 staleTags 就不删"两条用例。

**结论**：4a **不是** NekoBox 的做法，而是 **hiddify 语义下的"内核基准 + 出站层覆盖"**（内核一次只加载一份 profile、且配置含 `route.final` / dns detour 等 NekoBox 没有的结构）。取舍理由与差异已逐条记档，不再以"NekoBox 就这么做"表述。

### 8.6.8 实测推翻 4a 前提：**组由内核重建，应用只该管节点那一段**

本轮把"内核真正在跑的那份配置"读出来对照（`%APPDATA%\Hiddify\hiddify\data\current-config.json`），结果推翻了 4a 的前提。

**两份文件必须分清**（这是先前搞错的地方）：

| 文件 | 谁写 | 内容 |
|---|---|---|
| `configs/<id>.json` | 应用写、内核**读作输入** | **只有 `{"outbounds":[…]}`** —— 订阅自带的组（selector「冲上云霄」+ urltest「自动选择」）+ 节点 |
| `data/current-config.json` | 内核启动时写 | **真正在跑的**：`outbounds` 的组是 `select` / `balance` / `lowest`（固定常量），`route.final = "select"`，另有 `inbounds`（`mixed-in` / `dns-in`）、`dns`、`log`、`experimental` |

**内核 `v2/config/builder.go` 的 `setOutbounds`（:130-371）自己重建组**：

1. 丢弃输入里的**所有组**（selector/urltest/balancer，:154-164）、丢弃 `direct`/`bypass`/`block` 与预定义 tag（:142、:169），**只留下节点**（:178-183 顺带收集非 `§hide§` 的 tag）
2. 自建 `balance`（strategy = `opt.BalancerStrategy`，:295-310）与 `lowest`（`lowest-delay`，:278-293）
3. 自建 selector，tag = **常量** `OutboundSelectTag = "select"`，members = `[balance, lowest, …节点]`，default = `balance`（:311-341）
4. `setRoutingOptions` 再把 `route.final` 设成同一个常量

源码里甚至留着一段注释（:157-164）写明这件事：*"the app generates a config and then starts the core from that generated file, so the builder runs twice"*。

**因此 4a 那三条"硬规则"全部作废**（它们是从 `configs/<id>.tmp.json`＝**订阅原文**反推的，而那不是被启动的文件）：

| 4a 的说法 | 实测 |
|---|---|
| "主 selector 的 tag 可变（订阅组名 / profile 名），按第一个 selector 识别" | 运行期 selector tag 恒为 `select` |
| "`route.final` 与 dns detour 指向主 selector 的 tag，所以不能重命名" | 运行期 `route.final = "select"`，由内核设置 |
| "重建成员：selector = [其它组, 非节点, 节点]" | 内核自己重建为 `[balance, lowest, …节点]` |

⇒ **已删除** `config_assembly.dart` 里识别主 selector / 重建成员 / 设 default 的全部逻辑。应用负责的只有**节点出站那一段**，这恰好也是"节点可编辑"所需的最小权限。

**为什么不用 `enable_raw_config`**（先前 4b 的计划）：

- `StartRequest{config_content, enable_raw_config: true}` → `BuildConfig`（`buildconfighelper.go:28-44`）走 `ReadSingOptions`，**原样读取、跳过 builder**
- 于是 `setInbound` / `setDns` / `setRoutingOptions` / `setExperimental` / `setLog` **一次都不会执行** ⇒ 配置里没有 inbounds / dns / route / log，内核即使起得来也毫无意义（没有入站端口、没有 DNS、没有路由策略）
- 而应用也**拿不到"构建后的完整配置"来当基准**：`GenerateConfig` 那条 RPC 在 proto 里是**注释掉的**（`hcore_service.proto`：`//rpc GenerateConfig (GenerateConfigRequest) returns (GenerateConfigResponse);`）—— Go 侧有实现（`buildconfighelper.go:145`），但没挂在服务上，Dart 存根里也没有
- ⇒ 正确机制是**把出站表喂给内核、按路径启动**，其余部分仍由内核按 HiddifyOptions 构建。这也正是内核注释里描述的那条既有链路（"app generates a config and then starts the core from that generated file"）

**落地**：

- `ProfilePathResolver.entityFile(id)` → `configs/<id>.entities.json`
- `ProxyEntityRepository.assembleOutboundsForProfile(profileId)`：读盘取订阅基准 → 实体覆盖节点段；**只记日志、绝不抛出**
- `ConnectionRepository._start()`：优先用实体文件启动，组装修建失败 / 文件缺失 / 启动失败 → 回落订阅基准文件（即改动前行为）
- 回落之所以安全：内核组装或启动失败都会走 `errorWrapper → StopAndAlert → SetCoreStatus(STOPPED)`（`hcore/custom.go`），状态被复位，第二次 `start` 不会被判成 `ALREADY_STARTED`
- 订阅基准 `<id>.json` **保持不变**，随时可对照、可回退

#### 8.6.8.1 「映射」怎么解决（本轮，已实施）

上一节结尾的遗留是"组这一层 tag 对不上"。**NekoBox 的答案是：映射不靠 tag 相等，靠构建期建立的绑定。**

它的实现（源码位置）：

| NekoBox | 作用 |
|---|---|
| `ConfigBuilder.kt:44` `TAG_PROXY = "proxy"` | 运行期 selector 的 tag 是**常量** |
| `ConfigBuildResult.profileTagMap`（`Map<实体id, 配置tag>`） | **构建期**产出，随配置一起携带 |
| `BaseService.kt:185-190` `data.proxy!!.config.profileTagMap[ent?.id]` → `box.selectOutbound(tag)` | 运行期把选中实体翻译成 tag 再下发 |
| `DataStore.kt:36` `var selectedProxy by configurationStore.long(Key.PROFILE_ID)` | 选中项是**一条偏好**（实体 id） |
| `bg/proto/TrafficLooper.kt` `idMap`/`tagMap` 双索引，广播 `TrafficData(id = ent.id, …)` | 每节点实时值按实体 id 送 UI |
| `ConfigurationFragment` 的列表来自 `proxyDao.getByGroup` | 列表内容/顺序/显示名来自 DB |

**照此落到本项目**（`lib/features/proxy/data/runtime_outbound_tags.dart`）：

- 内核 tag 常量的 Dart 镜像：`select` / `lowest` / `balance` / `direct §hide§` / `direct-fragment §hide§` / `dns-out §hide§` / `🔒 WARP`（依据 `builder.go:37-43`）。**沿用内核自己的常量，不另造名字。**
- 由此修掉三处"拿订阅组名去对内核说话"的实质错误：

| 位置 | 原来 | 为什么错（源码依据） | 现在 |
|---|---|---|---|
| `proxies_overview_notifier.changeProxy` | 下发 `SelectOutbound(groupTag: 订阅组名)` | `commands.go` 的 `SelectOutbound` 是 `box.Outbound().Outbound(in.GroupTag)`，找不到就返回 `selector not found: <订阅组名>` —— 这就是"点了没反应" | 下发常量 `select` |
| `proxies_overview_notifier.urlTest` | `UrlTest(tag: 订阅组名)` | `commands.go` 的 `UrlTest` 在 `in.Tag == ""` 时才走 `UrlTestActive()`（内部用常量 `select`）；否则 `monitor.TestNow(组名)` —— 测一个不存在的出站 | `UrlTest(tag: "")` |
| `active_proxy_notifier.build` | `groups.first.items.first` | 内核第一组是 `select`，其第一个成员是 `balance`（balancer，不是节点）—— 仪表盘显示的是一行组名 | 取 `select` 组的 **`selected` 那个条目** |

- 取数分工照 NekoBox：`lib/features/proxy/data/live_proxy_join.dart` 的 `joinLiveIntoGroup()`
  - **列表内容 / 顺序 / tag** ← 骨架（订阅 / 实体清单）
  - **每节点延迟 / 测速时间 / 上下行 / 端口 / 主机 / IP / TLS** ← 内核，**按节点 tag** 逐个贴
  - **选中** ← 内核 `select` 组的 `selected`
  - **组 tag 不参与匹配**（这正是 Phase 1 "按组 tag 取那一组"的病根：组 tag 永远对不上，于是每次都落到 `liveGroups.first` = `select`，把内核那张并把 `balance`/`lowest` 都算进来的并集表当成了用户的组）
  - 校验：`tool/check_live_proxy_join.dart` **21 项断言 ALL PASS**（列表以骨架为准、组 tag 不参与、内核没给的节点保留骨架值、`isGroup` 的 live 条目不被当节点、退化路径等）

**与 Phase 1 的关系（如实说明）**：Phase 1 删掉了 `_mergeLive`，理由是"内核已经给全量组，不需要缝"。这个判断只在那两份数据**是同一个东西**时成立；而内核的组是重建出来的并集表，与订阅分组不是一回事。所以按 NekoBox 的分工把"按节点 tag 贴实时值"补了回来 —— 这不是回到旧的"双源缝合"，因为**匹配键换成了节点 tag（两侧天然一致），组 tag 完全不参与**。

#### 8.6.8.2 选中的持久化与校准（本轮，已实施）

上一节的"遗留"里还剩一条：**选中是"应用一次就清空"的临时值**。NekoBox 不是这样：

| NekoBox | 位置 | 作用 |
|---|---|---|
| `var selectedProxy by configurationStore.long(Key.PROFILE_ID)` | `DataStore.kt:36` | 选中是**持久偏好**（实体 id） |
| `DataStore.selectedProxy = proxyEntity.id` → `SagerNet.reloadService()` | `ConfigurationFragment.kt:1504-1517` | 用户点节点：**先落盘、再通知服务**，从不清空 |
| `box.selectOutbound(tag)`（同组时）/ start·stop（换组时） | `BaseService.kt:180-212` `reload()` + `canReloadSelector()` | 由**服务侧**应用，不在 UI 层 |
| `default_ = tagMap[proxy.id]` | `ConfigBuilder.kt:471` | 选中项在**构建期**写成 selector 的 `default` ⇒ 重启后自然还在 |
| `selector_OnProxySelected` → `cbSelectorUpdate(id)` → 回写 `DataStore.selectedProxy` | `NativeInterface.kt:84-105`、`MainActivity.kt:416-423` | 外部（yacd/webui）改选时**采纳并回写** |

**hiddify 的差异**：内核把 selector 的 `default` **写死成 `balance`**（`builder.go:311-341`），应用拿不到构建期那个口子（否则就要走 `enable_raw_config`，而那会丢掉内核生成的 inbounds/dns/route，见 §8.6.8）。⇒ 选中的"恢复"只能在**每次内核 ready 之后**补一次 `selectOutbound`。

**落地**：

- `lib/features/proxy/data/selected_proxy_store.dart`：持久存储「期望选中的节点」+「它属于哪份订阅」（对应上述两条 NekoBox 偏好；键名沿用历史，语义改为持久值）
- `lib/features/proxy/data/selection_reconcile.dart`：纯函数 `decideSelectionReconcile()`，判断顺序即优先级
  1. 没有期望值 → 不动（内核默认即当前事实）
  2. 期望值属于别的订阅 → 等待（内核一次只加载一份配置）
  3. 与内核当前选中一致 → 不动（**幂等**，所以每次事件都跑也不会重复下发）
  4. 内核节点集合里没有这个 tag → 等待（不硬下发，避免对不存在的 tag 反复重试）
  5. 内核停在它自己的默认值（`balance` / `lowest` = 没人选过）→ **下发期望值**
  6. 否则（内核选中是个具体节点）→ **采纳并回写**（对应上面的 `selector_OnProxySelected`）
- `ActiveProxyNotifier`：校准挂在这里 —— 它是 `keepAlive` 且被 `bootstrap.dart:104` eager listen，内核一起来就被驱动，**等价于 NekoBox 把这件事放在服务里做**
- `ProxiesOverviewNotifier.changeProxy`：改为"点节点 = 落盘持久期望值 + 立刻下发"；删掉了 `pending_proxy_group`（组恒为常量 `select`）与"应用后清空"的逻辑

**顺带修掉**：旧的"写 pending → 等内核事件 → 应用并清空"在跨订阅时会吃到旧内核的事件（旧内核还在推事件时组名碰巧存在就静默生效）。现在期望值不再被清空，归属校验一律以期望值为准，那个窗口期竞态自然消失。

**校验**：`tool/check_selection_reconcile.dart` **15 项断言 ALL PASS**（覆盖六个分叉与优先级顺序，含"期望值不在内核配置里时即使内核停在默认值也不许下发"）。

### 8.6.9 应用启动即崩溃：内核注册表不可重入（已修）

**现象**：新构建的 App 启动后进程直接消失。`%APPDATA%\Hiddify\hiddify\crash_reports\2026-09-15T05-37-06` 与 `...T05-37-20` 两份 dump（只有这两份，都在本次构建之后 ⇒ 是新引入的）。

**根因（在核心里，不在 Dart）**：

```
internal/runtime/maps.fatal                        ← Go 运行时「并发写 map」，进程直接 abort，不可恢复
 → sing-box/protocol/hiddify/dnstt.loadResolvers()      tools.go:22-28
 → dnstt.RegisterOutbound → include.OutboundRegistry()  registry.go:116
 → libbox.baseContextWithParent / baseContext
 → libbox.CheckConfigOptions
```

`hiddify-core/hiddify-sing-box/protocol/hiddify/dnstt/tools.go`：

```go
var (
	countryResolvers map[string][]string   // 包级
	resolverCountry  map[string]string     // 包级
)

func loadResolvers() {                     // ← 无任何同步
	json.Unmarshal(resolvers_bytes, &countryResolvers)
	resolverCountry = make(map[string]string)
	for country, resolvers := range countryResolvers {
		for _, resolver := range resolvers {
			resolverCountry[resolver] = country   // tools.go:26
		}
	}
}
```

而 `dnstt/outbound.go:26-29` 的 `RegisterOutbound` **每次注册都调它一遍**（不是 `sync.Once`）：

```go
func RegisterOutbound(registry *outbound.Registry) {
	outbound.Register[option.DnsttOptions](registry, C.TypeDNSTT, NewOutbound)
	loadResolvers()   // ← 每次重建 registry 都重写这两个包级 map
}
```

⇒ **任何两个并发地"重建注册表"的调用都会让进程 abort。** 这份数据是 `//go:embed` 的只读资源，重写纯属多余。

**证据（不是推断）**：两份 dump 里各有**恰好 2 个** goroutine 停在 `loadResolvers`，一个来自 `Parse`（`v2/config/parser.go:153` 的 `validateResult` → `CheckConfigOptions`），一个来自 `Start`（`v2/hcore/service.go:31` 的 `NewService`，以及 `start.go:131` 的 `libbox.FromContext`）。Dart 侧 `app.log` 的时间线也对上：`13:37:34.945 ConnectionNotifier: starting core in the background` 与 `13:37:35.039 offline proxies: ...` 重叠。

**会走到这条路的 RPC（全库枚举）**：`Parse` / `Start` / `StartService` / `Restart`（`v2/hcore/restart.go:40` 的 Restart 内部就是 StartService）。`Stop` / `SelectOutbound` / `UrlTest` / `ChangeHiddifySettings` / `OutboundsInfo` 不进这条路。

#### 已实施：应用侧串行化（本层能做的根因修复）

- `lib/core/utils/serial_async_lock.dart`：`SerialAsyncLock` —— 性质是**不重叠 / 保序（FIFO）/ 一次失败不破坏锁**
  （第三条最易漏：把失败的 Future 当链尾会让后续任务永久排队，表现为功能无声卡死，比崩溃更难查）
- `lib/hiddifycore/hiddify_core_service.dart`：`validateConfigByPath`（Parse）、`generateFullConfigByPath`（Parse）、
  `start`（Start）、`restart`（Restart）四处的 RPC 全部经 `_serializeRegistryAccess()` 串行化
- 为什么落在应用侧是正当的：内核这几条路径**不可重入**，而应用是唯一客户端；这与既有代码已经
  手工排序 `stop → 等 1.5s → start` 是同一个道理的延伸
- 校验：`tool/check_async_lock.dart` **8 项断言 ALL PASS**（含"连败三次后仍可用"与"同步抛出后仍继续"）

#### 上游修法（一行，未实施）

```go
var loadResolversOnce sync.Once

func loadResolvers() {
	loadResolversOnce.Do(func() { /* 原来的函数体 */ })
}
```

数据是 embed 的只读资源，`sync.Once` 既消除竞态也省掉每次注册的重复解析。
实施需要重建 `hiddify-core.dll`（本项目已有通路：`LOCAL_CORE=1 make windows-libs-local`，
见 `Makefile:805-841`，会用 Go + mingw 从源码构建）。**这是改 vendored 第三方源码 + 重产出 64MB 二进制，
属需要拍板的动作，故本轮只落应用侧修复并记录在此。**

> 注意 `EnableDNSRouting` 在**内核侧也被注释**（`hiddify_option.go` 的 `DNSOptions` 里是 `// EnableDNSRouting ...`），
> 所以「Enable DNS Routing」不是接线问题，**属 C 组**。我先前把它归入 A 组是错的。

### 8.6.10 「连接了但没流量」：系统代理链路上有两个断点（已修）

**现象**：点「连接」→ 界面显示已连接，但流量恒为 0、外网没走代理。

**Windows 侧实测**（python 读注册表）：`ProxyEnable = 0`（系统代理**未启用**），而 `ProxyServer = http://127.0.0.1:12334` 已经写好 —— 说明**这条链路曾经成功过**（值就是 sing-box 写的），只是要点亮的开关没人点亮。

#### 断点 1（内核侧，上游缺口）：命令服务器从不启动

- `v2/hcore/system_proxy.go:41-42` 的 `SetSystemProxyEnabled` 走 `libbox.NewStandaloneCommandClient()`，
  它去连 `<workingDir>/command.sock`（`command_client.go:125-126`）
- 那个 socket 由 `libbox.CommandServer.Start()` 创建（`command_server.go:119`），
  而**唯一那句调用在内核里被注释掉了**：`v2/hcore/service.go:48-50`
  ```go
  // if err := startCommandServer(instance); err != nil {
  // 	return errorWrapper(MessageType_START_COMMAND_SERVER, err)
  // }
  ```
  且 `startCommandServer` 这个函数在全库**已不存在**（只剩这行注释）
- ⇒ 该 RPC 必然失败：`dial unix …\hiddify\command.sock: connect: No connection could be made…`（实测 13:49:07 / 13:50:36）
- 注：`EnableOldCommandServer: true` 只在 FFI 导出 `start`/`restart`（`platform/desktop/custom.go:115`、`:137`）里传，
  Dart 侧走 gRPC、**不用这两个导出** ⇒ 这条口子对应用是无效的

#### 断点 2（应用侧，**这是"没流量"的直接原因**）：`rethrow` 让兜底永不执行

`ConnectionNotifier.setCapture`（`connection_notifier.dart:206-223`）本来有**正确**的兜底：

```
运行时 RPC 成功 → 结束
运行时 RPC 失败 → 重启内核，让 sing-box 自己设系统代理
                （common/listener/listener.go:109-117 → common/settings/proxy_windows.go:28 的 wininet.SetSystemProxy）
```

但 `HiddifyCoreService.setSystemProxyEnabled` 的 catch 里写的是 `rethrow`。
**`TaskEither` 体内抛出会变成"被拒绝的 Future"而不是 `Left`** ⇒ 调用方的 `applied.isRight()`
那一行**根本执行不到** ⇒ 兜底不触发，异常还逃到平台层（日志里的 `app: PlatformDispatcherError`）。

同类隐患共 4 处（都在 `hiddify_core_service.dart`）：`changeOptions` / `setSystemProxyEnabled` /
`selectOutbound` / `urlTest`。**要么返回 `Left`，要么整个 Either 契约对调用方失效。**

#### 修复

1. 这 4 处一律改为 `return left(...)` —— 恢复 Either 契约
2. `setSystemProxyEnabled` 超时 10s → **3s**：既然在这份内核上注定失败，
   不该让用户每次点「连接」都干等 10 秒。将来内核若恢复命令服务器，这条路会自动重新可用
3. 修复后的链路：点「连接」→ 写 `captureEnabled = true` → 运行时 RPC 失败（3s）→
   **兜底重启内核** → 配置里 `set-system-proxy: true`（`config_option_repository.dart:506`，
   `mode == systemProxy && captureEnabled`）→ sing-box 的 mixed 入站安装系统代理 ⇒ 流量走起来

**校验**：`flutter analyze` 0 issue；五个校验脚本全 PASS；windows release 构建通过。

**未验证**：真机确认「连接后 `ProxyEnable = 1` 且流量开始计数」需要你跑一次（沙箱不能常驻 GUI）。

### 8.6.11 实体回填：让第 3/4 步真正跑起来（已实施）

**为什么需要**：真机 DB 实测（`%APPDATA%\Hiddify\hiddify\db.sqlite`）——
`proxy_groups` **0 行**、`proxy_entities` **0 行**。原因是实体落库挂在「订阅写入」这条咽喉上，
而两份订阅都是在实体表出现**之前**导入的。于是第 3/4 步的代码从未被走过：
`configs/` 下没有 `.entities.json`，组装每次都回落到订阅基准（回落本身是对的，但等于实体层是死的）。

**回填判据**：库里已有该订阅的分组就跳过 —— 纯函数 `missingEntityProfileIds()`
（`proxy_entity_import.dart`，含 8 项断言）。幂等 ⇒ 第二次运行只是一次 DB 读。
对应 NekoBox 的 `GroupManager`「有组就不重建」。

**触发点**：新增 `lib/features/proxy/entity/entity_backfill_notifier.dart`（`@Riverpod(keepAlive)`），
订阅清单一变就检查一遍；在 `bootstrap.dart` 与 `activeProxyNotifierProvider` 并排 eager listen，
位于内核 init **之后**；fire-and-forget，不挡启动。

**顺带把配置文本的来源改对了**（`ProxyEntityRepository._sourceConfigTextFor`）：
优先**直接读** `configs/<id>.json`，而不是调内核 `Parse`。三条理由：

1. 那个文件本身就是 `Parse` 的产物（导入/更新时 `validateConfig()` 让内核把解析结果写在这里），内容等价；
2. **不需要内核在跑** ⇒ 回填才能安全地放在启动路径上（`Parse` 走内核里那段不可重入的注册表，见 §8.6.9）；
3. 真机实测**幂等**（见下表）——没有编辑时，从 `.entities.json` 启动与从订阅基准启动完全等价。

**真机数据验证**（本轮：把第 1~4 步的纯函数跑在**真实配置**上，而非仿写 fixture）：

| 订阅 | 实体数 | 类型分布 | 组装幂等（实体覆盖回基准） |
|---|---|---|---|
| 一分机场 `0a34c1c6` | 36 | hysteria2×15, vless×21 | ✅ **逐字节相同** |
| 云霄 `e2d4f850` | 48 | anytls×41, hysteria2×5, shadowsocks×2 | ✅ **逐字节相同** |

与离线解析日志 `[一分机场] 2 groups (节点选择:37, 自动选择:36)` 吻合：
selector 成员 = `[自动选择] + 36 个节点` ⇒ 实体 36 个。

**验收（已自测通过，2026-09-15，见 §8.6.15）**：

- `db.sqlite`：`proxy_groups` **2 行**、`proxy_entities` **84 行**（云霄 48 + 一分机场 36）✅
- 启动激活订阅后 `configs/<activeId>.entities.json` **已生成** ✅
- `app.log`：`entity assembly: [e2d4f850…] ConfigAssemblyResult(replaced=48, added=0, removed=0)` ✅
- 第二次启动**不再回填**（幂等，日志无 `entity backfill`）✅

**与 NekoBox 的对应**：NekoBox 的 `GroupUpdater`/`GroupManager` 在订阅更新时维护分组+节点；
本项目除了那条路径，还需要对"表出现之前就已存在的数据"补一次 ——
这是新表对既有数据的**一次性迁移**，此后完全由导入/更新驱动。

### 8.6.12 分组模型对齐：**一份订阅 = 一个分组**（已实施，Tab 粒度定案）

**用户指出的问题**：代理页凭空有一栏「自动选择」。对照 NekoBox 核实 —— **它没有这个东西**。

**NekoBox 的三条证据**：

| 证据 | 内容 |
|---|---|
| `Constants.kt` | `object GroupType { BASIC = 0; SUBSCRIPTION = 1 }` —— 组类型**只有这两种**，没有"自动选择/urltest" |
| `group/RawUpdater.kt:768-787` | 订阅是 sing-box 配置（`json.has("outbounds")`）时，把 `dns` / `block` / `direct` / `selector` / `urltest` **逐个过滤掉**，只留真节点 ⇒ 一份订阅产出**一个** group |
| `database/ProxyGroup.kt` `displayName()` | 组名就是**订阅名**（`name` 为空才用默认名） |

全仓搜 `urltest` 只有两种用途：`RawUpdater` 的**过滤名单**，以及 `SingBoxOptions` / `UrlTestPreference`
（用户手动建 url-test **出站**时用）。**没有任何地方把 urltest 当成"分组"。**

**改动**：

- `offline_proxy_parser.dart`：`parseOfflineProxyGroups()`（把配置里的 selector/urltest/balancer 当分组）
  → **`parseSubscriptionGroup(configJson, groupName:)`**：返回**唯一**一个组，`tag` = 订阅名，
  `items` = 过滤后的全部节点（顺序照配置）。**选中不由配置决定** —— 配置里的 `default` 不是选中，
  选中是 `SelectedProxyStore` 的持久偏好。
- `offline_proxies.dart`：`ProfileProxies{profile, groups, fallback}` → `{profile, group}`（`fallback` 概念消失）。
- 代理页：Tab = 订阅，标签就是订阅名（不再拼组名），`_tabLabel` 删除。
- `proxies_overview_notifier`：认订阅 id 即可（不再按组 tag 找组）；`urlTest(groupTag)` → **`urlTest()`**
  （NekoBox 没有"按组测速"，测速是工具栏的 URL Test）；新增 `_withExpectedSelection()`。
- 清理：`tool/offline_parse_check.dart` 与 `tool/check_offline_proxy_parser.dart` 是同一件事的两份脚本，
  合并成后者；`hiddenTag` 改为委托 `isHiddenTag`（同一条 `§hide§` 规则原来写了两遍）。

**真机数据验证**（新解析器跑在真实 `configs/<id>.json` 上）：

| 订阅 | 节点数 | 类型分布 |
|---|---|---|
| 一分机场 `0a34c1c6` | 36 | hysteria2×15, vless×21 |
| 云霄 `e2d4f850` | 48 | anytls×41, hysteria2×5, shadowsocks×2 |

与实体派生（§8.6.11）**完全一致**，且两个配置内分组（`节点选择` / `自动选择`）都已被正确过滤掉。

**一个必须说明的取舍**：`_withExpectedSelection()` 会把**持久化的期望选中**贴到列表上。
理由：内核那个 selector 的 `default` 被写死成 `balance`（`builder.go:311-341`），在它校准过来之前，
内核报的选中项（`balance`）**不是列表里的任何节点** —— 直接照抄就会整列没有高亮，看起来像"选中的节点丢了"。
规则是**只在"内核没给出可用选中"时兜底**：期望值属于别的订阅 ⇒ 不贴；不在本清单里 ⇒ 不贴。

**验收（已自测通过，2026-09-15，见 §8.6.15）**：

- 代理页 Tab 只有**订阅名**（「云霄」「一分机场」），**不再出现「自动选择」** ✅（截图为证）
- 每个订阅列出的节点数 = 它的全部节点：云霄 48 / 一分机场 36 ✅
- 每个订阅的列表都标注来源：`(from entities)` ✅

### 8.6.13 节点行三件套 + 「列表以实体为准」（已实施）

**规格（NekoBox，本轮读源码取）**：

| 证据 | 内容 |
|---|---|
| `res/layout/layout_profile.xml` | 行 1 右侧依次 `@id/edit`（✎）→ `@id/share`（⤴）→ `@id/remove`（🗑） |
| `ui/ConfigurationFragment.kt:1594-1600` | ✎ → `proxyEntity.settingIntent(ctx, isSubscription)` → 该协议的 `*SettingsActivity` |
| `:1602-1608` | 🗑 → `adapter.remove(index)` + `undoManager.remove(index to proxyEntity)` |
| `:1612-1613` | `editButton.isGone = select` / `removeButton.isGone = select` —— **只在"选择器模式"下隐藏**（Chain 端点选择等）；正常浏览时两个按钮都显示 |
| `:1624-1625` | `isEnabled = !started`，`started = selected && serviceState.started && currentProfile == entity.id` ⇒ **正在使用的那个节点不允许编辑/删除** |
| `widget/UndoSnackbarManager.kt` | 删除后弹 Snackbar「已删除 %d 个配置」+ **Undo**；点 Undo → 恢复；Snackbar 关闭（非 ACTION）→ `commit` 落库；新操作到来 → `flush()` |

**⚠️ 口径纠正**：`proxy_tile.dart` 原先写着"🗑 与 NekoBox 一致默认隐藏（订阅节点的增删走订阅更新）"——
**这条是错的**。XML 里 `@id/remove` 确实默认 `visibility=gone`，但 `bind()` 每次都会按 `select` 覆写
（正常模式 `select == false` ⇒ 显示）。所以 NekoBox 的节点行**默认就有删除按钮**，订阅节点也能删。

**本轮落地**：

- 实体层写接口（`ProxyEntityRepository`）：`groupForProfile()`（= `proxyDao.getByGroup`）、
  `removeNode()`（= `removeButton`）、`restoreNode()`（= undo）、`payloadOfNode()`（分享数据源）。
- **列表以实体为准**：`offlineAllProfilesProxyGroupsProvider` 改为先读实体表
  （`buildGroupFromEntityNodes`，组名 = 订阅名、顺序照 `userOrder`）；没有实体分组时回落到
  "解析配置文本"这条老路 ⇒ 行为与引入实体层前一致，最坏情况只是看不见新能力，不会让页面空掉。
  **节点级删除/编辑因此立刻可见**，不必等下一轮订阅解析。
- 节点行：按 NekoBox 顺序补上 🗑（**✎ 仍未做** —— 它要的是协议表单，见 §5）；
  `NkCardAction.onTap` 支持 `null` = 禁用（置灰不响应），照 `isEnabled = !started`。
- 删除 + 撤销：Material `SnackBar` + `SnackBarAction(撤销)`。
  差异说明：NekoBox 是"延迟落库 + 撤销"，这里是"立即落库 + 撤销时重新插入" ——
  用户可见行为一致，且少了"离开页面时漏提交"的风险。
- 分享改为**实体优先**、配置回落（列表以实体为准后，从配置里找 tag 会漏掉新节点或给出旧内容）。

**校验**：`tool/check_offline_proxy_parser.dart` 扩到 **36 项断言 ALL PASS**，新增 11 项覆盖
"实体来源 → 分组"（组名 = 订阅名、顺序照 `userOrder`、显示名用库里那一列、不预置选中、空清单→空组）
以及**两个来源必须产出同一形状**（否则"回落"会换掉列表长相）。六个校验脚本全 PASS；
`flutter analyze` 0 issue；release 构建通过。

**验收（已自测通过，2026-09-15，见 §8.6.14）**：

- 节点行右侧出现 🗑（悬停显示 tooltip「删除」）；正是"正在使用"的那个节点上是灰的
- 点 🗑 → 列表**立刻**少一项，底部弹出「已删除节点」+「撤销」
- 点「撤销」→ 节点回来；连做两轮，数据库计数 **47 → 46 → 47 → 46** 逐步吻合
- 无新崩溃报告；`app.log` 里 `offline proxies: [云霄] 48 nodes (from entities)`

### 8.6.14 节点卡地址行：取自**实体**而不是运行期（已实施 + 已自测）

**自测发现的缺陷**：节点卡第 2 行显示成 `:0`（主机/端口都是空）。
查证后确认**不是**本次改动引入的，而是从来如此 —— 因为那两个字段的来源选错了：

| 来源 | 有没有 host/port |
|---|---|
| 内核 `OutboundInfo` | ❌ 不给（实测：Clash API `/proxies` 的节点项只有 `type` / `name` / `udp` / `history`） |
| 订阅配置 / 实体 payload | ✅ `server` + `server_port`（真机 132 个节点**全部**都有） |

**NekoBox 的规格**：节点卡那一行是 `proxyEntity.displayAddress()`
→ `AbstractBean.displayAddress()` = `wrapIPV6Host(serverAddress) + ":" + serverPort`
（`fmt/AbstractBean.java`）——**取自 Bean 字段**，运行期只负责延迟/流量/选中；IPv6 用
`ktx/Nets.kt` 的 `wrapIPV6Host()` 加方括号。

**改法**：两个来源都补上地址（口径一致，回落不会换掉列表长相）——
新增纯函数 `serverAddressOfPayload()`（从 payload 读 `server`/`server_port`）与
`displayAddress()`（IPv6 加方括号）；`parseSubscriptionGroup` 也从配置里同样读取。

**自测结果**：地址行显示为 `b.ka.ws.3333399.xyz:443`、`en.hk.ha.444407.xyz:443` …

**已知不含**：`server_ports`（端口**区间**写法，hysteria2 range 形态）——
本项目的真实订阅里没有这种节点，暂不处理。

### 8.6.15 自测手段：截图 → 像素定位 → 点击 → 数据库校验

**为什么重要**：此前每轮都以"沙箱不能常驻 GUI"为由把真机验证推给用户 ——
但这是个 Windows 桌面程序，**完全可以自己跑**。本轮起改用下面这条链路，
它当场抓出了上面那个 `:0` 缺陷（以及一处我自己写错的 UI 规格判断）：

1. **启动**：`build\windows\x64\runner\Release\Hiddify.exe`（前台/后台都行）。
   注意用 `DETACHED_PROCESS` 启动会静默失败，直接 `Popen` / bash 后台跑即可。
2. **读日志**：`%APPDATA%\Hiddify\hiddify\app.log` —— 启动、回填、组装、列表来源
   （`(from entities)` / `(from config)`）都在里面。崩溃另有 `crash_reports\`。
3. **读数据库**：`db.sqlite` 的 `profile_entries` / `proxy_groups` / `proxy_entities`
   行数变化是**最硬的证据**（删除/撤销各一步都能对上）。
4. **看界面**：`.workbuddy/shot.py` 用 GDI `PrintWindow(hwnd, hdc, 2)`
   （**必须传 2**，否则 Flutter 的 GPU 合成面是全黑）截窗口存 PNG，再直接看图。
5. **点界面**：`.workbuddy/click.py` 先把窗口置前并核对 `GetForegroundWindow()`，
   再按截图像素坐标点击 —— 若目标窗口不是前台，**绝不能点**（会点到别的程序上）。
6. **量坐标**：`.workbuddy/px.py` 解自己写的 PNG（filter=0/RGB）找图标的深色像素区间。
   踩过的坑：聊天里显示的图被缩放成 1092 宽（实际 1230），按显示坐标去点会偏 ~11%。

**收尾纪律**：自测会改真实数据（本轮删了节点），结束后必须**按订阅原文把数据补回**
并在日志/DB 上复核（本轮：48 → 46 → … → 补齐回 48）。

### 8.6.16 批次 1 第一刀：4 份协议表单 + 节点行 ✎（已实施 + 已自测）

**做了什么**（详见 `nekobox-priority.md` §2 批次 1、字段映射见本文件 §5）：
1. `lib/features/proxy/data/protocol_form.dart`（纯 Dart）—— 4 份规格 + 双向变换
   （`readProtocolFormValues` / `applyProtocolForm`），**未知键一律原样保留**；
   NekoBox 的两条语义照抄：空值删键（`blankAsNull()`）、布尔 false 不写键。
2. `lib/features/proxy/widget/protocol_form_modal.dart` —— 规格驱动表单（分节照 `PreferenceCategory`）。
3. `proxy_tile.dart` 补齐 `edit → share → remove`；`proxies_overview_page.dart` 接线；
   `ProxyEntityRepository.updateNodePayload` + `ProxiesOverviewNotifier.updateNodePayload`。

**为什么容器要单独建模**（本轮的设计要点，不是细节）：
NekoBox 的构建函数有**三段"整体消失"**的语义 —— `transport` 在 `type=tcp` 时为 null、
`tls` 在 `security != tls` 时为 null、`utls`/`reality`/`obfs` 在各自密码为空时不写对象。
用"逐字段置空"表达会留下 `{enabled:true}` 之类的空壳（内核可能拒绝），所以引入
`ProtocolContainerRule`：**有控制器**（如 `transport` 由 `type` 决定）与**无控制器**
（如 `tls.utls`：其下受管字段全空则摘除）两种。这是把 NekoBox 的控制流搬成了数据。

**最重要的不变量（`tool/check_protocol_form.dart` 第 1 条）**：**往返幂等** ——
读出来原样写回，payload 逐字节等价。它等价于"表单没管理的键全部原样保留"，
真机 4 种协议的实测 payload 全部逐条断言（含 `tls.reality` / `tls.utls.enabled` /
`stream_receive_window`）。**69 项断言 ALL PASS。**

**真机自测（`.workbuddy/` 三件套 + `win.py`/`kbd.py`）**：
改一个 anytls 节点的 `server_port` 443→8443 →「保存」⇒
- `app.log`: `node payload updated: [🇭🇰 Hong Kong AWS B|4x]` →
  `ConnectionNotifier: reloading core with the new config (not capturing - capture state untouched)` →
  `entity assembly: replaced=48, added=0, removed=0`
- DB payload 的 `server_port` = 8443，**其余键逐字未变**（`tls.utls.enabled`、`tls.insecure`、password）
- `configs/<id>.entities.json` 里该出站也是 8443，总条数仍 51（没有多删少删）
- 列表地址行即时变为 `b.ka.ws.3333399.xyz:8443`，弹出「节点已更新」
- **无新崩溃报告**；测完已把 payload 与组装文件复原到 443 并复核
- 见过的既有噪声（非本次引入）：`SystemTrayNotifier: error getting active proxy`，启动阶段就有

**自测工具补充（写进 `windows-gui-self-test` skill）**：
- `Ctrl+A` 在 Flutter `TextField` 上**不可靠**（实测变成"追加"）⇒ 用**退格清空**再输入；
- 应用可能只留一个可见窗口（本次直接可见），但枚举仍应**按 pid 而不是 `IsWindowVisible`**。

### 8.2 ❌ 内核未开放（需上游或降级，属 C 组）



| 项 | 核实结果 |
|---|---|
| `trafficSniffing`（流量嗅探） | `builder.go:517-518` 的 `SniffEnabled` **被注释**；`HiddifyOptions` 无该字段 |
| `appendHttpProxy` | 全库 0 命中 |
| `domain_strategy_for_server` | `DNSOptions` 无该字段 |
| `networkChangeResetConnections` / `wakeResetConnections` | 全库 0 命中（可在应用侧用 Android 网络回调实现，但内核无对应项） |
| 清空测速结果 / 清空流量统计 | **RPC 不存在**（`hcore_service.proto` 只有 Start/Stop/Restart/SelectOutbound/UrlTest/UrlTestActive/Parse/…，无 clear 类接口） |

### 8.3 🟡 纯 app 侧（不需内核，但需 Android 平台管线）

`speedInterval`（通知速率间隔）、`showDirectSpeed`、`showGroupInNotification`、`alwaysShowAddress`、
`meteredNetwork`、`acquireWakeLock`、`appTLSVersion`（订阅下载的 TLS 下限，在 `DioHttpClient`）、
`allowInsecureOnRequest`、`globalAllowInsecure`、快捷方式三动作（QuickToggle/Enable/Disable）、
磁贴 TileService、BootReceiver 开机自启、导出用 FileProvider、日志清空/导出。

### 8.4 ⛔ 需模型层（B 组，体量最大）

节点实体、分组实体、路由实体编辑、Assets 管理 —— 见 §5 / §6 / §7。

**完成度（2026-09-15）**：实体层（节点实体 + 订阅分组 + 导入管线 + 回填 + 组装 + 列表 + 删除）
**已完工并真机自测通过** ⇒ §5 的 **150 个协议字段表单**现在可以直接做（不再被模型层卡住）；
剩下的三块（手动分组 / 路由编辑 / Assets）见 `nekobox-priority.md` 批次 3–4。

---

## 9. 既有约定（不移植）

- `nav_tuiguang`（推广）/ `nav_faq`（文档页）
- Material You 主题（已由 NekoBox 五色板取代）

---

## 10. 使用方式

1. 动手前先看 **`docs/design/nekobox-priority.md`**（执行顺序表：大功能批次 1–5 → 小功能批次 6），
   本文件只提供"规格与现状"，不提供顺序
2. 每条实现完，把状态改为 ✅ 并在本文件记录实现位置（commit 号）
3. 涉及 UI 的，规格以 NekoBox 的 layout/menu/xml 文件为准（不自行发明）
4. **动手前必须核实内核支持**（本轮已发现 `enable-dns-routing` 这类"看起来能接线、实际内核也注释了"的坑）

