import 'package:circle_flags/circle_flags.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import "package:simple_icons/simple_icons.dart";

/// 国旗 / 运营商徽标 —— **纯展示件**（circle_flags + simple_icons），无任何业务依赖。
///
/// 原在 `features/proxy/active/ip_widget.dart`；设置页的选择器与统计卡都要用它，
/// 放 core 才能让 `core/router/dialog/widgets/setting_picker_dialog` 不再反向依赖 feature。

class IPCountryFlag extends HookConsumerWidget {
  const IPCountryFlag({
    required this.countryCode,
    this.organization,
    this.size = 16,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final String? countryCode;
  final double size;

  final EdgeInsetsGeometry padding;

  final String? organization;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    return Semantics(
      label: t.pages.proxies.ipInfo.country,
      child: Padding(
        padding: padding,
        child: (countryCode?.isEmpty ?? true)
            ? Icon(FluentIcons.question_circle_20_regular, size: size)
            : SizedBox(
                width: size,
                height: size,
                child: Stack(
                  textDirection: Directionality.of(context),
                  alignment: Alignment.center,
                  children: [
                    CircleFlag(
                      // key: ValueKey(countryCode),
                      countryCode!.toLowerCase() == "ir" ? "ir-shir" : countryCode!,
                      size: size - 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8), // Rounded effect
                      ),
                    ),
                    if (organization != null)
                      Positioned.directional(
                        textDirection: Directionality.of(context),
                        bottom: 0,
                        end: 0,
                        child: OrganisationFlag(organization: organization!, size: size / 2.5),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class OrgIconData {
  final IconData icon;
  final Color color;

  const OrgIconData(this.icon, this.color);
}

// Map of organization keywords to icon and color
const Map<String, OrgIconData> organizationData = {
  "cloudflare": OrgIconData(SimpleIcons.cloudflare, SimpleIconColors.cloudflare),
  "hetzner": OrgIconData(SimpleIcons.hetzner, SimpleIconColors.hetzner),
  "ovh": OrgIconData(SimpleIcons.ovh, SimpleIconColors.ovh),
  "azure": OrgIconData(SimpleIcons.microsoftazure, SimpleIconColors.microsoftazure),
  "amazon": OrgIconData(SimpleIcons.amazonaws, SimpleIconColors.amazonaws),
  "oracle": OrgIconData(SimpleIcons.oracle, SimpleIconColors.oracle),
  "fastly": OrgIconData(SimpleIcons.fastly, SimpleIconColors.fastly),
  "digitalocean": OrgIconData(SimpleIcons.digitalocean, SimpleIconColors.digitalocean),
  "alibaba": OrgIconData(SimpleIcons.alibabacloud, SimpleIconColors.alibabacloud),
  "google": OrgIconData(SimpleIcons.googlecloud, SimpleIconColors.googlecloud),
  "starlink": OrgIconData(SimpleIcons.satellite, SimpleIconColors.satellite),
};

class OrganisationFlag extends HookConsumerWidget {
  const OrganisationFlag({required this.organization, this.size = 24, super.key});

  final String organization;
  final double size;

  // Function to create flag widget with icon and color
  Widget getFlagWidget({
    required Widget widget,
    required String organization,
    required double size,
    required String label,
    required Color color,
  }) {
    return Semantics(
      label: "$label $organization",
      child: Container(
        width: size,
        height: size,

        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(100)),
        // padding: const ,
        child: widget,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    for (final entry in organizationData.entries) {
      if (organization.toLowerCase().contains(entry.key)) {
        return getFlagWidget(
          widget: Icon(entry.value.icon, color: Colors.white, size: size - 6),
          color: entry.value.color,
          organization: organization,
          size: size,
          label: t.pages.proxies.ipInfo.organization,
        );
      }
    }

    // Return empty widget if no match is found
    return const SizedBox.shrink();
  }
}

/// 从"地区展示名"里抠出国家码并渲染旗标（如 `"China (cn)"` → `cn`）。
/// 解析不到就返回 null，由调用方决定是否留空。
Widget? countryFlagByTitle(String title, {double size = 32}) {
  if (title.isEmpty) return null;
  final match = RegExp(r'\(([^)]+)\)$').firstMatch(title);
  final countryCode = match?.group(1);
  if (countryCode == null) return null;
  return IPCountryFlag(countryCode: countryCode, size: size);
}
