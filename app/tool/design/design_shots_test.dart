import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/core/widgets/text_size_sheet.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/actions/run_workflow_sheet.dart';
import 'package:git_reviewer/features/offline/download_button.dart';
import 'package:git_reviewer/features/offline/offline_store.dart';
import 'package:git_reviewer/features/pulls/review_widgets.dart';
import 'package:git_reviewer/features/repo/ref_picker.dart';
import 'package:git_reviewer/features/terminal/host_edit_screen.dart';
import 'package:git_reviewer/features/terminal/host_key_dialog.dart';
import 'package:git_reviewer/features/terminal/ssh_session.dart';
import 'package:git_reviewer/features/terminal/terminal_appearance_screen.dart';

import '../../test/support/demo_app.dart';
import '../../test/support/demo_github.dart';
import '../../test/support/fonts.dart';
import '../../test/support/settle.dart';

/// Screenshots of the real app on demo data, for reviewing the UI without a
/// device: `make design-shots`. Not part of `make check` (it lives outside
/// test/ and only writes files).
///
/// Every screen the screen-size sweep (test/widgets/screen_sizes_test.dart)
/// visits, plus the PR tabs, sheets and dialogs, and the empty, error and
/// signed-out states, in each [_configs] entry. Output goes to
/// `app/build/design/<size>-<theme>/<screen>.png`, with an `index.md` per
/// folder listing every file, its route and any layout errors.
const _configs = <(String, Size, double, ThemeMode)>[
  ('phone-light', Size(393, 852), 1, ThemeMode.light),
  ('phone-dark', Size(393, 852), 1, ThemeMode.dark),
  ('tablet-light', Size(1376, 1032), 1, ThemeMode.light),
  ('phone-text150-light', Size(393, 852), 1.5, ThemeMode.light),
];
const _pixelRatio = 2.0;

final _repoRoot = Directory.current.path.endsWith('/app') ? Directory.current.parent.path : Directory.current.path;
final _outRoot = '$_repoRoot/app/build/design';

const _r = DemoGitHub.repo;
const _missingRepo = (owner: DemoGitHub.owner, name: 'missing-repo');

/// One screenshot: go to [route], then optionally [open] something on it (a
/// tab, a sheet, a dialog). An overlay left open is closed after the shot.
/// Going to the route already shown keeps that screen's state (its tab, its
/// toggles), so order shots of one screen with that in mind.
class _Shot {
  const _Shot(this.name, this.route, [this.open]);

  final String name;
  final String route;
  final Future<void> Function(WidgetTester tester, BuildContext context)? open;
}

Future<void> Function(WidgetTester, BuildContext) _tap(Finder Function() finder) => (tester, _) async {
  await tester.tap(finder().first);
  await settle(tester);
};

Future<void> Function(WidgetTester, BuildContext) _show(void Function(BuildContext) open) => (tester, context) async {
  open(context);
  await settle(tester);
};

