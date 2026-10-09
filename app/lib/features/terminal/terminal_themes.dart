import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';

/// A named terminal color scheme.
class TerminalPreset {
  const TerminalPreset(this.id, this.label, this.theme);

  final String id;
  final String label;
  final TerminalTheme theme;

  bool get isDark => theme.background.computeLuminance() < 0.4;
}

/// [colors] are the 16 ANSI colors as 0xRRGGBB: black, red, green, yellow,
/// blue, magenta, cyan, white, then the bright variants in the same order.
TerminalTheme _theme({
  required int bg,
  required int fg,
  required int cursor,
  required List<int> colors,
  int? selection,
}) {
  assert(colors.length == 16);
  Color c(int rgb) => Color(0xFF000000 | rgb);
  return TerminalTheme(
    background: c(bg),
    foreground: c(fg),
    cursor: c(cursor),
    selection: selection == null ? c(fg).withValues(alpha: 0.3) : c(selection).withValues(alpha: 0.6),
    black: c(colors[0]),
    red: c(colors[1]),
    green: c(colors[2]),
    yellow: c(colors[3]),
    blue: c(colors[4]),
    magenta: c(colors[5]),
    cyan: c(colors[6]),
    white: c(colors[7]),
    brightBlack: c(colors[8]),
    brightRed: c(colors[9]),
    brightGreen: c(colors[10]),
    brightYellow: c(colors[11]),
    brightBlue: c(colors[12]),
    brightMagenta: c(colors[13]),
    brightCyan: c(colors[14]),
    brightWhite: c(colors[15]),
    searchHitBackground: c(colors[3]),
    searchHitBackgroundCurrent: c(colors[11]),
    searchHitForeground: c(bg),
  );
}

/// Follows the app's light/dark mode.
const followAppPreset = 'app';

