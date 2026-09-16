// 协议编辑表单的**数据层**（纯 Dart：不 import Flutter / drift / UI，可被 `dart run` 校验）。
//
// 规格来源：NekoBox `res/xml/*_preferences.xml`（字段与顺序）+ `ui/profile/*SettingsActivity`
// （字段 key ↔ Bean 属性）+ `fmt/*/*Fmt.kt` 的 `buildSingBoxOutbound*`（Bean → sing-box JSON）。
// 三者交叉核对的结果写在 `docs/design/nekobox-parity.md` §5；本文件是它的可执行版本。
//
// 职责边界：这里只做「表单取值 ↔ 出站 JSON」的双向变换。
// **不碰**：`tag`（节点身份，改名是独立功能）、以及任何本表单没有字段的键 ——
// 实测真机 payload 里存在表单不管理的键（`tls.reality` / `stream_receive_window` /
// `tls.utls.enabled` …），一律原样保留，这是本模块最重要的不变量。
//
// NekoBox 的两条语义（照抄，不是自创）：
// 1. **空值 = 删键**（`blankAsNull()`）：文本框留空时，NekoBox 不会写这个键。
// 2. **布尔 false = 不写**（`if (bean.allowInsecure) insecure = true`）。
//    ⇒ 我们的「清空」同样处理，否则会把 `insecure: false` 写进去，语义虽等价但污染 diff。
import 'dart:convert';

/// 字段类型。前四种照 NekoBox 的 `PreferenceBinding.Type`（Text / TextToInt / Bool / 下拉），
/// 多出 [stringList] 是因为 sing-box 的 `tls.alpn` 在 JSON 里是**数组**而 NekoBox 表单里是文本
/// （它用 `listByLineOrComma()` 在构建期转换）。
enum ProtocolFieldKind { text, integer, boolean, choice, stringList }

class ProtocolField {
  const ProtocolField({
    required this.id,
    required this.kind,
    required this.path,
    this.choices = const [],
    this.pathByChoice = const {},
    this.pathControllerId,
    this.siblings = const {},
    this.required = false,
    this.section,
  });

  /// 稳定 id —— 同时用作翻译键后缀（`pages.proxies.form.<id>`）。
  final String id;

  final ProtocolFieldKind kind;

  /// JSON 路径（出站 payload 内）。[pathByChoice] 命中时会被覆盖。
  final List<String> path;

  /// [ProtocolFieldKind.choice] 的可选值（空字符串 = "不设置"）。
  final List<String> choices;

  /// 同一字段在不同取值下路径不同 —— 照 NekoBox `buildSingBoxOutboundStreamSettings`：
  /// `host` 在 ws 下进 `headers.Host`、在 http/httpupgrade 下进 `host`，`path` 在 grpc 下是 `service_name`。
  /// 键取 [pathControllerId] 对应字段的表单值；未命中 ⇒ 该取值下这个字段无意义，**跳过写入**。
  final Map<String, List<String>> pathByChoice;
  final String? pathControllerId;

  /// 非空时一并写入的固定键 —— 用法同 NekoBox：`obfs` 非空则 `{type:"salamander", password}`；
  /// `reality.public_key` 非空则 `{enabled:true, ...}`。写在 [path] 的**父级**。
  final Map<String, String> siblings;

  /// 校验用：必填字段留空时不允许保存。
  final bool required;

  /// 所属分节（NekoBox `PreferenceCategory` 的 `app:title`）。
  /// **只在每节第一个字段上标**；null ⇒ 沿用上一个字段的节。
  final String? section;
}

/// 容器规则：管理一组字段共同所在的 JSON 对象，决定它何时整体消失。
///
/// 两种用法（都取自 NekoBox）：
/// - **有控制器**（[controllerId] 非空）：控制器取值落在 [dropWhen] 里 ⇒ 整个容器摘掉，
///   其下所有字段一律不写。例：`transport.type == "tcp"` ⇒ 没有 transport（NekoBox 返回 null）；
///   `security == false` ⇒ 没有 tls（NekoBox 的 `buildSingBoxOutboundTLS` 返回 null）。
/// - **无控制器**：容器内**受管字段全部为空**时摘掉。例：uTLS 指纹清空 ⇒ 没有 `tls.utls`
///   （否则会留下一个只剩 `enabled:true` 的空壳）。
class ProtocolContainerRule {
  const ProtocolContainerRule({required this.path, this.controllerId, this.dropWhen = const {}});

