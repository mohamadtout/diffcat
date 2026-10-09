import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage.dart';
import '../../core/theme/app_theme.dart';

/// A ready-made set of diff colors for light and dark mode.
class DiffPalette {
  const DiffPalette(this.id, this.label, this.light, this.dark);

  final String id;
  final String label;
  final DiffColors light;
  final DiffColors dark;
}

const diffPalettes = [
  DiffPalette('github', 'GitHub', DiffColors.light, DiffColors.dark),
  // Blue for added, orange for removed: GitHub's colorblind-friendly scheme.
  DiffPalette(
    'colorblind',
    'Colorblind',
    DiffColors(
      addBg: Color(0xFFDDF4FF),
      addFg: Color(0xFF0969DA),
      delBg: Color(0xFFFFF1E5),
      delFg: Color(0xFFBC4C00),
      hunkBg: Color(0xFFF6F8FA),
      hunkFg: Color(0xFF57606A),
      gutter: Color(0xFF8C959F),
    ),
    DiffColors(
      addBg: Color(0xFF0C2D48),
      addFg: Color(0xFF58A6FF),
      delBg: Color(0xFF3A2112),
      delFg: Color(0xFFDB6D28),
      hunkBg: Color(0xFF161B22),
      hunkFg: Color(0xFF8B949E),
      gutter: Color(0xFF6E7681),
    ),
  ),
  DiffPalette(
    'high-contrast',
    'High contrast',
    DiffColors(
      addBg: Color(0xFFC6F6CF),
      addFg: Color(0xFF024C1A),
      delBg: Color(0xFFFFCECB),
      delFg: Color(0xFF86061D),
      hunkBg: Color(0xFFC8E1FF),
      hunkFg: Color(0xFF023B95),
      gutter: Color(0xFF40464E),
    ),
    DiffColors(
      addBg: Color(0xFF03401A),
      addFg: Color(0xFF7EE787),
      delBg: Color(0xFF5C0E15),
      delFg: Color(0xFFFF9492),
      hunkBg: Color(0xFF0C2D6B),
      hunkFg: Color(0xFF91CBFF),
      gutter: Color(0xFFB7BDC8),
    ),
  ),
  DiffPalette(
    'solarized',
    'Solarized',
    DiffColors(
      addBg: Color(0xFFEEF0D2),
      addFg: Color(0xFF859900),
      delBg: Color(0xFFF9E1D9),
      delFg: Color(0xFFDC322F),
      hunkBg: Color(0xFFEEE8D5),
      hunkFg: Color(0xFF268BD2),
      gutter: Color(0xFF93A1A1),
    ),
    DiffColors(
      addBg: Color(0xFF0E3A2A),
      addFg: Color(0xFF859900),
      delBg: Color(0xFF3A1F27),
      delFg: Color(0xFFDC322F),
      hunkBg: Color(0xFF073642),
      hunkFg: Color(0xFF268BD2),
      gutter: Color(0xFF586E75),
    ),
  ),
  DiffPalette(
    'neon',
    'Neon',
    DiffColors(
      addBg: Color(0xFFE3FFF4),
      addFg: Color(0xFF00A86B),
      delBg: Color(0xFFFFE6F4),
      delFg: Color(0xFFD6007E),
      hunkBg: Color(0xFFEDE7FF),
      hunkFg: Color(0xFF6E40FF),
      gutter: Color(0xFF9A8FB5),
    ),
    DiffColors(
      addBg: Color(0xFF062A22),
      addFg: Color(0xFF2CFFB2),
      delBg: Color(0xFF2E0A22),
      delFg: Color(0xFFFF4FB8),
      hunkBg: Color(0xFF1C1238),
      hunkFg: Color(0xFFB69CFF),
      gutter: Color(0xFF6C6488),
    ),
  ),
];

/// The chosen palette plus any colors the user changed, per brightness.
class DiffColorSettings {
  const DiffColorSettings({this.palette = 'github', this.light = const {}, this.dark = const {}});

  factory DiffColorSettings.fromJson(Map<String, dynamic> j) {
    Map<DiffColorSlot, Color> slots(Object? m) => {
      if (m is Map<String, dynamic>)
        for (final e in m.entries)
          if (DiffColorSlot.values.asNameMap()[e.key] case final slot? when e.value is int) slot: Color(e.value as int),
    };
    return DiffColorSettings(
      palette: (j['palette'] as String?) ?? 'github',
      light: slots(j['light']),
      dark: slots(j['dark']),
    );
  }

  final String palette;
  final Map<DiffColorSlot, Color> light;
  final Map<DiffColorSlot, Color> dark;

  DiffPalette get preset => diffPalettes.firstWhere((p) => p.id == palette, orElse: () => diffPalettes.first);

  DiffColors get lightColors => preset.light.withAll(light);
  DiffColors get darkColors => preset.dark.withAll(dark);

  Map<DiffColorSlot, Color> overrides({required bool dark}) => dark ? this.dark : light;

  DiffColorSettings withOverride(DiffColorSlot slot, Color? color, {required bool dark}) {
    final next = {...overrides(dark: dark)};
    color == null ? next.remove(slot) : next[slot] = color;
    return DiffColorSettings(palette: palette, light: dark ? light : next, dark: dark ? next : this.dark);
  }

  Map<String, dynamic> toJson() => {
    'palette': palette,
    'light': {for (final e in light.entries) e.key.name: e.value.toARGB32()},
    'dark': {for (final e in dark.entries) e.key.name: e.value.toARGB32()},
  };
}

final diffColorsProvider = NotifierProvider<DiffColorsNotifier, DiffColorSettings>(DiffColorsNotifier.new);

class DiffColorsNotifier extends Notifier<DiffColorSettings> {
  @override
  DiffColorSettings build() {
    final raw = ref.watch(sharedPrefsProvider).getString(StoreKeys.diffColors);
    if (raw == null) return const DiffColorSettings();
    try {
      return DiffColorSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const DiffColorSettings();
    }
  }

  void _save(DiffColorSettings s) {
    state = s;
    ref.read(sharedPrefsProvider).setString(StoreKeys.diffColors, jsonEncode(s.toJson()));
  }

  /// Switches palette, dropping individual changes (they were made on top of
  /// the old one).
  void setPalette(String id) => _save(DiffColorSettings(palette: id));

  void setColor(DiffColorSlot slot, Color? color, {required bool dark}) =>
      _save(state.withOverride(slot, color, dark: dark));

  void reset() => _save(const DiffColorSettings());
}
