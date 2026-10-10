import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/app.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/core/theme/app_theme.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/diff/diff_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _files = [
  GhFileChange(
    filename: 'lib/main.dart',
    status: FileChangeStatus.modified,
    additions: 1,
    deletions: 1,
    patch: '@@ -1,2 +1,2 @@\n context\n-old line\n+new line',
  ),
  GhFileChange(filename: 'assets/logo.png', status: FileChangeStatus.added, additions: 0, deletions: 0),
];

Future<ProviderScope> _scope(Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(overrides: [sharedPrefsProvider.overrideWithValue(prefs)], child: child);
}

void main() {
  testWidgets('DiffView renders files, lines and collapses on tap', (tester) async {
    await tester.pumpWidget(
      await _scope(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: DiffView(repo: (owner: 'o', name: 'r'), files: _files, fileRef: 'sha'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('logo.png'), findsOneWidget);
    expect(find.text('new line'), findsOneWidget);
    expect(find.text('Binary file or no diff available.'), findsOneWidget);

    await tester.tap(find.text('main.dart'));
    await tester.pumpAndSettle();
    expect(find.text('new line'), findsNothing);
  });

  testWidgets('first launch without a token opens the public repo browser, sign-in is optional', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(await _scope(const GitReviewerApp()));
    await tester.pumpAndSettle();
    expect(find.text('Browse any public repo'), findsOneWidget);

    await tester.tap(find.text('Sign in for your own and private repos'));
    await tester.pumpAndSettle();
    expect(find.text('Personal access token'), findsOneWidget);
    // Below "Sign in with GitHub" and the token field: scroll to it like a user would.
    await tester.ensureVisible(find.text('Not now'));
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Browse any public repo'), findsOneWidget);
  });
}
