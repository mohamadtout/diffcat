import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';
import 'package:git_reviewer/core/widgets/text_size_sheet.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/offline/download_button.dart';
import 'package:git_reviewer/features/offline/offline_store.dart';
import 'package:git_reviewer/features/repo/ref_picker.dart';
import 'package:git_reviewer/features/terminal/host_edit_screen.dart';
import 'package:git_reviewer/features/terminal/host_key_dialog.dart';
import 'package:git_reviewer/features/terminal/terminal_appearance_screen.dart';

import '../support/demo_app.dart';
import '../support/demo_github.dart';
import '../support/fonts.dart';

/// Every screen at phone, foldable, tablet and desktop sizes, in portrait and
/// landscape, with normal and large text. Fails on any layout error (e.g. a
/// RenderFlex overflow), naming the size and screen.
///
/// Uses the SDK's Roboto so text widths are realistic (see [loadSdkFonts]).
const _sizes = <(String, Size, double)>[
  ('small phone', Size(320, 568), 1),
  ('phone', Size(360, 640), 1),
  ('phone, large text', Size(360, 640), 1.5),
  ('iPhone', Size(393, 852), 1),
  ('large phone, largest text', Size(440, 956), 2),
  ('phone landscape', Size(852, 393), 1),
  ('foldable', Size(673, 841), 1),
  ('small tablet portrait', Size(744, 1133), 1),
  ('tablet portrait', Size(1032, 1376), 1),
  ('tablet landscape', Size(1376, 1032), 1),
  ('tablet landscape, large text', Size(1194, 834), 1.5),
  ('desktop', Size(1920, 1080), 1),
];

const _r = DemoGitHub.repo;
final _sha = DemoGitHub.sha(1);
final _screens = <String>[
  Routes.repos,
  Routes.repo(_r),
  Routes.repo(_r, tab: 'files'),
  Routes.repo(_r, tab: 'pulls'),
  Routes.repo(_r, tab: 'console'),
  Routes.commit(_r, _sha),
  Routes.commit(_r, _sha, file: DemoGitHub.retryGo),
  Routes.compare(_r, 'main', DemoGitHub.featureBranch),
  Routes.pull(_r, DemoGitHub.openPullNumber),
  Routes.file(_r, DemoGitHub.retryGo, 'main'),
  Routes.history(_r, DemoGitHub.retryGo, 'main'),
  Routes.changedSince(_r, ref: 'main', base: 'v1.4.0'),
  Routes.terminal,
  Routes.hostEdit(null),
  Routes.hostEdit(demoHosts.first.id),
  Routes.terminalSession(demoHosts.first.id),
  Routes.settings,
  Routes.commands,
  Routes.terminalAppearance,
  Routes.downloads,
  Routes.savedRepo(_r),
  Routes.setup,
];

