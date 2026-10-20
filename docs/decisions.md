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

*Amended 2026-10-10:* the owner registered Diffcat's OAuth App and its client ID is now the built-in default, so
every build (store, `flutter run`, CI) offers the button. That's how other open-source GitHub clients ship theirs:
the device flow has no secret, and the ID only names the app on GitHub's approval page. Forks override it with
`--dart-define=GITHUB_CLIENT_ID` (empty hides the button).

While the user approves in the browser, Android cuts the backgrounded app's network, so a poll fails with "Failed host
lookup". Polling treats that as temporary (only a GitHub answer or the code expiring ends it) and polls again the
moment the app returns to the foreground.

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
- **Diffs by default; all files is opt-in** (the sheet estimates its size from the tree's blob sizes, 1 request), fetched as one tarball (one request instead of one per file, which matters at 60 requests/hour signed out). Text files over 1 MB and binaries are skipped.
- Responses are filed by what they belong to (repo, branch, commit, PR, branch files), so Settings → Downloads can show sizes and delete at each level. A commit shared by two saved branches survives deleting one of them.
- The notification poller uses `liveGithubApiProvider`, which ignores saved copies.
- **Offline mode** is a separate, explicit per-repo switch (Offline chip, cloud button, banner): online mode prefers saved copies but still fetches what's missing; offline mode never touches the network. Tapping a repo row always opens online, so offline is a deliberate choice.

*Amended 2026-10-10:* serving every saved copy first made a downloaded repo a silent snapshot while online (new
commits and PRs didn't show until an update). Now Settings → **Data saver** chooses. Off (default, "fresh"): only
responses pinned to a commit sha (diffs, files and trees at a sha, compares of two shas) come from the download, since
they can never change and asking again would only spend rate limit; lists, branches and PRs load live and fall back to
the download when GitHub can't be reached or the rate limit runs out. On: the earlier behavior, everything saved first,
and the repo title shows the download's age. Live responses aren't written back into downloads: a download stays a
consistent snapshot of what the user chose to save.


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

### D15: One stateless Worker, only for the GitHub Marketplace webhook
GitHub requires an active webhook on every Marketplace listing, free ones included (2026-10-10). Diffcat is free with
no accounts, so `marketplace-webhook/` only verifies GitHub's signature, logs and answers 204. It stores nothing,
never sees a token, and the app never calls it, so the app itself still has no backend (D5). It runs on Cloudflare's
free Workers plan with no payment method on the account: past the free 100,000 requests a day it fails until the next
day rather than costing anything. Instant push would extend the same Worker; that plan is in
[instant-push.md](instant-push.md) and isn't built.

### D16: The terminal has its own keyboard input client
xterm's text input kept a word the keyboard was composing on the phone, drawn at the cursor, until a space committed
it: the cursor stayed at the start of the word, and Tab completed whatever the shell had (nothing of that word).
Its default email field also combines with suggestions off into Android's "filter" field type (0x20 | 0x90 = 0xB0),
where Samsung Keyboard composes. Backspace on its empty field did nothing on iOS (UIKit has nothing to delete, so
Flutter sends no update) and on Android keyboards that don't fall back to a delete key event; iOS also turned `"`
into `“`. All of this was reproduced on an emulator and simulator (2026-10-11).

`TerminalKeyboard` uses Flutter's delta model instead and sends every edit as it happens, composing included, with a
two-space field so backspace has something to delete. Deltas carry the text they apply to, so a keystroke that
reaches the app before its last reset is still counted once. Correcting a composed word costs a few backspaces in the
shell, which beats the shell not seeing it at all.

### D17: GitHub releases ship one APK per CPU type
The single release APK was 73 MB, and 46 MB of it was never used on any one phone: it held the Flutter engine
(12 MB) and the compiled Dart code (11 MB) once for each of arm64, 32-bit ARM and x86_64, stored uncompressed. Play
already sends each phone only its own part of the bundle (about 12 MB to download). Releases now ship
`--split-per-abi` APKs (25 MB for arm64), and release builds use `--split-debug-info` (1.6 MB less per CPU type; the
symbols are kept to decode stack traces, SETUP.md § 6c). Measured 2026-10-12.

Rewriting as two native apps (Kotlin/Compose and SwiftUI) was weighed and rejected. It would save an estimated 5 MB
per Play download for two codebases to maintain (D1). The other options measured: compressing the native libraries in
the APK (12.5 MB file, but 34 MB installed instead of 25, and a slower start), and cutting the Nerd Font down to the
prompt icons (about 1 MB, at the risk of blank icons in some prompts). Both are still open.

### D18: GitHub Actions through the API, with the form read from the workflow file
Starting, re-running and cancelling workflows are writes, like reviews: signed in and online only, and a 403 explains
that a fine-grained token needs the Actions permission. The REST API doesn't say whether a workflow can be started by
hand or which inputs it takes, so the Run workflow sheet reads the workflow's file at the chosen branch (one request)
and parses `on.workflow_dispatch.inputs` with the `yaml` package. That's also what GitHub does: the form follows the
file on that branch.

Runs that are still going refresh every 10 to 15 seconds, but only while they can be seen (`AutoRefresh` checks the
repo tab's visibility, `TickerMode` and the app's lifecycle) and only signed in: 60 requests an hour wouldn't last a
build signed out. Unchanged responses are 304s, which don't count against the rate limit. Job logs are plain text
behind a redirect, so they're fetched like tarballs and never saved offline; GitHub only has a job's log once the job
has finished, so the log screen waits for that instead of asking early.

### D21: Code scales less than UI text
Code, line numbers and the blame gutter follow the system text size only up to 1.15× (`AppTheme.codeMaxTextScale`),
because code has its own size setting (Settings → Code view) and at 1.5× a phone showed about 22 columns. Everything
else, including the commit and PR headers above a diff, keeps full scaling, and the 2× sweep still has to pass. Owner
decision, 2026-10 (D19).

### D20: Colors keep the brand blue; status colors are separate from diff colors
`ColorScheme.fromSeed`'s default `tonalSpot` variant turned the brand blue (#2F81F7) into a slate blue, so the scheme
uses `fidelity`, which keeps primary close to the seed (#0059BA light). Its tertiary is orange, which read as a second
brand on the "Offline" chip, so tertiary is set to a calm teal. CI, pull request and review states have their own
`StatusColors` instead of borrowing `DiffColors`, because users edit diff colors (a colorblind diff palette shouldn't
recolor "passed" and "failed"). Changed diff lines get a 3 dp bar at the left edge besides the tint and the +/- sign,
and the dark tints are stronger: at night the old ones were barely brighter than the page.

### D19: Design direction from the 2026-10 design review
[design-review.md](design-review.md) plans the redesign; the owner settled its open questions. Code, line numbers and
the blame gutter may scale less than UI text with large system text (code size has its own setting), so a phone at
1.5× still shows useful code. Repo sections stay in a bottom navigation bar on phones for reach; wider windows use top
tabs. Markdown may come from a package, but a lean hand-made renderer (publishable later as a pub package) is preferred
if it does the job better. The cat mascot can appear in first run and a few empty states, never on working screens.
