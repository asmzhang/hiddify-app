/// 出站 JSON → **标准分享链接**（纯 Dart，不依赖 Flutter，可被 `dart run` 校验）。
///
/// 这是 hiddify 侧缺失的"逆向转换"：ray2sing 只有 链接 → 出站（订阅导入方向），
/// 本文件补 出站 → 链接（节点分享方向），让节点卡的「分享」能给出可粘贴到
/// 其它客户端（NekoBox / v2rayN / Shadowrocket …）的标准链接，而不是一段 JSON。
///
/// ## 规格来源（两份，缺一不可）
///
/// **生成端准绳 = NekoBox 的 `fmt/*Fmt.kt` toUri**（本项目 UI 规格源，它就是
/// "标准链接"的定义者）：
/// - `shadowsocks/ShadowsocksFmt.kt` —— `ss://b64(method:password)@host:port`
///   + `plugin=`（**SIP003 合并式**：`name;opts` 一个参数）；userinfo 用
///   标准 base64（见 `_shadowsocks` 注释）
/// - `v2ray/V2RayFmt.kt` —— vless/trojan（ducksoft query 形态）、
///   `vmess://b64(json{v:2,...})`
/// - `hysteria/HysteriaFmt.kt` —— `hy2://`（auth 拆 `user:pass`）
/// - `tuic/TuicFmt.kt` —— `tuic://uuid:token?congestion_control&...`
/// - `socks/SOCKSFmt.kt` + `http/HTTPFmt.kt`
///
/// **验收端 = hiddify 内核自带的 ray2sing**（`hiddify-core/ray2sing/ray2sing/*.go`，
/// 本应用订阅导入用的就是它）。生成 → 用它解析 → 出站等价（往返幂等），
/// 由 `tool/check_outbound_to_link.dart` 用真实解析端断言。
///
/// ## 两端键名不一致处的既定决策（推导见各协议注释）
///
/// - **socks 用 `socks://`**：ray2sing 的分发表只有 `socks://`（不认 `socks5://`），
///   而 NekoBox 的链接分发（`ktx/Formats.kt:125`）`socks://` 也接受 ⇒ 取交集。
/// - **tuic 的 congestion/udp-relay/allow-insecure 参数双写**
///   （`congestion_control` + `congestionControl`）：ray2sing 按归一化键
///   `congestioncontrol` 取参（`_`/`-` 会归一成空格，下划线键它反而读不到），
///   NekoBox 只读下划线键；双写让两端都拿到值，多余键双方都忽略。
/// - **ws 早数据**：`max_early_data` 写进 path 的 `?ed=`（两端约定的唯一载体）。
/// - **不写入链接的字段**（ray2sing 不读、真实订阅罕见，写了解析端也丢）：
///   hysteria2 的 `server_ports`（端口跳跃）/ `up/down_mbps`、http 伪装的
///   自定义 method、ws 自定义 header（Host 除外）。
/// - **已知解析端损耗**（链接无损、ray2sing 产物有损，check 工具里白名单豁免）：
///   ss 的 plugin opts（SIP003 合并值被整塞进 plugin 字段）、
///   tuic 的 alpn（恒被换成默认值）、hy2 的 obfs-password（ray2sing 用含 `-`
///   的字面键取参，而参数键归一化后 `-` 变空格，永远查不到）。
library;

import 'dart:convert';

import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';

// ───────────────────────────────────────────────────────────────────────────
// 入口
// ───────────────────────────────────────────────────────────────────────────

/// 支持生成链接的出站类型（与上方文档一一对应）。
const _supportedOutboundTypes = {
  'shadowsocks',
  'vless',
  'vmess',
  'trojan',
  'hysteria2',
  'tuic',
  'socks',
  'http',
};

