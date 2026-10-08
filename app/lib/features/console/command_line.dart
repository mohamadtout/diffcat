import 'console_models.dart';

/// Splits a command line into words, honouring single/double quotes and
/// backslash escapes.
List<String> tokenize(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  String? quote;
  var inWord = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      } else if (ch == r'\' && quote == '"' && i + 1 < line.length) {
        buf.write(line[++i]);
      } else {
        buf.write(ch);
      }
    } else if (ch == '"' || ch == "'") {
      quote = ch;
      inWord = true;
    } else if (ch == r'\' && i + 1 < line.length) {
      buf.write(line[++i]);
      inWord = true;
    } else if (ch.trim().isEmpty) {
      if (inWord) {
        out.add(buf.toString());
        buf.clear();
        inWord = false;
      }
    } else {
      buf.write(ch);
      inWord = true;
    }
  }
  if (quote != null) throw ConsoleUsageError('Unterminated quote');
  if (inWord) out.add(buf.toString());
  return out;
}

/// A parsed command: name, positionals, flags/options and `--` paths.
class ParsedCommand {
  ParsedCommand(this.name, this.positionals, this.options, this.paths);

  final String name;
  final List<String> positionals;

  /// `--stat` → {'stat': ''}; `-n 5` / `--max-count=5` → {'n': '5'}.
  final Map<String, String> options;
  final List<String> paths;

  bool flag(String name) => options.containsKey(name);
  String? opt(String name) => options[name];

  int intOpt(String name, int fallback) {
    final v = options[name];
    if (v == null) return fallback;
    final n = int.tryParse(v);
    if (n == null || n <= 0) throw ConsoleUsageError('--$name expects a positive number');
    return n;
  }

  String? positional(int i) => i < positionals.length ? positionals[i] : null;
}

/// Options that take a value (everything else is a boolean flag).
const _valued = {'n', 'ref', 'state'};
const _aliases = {'max-count': 'n', 'r': 'ref', 's': 'state'};

ParsedCommand parseCommand(String line) {
  var words = tokenize(line.trim());
  if (words.isNotEmpty && words.first == 'git') words = words.sublist(1);
  if (words.isEmpty) throw ConsoleUsageError('Empty command');
  final name = words.first.toLowerCase();
  final positionals = <String>[];
  final options = <String, String>{};
  final paths = <String>[];
  var afterDashDash = false;

  for (var i = 1; i < words.length; i++) {
    final w = words[i];
    if (afterDashDash) {
      paths.add(w);
    } else if (w == '--') {
      afterDashDash = true;
    } else if (RegExp(r'^-\d+$').hasMatch(w)) {
      options['n'] = w.substring(1); // git log -5
    } else if (w.startsWith('-') && w.length > 1) {
      var key = w.replaceFirst(RegExp('^--?'), '');
      String? value;
      final eq = key.indexOf('=');
      if (eq >= 0) {
        value = key.substring(eq + 1);
        key = key.substring(0, eq);
      }
      key = _aliases[key] ?? key;
      if (value == null && _valued.contains(key)) {
        if (i + 1 >= words.length) throw ConsoleUsageError('Option $w needs a value');
        value = words[++i];
      }
      options[key] = value ?? '';
    } else {
      positionals.add(w);
    }
  }
  return ParsedCommand(name, positionals, options, paths);
}
