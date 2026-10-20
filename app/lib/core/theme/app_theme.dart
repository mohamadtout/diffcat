import 'dart:io' show Platform;

import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFF2F81F7);

  /// [diff]: the user's diff colors (Settings → Code view), else the defaults.
  static ThemeData light({DiffColors? diff}) => _build(Brightness.light, diff);
  static ThemeData dark({DiffColors? diff}) => _build(Brightness.dark, diff);

  static ThemeData _build(Brightness b, DiffColors? diff) {
    final scheme = schemeFor(b);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      extensions: [diff ?? (b == Brightness.dark ? DiffColors.dark : DiffColors.light), StatusColors.of(b)],
      listTileTheme: const ListTileThemeData(dense: false),
      appBarTheme: const AppBarTheme(centerTitle: false),
      // One text field style everywhere; fields that sit in a bar set InputBorder.none themselves.
      inputDecorationTheme: const InputDecorationThemeData(border: OutlineInputBorder()),
    );
  }

  /// The app's colors. `fidelity` keeps primary close to the brand blue (the
  /// default `tonalSpot` washes it out to slate), and tertiary, used for
  /// "downloaded" accents, is a calm teal instead of the variant's orange.
  /// The contrast pairs are checked in test/core/app_theme_test.dart.
  static ColorScheme schemeFor(Brightness b) {
    final light = b == Brightness.light;
    return ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: b,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ).copyWith(
      tertiary: light ? const Color(0xFF00696E) : const Color(0xFF4FD8DF),
      onTertiary: light ? Colors.white : const Color(0xFF003739),
      tertiaryContainer: light ? const Color(0xFFC8F4F5) : const Color(0xFF004F53),
      onTertiaryContainer: light ? const Color(0xFF002022) : const Color(0xFFC8F4F5),
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
    gutter: Color(0xFF656D76),
  );

  // Row tints strong enough to tell apart from the dark surface at night.
  static const dark = DiffColors(
    addBg: Color(0xFF1A3A28),
    addFg: Color(0xFF3FB950),
    delBg: Color(0xFF3D1E24),
    delFg: Color(0xFFF85149),
    hunkBg: Color(0xFF121D2F),
    hunkFg: Color(0xFF58A6FF),
    gutter: Color(0xFF8B949E),
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

/// Colors for the state of CI runs, pull requests and reviews. Separate from
/// [DiffColors], which users edit for diffs: a colorblind diff palette
/// shouldn't recolor "passed" and "failed". Always paired with a distinct icon.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.success,
    required this.failure,
    required this.warning,
    required this.merged,
    required this.neutral,
  });

  static const light = StatusColors(
    success: Color(0xFF1A7F37),
    failure: Color(0xFFCF222E),
    warning: Color(0xFF9A6700),
    merged: Color(0xFF8250DF),
    neutral: Color(0xFF6E7781),
  );

  static const dark = StatusColors(
    success: Color(0xFF3FB950),
    failure: Color(0xFFF85149),
    warning: Color(0xFFD29922),
    merged: Color(0xFFA371F7),
    neutral: Color(0xFF8B949E),
  );

  static StatusColors of(Brightness b) => b == Brightness.dark ? dark : light;

  /// Passed, approved, open.
  final Color success;

  /// Failed, closed, changes requested.
  final Color failure;

  /// Running, queued, waiting for something.
  final Color warning;
  final Color merged;

  /// Skipped, cancelled, draft.
  final Color neutral;

  static StatusColors from(BuildContext context) =>
      Theme.of(context).extension<StatusColors>() ?? of(Theme.of(context).brightness);

  @override
  StatusColors copyWith() => this;

  @override
  StatusColors lerp(StatusColors? other, double t) => t < 0.5 ? this : (other ?? this);
}