  final List<String> path;
  final String? controllerId;
  final Set<String> dropWhen;
}

class ProtocolFormSpec {
  const ProtocolFormSpec({required this.type, required this.fields, this.containers = const []});

  /// 出站 JSON 的 `type` 取值（`anytls` / `vless` / `hysteria2` / `shadowsocks` …）。
  final String type;
  final List<ProtocolField> fields;
  final List<ProtocolContainerRule> containers;
}

// ─────────────────────────────────────────────────────────────────────────────
// 下拉数组：全部照 `res/values/arrays.xml` 的 `<string-array>` 原样抄（不增不减）
// ─────────────────────────────────────────────────────────────────────────────

/// `@array/utls_fingerprint_entry`（11 项，首项为空 = 不使用）
const kUtlsFingerprints = [
  '',
  'chrome',
  'firefox',
  'edge',
  'safari',
  '360',
  'qq',
  'ios',
  'android',
  'random',
  'randomized',
];

/// `@array/ss_enc_method_value`（18 项）
const kShadowsocksMethods = [
  '2022-blake3-aes-128-gcm',
  '2022-blake3-aes-256-gcm',
  '2022-blake3-chacha20-poly1305',
  'none',
  'aes-128-gcm',
  'aes-192-gcm',
  'aes-256-gcm',
  'chacha20-ietf-poly1305',
  'xchacha20-ietf-poly1305',
  'aes-128-ctr',
  'aes-192-ctr',
  'aes-256-ctr',
  'aes-128-cfb',
  'aes-192-cfb',
  'aes-256-cfb',
  'rc4-md5',
  'chacha20-ietf',
  'xchacha20',
];

/// `@array/packet_encoding_entry`（3 项）。NekoBox 存的是 0/1/2（`@array/int_array_3`），
/// sing-box 侧的取值是 `''` / `packetaddr` / `xudp`（`buildSingBoxOutboundStandardV2RayBean`），
/// 所以这里**直接列 sing-box 的取值**，避免中间那层整数编码。
const kPacketEncodings = ['', 'packetaddr', 'xudp'];

/// `@array/networks_value`（6 项）
const kNetworks = ['tcp', 'ws', 'http', 'quic', 'grpc', 'httpupgrade'];

// ─────────────────────────────────────────────────────────────────────────────
// 四份表单（覆盖真机 84 个节点：anytls 42 / vless 21 / hysteria2 19 / shadowsocks 2）
// ─────────────────────────────────────────────────────────────────────────────

/// anytls —— `res/xml/anytls_preferences.xml` + `proxy/anytls/AnyTLSBean.java` + `AnyTLSFmt.kt`。
///
/// 注意：anytls **恒用 TLS**（`AnyTLSFmt.kt:19` 写死 `enabled = true`），所以表单里没有
/// "security" 开关，也**不设 `tls` 容器规则** —— 否则 `tls.enabled` 会被连根拔掉。
const _anytlsSpec = ProtocolFormSpec(
  type: 'anytls',
  fields: [
    ProtocolField(id: 'serverAddress', kind: ProtocolFieldKind.text, path: ['server'], required: true, section: 'proxy'),
    ProtocolField(id: 'serverPort', kind: ProtocolFieldKind.integer, path: ['server_port']),
    ProtocolField(id: 'password', kind: ProtocolFieldKind.text, path: ['password']),
    ProtocolField(id: 'sni', kind: ProtocolFieldKind.text, path: ['tls', 'server_name'], section: 'security'),
    ProtocolField(id: 'allowInsecure', kind: ProtocolFieldKind.boolean, path: ['tls', 'insecure']),
    ProtocolField(id: 'alpn', kind: ProtocolFieldKind.stringList, path: ['tls', 'alpn']),
    ProtocolField(id: 'certificates', kind: ProtocolFieldKind.text, path: ['tls', 'certificate']),
    ProtocolField(
      id: 'utlsFingerprint',
      kind: ProtocolFieldKind.choice,
      path: ['tls', 'utls', 'fingerprint'],
      choices: kUtlsFingerprints,
      siblings: {'enabled': 'true'},
    ),
  ],
  containers: [
    ProtocolContainerRule(path: ['tls', 'utls']),
  ],
);

