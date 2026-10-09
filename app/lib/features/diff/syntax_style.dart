import 'package:flutter/material.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';

import 'syntax.dart';

/// Syntax colors for the current brightness (GitHub's light and dark
/// themes). Only text colors and weights are used; backgrounds come from the
/// diff colors.
Map<String, TextStyle> syntaxTheme(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? githubDarkTheme : githubTheme;

/// [runs] as a text span over [base]: each run in its scope's color, changed
/// runs on [changedBg]. Tabs render as four spaces.
TextSpan codeSpan(List<Run> runs, TextStyle base, Map<String, TextStyle> theme, {Color? changedBg}) => TextSpan(
  style: base,
  children: [
    for (final r in runs)
      TextSpan(
        text: r.text.replaceAll('\t', '    '),
        style:
            _style(r.scope, theme)?.copyWith(backgroundColor: r.changed ? changedBg : null) ??
            (r.changed ? TextStyle(backgroundColor: changedBg) : null),
      ),
  ],
);

TextStyle? _style(String? scope, Map<String, TextStyle> theme) {
  if (scope == null) return null;
  // `title.function_` falls back to `title` when the theme has no exact match.
  final t = theme[scope] ?? theme[scope.split('.').first];
  return t == null ? null : TextStyle(color: t.color, fontWeight: t.fontWeight, fontStyle: t.fontStyle);
}
