import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/app.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/auth/auth_controller.dart';
import 'package:git_reviewer/features/auth/token_screen.dart';
import 'package:git_reviewer/features/repos/repos_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        tokenValidatorProvider.overrideWithValue((_) async => const GhUser(login: 'me')),
        myReposProvider.overrideWith((ref) async => <GhRepo>[]),
        viewerProvider.overrideWith((ref) async => const GhUser(login: 'me')),
      ],
      child: const GitReviewerApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _signIn(WidgetTester tester) async {
  expect(find.byType(TokenScreen), findsOneWidget);
  await tester.enterText(find.byType(TextField), 'ghp_test');
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in')); // below "Sign in with GitHub"
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signing in from the repo browser returns to the (now signed-in) repo list', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Sign in for your own and private repos'));
    await tester.pumpAndSettle();
    await _signIn(tester);

    expect(find.byType(TokenScreen), findsNothing, reason: 'left the sign-in screen');
    expect(find.text('Filter repositories'), findsOneWidget, reason: 'signed-in repo list');
  });

  testWidgets('signing in from Settings returns to Settings, now showing the account', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await _signIn(tester);

    expect(find.byType(TokenScreen), findsNothing, reason: 'left the sign-in screen');
    expect(find.text('Sign out'), findsOneWidget);
  });
}
