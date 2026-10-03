import 'package:hiddify/core/router/deep_linking/url_protocol/protocol.dart';

/// Web 上不存在「URL 协议关联」这回事。
///
/// [supportsAssociation] 恒为 false ⇒ 调用方会跳过整个注册流程，
/// [register]/[unregister] 也就永远不会被走到（保留空实现只为满足接口）。
class WindowsProtocolHandler extends ProtocolHandler {
  @override
  bool get supportsAssociation => false;

  @override
  String get executable => '';

  @override
  String? registeredCommand(String scheme) => null;

  @override
  void register(String scheme, {String? executable, List<String>? arguments}) {}

  @override
  void unregister(String scheme) {}
}
