enum DiffLineKind { context, add, delete, noNewline }

class DiffLine {
  const DiffLine(this.kind, this.text, {this.oldNo, this.newNo});

  final DiffLineKind kind;
  final String text;
  final int? oldNo;
  final int? newNo;
}

class DiffHunk {
  const DiffHunk({required this.header, required this.oldStart, required this.newStart, required this.lines});

  /// The raw `@@ -a,b +c,d @@ section` line.
  final String header;
  final int oldStart;
  final int newStart;
  final List<DiffLine> lines;
}

final _hunkRe = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');

/// Parses the `patch` field GitHub returns for a file: a sequence of hunks
/// without the `diff --git` / `---` / `+++` file headers.
List<DiffHunk> parsePatch(String patch) {
  final hunks = <DiffHunk>[];
  String? header;
  var oldStart = 0, newStart = 0, oldNo = 0, newNo = 0;
  var lines = <DiffLine>[];

  void flush() {
    if (header != null) {
      hunks.add(DiffHunk(header: header, oldStart: oldStart, newStart: newStart, lines: lines));
    }
  }

  for (final raw in patch.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    final m = _hunkRe.firstMatch(line);
    if (m != null) {
      flush();
      header = line;
      oldStart = oldNo = int.parse(m.group(1)!);
      newStart = newNo = int.parse(m.group(3)!);
      lines = [];
      continue;
    }
    if (header == null) continue; // preamble / file headers, if any
    if (line.isEmpty) {
      // A trailing empty string from split(); real blank context lines are ' '.
      continue;
    }
    switch (line[0]) {
      case '+':
        lines.add(DiffLine(DiffLineKind.add, line.substring(1), newNo: newNo++));
      case '-':
        lines.add(DiffLine(DiffLineKind.delete, line.substring(1), oldNo: oldNo++));
      case '\\':
        lines.add(DiffLine(DiffLineKind.noNewline, line.substring(1).trim()));
      default:
        lines.add(DiffLine(DiffLineKind.context, line.substring(1), oldNo: oldNo++, newNo: newNo++));
    }
  }
  flush();
  return hunks;
}
