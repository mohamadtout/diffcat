# Design review and redesign plan

A review of Diffcat's UI against [design-brief.md](design-brief.md) (the source of truth), written from the
`make design-shots` screenshots and the code in `app/lib/`. No app code was changed for it.

**Status (2026-10-20).** Implemented on `feature/design-overhaul`, one commit per feature: tokens, state views
and the cat, host-key dialog, phone chrome, diff first, merge readiness, Markdown, tablet panes. What still needs a
device is in [design-overhaul-checklist.md](design-overhaul-checklist.md). Changes from this plan: the review bar
stays on every PR tab (approving from Overview matters) and only its "Tap a line" hint is limited to Files; PR
Overview beside Files and run jobs beside the log are left as follow-ups.

**Evidence.** 220 screenshots, all read one by one: 55 screens in four setups (`phone-light` and `phone-dark` at
393×852, `tablet-light` at 1376×1032, `phone-text150-light` at 393×852 with text at 1.5×), all at pixel ratio 2. They
are not committed; run `make design-shots` and open `app/build/design/<setup>/<screen>.png`. Paths below are written
as `<setup>/<screen>.png`. Dart paths are relative to `app/lib/`.

**Method.** The `impeccable` skill's `teach` (context), `critique` and `audit` steps, adapted to a native Flutter
app:

- *Teach:* the skill's context loader found no `PRODUCT.md` and asks for an interview. The brief already answers
  every question it would ask, so product context was taken from the brief alone and nothing else was invented.
  Platform: `android` (Material 3, Flutter), with iOS planned.
- *Critique:* the native-platform method, "design review only". Its detector, browser overlay, live mode and
  dual sub-agent setup read HTML in a browser and **do not apply to Flutter**, so they were skipped. So were the
  snapshot it saves to `.impeccable/` and its closing questions, because only this file is committed. The questions
  and the owner's answers are in [§ 7](#7-owner-decisions).
- *Audit:* the native audit (`audit.native.md`), scored against the skill's Android reference. Web-only checks in
  the skill (CSS, bundle size, `px` units, hover states, Lighthouse) were skipped: they don't map to Flutter.

**Screenshot artefacts (not app bugs).** Before trusting a finding, rule out these test-only effects:

- **Black outlines** around FABs and the inbox "Get notified" card are `flutter_test` drawing shadows as solid
  outlines (`debugDisableShadows`). Fix it in the tool by setting `debugDisableShadows = false` while capturing.
- **Boxes for some glyphs** (`→`, `⌫`, `▸`): tests have no system font fallback.
- **Initials instead of avatars**: the demo has no `avatar_url`.
- **"0 B" sizes**: the offline store is in memory only.
- **Empty `host-edit.png`**: the shot reached that screen by changing only the URL's query, which a real tap never
  does (see § 6).

---

## 1. The five biggest problems

### 1. The diff is not the hero: page chrome eats the first screen

The brief says reading diffs on a small screen is the core job, yet on a phone the commit header uses 45% of the
first screen before the first diff line. At 1.5× text it uses almost all of it: only 7 code lines show, cut at about
22 columns.

- **What fills the header:** the title, body, author line, SHA chip (the SHA also appears in the app bar title and
  the copy action), file count, line counts, a "parent" chip and two stacked outlined buttons.
- **On a PR:** the header and tabs (title, branch line, counts, tabs, sticky file bar) stay on every tab and take
  about 46% of the screen at 1.5×.
- **Screens:** `phone-light/commit.png`, `phone-text150-light/commit-diff.png`, `phone-text150-light/pull-files.png`,
  `tablet-light/pull-files.png` (about 290 dp of chrome above the code even on a tablet).
- **Code:** `features/commits/commit_screen.dart` (`CommitHeader`, lines 63–130), `features/pulls/pull_screen.dart`
  (`PullView` lines 37–90, `_PullHeader`).

### 2. The PR screen doesn't answer "is this safe to merge?"

That question is the brief's own definition of the job, but the PR screen gives no answer to it:

- It shows no CI checks status, no mergeability (conflicts, behind base) and no requested-changes summary.
- The description is a raw `SelectableText`, so Markdown shows as literal `- ` dashes, with no links or code.
- The review bar says "Tap a line to comment" on the Overview and Commits tabs, which have no lines.
- On a tablet the Overview is one short column on a 1880 dp canvas.

**Screens:** `phone-light/pull-overview.png`, `tablet-light/pull-overview.png`, `phone-text150-light/pull-commits.png`.
**Code:** `features/pulls/pull_screen.dart:305` (the description), lines 76–80 (`ReviewBar` on every tab), and the
missing checks provider in `features/pulls/pulls_providers.dart`.

### 3. The brand barely shows, and colour isn't consistent

- **Washed-out blue:** `ColorScheme.fromSeed` uses its default `tonalSpot` variant, which softens the seed. Primary
  renders as a muted slate blue in light and periwinkle in dark, so #2F81F7 never appears. Every switch, link,
  selected pill and section header carries the muted colour (`phone-light/settings.png`, `phone-dark/settings.png`).
- **Off-brand pink:** the "Offline" chip uses the tertiary container, a pink in light and mauve in dark that reads
  as a second brand (`phone-light/repos.png`, `phone-dark/repos.png`).
