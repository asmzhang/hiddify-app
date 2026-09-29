import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/data/node_import.dart';
import 'package:hiddify/features/proxy/data/proxy_entity_import.dart';

void main() {
  group('classifyNodeImportInput', () {
    test('接受明确离线节点 scheme 的多链接输入', () {
      final result = classifyNodeImportInput('vless://id@example.com:443#A\nss://payload@example.com:8388#B');
      expect(result, isA<NodeImportLinks>());
      expect((result as NodeImportLinks).candidateCount, 2);
      expect(result.content.split('\n'), hasLength(2));
    });

    test('整包 base64 先解码再分类', () {
      final bundle = base64Encode(utf8.encode('trojan://pass@example.com:443#T'));
      final result = classifyNodeImportInput(bundle);
      expect(result, isA<NodeImportLinks>());
      expect((result as NodeImportLinks).candidateCount, 1);
    });

    test('HTTP(S) 明确走订阅入口，不交给 Core Parse 当 HTTP 节点', () {
      final result = classifyNodeImportInput('https://example.com/sub?id=1');
      expect(result, isA<NodeImportSubscription>());
      expect((result as NodeImportSubscription).url, 'https://example.com/sub?id=1');
    });

    test('拒绝混合订阅与节点、网络型 ssconf 和 chain detour', () {
      expect(
        classifyNodeImportInput('https://example.com/sub\nvless://id@example.com:443'),
        isA<NodeImportInvalid>().having((e) => e.reason, 'reason', NodeImportInvalidReason.mixed),
      );
      expect(
        classifyNodeImportInput('ssconf://example.com/config'),
        isA<NodeImportInvalid>().having((e) => e.reason, 'reason', NodeImportInvalidReason.unsupported),
      );
      expect(
        classifyNodeImportInput('vless://id@example.com:443?x=1&&detour=ss://payload@example.com:8388'),
        isA<NodeImportInvalid>().having((e) => e.reason, 'reason', NodeImportInvalidReason.chain),
      );
    });
    test('JSON 单出站/数组规范化，Clash YAML 与 WireGuard INI 识别为结构化输入', () {
      final single = classifyNodeImportInput(
        '{"type":"vless","tag":"A","server":"example.com","server_port":443,"uuid":"id"}',
      );
      expect(single, isA<NodeImportStructured>());
      expect(jsonDecode((single as NodeImportStructured).content), containsPair('outbounds', isA<List>()));

      final array = classifyNodeImportInput('[{"type":"wireguard","tag":"WG","peers":[]}]');
      expect(array, isA<NodeImportStructured>());
      expect(jsonDecode((array as NodeImportStructured).content), containsPair('endpoints', isA<List>()));

      expect(
        classifyNodeImportInput(
          'proxies:\n  - {name: A, type: ss, server: x, port: 1, cipher: aes-128-gcm, password: p}',
        ),
        isA<NodeImportStructured>(),
      );
      expect(
        classifyNodeImportInput(
          '[Interface]\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = pub\nEndpoint = wg.example.com:51820',
        ),
        isA<NodeImportStructured>(),
      );
    });

    test('ZIP 逐文件解码；普通文件保持单文本', () {
      final a = utf8.encode('vless://id@example.com:443#A');
      final b = utf8.encode('ss://payload@example.com:8388#B');
      final archive = Archive()
        ..addFile(ArchiveFile('a.txt', a.length, a))
        ..addFile(ArchiveFile('nested/b.txt', b.length, b));
      final zip = ZipEncoder().encodeBytes(archive);
      final decoded = decodeNodeImportFile('nodes.ZIP', Uint8List.fromList(zip));
      expect(decoded, hasLength(2));
      expect(decoded![0].name, 'a.txt');
      expect(decoded[0].content, startsWith('vless://'));
      expect(decoded[1].name, 'nested/b.txt');
      expect(decoded[1].content, startsWith('ss://'));

      final plain = decodeNodeImportFile('nodes.yaml', Uint8List.fromList(utf8.encode('proxies:\n')));
      expect(plain, hasLength(1));
      expect(plain!.single.name, 'nodes.yaml');
      expect(plain.single.content, 'proxies:');
      expect(decodeNodeImportFile('empty.zip', Uint8List.fromList(ZipEncoder().encodeBytes(Archive()))), isNull);
    });
  });

  group('extractProxyEntitiesFromConfig', () {
    test('独立抽取 outbounds，过滤内部项并保留内部 tag 身份', () {
      final entities = extractProxyEntitiesFromConfig('''
        {"outbounds":[
          {"type":"selector","tag":"select","outbounds":["Node § 0"]},
          {"type":"vless","tag":"Node § 0","server":"example.com","server_port":443,"uuid":"id"}
        ]}
      ''')!;
      expect(entities, hasLength(1));
      expect(entities.single.tag, 'Node § 0');
      expect(entities.single.displayName, 'Node');
      expect(entities.single.type, 'vless');
    });

    test('WireGuard INI 使用文件名作为 tag/displayName 并同步 payload tag', () {
      const ini = '[Interface]\nPrivateKey = private\nAddress = 10.0.0.2/32';
      const entityJson = '{"type":"wireguard","tag":"wiregaurd","address":["10.0.0.2/32"],"peers":[]}';
      final renamed = applyWireGuardFileName(
        const [ImportedProxyEntity(tag: 'wiregaurd', type: 'wireguard', payload: entityJson, displayName: 'wiregaurd')],
        fileName: 'nested/my-tunnel.conf',
        sourceContent: ini,
      );
      expect(wireGuardNameFromFile(r'nested\other.conf'), 'other');
      expect(renamed.single.tag, 'my-tunnel');
      expect(renamed.single.displayName, 'my-tunnel');
      expect(jsonDecode(renamed.single.payload), containsPair('tag', 'my-tunnel'));
    });

    test('endpoint-only WireGuard 配置也能抽取', () {
      final entities = extractProxyEntitiesFromConfig('''
        {"endpoints":[
          {"type":"wireguard","tag":"WG § 0","address":["10.0.0.2/32"],"peers":[{"address":"wg.example.com","port":51820,"public_key":"pub"}]}
        ]}
      ''')!;
      expect(entities, hasLength(1));
      expect(entities.single.type, 'wireguard');
      expect(entities.single.displayName, 'WG');
    });
  });
}
