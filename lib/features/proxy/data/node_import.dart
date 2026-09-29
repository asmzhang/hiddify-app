import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';
import 'package:hiddify/features/proxy/data/proxy_entity_import.dart';
import 'package:hiddify/features/proxy/data/runtime_outbound_tags.dart';

/// Configuration 页剪贴板/扫码/文件的安全分类结果。
sealed class NodeImportInput {
  const NodeImportInput();
}

class NodeImportLinks extends NodeImportInput {
  const NodeImportLinks(this.content, this.candidateCount);
  final String content;
  final int candidateCount;
}

class NodeImportStructured extends NodeImportInput {
  const NodeImportStructured(this.content);
  final String content;
}

class NodeImportSubscription extends NodeImportInput {
  const NodeImportSubscription(this.url);
  final String url;
}

class NodeImportInvalid extends NodeImportInput {
  const NodeImportInvalid(this.reason);
  final NodeImportInvalidReason reason;
}

enum NodeImportInvalidReason { empty, unsupported, mixed, chain }

sealed class NodeImportOutcome {
  const NodeImportOutcome();
}

class NodeImportSucceeded extends NodeImportOutcome {
  const NodeImportSucceeded(this.count);
  final int count;
}

class NodeImportNeedsSubscription extends NodeImportOutcome {
  const NodeImportNeedsSubscription(this.url);
  final String url;
}

class NodeImportFailed extends NodeImportOutcome {
  const NodeImportFailed(this.reason);
  final NodeImportFailureReason reason;
}

enum NodeImportFailureReason { invalidInput, parseFailed, partialParse, database }

/// 第一阶段只允许完全离线、无歧义且不会触发核心网络请求的标准节点 scheme。
const nodeImportSchemes = <String>{
  'vmess',
  'vless',
  'trojan',
  'svmess',
  'svless',
  'strojan',
  'ss',
  'tuic',
  'hysteria',
  'hysteria2',
  'hy2',
  'anytls',
  'ssh',
  'naive',
  'socks',
  'phttp',
  'phttps',
  'xvmess',
  'xvless',
  'xtrojan',
  'mieru',
  'mierus',
  'psiphon',
  'wg',
  'wireguard',
  'warp',
  'awg',
};

String? _normalizeStructuredInput(String text) {
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      if (decoded['outbounds'] is List || decoded['endpoints'] is List) return jsonEncode(decoded);
      final type = decoded['type'];
      if (type is String) {
        return jsonEncode({
          isNodeEndpoint(type) ? 'endpoints' : 'outbounds': [decoded],
        });
      }
      return null;
    }
    if (decoded is List) {
      final outbounds = <Map<String, dynamic>>[];
      final endpoints = <Map<String, dynamic>>[];
      for (final item in decoded.whereType<Map<String, dynamic>>()) {
        final type = item['type'];
        if (type is! String) continue;
        (isNodeEndpoint(type) ? endpoints : outbounds).add(item);
      }
      if (outbounds.isEmpty && endpoints.isEmpty) return null;
      return jsonEncode({
        if (outbounds.isNotEmpty) 'outbounds': outbounds,
        if (endpoints.isNotEmpty) 'endpoints': endpoints,
      });
    }
  } catch (_) {
    // Not JSON; Clash/WireGuard detection follows.
  }
  if (RegExp(r'^\s*proxies\s*:', multiLine: true).hasMatch(text) || text.contains('[Interface]')) return text;
  return null;
}

