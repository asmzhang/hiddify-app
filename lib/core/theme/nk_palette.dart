import 'package:flutter/material.dart';

/// NekoBox 复刻 · 主题色板。
///
/// 对标 NekoBox `themes.xml` 的可选主题色：每套五个语义色
/// （主色 500 / 深主色 700 / 强调色 / 底部条 / 浅容器），与原生主题一一对应。
/// 明暗由 [AppThemeMode] 决定，这里只管"主色调"维度。
enum NkPalette {
  pink('Pink', Color(0xFFE91E63), Color(0xFFC2185B), Color(0xFFFF4081), Color(0xFFF06292), Color(0xFFF8BBD0)),
  blue('Blue', Color(0xFF2196F3), Color(0xFF1976D2), Color(0xFF64B5F6), Color(0xFF42A5F5), Color(0xFFBBDEFB)),
  teal('Teal', Color(0xFF009688), Color(0xFF00796B), Color(0xFF4DB6AC), Color(0xFF26A69A), Color(0xFFB2DFDB)),
  amber('Amber', Color(0xFFFFC107), Color(0xFFFFA000), Color(0xFFFFD54F), Color(0xFFFFCA28), Color(0xFFFFECB3)),
  bilibili('Bilibili', Color(0xFFFB7299), Color(0xFFD44A72), Color(0xFFFB7299), Color(0xFFFB7299), Color(0xFFFDD5E0));

  const NkPalette(this.label, this.primary, this.primaryDark, this.accent, this.bar, this.container);

  /// 展示名（色名各语言通用，不做翻译）。
  final String label;

  /// colorPrimary（toolbar / tab 背景 / 选中指示条）。
  final Color primary;

  /// colorPrimaryDark（状态栏 / 抽屉头）。
  final Color primaryDark;

  /// colorAccent（FAB / 开关激活态）。
  final Color accent;

  /// 底部 StatsBar（colorMaterial300）。
  final Color bar;

  /// colorMaterial100（浅容器 / 悬停底色）。
  final Color container;

  /// 派生完整 M3 [ColorScheme]：关键槽位直接钉 NekoBox 原色，
  /// 其余槽位由 fromSeed 用主色生成，保证组件生态不至于缺色。
  ColorScheme scheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(seedColor: primary, brightness: brightness);
    if (brightness == Brightness.light) {
      return base.copyWith(
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: container,
        onPrimaryContainer: primaryDark,
        secondary: accent,
        onSecondary: Colors.white,
        secondaryContainer: container,
        onSecondaryContainer: primaryDark,
      );
    }
    return base.copyWith(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primaryDark,
      onPrimaryContainer: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      secondaryContainer: primaryDark,
      onSecondaryContainer: Colors.white,
    );
  }
}
