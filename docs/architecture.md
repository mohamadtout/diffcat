# Architecture

## Big picture

```
┌──────────── Phone (Flutter app) ───────────────┐        ┌──────── GitHub ────────┐
│                                                │  REST  │                        │
│  Repos · Commits · Files · PRs · Console ──────┼───────▶│  api.github.com        │
│                                                │        │                        │
│  Background poller (WorkManager, ~15 min) ─────┼───────▶│  branches / pulls /    │
│     └▶ local notifications ─tap─▶ route        │        │  compare               │
│                                                │        └────────────────────────┘
│  Terminal (xterm + dartssh2) ──── SSH ─────────┼──┐     ┌──── Your machine ─────┐
└────────────────────────────────────────────────┘  └────▶│ sshd · git · lazygit  │
                                                          └───────────────────────┘
```

There's no backend. Data reaches the phone in two ways, neither of which clones a repo:

1. **GitHub REST API**: all browsing, diffs, history, compare, PRs, the API console, and the notification poller.
2. **SSH**: a real shell on a machine the user owns, for lazygit and arbitrary git commands.

## App layers (`app/lib`)

```
main.dart            bootstrap: error safety net, prefs, LocalNotifications, BackgroundPolling, ProviderScope
app.dart             MaterialApp.router, theme, notification-tap → router.go, check-on-resume
core/
  routing/           Routes (path builders), app_router (GoRouter), root_scaffold (bar/rail)
  layout/            WindowSize breakpoints, SplitView (list/detail on wide screens), ReadableWidth
  theme/             AppTheme, DiffColors theme extension, monospace font
  storage/           SharedPreferences + SecureStore providers, StoreKeys
  widgets/, utils/   AsyncView/ErrorView/EmptyView, avatars, badges, text-size sheet, time formatting
data/github/         GitHubClient (HTTP, ETag cache, pagination, errors), GitHubApi (typed endpoints), models
features/<name>/     screens + providers + pure logic per feature (see docs/features.md)
```

Dependencies only point downwards: features may use `core` and `data`, but `core` and `data` never import features. The exceptions are `core/routing/app_router.dart` and `app.dart`, which are the composition root.

## State management: Riverpod 3 (no codegen)

- **Server data** uses `FutureProvider.autoDispose.family` keyed by Dart **records** (`({RepoRef repo, String sha})`). Records give structural equality for free.
- **Paged lists** use `AsyncNotifierProvider.autoDispose.family` + `Paged<T>` with `loadMore()` (see `CommitListNotifier`).
- **Local, persisted state** uses `Notifier`s backed by `sharedPrefsProvider` (custom commands, SSH hosts, watched/pinned repos, theme, diff settings).
- **Screen-local UI state** (the selected branch, selected item in split view) lives in `StatefulWidget`s, not providers. This keeps pushed screens independent: "browse at commit X" doesn't change the branch on the screen below it.
- **Retries:** `ProviderScope.retry` in `main.dart` retries only transient errors (`GitHubException.isRetryable`).
- **Background isolate:** the WorkManager task (`backgroundPollDispatcher`) runs without Riverpod. `Poller` takes a `GitHubApi` and `SharedPreferences` directly, so the same code runs in both isolates.
- **Heavy work off the UI thread:** trees over 5,000 entries are built with `Isolate.run`, saved responses over 50 KB are
  decoded with `compute` (Dio already does this for network JSON), and the file viewer splits a file once per content.
- **Long-lived things** (`sshSessionsProvider`, `consoleProvider`) are deliberately not auto-disposed, so an SSH session or console scrollback survives navigation.

## GitHub access

`GitHubClient` wraps Dio:

- Sends `Authorization: Bearer <token>` when signed in (nothing when signed out) and `X-GitHub-Api-Version: 2022-11-28`. `githubApiProvider` is always available; `isSignedInProvider` says which mode it's in.
- Uses **conditional requests**: it stores `ETag`s (LRU, 300 entries) and sends `If-None-Match`. A `304` reuses the cached body and doesn't count against the rate limit.
- `getPage` / `getAll` follow `Link: rel="next"`.
- The background notification check also passes an `EtagCache` (`FileEtagCache`), so its conditional requests survive
  between runs (each run is a fresh isolate with an empty memory cache).
- `getBytes` (tarballs) streams and stops at 300 MB rather than holding an unbounded archive in memory. Redirects to
  `codeload.github.com` don't carry the token: Dart's `HttpClient` drops `Authorization` on cross-origin redirects.
