// Run: node --test marketplace-webhook/test.mjs  (Node 20+, no dependencies)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import worker from './src/index.js';

const env = { WEBHOOK_SECRET: 'test-secret' };
const body = JSON.stringify({
  action: 'purchased',
  marketplace_purchase: { account: { login: 'someone' }, plan: { name: 'Free' } },
});
const signed = (secret) => `sha256=${createHmac('sha256', secret).update(body).digest('hex')}`;
const post = (signature, event = 'marketplace_purchase') =>
  new Request('https://example.workers.dev/', {
    method: 'POST',
    body,
    headers: { 'x-hub-signature-256': signature, 'x-github-event': event },
  });

test('a correctly signed Marketplace event is accepted', async () => {
  assert.equal((await worker.fetch(post(signed('test-secret')), env)).status, 204);
});

test('ping and other events are accepted too', async () => {
  assert.equal((await worker.fetch(post(signed('test-secret'), 'ping'), env)).status, 204);
});

test('a wrong or missing signature is rejected', async () => {
  assert.equal((await worker.fetch(post(signed('other-secret')), env)).status, 401);
  assert.equal((await worker.fetch(post(''), env)).status, 401);
});

test('only POST, and only once configured', async () => {
  assert.equal((await worker.fetch(new Request('https://example.workers.dev/'), env)).status, 405);
  assert.equal((await worker.fetch(post(signed('test-secret')), {})).status, 500);
});
