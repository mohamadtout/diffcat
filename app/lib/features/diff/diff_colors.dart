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

/// Every slot of [c], by name (a profile's full set of colors).
Map<String, int> _slotsJson(DiffColors c) => {for (final slot in DiffColorSlot.values) slot.name: c[slot].toARGB32()};

/// Colors read back from JSON, skipping unknown slots and junk values.
Map<DiffColorSlot, Color> _slotsFrom(Object? m) => {
  if (m is Map<String, dynamic>)
    for (final e in m.entries)
      if (DiffColorSlot.values.asNameMap()[e.key] case final slot? when e.value is int) slot: Color(e.value as int),
};

/// The chosen palette, the user's own profiles, the presets they deleted, and
/// any colors they changed on a preset (per brightness).
///
/// A preset's edits are overrides on top of it, dropped when switching away.
/// A profile owns its colors: editing one changes the profile itself.
class DiffColorSettings {
  const DiffColorSettings({
    this.palette = 'github',
    this.light = const {},
    this.dark = const {},
    this.profiles = const [],
    this.hidden = const {},
  });

  factory DiffColorSettings.fromJson(Map<String, dynamic> j) => DiffColorSettings(
    palette: (j['palette'] as String?) ?? 'github',
    light: _slotsFrom(j['light']),
    dark: _slotsFrom(j['dark']),
    profiles: [
      if (j['profiles'] case final List<dynamic> list)
        for (final p in list)
          if (p case {'id': final String id, 'label': final String label})
            DiffPalette(
              id,
              label,
              DiffColors.light.withAll(_slotsFrom(p['light'])),
              DiffColors.dark.withAll(_slotsFrom(p['dark'])),
            ),
    ],
    hidden: {if (j['hidden'] case final List<dynamic> list) ...list.whereType<String>()},
  );

  final String palette;

  /// Changes on top of a preset (empty while a profile is selected).
  final Map<DiffColorSlot, Color> light;
  final Map<DiffColorSlot, Color> dark;

  /// The user's own palettes, oldest first.
  final List<DiffPalette> profiles;

  /// Ids of deleted presets ("Reset colors" brings them back).
  final Set<String> hidden;

  /// Presets that weren't deleted, then the user's profiles.
  List<DiffPalette> get available => [
    for (final p in diffPalettes)
      if (!hidden.contains(p.id)) p,
    ...profiles,
  ];

  /// The palette in use. If it's gone, the first one left; GitHub's colors if
  /// everything was deleted.
  DiffPalette get preset {
    final all = available;
    return all.where((p) => p.id == palette).firstOrNull ?? all.firstOrNull ?? diffPalettes.first;
  }

  bool isProfile(String id) => profiles.any((p) => p.id == id);

  bool get editingProfile => isProfile(preset.id);

  DiffColors get lightColors => preset.light.withAll(light);
  DiffColors get darkColors => preset.dark.withAll(dark);

  Map<DiffColorSlot, Color> overrides({required bool dark}) => dark ? this.dark : light;

  DiffColorSettings copyWith({
    String? palette,
    Map<DiffColorSlot, Color>? light,
    Map<DiffColorSlot, Color>? dark,
    List<DiffPalette>? profiles,
    Set<String>? hidden,
  }) => DiffColorSettings(
    palette: palette ?? this.palette,
    light: light ?? this.light,
    dark: dark ?? this.dark,
    profiles: profiles ?? this.profiles,
    hidden: hidden ?? this.hidden,
  );

  /// Switches palette, dropping changes made on top of the old one.
  DiffColorSettings select(String id) => copyWith(palette: id, light: const {}, dark: const {});

  /// Sets one color of the palette in use: into the profile itself, or as an
  /// override on a preset ([color] null goes back to the preset's color).
  DiffColorSettings withOverride(DiffColorSlot slot, Color? color, {required bool dark}) {
    final current = preset;
    if (isProfile(current.id)) {
      if (color == null) return this;
      final edited = DiffPalette(
        current.id,
        current.label,
        dark ? current.light : current.light.withAll({slot: color}),
        dark ? current.dark.withAll({slot: color}) : current.dark,
      );
      return copyWith(profiles: [for (final p in profiles) p.id == current.id ? edited : p]);
    }
    final next = {...overrides(dark: dark)};
    color == null ? next.remove(slot) : next[slot] = color;
    return copyWith(light: dark ? light : next, dark: dark ? next : this.dark);
  }

  /// A new profile named [label] with the colors shown now (light and dark),
  /// selected. [id] must be unique.
  DiffColorSettings withNewProfile(String id, String label) => copyWith(
    palette: id,
    light: const {},
    dark: const {},
    profiles: [...profiles, DiffPalette(id, label, lightColors, darkColors)],
  );

  DiffColorSettings renamed(String id, String label) =>
      copyWith(profiles: [for (final p in profiles) p.id == id ? DiffPalette(p.id, label, p.light, p.dark) : p]);

  /// Deletes a profile, or hides a preset. The last palette can't be deleted.
  /// Deleting the one in use switches to the first one left.
  DiffColorSettings without(String id) {
    if (available.length <= 1) return this;
    final next = isProfile(id)
        ? copyWith(
            profiles: [
              for (final p in profiles)
                if (p.id != id) p,
            ],
          )
        : copyWith(hidden: {...hidden, id});
    return palette == id || preset.id == id ? next.select(next.available.first.id) : next;
  }

  /// "Reset colors": GitHub colors, every preset back, preset edits dropped.
  /// The user's profiles are kept.
  DiffColorSettings reset() => DiffColorSettings(profiles: profiles);

  Map<String, dynamic> toJson() => {
    'palette': palette,
    'light': {for (final e in light.entries) e.key.name: e.value.toARGB32()},
    'dark': {for (final e in dark.entries) e.key.name: e.value.toARGB32()},
    'profiles': [
      for (final p in profiles)
        {'id': p.id, 'label': p.label, 'light': _slotsJson(p.light), 'dark': _slotsJson(p.dark)},
    ],
    'hidden': hidden.toList(),
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

  void setPalette(String id) => _save(state.select(id));

  void setColor(DiffColorSlot slot, Color? color, {required bool dark}) =>
      _save(state.withOverride(slot, color, dark: dark));

  /// Saves the colors shown now as a new profile and selects it.
  void createProfile(String label) =>
      _save(state.withNewProfile('profile-${DateTime.now().microsecondsSinceEpoch}', label));

  void renameProfile(String id, String label) => _save(state.renamed(id, label));

  void delete(String id) => _save(state.without(id));

  void reset() => _save(state.reset());
}
