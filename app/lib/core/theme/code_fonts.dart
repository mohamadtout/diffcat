import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// Monospace fonts for the terminal and code views. All but [system] are
/// bundled (assets/fonts, SIL OFL 1.1).
enum CodeFont {
  system('System mono', null, null),
  jetBrainsMono('JetBrains Mono', 'JetBrainsMonoNerd', 'OFL-JetBrainsMono.txt'),
  firaCode('Fira Code', 'FiraCode', 'OFL-FiraCode.txt'),
  sourceCodePro('Source Code Pro', 'SourceCodePro', 'OFL-SourceCodePro.txt'),
  ibmPlexMono('IBM Plex Mono', 'IBMPlexMono', 'OFL-IBMPlexMono.txt');

  const CodeFont(this.label, this._family, this._license);

  final String label;
  final String? _family;
  final String? _license;

  String get family => _family ?? AppTheme.monoFamily;

  /// Nerd Font glyphs (prompt icons, powerline arrows) come from JetBrains
  /// Mono whatever the chosen font, then the platform's monospace.
  List<String> get fallback => [
    if (this != jetBrainsMono) 'JetBrainsMonoNerd',
    if (this != system) AppTheme.monoFamily,
    ...AppTheme.monoFallback,
  ];

  static CodeFont byName(String? name) => values.asNameMap()[name] ?? system;

  /// Adds the bundled fonts' licenses to the app's licenses page.
  static void registerLicenses() {
    LicenseRegistry.addLicense(() async* {
      for (final f in values) {
        if (f._license == null) continue;
        yield LicenseEntryWithLineBreaks([f.label], await rootBundle.loadString('assets/fonts/${f._license}'));
      }
      yield LicenseEntryWithLineBreaks([
        'Nerd Fonts',
      ], await rootBundle.loadString('assets/fonts/LICENSE-NerdFonts.txt'));
    });
  }
}
