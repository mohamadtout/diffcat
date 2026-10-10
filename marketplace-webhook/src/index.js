// GitHub Marketplace webhook for Diffcat's OAuth App listing.
//
// GitHub requires an active webhook for every Marketplace listing, free ones
// included. Diffcat is free and has no accounts, so a purchase or cancellation
// needs no action: this Worker checks the request really comes from GitHub,
// logs the event (visible with `npx wrangler tail`) and answers 204.
// Nothing is stored. See README.md for setup.

const encoder = new TextEncoder();

/** Hex HMAC-SHA256 of `body` with `secret`. */
async function sign(secret, body) {
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, [
    'sign',
  ]);
  const mac = await crypto.subtle.sign('HMAC', key, encoder.encode(body));
  return [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Compares without exiting early, so timing doesn't reveal the signature. */
function equal(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') return new Response('Diffcat Marketplace webhook\n', { status: 405 });
    if (!env.WEBHOOK_SECRET) return new Response('Not configured\n', { status: 500 });

    const body = await request.text();
    const signature = request.headers.get('x-hub-signature-256') ?? '';
    if (!equal(signature, `sha256=${await sign(env.WEBHOOK_SECRET, body)}`)) {
      return new Response('Bad signature\n', { status: 401 });
    }

    const event = request.headers.get('x-github-event');
    if (event === 'marketplace_purchase') {
      const payload = JSON.parse(body);
      const purchase = payload.marketplace_purchase ?? {};
      console.log(
        JSON.stringify({ action: payload.action, account: purchase.account?.login, plan: purchase.plan?.name }),
      );
    } else {
      console.log(JSON.stringify({ event }));
    }
    return new Response(null, { status: 204 });
  },
};