final terminalPresets = <TerminalPreset>[
  TerminalPreset(
    'diffcat-dark',
    'Diffcat Dark',
    _theme(
      bg: 0x0D1117,
      fg: 0xE6EDF3,
      cursor: 0x2F81F7,
      selection: 0x264F78,
      colors: [
        0x484F58, 0xFF7B72, 0x3FB950, 0xD29922, 0x58A6FF, 0xBC8CFF, 0x39C5CF, 0xB1BAC4, //
        0x6E7681, 0xFFA198, 0x56D364, 0xE3B341, 0x79C0FF, 0xD2A8FF, 0x56D4DD, 0xFFFFFF,
      ],
    ),
  ),
  TerminalPreset(
    'diffcat-light',
    'Diffcat Light',
    _theme(
      bg: 0xFFFFFF,
      fg: 0x1F2328,
      cursor: 0x0969DA,
      selection: 0xB6E3FF,
      colors: [
        0x24292F, 0xCF222E, 0x116329, 0x4D2D00, 0x0969DA, 0x8250DF, 0x1B7C83, 0x6E7781, //
        0x57606A, 0xA40E26, 0x1A7F37, 0x633C01, 0x218BFF, 0xA475F9, 0x3192AA, 0x8C959F,
      ],
    ),
  ),
  TerminalPreset(
    'dracula',
    'Dracula',
    _theme(
      bg: 0x282A36,
      fg: 0xF8F8F2,
      cursor: 0xF8F8F2,
      selection: 0x44475A,
      colors: [
        0x21222C, 0xFF5555, 0x50FA7B, 0xF1FA8C, 0xBD93F9, 0xFF79C6, 0x8BE9FD, 0xF8F8F2, //
        0x6272A4, 0xFF6E6E, 0x69FF94, 0xFFFFA5, 0xD6ACFF, 0xFF92DF, 0xA4FFFF, 0xFFFFFF,
      ],
    ),
  ),
  TerminalPreset(
    'catppuccin-mocha',
    'Catppuccin Mocha',
    _theme(
      bg: 0x1E1E2E,
      fg: 0xCDD6F4,
      cursor: 0xF5E0DC,
      selection: 0x585B70,
      colors: [
        0x45475A, 0xF38BA8, 0xA6E3A1, 0xF9E2AF, 0x89B4FA, 0xF5C2E7, 0x94E2D5, 0xBAC2DE, //
        0x585B70, 0xF38BA8, 0xA6E3A1, 0xF9E2AF, 0x89B4FA, 0xF5C2E7, 0x94E2D5, 0xA6ADC8,
      ],
    ),
  ),
  TerminalPreset(
    'tokyo-night',
    'Tokyo Night',
    _theme(
      bg: 0x1A1B26,
      fg: 0xC0CAF5,
      cursor: 0xC0CAF5,
      selection: 0x33467C,
      colors: [
        0x15161E, 0xF7768E, 0x9ECE6A, 0xE0AF68, 0x7AA2F7, 0xBB9AF7, 0x7DCFFF, 0xA9B1D6, //
        0x414868, 0xF7768E, 0x9ECE6A, 0xE0AF68, 0x7AA2F7, 0xBB9AF7, 0x7DCFFF, 0xC0CAF5,
      ],
    ),
  ),
  TerminalPreset(
    'nord',
    'Nord',
    _theme(
      bg: 0x2E3440,
      fg: 0xD8DEE9,
      cursor: 0xD8DEE9,
      selection: 0x434C5E,
      colors: [
        0x3B4252, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x88C0D0, 0xE5E9F0, //
        0x4C566A, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x8FBCBB, 0xECEFF4,
      ],
    ),
  ),
  TerminalPreset(
    'gruvbox-dark',
    'Gruvbox Dark',
    _theme(
      bg: 0x282828,
      fg: 0xEBDBB2,
      cursor: 0xEBDBB2,
      selection: 0x504945,
      colors: [
        0x282828, 0xCC241D, 0x98971A, 0xD79921, 0x458588, 0xB16286, 0x689D6A, 0xA89984, //
        0x928374, 0xFB4934, 0xB8BB26, 0xFABD2F, 0x83A598, 0xD3869B, 0x8EC07C, 0xEBDBB2,
      ],
    ),
  ),
  TerminalPreset(
    'one-dark',
    'One Dark',
    _theme(
      bg: 0x282C34,
      fg: 0xABB2BF,
      cursor: 0x528BFF,
      selection: 0x3E4451,
      colors: [
        0x282C34, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xABB2BF, //
        0x5C6370, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xFFFFFF,
      ],
    ),
  ),
  TerminalPreset(
    'monokai',
    'Monokai',
    _theme(
      bg: 0x272822,
      fg: 0xF8F8F2,
      cursor: 0xF8F8F0,
      selection: 0x49483E,
      colors: [
        0x272822, 0xF92672, 0xA6E22E, 0xF4BF75, 0x66D9EF, 0xAE81FF, 0xA1EFE4, 0xF8F8F2, //
        0x75715E, 0xF92672, 0xA6E22E, 0xF4BF75, 0x66D9EF, 0xAE81FF, 0xA1EFE4, 0xF9F8F5,
      ],
    ),
  ),
  TerminalPreset(
    'solarized-dark',
    'Solarized Dark',
    _theme(
      bg: 0x002B36,
      fg: 0x839496,
      cursor: 0x93A1A1,
      selection: 0x073642,
      colors: [
        0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5, //
        0x586E75, 0xCB4B16, 0x859900, 0xB58900, 0x268BD2, 0x6C71C4, 0x2AA198, 0xFDF6E3,
      ],
    ),
  ),
  TerminalPreset(
    'solarized-light',
    'Solarized Light',
    _theme(
      bg: 0xFDF6E3,
      fg: 0x657B83,
      cursor: 0x586E75,
      selection: 0xEEE8D5,
      colors: [
        0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5, //
        0x002B36, 0xCB4B16, 0x586E75, 0x657B83, 0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3,
      ],
    ),
  ),
  TerminalPreset(
    'matrix',
    'Matrix',
    _theme(
      bg: 0x000000,
      fg: 0x00FF41,
      cursor: 0x00FF41,
      selection: 0x003B00,
      colors: [
        0x000000, 0x008F11, 0x00FF41, 0x6FFF6F, 0x00B32C, 0x00D13A, 0x39FF8A, 0xB8FFB8, //
        0x0F4F1A, 0x00B32C, 0x5CFF7D, 0xA0FFA0, 0x00E040, 0x2FFF6F, 0x7DFFAE, 0xE0FFE0,
      ],
    ),
  ),
];

/// The preset for [id]; [followAppPreset] (or an unknown id) picks Diffcat
/// Dark or Light to match [appIsDark].
TerminalPreset presetFor(String id, {required bool appIsDark}) =>
    terminalPresets.where((p) => p.id == id).firstOrNull ??
    terminalPresets.firstWhere((p) => p.id == (appIsDark ? 'diffcat-dark' : 'diffcat-light'));

/// Built-in background gradients (id → colors, top-left to bottom-right).
const terminalGradients = <String, List<Color>>{
  'aurora': [Color(0xFF0B1026), Color(0xFF1B4B5A), Color(0xFF2D7D6F)],
  'synthwave': [Color(0xFF1A0B2E), Color(0xFF52206B), Color(0xFFB8336A)],
  'sunset': [Color(0xFF2B1B3D), Color(0xFF8E3B46), Color(0xFFE07A5F)],
  'ocean': [Color(0xFF021B35), Color(0xFF0B4F6C), Color(0xFF168AAD)],
  'forest': [Color(0xFF0B1A12), Color(0xFF1E3D2B), Color(0xFF4A7C59)],
  'mono': [Color(0xFF111111), Color(0xFF2A2A2A), Color(0xFF3D3D3D)],
};
