import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'markdown.dart';

/// Builds a fenced code block's text, e.g. with syntax highlighting; return
/// null for plain [base]-styled text.
typedef CodeHighlighter = InlineSpan? Function(String code, String? language, TextStyle base);

/// Renders [parseMarkdown] blocks with the app's Material theme: one
/// selection across the whole text, links through [onLink], code in
/// [codeStyle] (a monospace style) and fenced code through [highlight].
/// Images are shown as links rather than downloaded (data and privacy on a
/// phone). Depends only on Flutter, like the parser.
class MarkdownView extends StatefulWidget {
  const MarkdownView(this.blocks, {super.key, this.onLink, this.highlight, this.codeStyle, this.selectable = true});

  final List<MdBlock> blocks;
  final ValueChanged<String>? onLink;
  final CodeHighlighter? highlight;

  /// Inline and block code; defaults to the theme's body text in `monospace`.
  final TextStyle? codeStyle;

  /// Wraps the text in one [SelectionArea]; off when an ancestor already selects.
  final bool selectable;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  final _recognizers = <TapGestureRecognizer>[];

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final r = _Renderer(context, widget, _recognizers);
    final column = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: r.blocks(widget.blocks));
    return widget.selectable ? SelectionArea(child: column) : column;
  }
}

class _Renderer {
  _Renderer(this.context, this.w, this.recognizers)
    : theme = Theme.of(context),
      body = Theme.of(context).textTheme.bodyMedium!;

  final BuildContext context;
  final MarkdownView w;
  final List<TapGestureRecognizer> recognizers;
  final ThemeData theme;
  final TextStyle body;

  ColorScheme get scheme => theme.colorScheme;
  TextStyle get code => w.codeStyle ?? body.copyWith(fontFamily: 'monospace', fontSize: (body.fontSize ?? 14) * 0.92);

  List<Widget> blocks(List<MdBlock> blocks, {bool tight = false}) => [
    for (final (i, b) in blocks.indexed) ...[
      if (i > 0) SizedBox(height: tight ? 4 : (b is MdHeading ? 16 : 10)),
      block(b),
    ],
  ];

  Widget block(MdBlock b) => switch (b) {
    MdHeading(:final level, :final inlines) => _heading(level, inlines),
    MdParagraph(:final inlines) => Text.rich(TextSpan(style: body, children: spans(inlines))),
    MdCodeBlock(:final code, :final language) => _codeBlock(code, language),
    MdQuote(:final blocks) => DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.outlineVariant, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: scheme.onSurfaceVariant),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: this.blocks(blocks)),
        ),
      ),
    ),
    MdList() => _list(b),
    MdTable() => _table(b),
    MdRule() => Divider(height: 8, color: scheme.outlineVariant),
  };

  Widget _heading(int level, List<MdInline> inlines) {
    final style = switch (level) {
      1 => theme.textTheme.titleLarge,
      2 => theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      _ => theme.textTheme.titleSmall,
    };
    final text = Text.rich(TextSpan(style: style, children: spans(inlines)));
    if (level > 2) return text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        text,
        const SizedBox(height: 4),
        Divider(height: 1, color: scheme.outlineVariant),
      ],
    );
  }

  Widget _codeBlock(String source, String? language) => DecoratedBox(
    decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Text.rich(w.highlight?.call(source, language, code) ?? TextSpan(text: source, style: code)),
    ),
  );

  Widget _list(MdList list) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, item) in list.items.indexed)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: list.ordered ? 28 : 20,
                child: item.checked != null
                    ? Icon(
                        item.checked! ? Icons.check_box : Icons.check_box_outline_blank,
                        size: (body.fontSize ?? 14) * 1.25,
                        color: item.checked! ? scheme.primary : scheme.outline,
                        semanticLabel: item.checked! ? 'done' : 'not done',
                      )
                    : Text(list.ordered ? '${list.start + i}.' : '•', style: body),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: blocks(item.blocks, tight: true),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _table(MdTable t) {
    TextAlign align(int c) => switch (t.aligns[c]) {
      MdAlign.center => TextAlign.center,
      MdAlign.right => TextAlign.right,
      _ => TextAlign.left,
    };
    Widget cell(List<MdInline> inlines, int c, {bool header = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text.rich(
        TextSpan(
          style: header ? body.copyWith(fontWeight: FontWeight.w600) : body,
          children: spans(inlines),
        ),
        textAlign: align(c),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(8)),
        children: [
          TableRow(
            decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
            children: [for (final (c, h) in t.header.indexed) cell(h, c, header: true)],
          ),
          for (final row in t.rows) TableRow(children: [for (final (c, x) in row.indexed) cell(x, c)]),
        ],
      ),
    );
  }

  /// [tap] is passed down to the leaves: Flutter hit-tests the innermost span,
  /// and a parent's recognizer doesn't apply to its children.
  List<InlineSpan> spans(List<MdInline> inlines, {TextStyle? style, GestureRecognizer? tap}) => [
    for (final n in inlines) span(n, style, tap),
  ];

  InlineSpan span(MdInline n, TextStyle? style, GestureRecognizer? tap) => switch (n) {
    MdText(:final text) => TextSpan(text: text, style: style, recognizer: tap),
    MdBreak() => TextSpan(text: '\n', style: style),
    MdCode(code: final c) => TextSpan(
      text: c,
      recognizer: tap,
      style: code.merge(style).copyWith(backgroundColor: scheme.surfaceContainerHighest),
    ),
    MdStyled(style: final s, :final children) => TextSpan(
      children: spans(
        children,
        tap: tap,
        style: switch (s) {
          MdStyle.strong => const TextStyle(fontWeight: FontWeight.w700),
          MdStyle.emphasis => const TextStyle(fontStyle: FontStyle.italic),
          MdStyle.strikethrough => const TextStyle(decoration: TextDecoration.lineThrough),
        }.merge(style),
      ),
    ),
    MdLink(:final url, :final children) => TextSpan(
      children: spans(
        children,
        tap: _tap(url) ?? tap,
        style: TextStyle(
          color: scheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: scheme.primary,
        ).merge(style),
      ),
    ),
    MdImage(:final url, :final alt) => TextSpan(
      style: TextStyle(color: scheme.primary).merge(style),
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(Icons.image_outlined, size: (body.fontSize ?? 14) * 1.2, color: scheme.primary),
        ),
        TextSpan(text: ' ${alt.isEmpty ? 'Image' : alt}', recognizer: _tap(url) ?? tap),
      ],
    ),
  };

  TapGestureRecognizer? _tap(String url) {
    if (w.onLink == null) return null;
    final r = TapGestureRecognizer()..onTap = () => w.onLink!(url);
    recognizers.add(r);
    return r;
  }
}
