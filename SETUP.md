# Setup: steps only you can do

The app needs no server, no cloud project and no account: public repos work right away. Everything below is optional.

| # | Step | Needed for | Time |
|---|---|---|---|
| 1 | [GitHub token](#1-github-token) *(optional)* | your repo list, private repos, higher rate limit | 3 min |
| 2 | [Run the app](#2-run-the-app) | — | 2 min |
| 3 | [Notifications](#3-notifications) | new-commit / PR alerts | 1 min |
| 4 | [SSH host for terminal / lazygit](#4-ssh-host-for-terminal--lazygit-optional) *(optional)* | Terminal tab | 10 min |
| 5 | [Release signing](#5-android-release-signing-optional) *(optional)* | installing a release APK | 5 min |
| 6 | [iOS / iPadOS](#6-ios--ipados-later) *(later)* | Apple devices | 15 min |
| 7 | [Source control & CI](#7-source-control--ci) | CI | 2 min |

App IDs: Android `com.mohamadtout.git_reviewer` (`app/android/app/build.gradle.kts`), iOS `com.mohamadtout.gitReviewer` (Xcode → Runner → Signing & Capabilities). They are reserved for official releases. **If you fork and distribute a build, change both to your own** (see [LICENSE](LICENSE)).

---

## 1. GitHub token *(optional)*

Without a token you can open any public repo (type `owner/name` or paste a github.com link), but GitHub allows only 60 requests an hour. Sign in from **Repos → Sign in** or **Settings → Sign in** to list your repos, open private ones and get 5,000 an hour.


**Which kind?** Fine-grained tokens can only reach repos owned by **one** account or org, chosen when you create the token. If you review repos where you're a *collaborator on someone else's personal account*, use a **classic token**. A fine-grained token gets 404 there no matter what permissions the owner gives you.

**Classic token (works for everything you can access):** GitHub → Settings → Developer settings → Personal access tokens → *Tokens (classic)* → *Generate new token (classic)*

- Scope: **`repo`** (that's all the app needs)
- Expiration: your call. When it expires the app says "GitHub rejected the token"; sign out in Settings and paste a new one.
- If an org uses SAML SSO: on the token list, use **Configure SSO → Authorize** for that org.

**Fine-grained token (only your own or one org's repos):** Contents → Read, Metadata → Read, Pull requests → **Read and write** (write is for submitting reviews and comments; Read is enough to only browse).

Collaborator on someone's repo? Accept the invitation first (github.com/notifications or the repo page).

Paste the token on the Sign in screen. It's stored in Android Keystore / iOS Keychain and only sent to `api.github.com`. **Never keep it in a file inside the project.**

### 1b. "Sign in with GitHub" (OAuth device flow) *(done; forks only)*

Builds offer a **Sign in with GitHub** button instead of token pasting: the app shows a short code, you approve it on
github.com/login/device, and GitHub hands the app a token. No client secret and no server are involved.

Diffcat's OAuth App already exists and its client ID is built in (`githubClientId` in
`app/lib/features/auth/device_flow.dart`), so every build has the button. A fork should register its own app, so
GitHub's approval page shows the fork's name:

1. GitHub → Settings → Developer settings → **OAuth Apps → New OAuth App**. Name *Diffcat*, homepage the repo URL,
   callback URL anything (e.g. the repo URL; the device flow doesn't use it).
2. On the app's page, tick **Enable Device Flow** and save. Copy the **Client ID** (`Ov23…`). It's public, not a secret;
   don't create a client secret.
3. Build with it: `make run GITHUB_CLIENT_ID=Ov23…` (also `make apk`, `make device-test`), or
   `flutter run --dart-define=GITHUB_CLIENT_ID=Ov23…`. An empty value (`GITHUB_CLIENT_ID=`) hides the button.

The app asks for the `repo` and `read:user` scopes (private repos, reviews, your name). Users can revoke it any time at
github.com → Settings → Applications.

## 2. Run the app

```bash
cd app
flutter pub get
flutter run            # phone connected via USB with developer mode, or an emulator
```

## 3. Notifications

There's nothing to configure.

1. Open a repo and tap the **bell** in the app bar.
2. Allow notifications when Android asks.
3. On Samsung and other aggressive battery managers: **Settings → Apps → Diffcat → Battery → Unrestricted**. Otherwise background checks can be delayed for hours.

The phone checks GitHub about every 15 minutes (Android's minimum) and whenever you open the app. Settings shows when it last checked and has a **Check now** button. Notifications for your own commits are off by default; there's a toggle for that. How it works: [docs/notifications.md](docs/notifications.md).

## 4. SSH host for terminal / lazygit *(optional)*

This is for running real git and lazygit from the phone on a machine you own. Nothing is cloned to the phone.

1. **On the host machine** (a Mac here):
   - System Settings → General → Sharing → **Remote Login** on. (Linux: `sudo apt install openssh-server`.)
   - Optional: `brew install lazygit`.
   - Clone the repos you want to work on there (e.g. `~/code/<repo>`).
2. **Reach it from the phone with [Tailscale](https://tailscale.com):** install it on the host and on each phone/tablet and sign in to the same account. That's all the networking needed. Use the host's Tailscale IP (`100.x.y.z`, shown in the Tailscale app or `tailscale ip -4`) or its MagicDNS name as the host. **Don't** expose port 22 to the internet.
   - You don't need "Tailscale SSH". The Mac's own SSH server (Remote Login) does the work, and Tailscale just carries the traffic.
3. **In the app** (on each device): Terminal → *Add host* → host = the Tailscale IP, user = your Mac username → **Key** → *Generate Ed25519 key on this device*.
4. **Authorize the key:** tap **Install on host…** and enter your Mac account password once. The app logs in, adds this device's public key to `~/.ssh/authorized_keys` (like `ssh-copy-id`) and forgets the password. Then **Save**.
   - Manual alternative: *Copy public key*, then on the host:
     ```bash
     mkdir -p ~/.ssh && chmod 700 ~/.ssh
     echo '<paste public key>' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
     ```
5. *(Optional)* **Startup command:** `cd ~/code/<repo> && lazygit<enter>`
6. **First connection:** compare the fingerprint the app shows with `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on the host, then tap **Trust**.
7. *(Optional, after keys work)* turn off password logins on the host: `PasswordAuthentication no` and `KbdInteractiveAuthentication no` in `/etc/ssh/sshd_config.d/` (keep a key-authorized session open while you test).

## 5. Android release signing *(optional)*

Debug builds install fine with `flutter run`. Release builds (`make apk`, or `flutter build appbundle` for Google Play)
are signed with your own key. The Gradle side is already wired up in `app/android/app/build.gradle.kts`: it reads
`app/android/key.properties` when that file exists, and otherwise signs with the debug key, so CI and forks still build.

1. Create a keystore **outside the repo** and keep it and its passwords backed up. Losing it means you can't update the
   app on Google Play (unless you use Play App Signing with a separate upload key, which is recommended):
   ```bash
   keytool -genkey -v -keystore ~/diffcat-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias diffcat
   ```
2. Create `app/android/key.properties`. It is git-ignored; never commit it or the `.jks`:
   ```properties
   storePassword=…
   keyPassword=…
   keyAlias=diffcat
   storeFile=/Users/<you>/diffcat-release.jks
   ```
3. Run `make apk` and install `app/build/app/outputs/flutter-apk/app-release.apk`. To check which key signed it:
   `$ANDROID_HOME/build-tools/<version>/apksigner verify --print-certs <apk>`. It should show your name, not
   `CN=Android Debug`.

## 6. iOS / iPadOS

1. Put your Apple Developer Team ID in `app/ios/Flutter/Signing.xcconfig` (copy `Signing.xcconfig.example`; the
   file is git-ignored so the ID stays out of the public repo). Don't pick the team in Xcode's *Signing & Capabilities*
   tab: Xcode writes it into `project.pbxproj`, which is committed. If it does, delete the `DEVELOPMENT_TEAM` lines there.
2. `flutter run` on the device. Browsing, diffs and SSH work as on Android.
3. Background checks are wired up (BGAppRefreshTask `git-reviewer-poll`). On the device, keep *Settings → Diffcat →
   Background App Refresh* on. iOS decides when they run, usually a few times a day.

## 6b. Publishing to the App Store and Google Play

Listing text, screenshots, privacy answers and a checklist for each store are in [store/README.md](store/README.md).
The privacy policy is [PRIVACY.md](PRIVACY.md), public at <https://github.com/mohamadtout/diffcat/blob/main/PRIVACY.md>.

## 7. Source control & CI

The public repo is <https://github.com/mohamadtout/diffcat>.

Commits record your git e-mail, which becomes public when you push. This clone is set to GitHub's no-reply address
(`git config user.email` in this repo only), so your personal address stays out of the history. Do the same in any
new clone (GitHub → Settings → Emails shows the address):

```bash
git config user.email "60491833+mohamadtout@users.noreply.github.com"   # this repo only
```

Before pushing, the files that must stay private are git-ignored: `SETUP.local.md`, `app/ios/Flutter/Signing.xcconfig`
(Apple Team ID), `app/android/key.properties` and `*.jks` (release signing), and `store/screenshots/` (large, regenerated).

GitHub Actions (`.github/workflows/ci.yml`) runs format, analyze and tests on every push and PR. It needs no secrets.

---

### Troubleshooting

| Symptom | Fix |
|---|---|
| Repo opens with *Can't open owner/name* | The token can't see it. Fine-grained token + someone else's personal repo → use a classic token. Org repo → org approval / SSO authorization. Pending collaborator invite → accept it |
| No notifications at all | Bell not tapped on that repo, notification permission denied (Settings → Permission), or nothing new since you started watching (the first check is a silent baseline) |
| Notifications hours late | Battery optimisation: set the app to *Unrestricted* (step 3). Opening the app always triggers a check |
| Settings shows a repo under "failed" | That repo returned an error (usually lost access or a renamed repo). Unwatch and re-watch it, or fix the token |
| SSH: "HOST KEY CHANGED" | The host was reinstalled or its key rotated. Verify, then Terminal → host menu → *Forget host key* |
| SSH auth fails with a pasted key | Use OpenSSH-format keys (`-----BEGIN OPENSSH PRIVATE KEY-----`) |
