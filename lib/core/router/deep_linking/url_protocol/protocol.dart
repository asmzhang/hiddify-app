/// 桌面端 URL 协议关联的平台 seam。
///
/// 上游只有 `register` / `unregister` 两个方法（写入是单向的）。根治「抢协议」
/// 需要能**先读再决定**：只有知道注册表里当前是什么，才能区分
/// 「没注册」「是我们写的」「是别人的」—— 见
/// `lib/core/router/deep_linking/url_protocol/protocol_registration_spec.dart`。
///
/// 纯接口（不 import Flutter / dart:io），便于测试里替换成假实现。
abstract class ProtocolHandler {
  /// 本平台是否支持协议关联。false ⇒ [register]/[unregister] 都是空操作。
  bool get supportsAssociation;

  /// 本进程的可执行文件路径，用于判断「这个键是不是我们写的」。
  String get executable;

  /// 读取 `shell\open\command` 的当前值；没注册返回 null。
  String? registeredCommand(String scheme);

  void register(String scheme, {String? executable, List<String>? arguments});

  void unregister(String scheme);

  List<String> getArguments(List<String>? arguments) {
    if (arguments == null) return ['%s'];

    if (arguments.isEmpty && !arguments.any((e) => e.contains('%s'))) {
      throw ArgumentError('arguments must contain at least 1 instance of "%s"');
    }

    return arguments;
  }
}
