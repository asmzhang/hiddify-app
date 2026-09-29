import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/utils/available_port.dart';
import 'package:hiddify/gen/hiddify_core_generated_bindings.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello_service.pbgrpc.dart';
import 'package:hiddify/utils/custom_loggers.dart';

import 'package:loggy/loggy.dart';

import 'package:path/path.dart' as p;

final _logger = Loggy('HiddifyCoreFFI');

const preferredDesktopCorePort = 17078;

typedef StopFunc = Pointer<Utf8> Function();
typedef StopFuncDart = Pointer<Utf8> Function();

class CoreInterfaceDesktop extends CoreInterface with InfraLogger {
  static final HiddifyCoreNativeLibrary _box = _gen();

  static HiddifyCoreNativeLibrary _gen() {
    String fullPath = "";
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      fullPath = "hiddify-core";
    }
    if (Platform.isWindows) {
      fullPath = p.join(fullPath, "hiddify-core.dll");
    } else if (Platform.isMacOS) {
      fullPath = p.join(fullPath, "hiddify-core.dylib");
    } else {
      fullPath = p.join(fullPath, "hiddify-core.so");
    }

    _logger.debug('hiddify-core native libs path: "$fullPath"');
    final lib = DynamicLibrary.open(fullPath);
    // final stopFunc = lib.lookup<NativeFunction<StopFunc>>('stop').asFunction<StopFunc>();
    // final errPtr2 = stopFunc();
    // final err = errPtr2.cast<Utf8>().toDartString();

    return HiddifyCoreNativeLibrary(lib);
  }

  Future<bool> isMusl() async {
    try {
      final result = await Process.run('ldd', ['--version']);
      return result.stdout.toString().toLowerCase().contains('musl');
    } catch (_) {
      return false;
    }
  }

  int port = preferredDesktopCorePort;
  static String generateRandomPassword(int length) {
    const characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    // Random.secure() (audit C): dart:math Random() is predictable, which made
    // this gRPC secret guessable in principle. Loopback-only today, but the
    // secret is the only auth on the port -- generate it from the CSPRNG.
    final random = Random.secure();
    return List.generate(length, (_) => characters[random.nextInt(characters.length)]).join();
  }

  static final String secret = generateRandomPassword(100);

  @override
  Future<String> setup(Directories directories, bool debug, int mode) async {
    // Generate a random password for the grpc service
    // final errPtr2 = _box.stop();
    // final err = errPtr2.cast<Utf8>().toDartString();
    // throw Exception('stop: $err');
    const channelOption = ChannelCredentials.insecure();
    HelloClient helloAt(int value) => HelloClient(
      ClientChannel(
        '127.0.0.1',
        port: value,
        options: const ChannelOptions(credentials: channelOption),
      ),
    );

    // A busy core can miss a short probe, but a loopback connection-refused is
    // immediate — a 2s budget survives entity-sync load without slowing the
    // "nothing is listening" path down.
    Future<bool> probe(int value) async {
      try {
        await helloAt(value).sayHello(HelloRequest(name: "test")).timeout(const Duration(seconds: 2));
        return true;
      } catch (_) {
        return false;
      }
    }

    // Once clients exist the selected port is authoritative: the native gRPC
    // server cannot be created twice, and a second _box.setup would orphan the
    // clients on an unbound port (the "background core start failed" smoke
    // regression). Re-probe and return; only an unreachable core falls through
    // to a fresh port.
    if (isInitialized()) {
      if (await probe(port)) {
        loggy.info("core is already started on 127.0.0.1:$port");
        return "";
      }
      loggy.warning("core on 127.0.0.1:$port is unreachable; selecting a fresh port");
    } else if (await probe(port)) {
      // Another instance's core is already serving this port — reuse it.
      loggy.info("core is already started on 127.0.0.1:$port");
      bgClient = fgClient = CoreClient(
        ClientChannel(
          'localhost',
          port: port,
          options: const ChannelOptions(
            credentials: ChannelCredentials.insecure(),
            // credentials: ChannelCredentials.secure(
            //   password: secret,
            //   onBadCertificate: (certificate, host) => true,
            // ),
          ),
        ),
      );
      return "";
    }

    // Nothing reusable is listening. The preferred port may be occupied or
    // reserved by Windows (excluded ranges are invisible to netstat), so bind
    // a probe to select a loopback port the native core can take.
    port = await selectAvailableLoopbackPort(preferredDesktopCorePort);
    loggy.info("starting core gRPC on 127.0.0.1:$port");

    final errPtr = _box.setup(
      directories.baseDir.path.toNativeUtf8().cast(),
      directories.workingDir.path.toNativeUtf8().cast(),
      directories.tempDir.path.toNativeUtf8().cast(),
      SetupMode.GRPC_NORMAL_INSECURE.value,
      "127.0.0.1:$port".toNativeUtf8().cast(),
      secret.toNativeUtf8().cast(),
      0,
      debug ? 1 : 0,
    );
    final err = errPtr.cast<Utf8>().toDartString();

    if (err.isNotEmpty) {
      return err;
    }
    final res = await helloAt(port).sayHello(HelloRequest(name: "test"));
    loggy.info(res.toString());
    bgClient = fgClient = CoreClient(
      ClientChannel(
        'localhost',
        port: port,
        options: const ChannelOptions(
          credentials: ChannelCredentials.insecure(),
          // credentials: ChannelCredentials.secure(
          //   password: secret,
          //   onBadCertificate: (certificate, host) => true,
          // ),
        ),
      ),
    );

    return "";
  }

  @override
  Future<bool> restart(String path, String name) async {
    return false;
  }

  @override
  Future<bool> stop() async {
    return false;
  }
}
