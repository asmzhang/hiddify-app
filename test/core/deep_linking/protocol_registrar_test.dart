// ProtocolRegistrar 的行为测试。
//
// 这是「根治」的核心断言面：用假 handler 记录**实际发生的调用序列**，
// 从而证明外来 scheme 既不注册也不覆盖、自有 scheme 幂等、
// 且单个 scheme 失败不会带崩整条流程。
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/deep_linking/url_protocol/protocol.dart';
import 'package:hiddify/core/router/deep_linking/url_protocol/protocol_registrar.dart';
import 'package:hiddify/core/router/deep_linking/url_protocol/protocol_registration_spec.dart';

const _ourExe = r'S:\test\1\hiddify-app\build\windows\x64\runner\Release\Hiddify.exe';

/// 记录所有平台调用的假实现。
class _FakeHandler implements ProtocolHandler {
  _FakeHandler({
    Map<String, String>? registry,
    this.supportsAssociation = true,
    this.throwOn = const {},
  }) : registry = {...?registry};

  /// scheme → `shell\open\command` 的值（模拟注册表）。
  final Map<String, String> registry;

  /// 对这些 scheme 的注册表操作抛异常（模拟权限被拒）。
  final Set<String> throwOn;

  @override
  final bool supportsAssociation;

  @override
  final String executable = _ourExe;

  /// 调用日志，形如 `register:clash` / `unregister:clash`。
  final List<String> calls = [];

  @override
  String? registeredCommand(String scheme) {
    if (throwOn.contains(scheme)) throw Exception('registry read denied for $scheme');
    return registry[scheme];
  }

  @override
  void register(String scheme, {String? executable, List<String>? arguments}) {
    if (throwOn.contains(scheme)) throw Exception('registry write denied for $scheme');
    calls.add('register:$scheme');
    registry[scheme] = '"${this.executable}" "%1"';
  }

  @override
  void unregister(String scheme) {
    if (throwOn.contains(scheme)) throw Exception('registry delete denied for $scheme');
    calls.add('unregister:$scheme');
    registry.remove(scheme);
  }

  @override
  List<String> getArguments(List<String>? arguments) => arguments ?? const ['%s'];
}

