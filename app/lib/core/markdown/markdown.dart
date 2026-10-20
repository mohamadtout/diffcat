/// A small parser for the GitHub-flavoured Markdown that pull requests and
/// review comments use: headings, paragraphs (single newlines are line
/// breaks, as in GitHub comments), fenced and indented code, quotes, nested
/// and task lists, tables, rules; inline code, bold, italic, strikethrough,
/// links, images, autolinks and bare URLs. HTML comments are dropped (PR
/// templates are full of them) and other HTML tags are reduced to their text.
///
/// Pure Dart with no dependencies, so it can be published on its own. App
/// behaviour (what a link opens, how code is highlighted) belongs to the
/// renderer's callbacks, not here.
library;

/// A block-level element.
sealed class MdBlock {
  const MdBlock();
}

class MdHeading extends MdBlock {
  const MdHeading(this.level, this.inlines);
  final int level;
  final List<MdInline> inlines;
}

class MdParagraph extends MdBlock {
  const MdParagraph(this.inlines);
  final List<MdInline> inlines;
}

class MdCodeBlock extends MdBlock {
  const MdCodeBlock(this.code, {this.language});
  final String code;

  /// The fence's info string's first word (`go` in ```go), if any.
  final String? language;
}

class MdQuote extends MdBlock {
  const MdQuote(this.blocks);
  final List<MdBlock> blocks;
}

class MdList extends MdBlock {
  const MdList(this.items, {this.ordered = false, this.start = 1});
  final List<MdListItem> items;
  final bool ordered;
  final int start;
}

class MdListItem {
  const MdListItem(this.blocks, {this.checked});
  final List<MdBlock> blocks;

  /// Task list item: true for `[x]`, false for `[ ]`, null for a plain item.
  final bool? checked;
}

enum MdAlign { none, left, center, right }

class MdTable extends MdBlock {
  const MdTable(this.header, this.rows, this.aligns);
  final List<List<MdInline>> header;
  final List<List<List<MdInline>>> rows;
  final List<MdAlign> aligns;
}

class MdRule extends MdBlock {
  const MdRule();
}

/// An inline element.
sealed class MdInline {
  const MdInline();
}

class MdText extends MdInline {
  const MdText(this.text);
  final String text;
}

class MdCode extends MdInline {
  const MdCode(this.code);
  final String code;
}

enum MdStyle { strong, emphasis, strikethrough }

class MdStyled extends MdInline {
  const MdStyled(this.style, this.children);
  final MdStyle style;
  final List<MdInline> children;
}

class MdLink extends MdInline {
  const MdLink(this.url, this.children);
  final String url;
  final List<MdInline> children;
}

class MdImage extends MdInline {
  const MdImage(this.url, this.alt);
  final String url;
  final String alt;
}

class MdBreak extends MdInline {
  const MdBreak();
}

/// Parses [source] into blocks.
List<MdBlock> parseMarkdown(String source) {
  final text = source.replaceAll('\r\n', '\n').replaceAll(_htmlComment, '');
  return _BlockParser(text.split('\n')).parse();
}

final _htmlComment = RegExp(r'<!--[\s\S]*?-->');
final _heading = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$');
final _fence = RegExp(r'^( {0,3})(`{3,}|~{3,})\s*([^`\s]*)');
final _rule = RegExp(r'^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$');
final _bullet = RegExp(r'^( {0,3})([-*+])([ \t]+|$)(.*)$');
final _ordered = RegExp(r'^( {0,3})(\d{1,9})([.)])([ \t]+|$)(.*)$');
final _task = RegExp(r'^\[([ xX])\][ \t]+');
final _quote = RegExp(r'^ {0,3}> ?(.*)$');
final _tableDelim = RegExp(r'^ *\|? *:?-+:? *(\| *:?-+:? *)*\|? *$');

class _BlockParser {
  _BlockParser(this.lines);
  final List<String> lines;
  var i = 0;

  bool get done => i >= lines.length;