- **Weak dark diff:** dark diff row tints (`#12261E` / `#25171C`) sit on the M3 dark surface at roughly 1.1:1, so
  in dark mode, which is the brief's night-use case, removed rows show only through the `-` marker
  (`phone-dark/commit-diff.png`, `phone-dark/settings-code-view.png`).
- **Faint line numbers:** the light gutter colour `#8C959F` is about 3:1 on white.
- **Wrong button text colour:** the "Trust new key" button sets `error` as its background without `onError` as its
  text colour, so in dark it shows navy text on salmon (`phone-dark/dialog-host-key-changed.png`).
- **Status colours borrow diff colours:** PR and CI status icons take the user-editable diff colours
  (`DiffColors.addFg` / `delFg`), so choosing the Colorblind diff preset also recolours "open", "closed",
  "passed" and "failed". The rest are hard-coded: the in-progress amber is `Color(0xFFBF8700)`
  (`actions/run_widgets.dart:10`), merged is `Colors.purple` (`pulls/pulls_tab.dart:115`), and the history lanes
  are 6 literals in `files/history_graph_view.dart`, none of them adjusted for dark mode. The other literals outside
  `core/theme/` are deliberate palettes (diff presets in `diff/diff_colors.dart`, folder colours in
  `repos/repo_library.dart`).

**Code:** `core/theme/app_theme.dart:13` and `:64–82`, `features/offline/offline_chip.dart`,
`features/terminal/host_key_dialog.dart:30`.

### 4. Phone app bars and rows don't fit: names truncate, controls clip at 1.5×

The thing that names the screen loses to its decorations:

- **Repo name:** "payments-api" becomes "paym…" because the ref chip and three icons share the app bar. That happens
  at 1× too on a 360 dp phone (`phone-text150-light/repo-commits.png`). Downloads → repo has the same problem:
  "demo/pay…" (`phone-text150-light/downloads-repo.png`).
- **Repo list:** the pinned repo row puts lock, pin, bell and the Offline chip on the name's line, so the name is
  truncated (`phone-text150-light/repos.png`).
- **Clipped controls:**
  - PR tabs: "Commits (" is cut off (`phone-text150-light/pull-files.png`).
  - Inbox filter chips: cut off with no fade (`phone-light/inbox.png`).
  - Review verdict: wraps as "Comme / nt", and "Request changes" takes two lines even at 1×
    (`phone-text150-light/pull-review-sheet.png`, `phone-light/pull-review-sheet.png`).
- **Blame gutter:** takes 46% of the width at 1.5× (`phone-text150-light/file-blame.png`).
- **Download sheet:** its main button falls below the fold, so you scroll to find it
  (`phone-text150-light/sheet-download.png`).

**Code:** `features/repo/repo_screen.dart:99–160`, `features/repos/repo_tile.dart:56–62`,
`features/pulls/pull_screen.dart:56`, `features/inbox/inbox_screen.dart:79`,
`features/pulls/review_widgets.dart:360`, `features/files/file_view_screen.dart`,
`features/offline/download_button.dart`.

### 5. Tablets get a stretched phone, and empty and error states are dead ends

- **Unused split view:** on a 1376 dp landscape tablet the split view's detail pane usually shows only a grey
  "Select a…" line in 65% of the screen. Nothing is selected by default, even when the list has items
  (`tablet-light/inbox.png`, `tablet-light/repo-commits.png`, `tablet-light/empty-pulls.png`, which shows two
  "nothing here" messages side by side).
- **Full-bleed screens:** PR, run, job log, changed-since and console run edge to edge with no `ReadableWidth` and
  no second pane. The console intro is one ~200-character line; job rows put their chevron 1800 dp from their label
  (`tablet-light/repo-console.png`, `tablet-light/run-failed.png`, `tablet-light/changed-since.png`).
- **Two navigation styles:** repo sections are a centred `SegmentedButton` on tablets but a `NavigationBar` on
  phones, so the same sections use two different controls.
- **Empty states:** `EmptyView` is an icon and one line with no action. The app has five empty and error styles:
  - `EmptyView` (icon and a line)
  - `ErrorView` (icon, a line and Retry)
  - a rich custom error (`error-repo-not-found.png`, the best of them)
  - a bare centred paragraph (`settings-repo-folders.png`)
  - an empty state with an action (`signed-out-inbox.png`)
- **Rate-limit error:** offers only Retry, which can't work until the reset time
  (`tablet-light/error-rate-limited.png`).

**Code:** `core/layout/split_view.dart:79–84` (the placeholder), `core/widgets/async_view.dart` (`EmptyView`,
`ErrorView`), `features/repo/repo_screen.dart:166–190`, `features/repos/repo_list_settings_screen.dart:164`.

---

## 2. Ranked changes (impact vs effort)

Impact: H/M/L for the brief's job (triage diffs one-handed, at night, at any size). Effort: S (≤ 1 day), M (2–4 days),
L (a week or more). Ordered by impact, then by effort.

| # | Change | Impact | Effort |
|---|---|---|---|
| 1 | Diff-first commit and PR layout | H | M |
| 2 | Merge-readiness summary on the PR | H | M |
| 3 | Brand-true colour scheme and status colour tokens | H | S |
| 4 | Stronger dark diff, readable gutter, change marker bar | H | S |
| 5 | Compact app bar that keeps the name | H | S |
| 6 | Code and gutters scale less than UI text | H | S |
| 7 | One empty/error vocabulary with actions | M | S |
| 8 | Fix clipped controls at large text | M | S |
| 9 | Host-key dialog that helps comparison | M | S |
| 10 | Tablet: fill the detail pane, pane PR and run | M | M |
| 11 | One input style, one segmented style | M | S |
| 12 | Repo navigation idiom consistent across sizes | M | M |
| 13 | Render PR/commit Markdown | M | M |
| 14 | Labels for ambiguous app bar icons | L | S |
| 15 | The cat in first run and a few empty states | L | S |

