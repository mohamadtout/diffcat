# Changelog

Versions follow [Semantic Versioning](https://semver.org): features bump the minor version, fixes the patch. The
number after `+` is the store build number (Android `versionCode`, iOS `CFBundleVersion`) and only ever goes up.
Releases are tagged `vX.Y.Z` on `main` and published as GitHub releases with the signed APKs attached (SETUP.md § 6c).

## Unreleased

- Tablets: the first pull request, commit or run opens beside the list instead of an empty "Select a…" pane (not in
  data saver mode), the repo's sections are tabs, and the console, changed-since and run screens keep a readable
  width. The handle that hides the list is easier to hit.
- Pull request descriptions and review comments are formatted like on GitHub: headings, lists and checklists,
  highlighted code, quotes, tables and links. `#123`, `@user` and commit SHAs are links, and links to pull requests,
  commits and repos open in the app. Template comments (`<!-- … -->`) are hidden.
- Pull requests say whether they're ready to merge: one line under the title on every tab ("Ready to merge · 3
  passed", "Checks failing", "Has conflicts", "Changes requested", "Checks running", "Needs approval"), and a card on
  Overview with the checks (tap for Actions), conflicts with the base branch and approvals. The review bar's "Tap a
  line to comment" shows only on Files.
- Diffs come first: a commit's header is shorter (the body folds to two lines with **More**, the SHA shows once,
  actions sit in one row of chips) and the pull request header is two lines, so code shows on the first screen.
  With a large system font, code grows less than the rest of the app (it has its own size setting), and blame on
  phones shows age and initials so the code keeps the width.
- Phones: the repo screen's top bar keeps the repo's name readable (the branch picker moves to a row below it, and
  notifications, changed-since and offline mode to its menu); repo rows keep the name on the first line. Pull request
  tabs scroll instead of being cut off, the review verdict is a list (no more "Comme/nt" with large text), the
  download sheet's button stays in view, and the inbox filters no longer clip with large text.
- SSH: when a host's key changes, the warning shows the old and new fingerprints in groups of four, in a monospace
  font, so they can be compared, and Cancel is the highlighted choice.
- Empty screens offer the next step: "Show closed" for a repo without open pull requests, "Browse repos" when
  nothing is downloaded, "Back to hosts" for a deleted SSH host. Hitting GitHub's hourly limit says when it resets,
  and signed out offers signing in (5,000 requests an hour instead of 60). The Diffcat cat appears on first run, when
  nothing waits for your review, and when nothing is downloaded.
- Colors: the app's blue is now the brand blue instead of a muted slate, the "Offline" chip is teal instead of pink,
  and CI, pull request and review states keep their colors when you change diff colors. Changed diff lines have a bar
  at their left edge, removed and added lines stand out more in dark mode, and line numbers are easier to read. Text
  fields share one outlined style, and the download sheet's choices show a check like the other selectors. The
  "Trust new key" button's text is readable in dark mode.
- `make design-shots`: screenshots of every screen on demo data (phone light and dark, tablet, large text) in
  `app/build/design/`, for reviewing the UI without a device. No app changes.
- Store screenshots and the README show GitHub Actions (a failed run, its jobs and the Re-run buttons; the run list
  beside it on tablets) and a file's history graph. The App Store gets 10 per device (adding Run workflow and blame),
  Google Play 8. The sparse changed-since and console shots are out.
- Skipped jobs no longer show a "0s" duration.
- `make run DEVICE=<id>` picks the device, like the test targets, and `MODE=profile` or `MODE=release` builds
  in that mode (debug by default). No app changes.
- GitHub Actions: a new **Actions** tab on every repo lists workflow runs (filter by workflow) with their jobs,
  steps and logs. Signed in, you can start a workflow that has a manual trigger, filling in its inputs, and re-run
  or cancel runs. Runs that are still going update on their own while you watch.