  List<MdBlock> parse() {
    final out = <MdBlock>[];
    while (!done) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        i++;
        continue;
      }
      out.add(_block());
    }
    return out;
  }

  MdBlock _block() {
    final line = lines[i];
    if (_fence.firstMatch(line) case final m?) return _fenced(m);
    if (_heading.firstMatch(line) case final m?) {
      i++;
      return MdHeading(m.group(1)!.length, parseInlines(m.group(2) ?? ''));
    }
    if (_rule.hasMatch(line)) {
      i++;
      return const MdRule();
    }
    if (_quote.hasMatch(line)) return _quoteBlock();
    if (_bullet.hasMatch(line) || _ordered.hasMatch(line)) return _list();
    if (_isTableStart()) return _table();
    if (line.startsWith('    ') || line.startsWith('\t')) return _indented();
    return _paragraph();
  }

  MdBlock _fenced(RegExpMatch open) {
    final indent = open.group(1)!.length;
    final marker = open.group(2)!;
    final lang = open.group(3)!;
    i++;
    final body = <String>[];
    while (!done) {
      final l = lines[i];
      final t = l.trimLeft();
      if (t.startsWith(marker[0] * marker.length) && t.replaceAll(marker[0], '').trim().isEmpty) {
        i++;
        break;
      }
      body.add(_dedent(l, indent));
      i++;
    }
    return MdCodeBlock(body.join('\n'), language: lang.isEmpty ? null : lang);
  }

  MdBlock _indented() {
    final body = <String>[];
    while (!done && (lines[i].startsWith('    ') || lines[i].startsWith('\t') || lines[i].trim().isEmpty)) {
      body.add(lines[i].startsWith('\t') ? lines[i].substring(1) : lines[i].substring(lines[i].length < 4 ? 0 : 4));
      i++;
    }
    while (body.isNotEmpty && body.last.trim().isEmpty) {
      body.removeLast();
    }
    return MdCodeBlock(body.join('\n'));
  }

  MdBlock _quoteBlock() {
    final inner = <String>[];
    while (!done) {
      final m = _quote.firstMatch(lines[i]);
      if (m != null) {
        inner.add(m.group(1)!);
      } else if (lines[i].trim().isNotEmpty && inner.isNotEmpty && !_startsBlock(lines[i])) {
        inner.add(lines[i]); // lazy continuation
      } else {
        break;
      }
      i++;
    }
    return MdQuote(_BlockParser(inner).parse());
  }

  MdBlock _list() {
    final first = lines[i];
    final ordered = _ordered.hasMatch(first) && !_bullet.hasMatch(first);
    final start = ordered ? int.parse(_ordered.firstMatch(first)!.group(2)!) : 1;
    final items = <MdListItem>[];
    while (!done) {
      final line = lines[i];
      final b = _bullet.firstMatch(line);
      final o = _ordered.firstMatch(line);
      final isItem = ordered ? o != null : b != null;
      if (!isItem) break;
      // Width of the marker and its space: continuation lines indented this much belong to the item.
      final contentIndent = ordered
          ? o!.group(1)!.length + o.group(2)!.length + 1 + o.group(4)!.length
          : b!.group(1)!.length + 1 + b.group(3)!.length;
      var first = (ordered ? o!.group(5) : b!.group(4))!;
      bool? checked;
      if (_task.firstMatch(first) case final t?) {
        checked = t.group(1) != ' ';
        first = first.substring(t.end);
      }
      final body = [first];
      i++;
      while (!done) {
        final l = lines[i];
        if (l.trim().isEmpty) {
          // A blank line continues the item only if indented content follows.
          if (i + 1 < lines.length && _indentOf(lines[i + 1]) >= contentIndent && lines[i + 1].trim().isNotEmpty) {
            body.add('');
            i++;
            continue;
          }
          break;
        }
        final indent = _indentOf(l);
        if (indent >= contentIndent ||
            indent >= 2 && (_bullet.hasMatch(l.trimLeft()) || _ordered.hasMatch(l.trimLeft()))) {
          body.add(_dedent(l, indent >= contentIndent ? contentIndent : indent));
        } else if (!_startsBlock(l) && !_bullet.hasMatch(l) && !_ordered.hasMatch(l)) {
          body.add(l.trimLeft()); // lazy continuation of the item's paragraph
        } else {
          break;
        }
        i++;
      }
      items.add(MdListItem(_BlockParser(body).parse(), checked: checked));
      // Blank lines between items keep the list going.
      var j = i;
      while (j < lines.length && lines[j].trim().isEmpty) {
        j++;
      }
      if (j < lines.length && (ordered ? _ordered.hasMatch(lines[j]) : _bullet.hasMatch(lines[j]))) i = j;
    }
    return MdList(items, ordered: ordered, start: start);
  }

  bool _isTableStart() =>
      i + 1 < lines.length &&
      lines[i].contains('|') &&
      _tableDelim.hasMatch(lines[i + 1]) &&
      lines[i + 1].contains('-');

  MdBlock _table() {
    final header = _cells(lines[i]);
    final aligns = [
      for (final c in _cells(lines[i + 1]))
        c.startsWith(':') && c.endsWith(':')
            ? MdAlign.center
            : c.endsWith(':')
            ? MdAlign.right
            : c.startsWith(':')
            ? MdAlign.left
            : MdAlign.none,
    ];
    i += 2;
    final rows = <List<List<MdInline>>>[];
    while (!done && lines[i].trim().isNotEmpty && lines[i].contains('|')) {
      final cells = _cells(lines[i]);
      rows.add([for (var c = 0; c < header.length; c++) parseInlines(c < cells.length ? cells[c] : '')]);
      i++;
    }
    return MdTable(
      [for (final h in header) parseInlines(h)],
      rows,
      [for (var c = 0; c < header.length; c++) c < aligns.length ? aligns[c] : MdAlign.none],
    );
  }

  static List<String> _cells(String row) {
    var r = row.trim();
    if (r.startsWith('|')) r = r.substring(1);
    if (r.endsWith('|') && !r.endsWith(r'\|')) r = r.substring(0, r.length - 1);
    final cells = <String>[];
    final b = StringBuffer();
    for (var k = 0; k < r.length; k++) {
      if (r[k] == r'\' && k + 1 < r.length && r[k + 1] == '|') {
        b.write('|');
        k++;
      } else if (r[k] == '|') {
        cells.add(b.toString().trim());
        b.clear();
      } else {
        b.write(r[k]);
      }
    }
    cells.add(b.toString().trim());
    return cells;
  }

  MdBlock _paragraph() {
    final body = <String>[];
    while (!done && lines[i].trim().isNotEmpty && (body.isEmpty || !_startsBlock(lines[i]))) {
      if (body.isNotEmpty && _isTableStart()) break;
      body.add(lines[i].trim());
      i++;
    }
    // GitHub comments keep single newlines as line breaks.
    return MdParagraph(parseInlines(body.join('\n')));
  }

  static bool _startsBlock(String l) =>
      _fence.hasMatch(l) ||
      _heading.hasMatch(l) ||
      _rule.hasMatch(l) ||
      _quote.hasMatch(l) ||
      _bullet.hasMatch(l) ||
      _ordered.firstMatch(l)?.group(2) == '1';

  static int _indentOf(String l) {
    var n = 0;
    for (final c in l.split('')) {
      if (c == ' ') {
        n++;
      } else if (c == '\t') {
        n += 4;
      } else {
        break;
      }
    }
    return n;
  }

  static String _dedent(String l, int n) {
    var k = 0;
    while (k < l.length && k < n && l[k] == ' ') {
      k++;
    }
    return l.substring(k);
  }
}

