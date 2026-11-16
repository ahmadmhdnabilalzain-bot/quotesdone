// node --test scripts/e2e/node_keepalive.test.mjs  (offline: a local server on 127.0.0.1 counts the connections it is opened)
// Fails if a call made after the sign-in code's wait (here 4.6 s, past Node's 4 s default) opens a new connection once the harness
// holds its connections (node_keepalive.mjs says what it cost on the paid certification of 16 Nov 2026).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { holdConnectionsLikeABrowser, KEEP_ALIVE_MS } from './node_keepalive.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function server() {
  let connections = 0;
  const s = createServer((_q, r) => { r.end('ok'); });   // no Keep-Alive header, as Supabase sends none
  s.keepAliveTimeout = 0;   // no server timeout and so no Keep-Alive header (Node sends one otherwise): only the client's idle time decides
  s.on('connection', () => { connections++; });
  await new Promise((r) => s.listen(0, '127.0.0.1', r));
  return { url: `http://127.0.0.1:${s.address().port}/`, count: () => connections, close: () => new Promise((r) => { s.closeAllConnections(); s.close(r); }) };
}
const get = async (u) => { const r = await fetch(u); await r.text(); };

test('after the code e-mail\'s wait, a held connection is used again; Node\'s default opens a new one', async () => {
  const a = await server();
  try { await get(a.url); await sleep(4600); await get(a.url); } finally { await a.close(); }
  assert.equal(a.count(), 2, 'Node\'s default (4 s idle) opened a second connection: the handshake the paid run paid on Verify');

  const held = await holdConnectionsLikeABrowser();
  assert.ok(held, 'the global dispatcher was replaced');
  assert.equal(await holdConnectionsLikeABrowser(), held, 'idempotent');
  const b = await server();
  try { await get(b.url); await sleep(4600); await get(b.url); } finally { await b.close(); }
  assert.equal(b.count(), 1, 'the same connection after 4.6 s idle');
  assert.ok(KEEP_ALIVE_MS >= 30_000, 'held at least as long as the longest wait inside a step');
});

test('the certification and the browser route hold their connections before the first journey', () => {
  for (const f of ['./supplier_registration_certification.mjs', './browser.mjs']) {
    const src = readFileSync(new URL(f, import.meta.url), 'utf8');
    assert.match(src, /await holdConnectionsLikeABrowser\(\)/, `${f} routes the page's calls through Node without holding its connections`);
  }
});