- README: screenshots section (phone, plus tablet in a collapsible block). No app changes.
- Smaller APK: GitHub releases have one APK per CPU type (25 MB for nearly every phone) instead of one 73 MB APK
  carrying all three, and release builds leave Dart debug info out (1.6 MB less, on Google Play too). Installs of
  earlier APKs update in place.

## 1.1.3 (build 6), 2026-10-11

- Fix: typing in the terminal with the phone keyboard. Words reach the shell letter by letter, so the cursor follows
  them and Tab completes the word being typed (some keyboards, Samsung's among them, held the word back until a
  space). Backspace works on an empty line (it did nothing on iOS and with some Android keyboards). iOS no longer
  turns `"` and `--` into curly quotes and dashes. Tapping the terminal brings the keyboard back inside programs that
  use the mouse, like lazygit.
- Fix: after new commits on a pull request, comments added to a review started earlier were submitted against the old
  commit (wrong lines, or GitHub refused the review). Until that review is submitted or discarded, comments on the new
  version post right away.
- Fix: editing an SSH host (a mistyped address, say) didn't apply until the app restarted.
- Fix: Undo after hiding repos didn't watch them again.
- Fix: diffs lost their syntax colors when reloaded in place (switching a repo between online and offline).
- Fix: the check for new activity when the app starts was skipped until a minute later.

## 1.1.2 (build 5), 2026-10-10

- Fix: on a landscape 7" tablet the keyboard squeezed the navigation rail until its bottom tab was cut off.

## 1.1.1 (build 4), 2026-10-10

- Sign in with GitHub in every build (Diffcat's OAuth App is now built in), not only builds made with a client ID.
- Data saver (Settings): downloaded repos open from the device. Off (default), lists and pull requests load live
  while downloaded diffs and files still cost no requests, and downloads stand in when GitHub can't be reached.
- Downloads: any number of latest commits, everything since a commit, or the whole history (with a request
  estimate); open or open and closed pull requests with their review threads; a size estimate for all files.
- Download a single pull request, open or closed, from its screen; offline it shows in the PR list and reads fully.
- Diff color profiles: create, rename and delete your own; presets can be deleted and restored with Reset colors.
- Terminal: remove a background image without picking another one.
- Organize the repo list: colored folders, an Archived section, hiding repos or whole accounts, bulk select with
  Undo, and a choice of which repos to load from GitHub at all. Loads up to 1,000 repos.
- Notifications about pull requests that need you now come from your GitHub notifications inbox: review requests,
  mentions and replies, checked about every minute while the app is open.
- The Android APK is attached to each GitHub release, for installing without Google Play.
- Fixes: the palette chips in Code view overflowed with smaller system text; the terminal host's connected icon
  didn't update after leaving with the system back gesture.

## 1.1.0 (build 3), 2026-10-09

- File history graph across branches: forks, rebased/cherry-picked copies, reverts; compare any two versions.
- Terminal customization: color themes, bundled code fonts, gradient or photo backgrounds, git status bar.
- Code view settings: font, full files with changes in place, editable diff colors and palettes.
- Syntax highlighting in diffs and the file viewer, with the exact changed words marked.
- Blame in the file viewer (signed in): who last changed each line, tap to open the commit.
- Sign in with GitHub (OAuth device flow) as an alternative to pasting a token.
- Review pull requests: line comments (pending drafts kept on the device, or posted at once), replies to threads,
  and submitting Comment / Approve / Request changes.
- Inbox tab: pull requests waiting for your review, yours, mentions and assignments, with optional notifications for
  new review requests.
- Security and performance: secrets and offline copies kept out of backups, background checks that cost no rate
  limit when nothing changed, heavy work moved off the UI thread.

## 1.0.1 (build 2)

- Release signing and store screenshot tooling. No app changes.

## 1.0.0 (build 1)

First release: browse and review GitHub repos, commits, diffs and pull requests; file history; changed-since; API
console; SSH terminal with lazygit support; on-device notifications; offline downloads.