/// 把一条 sing-box 出站定义转成分享链接；不支持/字段残缺时返回 null
/// （调用方回落到"复制出站 JSON"，不丢功能）。
String? outboundToLink(Map<String, dynamic> outbound) {
  try {
    final type = outbound['type'];
    if (type is! String || !_supportedOutboundTypes.contains(type)) return null;
    final server = _str(outbound, 'server');
    final port = _int(outbound, 'server_port');
    if (server == null || server.isEmpty) return null;
    if (port == null || port <= 0 || port > 65535) return null;
    // 分享名用显示名：tag 可能带实体层的 " § n" 内部后缀（同内核 TrimTagName 口径）
    final rawTag = _str(outbound, 'tag');
    final tag = rawTag == null ? '' : trimTagName(rawTag);

    switch (type) {
      case 'shadowsocks':
        return _shadowsocks(outbound, server, port, tag);
      case 'vless':
        return _vless(outbound, server, port, tag);
      case 'vmess':
        return _vmess(outbound, server, port, tag);
      case 'trojan':
        return _trojan(outbound, server, port, tag);
      case 'hysteria2':
        return _hysteria2(outbound, server, port, tag);
      case 'tuic':
        return _tuic(outbound, server, port, tag);
      case 'socks':
        return _socks(outbound, server, port, tag);
      case 'http':
        return _http(outbound, server, port, tag);
    }
    return null;
  } catch (_) {
    return null;
  }
}

// ───────────────────────────────────────────────────────────────────────────
// 各协议
// ───────────────────────────────────────────────────────────────────────────

/// `ss://b64url(method:password)@host:port?plugin=…#name`
///
/// userinfo 必须 base64：ray2sing（`ParseUrl`）对"纯 base64 字符的 username"
/// 才尝试拆 `method:password`，明文放进去会被当成 `method=none` 的裸密码。
/// 用**标准 base64**（含 `+/=`）而非 url-safe：ray2sing 的探测正则是
/// `^[A-Za-z0-9+/=]+$`，url-safe 的 `-_` 会让它放弃解码（v2rayN 生态同样
/// 用标准 base64）。plugin 按 SIP003 合并式（NekoBox `ShadowsocksBean.plugin`
/// 就是 `name;opts` 合并存储，toUri 原样发出）；opts 为空时合并值即裸插件名，
/// 此时 ray2sing 也能完整等价还原。
String? _shadowsocks(Map<String, dynamic> o, String server, int port, String tag) {
  final method = _str(o, 'method');
  final password = _str(o, 'password');
  if (method == null || method.isEmpty) return null;
  if (password == null) return null;
  final userinfo = base64.encode(utf8.encode('$method:$password'));

  final query = <String, String>{};
  final plugin = _str(o, 'plugin');
  if (plugin != null && plugin.isNotEmpty) {
    final opts = _str(o, 'plugin_opts');
    // SIP003：name;opts 合并在一个参数里
    query['plugin'] = (opts != null && opts.isNotEmpty) ? '$plugin;$opts' : plugin;
  }
  return _link('ss', userinfo, server, port, query, tag);
}

/// `vless://uuid@host:port?encryption=none&security=…&type=…#name`（ducksoft 形态）
String? _vless(Map<String, dynamic> o, String server, int port, String tag) {
  final uuid = _str(o, 'uuid');
  if (uuid == null || uuid.isEmpty) return null;
  final query = <String, String>{'encryption': 'none'};
  _putIfPresent(query, 'flow', _str(o, 'flow'));
  _putIfPresent(query, 'packetEncoding', _str(o, 'packet_encoding'));
  _tlsParams(query, o);
  _transportParams(query, o);
  _muxParams(query, o);
  return _link('vless', _userInfo(uuid), server, port, query, tag);
}

/// `trojan://password@host:port?security=tls&…#name`
///
/// trojan 的密码放 userinfo（ray2sing `TrojanSingbox`：`Password = u.Username`）。
String? _trojan(Map<String, dynamic> o, String server, int port, String tag) {
  final password = _str(o, 'password');
  if (password == null || password.isEmpty) return null;
  final query = <String, String>{};
  _tlsParams(query, o);
  _transportParams(query, o);
  _muxParams(query, o);
  return _link('trojan', _userInfo(password), server, port, query, tag);
}

