import 'markdown.dart';

/// `#123`, `owner/repo#123`, `@user` and commit SHAs in plain text become
/// links to github.com, as GitHub shows them. Text in code, links and images is
/// left alone. SHAs need 7–40 hex characters with at least one digit and one
/// letter, so plain numbers and words like "deadbeef" stay text.
List<MdBlock> linkGitHubRefs(List<MdBlock> blocks, {required String owner, required String repo}) => [
  for (final b in blocks) _block(b, owner, repo),
];

const _base = 'https://github.com';
final _ref = RegExp(
  r'(?<![\w/#])(?:([A-Za-z0-9-]+/[A-Za-z0-9._-]+)?#(\d+))(?!\w)'
  r'|(?<![\w@`])@([A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))(?![\w/])'
  r'|(?<![\w/@#])([0-9a-f]{7,40})(?![\w/])',
);

MdBlock _block(MdBlock b, String o, String r) => switch (b) {
  MdHeading(:final level, :final inlines) => MdHeading(level, _inlines(inlines, o, r)),
  MdParagraph(:final inlines) => MdParagraph(_inlines(inlines, o, r)),
  MdQuote(:final blocks) => MdQuote([for (final x in blocks) _block(x, o, r)]),
  MdList(:final items, :final ordered, :final start) => MdList(
    [
      for (final i in items) MdListItem([for (final x in i.blocks) _block(x, o, r)], checked: i.checked),
    ],
    ordered: ordered,
    start: start,
  ),
  MdTable(:final header, :final rows, :final aligns) => MdTable(
    [for (final c in header) _inlines(c, o, r)],
    [
      for (final row in rows) [for (final c in row) _inlines(c, o, r)],
    ],
    aligns,
  ),
  MdCodeBlock() || MdRule() => b,
};

List<MdInline> _inlines(List<MdInline> inlines, String o, String r) => [
  for (final n in inlines)
    ...switch (n) {
      MdText(:final text) => _split(text, o, r),
      MdStyled(:final style, :final children) => [MdStyled(style, _inlines(children, o, r))],
      _ => [n],
    },
];

List<MdInline> _split(String text, String o, String r) {
  final out = <MdInline>[];
  var last = 0;
  for (final m in _ref.allMatches(text)) {
    final sha = m.group(4);
    if (sha != null && !(sha.contains(RegExp('[0-9]')) && sha.contains(RegExp('[a-f]')))) continue;
    final url = m.group(2) != null
        ? '$_base/${m.group(1) ?? '$o/$r'}/issues/${m.group(2)}'
        : m.group(3) != null
        ? '$_base/${m.group(3)}'
        : '$_base/$o/$r/commit/$sha';
    if (m.start > last) out.add(MdText(text.substring(last, m.start)));
    final label = sha == null ? m.group(0)! : sha.substring(0, 7);
    out.add(MdLink(url, [MdText(label)]));
    last = m.end;
  }
  if (last == 0) return [MdText(text)];
  if (last < text.length) out.add(MdText(text.substring(last)));
  return out;
}
