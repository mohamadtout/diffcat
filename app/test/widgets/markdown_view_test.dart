import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/markdown/markdown.dart';
import 'package:git_reviewer/core/markdown/markdown_view.dart';
import 'package:git_reviewer/core/routing/routes.dart';
import 'package:git_reviewer/core/theme/app_theme.dart';

Future<List<String>> _pump(WidgetTester tester, String source) async {
  final tapped = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(child: MarkdownView(parseMarkdown(source), onLink: tapped.add)),
      ),
    ),
  );
  return tapped;
}

void main() {
  test('github.com links open in the app when it has a screen for them', () {
    expect(Routes.fromGitHubUrl('https://github.com/demo/api'), '/repos/demo/api');
    expect(Routes.fromGitHubUrl('https://github.com/demo/api/pull/42/files'), '/repos/demo/api/pull/42');
    expect(Routes.fromGitHubUrl('https://github.com/demo/api/commit/9e3779b'), '/repos/demo/api/commit/9e3779b');
    expect(Routes.fromGitHubUrl('https://github.com/demo/api/issues/3'), isNull);
    expect(Routes.fromGitHubUrl('https://example.com/demo/api'), isNull);
  });

  testWidgets('renders lists, task boxes, code and tables, and taps links', (tester) async {
    final tapped = await _pump(
      tester,
      '## Changes\n\n- [x] backoff\n- [ ] docs\n\n```go\nfunc a() {}\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n'
      'See [the docs](https://x.dev).',
    );
    expect(find.text('Changes'), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    expect(find.text('func a() {}'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tapOnText(find.textRange.ofSubstring('the docs'));
    expect(tapped, ['https://x.dev']);
  });

  testWidgets('one selection area for the whole text', (tester) async {
    await _pump(tester, 'one\n\ntwo');
    expect(find.byType(SelectionArea), findsOneWidget);
  });
}
