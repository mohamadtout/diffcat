import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'shell_integration.dart';
import 'terminal_appearance.dart';
import 'terminal_themes.dart';

/// The terminal's background: the theme color, then the chosen gradient or
/// image at the chosen opacity and blur. The terminal draws on top of it with
/// a transparent background.
class TerminalBackdrop extends StatelessWidget {
  const TerminalBackdrop({super.key, required this.appearance, required this.theme});

  final TerminalAppearance appearance;
  final TerminalTheme theme;

  @override
  Widget build(BuildContext context) {
    final a = appearance;
    Widget? layer;
    if (a.hasBackground) {
      final opacity = a.backgroundOpacity;
      layer = switch (a.background) {
        BackgroundKind.image => Image.file(
          File(a.imagePath!),
          fit: BoxFit.cover,
          opacity: AlwaysStoppedAnimation(opacity),
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        _ => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                for (final c in terminalGradients[a.gradient] ?? terminalGradients.values.first)
                  c.withValues(alpha: opacity),
              ],
            ),
          ),
        ),
      };
      if (a.backgroundBlur > 0) {
        layer = ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: a.backgroundBlur, sigmaY: a.backgroundBlur, tileMode: TileMode.mirror),
          child: layer,
        );
      }
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: theme.background),
        if (layer != null) ClipRect(child: layer),
      ],
    );
  }
}

/// What the status bar shows.
class StatusBarData {
  const StatusBarData({required this.host, this.cwd, this.git, this.connected = true});

  final String host;
  final String? cwd;
  final GitStatus? git;
  final bool connected;
}

/// A shell-prompt style bar: host, folder, branch, ahead/behind, changes.
class TerminalStatusBar extends StatelessWidget {
  const TerminalStatusBar({
    super.key,
    required this.data,
    required this.appearance,
    required this.theme,
    this.onTap,
    this.onSetup,
  });

  final StatusBarData data;
  final TerminalAppearance appearance;
  final TerminalTheme theme;

  /// Tapping the bar (refreshes git status).
  final VoidCallback? onTap;

  /// Shown as a hint when the folder is unknown and integration is off.
  final VoidCallback? onSetup;

  /// Last two folders, `~` kept: `/home/me/code/app/lib` → `…/app/lib`.
  static String shortPath(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return path;
    return '…/${parts.sublist(parts.length - 2).join('/')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final a = appearance;
    final git = data.git;
    final segments = <(IconData?, String, Color)>[]; // icon, text, accent
    for (final s in StatusSegment.values.where(a.segments.contains)) {
      switch (s) {
        case StatusSegment.host:
          segments.add((Icons.dns_outlined, data.host, t.brightBlack));
        case StatusSegment.path:
          if (data.cwd case final cwd?) segments.add((Icons.folder_outlined, shortPath(cwd), t.blue));
        case StatusSegment.branch:
          if (git != null) {
            segments.add((
              git.detached ? Icons.commit : Icons.call_split,
              git.branch,
              git.changes == 0 ? t.green : t.yellow,
            ));
          }
        case StatusSegment.sync:
          if (git != null && (git.ahead > 0 || git.behind > 0)) {
            segments.add((
              null,
              [if (git.ahead > 0) '↑${git.ahead}', if (git.behind > 0) '↓${git.behind}'].join(' '),
              t.cyan,
            ));
          }
        case StatusSegment.changes:
          if (git != null && git.changes > 0) segments.add((null, '●${git.changes}', t.red));
      }
    }
    final needsFolder = a.segments.any((s) => s != StatusSegment.host);
    final hint = !data.connected
        ? 'disconnected'
        : data.cwd == null && needsFolder
        ? (a.shellIntegration ? 'waiting for the shell…' : 'folder unknown · tap to set up')
        : null;

    final textStyle = TextStyle(
      fontFamily: a.font.family,
      fontFamilyFallback: a.font.fallback,
      fontSize: 12,
      height: 1.2,
      fontWeight: FontWeight.w600,
    );
    final powerline = a.statusStyle == StatusBarStyle.powerline;
    final bar = Color.lerp(t.background, t.foreground, 0.06)!;
    final children = <Widget>[];
    for (final (i, (icon, text, accent)) in segments.indexed) {
      final fg = powerline ? t.background : accent;
      children.add(
        Container(
          color: powerline ? accent : null,
          padding: EdgeInsets.fromLTRB(i == 0 || !powerline ? 8 : 4, 4, powerline ? 4 : 2, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
              Text(text, style: textStyle.copyWith(color: fg)),
            ],
          ),
        ),
      );
      if (powerline) {
        final next = i + 1 < segments.length ? segments[i + 1].$3 : bar;
        children.add(_Chevron(color: accent, background: next));
      }
    }
    if (hint != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            hint,
            style: textStyle.copyWith(color: t.brightBlack, fontWeight: FontWeight.w400),
          ),
        ),
      );
    }

    return Material(
      color: bar,
      child: InkWell(
        onTap: data.cwd == null && !a.shellIntegration && onSetup != null ? onSetup : onTap,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ),
    );
  }
}

/// The arrow between two powerline segments, drawn (not a font glyph) so it
/// works with every font.
class _Chevron extends StatelessWidget {
  const _Chevron({required this.color, required this.background});

  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 10, child: CustomPaint(painter: _ChevronPainter(color, background)));
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter(this.color, this.background);

  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = background)
      ..drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, size.height / 2)
          ..lineTo(0, size.height)
          ..close(),
        Paint()..color = color,
      );
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.color != color || old.background != background;
}

/// Sample output for the appearance preview: a prompt, git log and all 16
/// colors.
const terminalPreviewText =
    '\x1b[1;32mdemo@laptop\x1b[0m:\x1b[1;34m~/code/payments-api\x1b[0m\$ git log --oneline --graph -4\r\n'
    '* \x1b[33m3f2a1c9\x1b[0m \x1b[1;36m(HEAD -> \x1b[1;32mmain\x1b[1;36m)\x1b[0m Add exponential backoff\r\n'
    '* \x1b[33m8be04d2\x1b[0m Fix rounding of JPY amounts\r\n'
    '|\\  \r\n'
    '| * \x1b[33m51c7e90\x1b[0m \x1b[1;31m(origin/ledger)\x1b[0m Reconcile in batches\r\n'
    '|/  \r\n'
    '\x1b[1;32mdemo@laptop\x1b[0m:\x1b[1;34m~/code/payments-api\x1b[0m\$ \r\n'
    '\x1b[40m  \x1b[41m  \x1b[42m  \x1b[43m  \x1b[44m  \x1b[45m  \x1b[46m  \x1b[47m  \x1b[0m\r\n'
    '\x1b[100m  \x1b[101m  \x1b[102m  \x1b[103m  \x1b[104m  \x1b[105m  \x1b[106m  \x1b[107m  \x1b[0m';