**1. Diff-first commit and PR layout.**

- **What:** turn the commit and PR headers into a compact summary that scrolls away with the content. Keep one line
  pinned: title, +/−, file *n/m*. Move "Changed since this", "Browse at this commit" and "parent" into the app bar
  overflow menu or one row of assist chips. Show the SHA once.
- **Why:** to show code lines in the first viewport at 1.5×. Problem 1.
- **Files:** `commits/commit_screen.dart`, `pulls/pull_screen.dart`, `diff/diff_view.dart`.
- **Flutter / M3 approach:** a `CustomScrollView` with the header as a `SliverToBoxAdapter` and the sticky file bar
  as a pinned `SliverPersistentHeader`. Under `NestedScrollView`, the PR `TabBar` sits in a pinned header and the
  title block collapses (`SliverAppBar.medium` or a custom collapsing header). Use `MenuAnchor` for the overflow.
- **Risk:** the diff view already pans horizontally and has its own sticky bar, so nested scrolling must keep that
  working. Keep every action reachable (48 dp) and covered by `screen_sizes_test.dart`.

**2. Merge-readiness summary on the PR.**

- **What:** a summary card at the top of Overview, and in the pinned header as a single line, showing:
  - checks: ✓ 3 passed, ✕ 1 failed, linking to the run
  - mergeable / conflicts / behind base
  - reviews: approved by…, changes requested by…
  - draft state
- **Why:** problem 2. It is the question the user opens the app to answer.
- **Files:** `pulls/pull_screen.dart`, `pulls/pulls_providers.dart`, `data/github/` (a check-runs endpoint and the
  `mergeable_state` field), `test/support/demo_github.dart`.
- **Flutter / M3 approach:** a `Card.outlined` holding a `ListTile` per signal, each with a status icon from the new
  `StatusColors` (shape plus colour, never colour alone). Put the check-runs fetch in a provider keyed by the head
  SHA.
- **Risk:** new endpoints. Add them to `DemoGitHub`, or the sweep records them as unknown and fails. More requests
  also bring the rate limit closer, so check offline-copy behaviour (does `downloader.dart` save checks?).

**3. Brand-true colour scheme and status colour tokens.**

- **What:**
  - Build the scheme with `dynamicSchemeVariant: DynamicSchemeVariant.fidelity` so primary stays close to #2F81F7.
  - Remap tertiary (the Offline chip) to a neutral, or move the chip to `secondaryContainer`.
  - Add a `StatusColors` `ThemeExtension` (success, failure, warning, merged, neutral, info) for CI and PR states
    and the history graph lanes, so they stop borrowing the user's diff colours and stop using literals.
- **Why:** problem 3. The brief names the seed colour, status colour appears on half the screens, and editing
  diff colours shouldn't recolour CI results.
- **Files:** `core/theme/app_theme.dart`, `offline/offline_chip.dart`, `actions/run_widgets.dart`,
  `pulls/pulls_tab.dart`, `files/history_graph_view.dart`.
- **Flutter / M3 approach:** `ColorScheme.fromSeed(…, dynamicSchemeVariant: …)` (checked in the SDK on this
  machine: `color_scheme.dart:312`), then `ThemeExtension`s for the status colours.
- **Risk:** fidelity can push primary-on-surface below 4.5:1 for text. A unit test must check the contrast pairs,
  and if one fails, switch to `copyWith(primary:…)`. Diff colours stay user-editable (unchanged).

**4. Stronger dark diff, readable gutter, change marker bar.**

- **What:**
  - Raise the dark `addBg` / `delBg` values (see § 3).
  - Darken the light gutter to about 4.5:1.
  - Draw a 3 dp bar in `addFg` / `delFg` at the left edge of changed rows.
- **Why:** night use. The brief requires added and removed lines to stay distinguishable without colour alone, and
  the marker bar and `+`/`-` give a second channel.
- **Files:** `core/theme/app_theme.dart:64–82`, `diff/diff_rows.dart`.
- **Flutter / M3 approach:** a `DecoratedBox` with a left `BorderSide` on the row. These are only default values,
  and the user's edited colours still win.
- **Risk:** users with custom colours keep them. The presets (Colorblind, High contrast…) need the same check.

**5. Compact app bar that keeps the name.**

- **What:** on compact width, the repo app bar shows the name (two lines allowed) and a branch subtitle that opens
  the ref picker. Bell and sync move into the overflow menu, and the ref chip moves into the subtitle. Repo tile
  badges move to the subtitle line.
- **Why:** problem 4.
- **Files:** `repo/repo_screen.dart:99–160`, `repo/ref_picker.dart`, `repos/repo_tile.dart:56–62`,
  `offline/downloads_screen.dart`.
- **Flutter / M3 approach:** `AppBar(title: Column(…))` keeps the top bar small, with at most two action icons on
  compact width plus a `MenuAnchor` overflow (`WindowSize.of`).
- **Risk:** the watch bell becomes one tap further away, so mirror its state in the subtitle (a bell glyph).