void main() {
  late Directory dir;
  late OfflineStore store;

  setUpAll(() async {
    if (!await loadSdkFonts()) debugPrint('SDK fonts not found: layout checks use the square test font');
    dir = await Directory.systemTemp.createTemp('screen_sizes');
    store = await OfflineStore.open(dir);
    // In memory only (no flush): widget tests can't wait on real file I/O.
    store.saveBranch(
      DemoGitHub.repo.fullName,
      'main',
      SavedBranch(updatedAt: DateTime.now(), options: const DownloadOptions(), commits: const []),
    );
  });
  tearDownAll(() => dir.delete(recursive: true));

  for (final (name, size, textScale) in _sizes) {
    for (final signedIn in [true, false]) {
      // Signed out only changes the home screen and Settings; check it on
      // the smallest and largest sizes.
      if (!signedIn && size != _sizes.first.$2 && size != _sizes.last.$2) continue;
      testWidgets('$name ${size.width.toInt()}×${size.height.toInt()} @${textScale}x'
          '${signedIn ? '' : ', signed out'}', (tester) async {
        tester.view
          ..physicalSize = size * 2
          ..devicePixelRatio = 2;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final env = await DemoEnv.create(signedIn: signedIn, store: store);
        final problems = <String>[];
        var screen = 'startup';
        final previous = FlutterError.onError;
        FlutterError.onError = (d) => problems.add(
          '$screen: ${d.exceptionAsString().split('\n').first} ${d.informationCollector?.call().take(3).join(' ').replaceAll('\n', ' ')}',
        );
        try {
          await tester.pumpWidget(env.app());
          await _settle(tester);
          final router = ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(routerProvider);
          for (final s in signedIn ? _screens : [Routes.repos, Routes.settings, Routes.setup]) {
            screen = s;
            router.go(s);
            await _settle(tester);
            final e = tester.takeException();
            if (e != null) problems.add('$s: $e');
          }
          // Leave the tree so pending timers and sessions shut down inside the test.
          await tester.pumpWidget(const SizedBox());
          await _settle(tester);
        } finally {
          FlutterError.onError = previous;
        }
        expect(problems, isEmpty, reason: problems.join('\n'));
        expect(env.github.unknown, isEmpty, reason: 'GitHub calls the demo API does not cover');
      });
    }
  }

  // Sheets and dialogs, where small screens and large text bite hardest.
  for (final (name, size, textScale) in _sizes.where((s) => s.$2.shortestSide < 400 || s.$3 > 1)) {
    testWidgets('sheets and dialogs: $name ${size.width.toInt()}×${size.height.toInt()} @${textScale}x', (
      tester,
    ) async {
      tester.view
        ..physicalSize = size * 2
        ..devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final env = await DemoEnv.create(store: store);
      final problems = <String>[];
      var overlay = 'startup';
      final previous = FlutterError.onError;
      FlutterError.onError = (d) => problems.add('$overlay: ${d.exceptionAsString().split('\n').first}');
      try {
        await tester.pumpWidget(env.app());
        await _settle(tester);
        final router = ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(routerProvider);
        router.go(Routes.repo(_r));
        await _settle(tester);
        BuildContext ctx() => tester.element(find.byType(Scaffold).last);

        Future<void> show(String what, void Function(BuildContext) open) async {
          overlay = what;
          open(ctx());
          await _settle(tester);
          expect(_overlayShown(), isTrue, reason: '$what did not open');
          Navigator.of(ctx(), rootNavigator: true).pop();
          await _settle(tester);
        }

        await show('download sheet', (c) => showDownloadSheet(c, repo: _r, branch: 'main'));
        await show(
          'download sheet, new branch',
          (c) => showDownloadSheet(c, repo: _r, branch: DemoGitHub.featureBranch),
        );
        await show('shell integration sheet', showShellIntegrationSheet);
        await show('text size sheet', (c) => showTextSizeSheet(c, value: 13, min: 8, max: 24, onChanged: (_) {}));
        overlay = 'branch picker';
        await tester.tap(find.byType(RefPickerButton).first);
        await _settle(tester);
        expect(_overlayShown(), isTrue, reason: 'branch picker did not open');
        Navigator.of(ctx(), rootNavigator: true).pop();
        await _settle(tester);
        await show(
          'host key changed dialog',
          (c) => confirmHostKey(
            c,
            hostName: 'dev-laptop.local',
            type: 'ssh-ed25519',
            fingerprint: 'SHA256:${'Zm9vYmFyYmF6' * 4}',
            previous: 'SHA256:${'cXV4cXV1eA' * 4}',
          ),
        );
        await show(
          'password dialog',
          (c) => showDialog<String>(
            context: c,
            builder: (_) => const PasswordDialog(address: 'demo@dev-laptop.local'),
          ),
        );
        overlay = 'open by name';
        router.go(Routes.repos);
        await _settle(tester);
        await tester.tap(find.byTooltip('Open by name'));
        await _settle(tester);
        expect(_overlayShown(), isTrue, reason: 'open by name did not open');
        Navigator.of(ctx(), rootNavigator: true).pop();
        await tester.pumpWidget(const SizedBox());
        await _settle(tester);
      } finally {
        FlutterError.onError = previous;
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }
}

bool _overlayShown() => find.byType(BottomSheet).evaluate().isNotEmpty || find.byType(Dialog).evaluate().isNotEmpty;

/// pumpAndSettle can spin forever on progress indicators; cap the wait.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (!tester.binding.hasScheduledFrame) return;
  }
}
