import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/theme/app_theme.dart';
import 'package:git_reviewer/core/widgets/color_picker.dart';
import 'package:git_reviewer/features/diff/diff_colors.dart';
import 'package:git_reviewer/features/diff/diff_parser.dart';

String _render(List<DiffLine> lines) => [
  for (final l in lines)
    '${switch (l.kind) {
      DiffLineKind.add => '+',
      DiffLineKind.delete => '-',
      DiffLineKind.noNewline => r'\',
      DiffLineKind.context => ' ',
    }}${l.oldNo ?? '_'}:${l.newNo ?? '_'} ${l.text}',
].join('\n');

void main() {
  group('fullFileLines', () {
    test('fills in unchanged lines around the hunks with both line numbers', () {
      final hunks = parsePatch('@@ -2,3 +2,3 @@\n b\n-c\n+C\n d\n@@ -7,2 +7,3 @@\n g\n+G2\n h');
      final out = fullFileLines('a\nb\nC\nd\ne\nf\ng\nG2\nh\ni\n', hunks)!;
      expect(_render(out), '''
 1:1 a
 2:2 b
-3:_ c
+_:3 C
 4:4 d
 5:5 e
 6:6 f
 7:7 g
+_:8 G2
 8:9 h
 9:10 i''');
    });

    test('a hunk that deletes lines shifts the old numbers after it', () {
      final hunks = parsePatch('@@ -1,3 +1,1 @@\n-x\n-y\n z');
      expect(_render(fullFileLines('z\nlast', hunks)!), '-1:_ x\n-2:_ y\n 3:1 z\n 4:2 last');
    });

    test('content that does not match the diff is rejected', () {
      final hunks = parsePatch('@@ -2,3 +2,3 @@\n b\n-c\n+C\n d');
      expect(fullFileLines('a\nb\nSOMETHING ELSE\nd\n', hunks), isNull);
      expect(fullFileLines('a\n', hunks), isNull, reason: 'too short');
    });

    test('CRLF files match their patch', () {
      final hunks = parsePatch('@@ -1,1 +1,1 @@\n-a\n+b');
      expect(_render(fullFileLines('b\r\nc\r\n', hunks)!), '-1:_ a\n+_:1 b\n 2:2 c');
    });
  });

  group('diff colors', () {
    test('overrides apply on top of the palette, per mode, and survive JSON', () {
      const red = Color(0xFFFF0000);
      final s = const DiffColorSettings(palette: 'colorblind').withOverride(DiffColorSlot.addFg, red, dark: true);
      expect(s.darkColors.addFg, red);
      expect(s.lightColors.addFg, s.preset.light.addFg);
      final back = DiffColorSettings.fromJson(s.toJson());
      expect(back.palette, 'colorblind');
      expect(back.darkColors.addFg, red);
      expect(back.withOverride(DiffColorSlot.addFg, null, dark: true).dark, isEmpty);
    });

    test('unknown palettes and junk fall back to GitHub colors', () {
      final s = DiffColorSettings.fromJson({
        'palette': 'nope',
        'dark': {'bogus': 1, 'addBg': 'red'},
      });
      expect(s.darkColors.addBg, DiffColors.dark.addBg);
      expect(s.preset.id, 'github');
    });

    test('a new profile copies the colors shown, then owns its edits', () {
      const red = Color(0xFFFF0000);
      const blue = Color(0xFF0000FF);
      final edited = const DiffColorSettings(palette: 'neon').withOverride(DiffColorSlot.addFg, red, dark: true);
      final s = edited.withNewProfile('p1', 'Mine');
      expect(s.preset.id, 'p1');
      expect(s.editingProfile, isTrue);
      expect(s.dark, isEmpty, reason: 'the override moved into the profile');
      expect(s.darkColors.addFg, red);
      expect(s.lightColors.delFg, diffPalettes.firstWhere((p) => p.id == 'neon').light.delFg);

      final changed = s.withOverride(DiffColorSlot.delBg, blue, dark: false);
      expect(changed.light, isEmpty, reason: 'profile edits are not overrides');
      expect(changed.lightColors.delBg, blue);
      expect(changed.withOverride(DiffColorSlot.delBg, null, dark: false).lightColors.delBg, blue);

      // Survives switching away and back, and JSON.
      final back = DiffColorSettings.fromJson(changed.select('github').toJson()).select('p1');
      expect(back.lightColors.delBg, blue);
      expect(back.darkColors.addFg, red);
      expect(back.renamed('p1', 'Night').preset.label, 'Night');
    });

    test('deleting: presets hide until reset, profiles go, the last one stays', () {
      var s = const DiffColorSettings(palette: 'neon').withNewProfile('p1', 'Mine').select('neon');
      s = s.without('neon');
      expect(s.hidden, {'neon'});
      expect(s.preset.id, 'github', reason: 'deleting the one in use switches to the first left');
      expect(s.available.map((p) => p.id), isNot(contains('neon')));
      expect(DiffColorSettings.fromJson(s.toJson()).hidden, {'neon'});

      for (final p in diffPalettes) {
        s = s.without(p.id);
      }
      expect(s.available.map((p) => p.id), ['p1'], reason: 'every preset can go while a profile is left');
      expect(s.preset.id, 'p1');
      expect(s.without('p1').available, hasLength(1), reason: 'the last palette is kept');

      final reset = s.withOverride(DiffColorSlot.gutter, const Color(0xFF123456), dark: true).reset();
      expect(reset.available, hasLength(diffPalettes.length + 1), reason: 'presets back, profile kept');
      expect(reset.preset.id, 'github');
      expect(reset.dark, isEmpty);
    });

    test('hex', () {
      expect(parseHexColor('#0a0'), const Color(0xFF00AA00));
      expect(parseHexColor('1A7F37'), const Color(0xFF1A7F37));
      expect(parseHexColor('#12345'), isNull);
      expect(parseHexColor('zzzzzz'), isNull);
      expect(hexOf(const Color(0x801A7F37)), '#1A7F37');
    });
  });
}