**6. Code and gutters scale less than UI text.**

- **What:** clamp the text scaler for code, line numbers and the blame gutter (for example
  `MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15)`), since the code font size is its own user setting.
  Add a compact blame mode for phones: an age bar plus initials instead of "10d lena-k".
- **Why:** at 1.5× the code shows about 22 columns and blame about 13.
- **Files:** `diff/diff_view.dart:394`, `files/file_view_screen.dart:288`, `diff/diff_rows.dart`.
- **Flutter / M3 approach:** `TextScaler.clamp`, plus a `LayoutBuilder` that switches the blame gutter style below a
  width.
- **Risk:** this touches the brief's "works at 2× text" constraint. **Owner decision (§ 7): approved.** Code and
  gutters may grow less than UI text, because code size has its own setting (Settings → Code view). UI text keeps
  full scaling, and the 2× sweep still has to pass.

**7. One empty/error vocabulary with actions.**

- **What:** extend `EmptyView` with an optional `title` and `action`. Add actions where one exists:
  - empty PRs → "Show closed"
  - empty downloads → "Browse repos"
  - host not found → "Back to hosts"
  - rate limit → "Sign in for 5,000/hour", "Open offline copy" and a countdown instead of a bare Retry

  Use the rich layout of `error-repo-not-found.png` as the model, and convert the folders paragraph to `EmptyView`.
- **Why:** problem 5. Each empty screen should offer the obvious next step.
- **Files:** `core/widgets/async_view.dart`, `pulls/pulls_tab.dart`, `offline/downloads_screen.dart`,
  `terminal/terminal_screen.dart:95`, `repos/repo_list_settings_screen.dart:164`.
- **Flutter / M3 approach:** an `EmptyView({icon, title?, message, action?})` that keeps its own `maxWidth` (about
  480) and sits in the top third of the screen, not dead centre.
- **Risk:** none on the constraints. Copy changes are factual only.

**8. Fix clipped controls at large text.**

- **What:**
  - PR `TabBar(isScrollable: true, tabAlignment: TabAlignment.start)`.
  - Inbox chips in a horizontal `ListView` with edge padding, or a `Wrap`.
  - Review verdict as a vertical `RadioListTile` group when it doesn't fit (or always).
  - Download sheet with a sticky bottom action.
  - Host form labels shortened, with helper text instead.
- **Why:** problem 4.
- **Files:** `pulls/pull_screen.dart:56`, `inbox/inbox_screen.dart:79`, `pulls/review_widgets.dart:360`,
  `offline/download_button.dart`, `terminal/host_edit_screen.dart`.
- **Flutter / M3 approach:** a `DraggableScrollableSheet` with the action outside the scroll view, and
  `LayoutBuilder` breakpoints.
- **Risk:** none.

**9. Host-key dialog that helps comparison.**

- **What:**
  - Sentence-case title with the icon at 32 dp.
  - Fingerprints in mono, split into 4-character groups, with Old and New aligned in a two-row table.
  - Cancel as the filled default; "Trust new key" as a text button in `error` colour.
  - Fix the `onError` text colour.
- **Why:** a security prompt shouldn't make the risky choice the emphasised one, and a SHA256 that wraps mid-string
  can't be compared (`phone-text150-light/dialog-host-key-changed.png`).
- **Files:** `terminal/host_key_dialog.dart`.
- **Flutter / M3 approach:** `AlertDialog` with `icon:`; a `Table` or `SelectableText.rich` for the fingerprints;
  `TextButton.styleFrom(foregroundColor: scheme.error)`.
- **Risk:** behaviour must stay identical (true/false result), covered by its existing widget test.

**10. Tablet: fill the detail pane, pane PR and run.**

- **What:**
  - Auto-select the first item in split view (inbox, commits, PRs, runs) when nothing is selected.
  - On expanded width, show PR Overview beside Files, and run jobs beside the selected job's log.
  - Wrap console, changed-since and the run header in `ReadableWidth`.
  - Give the collapse handle a 48 dp hit area.
- **Why:** problem 5, and the brief makes tablets first-class.
- **Files:** `core/layout/split_view.dart`, `inbox/inbox_screen.dart`, `commits/commits_tab.dart`,
  `pulls/pulls_tab.dart`, `actions/actions_tab.dart`, `pulls/pull_screen.dart`, `actions/run_screen.dart`,
  `console/console_tab.dart`, `compare/changed_since_screen.dart`.
- **Flutter / M3 approach:** a `SplitView` with an `initialSelection` callback; nested `SplitView`s for PR and run;
  the handle as a 48 dp-wide `InkWell` that draws a 1 dp divider.
- **Risk:** auto-selecting loads a detail (one more request), so skip it in data-saver mode. Routes stay the same,
  and every pane remains reachable by URL.

**11. One input style, one segmented style.**

- **What:** set the theme so every text field is outlined (today underline and outlined fields mix, sometimes on the
  same form), and `SegmentedButton` uses one `showSelectedIcon` policy app-wide. The download sheet and repo tabs
  turn it off; settings keep it.
- **Why:** consistency, heuristic 4.
- **Files:** `core/theme/app_theme.dart` (`inputDecorationTheme`, `segmentedButtonTheme`),
  `offline/download_button.dart:199,248`, `repo/repo_screen.dart:167`.
- **Flutter / M3 approach:** component themes in `ThemeData` instead of per-widget style.
- **Risk:** none.

**12. Repo navigation idiom consistent across sizes.**

