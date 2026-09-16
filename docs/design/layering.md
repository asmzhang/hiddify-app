# 分层约定与 core→features 逆依赖收敛

> 写于 2026-09-14。起因：审计发现 `lib/core` 反向 import `lib/features`，共 47 条。
> 本文记录**层规则**、已做的事、以及剩余清单，避免下一轮又把组合根塞回 core。

---

## 1. 层规则（唯一准绳）

```
lib/
  core/        基础设施：偏好、主题、本地化、gRPC 客户端、DB、通用对话框/弹窗、路由**基础设施**
  app/         组合根：路由表（哪个路径渲染哪个页面）、导航壳（Drawer/Rail）、GoRouter 实例
  features/    业务功能：页面、notifier、领域模型、功能专属对话框
  singbox/ hiddifycore/ utils/   （既有层，不属本文范围）
```

- **允许**：`features → app`、`features → core`、`app → core`、`app → features`。
- **禁止**：`core → features`、`core → app`。
- 判断一句话：**"这行代码知道某个具体业务页面/业务模型吗？"** 知道就不该待在 core。
- 如果 core 需要某个业务能力（例如"弹一个节点信息框"），正确做法是 core 只定义**通用能力+参数**（`showConfirmation(title, message)`），由 features 侧调用时传入业务内容；而不是让 core 去 import 那个业务组件。

---

## 2. 已做（第一刀：搬走组合根）

| 文件 | 原位置 | 现位置 |
|---|---|---|
| `routing_config_notifier.dart`（路由表，import 21 个 feature 页面） | `core/router/go_router/` | `app/routing/` |
| `go_router_notifier.dart`（GoRouter 实例） | `core/router/go_router/` | `app/routing/` |
| `my_adaptive_layout.dart`（Drawer/Rail 导航壳） | `core/router/adaptive_layout/` | `app/shell/` |
| `nav_items.dart`（导航项元数据，唯一数据源） | `core/router/adaptive_layout/` | `app/shell/` |
| `shell_route_action.dart` | `core/router/adaptive_layout/` | `app/shell/` |
| `rootNavKey`（对话框/弹窗挂载点） | 原在 `go_router_notifier.dart` | **留在 core**：`core/router/navigation_keys.dart` |

留在 core 的（无业务依赖，或 core 自身需要）：`shell_drawer.dart`（抽屉 key + 汉堡键）、`helper/active_breakpoint_notifier.dart`、`helper/custom_transition.dart`、`refresh_listenable.dart`。

**效果：core→features 逆依赖 47 条 → 25 条**（涉及文件 13 → 12）。
`rootNavKey` 单独提到 `navigation_keys.dart` 是关键一步 —— 否则 core 的 dialog / bottom_sheet 会被迫 import app 层，等于把违约换个方向。

---

## 3. 剩余 8 条清单与建议修法

> 2026-09-14 更新：A 组（对话框/弹窗）已全部完成 —— 见下节。
> 逆依赖 **47 → 25（组合根）→ 16（对话框）→ 8（弹窗）**，涉及文件 13 → 12 → 5。

### A. 对话框/弹窗（✅ 已完成）

做法：core 只留两个"纯基础设施 + 零业务内容"的入口 ——
`showRootDialog()`（`core/router/dialog/root_dialog.dart`）与
`showRootBottomSheet()`（`core/router/bottom_sheets/root_bottom_sheet.dart`）；
每个业务对话框/弹窗搬回它的 feature，并在同文件导出 `showXxxDialog()/showXxxSheet()` 薄入口，
调用方改调它。`DialogNotifier` 只留通用对话框（确认/输入/选择/OK…），
`BottomSheetsNotifier` 整个删除。

已搬：`sort_profiles_dialog`→profile、`new_version_dialog`→app_update、
`window_closing_dialog`→window、`setting_checkbox_dialog`→route_rules、
`predefined_rules_modal`（入口函数）、`add_profile_modal`（含深链确认）、
`quick_settings_modal`→settings、`auto_apps_selection_modal`→per_app_proxy。
顺手删掉零调用的 `showExperimentalFeatureNotice`。

### B. 偏好 / 数据层（✅ 已完成，2026-09-14）

做法：**共享模型/常量下沉 core，原位置留 `export` 薄转发**，调用方零改动或只改 import：

| 下沉对象 | 原位置 | 现位置 | 说明 |
|---|---|---|---|
| `PerAppProxyMode` / `AppProxyMode` | `features/per_app_proxy/model/per_app_proxy_mode.dart` | `core/model/per_app_proxy_mode.dart` | 偏好 + DB 双方都要用的枚举；原文件改为单行 `export`，10 个调用方无需改 import |
| `ProfileType` | `features/profile/model/profile_entity.dart` | `core/model/profile_type.dart` | db.dart 实际只用这个枚举（不是 `ProfileEntity` 本身）；profile_entity `export` 保持兼容 |
| `minimumWindowSize` / `defaultWindowSize` | `features/window/notifier/window_notifier.dart` | `core/model/window_size.dart` | 窗口尺寸常量（general_preferences 的 windowSize 默认值需要） |
| `ConfigOptions.mixedPort` | `features/settings/data/config_option_repository.dart` | `core/preferences/port_preferences.dart`（`PortPreferences.mixedPort`） | HTTP 客户端（core）需要监听该端口建立本地代理；`ConfigOptions.mixedPort` 改为别名引用，settings 页面零改动 |

改动的 core 文件（import 换到 core 内部）：
`general_preferences.dart`、`db.dart`、`http_client_provider.dart`、`config_option_repository.dart`（补 PortPreferences import）、`window_notifier.dart`（补回 Preferences import + 换 window_size）。

**效果：core→features 逆依赖 47 → 25（组合根）→ 16（对话框）→ 8（弹窗）→ 5 → 0（B 组），涉及文件 13 → 12 → 5 → 0。**
**`lib/core` 不再 import `lib/features` / `lib/app`（drift 生成文件 db.g.dart 除外，其 import 由 part 结构决定、与源文件一致）。**

经验教训：
- drift 的 `textEnum<T>()` 只需要枚举类型本身，不需要 freezed 实体——先看 db.dart 真正用了什么，不要被 "DB 依赖领域模型" 的表象吓住，迁移风险实际为零（表结构未动，schemaVersion 仍是 6）。
- 换 import 时先 grep 该文件对旧 import 其余符号的引用（window_notifier 还用 `Preferences`，不能整行删）。

---

## 4. 验证脚本

```powershell
# 逆依赖计数（应逐步下降）
python - <<'PY'
import io, os, re
n = 0
for dp, dn, fn in os.walk('lib/core'):
    for f in fn:
        if f.endswith('.dart') and not f.endswith('.g.dart'):
            s = io.open(os.path.join(dp, f), encoding='utf-8').read()
            n += len(re.findall(r"^import 'package:hiddify/(features/[^']+)';", s, re.M))
print('core -> features:', n)
PY
```