final _bareUrl = RegExp(
  r'https?://[^\s<>()\[\]]*[^\s<>()\[\].,;:!?"'
  "'"
  r'*_~]',
);
final _htmlTag = RegExp(r'</?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>]*)?/?>');
final _imgTag = RegExp(r'<img\s[^>]*>', caseSensitive: false);
String? _attr(String tag, String name) =>
    RegExp('\\b$name\\s*=\\s*["\']([^"\']*)["\']', caseSensitive: false).firstMatch(tag)?.group(1);
const _escapable = r'\`*_{}[]()#+-.!|~<>';

/// Parses inline Markdown in [text] (one paragraph, heading or cell).
List<MdInline> parseInlines(String text) => _InlineParser(text).parse();

class _InlineParser {
  _InlineParser(this.src);
  final String src;
  var pos = 0;
  final _out = <MdInline>[];
  final _text = StringBuffer();

  void _flush() {
    if (_text.isEmpty) return;
    _out.add(MdText(_text.toString()));
    _text.clear();
  }

  void _add(MdInline node) {
    _flush();
    _out.add(node);
  }

  List<MdInline> parse() {
    while (pos < src.length) {
      final c = src[pos];
      if (c == r'\' && pos + 1 < src.length) {
        if (src[pos + 1] == '\n') {
          _add(const MdBreak());
          pos += 2;
          continue;
        }
        if (_escapable.contains(src[pos + 1])) {
          _text.write(src[pos + 1]);
          pos += 2;
          continue;
        }
      }
      if (c == '\n') {
        _add(const MdBreak());
        pos++;
        continue;
      }
      if (c == '`' && _codeSpan()) continue;
      if (c == '!' && pos + 1 < src.length && src[pos + 1] == '[' && _link(image: true)) continue;
      if (c == '[' && _link()) continue;
      if (c == '<' && (_autolink() || _html())) continue;
      if ((c == '*' || c == '_' || c == '~') && _emphasis()) continue;
      if (c == 'h' && _bare()) continue;
      _text.write(c);
      pos++;
    }
    _flush();
    return _out;
  }

  bool _codeSpan() {
    var n = 0;
    while (pos + n < src.length && src[pos + n] == '`') {
      n++;
    }
    final ticks = '`' * n;
    final end = src.indexOf(ticks, pos + n);
    if (end < 0) {
      _text.write(ticks);
      pos += n;
      return true;
    }
    var code = src.substring(pos + n, end).replaceAll('\n', ' ');
    if (code.length > 2 && code.startsWith(' ') && code.endsWith(' ') && code.trim().isNotEmpty) {
      code = code.substring(1, code.length - 1);
    }
    _add(MdCode(code));
    pos = end + n;
    return true;
  }

