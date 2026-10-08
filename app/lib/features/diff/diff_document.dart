import '../../data/github/models/models.dart';
import 'diff_parser.dart';

/// A flattened, lazily-renderable view of many file diffs.
///
/// Rendering every line of a large commit as nested widgets is slow; instead
/// the diff is flattened into rows that a single sliver list builds on demand.
sealed class DiffRow {
  const DiffRow(this.fileIndex);
  final int fileIndex;
}

class FileHeaderRow extends DiffRow {
  const FileHeaderRow(super.fileIndex, this.file, {required this.collapsed});
  final GhFileChange file;
  final bool collapsed;
}

class HunkHeaderRow extends DiffRow {
  const HunkHeaderRow(super.fileIndex, this.header);
  final String header;
}

class LineRow extends DiffRow {
  const LineRow(super.fileIndex, this.line);
  final DiffLine line;
}

class NoticeRow extends DiffRow {
  const NoticeRow(super.fileIndex, this.message);
  final String message;
}

class FileGapRow extends DiffRow {
  const FileGapRow(super.fileIndex);
}

class DiffDocument {
  DiffDocument._(this.rows, this.headerIndex, this.maxLineLength);

  factory DiffDocument.build(
    List<GhFileChange> files, {
    required Set<int> collapsed,
    required List<List<DiffHunk>?> parsed,
  }) {
    final rows = <DiffRow>[];
    final headerIndex = <int>[];
    var maxLen = 0;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final isCollapsed = collapsed.contains(i);
      headerIndex.add(rows.length);
      rows.add(FileHeaderRow(i, f, collapsed: isCollapsed));
      if (!isCollapsed) {
        final hunks = parsed[i];
        if (hunks == null) {
          rows.add(NoticeRow(i, _noPatchMessage(f)));
        } else if (hunks.isEmpty) {
          rows.add(
            NoticeRow(
              i,
              f.status == FileChangeStatus.renamed ? 'File renamed without changes.' : 'No textual changes.',
            ),
          );
        } else {
          for (final h in hunks) {
            rows.add(HunkHeaderRow(i, h.header));
            for (final l in h.lines) {
              rows.add(LineRow(i, l));
              // Tabs render as 4 spaces.
              final len = l.text.length + 3 * '\t'.allMatches(l.text).length;
              if (len > maxLen) maxLen = len;
            }
          }
        }
      }
      rows.add(FileGapRow(i));
    }
    return DiffDocument._(rows, headerIndex, maxLen);
  }

  final List<DiffRow> rows;

  /// Row index of each file's header, by file index.
  final List<int> headerIndex;

  /// Longest code line, used to size the canvas in no-wrap mode.
  final int maxLineLength;

  static String _noPatchMessage(GhFileChange f) => f.additions + f.deletions == 0
      ? 'Binary file or no diff available.'
      : 'Diff too large to display inline. Open the file to view it.';
}
