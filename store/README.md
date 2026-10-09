# Store listings

Everything needed to publish Diffcat on the App Store and Google Play.

| File | What |
|---|---|
| [app-store.md](app-store.md) | App Store Connect fields, privacy answers, age rating, export compliance, review notes, checklist |
| [google-play.md](google-play.md) | Play Console fields, data safety, content rating, graphics, closed-test rule, checklist |
| [../PRIVACY.md](../PRIVACY.md) | Privacy policy, public at https://github.com/mohamadtout/diffcat/blob/main/PRIVACY.md |
| `screenshots/` | Captioned screenshots per store and device size, plus the Play feature graphic and 512 px icon. Git-ignored: regenerate them as below. |
| [check_lengths.py](check_lengths.py) | Checks the listing text against each store's character limits |

## Screenshots

Every screenshot is the real app running on **demo data**: a made-up `demo/payments-api` project with fictional
people, served by a fake GitHub (`app/test/support/demo_github.dart`). No real account, token or host appears.

```bash
make store-screenshots DEVICE=<simulator or emulator id> NAME=<folder>   # raw shots → app/build/store/raw/<folder>/
make store-frames                                                         # captions + device frame → store/screenshots/
```

Folder names the frame tool expects, and the devices that produce the right sizes:

| NAME | Device | Raw size | Framed output |
|---|---|---|---|
| `iphone-6.3` | iPhone 17 Pro simulator | 1206 × 2622 | App Store *iPhone with Dynamic Island (medium)*, required; also used for the header and search-results artwork |
| `iphone-6.9` | iPhone 17 Pro Max simulator | 1320 × 2868 | App Store *iPhone with Dynamic Island (large)*, optional |
| `ipad-13` | iPad Pro 13-inch (M5) simulator | 2064 × 2752 | App Store 13", same size |
| `android-phone` | Pixel 8 emulator (`Shots_Phone`) | 1080 × 2400 | Play phone, 1080 × 1920 |
| `android-tablet-7` | Medium tablet emulator (`Shots_Tablet7`) | 1200 × 1920 | Play 7", same size |
| `android-tablet-10` | Pixel Tablet emulator (`Shots_Tablet10`) | 1600 × 2560 | Play 10", same size |

The captions live in `app/tool/store/frame_test.dart`:

| # | Phone | Tablet |
|---|---|---|
| 1 | All your repos, in your pocket | Commits and diffs, side by side |
| 2 | Diffs made for small screens | Go full width |
| 3 | Review pull requests anywhere | Review pull requests anywhere |
| 4 | Download once, read offline | Browse code at any branch or tag |
| 5 | Your own machine, over SSH | Download once, read offline |
| 6 | Everything since the last release | Your own machine, over SSH |
| 7 | Git commands, no clone needed | Everything since the last release |
| 8 | Easy on the eyes at night | Easy on the eyes at night |

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