- **What:** on medium and expanded widths, show repo sections as a `TabBar` (secondary tabs) under the app bar
  instead of a `SegmentedButton`. **Owner decision (§ 7): on compact width keep the bottom `NavigationBar`**, which
  is easier to reach on tall phones.
- **Why:** a segmented button is for choosing a value, not for navigation, and phone and tablet use different
  patterns.
- **Files:** `repo/repo_screen.dart:166–190`.
- **Flutter / M3 approach:** `TabBar.secondary`.
- **Risk:** phone and tablet still differ (bottom bar vs top tabs). That is deliberate: each suits how the device is
  held. On phones the global destinations stay one Back away, as today.

**13. Render PR/commit Markdown.**

- **What:** show lists, code spans and blocks, links and headings in PR descriptions, review comments and commit
  bodies.
- **Why:** raw `- ` lists and backticks look unfinished on the screen people read most.
- **Files:** `pulls/pull_screen.dart:305`, `pulls/review_widgets.dart`, `commits/commit_screen.dart`.
- **Flutter / M3 approach (owner decision, § 7):** a package is acceptable, but build our own if it can be leaner
  and better suited than what's published. Phase 5 starts with a short comparison:
  - **Off-the-shelf widget packages:** check their current maintenance status, size and selection support first;
    the Flutter team's `flutter_markdown` was discontinued and has community forks.
  - **Our own renderer:** GitHub-flavoured subset (paragraphs, headings, lists, task lists, code spans and fenced
    blocks, links, emphasis, quotes, tables later) to `TextSpan`s and a few widgets. Pure Dart parsing (on the
    `markdown` parser package or hand-written), code in the user's code font, links through `url_launcher` (already a
    dependency), and text selectable. Unit-tested like `diff_parser.dart`.

  Pick our own if it is smaller and handles GitHub's dialect and selection better, and design its API so it can be
  published as a pub package later (no app imports, its own tests and README in a folder like `packages/`).
- **Risk:** "no new heavy dependencies": a package must stay small, and our own renderer has to cover GitHub's
  dialect well enough that PR descriptions never look worse than plain text.

**14. Labels for ambiguous app bar icons.**

- **What:** give icons that need recall a text label, a clearer icon, or a move into a labelled menu:
  - sync = online/offline
  - doc-plus = "changed since"
  - `open_in_new` = "open by name"
  - person-search = blame
- **Why:** heuristic 6 (recognition over recall).
- **Files:** `repo/repo_screen.dart`, `repos/repos_screen.dart`, `files/file_view_screen.dart`.
- **Flutter / M3 approach:** `MenuAnchor` items with labels, or a `FilledButton.tonalIcon` with a short label
  where space allows.
- **Risk:** none.

**15. The cat in first run and a few empty states.**