/// VLESS —— `res/xml/standard_v2ray_preferences.xml` 的 VLESS 分支
/// （`V2RayFmt.kt:640`：`VMessBean.isVLESS` → `Outbound_VLESSOptions`）。
///
/// 两处 key 名不一致，已按 NekoBox 的**行为**对齐（不是按它的 key 名）：
/// - 表单的 `encryption` 对 VLESS 而言装的是 **flow**（`V2RayFmt.kt:645` `flow = bean.encryption`）
/// - 表单的 `type` 是**传输方式**（networks_value），不是出站的 `type`（vlss 另有写死值）
const _vlessSpec = ProtocolFormSpec(
  type: 'vless',
  fields: [
    ProtocolField(id: 'serverAddress', kind: ProtocolFieldKind.text, path: ['server'], required: true, section: 'proxy'),
    ProtocolField(id: 'serverPort', kind: ProtocolFieldKind.integer, path: ['server_port']),
    ProtocolField(id: 'uuid', kind: ProtocolFieldKind.text, path: ['uuid'], required: true),
    ProtocolField(id: 'flow', kind: ProtocolFieldKind.text, path: ['flow']),
    ProtocolField(
      id: 'packetEncoding',
      kind: ProtocolFieldKind.choice,
      path: ['packet_encoding'],
      choices: kPacketEncodings,
    ),
    // 传输方式：`tcp` ⇒ 没有 transport 对象（NekoBox 返回 null）
    ProtocolField(
      id: 'transport',
      kind: ProtocolFieldKind.choice,
      path: ['transport', 'type'],
      choices: kNetworks,
      pathControllerId: 'transport',
    ),
    ProtocolField(
      id: 'host',
      kind: ProtocolFieldKind.text,
      path: ['transport', 'headers', 'Host'],
      pathControllerId: 'transport',
      pathByChoice: {
        'ws': ['transport', 'headers', 'Host'],
        'http': ['transport', 'host'],
        'httpupgrade': ['transport', 'host'],
      },
    ),
    ProtocolField(
      id: 'path',
      kind: ProtocolFieldKind.text,
      path: ['transport', 'path'],
      pathControllerId: 'transport',
      pathByChoice: {
        'ws': ['transport', 'path'],
        'http': ['transport', 'path'],
        'httpupgrade': ['transport', 'path'],
        'grpc': ['transport', 'service_name'],
      },
    ),
    ProtocolField(id: 'wsMaxEarlyData', kind: ProtocolFieldKind.integer, path: ['transport', 'max_early_data'], pathControllerId: 'transport', section: 'ws'),
    ProtocolField(id: 'earlyDataHeaderName', kind: ProtocolFieldKind.text, path: ['transport', 'early_data_header_name'], pathControllerId: 'transport'),
    // TLS：表单的 `security`（none/tls）在这里落成 `tls.enabled`
    ProtocolField(id: 'security', kind: ProtocolFieldKind.boolean, path: ['tls', 'enabled'], section: 'security'),
    ProtocolField(id: 'sni', kind: ProtocolFieldKind.text, path: ['tls', 'server_name']),
    ProtocolField(id: 'allowInsecure', kind: ProtocolFieldKind.boolean, path: ['tls', 'insecure']),
    ProtocolField(id: 'alpn', kind: ProtocolFieldKind.stringList, path: ['tls', 'alpn']),
    ProtocolField(id: 'certificates', kind: ProtocolFieldKind.text, path: ['tls', 'certificate']),
    ProtocolField(
      id: 'utlsFingerprint',
      kind: ProtocolFieldKind.choice,
      path: ['tls', 'utls', 'fingerprint'],
      choices: kUtlsFingerprints,
      siblings: {'enabled': 'true'},
    ),
    // Reality：`V2RayFmt.kt:601` —— 公钥非空才有 reality 对象
    ProtocolField(
      id: 'realityPubKey',
      kind: ProtocolFieldKind.text,
      path: ['tls', 'reality', 'public_key'],
      siblings: {'enabled': 'true'},
    ),
    ProtocolField(id: 'realityShortId', kind: ProtocolFieldKind.text, path: ['tls', 'reality', 'short_id']),
  ],
  containers: [
    // tcp ⇒ 没有 transport
    ProtocolContainerRule(path: ['transport'], controllerId: 'transport', dropWhen: {'', 'tcp'}),
    // security 关 ⇒ 没有 tls（NekoBox `buildSingBoxOutboundTLS` 返回 null）
    ProtocolContainerRule(path: ['tls'], controllerId: 'security', dropWhen: {'false'}),
    // 公钥清空 ⇒ 没有 reality（与 tls 无关，reality 在 tls 之内，顺序由 _startsWith 保证）
    ProtocolContainerRule(path: ['tls', 'reality'], controllerId: 'realityPubKey', dropWhen: {''}),
    ProtocolContainerRule(path: ['tls', 'utls']),
  ],
);

