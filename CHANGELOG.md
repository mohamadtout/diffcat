# Changelog

Versions follow [Semantic Versioning](https://semver.org): features bump the minor version, fixes the patch. The
number after `+` is the store build number (Android `versionCode`, iOS `CFBundleVersion`) and only ever goes up.
Releases are tagged `vX.Y.Z` on `main`.

## Unreleased

Nothing yet. Add changes here as they land on `development`.

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
