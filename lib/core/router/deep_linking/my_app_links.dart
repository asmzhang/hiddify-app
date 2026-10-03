import 'package:app_links/app_links.dart';
import 'package:hiddify/core/router/deep_linking/url_protocol/api.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'my_app_links.g.dart';

@riverpod
Stream<String> myAppLinks(Ref ref) async* {
  if (PlatformUtils.isWindows) {
    // 只主张自己的命名空间，并归还历史误占的外来 scheme。
    // 判定与理由见 url_protocol/protocol_registration_spec.dart。
    // 平台操作失败在 registrar 内部逐个 scheme 降级，不会走到这里。
    reconcileProtocolAssociations();
  }
  yield* AppLinks().uriLinkStream.map((event) => event.toString());
}
