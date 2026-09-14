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

## 3. 剩余 25 条清单与建议修法

### A. 对话框/弹窗里的业务组件（7 个文件，最容易修）

| 文件 | 反向依赖 | 建议 |
|---|---|---|
| `core/router/dialog/widgets/sort_profiles_dialog.dart` | `features/profile/*` | 挪到 `features/profile/widget/`，调用方（profiles_page 等）直接 push；`DialogNotifier.showSortProfiles()` 退役 |
| `core/router/dialog/widgets/new_version_dialog.dart` | `features/app_update/*` | 挪到 `features/app_update/widget/` |
| `core/router/dialog/widgets/window_closing_dialog.dart` | `features/window/*` | 挪到 `features/window/widget/` |
| `core/router/dialog/widgets/setting_checkbox_dialog.dart` | `features/route_rules/notifier` | 该对话框被路由规则页专用 → 挪到 `features/route_rules/widget/` |
| `core/router/dialog/widgets/setting_picker_dialog.dart` | `features/settings/widget/preference_tile.dart` | 抽出"旗帜/图标展示"到 core（或改为传 `Widget Function(T)` 由调用方给） |
| `core/router/dialog/dialog_notifier.dart` | 上述 4 个 + `features/common/qr_code_*` | 只留通用对话框（确认/输入/选择/OK），业务对话框的 `showXxx()` 方法随之搬到对应 feature |
| `core/router/bottom_sheets/*`（3 个文件） | `features/{profile,route_rules,per_app_proxy,chain,settings}` | 同法：`AddProfileModal` / `PredefinedRulesModal` / `AutoAppsSelectionModal` / `QuickSettingsModal` 各归其 feature；`BottomSheetsNotifier` 只留通用的 `_show` 机制 |

### B. 偏好 / 数据层（4 个文件，需先移模型）

| 文件 | 反向依赖 | 建议 |
|---|---|---|
| `core/preferences/general_preferences.dart` | `features/per_app_proxy/model/per_app_proxy_mode.dart`、`features/window/notifier/window_notifier.dart` | `PerAppProxyMode` 是"偏好枚举"，应下沉到 core（或 core 定义、feature 扩展）；window 的偏好项改成 core 里的纯值 |
| `core/db/db.dart` | `features/profile/model/profile_entity.dart`、`features/per_app_proxy/model/per_app_proxy_mode.dart` | DB 表结构依赖领域模型 → 二选一：把这两个模型下沉到 core，或把 `db.dart` 上移到 features 之上的数据层。**先定模型归属，再动 DB**（涉及 drift schema/迁移，风险最高，放最后） |
| `core/http_client/http_client_provider.dart` | `features/settings/data/config_option_repository.dart` | 它只是为了读代理/UA 偏好 → 直接读 `Preferences`，不要依赖 feature 仓库 |
| `core/router/adaptive_layout/shell_drawer.dart` | 无 | （示例：留 core 的正面样本） |

**顺序建议**：A（对话框/弹窗，纯搬移+改调用点）→ B 前三项（偏好/HTTP，改动小）→ `db.dart`（最后，需处理 drift 迁移）。

每步都要：`flutter analyze`（0 error）→ `dart run build_runner build` → `flutter build windows --release` → 真机跑一遍截图（`core/router` 与启动路径相关时必跑）。

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
