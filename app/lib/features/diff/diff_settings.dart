import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/code_fonts.dart';

/// How diffs and files read (Settings → Code view). Colors are separate:
/// see diff_colors.dart.
class DiffSettings {
  const DiffSettings({
    this.wrap = false,
    this.fontSize = defaultFontSize,
    this.font = CodeFont.system,
    this.fullFile = false,
    this.syntax = true,
  });

  static const defaultFontSize = 12.5;
  static const minFontSize = 9.0;
  static const maxFontSize = 22.0;

  final bool wrap;
  final double fontSize;
  final CodeFont font;

  /// Show modified files whole, with their changes in place, instead of only
  /// the changed hunks. Each file costs one more request when it's shown.
  final bool fullFile;

  /// Syntax highlighting and word-level emphasis of changed lines.
  final bool syntax;

  DiffSettings copyWith({bool? wrap, double? fontSize, CodeFont? font, bool? fullFile, bool? syntax}) => DiffSettings(
    wrap: wrap ?? this.wrap,
    fontSize: fontSize ?? this.fontSize,
    font: font ?? this.font,
    fullFile: fullFile ?? this.fullFile,
    syntax: syntax ?? this.syntax,
  );

  /// Monospace style for code at these settings.
  TextStyle codeStyle(BuildContext context) =>
      AppTheme.mono(context, size: fontSize).copyWith(fontFamily: font.family, fontFamilyFallback: font.fallback);
}

final diffSettingsProvider = NotifierProvider<DiffSettingsNotifier, DiffSettings>(DiffSettingsNotifier.new);

class DiffSettingsNotifier extends Notifier<DiffSettings> {
  @override
  DiffSettings build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return DiffSettings(
      wrap: prefs.getBool(StoreKeys.diffWrap) ?? false,
      fontSize: prefs.getDouble(StoreKeys.diffFontSize) ?? DiffSettings.defaultFontSize,
      font: CodeFont.byName(prefs.getString(StoreKeys.diffFont)),
      fullFile: prefs.getBool(StoreKeys.diffFullFile) ?? false,
      syntax: prefs.getBool(StoreKeys.diffSyntax) ?? true,
    );
  }

  void toggleWrap() {
    state = state.copyWith(wrap: !state.wrap);
    ref.read(sharedPrefsProvider).setBool(StoreKeys.diffWrap, state.wrap);
  }

  void setFontSize(double size) {
    final clamped = size.clamp(DiffSettings.minFontSize, DiffSettings.maxFontSize);
    if (clamped == state.fontSize) return;
    state = state.copyWith(fontSize: clamped);
    ref.read(sharedPrefsProvider).setDouble(StoreKeys.diffFontSize, clamped);
  }

  void setFont(CodeFont font) {
    state = state.copyWith(font: font);
    ref.read(sharedPrefsProvider).setString(StoreKeys.diffFont, font.name);
  }

  void setSyntax(bool on) {
    state = state.copyWith(syntax: on);
    ref.read(sharedPrefsProvider).setBool(StoreKeys.diffSyntax, on);
  }

  void setFullFile(bool on) {
    state = state.copyWith(fullFile: on);
    ref.read(sharedPrefsProvider).setBool(StoreKeys.diffFullFile, on);
  }
}
