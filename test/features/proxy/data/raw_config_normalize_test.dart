import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/data/raw_config_normalize.dart';

void main() {
  group('normalizeRawConfigSelector — raw 通道 selector 归一化', () {
    test('事故形态：无 select 时把 route.final 指向的 selector 改名并重写引用', () {
      final config = <String, dynamic>{
        'outbounds': <dynamic>[
          <String, dynamic>{'type': 'direct', 'tag': 'direct'},
          <String, dynamic>{
            'type': 'selector',
            'tag': '节点选择',
            'outbounds': <String>['n1', 'n2'],
          },
          <String, dynamic>{
            'type': 'selector',
            'tag': 'backup',
            'outbounds': <String>['节点选择'],
            'default': '节点选择',
          },
          <String, dynamic>{'type': 'direct', 'tag': 'd1', 'detour': '节点选择'},
          <String, dynamic>{'type': 'socks', 'tag': 'n1', 'server': '1.1.1.1', 'server_port': 1},
          <String, dynamic>{'type': 'socks', 'tag': 'n2', 'server': '2.2.2.2', 'server_port': 2},
        ],
        'route': <String, dynamic>{
          'final': '节点选择',
          'rules': <dynamic>[
            <String, dynamic>{'inbound': <String>['tun-in'], 'outbound': '节点选择'},
          ],
        },
      };

      expect(normalizeRawConfigSelector(config), '节点选择', reason: '返回值应是被改名的旧 tag');

      final outbounds = config['outbounds'] as List;
      expect(
        (outbounds[1] as Map<String, dynamic>)['tag'],
        'select',
        reason: '第一个 selector 应被改名为 select',
      );

      final route = config['route'] as Map<String, dynamic>;
      expect(route['final'], 'select', reason: 'route.final 应被重写为 select');
      expect(
        ((route['rules'] as List)[0] as Map<String, dynamic>)['outbound'],
        'select',
        reason: '路由规则里的 outbound 引用应被重写为 select',
      );

      final backup = outbounds[2] as Map<String, dynamic>;
      expect(backup['outbounds'], <String>['select'], reason: 'backup 的成员引用应被重写');
      expect(backup['default'], 'select', reason: 'backup 的 default 引用应被重写');

      expect(
        (outbounds[3] as Map<String, dynamic>)['detour'],
        'select',
        reason: 'd1 的 detour 引用应被重写',
      );
    });

    test('已存在 select 时整体不动', () {
      final config = <String, dynamic>{
        'outbounds': <dynamic>[
          <String, dynamic>{'type': 'selector', 'tag': 'select', 'outbounds': <String>['n1']},
          <String, dynamic>{'type': 'selector', 'tag': 'mine', 'outbounds': <String>['n1']},
          <String, dynamic>{'type': 'socks', 'tag': 'n1'},
        ],
        'route': <String, dynamic>{'final': 'mine'},
      };

      expect(normalizeRawConfigSelector(config), isNull, reason: '契约已满足时应返回 null');

      final outbounds = config['outbounds'] as List;
      expect((outbounds[0] as Map<String, dynamic>)['tag'], 'select', reason: '原有 select 不应被改名');
      expect((outbounds[1] as Map<String, dynamic>)['tag'], 'mine', reason: '另一个 selector 不应被改名');
      expect(
        (config['route'] as Map<String, dynamic>)['final'],
        'mine',
        reason: 'route.final 指向用户自己的 selector 是用户意图，不应动',
      );
    });

    test('无 selector 时不动', () {
      final config = <String, dynamic>{
        'outbounds': <dynamic>[
          <String, dynamic>{'type': 'direct', 'tag': 'direct'},
          <String, dynamic>{'type': 'socks', 'tag': 'n1'},
        ],
      };

      expect(normalizeRawConfigSelector(config), isNull, reason: '没有 selector 候选时应返回 null');
      expect(
        config['outbounds'],
        <dynamic>[
          <String, dynamic>{'type': 'direct', 'tag': 'direct'},
          <String, dynamic>{'type': 'socks', 'tag': 'n1'},
        ],
        reason: '原样返回，不应有任何改动',
      );
    });

    test('route.final 指向 urltest 时改首个 selector', () {
      final config = <String, dynamic>{
        'outbounds': <dynamic>[
          <String, dynamic>{'type': 'urltest', 'tag': 'auto', 'outbounds': <String>['n1']},
          <String, dynamic>{'type': 'selector', 'tag': 'my-group', 'outbounds': <String>['n1']},
          <String, dynamic>{'type': 'socks', 'tag': 'n1'},
        ],
        'route': <String, dynamic>{'final': 'auto'},
      };

      expect(normalizeRawConfigSelector(config), 'my-group', reason: 'route.final 非候选时应回落到首个候选');

      final outbounds = config['outbounds'] as List;
      expect(
        (outbounds[1] as Map<String, dynamic>)['tag'],
        'select',
        reason: '首个 selector 应被改名为 select',
      );
      expect(
        (config['route'] as Map<String, dynamic>)['final'],
        'auto',
        reason: 'route.final 指向 urltest（非旧 tag），应保持原样',
      );
    });

    test('§hide§ selector 不作候选', () {
      final config = <String, dynamic>{
        'outbounds': <dynamic>[
          <String, dynamic>{'type': 'selector', 'tag': 'secret §hide§', 'outbounds': <String>['n1']},
          <String, dynamic>{'type': 'socks', 'tag': 'n1'},
        ],
        'route': <String, dynamic>{'final': 'secret §hide§'},
      };

      expect(normalizeRawConfigSelector(config), isNull, reason: 'tag 含 §hide§ 的 selector 不参与候选');
      expect(
        (config['outbounds'] as List)[0],
        isA<Map<String, dynamic>>(),
        reason: '配置不应被改动',
      );
      expect(
        ((config['outbounds'] as List)[0] as Map<String, dynamic>)['tag'],
        'secret §hide§',
        reason: '隐藏 selector 的 tag 应保持原样',
      );
    });

    test('outbounds 非法形态返回 null', () {
      expect(normalizeRawConfigSelector(<String, dynamic>{}), isNull, reason: '无 outbounds 键时应返回 null');

      final notList = <String, dynamic>{'outbounds': 'oops'};
      expect(normalizeRawConfigSelector(notList), isNull, reason: 'outbounds 不是 List 时应返回 null');

      final empty = <String, dynamic>{'outbounds': <dynamic>[]};
      expect(normalizeRawConfigSelector(empty), isNull, reason: 'outbounds 是空列表时应返回 null');
    });
  });
}