NodeImportInput classifyNodeImportInput(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return const NodeImportInvalid(NodeImportInvalidReason.empty);
  if (!text.contains('://')) {
    try {
      final decoded = utf8.decode(base64Decode(base64.normalize(text))).trim();
      if (decoded.contains('://') || _normalizeStructuredInput(decoded) != null) text = decoded;
    } catch (_) {
      // Not a whole-bundle base64 input; normal classification below reports unsupported.
    }
  }

  final structured = _normalizeStructuredInput(text);
  if (structured != null) return NodeImportStructured(structured);

  final tokens = text.split(RegExp(r'\s+')).where((token) => token.isNotEmpty).toList();
  if (tokens.isEmpty) return const NodeImportInvalid(NodeImportInvalidReason.empty);
  var nodeCount = 0;
  String? subscription;
  for (final token in tokens) {
    if (token.contains('&&detour=') || token == '->') {
      return const NodeImportInvalid(NodeImportInvalidReason.chain);
    }
    final uri = Uri.tryParse(token);
    if (uri == null || !uri.hasScheme) return const NodeImportInvalid(NodeImportInvalidReason.unsupported);
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' ||
        scheme == 'https' ||
        scheme == 'ftp' ||
        scheme == 'hiddify' ||
        scheme == 'v2ray' ||
        scheme == 'v2rayn' ||
        scheme == 'v2rayng' ||
        scheme == 'clash' ||
        scheme == 'clashmeta' ||
        scheme == 'sing-box') {
      subscription ??= token;
      continue;
    }
    if (!nodeImportSchemes.contains(scheme)) {
      return const NodeImportInvalid(NodeImportInvalidReason.unsupported);
    }
    nodeCount++;
  }
  if (subscription != null && nodeCount > 0) return const NodeImportInvalid(NodeImportInvalidReason.mixed);
  if (subscription != null) return NodeImportSubscription(subscription);
  return NodeImportLinks(tokens.join('\n'), nodeCount);
}

class NodeImportFileEntry {
  const NodeImportFileEntry({required this.name, required this.content});
  final String name;
  final String content;
}

List<NodeImportFileEntry>? decodeNodeImportFile(String fileName, Uint8List bytes) {
  try {
    if (!fileName.toLowerCase().endsWith('.zip')) {
      final text = utf8.decode(bytes).trim();
      return text.isEmpty ? null : [NodeImportFileEntry(name: fileName, content: text)];
    }

    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final entries = <NodeImportFileEntry>[];
    for (final file in archive.files) {
      if (!file.isFile || file.isSymbolicLink) continue;
      final data = file.readBytes();
      if (data == null) return null;
      final text = utf8.decode(data).trim();
      if (text.isNotEmpty) entries.add(NodeImportFileEntry(name: file.name, content: text));
    }
    return entries.isEmpty ? null : entries;
  } catch (_) {
    return null;
  }
}

String wireGuardNameFromFile(String fileName) {
  final normalized = fileName.replaceAll('\\', '/');
  final baseName = normalized.split('/').last;
  return baseName.endsWith('.conf') ? baseName.substring(0, baseName.length - 5) : baseName;
}

List<ImportedProxyEntity> applyWireGuardFileName(
  List<ImportedProxyEntity> entities, {
  required String fileName,
  required String sourceContent,
}) {
  if (!sourceContent.contains('[Interface]')) return entities;
  final name = wireGuardNameFromFile(fileName);
  if (name.isEmpty || entities.length != 1 || !isNodeEndpoint(entities.single.type)) return entities;
  final source = entities.single;
  final decoded = jsonDecode(source.payload);
  if (decoded is! Map<String, dynamic>) return entities;
  decoded['tag'] = name;
  return [
    ImportedProxyEntity(
      tag: name,
      type: source.type,
      payload: jsonEncode(decoded),
      displayName: name,
      customOutbound: source.customOutbound,
      customConfig: source.customConfig,
    ),
  ];
}

/// ParseResponse.content → 手动节点实体。outbounds/endpoints 独立扫描，支持 endpoint-only。
List<ImportedProxyEntity>? extractProxyEntitiesFromConfig(String configJson) {
  try {
    final config = jsonDecode(configJson);
    if (config is! Map<String, dynamic>) return null;
    final entities = <ImportedProxyEntity>[];
    void addBucket(Object? raw, {required bool endpoints}) {
      if (raw is! List) return;
      for (final item in raw.whereType<Map<String, dynamic>>()) {
        final tag = item['tag'];
        final type = item['type'];
        if (tag is! String || type is! String || tag.isEmpty) continue;
        final valid = endpoints ? isNodeEndpoint(type) : isNodeOutbound(tag: tag, type: type);
        if (!valid) continue;
        entities.add(
          ImportedProxyEntity(tag: tag, type: type, payload: jsonEncode(item), displayName: trimTagName(tag)),
        );
      }
    }

    addBucket(config['outbounds'], endpoints: false);
    addBucket(config['endpoints'], endpoints: true);
    return entities.isEmpty ? null : entities;
  } catch (_) {
    return null;
  }
}
