import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/storage/storage.dart';
import '../../core/theme/code_fonts.dart';
import 'terminal_themes.dart';

enum BackgroundKind { none, gradient, image }

enum StatusBarPosition { top, bottom }

enum StatusBarStyle { powerline, plain }

/// What the status bar shows, in this order.
enum StatusSegment {
  host('user@host'),
  path('Folder'),
  branch('Git branch'),
  sync('Ahead/behind'),
  changes('Changed files');

  const StatusSegment(this.label);
  final String label;
}

/// How the terminal looks. One profile for every host; stored as JSON.
class TerminalAppearance {
  const TerminalAppearance({
    this.theme = followAppPreset,
    this.font = CodeFont.jetBrainsMono,
    this.fontSize = 13,
    this.lineHeight = 1.2,
    this.cursor = TerminalCursorType.block,
    this.background = BackgroundKind.none,
    this.gradient = 'aurora',
    this.imagePath,
    this.backgroundOpacity = 0.35,
    this.backgroundBlur = 0,
    this.statusBar = true,
    this.statusPosition = StatusBarPosition.top,
    this.statusStyle = StatusBarStyle.powerline,
    this.segments = const {StatusSegment.path, StatusSegment.branch, StatusSegment.sync, StatusSegment.changes},
    this.shellIntegration = false,
    this.keyToolbar = true,
  });

  factory TerminalAppearance.fromJson(Map<String, dynamic> j) {
    const d = TerminalAppearance();
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) => values.asNameMap()[name] ?? fallback;
    double num_(String k, double fallback, double min, double max) =>
        ((j[k] as num?)?.toDouble() ?? fallback).clamp(min, max);
    return TerminalAppearance(
      theme: (j['theme'] as String?) ?? d.theme,
      font: CodeFont.byName(j['font'] as String?),
      fontSize: num_('fontSize', d.fontSize, minFontSize, maxFontSize),
      lineHeight: num_('lineHeight', d.lineHeight, 1, 1.8),
      cursor: pick(TerminalCursorType.values, j['cursor'], d.cursor),
      background: pick(BackgroundKind.values, j['background'], d.background),
      gradient: (j['gradient'] as String?) ?? d.gradient,
      imagePath: j['imagePath'] as String?,
      backgroundOpacity: num_('backgroundOpacity', d.backgroundOpacity, 0, 1),
      backgroundBlur: num_('backgroundBlur', d.backgroundBlur, 0, 20),
      statusBar: (j['statusBar'] as bool?) ?? d.statusBar,
      statusPosition: pick(StatusBarPosition.values, j['statusPosition'], d.statusPosition),
      statusStyle: pick(StatusBarStyle.values, j['statusStyle'], d.statusStyle),
      segments: j['segments'] is List
          ? {for (final s in j['segments'] as List<dynamic>) ?StatusSegment.values.asNameMap()[s]}
          : d.segments,
      shellIntegration: (j['shellIntegration'] as bool?) ?? d.shellIntegration,
      keyToolbar: (j['keyToolbar'] as bool?) ?? d.keyToolbar,
    );
  }

  static const minFontSize = 8.0;
  static const maxFontSize = 24.0;

  /// A [TerminalPreset] id, or [followAppPreset].
  final String theme;
  final CodeFont font;
  final double fontSize;
  final double lineHeight;
  final TerminalCursorType cursor;

  final BackgroundKind background;

  /// A [terminalGradients] key.
  final String gradient;

  /// The picked image, copied into app storage.
  final String? imagePath;

  /// How strongly the gradient or image shows through (0 = not at all).
  final double backgroundOpacity;
  final double backgroundBlur;

  final bool statusBar;
  final StatusBarPosition statusPosition;
  final StatusBarStyle statusStyle;
  final Set<StatusSegment> segments;

  /// Type a small hook into the shell after login so it reports its folder
  /// (OSC 7), which the git status segments need. See shell_integration.dart.
  final bool shellIntegration;
  final bool keyToolbar;

  bool get hasBackground =>
      backgroundOpacity > 0 &&
      switch (background) {
        BackgroundKind.none => false,
        BackgroundKind.gradient => true,
        BackgroundKind.image => imagePath != null,
      };

  TerminalAppearance copyWith({
    String? theme,
    CodeFont? font,
    double? fontSize,
    double? lineHeight,
    TerminalCursorType? cursor,
    BackgroundKind? background,
    String? gradient,
    String? imagePath,
    bool clearImage = false,
    double? backgroundOpacity,
    double? backgroundBlur,
    bool? statusBar,
    StatusBarPosition? statusPosition,
    StatusBarStyle? statusStyle,
    Set<StatusSegment>? segments,
    bool? shellIntegration,
    bool? keyToolbar,
  }) => TerminalAppearance(
    theme: theme ?? this.theme,
    font: font ?? this.font,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    cursor: cursor ?? this.cursor,
    background: background ?? this.background,
    gradient: gradient ?? this.gradient,
    imagePath: clearImage ? null : imagePath ?? this.imagePath,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    backgroundBlur: backgroundBlur ?? this.backgroundBlur,
    statusBar: statusBar ?? this.statusBar,
    statusPosition: statusPosition ?? this.statusPosition,
    statusStyle: statusStyle ?? this.statusStyle,
    segments: segments ?? this.segments,
    shellIntegration: shellIntegration ?? this.shellIntegration,
    keyToolbar: keyToolbar ?? this.keyToolbar,
  );

  Map<String, dynamic> toJson() => {
    'theme': theme,
    'font': font.name,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'cursor': cursor.name,
    'background': background.name,
    'gradient': gradient,
    'imagePath': imagePath,
    'backgroundOpacity': backgroundOpacity,
    'backgroundBlur': backgroundBlur,
    'statusBar': statusBar,
    'statusPosition': statusPosition.name,
    'statusStyle': statusStyle.name,
    'segments': [
      for (final s in StatusSegment.values)
        if (segments.contains(s)) s.name,
    ],
    'shellIntegration': shellIntegration,
    'keyToolbar': keyToolbar,
  };
}

