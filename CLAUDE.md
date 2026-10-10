# Diffcat — agent guide

Mobile (Flutter) app for reviewing GitHub code changes from a phone. No backend:
data comes from the GitHub API, notifications from on-device background polling.
Android first; iOS/iPadOS planned (keep everything responsive and platform-neutral).

## Layout

```
app/         Flutter app (Dart)          → docs/architecture.md
docs/        Focused docs — read the one relevant to your task
SETUP.md     Manual, owner-only configuration (token, SSH, signing)
store/       App Store / Google Play / GitHub Marketplace listings and screenshots → store/README.md
marketplace-webhook/  Cloudflare Worker the Marketplace listing requires (stateless) → its README.md
PRIVACY.md   Privacy policy (linked from both stores)
CHANGELOG.md What's in each version; branching and versioning rules
Makefile     Entry points: make check | fmt | run | apk | release-apk
```

## Branches and versions

`main` is what's released (tagged `vX.Y.Z`). Unreleased work lands on `development` through one PR per feature from
`feature/<name>` branches. Version in `app/pubspec.yaml`: minor bump for features, patch for fixes, and the `+build`
number always goes up (stores reject reused numbers). Record changes in CHANGELOG.md.

## Before you finish any change

1. `make check` — format, analyze (strict), tests. Must be green.
2. New logic gets a unit test (pure code lives outside widgets for this reason).
3. Update the doc that owns the area you touched (table below). Docs are part of the change.

## Where things are documented

| Topic | Doc |
|---|---|
| Layers, state management, routing table, data flow | [docs/architecture.md](docs/architecture.md) |
| Feature → file map, UX behaviors | [docs/features.md](docs/features.md) |
| API console commands, SSH key notation, custom buttons | [docs/commands.md](docs/commands.md) |
| Background polling → local notifications | [docs/notifications.md](docs/notifications.md) |
| Instant push plan (not built): GitHub App + Cloudflare Worker + FCM/APNs | [docs/instant-push.md](docs/instant-push.md) |
| Code style, patterns, testing, adding a feature | [docs/conventions.md](docs/conventions.md) |
| Why things are the way they are | [docs/decisions.md](docs/decisions.md) |
| iOS/iPadOS plan and backlog | [docs/roadmap.md](docs/roadmap.md) |
| Store listings, screenshots, privacy policy | [store/README.md](store/README.md), [PRIVACY.md](PRIVACY.md) |

## Hard rules

- **Never clone repos onto the device.** Read through the GitHub REST API (`app/lib/data/github/`)
  or run git on the user's own machine over SSH (`app/lib/features/terminal/`). Offline copies are saved
  API responses, downloaded only when the user asks (`app/lib/features/offline/`), never a git clone.
  The notification poller must use `liveGithubApiProvider` (no offline copies) or it would miss new commits.
- **Secrets only in secure storage** (`SecureStore`, keys in `StoreKeys`). Never in prefs, logs, or code.
- **No backend.** Don't reintroduce servers, webhooks or Firebase without the owner asking. Notifications are
  on-device polling (`app/lib/features/notifications/`); the background isolate has no Riverpod, so keep
  `Poller` dependent only on `GitHubApi` + `SharedPreferences`. The one exception is `marketplace-webhook/` (D15):
  a stateless Cloudflare Worker the Marketplace listing requires. The app never talks to it; keep it storing nothing.
- **Every screen is reachable by a route** in `Routes` (notifications and iPad multi-pane depend on it).
- **Responsive by default:** use `WindowSize` / `SplitView` / `ReadableWidth`; no phone-only layouts. New routes go in
  `test/widgets/screen_sizes_test.dart`, which checks every screen from small phones to desktops.
- Verify third-party package APIs against `~/.pub-cache` sources; several deps are newer than common
  training data (go_router 18, Riverpod 3, dartssh2 4, flutter_local_notifications 22, xterm 4, workmanager 0.10).
