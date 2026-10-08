# Google Play listing (Android phones and tablets)

Everything Play Console asks for, ready to paste. Character counts are checked by `store/check_lengths.py`.

## Main store listing

| Field | Value |
|---|---|
| App name (30) | `Diffcat: Code Review for Git` (home-screen name: Diffcat) |
| Package name | `com.mohamadtout.git_reviewer` |
| Category | Tools (or Productivity) |
| Tags | Developer tools, Productivity |
| Contact email | Required and public: use an address you're happy to publish |
| Website (optional) | `https://github.com/mohamadtout/diffcat` |
| Privacy policy URL | `https://github.com/mohamadtout/diffcat/blob/main/PRIVACY.md` |
| Price | Free (this can't be changed to paid later) |
| Ads | **No ads** |

## Short description (80)

```
Review GitHub commits, diffs and pull requests on the go. Works offline too.
```

## Full description (4000)

```
Diffcat turns your phone or tablet into a place to read and review code on GitHub. Follow what changed, read the diffs properly and catch problems before you're back at your desk.

READ CHANGES COMFORTABLY
• Diffs built for small screens: line numbers, wrapped or scrolling lines, collapse files, jump between them
• Commit history for any branch or tag
• "Changed since…": every file that changed since a release, tag or commit, then its diffs
• File history: every commit that touched a file

REVIEW PULL REQUESTS
• Overview, changed files and commits for every pull request
• See what's open, merged or closed at a glance

BROWSE CODE
• Folder tree with path search
• File viewer with line numbers and image preview
• Browse the repo exactly as it was at any commit

MADE FOR TABLETS AND FOLDABLES
• List and detail side by side
• Hide the list for a full-width diff when you need the space

WORKS OFFLINE
• Download a branch with its recent commits, diffs and open pull requests, or every file
• Read it on a plane, a train or a slow connection
• See exactly how much space each repo, branch and commit uses, and delete what you don't need

YOUR OWN MACHINE, OVER SSH
• A real terminal to your laptop or server: run git, tests or lazygit
• Key toolbar (Esc, Tab, Ctrl, arrows) and your own one-tap command buttons
• Key-based login, host-key verification, and a one-tap way to install the app's key on your machine

STAY UP TO DATE
• Watch repos and get notified about new commits and pull requests
• Checked on your device in the background: no servers, nothing to configure

PRIVATE BY DESIGN
• No account needed: open any public repository right away
• Sign in with a GitHub token to see your private repos (optional)
• Your token and SSH keys stay in Android's secure storage. No analytics, no ads, no tracking.

Diffcat is an independent app. It is not affiliated with or endorsed by GitHub, Inc. or the Git project.
```

## Graphics

| Asset | Requirement | File |
|---|---|---|
| App icon | 512 × 512 PNG, up to 1 MB | `store/screenshots/google-play/icon-512.png` |
| Feature graphic | 1024 × 500 PNG/JPEG, required | `store/screenshots/google-play/feature-graphic.png` |
| Phone screenshots | 2–8, 9:16, at least 1080 px for promotion | `store/screenshots/google-play/phone/` (8, 1080 × 1920) |
| 7" tablet screenshots | Up to 8, needed to be featured for tablets | `store/screenshots/google-play/tablet-7/` (1200 × 1920) |
| 10" tablet screenshots | Up to 8, needed to be featured for tablets | `store/screenshots/google-play/tablet-10/` (1600 × 2560) |

Screenshots must stay within a 2:1 aspect ratio, so the raw emulator shots (1080 × 2400) can't be uploaded as they
are. The framed ones are 9:16.

## App content (Policy → App content)

- **Privacy policy:** the URL above.
- **Ads:** No.
- **App access:** *All functionality is available without special access.* Add a note: "Sign-in is optional
  (GitHub token). SSH needs the user's own server." Play's reviewers hit the same 60 requests/hour anonymous GitHub
  limit, so optionally add a read-only token from a throwaway GitHub account here too (see app-store.md).
- **Content rating (IARC questionnaire):** category *Utility, Productivity, Communication, or Other*. Answer No to
  violence, sexuality, language, controlled substances, gambling and user interaction or sharing (the app can't post or
  chat). Expected rating: Everyone / PEGI 3.
- **Target audience:** 18 and over (a developer tool, not designed for children). It isn't a family app.
- **News app:** No. **COVID-19 tracing:** No. **Government app:** No. **Financial features:** None. **Health:** None.

### Data safety form

- *Does your app collect or share any of the required user data types?* **No.**
  - There is no developer server or SDK that receives data. Requests go from the device straight to GitHub, or to SSH
    hosts the user adds, at the user's request. Credentials stay in on-device secure storage.
- *Is all user data encrypted in transit?* **Yes** (HTTPS, SSH).
- *Do you provide a way for users to request that their data be deleted?* Nothing is held off the device.
  Uninstalling, signing out or Settings → Downloads → delete removes it.

Result on the store page: "No data collected · No data shared with third parties".

## Permissions shown to users

- `INTERNET`: GitHub API and SSH.
- `POST_NOTIFICATIONS`: notifications for watched repos. It is requested only when you watch a repo.

No sensitive permissions (location, contacts, storage, exact alarms, foreground service) are used, so no permission
declarations are needed.

## Release

- [ ] Play Console developer account (one-time fee).
- [ ] **New personal accounts** (created after Nov 13, 2023) must run a **closed test with at least 12 testers opted
  in for 14 days in a row** before production access is granted. Start it early. Organization accounts are exempt.
- [ ] Upload key: create one, set up `app/android/key.properties` (SETUP.md § 5) and enroll in Play App Signing.
- [ ] Target API: Flutter 3.47 targets API 36, which meets the requirement for new apps and updates from Aug 31, 2026.
- [ ] Set `version:` in `app/pubspec.yaml`. The build number (`+N`) must increase with every upload.
- [ ] `cd app && flutter build appbundle --release`, then upload `build/app/outputs/bundle/release/app-release.aab`.
- [ ] Internal testing on your own devices, then the closed test, then production.