  /// Index of the `]` closing the `[` at [open], skipping nested brackets and code.
  int _closeBracket(int open) {
    var depth = 0;
    for (var k = open; k < src.length; k++) {
      final c = src[k];
      if (c == r'\') {
        k++;
      } else if (c == '`') {
        final end = src.indexOf('`', k + 1);
        if (end > 0) k = end;
      } else if (c == '[') {
        depth++;
      } else if (c == ']' && --depth == 0) {
        return k;
      }
    }
    return -1;
  }

  bool _link({bool image = false}) {
    final open = image ? pos + 1 : pos;
    final close = _closeBracket(open);
    if (close < 0 || close + 1 >= src.length || src[close + 1] != '(') return false;
    final end = src.indexOf(')', close + 2);
    if (end < 0) return false;
    var target = src.substring(close + 2, end).trim();
    // Drop an optional title: [x](url "title").
    final space = target.indexOf(RegExp(r'\s'));
    if (space > 0) target = target.substring(0, space);
    if (target.startsWith('<') && target.endsWith('>')) target = target.substring(1, target.length - 1);
    final label = src.substring(open + 1, close);
    _add(image ? MdImage(target, label) : MdLink(target, parseInlines(label)));
    pos = end + 1;
    return true;
  }

  bool _autolink() {
    final end = src.indexOf('>', pos);
    if (end < 0) return false;
    final inner = src.substring(pos + 1, end);
    if (!RegExp(r'^(https?://|mailto:)\S+$').hasMatch(inner)) return false;
    _add(MdLink(inner, [MdText(inner)]));
    pos = end + 1;
    return true;
  }

  /// Inline HTML: `<img>` becomes an image, `<br>` a break, other tags vanish
  /// (their text stays).
  bool _html() {
    final rest = src.substring(pos);
    if (_imgTag.matchAsPrefix(rest) case final m?) {
      final tag = m.group(0)!;
      if (_attr(tag, 'src') case final url?) _add(MdImage(url, _attr(tag, 'alt') ?? ''));
      pos += m.end;
      return true;
    }
    final tag = _htmlTag.matchAsPrefix(rest);
    if (tag == null) return false;
    if (RegExp(r'^<br\s*/?>$', caseSensitive: false).hasMatch(tag.group(0)!)) _add(const MdBreak());
    pos += tag.end;
    return true;
  }

  bool _bare() {
    final m = _bareUrl.matchAsPrefix(src, pos);
    if (m == null) return false;
    // Only at a word boundary: not inside "xhttps://".
    if (pos > 0 && RegExp(r'[A-Za-z0-9]').hasMatch(src[pos - 1])) return false;
    _add(MdLink(m.group(0)!, [MdText(m.group(0)!)]));
    pos = m.end;
    return true;
  }

  bool _emphasis() {
    final c = src[pos];
    final double = pos + 1 < src.length && src[pos + 1] == c;
    if (c == '~' && !double) return false;
    final marker = double ? c * 2 : c;
    final after = pos + marker.length;
    if (after >= src.length || src[after].trim().isEmpty) return false;
    // `_` inside a word (snake_case) is just an underscore, as on GitHub.
    if (c == '_' && pos > 0 && RegExp(r'[A-Za-z0-9]').hasMatch(src[pos - 1])) return false;
    var search = after;
    while (true) {
      final end = src.indexOf(marker, search);
      if (end < 0) return false;
      final closesWord = src[end - 1].trim().isNotEmpty;
      final beforeNext = end + marker.length;
      final intraword = c == '_' && beforeNext < src.length && RegExp(r'[A-Za-z0-9]').hasMatch(src[beforeNext]);
      // A single marker mustn't close on half of a double one.
      final halfDouble = !double && beforeNext < src.length && src[beforeNext] == c;
      if (closesWord && !intraword && !halfDouble && end > after) {
        final style = c == '~'
            ? MdStyle.strikethrough
            : double
            ? MdStyle.strong
            : MdStyle.emphasis;
        _add(MdStyled(style, parseInlines(src.substring(after, end))));
        pos = end + marker.length;
        return true;
      }
      search = end + marker.length;
    }
  }
}

/// All the text of [inlines], without formatting (for alt text, semantics).
String plainText(List<MdInline> inlines) => inlines
    .map(
      (n) => switch (n) {
        MdText(:final text) => text,
        MdCode(:final code) => code,
        MdStyled(:final children) || MdLink(:final children) => plainText(children),
        MdImage(:final alt) => alt,
        MdBreak() => '\n',
      },
    )
    .join();