- Maps errors to `GitHubException` (`isUnauthorized`, `isNotFound`, `isRateLimited`, `isRetryable`). `ErrorView` turns these into readable messages.
- **Offline copies** (`features/offline/`, decision D11): the client takes an optional `ResponseCache`. In `CacheMode.replay` (screens, via `githubApiProvider`) a saved response is returned before any network call. In `CacheMode.record` (`BranchDownloader`) every response is fetched and saved. Keys come from `GitHubClient.cacheKey` (owner/name case-insensitive). `OfflineStore` keeps one folder per repo with an `index.json` that files each response under a group (`repo`, `branch:<name>`, `commit:<sha>`, `pr:<n>`, `files:<branch>`) for sizes and selective deletes. `liveGithubApiProvider` skips the cache (the notification poller uses it). Both take their transport from `githubAdapterProvider` (null means the real network). Tests and the store screenshots override it with canned responses, so the offline layer and everything above it run unchanged. **Offline mode** (`offlineModeProvider`, a remembered per-repo set) adds `cacheOnly` to the screens' client: for those repos a missing response throws `GitHubException.notDownloaded` (never retried) instead of going to the network. The repo list merges `savedReposInfoProvider` (repo details read back from the saved copies) into your repos, so downloads show up even with no network.

### git → GitHub API mapping

| git concept | Endpoint | Used by |
|---|---|---|
| `git log [ref] [-- path]` | `GET /repos/{o}/{r}/commits?sha=&path=` | Commits tab, file history, console `log`/`history` |
| `git show <sha>` | `GET /repos/{o}/{r}/commits/{sha}` (files paginated, ≤3000) | Commit screen, console `show` |
| `git diff a...b` | `GET /repos/{o}/{r}/compare/{a}...{b}` (≤300 files) | Changed-since, compare screen, console `diff`/`since` |
| `git ls-tree -r` | `GET /repos/{o}/{r}/git/trees/{ref}?recursive=1` | Files tab, console `ls` |
| `git show ref:path` | `GET /repos/{o}/{r}/contents/{path}?ref=` (raw) | File viewer, console `cat` |
| branches / tags | `GET …/branches`, `GET …/tags` | Ref picker, console, poller |
| `git blame` | GraphQL `repository.object(expression:).blame(path:)` (token required) | File viewer blame |
| PRs | `GET …/pulls`, `…/pulls/{n}`, `…/files`, `…/commits` | PRs tab, PR screen, poller |

Known API limits: the tree is truncated for huge repos, compare returns at most 300 files, a single commit returns at most 3000 files, and file history doesn't follow renames. The UI says so wherever one of these applies.

## Error handling

- Every network-backed view renders through `AsyncView`, which shows loading, error and retry states. Pass `error:` for a domain-specific explanation, e.g. `RepoUnavailableView` for 404/403 on a repo, since GitHub reports private repos the token can't see as "not found".
- Fire-and-forget calls (e.g. `loadMore()` from scrolling) never throw. They record the failure in state (`Paged.loadMoreError`), and the UI offers Retry.
- Safety net in `main.dart`: uncaught async errors are logged rather than fatal, and a widget that throws while building is replaced by a small inline error instead of the red or grey full screen.
- Dialogs own their `TextEditingController`s in a `StatefulWidget`. Disposing a controller right after `await showDialog` crashes with `'_dependents.isEmpty'`, because the dialog is still animating out.

## Routing

`Routes` builds every path, and `app_router.dart` declares them. A `StatefulShellRoute` has three branches (Repos, Terminal, Settings), so each tab keeps its own stack.

| Route | Screen |
|---|---|
| `/` · `/setup` | splash · optional token sign-in (pushed from Repos/Settings) |
| `/repos` | repository list |
| `/repos/:owner/:name?tab=&ref=` | repo home (Commits / Files / PRs / Console) |
| `/repos/:owner/:name/commit/:sha?file=` | commit diff, optionally focused on a file |
| `/repos/:owner/:name/compare?base=&head=&file=` | range diff (multi-commit notifications land here) |
| `/repos/:owner/:name/pull/:number` | pull request |
| `/repos/:owner/:name/file?path=&ref=&blame=1` | file viewer (optionally with blame) |
| `/repos/:owner/:name/history?path=&ref=` | file history |
| `/repos/:owner/:name/since?ref=&base=` | "files changed since commit X" |
| `/terminal`, `/terminal/edit?id=`, `/terminal/:hostId` | SSH hosts, host editor, live session |
| `/settings`, `/settings/commands` | settings, custom buttons |
| `/settings/terminal` | terminal appearance |
| `/settings/code` | code view (font, full files, diff colors) |
| `/settings/downloads`, `/settings/downloads/:owner/:name` | offline storage: all repos, one repo by branch/commit/PR |