/// `vmess://b64url(json{v:"2",ps,add,port,id,aid,scy,net,type,host,path,tls,…})`
/// （v2rayN 形态；ray2sing `decodeVmess` 从第 8 个字符起解 base64 再解 JSON）。
///
/// `net` 用 sing-box 的 transport type 原名（含 `http`）。v2rayN 传统上把
/// "TCP+HTTP 伪装+TLS" 写作 `h2`，但 ray2sing 只认 `http`（`h2` 会直接
/// "unknown transport type" 报错）——自家解析端等价优先，且 h2 伪装已淘汰。
String? _vmess(Map<String, dynamic> o, String server, int port, String tag) {
  final uuid = _str(o, 'uuid');
  if (uuid == null || uuid.isEmpty) return null;
  final transport = _map(o, 'transport');
  final tls = _map(o, 'tls');
  final security = _str(o, 'security');
  final json = <String, dynamic>{
    'v': '2',
    'ps': tag,
    'add': server,
    'port': port,
    'id': uuid,
    'aid': _int(o, 'alter_id') ?? 0,
    'scy': (security != null && security.isNotEmpty) ? security : 'auto',
    // net/type/host/path 的取值与 _transportParams 同一张映射表（JSON 版）
    'net': _str(transport, 'type') ?? 'tcp',
    'type': '',
    'host': _transportHost(transport) ?? '',
    'path': _transportPath(transport) ?? '',
    'tls': tls?['enabled'] == true ? 'tls' : '',
    'sni': _str(tls, 'server_name') ?? '',
    'alpn': _joinList(_list(tls, 'alpn')) ?? '',
    'fp': _utlsFingerprint(tls) ?? '',
  };
  final reality = _map(tls, 'reality');
  if (reality?['enabled'] == true) {
    // ray2sing 的 getTLSOptions 从扁平键读 reality
    json['security'] = 'reality';
    json['pbk'] = _str(reality, 'public_key') ?? '';
    json['sid'] = _str(reality, 'short_id') ?? '';
  }
  return 'vmess://${b64UrlNoPad(jsonEncode(json))}';
}

/// `hy2://user:pass@host:port?sni=…&obfs=salamander&obfs-password=…&insecure=1#name`
///
/// auth（sing-box `password`）含 `:` 时拆成 user:pass（NekoBox 同规则，
/// ray2sing 用 `username + ":" + password` 拼回）。
String? _hysteria2(Map<String, dynamic> o, String server, int port, String tag) {
  final password = _str(o, 'password');
  if (password == null) return null;
  var user = password;
  var pass = '';
  final i = password.indexOf(':');
  if (i >= 0) {
    user = password.substring(0, i);
    pass = password.substring(i + 1);
  }
  final query = <String, String>{};
  final tls = _map(o, 'tls');
  final sni = _str(tls, 'server_name');
  if (sni != null && sni.isNotEmpty) query['sni'] = sni;
  if (tls?['insecure'] == true) query['insecure'] = '1';
  final obfs = _map(o, 'obfs');
  final obfsType = _str(obfs, 'type');
  if (obfsType != null && obfsType.isNotEmpty) {
    query['obfs'] = obfsType;
    final obfsPassword = _str(obfs, 'password');
    if (obfsPassword != null && obfsPassword.isNotEmpty) query['obfs-password'] = obfsPassword;
  }
  return _link('hy2', _userInfo(user, password: pass), server, port, query, tag, colonSplitsUserinfo: true);
}

/// `tuic://uuid:token@host:port?congestion_control=…&…#name`
///
/// congestion/udp-relay/allow-insecure 三组参数**双写**（下划线版给 NekoBox、
/// 驼峰版给 ray2sing——它把参数键归一化成小写+空格分隔，下划线键读不到，
/// 见文件头"既定决策"）。
String? _tuic(Map<String, dynamic> o, String server, int port, String tag) {
  final uuid = _str(o, 'uuid');
  if (uuid == null || uuid.isEmpty) return null;
  final token = _str(o, 'password') ?? '';
  final query = <String, String>{};
  void putBoth(String underscored, String camel, String? value) {
    if (value != null && value.isNotEmpty) {
      query[underscored] = value;
      query[camel] = value;
    }
  }

  putBoth('congestion_control', 'congestionControl', _str(o, 'congestion_control'));
  putBoth('udp_relay_mode', 'udpRelayMode', _str(o, 'udp_relay_mode'));
  final tls = _map(o, 'tls');
  final sni = _str(tls, 'server_name');
  if (sni != null && sni.isNotEmpty) query['sni'] = sni;
  final alpn = _joinList(_list(tls, 'alpn'));
  if (alpn != null && alpn.isNotEmpty) query['alpn'] = alpn;
  if (tls?['insecure'] == true) {
    query['allow_insecure'] = '1';
    query['allowInsecure'] = '1';
  }
  if (o['disable_sni'] == true) query['disable_sni'] = '1';
  return _link('tuic', _userInfo(uuid, password: token), server, port, query, tag, colonSplitsUserinfo: true);
}