/// Signed in, with a saved branch: the routes of the screen-size sweep (keep
/// in sync), then the PR tabs and the sheets and dialogs it checks.
final _main = <_Shot>[
  const _Shot('repos', Routes.repos),
  const _Shot('inbox', Routes.inbox),
  _Shot('repo-commits', Routes.repo(_r)),
  _Shot('repo-files', Routes.repo(_r, tab: 'files')),
  _Shot('repo-pulls', Routes.repo(_r, tab: 'pulls')),
  _Shot('repo-actions', Routes.repo(_r, tab: 'actions')),
  _Shot('repo-console', Routes.repo(_r, tab: 'console')),
  _Shot('commit', Routes.commit(_r, DemoGitHub.sha(1))),
  _Shot('commit-diff', Routes.commit(_r, DemoGitHub.sha(1), file: DemoGitHub.retryGo)),
  _Shot('compare', Routes.compare(_r, 'main', DemoGitHub.featureBranch)),
  _Shot('pull-files', Routes.pull(_r, DemoGitHub.openPullNumber)),
  _Shot('pull-review-sheet', Routes.pull(_r, DemoGitHub.openPullNumber), _tap(() => find.text('Review'))),
  _Shot(
    'pull-comment-composer',
    Routes.pull(_r, DemoGitHub.openPullNumber),
    _show((c) => showCommentComposer(c, title: 'retry.go:27')),
  ),
  _Shot('pull-overview', Routes.pull(_r, DemoGitHub.openPullNumber), _tap(() => find.text('Overview'))),
  _Shot('pull-commits', Routes.pull(_r, DemoGitHub.openPullNumber), _tap(() => find.textContaining('Commits ('))),
  _Shot('run-failed', Routes.run(_r, DemoGitHub.failedRunId)),
  _Shot('run-in-progress', Routes.run(_r, 5001)),
  _Shot('job-log', Routes.jobLog(_r, DemoGitHub.failedJobId)),
  _Shot('file', Routes.file(_r, DemoGitHub.retryGo, 'main')),
  _Shot('file-history', Routes.history(_r, DemoGitHub.retryGo, 'main')),
  _Shot('file-blame', Routes.file(_r, DemoGitHub.retryGo, 'main', blame: true)),
  _Shot('changed-since', Routes.changedSince(_r, ref: 'main', base: 'v1.4.0')),
  const _Shot('terminal-hosts', Routes.terminal),
  _Shot('host-new', Routes.hostEdit(null)),
  _Shot('host-edit', Routes.hostEdit(demoHosts.first.id)),
  _Shot('terminal-session', Routes.terminalSession(demoHosts.first.id)),
  const _Shot('settings', Routes.settings),
  const _Shot('settings-commands', Routes.commands),
  const _Shot('settings-terminal', Routes.terminalAppearance),
  const _Shot('settings-code-view', Routes.codeView),
  const _Shot('settings-repos', Routes.repoList),
  const _Shot('settings-repo-folders', Routes.repoFolders),
  const _Shot('downloads', Routes.downloads),
  _Shot('downloads-repo', Routes.savedRepo(_r)),
  const _Shot('setup', Routes.setup),
  _Shot('sheet-download', Routes.repo(_r), _show((c) => showDownloadSheet(c, repo: _r, branch: 'main'))),
  _Shot(
    'sheet-download-new-branch',
    Routes.repo(_r),
    _show((c) => showDownloadSheet(c, repo: _r, branch: DemoGitHub.featureBranch)),
  ),
  _Shot('sheet-shell-integration', Routes.repo(_r), _show(showShellIntegrationSheet)),
  _Shot(
    'sheet-run-workflow',
    Routes.repo(_r, tab: 'actions'),
    _show(
      (c) => showRunWorkflowSheet(
        c,
        repo: _r,
        gitRef: 'main',
        workflows: const [
          GhWorkflow(
            id: DemoGitHub.deployWorkflowId,
            name: 'Deploy',
            path: '.github/workflows/deploy.yml',
            state: 'active',
          ),
        ],
      ),
    ),
  ),
  _Shot(
    'sheet-text-size',
    Routes.codeView,
    _show((c) => showTextSizeSheet(c, value: 13, min: 8, max: 24, onChanged: (_) {})),
  ),
  _Shot('sheet-branch-picker', Routes.repo(_r), _tap(() => find.byType(RefPickerButton))),
  _Shot(
    'dialog-host-key-changed',
    Routes.terminal,
    _show(
      (c) => confirmHostKey(
        c,
        hostName: 'dev-laptop.local',
        type: 'ssh-ed25519',
        fingerprint: 'SHA256:${'Zm9vYmFyYmF6' * 4}',
        previous: 'SHA256:${'cXV4cXV1eA' * 4}',
      ),
    ),
  ),
  _Shot(
    'dialog-password',
    Routes.terminal,
    _show(
      (c) => showDialog<String>(
        context: c,
        builder: (_) => const PasswordDialog(address: 'demo@dev-laptop.local'),
      ),
    ),
  ),
  _Shot('dialog-open-by-name', Routes.repos, _tap(() => find.byTooltip('Open by name'))),
];

/// On [_StatesGitHub]: nothing to show, or GitHub refusing.
final _states = <_Shot>[
  const _Shot('empty-inbox', Routes.inbox),
  _Shot('empty-commits', Routes.repo(_r)),
  _Shot('empty-pulls', Routes.repo(_r, tab: 'pulls')),
  _Shot('empty-actions', Routes.repo(_r, tab: 'actions')),
  const _Shot('empty-downloads', Routes.downloads),
  _Shot('empty-host-not-found', Routes.terminalSession('missing-host')),
  _Shot('error-repo-not-found', Routes.repo(_missingRepo)),
  _Shot('error-rate-limited', Routes.compare(_r, 'main', DemoGitHub.featureBranch)),
];

