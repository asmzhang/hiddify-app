import 'dart:convert';

import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

/// Batch 13: Dart RouteRule -> hiddify-core HiddifyOptions "rules" JSON.
///
/// Go side contract (v2/config/route_rules.go, do not change unilaterally):
/// - HiddifyOptions top-level key: "rules" (Go json tag of HiddifyOptions.Rules).
/// - Each rule entry uses the Go json tags of v2/config/route_rule.pb.go:
///   plural keys ("rule_sets", "package_names", ...) and NUMERIC enum values.
///
/// `toProto3Json()` was unusable here: it emits proto3 JSON (singular keys +
/// enum names), which Go json.Unmarshal silently drops for [Rule] because the
/// pb.go struct tags are plural. That was exactly why upstream commented out
/// the whole consumer in builder.go.
///
/// Empty list => send "rules": [] — still a no-op on the Go side because
/// makeUserRouteRules iterates an empty slice, but the contract stays explicit.
Map<String, dynamic> routeRuleToCoreJson(final List<Rule> rules) {
  return {
    'rules': [for (final rule in rules) _ruleToCoreJson(rule)],
  };
}

Map<String, dynamic> _ruleToCoreJson(final Rule rule) {
  final json = <String, dynamic>{};

  // Scalars: only emit when explicitly set, so the payload stays clean and
  // matches what the Go unmarshal target actually consumes.
  if (rule.hasListOrder()) json['list_order'] = rule.listOrder;
  if (rule.enabled) json['enabled'] = true;
  if (rule.name.isNotEmpty) json['name'] = rule.name;

  // outbound / network: numeric proto enum values (Route_rule.pb.go contract).
  // hasOutbound() is false unless the UI set it explicitly.
  if (rule.hasOutbound()) json['outbound'] = rule.outbound.value;
  if (rule.hasNetwork() && rule.network != Network.all) {
    json['network'] = rule.network.value;
  }

  // Repeated string fields: emit only when non-empty, with the PLURAL Go tags.
  void addStrings(String key, Iterable<String> values) {
    if (values.isNotEmpty) json[key] = values.toList();
  }

  addStrings('rule_sets', rule.ruleSets);
  addStrings('package_names', rule.packageNames);
  addStrings('process_names', rule.processNames);
  addStrings('process_paths', rule.processPaths);
  addStrings('port_ranges', rule.portRanges);
  addStrings('source_port_ranges', rule.sourcePortRanges);
  addStrings('ip_cidrs', rule.ipCidrs);
  addStrings('source_ip_cidrs', rule.sourceIpCidrs);
  addStrings('domains', rule.domains);
  addStrings('domain_suffixes', rule.domainSuffixes);
  addStrings('domain_keywords', rule.domainKeywords);
  addStrings('domain_regexes', rule.domainRegexes);

  if (rule.protocols.isNotEmpty) {
    json['protocols'] = [for (final p in rule.protocols) p.value];
  }

  return json;
}

/// Inverse mapping, for round-tripping: core JSON -> Rule messages. Used by
/// the "import rules" flow so hand-edited payloads survive the exact contract
/// instead of proto3 JSON.
List<Rule> coreJsonToRules(final Map<String, dynamic> json) {
  final rawRules = json['rules'];
  if (rawRules is! List) return const [];
  return [
    for (final entry in rawRules)
      if (entry is Map) _ruleFromCoreJson(Map<String, dynamic>.from(entry)),
  ];
}

Rule _ruleFromCoreJson(final Map<String, dynamic> json) {
  final rule = Rule();
  if (json['list_order'] is int) rule.listOrder = json['list_order'] as int;
  if (json['enabled'] == true) rule.enabled = true;
  if (json['name'] is String) rule.name = json['name'] as String;
  if (json['outbound'] is int) {
    final outbound = Outbound.valueOf(json['outbound'] as int);
    if (outbound != null) rule.outbound = outbound;
  }
  if (json['network'] is int) {
    final network = Network.valueOf(json['network'] as int);
    if (network != null) rule.network = network;
  }

  void readStrings(String key, void Function(List<String>) assign) {
    final value = json[key];
    if (value is List && value.isNotEmpty) {
      assign([for (final item in value) if (item is String) item]);
    }
  }

  readStrings('rule_sets', (v) => rule.ruleSets.addAll(v));
  readStrings('package_names', (v) => rule.packageNames.addAll(v));
  readStrings('process_names', (v) => rule.processNames.addAll(v));
  readStrings('process_paths', (v) => rule.processPaths.addAll(v));
  readStrings('port_ranges', (v) => rule.portRanges.addAll(v));
  readStrings('source_port_ranges', (v) => rule.sourcePortRanges.addAll(v));
  readStrings('ip_cidrs', (v) => rule.ipCidrs.addAll(v));
  readStrings('source_ip_cidrs', (v) => rule.sourceIpCidrs.addAll(v));
  readStrings('domains', (v) => rule.domains.addAll(v));
  readStrings('domain_suffixes', (v) => rule.domainSuffixes.addAll(v));
  readStrings('domain_keywords', (v) => rule.domainKeywords.addAll(v));
  readStrings('domain_regexes', (v) => rule.domainRegexes.addAll(v));

  if (json['protocols'] is List) {
    for (final p in json['protocols'] as List) {
      if (p is int) {
        final protocol = Protocol.valueOf(p);
        if (protocol != null) rule.protocols.add(protocol);
      }
    }
  }
  return rule;
}

/// Convenience for the export/import flows that pass through plain strings.
String routeRuleToCoreJsonString(final List<Rule> rules) =>
    jsonEncode(routeRuleToCoreJson(rules));
