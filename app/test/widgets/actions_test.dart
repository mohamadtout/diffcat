import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';

import '../support/demo_app.dart';
import '../support/demo_github.dart';
import '../support/settle.dart';

const _r = DemoGitHub.repo;

Future<DemoEnv> _open(WidgetTester tester, String route, {bool signedIn = true}) async {
  tester.view
    ..physicalSize = const Size(800, 1600)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final env = await DemoEnv.create(signedIn: signedIn);
  await tester.pumpWidget(env.app());
  await settle(tester);
  ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(routerProvider).go(route);
  await settle(tester);
  return env;
}

/// Leaves the tree so the runs' auto-refresh timers stop inside the test.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await settle(tester);
}

void main() {
  testWidgets('the Actions tab lists runs and filters them by workflow', (tester) async {
    await _open(tester, Routes.repo(_r, tab: 'actions'));
    expect(find.text('Fix rounding of JPY amounts'), findsOneWidget);
    expect(find.textContaining('CI #126'), findsOneWidget);
    expect(find.text('Run workflow'), findsOneWidget);

    await tester.tap(find.text('All workflows'));
    await settle(tester);
    await tester.tap(find.text('Deploy').last);
    await settle(tester);
    expect(find.textContaining('Deploy #31'), findsOneWidget);
    expect(find.textContaining('CI #126'), findsNothing);
    await _close(tester);
  });

  testWidgets('a failed run shows its failed job open, and re-runs only the failed jobs', (tester) async {
    final env = await _open(tester, Routes.run(_r, DemoGitHub.failedRunId));
    expect(find.text('go test ./...'), findsOneWidget, reason: 'the failed job starts expanded');
    expect(find.text('Cancel run'), findsNothing);

    await tester.tap(find.text('Re-run failed jobs'));
    await settle(tester);
    expect(
      env.github.posted.single.$1,
      '/repos/demo/payments-api/actions/runs/${DemoGitHub.failedRunId}/rerun-failed-jobs',
    );
    await _close(tester);
  });

  testWidgets('a running run can be cancelled after confirming', (tester) async {
    final env = await _open(tester, Routes.run(_r, 5001));
    expect(find.text('Re-run all jobs'), findsNothing);
    await tester.tap(find.text('Cancel run'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel run'));
    await settle(tester);
    expect(env.github.posted.single.$1, '/repos/demo/payments-api/actions/runs/5001/cancel');
    await _close(tester);
  });

  testWidgets('signed out, runs are read-only', (tester) async {
    await _open(tester, Routes.run(_r, DemoGitHub.failedRunId), signedIn: false);
    expect(find.text('Re-run failed jobs'), findsNothing);
    expect(find.text('Re-run all jobs'), findsNothing);
    await _close(tester);
  });

  testWidgets('the job log folds step setup and jumps to the error', (tester) async {
    await _open(tester, Routes.jobLog(_r, DemoGitHub.failedJobId));
    expect(find.text('Run go test ./...'), findsOneWidget);
    expect(find.text('go test ./...'), findsNothing, reason: 'folded under its group');
    expect(find.text('Process completed with exit code 1.'), findsOneWidget);
    await tester.tap(find.text('Run go test ./...'));
    await settle(tester);
    expect(find.text('go test ./...'), findsOneWidget);
    await tester.tap(find.byTooltip('Next error (1)'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  testWidgets('Run workflow starts Deploy with its inputs on the picked branch', (tester) async {
    final env = await _open(tester, Routes.repo(_r, tab: 'actions'));
    await tester.tap(find.text('Run workflow'));
    await settle(tester);
    // CI has no workflow_dispatch; Deploy does.
    expect(find.textContaining("can't be started by hand"), findsOneWidget);
    await tester.tap(find.text('CI').last);
    await settle(tester);
    await tester.tap(find.text('Deploy').last);
    await settle(tester);

    expect(find.text('dry_run'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'version'), 'v1.4.0');
    await tester.tap(find.text('dry_run'));
    await tester.tap(find.text('staging'));
    await settle(tester);
    await tester.tap(find.text('production').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Run workflow').last); // the sheet's
    await settle(tester);

    final (path, body) = env.github.posted.single;
    expect(path, '/repos/demo/payments-api/actions/workflows/${DemoGitHub.deployWorkflowId}/dispatches');
    expect(body, {
      'ref': 'main',
      'inputs': {'environment': 'production', 'version': 'v1.4.0', 'dry_run': 'false'},
    });
    expect(find.textContaining('Started Deploy'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4)); // the delayed list refresh
    await _close(tester);
  });
}