final _signedOut = <_Shot>[
  const _Shot('signed-out-repos', Routes.repos),
  const _Shot('signed-out-inbox', Routes.inbox),
  const _Shot('signed-out-settings', Routes.settings),
];

void main() {
  late Directory dir;
  late OfflineStore store;
  late OfflineStore emptyStore;

  setUpAll(() async {
    if (!await loadSdkFonts()) throw StateError('SDK fonts not found: screenshots would show boxes, not text');
    await loadAppFonts();
    dir = await Directory.systemTemp.createTemp('design_shots');
    store = await OfflineStore.open(Directory('${dir.path}/saved'));
    emptyStore = await OfflineStore.open(Directory('${dir.path}/empty'));
    // In memory only (no flush): widget tests can't wait on real file I/O.
    store.saveBranch(
      DemoGitHub.repo.fullName,
      'main',
      SavedBranch(updatedAt: DateTime.now(), options: const DownloadOptions(), commits: const []),
    );
  });
  tearDownAll(() => dir.delete(recursive: true));

  for (final (folder, size, textScale, theme) in _configs) {
    testWidgets('design shots: $folder', (tester) async {
      tester.view
        ..physicalSize = size * _pixelRatio
        ..devicePixelRatio = _pixelRatio;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // Widget tests draw shadows as solid black outlines; real ones look like the app. Put back
      // before the test ends: the framework checks debug flags before tear-downs run.
      debugDisableShadows = false;

      final out = Directory('$_outRoot/$folder');
      if (out.existsSync()) out.deleteSync(recursive: true); // no stale shots from an older run
      out.createSync(recursive: true);

      final written = <(_Shot, List<String>)>[];
      final unknown = <String>{};
      var problems = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (d) => problems.add(d.exceptionAsString().split('\n').first);
      try {
        // One at a time: each DemoEnv.create resets the shared mock storage.
        for (final (shots, create) in [
          (_main, () => DemoEnv.create(store: store)),
          (_states, () => DemoEnv.create(store: emptyStore, github: _StatesGitHub())),
          (_signedOut, () => DemoEnv.create(signedIn: false, store: store)),
        ]) {
          final env = await create();
          await env.prefs.setString(StoreKeys.themeMode, theme.name);
          await tester.pumpWidget(RepaintBoundary(key: _boundary, child: env.app()));
          await settle(tester);
          final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
          final router = container.read(routerProvider);
          BuildContext ctx() => tester.element(find.byType(Scaffold).last);

          for (final shot in shots) {
            problems = [];
            try {
              if (shot.route == Routes.terminalSession(demoHosts.first.id)) _fakeTerminalOutput(container);
              router.go(shot.route);
              await settle(tester);
              await settle(tester); // a second pass for loads that chain (repo, then its commits)
              await shot.open?.call(tester, ctx());
              await _capture(tester, '${out.path}/${shot.name}.png');
              if (_overlayShown()) {
                Navigator.of(ctx(), rootNavigator: true).pop();
                await settle(tester);
              }
            } on Object catch (e) {
              problems.add('$e'.split('\n').first);
            }
            final e = tester.takeException();
            if (e != null) problems.add('$e'.split('\n').first);
            written.add((shot, problems));
          }
          unknown.addAll(env.github.unknown.where((p) => !p.contains(_missingRepo.name)));
          // Leave the tree so pending timers and sessions shut down inside the test.
          await tester.pumpWidget(const SizedBox());
          await settle(tester);
        }
      } finally {
        FlutterError.onError = previous;
        debugDisableShadows = true;
      }

      File('${out.path}/index.md').writeAsStringSync(_index(folder, size, textScale, theme, written, unknown));
      final failed = written.where((w) => w.$2.isNotEmpty).map((w) => w.$1.name);
      debugPrint(
        'wrote ${written.length} screenshots to ${out.path}'
        '${failed.isEmpty ? '' : '; problems (see index.md): ${failed.join(', ')}'}',
      );
    });
  }
}