/// `socks://user:pass@host:port#name`
///
/// scheme 用 `socks://` 而非事实标准的 `socks5://`：ray2sing 的分发表只有
/// `socks://`（`socks5://` 前缀匹配不上、直接"不支持"），而 NekoBox 的链接
/// 分发对 `socks://` 也接受（`ktx/Formats.kt:125`）。版本无需携带——两端
/// 缺省都是 v5。
String _socks(Map<String, dynamic> o, String server, int port, String tag) {
  final username = _str(o, 'username') ?? '';
  final password = _str(o, 'password') ?? '';
  return _link('socks', _userInfo(username, password: password), server, port, const {}, tag,
      colonSplitsUserinfo: true);
}

/// `http://user:pass@host:port?sni=…&insecure=1#name`；带 TLS 时 scheme = `https`。
///
/// ray2sing 对 `http://` 的 TLS 判据是"出现 tls/sni/insecure 任一参数"，
/// `https://` 恒开 TLS——scheme 本身就是 TLS 的载体，sni/insecure 走参数。
String _http(Map<String, dynamic> o, String server, int port, String tag) {
  final username = _str(o, 'username') ?? '';
  final password = _str(o, 'password') ?? '';
  final tls = _map(o, 'tls');
  final query = <String, String>{};
  final sni = _str(tls, 'server_name');
  if (sni != null && sni.isNotEmpty) query['sni'] = sni;
  if (tls?['insecure'] == true) query['insecure'] = '1';
  _putIfPresent(query, 'path', _str(o, 'path'));
  final scheme = tls?['enabled'] == true ? 'https' : 'http';
  return _link(scheme, _userInfo(username, password: password), server, port, query, tag,
      colonSplitsUserinfo: true);
}

// ───────────────────────────────────────────────────────────────────────────
// TLS / 传输层 / mux 参数（vless、trojan 的 query 共用；vmess 走 JSON 字段）
// ───────────────────────────────────────────────────────────────────────────

/// ducksoft TLS 参数：`security`/`sni`/`fp`/`alpn`/`allowInsecure`/`pbk`/`sid`。
///
/// 键名同时被 ray2sing 的归一化匹配与 NekoBox/v2rayN 生态接受：
/// `allowInsecure` 归一化后即 ray2sing 读的 `allowinsecure`。
void _tlsParams(Map<String, String> query, Map<String, dynamic> o) {
  final tls = _map(o, 'tls');
  if (tls == null || tls['enabled'] != true) return;
  final reality = _map(tls, 'reality');
  if (reality?['enabled'] == true) {
    query['security'] = 'reality';
    _putIfPresent(query, 'pbk', _str(reality, 'public_key'));
    _putIfPresent(query, 'sid', _str(reality, 'short_id'));
  } else {
    query['security'] = 'tls';
  }
  final sni = _str(tls, 'server_name');
  if (sni != null && sni.isNotEmpty) query['sni'] = sni;
  final fp = _utlsFingerprint(tls);
  if (fp != null && fp.isNotEmpty) query['fp'] = fp;
  final alpn = _joinList(_list(tls, 'alpn'));
  if (alpn != null && alpn.isNotEmpty) query['alpn'] = alpn;
  if (tls['insecure'] == true) query['allowInsecure'] = '1';
}

