import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hiddify/core/model/environment.dart';

part 'app_info_entity.freezed.dart';

@freezed
class AppInfoEntity with _$AppInfoEntity {
  const AppInfoEntity._();

  const factory AppInfoEntity({
    required String name,
    required String version,
    required String buildNumber,
    required Release release,
    required String operatingSystem,
    required String operatingSystemVersion,
    required Environment environment,
  }) = _AppInfoEntity;

  /// Subscription panels pick the payload format from this UA, so its wording matters:
  /// it must NOT contain "clash". Panels that understand both clash and sing-box check
  /// clash first, then serve **Clash YAML**; the core converts that with clash2singbox,
  /// and every outbound type clash2singbox does not know (e.g. anytls) is silently
  /// dropped, so the profile ends up missing most of its nodes.
  /// Verified 2026-09-13 on cpdd.one and yfjc.xyz: removing "ClashMeta" makes both
  /// return native sing-box JSON with all anytls outbounds preserved.
  /// Keep "sing-box" (panels switch to sing-box JSON) and "v2ray" (old panels keep
  /// replying with share links, which the core still converts via ray2sing).
  String get userAgent => "HiddifyNext/$version ($operatingSystem) sing-box v2ray";

  String get presentVersion => environment == Environment.prod ? version : "$version ${environment.name}";

  /// formats app info for sharing
  String format() =>
      '''
$name v$version ($buildNumber) [${environment.name}]
${release.name} release
$operatingSystem [$operatingSystemVersion]''';
}
