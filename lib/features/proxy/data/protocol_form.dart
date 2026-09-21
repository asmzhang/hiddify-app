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
/// （它用 `listByLineOrComma()` 在构建期转换）；
/// [integerList] 是 wireguard 的 `reserved`（内核 `[]uint8`，JSON 数字数组）——
/// NekoBox 里它是一段文本、构建期经 `genReserved()` 转 b64 字符串（那是为适配它镜像类里
/// `reserved: String` 的约束）；我们内核是字节数组，直接收「逗号分隔的 0-255 数字」产数组。
enum ProtocolFieldKind { text, integer, boolean, choice, stringList, integerList }

class ProtocolField {
  const ProtocolField({
    required this.id,
    required this.kind,
    required this.path,
    this.choices = const [],
    this.pathByChoice = const {},
    this.writeValues = const {},
    this.pathControllerId,
    this.siblings = const {},
    this.required = false,
    this.section,
    this.valueSuffix,
  });

  /// 稳定 id —— 同时用作翻译键后缀（`pages.proxies.form.<id>`）。
  final String id;

  final ProtocolFieldKind kind;

  /// JSON 路径（出站 payload 内）。[pathByChoice] 命中时会被覆盖。
  /// 元素是 String（对象键）或 int（数组下标）—— int 用于 mieru 的
  /// `portBindings[0]`（内核 `MieruOutboundOptions.PortBindings` 是数组，
  /// NekoBox 表单的 serverPort/serverProtocol 落在第 0 个元素）。
  final List<Object> path;

  /// [ProtocolFieldKind.choice] 的可选值（空字符串 = "不设置"）。
  final List<String> choices;

  /// [ProtocolFieldKind.choice] 的「表单取值 → 写入 JSON 的值」映射。
  /// 典型用例（都取自内核选项类型，不自创）：
  /// - shadowtls `version`：内核 `ShadowTLSOutboundOptions.Version` 是 **int**，
  ///   下拉值 "2"/"3" 必须写成 2/3（写 "3" 字符串内核会拒）；
  /// - naive `serverProtocol`：内核 `NaiveOutboundOptions.QUIC` 是 **bool**，
  ///   https→false / quic→true（false 用 `omitempty` 等价于不写，但显式 false
  ///   能让读回时正确显示 "https"）。
  /// 未列出的取值按原字符串写入；值为 null ⇒ 删键。
  final Map<String, Object?> writeValues;

  /// 同一字段在不同取值下路径不同 —— 照 NekoBox `buildSingBoxOutboundStreamSettings`：
  /// `host` 在 ws 下进 `headers.Host`、在 http/httpupgrade 下进 `host`，`path` 在 grpc 下是 `service_name`。
  /// 键取 [pathControllerId] 对应字段的表单值；未命中 ⇒ 该取值下这个字段无意义，**跳过写入**。
  final Map<String, List<Object>> pathByChoice;
  final String? pathControllerId;

  /// 非空时一并写入的固定键 —— 用法同 NekoBox：`obfs` 非空则 `{type:"salamander", password}`；
  /// `reality.public_key` 非空则 `{enabled:true, ...}`。写在 [path] 的**父级**。
  final Map<String, String> siblings;

  /// 写入前追加的后缀（仅对**纯数字**值生效）。动机：内核 `hop_interval` 是
  /// `badoption.Duration`，**必须带单位**（sing `my_time.ParseDuration`：裸数字报
  /// "missing unit"）；NekoBox 构建期拼 `"${hopInterval}s"`（`HysteriaFmt.kt:286`）。
  /// 本表单沿用该行为：用户填裸数字，写 JSON 前补后缀；读回时若剥后前缀是纯数字
  /// 则剥掉。含字母的值（"2m"/"500ms"）是内核合法的其它单位 duration，两端都原样
  /// 保留 —— 规则对称，往返幂等。
  final String? valueSuffix;

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

  final List<Object> path;
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
// 路径工具：`List<Object>`（String 键 + int 下标）⇄  `String`（"a.0.b" 点分形式）
// ─────────────────────────────────────────────────────────────────────────────

/// 点分字符串 → 路径。数字段转 int（数组下标），其余原样。
/// 只在测试/检查代码里用到；spec 内的路径一律直接写 `List<Object>`。
List<Object> parseFieldPath(String dotted) => [
  for (final part in dotted.split('.')) int.tryParse(part) ?? part,
];

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
    // 内核是 badoption.Duration（必须带单位），NekoBox 构建期补 "s"（HysteriaFmt.kt:325）；
    // 表单存裸数字，写入前补后缀（批次 6 修复：此前裸数字会让内核拒配）。
    ProtocolField(id: 'hopInterval', kind: ProtocolFieldKind.text, path: ['hop_interval'], valueSuffix: 's'),
  ],
  containers: [
    ProtocolContainerRule(path: ['obfs'], controllerId: 'serverObfs', dropWhen: {''}),
  ],
);

