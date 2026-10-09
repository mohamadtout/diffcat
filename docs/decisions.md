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

*Amended 2026-10-09:* builds with an OAuth App client ID (`--dart-define=GITHUB_CLIENT_ID`) also offer **Sign in with
GitHub** through the device flow. It needs no client secret or redirect, so the app stays backend-free; the client ID
is public. Pasting a PAT still works, and is the only option in builds without the ID (forks, CI).

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


### D12: The file history graph is built from per-branch path histories
GitHub's `commits?path=` returns each commit's real parents, not the simplified ones `git log --graph -- path` draws
with, and walking the real DAG would mean fetching every commit in between (or a clone, ruled out by D2). So the graph
uses one path-filtered history per branch (1 request per 30 commits per branch) and lays it out in
`history_graph.dart`:

- A commit belongs to the base lane if the base branch has it, otherwise to the first other branch that does. A
  branch's line runs from its newest own commit to the commit its work started from.
- Rebased or cherry-picked copies are found by identical message, author and author date (git keeps the author date
  and changes the committer date), and `Revert "X"` by title. Both get dashed links. Squash merges can't be matched.
- A branch that was merged has no commits of its own any more, so it shows only as a tip label in the base lane.
- Rows older than the oldest loaded commit of a branch with more pages are hidden until that page loads, so a lane
  never looks shorter than it is.

Branches cost requests, so open PR branches are added automatically only when signed in (at most 3), and at most 5
branches are drawn, which is about as many lanes as fit beside the text on a phone.
### D13: Terminal git status via OSC 7 and a side channel, hook typing opt-in
The status bar needs the shell's folder. Parsing prompts or guessing from `/proc` breaks across shells and OSes;
OSC 7 is the standard way for a shell to report it (fish/VTE setups already do). The git status is then read on a
separate SSH exec channel, so the user's shell, scrollback and history are untouched. Shells that don't report OSC 7
need a hook: typing one into someone's shell is surprising (and it would land on production boxes too), so it's
off by default, its echo is hidden, and the same hook is offered to paste into an rc file instead.

Fonts are bundled (about 3.8 MB) rather than downloaded at runtime (Google Fonts), which would add a network
dependency and a third party to the privacy policy. JetBrains Mono is the Nerd Font build, regular weight only,
because prompt themes (starship, powerlevel10k) need its glyphs.
### D14: Secrets stay on this device; app data isn't backed up
Secure storage uses one configuration everywhere (`appSecureStorage`). On iOS it's
`first_unlock_this_device`: the background check runs while the phone is locked, which the default
(`when_unlocked`) can't read, and `ThisDevice` keeps secrets out of backups and device migration. Existing items are
re-saved once (`SecureStore.migrate`) because a keychain item keeps the level it was written with.

Android backups are off (`allowBackup=false`, `data_extraction_rules.xml` for cloud and device transfer) and on iOS
the offline folder is excluded from iCloud backup: offline copies can be private source code, which the privacy policy
promises never leaves the device. Secure storage couldn't be restored on another device anyway (its key is in the
Keystore/Keychain). The cost is that a new phone starts fresh: re-add the token and SSH hosts.
