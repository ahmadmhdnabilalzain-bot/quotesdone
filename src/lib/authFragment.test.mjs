// authFragment.test.mjs — a session in the URL is stripped from the address bar and NEVER adopted.
// Audit 21 Sep item 29 (no token left in history) + CWE-384 audit 19 Oct 2026 (no login fixation by crafted link).
// node --experimental-strip-types --test src/lib/authFragment.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { takeAuthFragment } from './authFragment.ts';
import { readSource } from '../../scripts/lib/portal_sources.mjs';

const SRC = join(import.meta.dirname, '..');
const fakeWin = (path, search, hash) => {
  const calls = [];
  return { calls, location: { pathname: path, search, hash }, history: { state: { s: 1 }, replaceState: (s, t, u) => calls.push({ s, u }) } };
};
const jwt = (sub) => 'h.' + Buffer.from(JSON.stringify({ sub, email: sub + '@example.invalid' })).toString('base64url') + '.s';

test('a crafted link carrying a session is stripped IN PLACE and never handed over (session fixation)', () => {
  const w = fakeWin('/portal', '', '#access_token=' + jwt('zz-demo-attacker') + '&expires_in=3600&refresh_token=rrr&token_type=bearer&type=magiclink');
  assert.equal(takeAuthFragment(w), null);
  assert.equal(w.calls.length, 1, 'replaceState exactly once: nothing left one Back press away');
  assert.equal(w.calls[0].u, '/portal');
  assert.deepEqual(w.calls[0].s, { s: 1 });
});

test('the query string survives, and an error fragment is stripped', () => {
  const w = fakeWin('/ar/me', '?request=1', '#error=access_denied&error_code=otp_expired');
  assert.equal(takeAuthFragment(w), null);
  assert.equal(w.calls[0].u, '/ar/me?request=1');
});

test("the portal's own view fragments are left alone", () => {
  for (const h of ['', '#', '#account', '#spatial', '#documents']) {
    const w = fakeWin('/me', '', h);
    assert.equal(takeAuthFragment(w), null, h);
    assert.equal(w.calls.length, 0, h);
  }
});

test('both portals strip the fragment first and sign in from nothing in the URL', () => {
  const client = readFileSync(join(SRC, 'lib', 'supaClient.ts'), 'utf8');
  assert.match(client, /detectSessionInUrl:\s*false/, 'supabase-js must not read a session out of the URL itself');
  for (const f of ['components/me/CustomerPortal.tsx', 'components/portal/SupplierPortal.tsx']) {
    const src = readSource('src/' + f);
    assert.match(src, /takeAuthFragment\(\);/, `${f} must strip a URL session on mount`);
    assert.doesNotMatch(src, /urlSession|takeAuthFragment\([^)]/, `${f} must never adopt a URL session`);
  }
});

test('supplier sign-out also drops the widget chat id', () => {
  const src = readSource('src/components/portal/SupplierPortal.tsx');
  const so = src.match(/const doSignOut = [^\n]*/)[0];
  assert.match(so, /removeItem\('qd-chat-conv'\)/);
});
