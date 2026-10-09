# Roadmap

## iOS / iPadOS

The `ios/` platform folder is already scaffolded, and all UI is responsive (bottom bar → rail → split view). Remaining work:

*Status (2026-10-08): runs on a physical iPad (iOS 18). Signing is set up (Team ID in the git-ignored
`ios/Flutter/Signing.xcconfig`), the on-device smoke test passes, and background checks are wired (BGAppRefreshTask
`git-reviewer-poll`, see [notifications.md](notifications.md)). Still to verify on a device: a background check actually
firing (Xcode → Debug → Simulate Background Fetch).*

1. **Keyboard:** verify the terminal toolbar with the iPad hardware keyboard (xterm handles hardware keys, and Ctrl/Alt latches are only needed on soft keyboards).
2. **iPad polish:** `UIRequiresFullScreen` = false for Split View/Slide Over, test multitasking sizes (compact ↔ expanded switches live), and pointer hover effects.
3. **Background SSH:** iOS suspends sockets in the background, so expect reconnects (the app shows `[session closed]` and a Reconnect button).

## Backlog

- Syntax highlighting in diffs and the file viewer (e.g. `re_highlight`), plus word-level intra-line diff.
- Sticky file header while scrolling a diff.
- Review actions: approve / request changes / comment on lines (GitHub review API).
- PR "files changed since last review" (track the last-seen head SHA per PR).
- Mark files as viewed (persisted per PR or commit).
- Blame view (GraphQL `blame`), and history that follows renames (GraphQL or the compare API heuristics).
- Android foreground service to keep SSH sessions alive in the background.
- OAuth device-flow sign-in (no PAT copy-paste).
- Mosh / Eternal Terminal for flaky mobile networks; jump-host support.
- Share-sheet / github.com link handling (Android App Links, iOS Universal Links), which maps straight onto `Routes`.
- Notification preferences per repo (branches filter, PR-only).
- i18n.
