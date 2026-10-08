enum SpanStyle { normal, dim, add, del, accent, error, heading, sha }

class ConsoleSpan {
  const ConsoleSpan(this.text, [this.style = SpanStyle.normal]);
  final String text;
  final SpanStyle style;
}

class ConsoleLine {
  const ConsoleLine(this.spans, {this.route});

  ConsoleLine.text(String text, [SpanStyle style = SpanStyle.normal, String? route])
    : this([ConsoleSpan(text, style)], route: route);

  final List<ConsoleSpan> spans;

  /// Tapping the line navigates here (commit, file, PR…).
  final String? route;

  String get plain => spans.map((s) => s.text).join();
}

class ConsoleEntry {
  const ConsoleEntry({required this.input, this.output = const [], this.running = false});

  final String input;
  final List<ConsoleLine> output;
  final bool running;
}

/// Thrown by commands for user-facing usage errors.
class ConsoleUsageError implements Exception {
  ConsoleUsageError(this.message);
  final String message;
  @override
  String toString() => message;
}
