/// How a log line is shown.
enum LogKind { plain, group, error, warning, notice, command, debug }

class LogLine {
  const LogLine(this.text, {this.kind = LogKind.plain, this.group});

  final String text;
  final LogKind kind;

  /// Index (in the parsed list) of the `##[group]` header this line is
  /// folded under; null outside a group. Headers themselves have none.
  final int? group;
}

final _timestamp = RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z ?');
// CSI sequences (colors, cursor moves) and OSC sequences (titles, links).
final _ansi = RegExp(r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\)|[@-Z\\-_])');
final _marker = RegExp(r'^##\[(\w+)\]');

/// Parses a GitHub Actions job log: drops the timestamp GitHub puts on every
/// line and terminal color codes, and turns workflow commands (`##[group]`,
/// `##[error]`…) into [LogKind]s. Lines between `##[group]` and
/// `##[endgroup]` (a step's command and settings) belong to that header so
/// they can be folded away, as on github.com.
List<LogLine> parseJobLog(String raw) {
  final out = <LogLine>[];
  int? group;
  final text = raw.startsWith('\uFEFF') ? raw.substring(1) : raw;
  final lines = text.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  for (var line in lines) {
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    line = line.replaceFirst(_timestamp, '').replaceAll(_ansi, '');
    final m = _marker.firstMatch(line);
    final rest = m == null ? line : line.substring(m.end);
    switch (m?[1]) {
      case 'group':
        group = out.length;
        out.add(LogLine(rest, kind: LogKind.group));
      case 'endgroup':
        group = null;
      case 'error':
        out.add(LogLine(rest, kind: LogKind.error, group: group));
      case 'warning':
        out.add(LogLine(rest, kind: LogKind.warning, group: group));
      case 'notice':
        out.add(LogLine(rest, kind: LogKind.notice, group: group));
      case 'debug':
        out.add(LogLine(rest, kind: LogKind.debug, group: group));
      case 'command':
        out.add(LogLine(rest, kind: LogKind.command, group: group));
      default:
        // `[command]` without `##` is how actions/checkout echoes git.
        final command = line.startsWith('[command]');
        out.add(
          LogLine(command ? line.substring(9) : line, kind: command ? LogKind.command : LogKind.plain, group: group),
        );
    }
  }
  return out;
}

/// Indexes into [lines] that are shown: everything outside groups, every
/// group header, and the lines of [expanded] groups.
List<int> visibleLogLines(List<LogLine> lines, Set<int> expanded) => [
  for (var i = 0; i < lines.length; i++)
    if (lines[i].group == null || expanded.contains(lines[i].group)) i,
];