void main() {
  group('干净机器（什么都没注册）', () {
    test('只注册 hiddify，其余 6 个外来 scheme 一个字都不写', () {
      final handler = _FakeHandler();
      final report = ProtocolRegistrar(handler).reconcile();

      expect(report.claimed, ['hiddify']);
      expect(report.revoked, isEmpty);
      expect(report.failed, isEmpty);
      expect(report.left.toSet(), kForeignProtocolSchemes);

      expect(handler.calls, ['register:hiddify']);
      expect(handler.registry.keys, ['hiddify']);
    });
  });

  group('升级自老版本（6 个外来键都指向我们）', () {
    _FakeHandler legacyHandler() => _FakeHandler(
      registry: {
        for (final s in kAllProtocolSchemes) s: '"$_ourExe" "%1"',
      },
    );

    test('把 6 个外来键全部归还，自有键保持不变', () {
      final handler = legacyHandler();
      final report = ProtocolRegistrar(handler).reconcile();

      expect(report.revoked.toSet(), kForeignProtocolSchemes);
      expect(report.kept, ['hiddify']);
      expect(report.claimed, isEmpty);

      expect(handler.calls.toSet(), {for (final s in kForeignProtocolSchemes) 'unregister:$s'});
      expect(handler.registry.keys, ['hiddify'], reason: '只剩自己的命名空间');
    });

    test('再跑一次 ⇒ 零改动（幂等收尾）', () {
      final handler = legacyHandler();
      ProtocolRegistrar(handler).reconcile();
      handler.calls.clear();

      final second = ProtocolRegistrar(handler).reconcile();

      expect(handler.calls, isEmpty, reason: '稳态下不应有任何注册表写入');
      expect(second.claimed, isEmpty);
      expect(second.revoked, isEmpty);
      expect(second.kept, ['hiddify']);
    });
  });

  group('机器上装着真正的 Clash / sing-box', () {
    test('绝不覆盖别人的键', () {
      final handler = _FakeHandler(
        registry: {
          'clash': r'"C:\Program Files\Clash Verge\clash-verge.exe" "%1"',
          'sing-box': r'"C:\Program Files\sing-box\sing-box.exe" "%1"',
        },
      );
      final report = ProtocolRegistrar(handler).reconcile();

      expect(handler.registry['clash'], contains('clash-verge.exe'), reason: '别人的键原样不动');
      expect(handler.registry['sing-box'], contains(r'sing-box\sing-box.exe'));
      expect(handler.calls, ['register:hiddify'], reason: '只动了自有 scheme');
      expect(report.left, containsAll(['clash', 'sing-box']));
    });

    test('别人的键即使路径里带 hiddify 字样也不误删（只认可执行文件名）', () {
      final handler = _FakeHandler(
        registry: {
          'clash': r'"C:\Program Files\hiddify-helper\helper.exe" "%1"',
        },
      );
      ProtocolRegistrar(handler).reconcile();

      expect(handler.registry['clash'], contains('helper.exe'), reason: '文件名不是 hiddify.exe ⇒ 别人的');
      expect(handler.calls, isNot(contains('unregister:clash')));
    });
  });

  group('升级/换目录后的自愈（真机实测暴露的场景）', () {
    test('老开发构建写下的 6 个键，从新路径运行也能归还', () {
      const legacy = r'"S:\test\1\hiddify-app\build\windows\x64\runner\Release\Hiddify.exe" "%1"';
      final handler = _FakeHandler(
        registry: {
          for (final s in kForeignProtocolSchemes) s: legacy,
        },
      );

      final report = ProtocolRegistrar(handler).reconcile();

      expect(report.revoked.toSet(), kForeignProtocolSchemes);
      expect(handler.registry.keys, ['hiddify'], reason: '外来键被全部清空，只剩自有命名空间');
      expect(handler.registry['hiddify'], contains(_ourExe), reason: '自有键指向我们自己的 exe');
    });
  });

  group('自有 scheme 被别人占了', () {
    test('拿回来（例如另一个 hiddify 构建）', () {
      final handler = _FakeHandler(
        registry: {'hiddify': r'"C:\Program Files\Hiddify\Hiddify.exe" "%1"'},
      );
      final report = ProtocolRegistrar(handler).reconcile();

      expect(report.claimed, ['hiddify']);
      expect(handler.registry['hiddify'], contains(_ourExe));
    });
  });

  group('平台操作失败', () {
    test('单个 scheme 抛异常 ⇒ 其余照常，失败的记进 failed', () {
      final handler = _FakeHandler(throwOn: {'clash'});
      final report = ProtocolRegistrar(handler).reconcile();

      expect(report.failed, ['clash']);
      expect(report.claimed, ['hiddify'], reason: '失败被隔离，不影响自有 scheme');
      expect(report.kept, isNot(contains('clash')));
    });

    test('自有 scheme 失败 ⇒ 其余仍走完，不抛出去', () {
      final handler = _FakeHandler(throwOn: {'hiddify'});
      late ProtocolReconcileReport report;

      expect(() => report = ProtocolRegistrar(handler).reconcile(), returnsNormally);
      expect(report.failed, ['hiddify']);
      expect(report.left.toSet(), kForeignProtocolSchemes);
    });

    test('全部失败也不抛（企业环境注册表被组策略锁死）', () {
      final handler = _FakeHandler(throwOn: kAllProtocolSchemes.toSet());
      late ProtocolReconcileReport report;

      expect(() => report = ProtocolRegistrar(handler).reconcile(), returnsNormally);
      expect(report.failed.toSet(), kAllProtocolSchemes.toSet());
      expect(report.claimed, isEmpty);
      expect(report.revoked, isEmpty);
    });
  });

  group('不支持的平台（Web / 移动端）', () {
    test('supportsAssociation=false ⇒ 一次平台调用都没有', () {
      final handler = _FakeHandler(supportsAssociation: false);
      final report = ProtocolRegistrar(handler).reconcile();

      expect(handler.calls, isEmpty);
      expect(report.claimed, isEmpty);
      expect(report.failed, isEmpty, reason: '平台不支持不是失败');
    });
  });

  group('每次 reconcile 的可观测性', () {
    test('报告四类互斥且并集为全部 scheme', () {
      final handler = _FakeHandler(
        registry: {'clash': '"$_ourExe" "%1"'},
      );
      final report = ProtocolRegistrar(handler).reconcile();

      final covered = {
        ...report.claimed,
        ...report.kept,
        ...report.revoked,
        ...report.left,
        ...report.failed,
      };
      expect(covered, kAllProtocolSchemes.toSet());
      expect(covered.length, kAllProtocolSchemes.length, reason: '没有 scheme 被重复归类');
    });
  });
}
