import 'package:hiddify/core/router/deep_linking/url_protocol/protocol_registrar.dart';
import 'package:hiddify/core/router/deep_linking/url_protocol/protocol_registration_spec.dart';
import 'package:hiddify/core/router/deep_linking/url_protocol/windows_protocol.dart'
    if (dart.library.js_interop) 'package:hiddify/core/router/deep_linking/url_protocol/web_url_protocol.dart';

/// 协议关联的平台实现。测试里替换成假实现即可覆盖整条注册流程。
final protocolHandler = WindowsProtocolHandler();

/// 按「只主张自己的命名空间」原则校准协议关联。
///
/// 每次调用都是幂等的：已经注册对了就不写注册表。详见
/// [ProtocolRegistrar.reconcile] 与 [protocolRegistrationAction]。
ProtocolReconcileReport reconcileProtocolAssociations() =>
    ProtocolRegistrar(protocolHandler).reconcile();

/// 注册单个协议关联（仅供需要显式注册的场景使用；常规启动走
/// [reconcileProtocolAssociations]，它会顺带归还外来 scheme）。
void registerProtocolHandler(String scheme, {String? executable, List<String>? arguments}) {
  protocolHandler.register(scheme, executable: executable, arguments: arguments);
}

/// 移除单个协议关联。
void unregisterProtocolHandler(String scheme) {
  protocolHandler.unregister(scheme);
}
