# Instant push notifications (plan, not built)

Today notifications come from polling (see [notifications.md](notifications.md)): about every minute while the app is
open, and every 15 minutes or later in the background, when the OS allows. This is the plan for notifications within
seconds **with the app closed**, written down on 2026-10-10 so it can be picked up later. Nothing here is implemented.

## What GitHub allows (why polling is the default)

- GitHub only pushes events through **webhooks**, and a webhook can only be created by a repo admin (repository
  webhook), an org owner (organization webhook), or by installing a **GitHub App**. There are no webhooks for user
  accounts, and an OAuth token (even with `repo` scope) doesn't change that.
- So instant push can only cover repos where someone with admin rights installs Diffcat's GitHub App: your own repos and
  your organizations'. Repos you merely watch stay on polling. That's decision D5's original obstacle, and it still holds.
- GitHub's notifications inbox (used by polling since 1.1.1) covers PR activity, but never plain commit pushes.

## Architecture

```
GitHub ──webhook (push, pull_request, review…)──▶ Cloudflare Worker ──FCM HTTP v1──▶ Firebase Cloud Messaging
  ▲ GitHub App "Diffcat" installed                 │  verify signature                 │        (APNs for iOS)
  │ on the user's / org's repos                     │  look up devices in D1            ▼
  │                                                 │  send a data-only "ping"       Diffcat (closed)
  └───────────── app polls that repo ◀──────────────┴──────────────────────────────  wakes, runs Poller.checkRepo,
                 (its own token, as today)                                           shows the usual notification
```

**Ping, don't payload.** The Worker sends only "repo `<id>` changed" (data-only message, no commit titles). The app
wakes, runs the existing per-repo check with its own token, and builds the same notifications as polling. That keeps
private code out of the Worker and out of Google/Apple's push services, reuses all the existing filtering (own
commits, bots, drafts…), and means the server never needs a GitHub token.

## Components

### 1. GitHub App (separate from the OAuth App used for sign-in)

| Setting | Value |
|---|---|
| Name | `Diffcat Push` (the OAuth App already uses "Diffcat") |
| Webhook URL | `https://<worker>.workers.dev/github` |
| Webhook secret | random 32+ bytes, stored as a Worker secret (`GITHUB_WEBHOOK_SECRET`) |
| Repository permissions | Metadata: read (always), Contents: read (`push`), Pull requests: read (`pull_request`, `pull_request_review`, `pull_request_review_comment`) |
| Events | Push, Pull request, Pull request review, Pull request review comment |
| Where it can be installed | Any account |

Installing needs the account owner (personal repos) or an org owner; org members can request it and an owner
approves. Check GitHub's current rules when building.

### 2. Cloudflare Worker (free plan, no payment method on the account)

Endpoints:

| Route | What |
|---|---|
| `POST /github` | Verify `X-Hub-Signature-256` (HMAC-SHA256, constant-time compare). Read `repository.id`, find subscribed devices in D1, send each a data-only FCM message `{repo_id, kind}`. Reply 202 quickly. |
| `POST /devices` | The app registers `{fcm_token, platform, repos: [{owner, name}]}` with the user's GitHub token in `Authorization`. The Worker calls `GET /repos/{o}/{r}` with that token once, to prove access (no subscribing to private repos you can't read), stores repo **ids**, and **discards the token**. |
| `DELETE /devices` | Unregister a token (sign-out, unwatch all, uninstall). |
| `GET /installed?repo=o/r` | Whether the GitHub App is installed on a repo, so the app can show "instant" vs "checked every 15 min". Uses the app's JWT; cache the answer. |
| `POST /marketplace` | The Marketplace webhook already deployed (`marketplace-webhook/`); merge it in. |

Storage (D1, free: 5 GB, 5M row reads and 100k row writes per day):

```sql
CREATE TABLE devices (token TEXT PRIMARY KEY, platform TEXT, login TEXT, updated_at INTEGER);
CREATE TABLE subscriptions (repo_id INTEGER, token TEXT, PRIMARY KEY (repo_id, token));
```

Remove a token when FCM answers `UNREGISTERED`. Remove all rows of a repo on `installation_repositories` "removed".

FCM HTTP v1 needs an OAuth access token: sign a JWT (RS256) with the Firebase service account key (Worker secret
`FCM_SERVICE_ACCOUNT`) using WebCrypto, exchange it at `oauth2.googleapis.com/token`, and keep it in memory or KV for
its hour of validity.

### 3. Firebase project (Spark plan, free, no billing account)

Only **Cloud Messaging** is used: no Functions, Firestore or Hosting, which are the parts that cost money at scale.
Upload the APNs auth key (`.p8`, from the Apple developer account) to the Firebase project so FCM delivers to iOS.

### 4. App changes

- `firebase_messaging` (verify the current major version in `~/.pub-cache` first), `google-services.json` /
  `GoogleService-Info.plist` (git-ignored, like the signing files), iOS Push Notifications + Background Modes →
  *remote notifications* capability.
- On watch/unwatch, sign-in/out and token refresh: call `POST /devices` / `DELETE /devices`.
- Background message handler (its own isolate, like `backgroundPollDispatcher`, so no Riverpod): look up the repo by id
  among watched repos, run `Poller.checkRepo` for just that repo, show events via `LocalNotifications`. Same tags as
  polling, so a later poll doesn't duplicate.
- Repo screen bell: say "Instant" when `/installed` is true, else "Checked about every 15 minutes", with a link to
  install the GitHub App.
- Polling stays exactly as it is: it covers everything the App isn't installed on, and is the fallback when the
  Worker is down or over its daily limit.

## Costs and limits

| Piece | Free allowance | When exceeded |
|---|---|---|
| Worker requests | 100,000 / day | Requests fail with error 1027 until the next day. **No charge without a payment method**; the app silently falls back to polling. |
| Worker outgoing calls (FCM sends) | 50 per request | A push to a repo with more than ~45 devices must be split: queue the rest, or send FCM **topic** messages (`/topics/repo_<id>`, one call for everyone; the app subscribes to topics itself). Topics are the simpler choice. |
| Worker CPU | 10 ms per request | HMAC and RS256 run in WebCrypto (fast); fine. |
| D1 | 5M row reads, 100k row writes / day | Writes are only registrations; reads are one query per webhook. |
| FCM / APNs | Free, no per-message cost | — |
| If ever paid | Workers Paid: $5/month, 10M requests included | Optional, only if usage grows past the free day. |

Volume grows with **activity on installed repos**, not with downloads: a user who never installs the GitHub App costs
nothing. Rough sizing: 100k webhooks/day is about one event every second, all day.

## What changes outside the code

- CLAUDE.md hard rule "No backend": add the Worker as the one exception (stateless apart from device registrations).
- decisions.md: amend D5 (instant push for installed repos, polling everywhere else), new decision for ping-only push.
- PRIVACY.md and the store privacy answers (App Store privacy labels, Play data safety): a push token, the GitHub login
  and the ids of watched repos are sent to the Worker; nothing else, and nothing from the repos.
- SETUP.md: Firebase project, APNs key, GitHub App, Worker secrets.

## Build order

1. GitHub App (webhook URL can point at the Worker from step 2).
2. Worker with `/github` that only verifies and logs; check deliveries in the App's "Advanced" tab.
3. Firebase project, FCM service account; send a test ping to one device.
4. App: register device, background handler running `Poller.checkRepo`, bell shows "Instant".
5. D1 schema, `/devices`, cleanup on `UNREGISTERED` and on uninstall.
6. Docs and privacy updates above; test on both devices with the app swiped away.