- **What (owner decision, § 7: yes, if it doesn't get in the way of work):** use the mascot's monochrome drawing
  (`app/assets/icon/monochrome.svg`) in place of the generic icon in a few calm moments only: the signed-out home and
  first run, "Inbox zero" (nothing waiting for review), and "Nothing downloaded yet". Never on working screens
  (diffs, lists with content, the terminal, dialogs, errors).
- **Why:** the brand is nearly invisible inside the app (problem 3), and the brief's tone is "a bit friendly".
- **Files:** `repos/signed_out_home.dart`, `inbox/inbox_screen.dart`, `offline/downloads_screen.dart`,
  `core/widgets/async_view.dart` (an optional `illustration` on `EmptyView`), `pubspec.yaml` (asset).
- **Flutter / M3 approach:** the PNG (or SVG rasterised at build time, so no new SVG dependency) tinted with
  `ColorFilter.mode(scheme.outline, BlendMode.srcIn)`, at most 96 dp, sharing `EmptyView`'s layout so nothing shifts.
- **Risk:** must stay small and quiet at 320 dp and 2× text; hide it when the screen is short (landscape phone) so
  the message and action stay in view.

---

## 3. Proposed design tokens (changes to `AppTheme`)

This is a proposal: verify each value with the contrast test in phase 1 before shipping.

### Colour

```dart
static ThemeData _build(Brightness b, DiffColors? diff) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed, // #2F81F7
    brightness: b,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity, // keeps primary near the seed
  ).copyWith(
    // Offline/"saved" accents: a calm teal instead of the default pink tertiary.
    tertiary: b == Brightness.light ? const Color(0xFF00696E) : const Color(0xFF4FD8DF),
    tertiaryContainer: b == Brightness.light ? const Color(0xFFC8F4F5) : const Color(0xFF004F53),
    onTertiaryContainer: b == Brightness.light ? const Color(0xFF002022) : const Color(0xFFC8F4F5),
  );
  …
  extensions: [diffColors, StatusColors.of(b)],
}
```

New `StatusColors` extension (replaces `DiffColors` reuse and the literals in `run_widgets.dart`,
`pulls_tab.dart` and the history lanes; always paired with a distinct icon shape):

| Token | Light | Dark | Used for |
|---|---|---|---|
| `success` | `#1A7F37` | `#3FB950` | passed checks, approved, open PR |
| `failure` | `#CF222E` | `#F85149` | failed checks, closed PR, changes requested |
| `warning` | `#9A6700` | `#D29922` | in progress, queued, behind base |
| `merged` | `#8250DF` | `#A371F7` | merged PR |
| `neutral` | `scheme.outline` | `scheme.outline` | skipped, cancelled, draft |

`DiffColors` defaults:

| Slot | Light (now → proposed) | Dark (now → proposed) |
|---|---|---|
| `addBg` | `#E6FFEC` (keep) | `#12261E` → `#1A3A28` |
| `delBg` | `#FFEBE9` (keep) | `#25171C` → `#3D1E24` |
| `gutter` | `#8C959F` → `#6E7781` (≈4.6:1 on white) | `#6E7681` → `#8B949E` |
| new: `marker` width | — | 3 dp left bar in `addFg`/`delFg` on changed rows |

Rules: no `Color(0x…)` outside `core/theme/`, the terminal themes and the user-selectable palettes (diff
presets, folder colours). Status never reads `DiffColors`. Every foreground/background pair must come from
the same role family (`error`/`onError`, …).

### Type scale (Roboto via M3 roles; code in the user's chosen mono)

| Role | Use | Change |
|---|---|---|
| `titleLarge` | app bar titles, sheet and dialog titles | unify: download sheet uses `headlineSmall`, review sheet `titleMedium` |
| `titleMedium` (w600) | commit and PR titles in headers | add weight 600 |
| `titleSmall` (primary) | section headers (`SectionHeader`) | keep |
| `bodyLarge` | list row titles | keep (ListTile default) |
| `bodyMedium` | body copy, descriptions | keep; cap explanatory paragraphs at 2 lines with "More" |
| `bodySmall` / `labelMedium` | metadata (author · time) | keep |
| `labelMedium` + mono | SHA chips, counts, file badges | replace hand-set `fontSize: 12`/`11` in `core/widgets/common.dart` |
| code | diff, file view, logs | user size (default 12.5), text scaler clamped (change 6) |

Never write all-caps titles (the host-key dialog is the only one).

### Spacing (`AppSpace`, multiples of 4)

`xs 4 · s 8 · m 12 · l 16 · xl 24 · xxl 32`. Screen edge padding is `l` (16) everywhere (`actions_tab.dart`'s "Run
workflow" button sits 8 dp from the edge today). List rows use M3 `ListTile` defaults. Sections are `xl` (24) apart.
Empty states start at about 30% of the height, not the centre.

### Shape (radii)

| Token | Value | Use |
|---|---|---|
| `xs` | 4 | status badge, SHA chip (keep) |
| `s` | 8 | code blocks, chips, the "parent" chip |
| `m` | 12 | cards (PR summary, review thread, notify card) |
| `l` | 16 | images, terminal preview |
| `xl` | 28 | sheets and dialogs (M3 default; set via `bottomSheetTheme`/`dialogTheme`) |
| full | stadium | buttons (M3 default) |

### Elevation

Tonal only, as M3 recommends:

- Cards are `Card.filled` (`surfaceContainerHighest`) or `Card.outlined` (`outlineVariant`).
- Sticky bars (file bar, PR header) use `surfaceContainer` with a 1 dp `outlineVariant` bottom edge, not a shadow.
- Bottom sheets keep the drag handle and stay non-modal only where a live preview needs it (text size). Give that
  sheet `surfaceContainerHigh` plus a top `outlineVariant` edge so it doesn't blend into the page
  (`phone-dark/sheet-text-size.png`).

### Component themes to add to `ThemeData`

`inputDecorationTheme` (outlined), `segmentedButtonTheme` (one icon policy),
`tabBarTheme(tabAlignment: TabAlignment.start)`, `bottomSheetTheme(showDragHandle: true, constraints:
BoxConstraints(maxWidth: 640))`, `chipTheme` (radius `s`), `cardTheme` (radius `m`, no shadow) and
`listTileTheme(minVerticalPadding: 8)`.

---

## 4. Phased implementation plan

Each phase is one `feature/<name>` PR off `development`, with a minor version bump (patch for phase 1 if it only
fixes colours), a `+build` bump and a CHANGELOG entry. Every phase ends with `make check`, plus a before-and-after
`make design-shots` pass attached to the PR as a few representative PNGs.

All phases keep `test/widgets/screen_sizes_test.dart` green. Phases that add or change a route add it to the sweep's
`_screens` list and to `tool/design/design_shots_test.dart`.

**Phase 1: `feature/design-tokens`.** Changes 3, 4 and 11, and the host-key colour fix.

- **Code:** `AppTheme` (scheme variant, tertiary remap, component themes), a `StatusColors` extension, `AppSpace`
  and radius constants. Replace the colour literals in `run_widgets.dart`, `pulls_tab.dart` and
  `history_graph_view.dart`. Set new `DiffColors` defaults and draw the marker bar in `diff_rows.dart`.
- **Tests:**
  - `test/core/app_theme_test.dart` (new): contrast pairs for both brightnesses (primary/surface ≥ 4.5:1 for text,
    `onX`/`X` pairs, gutter/surface ≥ 4.5:1, dark `addBg`/`delBg` distinguishable from `surface`).
  - `diff_view_test.dart`: the marker bar is present on changed rows.
  - The sweep stays green.
- **Tool:** set `debugDisableShadows = false` in `design_shots_test.dart` so FAB and card shadows render.
- **Docs:** `conventions.md` (a "Design tokens" section: no colour literals outside `core/theme`, use
  `StatusColors`/`AppSpace`), `decisions.md` (why fidelity, why teal tertiary).

**Phase 2: `feature/state-views`.** Changes 7, 9 and 15.

- **Code:** `EmptyView(title, action)`, a richer `ErrorView` (rate-limit actions and countdown, not-found layout
  shared with the repo screen), each empty state with its action, the folders empty state converted, the host-key
  dialog redesign.
- **Tests:** widget tests for the `EmptyView` action, the rate-limit actions (signed in vs out) and the host-key
  dialog result (true/false unchanged). The sweep stays green. The design-shots "states" pass covers the visuals.
- **Docs:** `features.md` (empty/error behaviour), `conventions.md` (use `EmptyView` with an action when one
  exists).

**Phase 3: `feature/compact-chrome`.** Changes 5, 8 and 14.

- **Code:** the repo app bar (name, branch subtitle, overflow), the repo tile badge row, a scrollable PR `TabBar`,
  inbox chips, the review verdict layout, a sticky action on the download sheet, host form labels, labelled menu
  items.
- **Tests:**
  - A new widget test: at 360×640 and 393×852 @1.5×, the repo title `Text` doesn't overflow (`TextPainter` with
    the screen's `textScaler`, `didExceedMaxLines == false`), and every PR tab is reachable.
  - The sweep stays green: it already runs 1.5× and 2×, and catches overflow but not truncation, which is why the
    new test exists.
- **Docs:** `features.md` (where the watch bell and online/offline toggle now live).

**Phase 4: `feature/diff-first`.** Changes 1 and 6.

- **Code:** commit and PR screens as slivers (collapsing header, pinned file bar), the SHA shown once, secondary
  actions in the overflow menu, `TextScaler.clamp` for code and gutters, compact blame on narrow widths.
- **Tests:**
  - A widget test: on 393×852 @1.5×, at least 15 diff lines are visible on first load of
    `Routes.commit(…, file:)`.
  - `blame_test.dart`: the compact gutter below the width threshold.
  - `diff_view_test.dart`: the sticky file bar still pins.
  - The sweep stays green.
- **Docs:** `features.md` (diff screen layout), `decisions.md` (the code-text clamp and why it respects the 2× rule),
  `architecture.md` only if a widget moves layer.
- **Owner decision:** the text clamp is approved (§ 7).

**Phase 5: `feature/pr-merge-readiness`.** Changes 2 and 13.

- **Code:** a check-runs/status endpoint in `data/github/` (keyed by the head SHA), the `mergeable_state` field, a
  merge-readiness card and a header line, Markdown rendering (package or our own renderer, chosen by the comparison in
  change 13), and `ReviewBar` only on the Files tab.
- **Tests:**
  - Unit tests for the checks summary model and the Markdown renderer (`test/features/…`).
  - A `GitHubClient` scripted-adapter test for the new endpoint.
  - `DemoGitHub` gains the check-runs route (or the sweep fails on unknown calls).
  - `review_test.dart`: the bar only shows on Files.
- **Docs:** `architecture.md` (the new endpoint), `features.md`, `decisions.md` (package vs own renderer, with the
  comparison), `docs/notifications.md` if the poller ever uses checks (it shouldn't in this phase), and
  `offline/downloader.dart` docs if offline copies save checks. If the Markdown phase grows, split it into its own
  `feature/markdown` PR.

**Phase 6: `feature/tablet-panes`.** Changes 10 and 12.

- **Code:** a `SplitView` `initialSelection`, auto-select in inbox, commits, PRs and runs (skipped in data-saver
  mode), PR Overview beside Files and run jobs beside the log on expanded width, `ReadableWidth` on console,
  changed-since and the run header, a 48 dp collapse handle, repo sections as `TabBar.secondary` on medium and wider
  (phones keep the bottom `NavigationBar`).
- **Tests:**
  - `split_view_test.dart`: initial selection and the 48 dp handle hit area.
  - `screen_sizes_test.dart`: add any new pane routes. It already covers foldable, tablet and desktop.
  - A widget test: on 1376×1032 the inbox detail shows the first PR without a tap.
- **Docs:** `architecture.md` (routing table if pane URLs change; every pane must stay reachable by a route),
  `features.md`, `roadmap.md` (iPad multi-pane notes).

---

## 5. What screenshots can't show

- **Touch:** whether hit areas feel right (rows, the 20 dp split handle, terminal key bar), ripple, haptics,
  long-press discoverability (folders rely on it), and drag-to-reorder in Command buttons.
- **Motion:** split-view collapse (200 ms ease-out), sheet and dialog transitions, tab changes, predictive Back,
  the in-progress run updating live, and whether any motion respects the system "remove animations" setting.
- **Real-device rendering:**
  - The platform monospace (`monospace` / `Menlo`); the shots use Source Code Pro in its place.
  - Glyph fallback (`→`, `⌫`, `▸` show as boxes here).
  - Real avatars (the demo has none, so every row shows an initial).
  - OLED blacks and dark-diff visibility on a real panel at night brightness.
  - Status bar, cutout and IME insets (no keyboard in any shot).
  - Material You dynamic colour, if ever enabled.
- **Things to confirm on a device:**
  - The terminal's "folder unknown" status bar appears to overlap the first terminal line at 1.5×
    (`phone-text150-light/terminal-session.png`).
  - A file or host-edit screen keeps its old state when only the URL query changes: `?blame=1` on an open file
    (`file_view_screen.dart:73` reads it only once) and `/terminal/edit?id=` (`host-edit.png` is empty here). Real
    taps always push a new page, but deep links from notifications might not.
- **Screen readers and keyboards:** TalkBack/VoiceOver labels and reading order, focus order, and hardware-keyboard
  shortcuts on tablets.
- **Performance:** scrolling long diffs and logs, startup, and jank at 120 Hz.
- **iOS:** none of the shots is iOS; edge-swipe Back and safe areas need the iOS build.

---

## 6. Critique and audit scores

### Critique (`impeccable critique`, native method: design review only, detector not applicable)

**Design specificity.** Mostly category-default Material 3. With the name hidden, most screens could belong to any
GitHub client. The authored moments show what the app can be:

- the file history lane graph (`file-history.png`)
- the terminal appearance live preview with font chips set in their own fonts (`settings-terminal.png`)
- the Code view settings live diff preview
- the repo-not-found explanation

The brand is nearly absent: no cat outside the launcher icon, and the seed blue is desaturated away (problem 3).

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of system status | 3 | Run states are clear; online/offline shows only as an icon swap (download ↔ sync) |
| 2 | Match system / real world | 3 | Right vocabulary for developers; raw Markdown in PRs |
| 3 | User control and freedom | 3 | Back and undo for hide work; one-tap delete icons in Command buttons (undo not visible) |
| 4 | Consistency and standards | 2 | Mixed input styles, segmented icon policy, sheet titles, 5 empty/error styles, two repo nav idioms |
| 5 | Error prevention | 2 | Host-key dialog emphasises the risky action |
| 6 | Recognition rather than recall | 2 | Unlabeled sync, doc-plus, `open_in_new`, person-search icons |
| 7 | Flexibility and efficiency | 3 | Custom command buttons, console, presets, key bar; no tablet keyboard shortcuts seen |
| 8 | Aesthetic and minimalist design | 2 | Header chrome over the diff, badge clusters, SHA and path repeated |
| 9 | Error recovery | 3 | Repo-not-found is excellent; rate-limit offers only Retry |
| 10 | Help and documentation | 3 | Inline explanations everywhere, sometimes 4–5 lines long |
| **Total** | | **26/40** | **Acceptable** |

**Cognitive load:** 3 of 8 checks fail (moderate):

- **Visual hierarchy:** the header outweighs the diff.
- **Single focus:** the repo app bar has 5 competing controls.
- **Minimal choices:** the commit header offers 5 actions at once.

**Personas:**

- **Casey (one-handed, interrupted, the brief's main user):**
  - The repo name is truncated, so it's hard to tell where you are after switching apps.
  - The review button is at the bottom (good), but Save on the host form is top-right.
  - On a 1.5× phone the download sheet's button needs a scroll.
- **Sam (accessibility):**
  - The line-number gutter is about 3:1.
  - The branch picker marks the current ref by colour only.
  - The split handle's hit area is 20 dp.
  - Fingerprints wrap mid-string.
  - The review verdict breaks mid-word at 1.5×.
- **Alex (power user):** good accelerators (console, command buttons, key bar), but the commit's secondary actions
  take space on every visit instead of living in a menu.
- **Night triager (from the brief):** dark is mostly first-class, but removed lines nearly vanish in the dark diff,
  and the terminal background and app surface differ by a visible seam (`phone-dark/terminal-session.png`).

### Audit (`impeccable audit`, native)

| # | Dimension | Score | Key finding |
|---|---|---|---|
| 1 | Accessibility | 2 | Gutter contrast, colour-only selection in the ref picker, 20 dp split handle, large-text truncation |
| 2 | Performance | n/a | Not judged from screenshots (§ 5) |
| 3 | Appearance and theming | 2 | Tokens exist (`DiffColors`, scheme roles) but status colours reuse diff colours or literals; brand variant; on-colour pairing bug |
| 4 | Platform conformance | 3 | Real M3 components, NavigationBar/Rail by width; segmented button used as navigation on tablets, all-caps dialog title |
| 5 | Adaptivity | 2 | Rail, `ReadableWidth` and `SplitView` are in place, but empty detail panes and full-bleed tablet screens remain |
| **Total** | | **9/16** (56%) | **Acceptable** (scored without performance) |

**Platform verdict: pass.** It reads as a native Material app, not a ported website.

**What's working, and should be kept:**

- Real M3 components throughout.
- Responsive scaffolding that already exists (`WindowSize`, `SplitView`, `ReadableWidth`, rail ↔ bar).
- `+`/`−` markers so diffs don't rely on colour alone.
- User-editable diff colours with Colorblind and High contrast presets.
- Live previews in settings.
- The repo-not-found error.
- Sheets capped at about 640 dp on tablets.
- Primary actions at the bottom of sheets.

---

## 7. Owner decisions

Asked in the first version of this review; answered by the owner on 2026-10-20.

1. **Code text scaling (change 6):** approved. Code, line numbers and the blame gutter may grow less than UI text
   (clamped system text scale); code size stays its own setting.
2. **Repo navigation (change 12):** keep the bottom `NavigationBar` for repo sections on phones; it's better for
   reach, especially on tall phones. Tablets and wider get secondary top tabs instead of the segmented button.
3. **Markdown (change 13):** a package is fine, but if a hand-made renderer can be leaner and better suited, build it,
   with an API that could later be published as a pub package.
4. **Brand presence (change 15):** yes, the cat may appear where it makes sense and doesn't disturb the work-focused
   layout: first run and a few empty states, never on working screens.