/// 传输层参数：`type`/`path`/`host`/`serviceName`/`mode`（grpc 用
/// `serviceName` —— ray2sing 在 path 缺省时读它，NekoBox/v2rayN 同名）。
///
/// ws 早数据：`max_early_data` 拼进 path 的 `?ed=`（ray2sing 只从 path query
/// 里取 `ed`；`early_data_header_name` 两端缺省同为 `Sec-WebSocket-Protocol`，
/// 无需携带）。
void _transportParams(Map<String, String> query, Map<String, dynamic> o) {
  final transport = _map(o, 'transport');
  final type = _str(transport, 'type');
  if (transport == null || type == null || type.isEmpty) return;
  query['type'] = type;
  switch (type) {
    case 'ws':
      _putWsPath(query, transport);
      final host = _transportHost(transport);
      if (host != null && host.isNotEmpty) query['host'] = host;
    case 'http':
      _putIfPresent(query, 'path', _str(transport, 'path'));
      final host = _transportHost(transport);
      if (host != null && host.isNotEmpty) query['host'] = host;
    case 'grpc':
      final serviceName = _str(transport, 'service_name');
      if (serviceName != null && serviceName.isNotEmpty) query['serviceName'] = serviceName;
    case 'httpupgrade':
      _putIfPresent(query, 'path', _str(transport, 'path'));
      final host = _transportHost(transport);
      if (host != null && host.isNotEmpty) query['host'] = host;
    case 'xhttp':
      _putIfPresent(query, 'path', _str(transport, 'path'));
      _putIfPresent(query, 'host', _str(transport, 'host'));
      _putIfPresent(query, 'mode', _str(transport, 'mode'));
    case 'quic':
      break; // 无参数
  }
}

/// ws 的 path + `?ed=`（`max_early_data` > 0 时）。
void _putWsPath(Map<String, String> query, Map<String, dynamic> transport) {
  var path = _str(transport, 'path') ?? '';
  final earlyData = _int(transport, 'max_early_data');
  if (earlyData != null && earlyData > 0) {
    path += path.contains('?') ? '&' : '?';
    path += 'ed=$earlyData';
  }
  if (path.isNotEmpty) query['path'] = path;
}

/// vless/trojan 通用的 mux 参数（ray2sing `getMuxOptions` 的键名：
/// `muxtype`/`muxmaxc`/`muxsmax`/`mux`/`muxpad`/`muxup`/`muxdown`）。
void _muxParams(Map<String, String> query, Map<String, dynamic> o) {
  final mux = _map(o, 'multiplex');
  final protocol = _str(mux, 'protocol');
  if (protocol == null || protocol.isEmpty) return;
  query['muxType'] = protocol;
  final maxConnections = _int(mux, 'max_connections');
  if (maxConnections != null && maxConnections > 0) query['muxMaxC'] = '$maxConnections';
  final maxStreams = _int(mux, 'max_streams');
  if (maxStreams != null && maxStreams > 0) query['muxSmax'] = '$maxStreams';
  final minStreams = _int(mux, 'min_streams');
  if (minStreams != null && minStreams > 0) query['mux'] = '$minStreams';
  if (mux?['padding'] == true) query['muxPad'] = 'true';
  final brutal = _map(mux, 'brutal');
  final up = _int(brutal, 'up_mbps');
  final down = _int(brutal, 'down_mbps');
  if (brutal?['enabled'] == true && up != null && down != null) {
    query['muxUp'] = '$up';
    query['muxDown'] = '$down';
  }
}

// ───────────────────────────────────────────────────────────────────────────
// 传输层字段的小工具（JSON 生成端也复用）
// ───────────────────────────────────────────────────────────────────────────

/// transport 的 host：sing-box 里 `headers.Host`（ws/httpupgrade，字符串或
/// 数组）与 `host`（http，数组）两种形态；多值取第一个（ray2sing 只收单值）。
String? _transportHost(Map<String, dynamic>? transport) {
  if (transport == null) return null;
  final headers = _map(transport, 'headers');
  final hostHeader = headers?['Host'] ?? headers?['host'];
  final fromHeaders = _firstOf(hostHeader);
  if (fromHeaders != null && fromHeaders.isNotEmpty) return fromHeaders;
  return _firstOf(transport['host']);
}

/// transport 的 path；grpc 的 `service_name` 也走这里（v2rayN JSON 约定把
/// serviceName 放 path 字段，ray2sing 在 path 缺省时回落 `serviceName` 参数，
/// 两条路都通）。
String? _transportPath(Map<String, dynamic>? transport) {
  if (transport == null) return null;
  final path = _str(transport, 'path');
  if (path != null && path.isNotEmpty) return path;
  final serviceName = _str(transport, 'service_name');
  return (serviceName == null || serviceName.isEmpty) ? null : serviceName;
}