Because repo routes are nested under `/repos`, `router.go(route)` from a notification builds a proper back stack (repo list → repo → commit).

Redirects: while auth is loading the app stays on `/`, then goes to `LocalNotifications.takeLaunchRoute()` (a cold-start notification tap) or `/repos`, signed in or not. After a successful sign-in, `TokenScreen` pops back to wherever it was pushed from (or goes to `/repos` on a direct visit). It waits one frame first: the auth change refreshes the router, which re-applies the current stack and would undo an immediate pop.

## Responsive layout

- `WindowSize.compact` (<600dp) gets a bottom `NavigationBar`, which only appears on top-level screens so it never stacks with the repo tab bar. Repo tabs go in a bottom bar.
- `medium` / `expanded` get a `NavigationRail`, and repo tabs become a segmented control in the app bar.
- List-style screens (repo list, Settings, Downloads, SSH hosts, command buttons, host form) use `ReadableWidth`, which keeps rows at a 720dp reading width on wide screens. It pads the list rather than shrinking it, so the list still scrolls when dragged in the margins.
- `expanded` (≥840dp) activates `SplitView`: the commit, file and PR lists show their detail beside them instead of pushing a route. Each list checks `SplitView.isActive(context)`. The handle between the panes collapses the list for a full-width detail (`splitCollapsedProvider`, shared by all split views and remembered). The list stays mounted while hidden, so its scroll position survives.

## Diff rendering

`diff_parser.dart` parses GitHub's `patch` hunks. `DiffDocument` flattens all files into rows (file header, hunk header, line, notice, gap), and `DiffView` renders them in a single `SuperSliverList`:

- It's lazy, so a 5,000-line commit scrolls smoothly, and `ListController.jumpToItem` powers "jump to file".
- **No-wrap mode** pans only the code column horizontally (a shared `AnimationController` plus `Transform.translate`, with fling), so line numbers stay visible. Wrap mode is a toggle and persists.
- **Full files:** `fullFileLines` merges the new file's content with the hunks (context lines between them get both
  line numbers) and returns null if the content doesn't match, e.g. a compare whose head branch moved. A file header
  requests its content after it's built, so only files scrolled near cost a request.
- **Colors** come from the `DiffColors` theme extension, which `app.dart` builds from `diffColorsProvider` (a palette
  plus per-slot overrides for light and dark), so every `DiffColors.of(context)` follows the user's choice.
- **Syntax and word diffs** (`syntax.dart`, pure): `highlightDiffLines` highlights each side of a file's diff as one
  text (new side: context + added; old side: context + removed), so block comments and strings spanning lines color
  right, then splits the result back into lines. `pairedWordDiffs` pairs the i-th removed with the i-th added line of a
  change block and marks differing tokens (token LCS, skipped for rewrites). Both run per file the first time one of
  its lines is built and are looked up per line through `Expando`s.
- Files with more than 1200 changed lines start collapsed. The toolbar shows the file currently on screen; tap it for the file list.

## SSH terminal

`SshSessionController` wires a `dartssh2` shell to an `xterm` `Terminal`:

- PTY type `xterm-256color`. Resizes are forwarded. Output is decoded as streaming UTF-8.
- Host keys use trust-on-first-use, stored in prefs (`KnownHosts`). A changed key gets a red warning dialog.
- On-screen toolbar: Esc/Tab/arrows/PgUp…, plus sticky **Ctrl/Alt** that modify the next typed key.
- Custom buttons and the startup command use key notation (docs/commands.md) and go through `Terminal.keyInput`, so arrow keys respect application-cursor mode (important for lazygit).
- Sessions live in `SshSessionRegistry`, so leaving the screen doesn't drop the connection while the app is in the foreground.
- **Status bar / shell integration** (`shell_integration.dart`): the shell's folder arrives as OSC 7 (`Terminal.onPrivateOSC`).
  After each report the session runs `git status --porcelain=v2 --branch` in that folder on a separate exec channel
  (`SSHClient.run`, `GIT_OPTIONAL_LOCKS=0`), never in the user's shell. With shell integration on, the hook is typed
  once the login output settles; `EchoHider` hides its echo up to a private OSC marker and fails open after 4 s.
- **Appearance** (`terminalAppearanceProvider`) is one JSON blob in prefs. A picked background image is copied to
  app support storage (`terminal/`) and the old copy deleted. Bundled fonts' licenses are registered in `main.dart`.
