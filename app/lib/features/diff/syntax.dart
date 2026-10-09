import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/elixir.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/gradle.dart';
import 'package:re_highlight/languages/groovy.dart';
import 'package:re_highlight/languages/haskell.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/objectivec.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/r.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scala.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

import 'diff_parser.dart';

/// A run of text in one highlight.js scope (`keyword`, `string`,
/// `title.function_`…), or none.
class HlSeg {
  const HlSeg(this.text, [this.scope]);

  final String text;
  final String? scope;

  @override
  bool operator ==(Object other) => other is HlSeg && other.text == text && other.scope == scope;

  @override
  int get hashCode => Object.hash(text, scope);

  @override
  String toString() => scope == null ? text : '$scope($text)';
}

/// Only the languages people review most, to keep the app small.
final _languages = <String, Mode>{
  'bash': langBash,
  'c': langC,
  'cpp': langCpp,
  'csharp': langCsharp,
  'css': langCss,
  'dart': langDart,
  'dockerfile': langDockerfile,
  'elixir': langElixir,
  'go': langGo,
  'gradle': langGradle,
  'groovy': langGroovy,
  'haskell': langHaskell,
  'ini': langIni,
  'java': langJava,
  'javascript': langJavascript,
  'json': langJson,
  'kotlin': langKotlin,
  'lua': langLua,
  'makefile': langMakefile,
  'markdown': langMarkdown,
  'objectivec': langObjectivec,
  'php': langPhp,
  'python': langPython,
  'r': langR,
  'ruby': langRuby,
  'rust': langRust,
  'scala': langScala,
  'scss': langScss,
  'sql': langSql,
  'swift': langSwift,
  'typescript': langTypescript,
  'xml': langXml,
  'yaml': langYaml,
};

const _byExtension = {
  'sh': 'bash', 'bash': 'bash', 'zsh': 'bash', //
  'c': 'c', 'h': 'c',
  'cc': 'cpp', 'cpp': 'cpp', 'cxx': 'cpp', 'hpp': 'cpp', 'hh': 'cpp',
  'cs': 'csharp',
  'css': 'css',
  'dart': 'dart',
  'ex': 'elixir', 'exs': 'elixir',
  'go': 'go',
  'gradle': 'gradle',
  'groovy': 'groovy',
  'hs': 'haskell',
  'ini': 'ini', 'toml': 'ini', 'cfg': 'ini', 'properties': 'ini',
  'java': 'java',
  'js': 'javascript', 'jsx': 'javascript', 'mjs': 'javascript', 'cjs': 'javascript',
  'json': 'json', 'arb': 'json',
  'kt': 'kotlin', 'kts': 'kotlin',
  'lua': 'lua',
  'md': 'markdown', 'markdown': 'markdown',
  'm': 'objectivec', 'mm': 'objectivec',
  'php': 'php',
  'py': 'python', 'pyi': 'python',
  'r': 'r',
  'rb': 'ruby',
  'rs': 'rust',
  'scala': 'scala',
  'scss': 'scss',
  'sql': 'sql',
  'swift': 'swift',
  'ts': 'typescript', 'tsx': 'typescript',
  'xml': 'xml', 'html': 'xml', 'htm': 'xml', 'svg': 'xml', 'plist': 'xml', 'xib': 'xml',
  'yaml': 'yaml', 'yml': 'yaml',
};

/// The highlight.js language for a file, or null to leave it plain.
String? languageForPath(String path) {
  final name = path.split('/').last;
  final lower = name.toLowerCase();
  if (lower == 'dockerfile' || lower.startsWith('dockerfile.')) return 'dockerfile';
  if (lower == 'makefile' || lower == 'gnumakefile') return 'makefile';
  if (lower == 'gemfile' || lower == 'rakefile') return 'ruby';
  final dot = lower.lastIndexOf('.');
  return dot < 0 ? null : _byExtension[lower.substring(dot + 1)];
}

/// Files bigger than this aren't highlighted (highlight.js is regex-heavy).
const maxHighlightChars = 400 * 1000;

