import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/markdown/github_refs.dart';
import 'package:git_reviewer/core/markdown/markdown.dart';

/// A compact, readable dump of the tree, so expectations stay short.
String dump(List<MdBlock> blocks) => blocks.map(_block).join('\n');

String _block(MdBlock b) => switch (b) {
  MdHeading(:final level, :final inlines) => 'h$level(${_in(inlines)})',
  MdParagraph(:final inlines) => 'p(${_in(inlines)})',
  MdCodeBlock(:final code, :final language) =>
    'code${language == null ? '' : '[$language]'}(${code.replaceAll('\n', r'\n')})',
  MdQuote(:final blocks) => 'quote(${blocks.map(_block).join(' ')})',
  MdList(:final items, :final ordered, :final start) =>
    '${ordered ? 'ol$start' : 'ul'}(${items.map((i) => '${i.checked == null
        ? ''
        : i.checked!
        ? '[x]'
        : '[ ]'}${i.blocks.map(_block).join(' ')}').join(' | ')})',
  MdTable(:final header, :final rows, :final aligns) =>
    'table(${header.map(_in).join(',')} / ${rows.map((r) => r.map(_in).join(',')).join(' / ')} / ${aligns.map((a) => a.name).join(',')})',
  MdRule() => 'hr',
};

String _in(List<MdInline> inlines) => inlines
    .map(
      (n) => switch (n) {
        MdText(:final text) => text,
        MdCode(:final code) => '`$code`',
        MdStyled(:final style, :final children) => '${style.name[0]}{${_in(children)}}',
        MdLink(:final url, :final children) => '[${_in(children)}]<$url>',
        MdImage(:final url, :final alt) => 'img[$alt]<$url>',
        MdBreak() => '↵',
      },
    )
    .join();

String md(String s) => dump(parseMarkdown(s));

void main() {
  group('blocks', () {
    test('the demo PR body: a paragraph and a list', () {
      expect(
        md('Endpoints were hammered.\n\n- exponential backoff\n- capped at one minute'),
        'p(Endpoints were hammered.)\nul(p(exponential backoff) | p(capped at one minute))',
      );
    });

    test('headings, rules and single newlines as breaks', () {
      expect(md('## Why\nline one\nline two\n\n---\n# Done #'), 'h2(Why)\np(line one↵line two)\nhr\nh1(Done)');
    });

    test('fenced and indented code keep their text', () {
      expect(md('```go\nfunc a() {\n\treturn\n}\n```'), 'code[go](func a() {\\n\treturn\\n})');
      expect(md('~~~\nx < y\n~~~'), 'code(x < y)');
      expect(md('text\n\n    indented()\n    more()'), 'p(text)\ncode(indented()\\nmore())');
      expect(md('```\nunclosed'), 'code(unclosed)');
    });

    test('quotes nest blocks', () {
      expect(md('> **Note**\n> keep this'), 'quote(p(s{Note}↵keep this))');
    });

    test('ordered, nested and task lists', () {
      expect(md('3. three\n4. four'), 'ol3(p(three) | p(four))');
      expect(md('- a\n  - b\n  - c\n- d'), 'ul(p(a) ul(p(b) | p(c)) | p(d))');
      expect(md('- [x] tests\n- [ ] docs'), 'ul([x]p(tests) | [ ]p(docs))');
    });

    test('tables with alignment', () {
      expect(
        md('| Name | Size |\n|:-----|-----:|\n| a.go | 1 KB |\n| b | `2` |'),
        'table(Name,Size / a.go,1 KB / b,`2` / left,right)',
      );
    });

    test('HTML comments from PR templates vanish; other tags keep their text', () {
      expect(md('<!-- Describe your change -->\nFixes it.\n<!--\nmulti\n-->'), 'p(Fixes it.)');
      expect(md('<details><summary>Logs</summary>\nlots\n</details>'), 'p(Logs↵lots↵)');
      expect(md('a<br>b'), 'p(a↵b)');
    });
  });

  group('inlines', () {
    test('code, bold, italic, strikethrough', () {
      expect(md('`a*b` **bold** *it* _it_ ~~gone~~ __b__'), 'p(`a*b` s{bold} e{it} e{it} s{gone} s{b})');
    });

    test('snake_case and lone markers stay text', () {
      expect(md('use max_retry_count and 2 * 3 * 4'), 'p(use max_retry_count and 2 * 3 * 4)');
    });

    test('links, images, autolinks, bare URLs and escapes', () {
      expect(
        md('[docs](https://x.dev/a "t") ![cat](c.png) <https://a.b> see https://g.co/x.'),
        'p([docs]<https://x.dev/a> img[cat]<c.png> [https://a.b]<https://a.b> see [https://g.co/x]<https://g.co/x>.)',
      );
      expect(md(r'\*not em\* and [nested [brackets]](u)'), 'p(*not em* and [nested [brackets]]<u>)');
      expect(md('<img src="s.png" alt="shot">'), 'p(img[shot]<s.png>)');
    });

    test('strong containing emphasis', () {
      expect(md('**very *important* note**'), 'p(s{very e{important} note})');
    });
  });

  group('GitHub references', () {
    String refs(String s) => dump(linkGitHubRefs(parseMarkdown(s), owner: 'demo', repo: 'api'));

    test('issues and PRs, users, commits', () {
      expect(
        refs('Fixes #12 and other/lib#3, thanks @lena-k, see 9e3779b9e3779b'),
        'p(Fixes [#12]<https://github.com/demo/api/issues/12> and '
        '[other/lib#3]<https://github.com/other/lib/issues/3>, thanks [@lena-k]<https://github.com/lena-k>, '
        'see [9e3779b]<https://github.com/demo/api/commit/9e3779b9e3779b>)',
      );
    });

    test('not in code, links, emails, or numbers and hex-looking words', () {
      expect(refs('`#1` [#2](u) a@b.c 1234567 deadbeef'), 'p(`#1` [#2]<u> a@b.c 1234567 deadbeef)');
    });
  });
}
