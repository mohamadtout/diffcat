# Decisions (lightweight ADRs)

### D1: Flutter for Android now, iOS/iPadOS later
One codebase covers both platforms. Terminal needs are met by `xterm` (a full VT emulator) plus `dartssh2` (pure-Dart SSH), which together run lazygit at full fidelity. Native per-platform apps would double the work for no capability gain.

### D2: Read through the GitHub API, never clone on device
The goal was "review from my palm" with minimal pulling. The REST API covers log/show/diff/tree/blob/PRs. ETag caching keeps rate-limit use low. Limits (300-file compare, no rename following) are surfaced in the UI rather than worked around with a clone.

*Amended 2026-10-08 (D11):* the owner asked for offline copies for slow networks. They're saved API responses, so this still holds: nothing is cloned and there's no git on the device.

### D3: Real git and lazygit run on the user's machine over SSH
A stock phone can't run lazygit, and an on-device git (libgit2/JGit) would require cloning, which conflicts with D2. SSH gives an unrestricted terminal with zero repo data on the phone.

### D4: Separate API console (git-like DSL)
For quick queries without an SSH host, a small command language mirrors familiar git syntax over the API. It's read-only by design. Writes go through SSH.

### D5: Notifications by on-device polling (no backend)
*Superseded an earlier webhook → Cloud Function → FCM design (2026-10-08).* Webhooks needed a Firebase Blaze
project, a deployed function, a shared secret, and repo **admin** rights. That last one is impossible on another
user's personal repo, where collaborators can't manage webhooks. Polling from the phone needs only the token the
app already has, works for any repo you can read, and costs nothing. The tradeoff is latency (≥15 min on Android,
OS-scheduled on iOS), which the owner explicitly accepted.

### D6: Personal access token auth, optional
For a single-user app, a fine-grained PAT is the simplest secure option, with no OAuth app or callback server. OAuth device flow is on the roadmap if the app is ever shared.

Signing in is optional (2026-10-08): public repos are readable without a token, so the app opens to a public-repo browser and the token only unlocks your repo list, private repos and the 5,000/hour limit (60/hour signed out). Notifications also work signed out, within the lower limit.

### D7: Riverpod 3 without codegen, hand-written models
This keeps the build to `flutter pub get` with no `build_runner` step that agents or CI can forget. Records serve as family keys.

### D8: Trust-on-first-use SSH host keys, keys generated on device
This mirrors OpenSSH behaviour. Generating Ed25519 keys on the phone means the private key never travels. Keys are stored in Keychain/Keystore-backed secure storage.

### D9: Source-available, noncommercial license with reserved app IDs
The code is public under PolyForm Noncommercial 1.0.0 plus one condition: distributed builds must not use the
`com.mohamadtout.*` identifiers (see [LICENSE](../LICENSE)). The owner wanted free use and modification but no
commercial use. That rules out OSI "open source" licenses, so the project says "source-available". PolyForm is
used unchanged, with the condition added before it, instead of writing a custom license. Reserving the IDs keeps
forks from shipping as, or updating over, the official app.

### D10: Original cat icon, not the Octocat
The icon is an original cat wearing glasses with a red − lens and a green + lens, a nod to GitHub and diffs.
GitHub's logo policy forbids using the Octocat in another app's icon, and app stores reject trademark misuse.
Sources and regeneration steps are in [app/assets/icon/](../app/assets/icon/README.md).

### D11: Offline copies are recorded API responses, served first
Downloads (repo screen → download button, per branch) replay the same `GitHubApi` calls the screens make through a recording client, so every response is saved under exactly the key a later read looks up. Screens get a replaying client: a saved response is served instantly with no network, anything not saved goes to GitHub as before. The alternatives were a separate offline data model (a second code path per screen, which drifts) or a clone (ruled out by D2 and needing git on the device).

- **Saved copies are served even when online**, so slow networks don't wait. That makes them snapshots: the repo title says "saved 2h ago" and the button becomes **Update**. Updates skip commit diffs already saved (a sha never changes), so they're cheap.
- **Diffs by default; all files is opt-in**, fetched as one tarball (one request instead of one per file, which matters at 60 requests/hour signed out). Text files over 1 MB and binaries are skipped.
- Responses are filed by what they belong to (repo, branch, commit, PR, branch files), so Settings → Downloads can show sizes and delete at each level. A commit shared by two saved branches survives deleting one of them.
- The notification poller uses `liveGithubApiProvider`, which ignores saved copies.
- **Offline mode** is a separate, explicit per-repo switch (Offline chip, cloud button, banner): online mode prefers saved copies but still fetches what's missing; offline mode never touches the network. Tapping a repo row always opens online, so offline is a deliberate choice.

