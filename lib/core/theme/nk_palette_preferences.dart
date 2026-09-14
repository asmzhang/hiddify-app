import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/theme/nk_palette.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'nk_palette_preferences.g.dart';

/// NekoBox 复刻 · 主题色板偏好。
///
/// 与 [ThemePreferences]（明暗模式）正交：模式决定亮暗，色板决定主色调。
/// 动态取色（Material You）已随本次复刻退役，不再有第三条配色来源。
@Riverpod(keepAlive: true)
class NkPalettePreferences extends _$NkPalettePreferences {
  @override
  NkPalette build() {
    final persisted = ref.watch(sharedPreferencesProvider).requireValue.getString("nk_palette");
    if (persisted == null) return NkPalette.pink;
    return NkPalette.values.asNameMap()[persisted] ?? NkPalette.pink;
  }

  Future<void> changePalette(NkPalette value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).requireValue.setString("nk_palette", value.name);
  }
}
