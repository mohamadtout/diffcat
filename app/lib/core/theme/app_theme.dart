import 'dart:io' show Platform;

import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFF2F81F7);

  /// [diff]: the user's diff colors (Settings → Code view), else the defaults.
  static ThemeData light({DiffColors? diff}) => _build(Brightness.light, diff);
  static ThemeData dark({DiffColors? diff}) => _build(Brightness.dark, diff);

  static ThemeData _build(Brightness b, DiffColors? diff) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      extensions: [diff ?? (b == Brightness.dark ? DiffColors.dark : DiffColors.light)],
      listTileTheme: const ListTileThemeData(dense: false),
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }

  /// Platform monospace font, no bundled asset needed.
  static String get monoFamily => Platform.isIOS ? 'Menlo' : 'monospace';

  static const monoFallback = ['Menlo', 'Roboto Mono', 'Courier'];

  static TextStyle mono(BuildContext context, {double size = 12.5}) => TextStyle(
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    fontSize: size,
    height: 1.35,
    color: Theme.of(context).colorScheme.onSurface,
  );
}

/// The editable colors of [DiffColors].
enum DiffColorSlot {
  addBg('Added line background'),
  addFg('Added text and markers'),
  delBg('Removed line background'),
  delFg('Removed text and markers'),
  hunkBg('Hunk header background'),
  hunkFg('Hunk header text'),
  gutter('Line numbers');

  const DiffColorSlot(this.label);
  final String label;
}

/// Colors used by diff rendering and change badges.
@immutable
class DiffColors extends ThemeExtension<DiffColors> {
  const DiffColors({
    required this.addBg,
    required this.addFg,
    required this.delBg,
    required this.delFg,
    required this.hunkBg,
    required this.hunkFg,
    required this.gutter,
  });

  static const light = DiffColors(
    addBg: Color(0xFFE6FFEC),
    addFg: Color(0xFF1A7F37),
    delBg: Color(0xFFFFEBE9),
    delFg: Color(0xFFCF222E),
    hunkBg: Color(0xFFDDF4FF),
    hunkFg: Color(0xFF0969DA),
    gutter: Color(0xFF8C959F),
  );

  static const dark = DiffColors(
    addBg: Color(0xFF12261E),
    addFg: Color(0xFF3FB950),
    delBg: Color(0xFF25171C),
    delFg: Color(0xFFF85149),
    hunkBg: Color(0xFF121D2F),
    hunkFg: Color(0xFF58A6FF),
    gutter: Color(0xFF6E7681),
  );

  final Color addBg;
  final Color addFg;
  final Color delBg;
  final Color delFg;
  final Color hunkBg;
  final Color hunkFg;
  final Color gutter;

  static DiffColors of(BuildContext context) => Theme.of(context).extension<DiffColors>() ?? light;

  Color operator [](DiffColorSlot slot) => switch (slot) {
    DiffColorSlot.addBg => addBg,
    DiffColorSlot.addFg => addFg,
    DiffColorSlot.delBg => delBg,
    DiffColorSlot.delFg => delFg,
    DiffColorSlot.hunkBg => hunkBg,
    DiffColorSlot.hunkFg => hunkFg,
    DiffColorSlot.gutter => gutter,
  };

  /// These colors with [overrides] applied.
  DiffColors withAll(Map<DiffColorSlot, Color> overrides) => overrides.isEmpty
      ? this
      : DiffColors(
          addBg: overrides[DiffColorSlot.addBg] ?? addBg,
          addFg: overrides[DiffColorSlot.addFg] ?? addFg,
          delBg: overrides[DiffColorSlot.delBg] ?? delBg,
          delFg: overrides[DiffColorSlot.delFg] ?? delFg,
          hunkBg: overrides[DiffColorSlot.hunkBg] ?? hunkBg,
          hunkFg: overrides[DiffColorSlot.hunkFg] ?? hunkFg,
          gutter: overrides[DiffColorSlot.gutter] ?? gutter,
        );

  @override
  DiffColors copyWith() => this;

  @override
  DiffColors lerp(DiffColors? other, double t) => t < 0.5 ? this : (other ?? this);
}