final terminalAppearanceProvider = NotifierProvider<TerminalAppearanceNotifier, TerminalAppearance>(
  TerminalAppearanceNotifier.new,
);

class TerminalAppearanceNotifier extends Notifier<TerminalAppearance> {
  @override
  TerminalAppearance build() {
    final raw = ref.watch(sharedPrefsProvider).getString(StoreKeys.terminalAppearance);
    if (raw == null) return const TerminalAppearance();
    try {
      return TerminalAppearance.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const TerminalAppearance(); // unreadable: start over rather than crash the terminal
    }
  }

  void update(TerminalAppearance Function(TerminalAppearance a) change) {
    state = change(state);
    ref.read(sharedPrefsProvider).setString(StoreKeys.terminalAppearance, jsonEncode(state.toJson()));
  }

  /// Copies [source] into app storage (the picker's copy can be temporary)
  /// and uses it as the background.
  Future<void> setImage(File source, Directory storage) async {
    await storage.create(recursive: true);
    final old = state.imagePath;
    // A new name each time, so Flutter's image cache doesn't show the old one.
    final ext = source.path.contains('.') ? source.path.split('.').last.toLowerCase() : 'img';
    final target = File('${storage.path}/background-${DateTime.now().millisecondsSinceEpoch}.$ext');
    await source.copy(target.path);
    update((a) => a.copyWith(background: BackgroundKind.image, imagePath: target.path));
    if (old != null && old != target.path) await _delete(old);
  }

  /// Deletes the copied image and goes back to a plain background.
  Future<void> removeImage() async {
    final old = state.imagePath;
    update((a) => a.copyWith(background: BackgroundKind.none, clearImage: true));
    if (old != null) await _delete(old);
  }

  Future<void> reset() async {
    final old = state.imagePath;
    state = const TerminalAppearance();
    await ref.read(sharedPrefsProvider).remove(StoreKeys.terminalAppearance);
    if (old != null) await _delete(old);
  }

  static Future<void> _delete(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}