/// hysteria2 —— `res/xml/hysteria_preferences.xml` 的 v2 分支（`HysteriaFmt.kt:316`）。
///
/// `protocolVersion` / `serverProtocol` / `serverAuthType` / `serverDisableMtuDiscovery`
/// 是 v1 概念或 NekoBox 自己注释掉的项（`:334`），未纳入 —— 见文档的"未纳入字段"清单。
const _hysteria2Spec = ProtocolFormSpec(
  type: 'hysteria2',
  fields: [
    ProtocolField(id: 'serverAddress', kind: ProtocolFieldKind.text, path: ['server'], required: true, section: 'proxy'),
    ProtocolField(id: 'serverPorts', kind: ProtocolFieldKind.integer, path: ['server_port']),
    ProtocolField(id: 'serverPassword', kind: ProtocolFieldKind.text, path: ['password']),
    ProtocolField(id: 'serverSNI', kind: ProtocolFieldKind.text, path: ['tls', 'server_name']),
    ProtocolField(id: 'serverAllowInsecure', kind: ProtocolFieldKind.boolean, path: ['tls', 'insecure']),
    ProtocolField(id: 'serverALPN', kind: ProtocolFieldKind.stringList, path: ['tls', 'alpn']),
    ProtocolField(id: 'serverCertificates', kind: ProtocolFieldKind.text, path: ['tls', 'certificate']),
    // 混淆：`HysteriaFmt.kt:328` —— 密码非空才有 obfs，且 type 恒为 salamander
    ProtocolField(
      id: 'serverObfs',
      kind: ProtocolFieldKind.text,
      path: ['obfs', 'password'],
      siblings: {'type': 'salamander'},
    ),
    ProtocolField(id: 'serverUploadSpeed', kind: ProtocolFieldKind.integer, path: ['up_mbps']),
    ProtocolField(id: 'serverDownloadSpeed', kind: ProtocolFieldKind.integer, path: ['down_mbps']),
    ProtocolField(id: 'serverStreamReceiveWindow', kind: ProtocolFieldKind.integer, path: ['stream_receive_window']),
    ProtocolField(id: 'serverConnectionReceiveWindow', kind: ProtocolFieldKind.integer, path: ['connection_receive_window']),
    ProtocolField(id: 'hopInterval', kind: ProtocolFieldKind.text, path: ['hop_interval']),
  ],
  containers: [
    ProtocolContainerRule(path: ['obfs'], controllerId: 'serverObfs', dropWhen: {''}),
  ],
);

/// shadowsocks —— `res/xml/shadowsocks_preferences.xml` + `ShadowsocksFmt.kt:110`。
///
/// NekoBox 把插件存成一条 `"name;opts"` 字符串再拆开；sing-box 原生是两个键
/// （`plugin` / `plugin_opts`），这里按原生形状拆成两个字段（语义等价，已记档）。
/// `sUoT`（UDP over TCP）未纳入：sing-box 侧是 `udp_over_tcp: {enabled, version}` 对象，
/// NekoBox 的表单只给一个布尔（版本无从选择），且真机 0 个节点用到 —— 留待后续。
const _shadowsocksSpec = ProtocolFormSpec(
  type: 'shadowsocks',
  fields: [
    ProtocolField(id: 'serverAddress', kind: ProtocolFieldKind.text, path: ['server'], required: true, section: 'proxy'),
    ProtocolField(id: 'serverPort', kind: ProtocolFieldKind.integer, path: ['server_port']),
    ProtocolField(id: 'method', kind: ProtocolFieldKind.choice, path: ['method'], choices: kShadowsocksMethods),
    ProtocolField(id: 'password', kind: ProtocolFieldKind.text, path: ['password']),
    ProtocolField(id: 'pluginName', kind: ProtocolFieldKind.text, path: ['plugin'], section: 'plugin'),
    ProtocolField(id: 'pluginConfig', kind: ProtocolFieldKind.text, path: ['plugin_opts']),
  ],
);