Highlight? _hl;
Highlight get _highlighter => _hl ??= Highlight()..registerLanguages(_languages);

/// Highlights [code] and splits the result into lines (on `\n`), so a
/// line-by-line view keeps multi-line context (block comments, strings).
/// Unknown languages and errors give plain lines.
List<List<HlSeg>> highlightLines(String code, String language) {
  if (!_languages.containsKey(language) || code.length > maxHighlightChars) return _plain(code);
  try {
    final r = _LineRenderer();
    _highlighter.highlight(code: code, language: language).render(r);
    return r.finish();
  } on Object {
    return _plain(code);
  }
}

List<List<HlSeg>> _plain(String code) => [
  for (final l in code.split('\n')) [if (l.isNotEmpty) HlSeg(l)],
];

class _LineRenderer implements HighlightRenderer {
  final _lines = <List<HlSeg>>[[]];
  final _scopes = <String?>[];

  String? get _scope {
    for (var i = _scopes.length - 1; i >= 0; i--) {
      if (_scopes[i] != null) return _scopes[i];
    }
    return null;
  }

  @override
  void addText(String text) {
    final parts = text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) _lines.add([]);
      if (parts[i].isNotEmpty) _lines.last.add(HlSeg(parts[i], _scope));
    }
  }

  @override
  void openNode(DataNode node) => _scopes.add(node.scope);

  @override
  void closeNode(DataNode node) => _scopes.removeLast();

  List<List<HlSeg>> finish() => _lines;
}

/// Highlights a diff's lines: the new side (context + added) and the old
/// side (context + removed) are each highlighted as one text, so constructs
/// spanning lines color correctly on both. Result is parallel to [lines].
List<List<HlSeg>> highlightDiffLines(List<DiffLine> lines, String language) {
  final newIdx = <int>[], oldIdx = <int>[];
  for (final (i, l) in lines.indexed) {
    if (l.kind == DiffLineKind.noNewline) continue;
    if (l.kind != DiffLineKind.delete) newIdx.add(i);
    if (l.kind == DiffLineKind.delete) oldIdx.add(i);
  }
  final out = List<List<HlSeg>>.generate(lines.length, (i) => [HlSeg(lines[i].text)]);
  void side(List<int> idx) {
    if (idx.isEmpty) return;
    final hl = highlightLines(idx.map((i) => lines[i].text).join('\n'), language);
    for (var k = 0; k < idx.length && k < hl.length; k++) {
      out[idx[k]] = hl[k];
    }
  }

  side(newIdx);
  // Removed lines read best with their surrounding context, so the old side
  // includes the context lines too (only the removed ones are kept).
  final oldWithContext = <int>[
    for (final (i, l) in lines.indexed)
      if (l.kind == DiffLineKind.context || l.kind == DiffLineKind.delete) i,
  ];
  if (oldIdx.isNotEmpty) {
    final hl = highlightLines(oldWithContext.map((i) => lines[i].text).join('\n'), language);
    for (var k = 0; k < oldWithContext.length && k < hl.length; k++) {
      if (lines[oldWithContext[k]].kind == DiffLineKind.delete) out[oldWithContext[k]] = hl[k];
    }
  }
  return out;
}

/// A changed part of a line, as `[start, end)` character offsets.
typedef Span = (int start, int end);

final _token = RegExp(r'\w+|\s+|[^\w\s]');

