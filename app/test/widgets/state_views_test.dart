import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/theme/app_theme.dart';
import 'package:git_reviewer/core/widgets/async_view.dart';
import 'package:git_reviewer/core/widgets/mascot.dart';
import 'package:git_reviewer/data/github/github_exception.dart';

Widget _host(Widget child, {Size size = const Size(393, 852)}) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(
        body: SizedBox.fromSize(size: size, child: child),
      ),
    ),
  ),
);

void main() {
  testWidgets('EmptyView shows its title, message and action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(
        EmptyView(
          icon: Icons.merge_type,
          title: 'Nothing here',
          message: 'No open pull requests.',
          action: FilledButton.tonal(onPressed: () => tapped = true, child: const Text('Show closed')),
        ),
      ),
    );
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('No open pull requests.'), findsOneWidget);
    await tester.tap(find.text('Show closed'));
    expect(tapped, isTrue);
  });

  testWidgets('the mascot shows where there is room and gives way to the icon where there is not', (tester) async {
    const view = EmptyView(icon: Icons.done_all, mascot: true, message: 'Nothing waiting for your review.');
    await tester.pumpWidget(_host(view));
    expect(find.byType(Mascot), findsOneWidget);

    await tester.pumpWidget(_host(view, size: const Size(852, 300)));
    expect(find.byType(Mascot), findsNothing);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
  });

  testWidgets('EmptyView scrolls instead of overflowing in a tiny space', (tester) async {
    await tester.pumpWidget(
      _host(
        EmptyView(
          icon: Icons.inbox,
          title: 'A title',
          message: 'A long message ' * 20,
          action: FilledButton(onPressed: () {}, child: const Text('Act')),
        ),
        size: const Size(320, 160),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  group('rate limit', () {
    final reset = DateTime.now().add(const Duration(minutes: 23, seconds: 30));

    testWidgets('signed out: says when it resets and offers signing in', (tester) async {
      await tester.pumpWidget(
        _host(
          ErrorView(
            error: GitHubException('limited', statusCode: 403, rateLimitResetAt: reset, signedOut: true),
            onRetry: () {},
          ),
        ),
      );
      expect(find.text("GitHub's hourly limit is used up"), findsOneWidget);
      expect(find.textContaining('in 23 min'), findsOneWidget);
      expect(find.text('Sign in for 5,000 an hour'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('signed in: no sign-in offer, points to downloads instead', (tester) async {
      await tester.pumpWidget(
        _host(
          ErrorView(
            error: GitHubException('limited', statusCode: 403, rateLimitResetAt: reset),
            onRetry: () {},
          ),
        ),
      );
      expect(find.text('Sign in for 5,000 an hour'), findsNothing);
      expect(find.textContaining('Downloaded repos still open offline'), findsOneWidget);
    });
  });

  testWidgets('other errors keep the message and a Retry button', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _host(ErrorView(error: GitHubException('Not Found', statusCode: 404), onRetry: () => retried = true)),
    );
    expect(find.textContaining('Not found'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