const _specs = <String, ProtocolFormSpec>{
  'anytls': _anytlsSpec,
  'vless': _vlessSpec,
  'vmess': _vlessSpec,
  'hysteria2': _hysteria2Spec,
  'shadowsocks': _shadowsocksSpec,
};

/// 这个出站类型有没有表单。返回 null ⇒ 调用方不要给 ✎ 入口（照 NekoBox：没写表单的协议就没有编辑页）。
ProtocolFormSpec? protocolFormSpecFor(String type) => _specs[type.trim().toLowerCase()];

/// 「手动新建」菜单里**有表单可用**的协议。
///
/// 顺序照 NekoBox `res/menu/add_profile_menu.xml` 的 Manual Settings 子菜单
/// （17 项：socks / http / ss / vmess / **vless** / trojan / trojan_go / mieru / naive /
/// **hysteria** / tuic / shadowtls / **anytls** / ssh / wg / config / chain）——
/// 我们目前有表单的是其中的第 3 / 5 / 10 / 13 项，所以这里是 ss / vless / hysteria2 / anytls。
/// 其余 13 项等批次 2 补齐表单后再进来。
const kManualCreatableProtocols = <String>['shadowsocks', 'vless', 'hysteria2', 'anytls'];

/// 协议在菜单里的显示名 —— 照 NekoBox：`action_shadowsocks` = "Shadowsocks"、
/// `action_hysteria` = "Hysteria"、`action_anytls` = "AnyTLS"、VLESS 是字面量 "VLESS"。
/// NekoBox 的中文包里没有这几条的翻译（`values-zh-rCN` 里查不到），所以这里也不翻译。
String protocolDisplayName(String type) => switch (type.trim().toLowerCase()) {
  'shadowsocks' => 'Shadowsocks',
  'vless' => 'VLESS',
  'vmess' => 'VMess',
  'hysteria2' => 'Hysteria',
  'anytls' => 'AnyTLS',
  _ => type,
};

/// 表单里出现的全部字段 id（UI 按这个顺序渲染）。
List<String> protocolFormFieldIds(ProtocolFormSpec spec) => [for (final f in spec.fields) f.id];

