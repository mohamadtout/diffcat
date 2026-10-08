import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/diff/diff_document.dart';
import 'package:git_reviewer/features/diff/diff_parser.dart';

const _patch = '''@@ -1,4 +1,5 @@ class Foo
 line one
-old two
+new two
+added three
 line four
\\ No newline at end of file
@@ -10,2 +11,2 @@
-x
+y''';

void main() {
  group('parsePatch', () {
    test('splits hunks and numbers lines', () {
      final hunks = parsePatch(_patch);
      expect(hunks, hasLength(2));

      final h = hunks.first;
      expect(h.oldStart, 1);
      expect(h.newStart, 1);
      expect(h.lines.map((l) => l.kind), [
        DiffLineKind.context,
        DiffLineKind.delete,
        DiffLineKind.add,
        DiffLineKind.add,
        DiffLineKind.context,
        DiffLineKind.noNewline,
      ]);
      expect(h.lines[0].oldNo, 1);
      expect(h.lines[0].newNo, 1);
      expect(h.lines[1].oldNo, 2);
      expect(h.lines[1].newNo, isNull);
      expect(h.lines[2].newNo, 2);
      expect(h.lines[3].newNo, 3);
      expect(h.lines[4].oldNo, 3);
      expect(h.lines[4].newNo, 4);
      expect(h.lines[1].text, 'old two');

      expect(hunks[1].oldStart, 10);
      expect(hunks[1].newStart, 11);
      expect(hunks[1].lines.last.newNo, 11);
    });

    test('handles hunk headers without counts and CRLF', () {
      final hunks = parsePatch('@@ -3 +3 @@\r\n-a\r\n+b\r\n');
      expect(hunks.single.lines.map((l) => l.text), ['a', 'b']);
    });

    test('empty patch yields no hunks', () {
      expect(parsePatch(''), isEmpty);
    });
  });

  group('DiffDocument', () {
    const files = [
      GhFileChange(filename: 'a.dart', status: FileChangeStatus.modified, additions: 2, deletions: 1, patch: _patch),
      GhFileChange(filename: 'img.png', status: FileChangeStatus.added, additions: 0, deletions: 0),
    ];

    test('flattens files into rows with header index', () {
      final doc = DiffDocument.build(files, collapsed: {}, parsed: [parsePatch(_patch), null]);
      expect(doc.headerIndex, hasLength(2));
      expect(doc.rows[doc.headerIndex[0]], isA<FileHeaderRow>());
      expect(doc.rows[doc.headerIndex[1]], isA<FileHeaderRow>());
      expect(doc.rows.whereType<HunkHeaderRow>(), hasLength(2));
      expect(doc.rows.whereType<NoticeRow>().single.fileIndex, 1);
      expect(doc.maxLineLength, 'No newline at end of file'.length); // meta lines render too
    });

    test('collapsed files contribute only header and gap', () {
      final doc = DiffDocument.build(files, collapsed: {0}, parsed: [parsePatch(_patch), null]);
      final file0 = doc.rows.where((r) => r.fileIndex == 0).toList();
      expect(file0.map((r) => r.runtimeType), [FileHeaderRow, FileGapRow]);
    });
  });
}
