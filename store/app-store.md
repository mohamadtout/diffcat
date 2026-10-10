# App Store listing (iOS and iPadOS)

Everything App Store Connect asks for, ready to paste. Character counts are checked by `store/check_lengths.py`.

## App information

| Field | Value |
|---|---|
| Name (30) | `Diffcat: Code Review for Git` (home-screen name: Diffcat) |
| Subtitle (30) | `Review GitHub code on the go` |
| Bundle ID | `com.mohamadtout.gitReviewer` |
| SKU | `git-reviewer-ios` (any unique string, never shown) |
| Primary category | Developer Tools |
| Secondary category | Productivity |
| Content rights | *Does your app contain, show, or access third-party content?* **Yes**: it shows GitHub content the user opens, through GitHub's public API as GitHub's terms allow. Confirm you have the rights. |
| Copyright | `2026 Mohamad Tout` |
| Price | Free, all territories |
| Privacy Policy URL | `https://github.com/mohamadtout/diffcat/blob/main/PRIVACY.md` |
| Support URL | `https://github.com/mohamadtout/diffcat/issues` |
| Marketing URL (optional) | `https://github.com/mohamadtout/diffcat` |

## Promotional text (170)

```
Read diffs, review pull requests and browse code from your iPhone or iPad. Download repos to read offline, or reach your own machine over SSH. No account needed.
```

## Description (4000)

```
Diffcat turns your iPhone and iPad into a place to read and review code on GitHub. Follow what changed, read the diffs properly and catch problems before you're back at your desk.

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

MADE FOR IPAD
• List and detail side by side
• Hide the list for a full-width diff when you need the space
• Works in every orientation and multitasking size

WORKS OFFLINE
• Download a branch: its latest commits, everything since a commit, or its whole history, with diffs, pull requests (open or closed) and optionally every file
• Save any single pull request, review threads included
• Read it on a plane, a train or a slow connection, and turn on Data saver to spend fewer GitHub requests
• See exactly how much space each repo, branch and commit uses, and delete what you don't need

YOUR OWN MACHINE, OVER SSH
• A real terminal to your laptop or server: run git, tests or lazygit
• Key toolbar (Esc, Tab, Ctrl, arrows) and your own one-tap command buttons
• Key-based login, host-key verification, and a one-tap way to install the app's key on your machine

STAY UP TO DATE
• Watch repos and get notified about new commits and pull requests
• Checked on your device: no servers, no accounts, nothing to configure

PRIVATE BY DESIGN
• No account needed: open any public repository right away
• Sign in with GitHub, or with a token, to see your private repos (optional)
• Your token and SSH keys stay in the Keychain. No analytics, no ads, no tracking.

Diffcat is an independent app. It is not affiliated with or endorsed by GitHub, Inc. or the Git project.
```

## Keywords (100, comma separated, no spaces)

```
diff,pull request,code review,commits,ssh,terminal,developer,repository,offline,lazygit,branch,PR
```

Trademarked names (GitHub, Git) are left out of keywords on purpose: Apple rejects keywords using other companies' marks.

## What's New (first version)

```
First release. Read diffs, review pull requests, browse code, download repos for offline reading and open SSH sessions to your own machine.
```

## Screenshots

*Product Page Information → App Previews and Screenshots.* Folder names match the slots in App Store Connect
(spec: [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)).

| Slot in App Store Connect | Status | Size (portrait) | Files |
|---|---|---|---|
| iPhone with Dynamic Island (medium display) | **Required** | 1206 × 2622 (iPhone 17 Pro) | `store/screenshots/app-store/iphone-dynamic-island-medium/` (8) |
| iPhone with Dynamic Island (large display) | Optional (else scaled from older sizes) | 1320 × 2868 (iPhone 17 Pro Max) | `store/screenshots/app-store/iphone-dynamic-island-large/` (8) |
| iPad 13" display | **Required** (the app runs on iPad) | 2064 × 2752 | `store/screenshots/app-store/ipad-13/` (8) |
| iPhone Duo (inner and outer) | Optional now; required from April 2027 for apps built with the iOS 27.1 SDK | inner 2007 × 2853, outer 1398 × 2034 | none yet, see below |

- Each slot only accepts its own sizes, so a 1320 × 2868 image is rejected in the medium slot.
- Smaller iPhones and iPads are scaled from these. Upload in file-name order: up to three show in search results.
- Every image is a 24-bit PNG with no alpha channel, as Apple requires.
- Each image shows the app in use with a short caption. That follows guideline 2.3.3: most screenshots must show the
  app in use, and marketing text must not crowd out the app.

**iPhone Duo:** leave it empty for now. Diffcat is built with the iOS 26 SDK, so on an iPhone Duo it runs in a
375 × 667 pt compatibility window. Screenshots of a full-screen Duo layout would misrepresent it (guideline 2.3.3).
Duo support and its screenshots need the iOS 27.1 SDK and the iPhone Duo simulator (Xcode 27.1), which run only on
Apple silicon Macs. Before April 2027, either use an Apple silicon Mac (or a hosted macOS runner) to build with the new
SDK and run `make store-screenshots` on the Duo simulator, or keep building with the older SDK for as long as App Store
Connect accepts it.

