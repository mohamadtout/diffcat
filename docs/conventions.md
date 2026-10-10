# Conventions

## Workflow

- `make check` is the definition of done (it's what CI runs: `.github/workflows/ci.yml`).
- `make fmt` formats Dart at 120 columns (set in `app/analysis_options.yaml`).
- Analyzer runs with `strict-casts` and `strict-raw-types` plus extra lints. Fix warnings; don't suppress them without a comment explaining why.

## Dart / Flutter

- **Feature-first folders:** `features/<feature>/` holds that feature's screens, providers, and pure logic. Shared UI goes in `core/widgets`; shared infrastructure goes in `core/*`.
- **Reuse before copying:** `core/widgets` has `AsyncView`, `EmptyView`, `SectionHeader` (settings group headings), `askText` (one-line text dialogs with validation), the color picker and the text-size sheet. When a screen file grows past ~500 lines, move its leaf widgets out (a `part` file keeps private ones private, as `diff_rows.dart` does).
- **Pure logic in plain Dart files** (parsers, builders, executors) with no Flutter imports where possible, so it's unit-testable. Examples: `diff_parser.dart`, `tree_builder.dart`, `key_sequence.dart`, `command_line.dart`.
- **Models:** hand-written immutable classes with `fromJson` and explicit casts. No codegen, which keeps the build simple for agents and CI.
- **Providers:** declare them next to the feature that owns them (`*_providers.dart`). Use records as family keys. Prefer `autoDispose` unless state must survive navigation, and say why in a comment when it must.
- **Async UI:** render `AsyncValue` with `AsyncView` (consistent loading, error and retry).
- **Navigation:** always go through `Routes.*` builders, never string literals. Use `context.push` for drill-down and `go` for deep links.
- **Layouts:** check `WindowSize` / `SplitView.isActive`; wrap list-style screens in `ReadableWidth`. Never assume a phone. When you measure text yourself (`TextPainter`), pass `textScaler: MediaQuery.textScalerOf(context)`, or large system text overflows.
- **Secrets:** use `SecureStore` with keys from `StoreKeys`. Non-secrets go in `sharedPrefsProvider` via the `JsonPrefs` helpers.
- **Text:** user-facing strings are plain English in widgets for now (see roadmap: i18n).

## Adding a feature (checklist)

1. Pure logic + tests → `features/<x>/…`, `test/features/…_test.dart`.
2. Provider(s) for data → `features/<x>/<x>_providers.dart`.
3. Screen(s): add a route to `Routes` and `app_router.dart`, and support split view if it's a list/detail.
4. Update `docs/features.md` (and `architecture.md` if you add a layer, route, or endpoint).
5. `make check`.

## Testing

- Unit tests for parsers, executors, and HTTP behaviour. `GitHubClient` is tested with a scripted Dio adapter (`test/data/github_client_test.dart`). The API is mocked with `mocktail`.
- Widget tests wait with `settle` (`test/support/settle.dart`), not `pumpAndSettle`, which spins forever on progress indicators. They use `SharedPreferences.setMockInitialValues` and `FlutterSecureStorage.setMockInitialValues`, and override `sharedPrefsProvider`.
- **Demo project** (`test/support/demo_github.dart`, `demo_app.dart`): a fictional `demo/payments-api` with commits, diffs, PRs, a file tree, tags and SSH hosts. `DemoEnv` runs the whole `GitReviewerApp` on it, with in-memory prefs and secure storage and `githubAdapterProvider` overridden. The screen-size sweep, the device smoke test and the store screenshots all use it. When a screen calls a new endpoint, add it there: unknown calls are recorded and fail those tests.
- **Screen-size sweep** (`test/widgets/screen_sizes_test.dart`, part of `make check`): every route, plus the sheets and dialogs, at 12 sizes from a 320×568 phone to a desktop. It covers portrait and landscape, text at 1×, 1.5× and 2×, and signed in and out. Any layout error fails the test with the size and screen. It loads the SDK's Roboto (`test/support/fonts.dart`) so text widths are realistic. Add new routes to its list.
- **Store screenshots:** `make store-screenshots DEVICE=<id> NAME=<folder>`, then `make store-frames`. See [store/README.md](../store/README.md).
- On-device smoke test: `make device-test DEVICE=<id>` (`app/integration_test/device_smoke_test.dart`). It runs the real app with real platform plugins on a phone or tablet. GitHub is replaced by the demo project, so no token is needed. It taps through the main screens and saves screenshots to `app/build/device_screenshots/`. CI can't run it (no device). Run it after layout or platform changes, and extend the canned routes when a screen calls a new endpoint (unknown calls fail the test).
- Real offline download on a device: `make offline-test DEVICE=<id>` (`app/integration_test/offline_test.dart`). It downloads `octocat/Hello-World` signed out into a throwaway store, reads it back with networking disabled, then drives the download button and Downloads screens and takes screenshots.
- Real SSH from a device: `make ssh-test DEVICE=<id> SSH_HOST=<tailscale ip> SSH_USER=<user> SSH_KEY=<private key file>` (`app/integration_test/ssh_test.dart`). The key must already be in the host's `authorized_keys`. The test checks the trust prompt shows the host's real fingerprint, runs commands through the Terminal screen, and installs then uses a fresh key (lines commented `git-reviewer-device-test-installed`; remove them afterwards). Keep the device unlocked while it runs.
