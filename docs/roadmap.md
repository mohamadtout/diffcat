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

- Sticky file header while scrolling a diff.
- PR "files changed since last review" (track the last-seen head SHA per PR).
- Mark files as viewed (persisted per PR or commit).
- File history that follows renames (GraphQL or the compare API heuristics).
- Android foreground service to keep SSH sessions alive in the background.
- Mosh / Eternal Terminal for flaky mobile networks; jump-host support.
- Share-sheet / github.com link handling (Android App Links, iOS Universal Links), which maps straight onto `Routes`.
- Notification preferences per repo (branches filter, PR-only).
- i18n.

## Instant push notifications (planned, not built)

Notifications within seconds with the app closed, for repos the user or their organizations own: a GitHub App
installed on those repos, a Cloudflare Worker on the free plan and Firebase Cloud Messaging / APNs. Costs, limits,
setup and the app changes are in [instant-push.md](instant-push.md).

