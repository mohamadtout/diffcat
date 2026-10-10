# GitHub Marketplace listing

Diffcat's OAuth App (the one behind **Sign in with GitHub**) listed on GitHub Marketplace. Fill these in at
github.com → Settings → Developer settings → OAuth Apps → Diffcat → **List in Marketplace**. Requirements are from
GitHub's docs ([requirements](https://docs.github.com/en/apps/github-marketplace/creating-apps-for-github-marketplace/requirements-for-listing-an-app),
[listing description](https://docs.github.com/en/apps/github-marketplace/listing-an-app-on-github-marketplace/writing-a-listing-description-for-your-app),
[pricing](https://docs.github.com/en/apps/github-marketplace/listing-an-app-on-github-marketplace/setting-pricing-plans-for-your-listing)).

The images are git-ignored like the store screenshots: `python3 store/github_marketplace_assets.py` writes them to
`store/screenshots/github-marketplace/` (after `make store-screenshots NAME=android-tablet-10`).

## OAuth App settings (before listing)

| Field | Value |
|---|---|
| Application logo | `logo-512.png` (the same logo as the listing; replaces GitHub's default pattern on the approval page) |
| Badge background color | `#4C2F9E` |
| Homepage URL | `https://github.com/mohamadtout/diffcat` |
| Application description | `Review GitHub code changes from your phone or tablet.` |
| Enable Device Flow | On (sign-in depends on it) |

## Contact info

GitHub asks for individual addresses rather than group ones (`support@…`). These are for GitHub only and are
not shown on the listing. Use the owner's address; it's deliberately not written here (public repo).

| Field | Value |
|---|---|
| Technical lead | owner's email |
| Marketing lead | owner's email |
| Finance lead | owner's email (only used for paid plans) |

## Listing description

| Field | Limit | Value |
|---|---|---|
| Listing name | 255; can't match another GitHub account (`diffcat` is free) | `Diffcat` |
| Very short description | 40–80 recommended; no app name, no final period | `Review commits, diffs, and pull requests from your phone or tablet` (66) |
| Primary category | | `Code review` |
| Secondary category | | `Mobile` |
| Supported languages | up to 10, optional | Leave empty: Diffcat works with any language |

### Introductory description

150–250 recommended, starts with the app's name (175):

```
Diffcat brings code review to your phone and tablet. Read diffs with syntax highlighting, follow a file's history across branches, and review pull requests, online or offline.
```

### Detailed description

At most 1,000 characters, 3–5 value propositions with level-three headings, no final punctuation on titles (786):

```
### Review pull requests anywhere
Comment on lines, reply to threads, and submit Comment, Approve, or Request changes reviews. An inbox lists the pull requests waiting for you.

### Diffs made for small screens
Syntax highlighting with the exact changed words marked, whole files with changes in place, and list and detail side by side on tablets.

### See how code got here
Blame, a file history graph across branches, and every file changed since any commit or tag.

### Read offline
Download commits, pull requests, and files, then read them on a plane or a slow connection. Data saver keeps GitHub requests low.

### Nothing in between
The app talks to GitHub directly with no servers of its own. Notifications are checked on your device, and your token stays in its secure storage.
```

### URLs

| Field | Required | Value |
|---|---|---|
| Customer support URL | yes | `https://github.com/mohamadtout/diffcat/issues` |
| Privacy policy URL | yes | `https://github.com/mohamadtout/diffcat/blob/main/PRIVACY.md` |
| Installation URL | yes (OAuth Apps) | `https://github.com/mohamadtout/diffcat#readme` until the store pages are live, then the App Store / Google Play link |
| Company URL | no | `https://github.com/mohamadtout` |
| Documentation URL | no | `https://github.com/mohamadtout/diffcat#readme` |
| Status URL | no | Leave empty (there's no Diffcat service to report on) |

## Images

| Field | Rule | File / value |
|---|---|---|
| Logo | ≥ 200 × 200, square, transparent, no text | `logo-512.png` |
| Badge background color | behind the logo | `#4C2F9E` |
| Feature card | 965 × 482, a pattern or texture; GitHub draws the logo and name on it | `feature-card-965x482.png` |
| Feature card text color | | `#FFFFFF` (white) |
| Screenshots | up to 5, ≥ 1,200 px wide, same ratio, no browser chrome | the five `screenshot-*.png` (2560 × 1600, demo data) |

Screenshot captions, in order:

1. `Commits and diffs side by side on a tablet`
2. `Review pull requests: line comments, replies, and approvals`
3. `Full-width diffs with syntax highlighting`
4. `Downloaded repos open with no connection`
5. `A real terminal to your own machine for git and lazygit`

## Pricing plan

Free only. GitHub doesn't allow a free listing for an app that's paid elsewhere, and Diffcat is free everywhere.
Published plans can't be edited later.

| Field | Value |
|---|---|
| Plan name | `Free` |
| Pricing model | Free |
| Available for | Personal accounts and organizations |
| Short description | `All of Diffcat, free for everyone` |
| Bullet 1 | `Public and private repositories` |
| Bullet 2 | `Pull request reviews and an inbox` |
| Bullet 3 | `Offline downloads and data saver` |
| Bullet 4 | `A terminal to your own machine` |

## Webhook

Required for every listing, free ones included: GitHub sends `marketplace_purchase` events (purchases,
cancellations), and **Active** must be on before submitting. It goes to the stateless Cloudflare Worker in
[`marketplace-webhook/`](../marketplace-webhook/README.md) (free plan, no card): set that up first, then:

| Field | Value |
|---|---|
| Payload URL | `https://diffcat-marketplace.<your workers.dev subdomain>.workers.dev` |
| Content type | `application/json` |
| Secret | the secret stored in the Worker as `WEBHOOK_SECRET` (password manager, never this repo) |
| Active | On |

## Submitting

Complete every section on the listing's Overview page, accept the GitHub Marketplace Developer Agreement, then
**Submit for review**; an onboarding expert follows up. Paid plans would need a verified organization and at least
200 users for an OAuth App, which a free listing doesn't.
