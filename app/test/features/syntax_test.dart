import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/features/diff/diff_parser.dart';
import 'package:git_reviewer/features/diff/syntax.dart';

String _changed(String text, List<Span> spans) => [for (final s in spans) text.substring(s.$1, s.$2)].join('|');

void main() {
  test('languages by file name', () {
    expect(languageForPath('lib/main.dart'), 'dart');
    expect(languageForPath('internal/x/retry.go'), 'go');
    expect(languageForPath('web/App.TSX'), 'typescript');
    expect(languageForPath('Dockerfile'), 'dockerfile');
    expect(languageForPath('build/Makefile'), 'makefile');
    expect(languageForPath('pubspec.yaml'), 'yaml');
    expect(languageForPath('LICENSE'), isNull);
    expect(languageForPath('photo.png'), isNull);
  });

  test('highlighting keeps one entry per line, with multi-line context', () {
    final lines = highlightLines('/* a\n b */\nfinal x = 1;', 'dart');
    expect(lines, hasLength(3));
    expect(lines[1].single.scope, 'comment', reason: 'inside a block comment opened on the line before');
    expect(lines[2].map((s) => s.text).join(), 'final x = 1;');
    expect(lines[2].first, const HlSeg('final', 'keyword'));
    expect(lines[2].any((s) => s.scope == 'number'), isTrue);
  });

  test('unknown languages come back plain', () {
    expect(highlightLines('a\n\nb', 'klingon'), [
      [const HlSeg('a')],
      <HlSeg>[],
      [const HlSeg('b')],
    ]);
  });

  test('diff lines: each side highlighted with its own context', () {
    final hunk = parsePatch('@@ -1,3 +1,3 @@\n /*\n-old */ int a;\n+new */ int b;')[0].lines;
    final hl = highlightDiffLines(hunk, 'c');
    expect(hl, hasLength(3));
    expect(hl[1].first.scope, 'comment', reason: 'removed line continues the comment on the old side');
    expect(hl[2].first.scope, 'comment');
  });

  group('word diff', () {
    test('marks only the changed words', () {
      final d = wordDiff('return r.wait(attempt);', 'return r.backoff(attempt);')!;
      expect(_changed('return r.wait(attempt);', d.removed), 'wait');
      expect(_changed('return r.backoff(attempt);', d.added), 'backoff');
    });

    test('adjacent changed tokens merge into one span', () {
      final d = wordDiff('a = b + c', 'a = x - y + c')!;
      expect(_changed('a = x - y + c', d.added), 'x - y');
    });

    test('a rewrite gets no emphasis', () {
      expect(wordDiff('foo(bar)', 'completely different text here'), isNull);
      expect(wordDiff('same', 'same'), isNull);
    });

    test('pairs removed and added lines block by block', () {
      final lines = parsePatch('@@ -1,4 +1,4 @@\n-int a = 1;\n-int b = 2;\n+int a = 10;\n+int b = 20;\n x\n')[0].lines;
      final w = pairedWordDiffs(lines);
      expect(w.keys, unorderedEquals([0, 1, 2, 3]));
      expect(_changed(lines[2].text, w[2]!), '10');
    });
  });

  test('runs split highlighted segments at changed spans', () {
    final runs = lineRuns([const HlSeg('return', 'keyword'), const HlSeg(' r.wait(n)')], [(9, 13)]);
    expect(runs.map((r) => '${r.text}${r.changed ? '*' : ''}'), ['return', ' r.', 'wait*', '(n)']);
    expect(runs.first.scope, 'keyword');
    expect(lineRuns([const HlSeg('abc')], const []).single.text, 'abc');
  });
}