final _boundary = GlobalKey();

/// Writes the whole app (overlays included) as a PNG at [_pixelRatio].
Future<void> _capture(WidgetTester tester, String path) async {
  await tester.runAsync(() async {
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File(path).writeAsBytes(png!.buffer.asUint8List());
  });
}

bool _overlayShown() => find.byType(BottomSheet).evaluate().isNotEmpty || find.byType(Dialog).evaluate().isNotEmpty;

/// A connected-looking session with some shell output, as in the store
/// screenshots, instead of a failed SSH connection to a fictional host.
void _fakeTerminalOutput(ProviderContainer container) {
  final session = container.read(sshSessionsProvider).obtain(demoHosts.first);
  if (session.status == SshStatus.connected) return;
  session
    ..status = SshStatus.connected
    ..terminal.write(
      '\x1b[1;32mpayments-api\x1b[0m % git status -sb\r\n'
      '\x1b[32m## feature/retry-backoff\x1b[0m [ahead \x1b[32m1\x1b[0m]\r\n'
      ' \x1b[31mM\x1b[0m internal/webhooks/retry.go\r\n'
      '\x1b[1;32mpayments-api\x1b[0m % go test ./internal/webhooks\r\n'
      '\x1b[32mok\x1b[0m  internal/webhooks  0.412s\r\n'
      '\x1b[1;32mpayments-api\x1b[0m % ',
    );
}

String _index(
  String folder,
  Size size,
  double textScale,
  ThemeMode theme,
  List<(_Shot, List<String>)> written,
  Set<String> unknown,
) {
  final b = StringBuffer()
    ..writeln('# Design shots: $folder')
    ..writeln()
    ..writeln(
      '${size.width.toInt()}×${size.height.toInt()} dp at ${_pixelRatio.toInt()}x, text ${textScale}x, '
      '${theme.name} theme, on demo data. Written by `make design-shots` '
      '(app/tool/design/design_shots_test.dart); not committed. Fonts: Roboto, the bundled code fonts, and '
      'Source Code Pro in place of the platform monospace. Tests have no system font fallback, so characters '
      'Roboto lacks (such as →) show as boxes here but not on a device.',
    )
    ..writeln()
    ..writeln('| Screen | Route | Problems |')
    ..writeln('|---|---|---|');
  for (final (shot, problems) in written) {
    b.writeln(
      '| [${shot.name}.png](${shot.name}.png) | `${shot.route}` | ${problems.join('<br>').replaceAll('|', r'\|')} |',
    );
  }
  if (unknown.isNotEmpty) {
    b
      ..writeln()
      ..writeln('GitHub calls the demo API does not cover: ${unknown.map((u) => '`$u`').join(', ')}');
  }
  return b.toString();
}

/// The demo API with the payments-api repo emptied (no pull requests, runs or
/// commits), an empty inbox, and comparisons refused for the rate limit.
class _StatesGitHub extends DemoGitHub {
  static const _base = '/repos/${DemoGitHub.owner}/${DemoGitHub.repoName}';

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    final p = options.path;
    final Object? empty = switch (p) {
      '/search/issues' => {'total_count': 0, 'incomplete_results': false, 'items': <Object>[]},
      '$_base/pulls' || '$_base/commits' => <Object>[],
      _ when p.startsWith('$_base/actions/') && p.endsWith('/runs') => {'total_count': 0, 'workflow_runs': <Object>[]},
      _ => null,
    };
    if (empty != null) return Future.value(_json(empty, 200));
    if (p.startsWith('$_base/compare/')) {
      final reset = DateTime.now().add(const Duration(minutes: 23)).millisecondsSinceEpoch ~/ 1000;
      return Future.value(
        _json(
          {'message': 'API rate limit exceeded'},
          403,
          headers: {
            'x-ratelimit-remaining': ['0'],
            'x-ratelimit-reset': ['$reset'],
          },
        ),
      );
    }
    return super.fetch(options, requestStream, cancelFuture);
  }

  static ResponseBody _json(Object data, int status, {Map<String, List<String>> headers = const {}}) =>
      ResponseBody.fromString(
        jsonEncode(data),
        status,
        headers: {
          'content-type': ['application/json'],
          ...headers,
        },
      );
}
