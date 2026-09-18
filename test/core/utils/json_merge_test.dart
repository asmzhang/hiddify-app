import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/utils/json_merge.dart';

void main() {
  group('deepMergeJson — NekoBox Util.mergeMap 语义复刻', () {
    test('标量直接覆盖', () {
      final dst = <String, dynamic>{'a': 1, 'b': 'x'};
      deepMergeJson(dst, {'a': 2, 'b': 'y'});
      expect(dst, {'a': 2, 'b': 'y'});
    });

    test('嵌套 Map 递归深合并，兄弟键保留', () {
      final dst = <String, dynamic>{
        'route': <String, dynamic>{'final': 'proxy', 'auto_detect_interface': true},
        'log': <String, dynamic>{'level': 'warn'},
      };
      deepMergeJson(dst, {
        'route': {'final': 'direct'},
      });
      expect(dst['route'], {'final': 'direct', 'auto_detect_interface': true});
      expect(dst['log'], {'level': 'warn'});
    });

    test('类型不同（Map 撞标量）→ 覆盖', () {
      final dst = <String, dynamic>{
        'a': <String, dynamic>{'x': 1},
      };
      deepMergeJson(dst, {'a': 5});
      expect(dst['a'], 5);
    });

    test('key+ 追加到现有 List 末尾', () {
      final dst = <String, dynamic>{
        'rules': <dynamic>[{'a': 1}],
      };
      deepMergeJson(dst, {
        'rules+': [
          {'b': 2},
        ],
      });
      expect(dst['rules'], [
        {'a': 1},
        {'b': 2},
      ]);
    });

    test('key+ 目标不存在 → 新建 List', () {
      final dst = <String, dynamic>{};
      deepMergeJson(dst, {
        'rules+': [
          {'b': 2},
        ],
      });
      expect(dst['rules'], [
        {'b': 2},
      ]);
    });

    test('+key 前插到现有 List 头部', () {
      final dst = <String, dynamic>{
        'rules': <dynamic>[{'a': 1}],
      };
      deepMergeJson(dst, {
        '+rules': [
          {'b': 2},
        ],
      });
      expect(dst['rules'], [
        {'b': 2},
        {'a': 1},
      ]);
    });

    test('裸键 List 整体替换', () {
      final dst = <String, dynamic>{
        'rules': <dynamic>[{'a': 1}],
      };
      deepMergeJson(dst, {
        'rules': [
          {'c': 3},
        ],
      });
      expect(dst['rules'], [
        {'c': 3},
      ]);
    });

    test('混合场景：dns.servers + route.rules + 实验字段（真实用例形态）', () {
      final dst = <String, dynamic>{
        'dns': <String, dynamic>{
          'servers': <dynamic>[
            <String, dynamic>{'tag': 'remote', 'address': 'https://1.1.1.1/dns-query'},
          ],
          'rules': <dynamic>[],
        },
        'inbounds': <dynamic>[
          <String, dynamic>{'type': 'tun'},
        ],
        'experimental': <String, dynamic>{
          'cache_file': <String, dynamic>{'enabled': true},
        },
      };
      deepMergeJson(dst, {
        'dns': {
          'servers+': [
            {'tag': 'local', 'address': 'local'},
          ],
        },
        '+route': {
          'rules': [
            {'protocol': 'dns', 'action': 'hijack-dns'},
          ],
        },
        'experimental': {
          'cache_file': {'store_rdrc': true},
        },
      });
      // servers 追加成功
      final dns = dst['dns'] as Map;
      expect((dns['servers'] as List).length, 2);
      // inbounds 未被触碰
      expect((dst['inbounds'] as List).length, 1);
      // experimental 深合并：enabled 保留 + store_rdrc 新增
      final exp = dst['experimental'] as Map;
      expect(exp['cache_file'], {'enabled': true, 'store_rdrc': true});
    });

    test('返回 dst 本身（就地修改语义）', () {
      final dst = <String, dynamic>{};
      final out = deepMergeJson(dst, {'a': 1});
      expect(identical(dst, out), isTrue);
    });
  });

  group('parseCustomConfig', () {
    test('空串 → 空 Map', () {
      expect(parseCustomConfig(''), isEmpty);
      expect(parseCustomConfig('   '), isEmpty);
    });

    test('合法对象 → 解析成功', () {
      expect(parseCustomConfig('{"a":1}'), {'a': 1});
    });

    test('非对象（数组/标量）→ FormatException', () {
      expect(() => parseCustomConfig('[1,2]'), throwsFormatException);
      expect(() => parseCustomConfig('42'), throwsFormatException);
      expect(() => parseCustomConfig('"str"'), throwsFormatException);
    });

    test('坏 JSON → FormatException', () {
      expect(() => parseCustomConfig('{bad'), throwsFormatException);
    });
  });
}
