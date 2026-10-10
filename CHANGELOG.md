# Changelog

Versions follow [Semantic Versioning](https://semver.org): features bump the minor version, fixes the patch. The
number after `+` is the store build number (Android `versionCode`, iOS `CFBundleVersion`) and only ever goes up.
Releases are tagged `vX.Y.Z` on `main`.

## 1.1.1 (build 4, unreleased, on `development`)

- Sign in with GitHub in every build (Diffcat's OAuth App is now built in), not only builds made with a client ID.
- Data saver (Settings): downloaded repos open from the device. Off (default), lists and pull requests load live
  while downloaded diffs and files still cost no requests, and downloads stand in when GitHub can't be reached.
- Downloads: any number of latest commits, everything since a commit, or the whole history (with a request
  estimate); open or open and closed pull requests with their review threads; a size estimate for all files.
- Download a single pull request, open or closed, from its screen; offline it shows in the PR list and reads fully.
- Diff color profiles: create, rename and delete your own; presets can be deleted and restored with Reset colors.
- Terminal: remove a background image without picking another one.
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