/// Which parts of [a] (removed) and [b] (added) differ, by word-level LCS.
/// Null when the lines are too different for the emphasis to help (a
/// rewrite), or too long to compare cheaply.
({List<Span> removed, List<Span> added})? wordDiff(String a, String b, {int maxTokens = 400}) {
  final ta = _token.allMatches(a).toList();
  final tb = _token.allMatches(b).toList();
  if (ta.isEmpty || tb.isEmpty || ta.length > maxTokens || tb.length > maxTokens) return null;
  // LCS table over tokens.
  final n = ta.length, m = tb.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = ta[i][0] == tb[j][0]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final keepA = List.filled(n, false), keepB = List.filled(m, false);
  for (var i = 0, j = 0; i < n && j < m;) {
    if (ta[i][0] == tb[j][0]) {
      keepA[i++] = true;
      keepB[j++] = true;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  // Mostly different: emphasizing nearly everything is just noise.
  final sameChars = [
    for (var i = 0; i < n; i++)
      if (keepA[i]) ta[i][0]!.trim().length,
  ].fold(0, (s, l) => s + l);
  final total = (a + b).replaceAll(RegExp(r'\s'), '').length; // like sameChars: no whitespace
  if (total == 0 || 2 * sameChars / total < 0.4) return null;

  List<Span> spans(String text, List<RegExpMatch> t, List<bool> keep) {
    final raw = <Span>[];
    for (var i = 0; i < t.length; i++) {
      if (keep[i]) continue;
      final start = t[i].start;
      var end = t[i].end;
      while (i + 1 < t.length && !keep[i + 1]) {
        end = t[++i].end;
      }
      raw.add((start, end));
    }
    // Whitespace alone doesn't separate changes, nor belong at their edges.
    final out = <Span>[];
    for (final (start, end) in raw) {
      if (out.isNotEmpty && text.substring(out.last.$2, start).trim().isEmpty) {
        out.last = (out.last.$1, end);
      } else {
        out.add((start, end));
      }
    }
    return [
      for (final (start, end) in out)
        if (text.substring(start, end).trim().isNotEmpty)
          (
            start + (text.substring(start, end).length - text.substring(start, end).trimLeft().length),
            end - (text.substring(start, end).length - text.substring(start, end).trimRight().length),
          ),
    ];
  }

  final removed = spans(a, ta, keepA), added = spans(b, tb, keepB);
  if (removed.isEmpty && added.isEmpty) return null;
  return (removed: removed, added: added);
}

/// Word-level emphasis for each changed line of a hunk: within each block of
/// removed lines followed by added lines, the i-th removed line pairs with
/// the i-th added line. Keyed by index into [lines].
Map<int, List<Span>> pairedWordDiffs(List<DiffLine> lines) {
  final out = <int, List<Span>>{};
  var i = 0;
  while (i < lines.length) {
    final dels = <int>[], adds = <int>[];
    while (i < lines.length && lines[i].kind == DiffLineKind.delete) {
      dels.add(i++);
    }
    while (i < lines.length && lines[i].kind == DiffLineKind.add) {
      adds.add(i++);
    }
    if (dels.isEmpty && adds.isEmpty) {
      i++;
      continue;
    }
    for (var k = 0; k < dels.length && k < adds.length; k++) {
      final d = wordDiff(lines[dels[k]].text, lines[adds[k]].text);
      if (d == null) continue;
      out[dels[k]] = d.removed;
      out[adds[k]] = d.added;
    }
  }
  return out;
}

/// A piece of a rendered line: its text, syntax scope and whether it's in a
/// changed (emphasized) span.
typedef Run = ({String text, String? scope, bool changed});

/// Splits highlighted [segs] at the [changed] span edges.
List<Run> lineRuns(List<HlSeg> segs, List<Span> changed) {
  final out = <Run>[];
  var pos = 0;
  for (final s in segs) {
    var start = 0;
    while (start < s.text.length) {
      final at = pos + start;
      final inSpan = changed.where((c) => c.$1 <= at && at < c.$2).firstOrNull;
      // Up to the next edge: the end of this span or the start of the next.
      var edge = pos + s.text.length;
      if (inSpan != null) {
        if (inSpan.$2 < edge) edge = inSpan.$2;
      } else {
        for (final c in changed) {
          if (c.$1 > at && c.$1 < edge) edge = c.$1;
        }
      }
      out.add((text: s.text.substring(start, edge - pos), scope: s.scope, changed: inSpan != null));
      start = edge - pos;
    }
    pos += s.text.length;
  }
  return out;
}