## Header and search results (optional, iOS 27 and later)

*Product Page Information → Header and Search Results.* New in October 2026, shown on iOS and iPadOS 27 and later,
alongside the screenshots (spec: [Creative assets specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications)).

| Asset | Size | File | Design |
|---|---|---|---|
| Product page header | 3840 × 1646 (21:9) | `store/screenshots/app-store/header-and-search/product-page-header.png` | Icon, name and "Code review in your pocket" in the center, where Apple says focal artwork belongs. The phones at the sides can be cropped without losing anything. |
| Search results | 3840 × 2560 (3:2) | `store/screenshots/app-store/header-and-search/search-results.png` | States what the app does ("Review GitHub code on the go"), then shows the interface, as Apple's guidance suggests. |

Check both with the **Preview** button in App Store Connect before submitting. Apple publishes no exact safe areas, so
confirm nothing important is cut off on iPhone and iPad.

## App Privacy ("nutrition label")

Answer **Data Not Collected**. Apple counts data as *collected* only when it leaves the device in a way the developer
(or a partner) can access beyond serving the request in real time. Diffcat has no server. Requests go straight from
the device to GitHub or to the user's own SSH host. No analytics or ad SDKs are included.

## Age rating

Answer **None / No** to every content question, including *Unrestricted Web Access*, which doesn't apply because the
app is not a web browser. For *User-Generated Content*, answer No: the app can't post anything. Expected rating: **4+**.

## Export compliance

App Store Connect asks this on every build unless Info.plist sets `ITSAppUsesNonExemptEncryption`.

- Does the app use encryption? **Yes**: HTTPS to GitHub, and the SSH protocol for the terminal.
- It uses only standard, published encryption (TLS, SSH) for authentication and to protect data in transit. Nothing
  proprietary is used. Apps like this are normally treated as exempt mass-market software.
- Confirm against Apple's [export compliance overview](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)
  before answering. This is not legal advice. Once you've decided, set `ITSAppUsesNonExemptEncryption` in
  `app/ios/Runner/Info.plist` so the question stops appearing.

## App Review information

**Sign-in required?** No. Leave the demo account fields empty and paste this into *Notes*:

```
No account is needed. On the Repos tab, type a public repository such as flutter/flutter and tap Open to see commits, diffs, files and pull requests.

Optional features:
- Sign in (Settings > Sign in) takes the reviewer's own GitHub personal access token and only adds their private repositories.
- Downloads: open a repo and tap the download icon to save it for offline reading (Settings > Downloads manages them).
- Terminal: SSH to a machine the user owns. It needs the user's own server, so it can't be tried without one. The Terminal tab shows how a host is added.
- Notifications: tap the bell on a repo to watch it. iOS runs the background check (Background App Refresh) a few times a day.

Signed out, GitHub allows 60 requests an hour per network. If that limit is reached, the app says so; signing in raises it to 5,000.

The app has no backend. It talks only to api.github.com and to SSH hosts the user adds.
```

Reviewers often share one network, so the anonymous limit can run out mid-review. To avoid that, create a throwaway
GitHub account, make a **read-only fine-grained token** for it (public repositories, no permissions beyond read), and
paste it in the notes as "Optional token for Settings > Sign in". Revoke it after approval.

Contact info: your name, phone and email (not shown publicly).

## Before you submit

- [ ] Apple Developer Program membership (paid, yearly).
- [ ] Register the bundle ID as an **explicit App ID**. App Store Connect's *New App* dialog only lists explicit App IDs,
  and device builds with automatic signing may use the team's wildcard (`*`) profile instead. Running
  `cd app && flutter build ipa --release` once registers it, together with an App Store provisioning profile. Or add it
  by hand: developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → **+** → App IDs → App →
  Explicit, `com.mohamadtout.gitReviewer`, no extra capabilities. It can take a few minutes to show up.
- [ ] App Store Connect → *Apps* → **+** → New App with the bundle ID above, which must match `PRODUCT_BUNDLE_IDENTIFIER`.
  The app belongs to whichever team you create it in, and that team's name is shown as the seller.
- [ ] Your Team ID in `app/ios/Flutter/Signing.xcconfig` (git-ignored, see SETUP.md § 6).
- [ ] Build with Xcode 26 or later. Apple has required the iOS 26 SDK for uploads since April 28, 2026; Xcode 26.3 is installed.
- [ ] Set `version:` in `app/pubspec.yaml` (`1.0.0+1`). Raise the build number (`+N`) on every upload.
- [ ] `cd app && flutter build ipa --release`, then upload `build/ios/ipa/Diffcat.ipa` with Transporter, or open
  `build/ios/archive/Runner.xcarchive` (Xcode → Organizer) → *Distribute App* → *App Store Connect*.
- [ ] TestFlight on your own iPhone and iPad first, including a background notification check.
- [ ] App icon: the 1024 px marketing icon is already in the asset catalog with no alpha channel.
