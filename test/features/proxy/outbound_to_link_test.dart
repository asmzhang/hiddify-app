import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/data/outbound_to_link.dart';

void main() {
  test('AnyTLS outbound -> NekoBox 标准分享链接', () {
    final link = outboundToLink({
      'type': 'anytls',
      'tag': 'AnyTLS 节点',
      'server': 'any.example.com',
      'server_port': 443,
      'password': 'p@ss:word',
      'tls': {
        'enabled': true,
        'server_name': 'sni.example.com',
        'insecure': true,
        'utls': {'enabled': true, 'fingerprint': 'chrome'},
      },
    });

    expect(link, isNotNull);
    final uri = Uri.parse(link!);
    expect(uri.scheme, 'anytls');
    expect(uri.userInfo, 'p%40ss%3Aword');
    expect(uri.host, 'any.example.com');
    expect(uri.port, 443);
    expect(uri.queryParameters, {'insecure': '1', 'sni': 'sni.example.com', 'fp': 'chrome'});
    expect(Uri.decodeComponent(uri.fragment), 'AnyTLS 节点');
    expect(outboundTypeHasStandardLink('anytls'), isTrue);
    expect(outboundTypeHasStandardLink('chain'), isFalse);
  });
}
