import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/nk_palette.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';

class AppTheme {
  AppTheme(this.mode, this.fontFamily, {this.palette = NkPalette.pink});
  final AppThemeMode mode;
  final String fontFamily;

  /// NekoBox 复刻 · 当前主题色板（决定主色调）。
  final NkPalette palette;

  /// NekoBox 复刻 · 全局 Toolbar：主色底 + 主色前景（对标各页 actionBar 的 colorPrimary）。
  ///
  /// 之前只有"配置"页本地设了主色底，其余页面仍是默认 surface 底 → 各页观感不一致；
  /// 统一到这里，页面无需再各自设置。
  AppBarTheme _appBarTheme(ColorScheme scheme) => AppBarTheme(
    backgroundColor: scheme.primary,
    foregroundColor: scheme.onPrimary,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    iconTheme: IconThemeData(color: scheme.onPrimary),
    actionsIconTheme: IconThemeData(color: scheme.onPrimary),
    titleTextStyle: TextStyle(color: scheme.onPrimary, fontSize: 20, fontWeight: FontWeight.w500),
  );

  ThemeData lightTheme() {
    final scheme = palette.scheme(Brightness.light);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      appBarTheme: _appBarTheme(scheme),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
      ),
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );
  }

  ThemeData darkTheme() {
    final scheme = palette.scheme(Brightness.dark);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: mode.trueBlack ? Colors.black : null,
      fontFamily: fontFamily,
      appBarTheme: _appBarTheme(scheme),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
      ),
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );
  }

  CupertinoThemeData cupertinoThemeData(bool sysDark) {
    final bool isDark = switch (mode) {
      AppThemeMode.system => sysDark,
      AppThemeMode.light => false,
      AppThemeMode.dark => true,
      AppThemeMode.black => true,
    };
    final def = CupertinoThemeData(brightness: isDark ? Brightness.dark : Brightness.light);
    // final def = CupertinoThemeData(brightness: Brightness.dark);

    // return def;
    final defaultMaterialTheme = isDark ? darkTheme() : lightTheme();
    return MaterialBasedCupertinoThemeData(
      materialTheme: defaultMaterialTheme.copyWith(
        cupertinoOverrideTheme: def.copyWith(
          textTheme: CupertinoTextThemeData(
            textStyle: def.textTheme.textStyle.copyWith(fontFamily: fontFamily),
            actionTextStyle: def.textTheme.actionTextStyle.copyWith(fontFamily: fontFamily),
            navActionTextStyle: def.textTheme.navActionTextStyle.copyWith(fontFamily: fontFamily),
            navTitleTextStyle: def.textTheme.navTitleTextStyle.copyWith(fontFamily: fontFamily),
            navLargeTitleTextStyle: def.textTheme.navLargeTitleTextStyle.copyWith(fontFamily: fontFamily),
            pickerTextStyle: def.textTheme.pickerTextStyle.copyWith(fontFamily: fontFamily),
            dateTimePickerTextStyle: def.textTheme.dateTimePickerTextStyle.copyWith(fontFamily: fontFamily),
            tabLabelTextStyle: def.textTheme.tabLabelTextStyle.copyWith(fontFamily: fontFamily),
          ).copyWith(),
          barBackgroundColor: def.barBackgroundColor,
          scaffoldBackgroundColor: def.scaffoldBackgroundColor,
        ),
      ),
    );
  }
}