/// trojan —— 复用 `res/xml/standard_v2ray_preferences.xml`（NekoBox 的
/// `TrojanSettingsActivity` 就是 `StandardV2RaySettingsActivity` 的空壳子类，
/// 仅把 `uuid` 字段改绑 `bean.password`、隐藏独立 password 字段，
/// `StandardV2RaySettingsActivity.kt:56-59`）。
///
/// 内核侧 `TrojanFmt` → `buildSingBoxOutboundStandardV2RayBean` 的 TrojanBean 分支
/// （`V2RayFmt.kt:673-682`）：`Outbound_TrojanOptions{password, tls, transport}` ——
/// 结构上就是 vless 减去 flow / packetEncoding（trojan 无此二者，内核
/// `TrojanOutboundOptions` 也没有对应键）。
///
/// trojan **恒用 TLS 吗？不是**：内核选项的 tls 是容器（可缺省），
/// NekoBox `buildSingBoxOutboundTLS` 由 `bean.security` 决定 —— 与 vless 同一套，
/// 所以 security 开关照 vless 保留（表单 boolean 落 `tls.enabled`）。
const _trojanSpec = ProtocolFormSpec(
  type: 'trojan',
  fields: [
    ProtocolField(id: 'serverAddress', kind: ProtocolFieldKind.text, path: ['server'], required: true, section: 'proxy'),
    ProtocolField(id: 'serverPort', kind: ProtocolFieldKind.integer, path: ['server_port']),
    // NekoBox 表单里 trojan 的密码就是 uuid 字段（改标题 Password、绑定 bean.password），
    // 是出站的唯一凭据 ⇒ 必填（vless 的 uuid 同为 required）。
    ProtocolField(id: 'password', kind: ProtocolFieldKind.text, path: ['password'], required: true),
    // 传输方式：`tcp` ⇒ 没有 transport 对象（NekoBox 返回 null）—— 与 vless 完全同构
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
    // Reality：同 vless（`V2RayFmt.kt:601` —— 公钥非空才有 reality 对象）
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

/// hysteria v1 —— 与 hysteria2 共用 NekoBox `res/xml/hysteria_preferences.xml`
/// （`protocolVersion` 下拉切换 1/2，`HysteriaSettingsActivity.updateVersion`）。
/// 本表单只收 v1 分支字段；v2 分支字段见 [_hysteria2Spec]。
///
/// 内核侧 `HysteriaFmt.kt:277-314`（v1 分支）→ `Outbound_HysteriaOptions`：
/// - **auth 类型下拉不移植**（ssh 同款决策）：NekoBox 的 `serverAuthType`
///   （NONE/STRING/BASE64，`arrays.xml:390`）决定构建时写 `auth_str` 还是 `auth`；
///   sing-box 内核两个键都会尝试（`HysteriaOutboundOptions.Auth/AuthString`），
///   表单直接给两个文本框，填了就写；
/// - `serverProtocol`（UDP/FakeTCP/WeChat Video）**不移植**：NekoBox 自己的
///   `canUseSingBox()`（`HysteriaFmt.kt:270-273`）规定非 UDP 模式不能用 sing-box
///   （要走独立二进制）—— 本项目只有 sing-box 内核，faketcp/wechat-video 表单做了
///   也连不上，留给 hysteria2 用户场景（v2 无此概念）；
/// - `serverDisableMtuDiscovery` 不移植：内核标记 Deprecated（`option/hysteria.go:50`，
///   "use QUIC fields instead"），写它只会污染新配置；
/// - 修复 NekoBox 的抄写 bug（`HysteriaFmt.kt:299`）：
///   `recv_window_conn = bean.connectionReceiveWindow.toLong()` 把**连接窗口**
///   写进了**流窗口**键 —— 按字段语义各写各键（`recv_window_conn`/`recv_window`）。
const _hysteriaSpec = ProtocolFormSpec(
  type: 'hysteria',
  fields: [
    ProtocolField(id: 'serverAddress', kind: ProtocolFieldKind.text, path: ['server'], required: true, section: 'proxy'),
    ProtocolField(id: 'serverPorts', kind: ProtocolFieldKind.integer, path: ['server_port']),
    // 混淆（v1 是 xplus 算法明文串；NekoBox `HysteriaFmt.kt:289` 直接写 `obfs` 键）
    ProtocolField(id: 'serverObfs', kind: ProtocolFieldKind.text, path: ['obfs']),
    // 认证：两个文本框顶替 NekoBox 的 TYPE 下拉（见上），填了就写
    ProtocolField(id: 'serverAuthString', kind: ProtocolFieldKind.text, path: ['auth_str']),
    ProtocolField(id: 'serverAuthBase64', kind: ProtocolFieldKind.text, path: ['auth']),
    ProtocolField(id: 'serverSNI', kind: ProtocolFieldKind.text, path: ['tls', 'server_name']),
    ProtocolField(id: 'serverAllowInsecure', kind: ProtocolFieldKind.boolean, path: ['tls', 'insecure']),
    ProtocolField(id: 'serverALPN', kind: ProtocolFieldKind.stringList, path: ['tls', 'alpn']),
    ProtocolField(id: 'serverCertificates', kind: ProtocolFieldKind.text, path: ['tls', 'certificate']),
    ProtocolField(id: 'serverUploadSpeed', kind: ProtocolFieldKind.integer, path: ['up_mbps']),
    ProtocolField(id: 'serverDownloadSpeed', kind: ProtocolFieldKind.integer, path: ['down_mbps']),
    ProtocolField(id: 'serverStreamReceiveWindow', kind: ProtocolFieldKind.integer, path: ['recv_window_conn']),
    ProtocolField(id: 'serverConnectionReceiveWindow', kind: ProtocolFieldKind.integer, path: ['recv_window']),
    // 内核是 badoption.Duration（必须带单位），NekoBox 构建期补 "s"（HysteriaFmt.kt:286）
    ProtocolField(id: 'hopInterval', kind: ProtocolFieldKind.text, path: ['hop_interval'], valueSuffix: 's'),
  ],
  // 恒用 TLS（`HysteriaFmt.kt:301-313` v1 分支写死 `enabled = true`），
  // 种子给 `tls.enabled`；表单不设 tls 容器规则，否则会连根拔掉。
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

/// socks —— `res/xml/socks_preferences.xml` + `fmt/socks/SOCKSFmt.kt` +
/// 内核 `SOCKSOutboundOptions`（`option/simple.go:22`）。
///
/// 版本下拉：NekoBox 表单存整数（0/1/2），`SOCKSFmt.kt` 构建时经
/// `protocolVersionName()` 转成 sing-box 的字符串 `"4"/"4a"/"5"`
/// （内核 `socks.ParseVersion` 只认这三个串）。这里直接列**最终取值**，
/// 跳过中间那层整数编码（同 [kPacketEncodings] 的处理）。
/// `sUoT` 未纳入 —— 理由同 shadowsocks（`udp_over_tcp` 是对象、表单只有布尔）。
const _socksSpec = ProtocolFormSpec(
  type: 'socks',
  fields: [
    ProtocolField(id: 'serverAddress', kind: ProtocolFieldKind.text, path: ['server'], required: true, section: 'proxy'),
    ProtocolField(id: 'serverPort', kind: ProtocolFieldKind.integer, path: ['server_port']),
    ProtocolField(id: 'serverProtocol', kind: ProtocolFieldKind.choice, path: ['version'], choices: ['4', '4a', '5']),
    ProtocolField(id: 'serverUsername', kind: ProtocolFieldKind.text, path: ['username']),
    ProtocolField(id: 'serverPassword', kind: ProtocolFieldKind.text, path: ['password']),
  ],
);

/// http —— NekoBox 的 HttpBean 复用 `standard_v2ray_preferences.xml`，但
/// `StandardV2RaySettingsActivity.kt:103-109` 对 HttpBean 做**可见性裁剪**：
/// 隐藏 type/uuid/alterId/encryption/packetEncoding，显示 username/password；
/// `updateView` 对 http 传输显示 host/path（标题 HTTP Host/Path）。
///
/// 本表单只保留**构建期真正被消费**的字段。NekoBox `buildSingBoxOutboundStandardV2RayBean`
/// 的 HttpBean 分支（`V2RayFmt.kt:628-637`）只搬 server/port/username/password/tls
/// —— **host/path 是死字段**（UI 显示但 HttpBean 分支不读它们，sing-box 的 http 出站
/// 也不认 `transport`），所以这里不做 host/path，也不做 transport。
/// TLS 字段与 vless 同一套（`buildSingBoxOutboundTLS`，security=="tls" 才有 tls 对象）：
/// sni/alpn/certificates/allowInsecure/utlsFingerprint（HttpBean 是 StandardV2RayBean
/// 子类，reality/ech 也继承可用；内核 `HTTPOutboundOptions` 的 TLS 容器同样全量支持）。
/// 内核 `HTTPOutboundOptions`（`option/simple.go:32-40`）还有 `Path`/`Headers`
/// —— Headers 是 `map[string][]string`，表单文本写不出正确形状（与 naive
/// serverHeaders 同一放弃理由）；Path 在 NekoBox 构建期同样不消费，一并放弃。
const _httpSpec = ProtocolFormSpec(
  type: 'http',
  fields: [
    ProtocolField(id: 'serverAddress', kind: ProtocolFieldKind.text, path: ['server'], required: true, section: 'proxy'),
    ProtocolField(id: 'serverPort', kind: ProtocolFieldKind.integer, path: ['server_port']),
    ProtocolField(id: 'serverUsername', kind: ProtocolFieldKind.text, path: ['username']),
    ProtocolField(id: 'serverPassword', kind: ProtocolFieldKind.text, path: ['password']),
    // TLS：表单的 `security`（none/tls）落成 `tls.enabled` —— 与 vless/trojan 同构
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
  ],
  containers: [
    // security 关 ⇒ 没有 tls（NekoBox `buildSingBoxOutboundTLS` 返回 null）
    ProtocolContainerRule(path: ['tls'], controllerId: 'security', dropWhen: {'false'}),
    ProtocolContainerRule(path: ['tls', 'utls']),
  ],
);

/// ssh —— `res/xml/ssh_preferences.xml` + `fmt/ssh/SSHFmt.kt` +
/// 内核 `SSHOutboundOptions`（`option/ssh.go:5`）。
///
/// 三处对齐：
/// - `private_key` 用 **text** 而非 stringList：NekoBox 的 `SSHFmt.kt` 写
///   `private_key = bean.privateKey`（单字符串，含 PEM 换行），拆行会毁掉密钥；
///   内核 `Listable[string]` 收单串等价于单元素数组。若来源是链接解析（ray2sing）
///   产出的数组形状，保存时会**归一成单串** —— 内核语义不变，这是有意的归一；
/// - 表单 `serverCertificates`（标题 ssh_public_key）→ 内核 **`host_key`**
///   （SSHFmt：`host_key: publicKey.listByLineOrComma()`），这个才是列表；
/// - NekoBox 的 `serverAuthType` 下拉只决定 UI 里哪个字段生效（有 key 不写 password），
///   sing-box 自身会先试公钥再试密码，所以这里**不移植**该下拉 —— 两个都给，填了就写。
const _sshSpec = ProtocolFormSpec(
  type: 'ssh',
  fields: [
    ProtocolField(id: 'serverAddress', kind: ProtocolFieldKind.text, path: ['server'], required: true, section: 'proxy'),
    ProtocolField(id: 'serverPort', kind: ProtocolFieldKind.integer, path: ['server_port']),
    ProtocolField(id: 'serverUsername', kind: ProtocolFieldKind.text, path: ['user']),
    ProtocolField(id: 'serverPassword', kind: ProtocolFieldKind.text, path: ['password']),
    ProtocolField(id: 'serverPrivateKey', kind: ProtocolFieldKind.text, path: ['private_key']),
    ProtocolField(id: 'serverPassword1', kind: ProtocolFieldKind.text, path: ['private_key_passphrase']),
    ProtocolField(id: 'serverCertificates', kind: ProtocolFieldKind.stringList, path: ['host_key']),
  ],
);

/// tuic —— `res/xml/tuic_preferences.xml` + `fmt/tuic/TuicFmt.kt` +
/// 内核 `TUICOutboundOptions`。
///
/// 恒用 TLS（`TuicFmt.kt:84-97` 写死 `tls.enabled = true`），种子给 `tls.enabled`
/// （同 anytls/hysteria2）；表单不设 tls 容器规则，否则会连根拔掉。
/// `protocolVersion` / `customJSON` / `fastConnect` / `mtu` 未纳入：v4 已被
/// `TuicFmt.kt:72` 显式拒绝，后三者 NekoBox 表单里也没有。
const _tuicSpec = ProtocolFormSpec(
  type: 'tuic',
  fields: [
    ProtocolField(id: 'serverAddress', kind: ProtocolFieldKind.text, path: ['server'], required: true, section: 'proxy'),
    ProtocolField(id: 'serverPort', kind: ProtocolFieldKind.integer, path: ['server_port']),
    ProtocolField(id: 'serverUsername', kind: ProtocolFieldKind.text, path: ['uuid']),
    ProtocolField(id: 'serverPassword', kind: ProtocolFieldKind.text, path: ['password']),
    ProtocolField(id: 'serverALPN', kind: ProtocolFieldKind.stringList, path: ['tls', 'alpn']),
    ProtocolField(id: 'serverCertificates', kind: ProtocolFieldKind.text, path: ['tls', 'certificate']),
    ProtocolField(
      id: 'serverUDPRelayMode',
      kind: ProtocolFieldKind.choice,
      path: ['udp_relay_mode'],
      choices: ['', 'native', 'quic'],
    ),
    ProtocolField(
      id: 'serverCongestionController',
      kind: ProtocolFieldKind.choice,
      path: ['congestion_control'],
      choices: ['', 'cubic', 'new_reno', 'bbr'],
    ),
    ProtocolField(id: 'serverDisableSNI', kind: ProtocolFieldKind.boolean, path: ['tls', 'disable_sni']),
    ProtocolField(id: 'serverSNI', kind: ProtocolFieldKind.text, path: ['tls', 'server_name']),
    ProtocolField(id: 'serverReduceRTT', kind: ProtocolFieldKind.boolean, path: ['zero_rtt_handshake']),
    ProtocolField(id: 'serverAllowInsecure', kind: ProtocolFieldKind.boolean, path: ['tls', 'insecure']),
  ],
);

/// shadowtls —— `res/xml/shadowtls_preferences.xml` + `ShadowTLSFmt.kt` +
/// 内核 `ShadowTLSOutboundOptions`（`option/shadowtls.go:75`）。
///
/// 两处要点：
/// - `version` 内核是 **int**（下拉值 "2"/"3" 必须经 [ProtocolField.writeValues]
///   写成 2/3，写 "3" 字符串内核会拒）；
/// - 恒用 TLS（Bean `security="tls"` 写死 → `buildSingBoxOutboundTLS` 恒有对象），
///   种子给 `tls.enabled`。
const _shadowtlsSpec = ProtocolFormSpec(
  type: 'shadowtls',
  fields: [
    ProtocolField(id: 'serverAddress', kind: ProtocolFieldKind.text, path: ['server'], required: true, section: 'proxy'),
    ProtocolField(id: 'serverPort', kind: ProtocolFieldKind.integer, path: ['server_port']),
    ProtocolField(
      id: 'version',
      kind: ProtocolFieldKind.choice,
      path: ['version'],
      choices: ['', '2', '3'],
      writeValues: {'2': 2, '3': 3},
    ),
    ProtocolField(id: 'password', kind: ProtocolFieldKind.text, path: ['password']),
    ProtocolField(id: 'sni', kind: ProtocolFieldKind.text, path: ['tls', 'server_name'], section: 'security'),
    ProtocolField(id: 'alpn', kind: ProtocolFieldKind.stringList, path: ['tls', 'alpn']),
    ProtocolField(id: 'certificates', kind: ProtocolFieldKind.text, path: ['tls', 'certificate']),
    ProtocolField(id: 'allowInsecure', kind: ProtocolFieldKind.boolean, path: ['tls', 'insecure']),
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

/// mieru —— `res/xml/mieru_preferences.xml` + `MieruBean.java` +
/// 内核 **fork 专有** `MieruOutboundOptions`（`option/mieru.go:3`）。
///
/// 与 NekoBox 的结构差异（已记档）：NekoBox 把 mieru 交给独立二进制，表单的
/// serverPort/serverProtocol 是平级字段；hiddify 内核是 sing-box 原生出站，
/// 端口与传输协议落在 **`portBindings[0]`**（`validateMieruOptions`：`server_port`
/// 留 0 且 bindings 非空即合法）。`portBindings` 是数组 ⇒ 路径用 int 下标。
/// `serverMTU` 未纳入：内核选项结构里没有 mtu（sing-box 严格解析，写了未知键直接拒）。
const _mieruSpec = ProtocolFormSpec(
  type: 'mieru',
  fields: [
    ProtocolField(id: 'serverAddress', kind: ProtocolFieldKind.text, path: ['server'], required: true, section: 'proxy'),
    ProtocolField(id: 'serverPort', kind: ProtocolFieldKind.integer, path: ['portBindings', 0, 'port'], required: true),
    ProtocolField(
      id: 'serverProtocol',
      kind: ProtocolFieldKind.choice,
      path: ['portBindings', 0, 'protocol'],
      choices: ['TCP', 'UDP'],
    ),
    ProtocolField(id: 'serverUsername', kind: ProtocolFieldKind.text, path: ['username'], required: true),
    ProtocolField(id: 'serverPassword', kind: ProtocolFieldKind.text, path: ['password'], required: true),
  ],
);

/// wireguard —— `res/xml/wireguard_preferences.xml`（proxy_cat 8 字段）+
/// `fmt/wireguard/WireGuardFmt.kt`。字段清单照 NekoBox，**产物形态按内核**：
///
/// 内核 1.13 起 wireguard outbound 是 stub（`include/registry.go:200-201`），正确形态是
/// **endpoint**（`WireGuardEndpointOptions`，`option/wireguard.go:11-37`）—— 手动节点落
/// `endpoints` 段（组装层拆桶，见 config_assembly.dart）。字段映射（NekoBox → 内核）：
/// - `serverAddress/serverPort` → `peers[0].address/port`（NekoBox 的 Bean 字段在内核
///   选项里就是 peer 一员；单 peer 是 wg 节点的常态，NekoBox 构建的也是单 peer）；
/// - `localAddress`（listByLineOrComma）→ `address`（`Listable[netip.Prefix]`，
///   内核反序列化走 `netip.ParsePrefix`——**裸 IP 无掩码会被拒**，需 CIDR 形态如
///   `172.16.0.2/32`。NekoBox 原样透传不补掩码，这里同口径，翻译 hint 说明）；
/// - `reserved` → `peers[0].reserved`（`[]uint8` 数字数组。NekoBox 的 `genReserved()`
///   把 3 数字转 b64 字符串是为适配它 `reserved: String`，我们直接收数字产数组，
///   同 ray2sing `awg.go:341-349` 的原生形态）；
/// - `mtu`（defaultValue=1420）→ `mtu`（种子给默认值，标签复用 serverMTU）。
///
/// 未纳入（NekoBox 表单也没有）：`listen_port`/`workers`/`system`/`noise`/`awg` 参数。
const _wireguardSpec = ProtocolFormSpec(
  type: 'wireguard',
  fields: [
    ProtocolField(id: 'serverAddress', kind: ProtocolFieldKind.text, path: ['peers', 0, 'address'], required: true, section: 'proxy'),
    ProtocolField(id: 'serverPort', kind: ProtocolFieldKind.integer, path: ['peers', 0, 'port']),
    ProtocolField(id: 'localAddress', kind: ProtocolFieldKind.stringList, path: ['address']),
    ProtocolField(id: 'privateKey', kind: ProtocolFieldKind.text, path: ['private_key'], required: true),
    ProtocolField(id: 'peerPublicKey', kind: ProtocolFieldKind.text, path: ['peers', 0, 'public_key']),
    ProtocolField(id: 'peerPreSharedKey', kind: ProtocolFieldKind.text, path: ['peers', 0, 'pre_shared_key']),
    ProtocolField(id: 'serverMTU', kind: ProtocolFieldKind.integer, path: ['mtu']),
    ProtocolField(id: 'reserved', kind: ProtocolFieldKind.integerList, path: ['peers', 0, 'reserved']),
  ],
);

/// naive —— `res/xml/naive_preferences.xml` + `NaiveFmt.kt`（链接侧）+
/// 内核 `NaiveOutboundOptions`（`option/naive.go:27`）。
///
/// 三处要点：
/// - `serverProtocol`（https/quic）在内核是 **`quic` 布尔**。经 [ProtocolField.writeValues]
///   映射：https → 删键（内核默认非 QUIC，omitempty 语义一致）、quic → true；
///   读回时缺键反查为 "https"（内核默认值，不显示"未设置"）。
/// - 恒用 TLS（`NaiveSingbox`：security 缺省置 "tls" → enabled），种子给 `tls.enabled`。
/// - `serverHeaders` / `sUoT` 未纳入：内核 `extra_headers` 是 `HTTPHeader`
///   （`map[string][]string`）、`udp_over_tcp` 是对象 —— 表单的文本/布尔都写不出
///   正确形状（sing-box 严格解析）。链接里带的这两项编辑时原样保留。
const _naiveSpec = ProtocolFormSpec(
  type: 'naive',
  fields: [
    ProtocolField(id: 'serverAddress', kind: ProtocolFieldKind.text, path: ['server'], required: true, section: 'proxy'),
    ProtocolField(id: 'serverPort', kind: ProtocolFieldKind.integer, path: ['server_port']),
    ProtocolField(id: 'serverUsername', kind: ProtocolFieldKind.text, path: ['username']),
    ProtocolField(id: 'serverPassword', kind: ProtocolFieldKind.text, path: ['password']),
    ProtocolField(
      id: 'serverProtocol',
      kind: ProtocolFieldKind.choice,
      path: ['quic'],
      choices: ['', 'https', 'quic'],
      writeValues: {'https': null, 'quic': true},
    ),
    ProtocolField(id: 'serverSNI', kind: ProtocolFieldKind.text, path: ['tls', 'server_name'], section: 'security'),
    ProtocolField(id: 'serverCertificates', kind: ProtocolFieldKind.text, path: ['tls', 'certificate']),
    ProtocolField(id: 'serverInsecureConcurrency', kind: ProtocolFieldKind.integer, path: ['insecure_concurrency']),
  ],
);

const _specs = <String, ProtocolFormSpec>{
  'anytls': _anytlsSpec,
  'vless': _vlessSpec,
  'vmess': _vlessSpec,
  'trojan': _trojanSpec,
  'hysteria': _hysteriaSpec,
  'hysteria2': _hysteria2Spec,
  'shadowsocks': _shadowsocksSpec,
  'socks': _socksSpec,
  'http': _httpSpec,
  'ssh': _sshSpec,
  'tuic': _tuicSpec,
  'shadowtls': _shadowtlsSpec,
  'mieru': _mieruSpec,
  'naive': _naiveSpec,
  'wireguard': _wireguardSpec,
};

/// 这个出站类型有没有表单。返回 null ⇒ 调用方不要给 ✎ 入口（照 NekoBox：没写表单的协议就没有编辑页）。
ProtocolFormSpec? protocolFormSpecFor(String type) => _specs[type.trim().toLowerCase()];

/// 「手动新建」菜单里**有表单可用**的协议。
///
/// 顺序照 NekoBox `res/menu/add_profile_menu.xml` 的 Manual Settings 子菜单
/// （17 项：socks / http / ss / vmess / **vless** / trojan / trojan_go / mieru / naive /
/// **hysteria** / tuic / shadowtls / **anytls** / ssh / wg / chain）。
///
/// 批次 9 后的缺席项及理由：
/// - `trojan_go`：**不移植** —— hiddify 内核（sing-box fork）没有 trojan-go 出站
///   注册（`include/registry.go` 无 TypeTrojanGo），NekoBox 靠外部二进制运行，
///   hiddify 无此机制，表单做了也连不上。
/// - ~~`config`：NekoBox 的「从配置文件导入」不属于协议表单~~ 批次 11 反悔：
///   确实不属于协议表单，但属于手动菜单（`action_new_config`）—— 走
///   [kManualCreatableProtocols] 列表 + 特判流程，见该常量的批次 11 注释。
///
/// 批次 9 补上 `wireguard`（NekoBox add_profile_menu 第 15 项 wg）：内核形态是
/// endpoint（`_wireguardSpec` 的注释），payload 由组装层进 `endpoints` 段。
/// 批次 10 补上 `chain`（NekoBox add_profile_menu 的 `action_new_chain`，title=
/// `proxy_chain`="Proxy Chain"）：它**不是协议表单** —— [startManualNodeFlow] 对它
/// 特判开 ChainSettings 页；列在这里只是为了让它出现在「选择协议」菜单
/// （NekoBox 的菜单位也在这：`add_profile_menu.xml` 手动设置子菜单内）。
/// 批次 11 补上 `config`（NekoBox `action_new_config`，title=`custom_config`
/// ="Custom Config"，菜单位紧挨 chain 之前）：同样**不是协议表单** —— 它没有字段
/// （payload 就是用户手写的整份 JSON），[startManualNodeFlow] 对它特判开
/// ConfigSettings 页；组装层按 payload 有无 `type` 键分 outbound/full 两形态
/// （`config_assembly.kConfigEntityType` 的注释）。
/// 批次 12 补上 `http`（NekoBox add_profile_menu 第 2 项 action_new_http）：
/// 表单见 [_httpSpec] —— 字段照 `StandardV2RaySettingsActivity.kt:103-109` 对
/// HttpBean 的可见性裁剪，host/path 因 NekoBox 构建期不消费（死字段）而不移植。
const kManualCreatableProtocols = <String>[
  'socks',
  'http',
  'shadowsocks',
  'vless',
  'trojan',
  'mieru',
  'naive',
  'hysteria',
  'hysteria2',
  'tuic',
  'shadowtls',
  'anytls',
  'ssh',
  'wireguard',
  'config',
  'chain',
];

/// 协议在菜单里的显示名 —— 照 NekoBox `strings.xml` 的 `action_*`
/// （`action_socks`="SOCKS"、`action_ssh`="SSH"、`action_tuic`="TUIC"、
/// `action_shadowtls`="ShadowTLS"、`action_mieru`="Mieru"、`action_naive`="Naïve"）。
String protocolDisplayName(String type) => switch (type.trim().toLowerCase()) {
  'shadowsocks' => 'Shadowsocks',
  'vless' => 'VLESS',
  'vmess' => 'VMess',
  'trojan' => 'Trojan',
  'hysteria' => 'Hysteria',
  'hysteria2' => 'Hysteria',
  'anytls' => 'AnyTLS',
  'socks' => 'SOCKS',
  'http' => 'HTTP',
  'ssh' => 'SSH',
  'tuic' => 'TUIC',
  'shadowtls' => 'ShadowTLS',
  'mieru' => 'Mieru',
  'naive' => 'Naïve',
  'wireguard' => 'WireGuard',
  'config' => 'Custom Config',
  'chain' => 'Proxy Chain',
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
  // 带 writeValues 的 choice 字段：读出 JSON 值后要**反查**回表单取值
  // （如 naive `quic:false` → "https"、`quic:true` → "quic"）。
  for (final field in spec.fields) {
    if (field.writeValues.isEmpty) continue;
    final jsonValue = _get(payload, field.path);
    for (final entry in field.writeValues.entries) {
      if (_reprScalar(entry.value) == _reprScalar(jsonValue)) {
        out[field.id] = entry.key;
        break;
      }
    }
  }
  // 带 valueSuffix 的字段：还原成"用户填写的裸值"。剥后缀**仅当剥剩的前缀
  // 是纯数字**（"30s" → "30"）；否则原样显示（"2m"/"2ms" 是内核合法的其它
  // 单位 duration，剥了会破坏语义，且写回时也不会再补——两端对称）。
  for (final field in spec.fields) {
    final suffix = field.valueSuffix;
    if (suffix == null || suffix.isEmpty) continue;
    final v = out[field.id] ?? '';
    if (v.length > suffix.length && v.endsWith(suffix)) {
      final prefix = v.substring(0, v.length - suffix.length);
      if (int.tryParse(prefix) != null) out[field.id] = prefix;
    }
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
        // choice + writeValues：表单取值映射成 JSON 值（int/bool/null），
        // 未映射的取值按原字符串写入（向后兼容普通下拉）。
        Object? v = field.kind == ProtocolFieldKind.choice && field.writeValues.containsKey(raw)
            ? field.writeValues[raw]
            : raw;
        // valueSuffix：写入前补单位（内核 badoption.Duration 必须带单位）。
        // 只对**纯数字**补（"30" → "30s"）；含字母的值视为用户已带单位
        // （"2m"/"500ms" 都是内核合法取值），原样写。读回端同规则剥离。
        final suffix = field.valueSuffix;
        if (v is String && suffix != null && suffix.isNotEmpty && int.tryParse(v) != null) {
          v = '$v$suffix';
        }
        value = v;
      case ProtocolFieldKind.stringList:
        value = [for (final part in raw.split(RegExp(r'[\n,]'))) if (part.trim().isNotEmpty) part.trim()];
      case ProtocolFieldKind.integerList:
        // reserved（内核 `[]uint8`）：逗号/换行分隔的 0-255 数字 → 数字数组。
        // 任一元素不是数字 ⇒ 整个字段判非法（return null，调用方提示不落库）
        // —— 与 integer 字段「填了非数字就拒存」同一严格度。
        final parts = [for (final part in raw.split(RegExp(r'[\n,]'))) part.trim()];
        final parsedList = <int>[];
        for (final part in parts) {
          if (part.isEmpty) continue;
          final n = int.tryParse(part);
          if (n == null || n < 0 || n > 255) return null;
          parsedList.add(n);
        }
        if (parsedList.isEmpty) {
          _remove(root, path);
          continue;
        }
        value = parsedList;
      case ProtocolFieldKind.integer:
        final parsed = int.tryParse(raw);
        if (parsed == null) return null;
        value = parsed;
      case ProtocolFieldKind.boolean:
        value = true;
    }
    if (value == null) {
      _remove(root, path);
      continue;
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
List<Object>? resolveProtocolFieldPath(ProtocolField field, {required Map<String, String> values}) {
  if (field.pathByChoice.isEmpty) return field.path;
  final controller = field.pathControllerId;
  if (controller == null) return field.path;
  return field.pathByChoice[(values[controller] ?? '').trim()];
}

/// 保存前的校验。返回错误信息的字段 id 列表（空列表 = 可保存）。
///
/// 只校验三件（如实照 NekoBox 的最小集，不自创规则）：必填非空、端口可解析且在 1..65535、
/// integerList（reserved）每个元素都是 0-255 的数字。
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
    } else if (field.kind == ProtocolFieldKind.integerList) {
      // reserved：写回时才逐元素 tryParse，这里先拦住明显非法的（与写回同一判据）
      final ok = raw.split(RegExp(r'[\n,]')).every((part) {
        final p = part.trim();
        if (p.isEmpty) return true;
        final n = int.tryParse(p);
        return n != null && n >= 0 && n <= 255;
      });
      if (!ok) bad.add(field.id);
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
/// 取值只取自 NekoBox 的构建函数 / 内核选项里**写死或默认**的部分，不自创：
/// - `anytls`：`AnyTLSFmt.kt:19` 写死 `tls.enabled = true`
/// - `hysteria` v1：`HysteriaFmt.kt:301-313` 写死 `tls.enabled = true`
/// - `hysteria2`：`HysteriaFmt.kt:351` 写死 `tls.enabled = true`
/// - `tuic`：`TuicFmt.kt:84-97` 写死 `tls.enabled = true`
/// - `shadowtls`：Bean `security="tls"` 写死 → `buildSingBoxOutboundTLS` 恒有对象
/// - `naive`：ray2sing `NaiveSingbox` security 缺省置 "tls" → enabled
/// - `mieru`：`portBindings[0]` 的 protocol 由表单写入，port 也由表单写入
///   （`portBindings[0].port`）—— 但内核 `MieruPortBinding` 反序列化要求元素是
///   对象，种子先把数组占位，避免"端口填了、协议下拉没动"时写不出对象形状
/// - `vless`：`V2RayFmt.kt:593` —— 只有 `security == "tls"` 才有 tls 对象，
///   而 `StandardV2RayBean` 的 `security` 默认是空 ⇒ 种子里**不带** tls
/// - `trojan`：同 vless（security 由表单开关决定，默认关）
/// - `shadowsocks` / `socks` / `ssh`：没有 tls
/// - `wireguard`：`mtu: 1420`（NekoBox `wireguard_preferences.xml` 的 defaultValue）
///   + `peers: [{}]` 占位 —— `peers[0]` 是表单五个字段的落点，数组元素必须是对象
///   才写得出 `peers[0].address` 等（同 mieru `portBindings[0]` 的占位逻辑）
Map<String, dynamic> protocolSeedPayload(ProtocolFormSpec spec) => switch (spec.type) {
  'anytls' || 'hysteria' || 'hysteria2' || 'tuic' || 'shadowtls' || 'naive' => {
    'tls': {'enabled': true},
  },
  'mieru' => {
    'portBindings': <dynamic>[<String, dynamic>{}],
  },
  'wireguard' => {
    'mtu': 1420,
    'peers': <dynamic>[<String, dynamic>{}],
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

Object? _get(Object? node, List<Object> path) {
  Object? cur = node;
  for (final key in path) {
    if (key is int) {
      if (cur is! List || key >= cur.length) return null;
      cur = cur[key];
    } else if (cur is! Map) {
      return null;
    } else {
      cur = cur[key];
    }
  }
  return cur;
}

void _set(Map<String, dynamic> root, List<Object> path, Object? value) {
  Object? child(Object? existing, Object key) {
    if (key is int) {
      // 数组下标：容器必须是 List；不存在/类型不对就造一个定长 null 列表。
      // mieru 的 portBindings 只会写到 [0]，无需扩容语义。
      if (existing is List && existing.length > key) return existing;
      return List<dynamic>.filled(key + 1, null);
    }
    if (existing is Map<String, dynamic>) return existing;
    if (existing is Map) return Map<String, dynamic>.from(existing);
    return <String, dynamic>{};
  }

  Object cur = root;
  for (var i = 0; i < path.length - 1; i++) {
    final key = path[i];
    final nextKey = path[i + 1];
    if (key is int) {
      final list = cur as List<dynamic>;
      final existing = list[key] as Object?;
      if (existing == null || _isEmptyContainerFor(existing, nextKey)) {
        list[key] = child(existing, nextKey);
      }
      cur = list[key] as Object;
    } else {
      final map = cur as Map<String, dynamic>;
      final existing = map[key] as Object?;
      if (existing == null || _isEmptyContainerFor(existing, nextKey)) {
        map[key as String] = child(existing, nextKey);
      }
      cur = map[key] as Object;
    }
  }
  final last = path.last;
  if (last is int) {
    (cur as List<dynamic>)[last] = value;
  } else {
    (cur as Map<String, dynamic>)[last as String] = value;
  }
}

/// [existing] 是中间节点、[nextKey] 是下一个键：判断 existing 是不是"没内容"，
/// 需要被 child 重建（mieru 的 null 数组元素、旧空对象等）。
bool _isEmptyContainerFor(Object existing, Object nextKey) {
  if (nextKey is int) return existing is! List || (existing.length <= nextKey && existing.isEmpty);
  return existing is! Map;
}

void _remove(Map<String, dynamic> root, List<Object> path) {
  Object? cur = root;
  for (var i = 0; i < path.length - 1; i++) {
    final key = path[i];
    if (key is int) {
      if (cur is! List || key >= cur.length) return;
      cur = cur[key];
    } else if (cur is! Map) {
      return;
    } else {
      cur = cur[key];
    }
  }
  final last = path.last;
  if (last is int) {
    if (cur is List && last < cur.length) cur[last] = null;
  } else if (cur is Map) {
    cur.remove(last);
  }
}

/// 递归删掉 [root] 在 [container] 之下的空 Map（保留容器自身）。
void _pruneEmptyMaps(Map<String, dynamic> root, List<Object> container) {
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

bool _startsWith(List<Object> path, String container) {
  final parts = container.split('.');
  if (path.length < parts.length) return false;
  for (var i = 0; i < parts.length; i++) {
    if (path[i].toString() != parts[i]) return false;
  }
  return true;
}

/// 标量（String/int/bool/null）的比较表示 —— writeValues 反查用。
String _reprScalar(Object? value) {
  if (value == null) return 'null';
  if (value is String) return value;
  return value.toString();
}

String _stringify(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  if (value is List) return [for (final item in value) _stringify(item)].where((e) => e.isNotEmpty).join(',');
  return '';
}
