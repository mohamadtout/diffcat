# Marketplace webhook (Cloudflare Worker)

GitHub requires an active webhook on every Marketplace listing, free ones too. Diffcat is free and has no accounts,
so this Worker only checks that a request comes from GitHub (HMAC signature), logs it and answers `204`. It stores
nothing and never sees a GitHub token. It's the only server code in the project (see decision D15).

Runs on Cloudflare's **free Workers plan**: 100,000 requests a day, far more than Marketplace events will ever be.
Without a payment method on the account Cloudflare can't charge anything; over the limit, requests just fail until
the next day.

## One-time setup (owner)

### 1. Cloudflare account

1. Sign up at <https://dash.cloudflare.com/sign-up> with your email. The free plan needs no credit card; don't add one.
2. Workers & Pages → pick your `workers.dev` subdomain when asked (e.g. `diffcat`). The Worker's URL will be
   `https://diffcat-marketplace.<subdomain>.workers.dev`.

### 2. A webhook secret

Generate one and keep it in your password manager (never commit it):

```bash
openssl rand -hex 32
```

### 3. Deploy

**Command line** (from the repo root; `npx` downloads Wrangler, Cloudflare's CLI):

```bash
cd marketplace-webhook
npx wrangler login                      # opens the browser once
npx wrangler secret put WEBHOOK_SECRET  # paste the secret from step 2
npx wrangler deploy                     # prints the Worker URL
```

**Or the dashboard only:** Workers & Pages → Create → Create Worker → name it `diffcat-marketplace` → Deploy → Edit
code → replace everything with `src/index.js` → Deploy. Then the Worker's Settings → Variables and Secrets → Add →
type *Secret*, name `WEBHOOK_SECRET`, value from step 2 → Deploy.

### 4. Check it

```bash
curl -i https://diffcat-marketplace.<subdomain>.workers.dev        # 405: it's up, and only takes POST
```

### 5. Point the listing at it

GitHub → Settings → Developer settings → OAuth Apps → Diffcat → Marketplace listing → **Webhook**:

| Field | Value |
|---|---|
| Payload URL | `https://diffcat-marketplace.<subdomain>.workers.dev` |
| Content type | `application/json` |
| Secret | the secret from step 2 |
| Active | On |

Save; GitHub sends a `ping`, which shows as delivered (204) under the webhook's recent deliveries. Live logs:
`npx wrangler tail` (or the Worker's Logs tab in the dashboard).

## Changing it

`node --test marketplace-webhook/test.mjs` runs the tests (Node 20+, no dependencies; CI runs them too). Redeploy
with `npx wrangler deploy`, or paste the file into the dashboard editor again.