/// 把"只在节首标注"的 [ProtocolField.section] 铺成**分节布局**（UI 直接照这个画）。
///
/// 节名只做分组用，标签由 UI 查翻译（`pages.proxies.form.section.<name>`）。
List<({String section, List<ProtocolField> fields})> protocolFormLayout(ProtocolFormSpec spec) {
  final out = <({String section, List<ProtocolField> fields})>[];
  for (final field in spec.fields) {
    if (out.isEmpty || field.section != null) {
      out.add((section: field.section ?? '', fields: <ProtocolField>[]));
    }
    out.last.fields.add(field);
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// 双向变换
// ─────────────────────────────────────────────────────────────────────────────

/// 把出站 payload 读成「字段 id → 表单字符串」。
///
/// 缺键 / null 一律给空串（NekoBox 的 `initializeDefaultValues()` 也是把 null 归一成空）。
/// 布尔读成 `'true'` / `'false'`；数组（`alpn`）按逗号拼。
Map<String, String> readProtocolFormValues({
  required Map<String, dynamic> payload,
  required ProtocolFormSpec spec,
}) {
  final out = <String, String>{};
  for (final field in spec.fields) {
    final path = resolveProtocolFieldPath(field, values: const {});
    if (path == null) {
      out[field.id] = '';
      continue;
    }
    out[field.id] = _stringify(_get(payload, path) ?? _get(payload, field.path));
  }
  // 带 pathByChoice 的字段（host/path）要根据"当前传输方式"才能读对位置
  for (final field in spec.fields) {
    if (field.pathByChoice.isEmpty) continue;
    final controllerValue = (out[field.pathControllerId] ?? '').trim();
    final path = field.pathByChoice[controllerValue];
    if (path == null) {
      out[field.id] = '';
      continue;
    }
    out[field.id] = _stringify(_get(payload, path));
  }
  return out;
}

/// 把表单字符串写回出站 payload。
///
/// 返回新的 payload JSON 字符串；[payloadJson] 不是 JSON 对象、或整数字段填了非数字时返回 null
/// （调用方提示错误，**不落库**）。除表单管理的键以外，一切都原样保留。
String? applyProtocolForm({
  required String payloadJson,
  required ProtocolFormSpec spec,
  required Map<String, String> values,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(payloadJson);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;

  final root = jsonDecode(jsonEncode(decoded)) as Map<String, dynamic>;

  final dropped = <String>{
    for (final rule in spec.containers)
      if (rule.controllerId != null && rule.dropWhen.contains((values[rule.controllerId!] ?? '').trim()))
        rule.path.join('.'),
  };
  for (final rule in spec.containers) {
    if (rule.controllerId != null && dropped.contains(rule.path.join('.'))) _remove(root, rule.path);
  }

  for (final field in spec.fields) {
    if (dropped.any((p) => _startsWith(field.path, p))) continue;

    final path = resolveProtocolFieldPath(field, values: values);
    if (path == null) continue; // 当前取值下这个字段没有对应位置（如 quic 的 host）

    final raw = (values[field.id] ?? '').trim();
    // 布尔：false 与留空同义（NekoBox `if (bean.allowInsecure) insecure = true`）
    if (raw.isEmpty || (field.kind == ProtocolFieldKind.boolean && raw != 'true')) {
      _remove(root, path);
      continue;
    }

    final Object? value;
    switch (field.kind) {
      case ProtocolFieldKind.text:
      case ProtocolFieldKind.choice:
        value = raw;
      case ProtocolFieldKind.stringList:
        value = [for (final part in raw.split(RegExp(r'[\n,]'))) if (part.trim().isNotEmpty) part.trim()];
      case ProtocolFieldKind.integer:
        final parsed = int.tryParse(raw);
        if (parsed == null) return null;
        value = parsed;
      case ProtocolFieldKind.boolean:
        value = true;
    }
    _set(root, path, value);

    // 兄弟固定键写在父级（obfs.type / reality.enabled …）
    if (field.siblings.isNotEmpty && path.length >= 2) {
      final parent = path.sublist(0, path.length - 1);
      for (final entry in field.siblings.entries) {
        _set(root, [...parent, entry.key], entry.value == 'true' ? true : entry.value);
      }
    }
  }

  // 无控制器的容器：受管字段全空 ⇒ 整个容器摘掉（uTLS 指纹清空 ⇒ 不留 `tls.utls` 空壳）
  for (final rule in spec.containers) {
    if (rule.controllerId != null) continue;
    final hasValue = spec.fields.any(
      (f) => _startsWith(f.path, rule.path.join('.')) && (values[f.id] ?? '').trim().isNotEmpty,
    );
    if (!hasValue) _remove(root, rule.path);
  }

  // 清掉受管容器内部因删键而变空的对象（如 ws 的 `headers`）
  for (final rule in spec.containers) {
    _pruneEmptyMaps(root, rule.path);
  }

  return jsonEncode(root);
}

/// 解析字段在当前表单取值下的 JSON 路径。
///
/// 有 [ProtocolField.pathByChoice] 时，取控制器字段的值去查表；查不到 ⇒ 返回 null（该取值下无意义）。
List<String>? resolveProtocolFieldPath(ProtocolField field, {required Map<String, String> values}) {
  if (field.pathByChoice.isEmpty) return field.path;
  final controller = field.pathControllerId;
  if (controller == null) return field.path;
  return field.pathByChoice[(values[controller] ?? '').trim()];
}

/// 保存前的校验。返回错误信息的字段 id 列表（空列表 = 可保存）。
///
/// 只校验两件（如实照 NekoBox 的最小集，不自创规则）：必填非空、端口可解析且在 1..65535。
List<String> validateProtocolForm({required ProtocolFormSpec spec, required Map<String, String> values}) {
  final bad = <String>[];
  for (final field in spec.fields) {
    final raw = (values[field.id] ?? '').trim();
    if (field.required && raw.isEmpty) {
      bad.add(field.id);
      continue;
    }
    if (raw.isEmpty) continue;
    if (field.kind == ProtocolFieldKind.integer) {
      final parsed = int.tryParse(raw);
      if (parsed == null) {
        bad.add(field.id);
      } else if (field.id.toLowerCase().contains('port') && (parsed < 1 || parsed > 65535)) {
        bad.add(field.id);
      }
    }
  }
  return bad;
}

// ─────────────────────────────────────────────────────────────────────────────
// 「从零新建」：种子键（NekoBox 构建期写死、表单不管、但缺了内核会拒的那些）
// ─────────────────────────────────────────────────────────────────────────────

/// 每个协议**新建时必须存在**的种子键。
///
/// 为什么需要它（编辑模式不需要）：编辑时 `tls.enabled` 这类键是靠"原样保留"活下来的
/// （表单没有对应字段）；新建时没有"原样"可保留 ⇒ 不显式给，建出来的节点内核会拒。
///
/// 取值只取自 NekoBox 的构建函数里**写死或默认**的部分，不自创：
/// - `anytls`：`AnyTLSFmt.kt:19` 写死 `tls.enabled = true`
/// - `hysteria2`：`HysteriaFmt.kt:351` 写死 `tls.enabled = true`
/// - `vless`：`V2RayFmt.kt:593` —— 只有 `security == "tls"` 才有 tls 对象，
///   而 `StandardV2RayBean` 的 `security` 默认是空 ⇒ 种子里**不带** tls
/// - `shadowsocks`：没有 tls
Map<String, dynamic> protocolSeedPayload(ProtocolFormSpec spec) => switch (spec.type) {
  'anytls' || 'hysteria2' => {
    'tls': {'enabled': true},
  },
  _ => const <String, dynamic>{},
};

/// 用表单值**从零构造**一个出站 payload（手动新建节点，NekoBox Manual Settings 的保存）。
///
/// 与编辑路径共用 [applyProtocolForm] —— 所以"空值删键 / 布尔 false 不写 / 容器整体消失"
/// 这套语义完全一致，不产生第二条写入路径。
/// 返回 null 表示表单值不合法（与编辑路径同一判据）。
String? buildProtocolPayload({
  required ProtocolFormSpec spec,
  required String tag,
  required Map<String, String> values,
}) {
  final seed = jsonEncode(<String, dynamic>{'type': spec.type, 'tag': tag, ...protocolSeedPayload(spec)});
  return applyProtocolForm(payloadJson: seed, spec: spec, values: values);
}

// ─────────────────────────────────────────────────────────────────────────────
// JSON 路径小工具（只处理 Map/List 的嵌套，不做别的）
// ─────────────────────────────────────────────────────────────────────────────

Object? _get(Object? node, List<String> path) {
  Object? cur = node;
  for (final key in path) {
    if (cur is! Map) return null;
    cur = cur[key];
  }
  return cur;
}

void _set(Map<String, dynamic> root, List<String> path, Object? value) {
  var cur = root;
  for (var i = 0; i < path.length - 1; i++) {
    final next = cur[path[i]];
    if (next is Map<String, dynamic>) {
      cur = next;
    } else if (next is Map) {
      final copy = Map<String, dynamic>.from(next);
      cur[path[i]] = copy;
      cur = copy;
    } else {
      final fresh = <String, dynamic>{};
      cur[path[i]] = fresh;
      cur = fresh;
    }
  }
  cur[path.last] = value;
}

void _remove(Map<String, dynamic> root, List<String> path) {
  var cur = root;
  for (var i = 0; i < path.length - 1; i++) {
    final next = cur[path[i]];
    if (next is Map<String, dynamic>) {
      cur = next;
    } else if (next is Map) {
      final copy = Map<String, dynamic>.from(next);
      cur[path[i]] = copy;
      cur = copy;
    } else {
      return;
    }
  }
  cur.remove(path.last);
}

/// 递归删掉 [root] 在 [container] 之下的空 Map（保留容器自身）。
void _pruneEmptyMaps(Map<String, dynamic> root, List<String> container) {
  final node = container.isEmpty ? root : _get(root, container);
  if (node is! Map<String, dynamic>) return;
  _pruneEmptyMapsIn(node);
}

void _pruneEmptyMapsIn(Map<String, dynamic> node) {
  final emptyKeys = <String>[];
  for (final entry in node.entries) {
    final value = entry.value;
    if (value is Map<String, dynamic>) {
      _pruneEmptyMapsIn(value);
      if (value.isEmpty) emptyKeys.add(entry.key);
    }
  }
  for (final key in emptyKeys) {
    node.remove(key);
  }
}

bool _startsWith(List<String> path, String container) {
  final parts = container.split('.');
  if (path.length < parts.length) return false;
  for (var i = 0; i < parts.length; i++) {
    if (path[i] != parts[i]) return false;
  }
  return true;
}

String _stringify(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  if (value is List) return [for (final item in value) _stringify(item)].where((e) => e.isNotEmpty).join(',');
  return '';
}
