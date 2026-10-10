# Privacy Policy

*Diffcat · Last updated: October 10, 2026*

Diffcat is a mobile app for reading code changes on GitHub. It has no server, no account system of its own, no
analytics, no advertising and no tracking. The developer of Diffcat does not collect, receive, store, sell or share
any of your data.

## What the app stores, and where

Everything the app keeps stays on your device:

- **Your GitHub token**, if you choose to sign in. It is kept in the system's secure storage (Keychain on iOS and
  iPadOS, Keystore-backed encrypted storage on Android). Signing in is optional.
- **SSH host details and keys or passwords** you add for the terminal. Keys and passwords are in secure storage, and
  host names and user names are in app preferences.
- **Preferences**, such as theme, text size, pinned and recently opened repositories, watched repositories and
  command buttons.
- **A terminal background picture**, if you choose one. The app copies it into its own storage; it never leaves
  the device. Only the picture you pick is read, not your photo library.
- **Offline copies** of repositories you choose to download. These are saved responses from the GitHub API. You can
  see their size and delete them in Settings → Downloads.

None of it is included in device backups (Android backups are turned off for the app; on iOS, secrets and offline
copies are excluded from iCloud backup). Uninstalling the app deletes all of it. Signing out deletes the token.

## Who the app talks to

- **GitHub** (`api.github.com`), to load the repositories, commits, pull requests and files you open, and to check
  repositories you choose to watch for notifications. If you are signed in, requests carry your token. GitHub handles
  this traffic under its own privacy statement: <https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement>.
  If you use **Sign in with GitHub**, the app also asks `github.com` for a sign-in code and, once you approve it on
  GitHub's website, for your token. Nothing else is sent; the app never sees your GitHub password.
- **SSH servers you add yourself**, only when you open a terminal session to them. To show the git branch in the
  terminal's status bar, the app runs `git status` on that server over the same SSH connection.

All connections are encrypted (HTTPS and SSH). The app makes no other network requests.

## Notifications

Notifications about new commits and pull requests are produced on your device by a periodic check against GitHub.
No push service or server is involved.

## Children

The app is a developer tool, is not directed at children, and collects no personal information from anyone.

## Changes

If this policy changes, the new version will be published at this address with a new date.

## Contact

Questions about this policy: open an issue in the app's source repository, or use the contact address on its store page.
