import 'dart:io';

import 'package:flutter/services.dart';

/// Loads Roboto and the Material icon font from the Flutter SDK, so text in
/// widget tests has real widths instead of the square test font. Layout
/// checks (overflow at small sizes, large text) are only meaningful with them.
///
/// Returns false if the SDK fonts weren't found (tests still run, with the
/// test font).
Future<bool> loadSdkFonts() async {
  final dir = _materialFontsDir();
  if (dir == null) return false;
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('${dir.path}/$f');
      if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Italic.ttf',
    'Roboto-Light.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  return true;
}

/// flutter_tester lives under `<sdk>/bin/cache/artifacts/engine/…`; the fonts
/// under `<sdk>/bin/cache/artifacts/material_fonts`.
Directory? _materialFontsDir() {
  final roots = [
    if (Platform.environment['FLUTTER_ROOT'] case final root?) Directory(root),
    File(Platform.resolvedExecutable).parent,
  ];
  for (final start in roots) {
    Directory? d = start;
    for (var i = 0; i < 8 && d != null; i++) {
      final fonts = Directory('${d.path}/bin/cache/artifacts/material_fonts');
      if (fonts.existsSync()) return fonts;
      final inCache = Directory('${d.path}/material_fonts');
      if (inCache.existsSync()) return inCache;
      d = d.parent.path == d.path ? null : d.parent;
    }
  }
  return null;
}
