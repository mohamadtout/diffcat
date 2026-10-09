# Notifications (on-device polling)

There's no server, webhook or Firebase. The phone itself asks GitHub what's new and posts local notifications.

```
Android WorkManager (every ~15 min, network required)      App opened / resumed (if last check > 10 min)
        │  background isolate: backgroundPollDispatcher           │  Settings → Check now
        └──────────────────────┬────────────────────────────────┘
                               ▼
              pollAndNotify()  (features/notifications/background.dart)
                               ▼
              Poller.run()     (features/notifications/poller.dart)
                 for each watched repo:
                   GET /repos/{o}/{r}/branches            → which heads moved?
                   GET /repos/{o}/{r}/pulls?state=all     → PR lifecycle changes
                   GET /repos/{o}/{r}/compare/{old}...{new}  (only for moved branches)
                 pure diffing in poll_state.dart → GitEvent list
                               ▼
              LocalNotifications.show()  (flutter_local_notifications, channel git_events)
                               ▼
              tap → payload = in-app route → router.go(route)
```

## Behaviour

- **Watch a repo:** tap the bell on the repo screen. This asks for notification permission, schedules the background task, and immediately records a **baseline**. The first check of a repo is silent, so you're only told about activity after you started watching.
- **Latency:** the background check runs about every 15 minutes, which is Android's minimum. Doze and battery saver can stretch that to an hour or more. Opening the app triggers a check if the last one is more than 10 minutes old.
- **Cost:** two API requests per watched repo per check, plus one per branch that moved. The background check keeps
  its ETags on disk (`FileEtagCache`, `<app support>/poll_etags`, cleared on sign-in and sign-out), so a repo with no
  changes answers 304 and costs no rate limit at all. Repos are checked four at a time (iOS allows a background refresh
  about 30 seconds).
- **State:** each repo's branch heads, PR snapshots and last-check time are stored as JSON under `StoreKeys.pollState`. The last result (time, event count, per-repo errors) is under `StoreKeys.lastPoll` and shown in Settings.

| Event | Notification | Tap opens |
|---|---|---|
| Branch moved, 1 new commit | `repo · branch` / `author: message` | the commit |
| Branch moved, several commits | `repo · branch: N new commits` + up to 3 titles | compare view `old...new` |
| Force-push | `repo · branch force-pushed` | the new head commit |
| New branch | `repo · branch` / head commit | that commit |
| PR opened / ready for review / reopened / merged | `repo · PR #N <verb>` / `author: title` | the PR |

**Filtered out:**
- your own commits and PRs (toggle in Settings; merges of your PRs still notify)
- bot authors (`*[bot]`)
- branches reset backwards
- plain PR closes
- draft PRs until they're marked ready
- more than 5 events per repo per check

## Platform notes

- **Android:** `workmanager` periodic task `git-reviewer-poll`, registered with `ExistingPeriodicWorkPolicy.update`, and cancelled when nothing is watched. It survives reboots (WorkManager handles that). Aggressive OEM battery managers (Samsung, Xiaomi…) can delay it further. Setting the app's battery usage to *Unrestricted* helps.
- **iOS:** a `BGAppRefreshTask` with the same identifier, `git-reviewer-poll`. It is listed in Info.plist (`BGTaskSchedulerPermittedIdentifiers`, Background Modes → *fetch* only) and registered in `AppDelegate.swift` before launch finishes, together with the plugin registrant for the headless engine. iOS decides when it runs (typically a few times a day, less if the user rarely opens the app or turns off Background App Refresh), and the app also checks when it opens. To test: run from Xcode, background the app, then *Debug → Simulate Background Fetch*.
- The background isolate reads the token from secure storage and prefs directly (no Riverpod). It always returns success to WorkManager: a failed check simply waits for the next period instead of triggering exponential backoff.

## Testing

`test/features/poller_test.dart` covers branch diffing, PR lifecycle rules, self/bot filtering, the silent baseline, reset-backwards, and the include-own toggle against a mocked `GitHubApi`.

To test on a device: watch a repo, push a commit from another account (or enable *Notify about my own activity*), then tap **Settings → Check now**.