String? _utlsFingerprint(Map<String, dynamic>? tls) {
  final utls = _map(tls, 'utls');
  if (utls?['enabled'] != true) return null;
  final fp = _str(utls, 'fingerprint');
  return (fp == null || fp.isEmpty) ? null : fp;
}

// ───────────────────────────────────────────────────────────────────────────
// 类型安全取值 + 通用小工具
// ───────────────────────────────────────────────────────────────────────────

String? _str(Map<String, dynamic>? o, String key) {
  final v = o?[key];
  return v is String ? v : null;
}

int? _int(Map<String, dynamic>? o, String key) {
  final v = o?[key];
  return v is int ? v : null;
}

List<String> _list(Map<String, dynamic>? o, String key) {
  final v = o?[key];
  if (v is List) return v.whereType<String>().toList();
  if (v is String) return [v];
  return const [];
}

Map<String, dynamic>? _map(Map<String, dynamic>? o, String key) {
  final v = o?[key];
  return v is Map<String, dynamic> ? v : null;
}

String? _joinList(List<String> items) {
  final nonEmpty = items.where((s) => s.isNotEmpty).toList();
  if (nonEmpty.isEmpty) return null;
  return nonEmpty.join(',');
}

String? _firstOf(Object? raw) {
  if (raw is String) return raw;
  if (raw is List) {
    for (final item in raw) {
      if (item is String && item.isNotEmpty) return item;
    }
  }
  return null;
}

void _putIfPresent(Map<String, String> query, String key, String? value) {
  if (value != null && value.isNotEmpty) query[key] = value;
}

/// base64url、去 padding（NekoBox `Util.b64EncodeUrlSafe`：
/// NO_PADDING | NO_WRAP | URL_SAFE）。
String b64UrlNoPad(String input) => base64Url.encode(utf8.encode(input)).replaceAll('=', '');

/// userinfo：密码为空时只放用户名（不产生尾随 `:`）。
String _userInfo(String username, {String password = ''}) =>
    password.isEmpty ? username : '$username:$password';

/// 组装链接。host 为 IPv6（含 `:`）时加方括号；query 手工拼接以保持插入
/// 顺序（Dart 的 queryParameters 语义一致但不保序，这里显式化）。
///
/// userinfo 的冒号处理（[colonSplitsUserinfo]）：
/// - **true**（user:pass 语义：hy2/tuic/socks/http）：user 与 pass 分别转义、
///   中间放**裸冒号** —— Go `url.Parse` 在解码前按裸冒号分隔 userinfo，
///   编码过的 `%3A` 不会成为分隔符；这样两端都拿到分离的 user/pass。
/// - **false**（整体承载：vless uuid / trojan password / ss base64）：
///   整体转义（内含的 `:` 变 `%3A`，Go 端解码后原样保留在 Username 里，
///   不被拆开 —— trojan 密码含冒号时必须走这条路）。
String _link(
  String scheme,
  String userinfo,
  String server,
  int port,
  Map<String, String> query,
  String tag, {
  bool colonSplitsUserinfo = false,
}) {
  final host = server.contains(':') ? '[$server]' : server;
  final buffer = StringBuffer('$scheme://');
  if (userinfo.isNotEmpty) {
    if (colonSplitsUserinfo && userinfo.contains(':')) {
      final i = userinfo.indexOf(':');
      buffer
        ..write(Uri.encodeComponent(userinfo.substring(0, i)))
        ..write(':')
        ..write(Uri.encodeComponent(userinfo.substring(i + 1)));
    } else {
      buffer.write(Uri.encodeComponent(userinfo));
    }
    buffer.write('@');
  }
  buffer.write('$host:$port');
  if (query.isNotEmpty) {
    // 键值都用 application/x-www-form-urlencoded 转义（NekoBox 的 okhttp
    // builder 同样保序、同样转义）
    final encoded = query.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    buffer.write('?$encoded');
  }
  if (tag.isNotEmpty) buffer.write('#${Uri.encodeComponent(tag)}');
  return buffer.toString();
}
