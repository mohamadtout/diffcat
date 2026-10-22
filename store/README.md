# Store listings

Everything needed to publish Diffcat on the App Store, Google Play and GitHub Marketplace.

| File | What |
|---|---|
| [app-store.md](app-store.md) | App Store Connect fields, privacy answers, age rating, export compliance, review notes, checklist |
| [google-play.md](google-play.md) | Play Console fields, data safety, content rating, graphics, closed-test rule, checklist |
| [github-marketplace.md](github-marketplace.md) | GitHub Marketplace listing for the OAuth App: copy, URLs, images, free plan, webhook; images from [github_marketplace_assets.py](github_marketplace_assets.py) |
| [../PRIVACY.md](../PRIVACY.md) | Privacy policy, public at https://github.com/mohamadtout/diffcat/blob/main/PRIVACY.md |
| `screenshots/` | Captioned screenshots per store and device size, plus the Play feature graphic and 512 px icon. Git-ignored (regenerate them as below), except `google-play/phone/` and `google-play/tablet-10/`, which the main README shows: commit those again after regenerating. |
| [check_lengths.py](check_lengths.py) | Checks the listing text against each store's character limits |

## Screenshots

Every screenshot is the real app running on **demo data**: a made-up `demo/payments-api` project with fictional
people, served by a fake GitHub (`app/test/support/demo_github.dart`). No real account, token or host appears.

```bash
make store-screenshots                                   # all six devices below, one at a time → app/build/store/raw/<folder>/
make store-screenshots DEVICES="android-phone=Shots_Phone,ipad-13=iPad Pro 13-inch (M5)"   # just these
make store-screenshot DEVICE=<id> NAME=<folder>          # one device that is already running
make store-frames                                        # captions + device frame → store/screenshots/
```

`DEVICES` is a comma-separated list of `NAME=target`, where `NAME` is a folder from the table below and `target` is an
Android AVD name, an iOS simulator name or UDID, or the id of a connected device. [take_screenshots.sh](take_screenshots.sh)
goes through them **sequentially**: it boots the emulator or simulator, shoots, and shuts it down before the next one
starts (several Android emulators at once exhaust memory). A failed device is reported at the end and doesn't stop the rest.

Folder names the frame tool expects, and the devices that produce the right sizes:

| NAME | Device | Raw size | Framed output |
|---|---|---|---|
| `iphone-6.3` | iPhone 17 Pro simulator | 1206 × 2622 | App Store *iPhone with Dynamic Island (medium)*, required; also used for the header and search-results artwork |
| `iphone-6.9` | iPhone 17 Pro Max simulator | 1320 × 2868 | App Store *iPhone with Dynamic Island (large)*, optional |
| `ipad-13` | iPad Pro 13-inch (M5) simulator | 2064 × 2752 | App Store 13", same size |
| `android-phone` | Pixel 8 emulator (`Shots_Phone`) | 1080 × 2400 | Play phone, 1080 × 1920 |
| `android-tablet-7` | Medium tablet emulator (`Shots_Tablet7`) | 1200 × 1920 | Play 7", same size |
| `android-tablet-10` | Pixel Tablet emulator (`Shots_Tablet10`) | 1600 × 2560 | Play 10", same size |

- **Android tablets are shot in landscape** (in portrait they're narrower than the 840dp split view); the script sets
  the rotation itself. By hand: `adb -s <id> shell settings put system accelerometer_rotation 0 && adb -s <id> shell settings put system user_rotation 1`.
- **Emulators start with `-gpu host`**, which the script does. With less than about 5 GB of free memory the emulator
  otherwise falls back to software rendering, and the app dies mid-run ("Service has disappeared").

The captions and each store's pick live in `app/tool/store/frame_test.dart`. The App Store takes up to 10 screenshots
per device and Google Play up to 8, so the App Store gets two more:

| # | iPhone (App Store) | Android phone (Play) | iPad (App Store) | Android tablets (Play) |
|---|---|---|---|---|
| 1 | All your repos, your way | All your repos, your way | Commits and diffs, side by side | Commits and diffs, side by side |
| 2 | Diffs made for small screens | Diffs made for small screens | Go full width | Go full width |
| 3 | Review pull requests anywhere | Review pull requests anywhere | Review pull requests anywhere | Review pull requests anywhere |
| 4 | Keep CI moving | Keep CI moving | Keep CI moving | Keep CI moving |
| 5 | Deploy from anywhere | Every change to a file, across branches | Deploy from anywhere | Every change to a file, across branches |
| 6 | Every change to a file, across branches | Download once, read offline | Every change to a file, across branches | Download once, read offline |
| 7 | Who changed what, and when | Your own machine, over SSH | Who changed what, and when | Your own machine, over SSH |
| 8 | Download once, read offline | Easy on the eyes at night | Download once, read offline | Easy on the eyes at night |
| 9 | Your own machine, over SSH | | Your own machine, over SSH | |
| 10 | Easy on the eyes at night | | Easy on the eyes at night | |

The first three carry the core (browse, read diffs, review), since search results show only those. The raw run also
has the commit list, file view, changed-since, downloads, console, settings and inbox (`app/build/store/raw/`), so a
pick can change in `frame_test.dart` without retaking anything.

## Name and trademarks

- **Name:** the app is **Diffcat**. In both stores it's listed as **"Diffcat: Code Review for Git"**, the form the
  [Git trademark policy](https://git-scm.com/about/trademark) allows for third-party tools ("[Product Name] for
  Git"). The home-screen name is just "Diffcat". The project was first called "Git Reviewer", which the policy doesn't
  allow, so that name is retired. The Dart package (`git_reviewer`) and the reserved app IDs (`com.mohamadtout.*`)
  keep their old spelling: users never see them, and app IDs can't change after the first upload.
- **"GitHub"** appears only to describe what the app works with, never in the name or icon, and the descriptions end
  with a not-affiliated line. The cat in the icon is our own drawing, not the Octocat.
- App Store names are unique across the store. If the name is taken, App Store Connect says so when you create the
  app record.

## Accounts and costs

| | Apple | Google |
|---|---|---|
| Account | Apple Developer Program (yearly fee) | Play Console (one-time fee) |
| First release | TestFlight, then App Review (often 1–2 days) | New personal accounts: 12 testers in a closed test for 14 straight days, then production review |
| Build | `flutter build ipa` with Xcode 26+ | `flutter build appbundle`, signed with your upload key |
