// URL 协议关联注册决策的规格测试。
//
// 这一层的存在理由就是「防止再把 Android 的声明式清单当成 Windows 的独占接管」，
// 所以断言的重点是**不该做什么**（外来 scheme 绝不写注册表），而不是做了什么。
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/deep_linking/url_protocol/protocol_registration_spec.dart';

const _ourExe = r'S:\test\1\hiddify-app\build\windows\x64\runner\Release\Hiddify.exe';

void main() {
  group('scheme 归属表', () {
    test('自有命名空间只有 hiddify 一个', () {
      expect(kOwnedProtocolSchemes, {'hiddify'});
    });

    test('外来命名空间正是上游从 Android 清单照搬的那 6 个', () {
      expect(kForeignProtocolSchemes, {
        'v2ray',
        'v2rayn',
        'v2rayng',
        'clash',
        'clashmeta',
        'sing-box',
      });
    });

    test('两类不重叠', () {
      expect(kOwnedProtocolSchemes.intersection(kForeignProtocolSchemes), isEmpty);
    });

    test('合表覆盖上游 LinkParser.protocols 的全部 7 项，且自有在前', () {
      expect(kAllProtocolSchemes, [
        'hiddify',
        'v2ray',
        'v2rayn',
        'v2rayng',
        'clash',
        'clashmeta',
        'sing-box',
      ]);
    });
  });

  group('protocolCommandExecutable', () {
    test('带引号的命令行取出 exe 路径', () {
      expect(
        protocolCommandExecutable(r'"S:\app\Hiddify.exe" "%1"'),
        r'S:\app\Hiddify.exe',
      );
    });

    test('不带引号但路径含空格时按 .exe 切开', () {
      expect(
        protocolCommandExecutable(r'C:\Program Files\Foo Bar\foo.exe %1'),
        r'C:\Program Files\Foo Bar\foo.exe',
      );
    });

    test('没有参数的裸路径', () {
      expect(protocolCommandExecutable(r'C:\a\b.exe'), r'C:\a\b.exe');
    });

    test('空值与空白 ⇒ null', () {
      expect(protocolCommandExecutable(null), isNull);
      expect(protocolCommandExecutable(''), isNull);
      expect(protocolCommandExecutable('   '), isNull);
    });

    test('只有引号没有内容 ⇒ null（畸形值不猜）', () {
      expect(protocolCommandExecutable('""'), isNull);
    });
  });

  group('sameExecutablePath', () {
    test('大小写与分隔符都不敏感', () {
      expect(sameExecutablePath(r'S:\A\Hiddify.EXE', 's:/a/hiddify.exe'), isTrue);
    });

    test('不同路径为 false', () {
      expect(sameExecutablePath(r'S:\a\Hiddify.exe', r'S:\b\Hiddify.exe'), isFalse);
    });

    test('不做 8.3 短名解析 ⇒ 判为不同（偏保守，不会误删别人的键）', () {
      expect(
        sameExecutablePath(
          r'C:\Users\ADMINI~1\AppData\Local\Temp\Hiddify.exe',
          r'C:\Users\Administrator\AppData\Local\Temp\Hiddify.exe',
        ),
        isFalse,
      );
    });
  });

  group('executableFileName / isOurRegisteredExecutable', () {
    test('取文件名，大小写不敏感', () {
      expect(executableFileName(r'S:\a\b\Hiddify.EXE'), 'hiddify.exe');
      expect(executableFileName('C:/x/y/Hiddify.exe'), 'hiddify.exe');
      expect(executableFileName('Hiddify.exe'), 'hiddify.exe');
    });

    test('全路径相同 ⇒ 是我们的', () {
      expect(isOurRegisteredExecutable(_ourExe, _ourExe), isTrue);
    });

    test('★真机实测逼出来的用例：换路径（%TEMP% 副本 / 升级 / 换安装目录）仍认得是自己', () {
      expect(
        isOurRegisteredExecutable(
          r'S:\test\1\hiddify-app\build\windows\x64\runner\Release\Hiddify.exe',
          r'C:\Users\Administrator\AppData\Local\Temp\hiddify_proto_verify\Hiddify.exe',
        ),
        isTrue,
        reason: '只比全路径会让开发构建写下的 6 个外来键永远清不掉（实测一个都没归还）',
      );
    });

    test('别的客户端 ⇒ 不是我们的（绝不误删）', () {
      expect(
        isOurRegisteredExecutable(
          r'C:\Program Files\Clash Verge\clash-verge.exe',
          _ourExe,
        ),
        isFalse,
      );
      expect(
        isOurRegisteredExecutable(
          r'C:\Program Files\sing-box\sing-box.exe',
          _ourExe,
        ),
        isFalse,
      );
    });
  });

  group('自有命名空间（hiddify）', () {
    test('没注册过 ⇒ claim', () {
      expect(
        protocolRegistrationAction(scheme: 'hiddify', registeredCommand: null, executable: _ourExe),
        ProtocolRegistrationAction.claim,
      );
    });

    test('已指向本 exe ⇒ keep（幂等，稳态下零写入）', () {
      expect(
        protocolRegistrationAction(
          scheme: 'hiddify',
          registeredCommand: '"$_ourExe" "%1"',
          executable: _ourExe,
        ),
        ProtocolRegistrationAction.keep,
      );
    });

    test('指向别的 exe ⇒ claim（自己的名字要拿回来，例如正式版 vs 开发版）', () {
      expect(
        protocolRegistrationAction(
          scheme: 'hiddify',
          registeredCommand: r'"C:\Program Files\Hiddify\Hiddify.exe" "%1"',
          executable: _ourExe,
        ),
        ProtocolRegistrationAction.claim,
      );
    });

    test('大小写不同的同一条路径仍判 keep', () {
      expect(
        protocolRegistrationAction(
          scheme: 'hiddify',
          registeredCommand: '"${_ourExe.toUpperCase()}" "%1"',
          executable: _ourExe,
        ),
        ProtocolRegistrationAction.keep,
      );
    });
  });

  group('外来命名空间（clash / sing-box / v2ray*）', () {
    for (final scheme in kForeignProtocolSchemes) {
      test('$scheme 没注册过 ⇒ leave（不抢）', () {
        expect(
          protocolRegistrationAction(scheme: scheme, registeredCommand: null, executable: _ourExe),
          ProtocolRegistrationAction.leave,
          reason: '$scheme 属于别的客户端；空着也不该由我们占',
        );
      });

      test('$scheme 被别的客户端占着 ⇒ leave（绝不覆盖）', () {
        expect(
          protocolRegistrationAction(
            scheme: scheme,
            registeredCommand: r'"C:\Program Files\Clash Verge\clash-verge.exe" "%1"',
            executable: _ourExe,
          ),
          ProtocolRegistrationAction.leave,
        );
      });

      test('$scheme 指向我们自己的 exe ⇒ revoke（历史误占，自愈清掉）', () {
        expect(
          protocolRegistrationAction(
            scheme: scheme,
            registeredCommand: '"$_ourExe" "%1"',
            executable: _ourExe,
          ),
          ProtocolRegistrationAction.revoke,
          reason: '老版本无条件写下的 6 个键，必须能被新版本自动归还',
        );
      });

      test('$scheme 指向**旧路径下的**本产品 exe ⇒ revoke（跨路径自愈）', () {
        expect(
          protocolRegistrationAction(
            scheme: scheme,
            registeredCommand: r'"C:\Users\Administrator\AppData\Local\Temp\hiddify_proto_verify\Hiddify.exe" "%1"',
            executable: _ourExe,
          ),
          ProtocolRegistrationAction.revoke,
          reason: '升级 / 开发构建 / 换安装目录之后，老键也必须能被归还',
        );
      });
    }
  });

  group('决策优先级（同一 scheme 的四种输入互斥穷尽）', () {
    test('自有 + 空 ⇒ claim；外来 + 空 ⇒ leave —— 同样的输入，归属决定动作', () {
      final ownedEmpty = protocolRegistrationAction(
        scheme: 'hiddify',
        registeredCommand: null,
        executable: _ourExe,
      );
      final foreignEmpty = protocolRegistrationAction(
        scheme: 'clash',
        registeredCommand: null,
        executable: _ourExe,
      );
      expect(ownedEmpty, ProtocolRegistrationAction.claim);
      expect(foreignEmpty, ProtocolRegistrationAction.leave);
      expect(ownedEmpty, isNot(foreignEmpty));
    });

    test('引用同一产品时：自有 ⇒ keep，外来 ⇒ revoke', () {
      final ownedOurs = protocolRegistrationAction(
        scheme: 'hiddify',
        registeredCommand: '"$_ourExe"',
        executable: _ourExe,
      );
      final foreignOurs = protocolRegistrationAction(
        scheme: 'clash',
        registeredCommand: '"$_ourExe"',
        executable: _ourExe,
      );
      expect(ownedOurs, ProtocolRegistrationAction.keep);
      expect(foreignOurs, ProtocolRegistrationAction.revoke);
    });

    test('★真机实测场景：从 %TEMP% 副本运行，注册表里是旧开发构建路径', () {
      const tempExe = r'C:\Users\Administrator\AppData\Local\Temp\hiddify_proto_verify\Hiddify.exe';
      const legacyKey = r'"S:\test\1\hiddify-app\build\windows\x64\runner\Release\Hiddify.exe" "%1"';

      // 自有 scheme：抢回来指向当前 exe
      expect(
        protocolRegistrationAction(
          scheme: 'hiddify',
          registeredCommand: legacyKey,
          executable: tempExe,
        ),
        ProtocolRegistrationAction.claim,
      );
      // 外来 scheme：识别出是本产品留下的 ⇒ 归还
      for (final scheme in kForeignProtocolSchemes) {
        expect(
          protocolRegistrationAction(
            scheme: scheme,
            registeredCommand: legacyKey,
            executable: tempExe,
          ),
          ProtocolRegistrationAction.revoke,
          reason: '$scheme 的自愈必须跨路径生效（否则实测一个都不会归还）',
        );
      }
    });
  });
}
