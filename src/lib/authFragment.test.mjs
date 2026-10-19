// authFragment.test.mjs — a magic-link session never stays in the browser's history (audit 21 Sep, item 29).
// node --test src/lib/authFragment.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { takeAuthFragment } from './authFragment.ts';

const SRC = join(import.meta.dirname, '..');
const fakeWin = (path, search, hash) => {
  const calls = [];
  return { calls, location: { pathname: path, search, hash }, history: { state: { s: 1 }, replaceState: (s, t, u) => calls.push({ s, u }) } };
};

test('the exact fragment Supabase lands with is taken out IN PLACE and handed over', () => {
  // Shape measured on production 21 Sep 2026 (tokens replaced).
  const w = fakeWin('/portal', '', '#access_token=AAA.BBB.CCC&expires_at=1790011535&expires_in=3600&refresh_token=rrr&sb=&token_type=bearer&type=magiclink');
  assert.deepEqual(takeAuthFragment(w), { access_token: 'AAA.BBB.CCC', refresh_token: 'rrr' });
  assert.equal(w.calls.length, 1, 'replaceState, exactly once: an assignment to location.hash would push a new entry and leave this one in history');
  assert.equal(w.calls[0].u, '/portal');
  assert.deepEqual(w.calls[0].s, { s: 1 }, 'the history state is kept');
});

test('the query string survives, and an error fragment is stripped without a session', () => {
  const w = fakeWin('/ar/me', '?request=1', '#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid');
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

test('supabase-js may not read the URL itself, and both portals take the fragment first', () => {
  const client = readFileSync(join(SRC, 'lib', 'supaClient.ts'), 'utf8');
  assert.match(client, /detectSessionInUrl:\s*false/, "supaClient must build the client with detectSessionInUrl:false — auth-js clears the hash with location.hash='' and that leaves the token in history");
  for (const f of ['components/me/CustomerPortal.tsx', 'components/portal/SupplierPortal.tsx']) {
    const src = readFileSync(join(SRC, f), 'utf8');
    assert.match(src, /takeAuthFragment\(undefined, /, `${f} must take a magic-link session out of the URL`);
  }
});

// CWE-384 audit, 19 Oct 2026: a crafted link carrying ANOTHER account's session must not replace the signed-in one.
const jwt = (sub) => 'h.' + Buffer.from(JSON.stringify({ sub, email: sub + '@example.invalid' })).toString('base64url') + '.s';
test('a fragment session for a different user than the signed-in one is dropped (session fixation)', () => {
  const w = fakeWin('/portal', '', '#access_token=' + jwt('zz-demo-attacker') + '&refresh_token=rrr&type=magiclink');
  assert.equal(takeAuthFragment(w, jwt('zz-demo-victim')), null);
  assert.equal(w.calls.length, 1, 'the fragment is still stripped from the address bar');
});
test('a fragment session for the same user, or with nobody signed in, is taken', () => {
  const same = fakeWin('/portal', '', '#access_token=' + jwt('zz-demo-a') + '&refresh_token=r1');
  assert.deepEqual(takeAuthFragment(same, jwt('zz-demo-a')), { access_token: jwt('zz-demo-a'), refresh_token: 'r1' });
  const none = fakeWin('/portal', '', '#access_token=' + jwt('zz-demo-a') + '&refresh_token=r1');
  assert.deepEqual(takeAuthFragment(none, null), { access_token: jwt('zz-demo-a'), refresh_token: 'r1' });
});
