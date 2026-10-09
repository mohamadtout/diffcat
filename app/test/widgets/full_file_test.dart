import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/core/theme/app_theme.dart';
import 'package:git_reviewer/data/github/github_api.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/auth/auth_controller.dart';
import 'package:git_reviewer/features/diff/diff_view.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockApi extends Mock implements GitHubApi {}

const _repo = (owner: 'o', name: 'r');
const _files = [
  GhFileChange(
    filename: 'lib/a.dart',
    status: FileChangeStatus.modified,
    additions: 1,
    deletions: 1,
    patch: '@@ -2,3 +2,3 @@\n b\n-c\n+C\n d',
  ),
];

Future<void> _pump(WidgetTester tester, GitHubApi api, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(p), githubApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: DiffView(repo: _repo, files: _files, fileRef: 'sha1'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => registerFallbackValue(_repo));

  testWidgets('a file can be shown whole from its menu, and back', (tester) async {
    final api = _MockApi();
    when(() => api.fileContent(any(), 'lib/a.dart', 'sha1')).thenAnswer((_) async => 'first\nb\nC\nd\nlast\n');
    await _pump(tester, api);
    expect(find.text('first'), findsNothing);
    expect(find.text('@@ -2,3 +2,3 @@'), findsOneWidget);

    await tester.tap(find.byTooltip('File actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show full file'));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    expect(find.text('last'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('@@ -2,3 +2,3 @@'), findsNothing, reason: 'no hunk headers in a whole file');
    verify(() => api.fileContent(any(), any(), any())).called(1);

    await tester.tap(find.byTooltip('File actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show changes only'));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
  });

  testWidgets('the default comes from settings and a mismatch falls back to the hunks', (tester) async {
    final api = _MockApi();
    when(() => api.fileContent(any(), any(), any())).thenAnswer((_) async => 'moved on\n');
    await _pump(tester, api, prefs: {StoreKeys.diffFullFile: true});
    expect(find.textContaining("doesn't match this diff"), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('@@ -2,3 +2,3 @@'), findsOneWidget);
  });
}
