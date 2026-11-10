// adminTwoStep.test.mjs — the two-step admin sign-in, driven with the REAL @supabase/auth-js client over a stubbed auth
// server (security checklist audit 10 Nov 2026, open item 1; it_engineer). Nothing reaches a real host: the client's
// `fetch` is the stub below, the identity is a ZZ DEMO address under example.invalid, and storage is in memory.
// node --test src/lib/adminTwoStep.test.mjs
//
// Proves: no session -> e-mail step; an aal1 admin with no authenticator -> ENROL (never refused); a wrong code is
// rejected and the session stays aal1; the right code makes it aal2; a later aal1 sign-in with that authenticator ->
// CHALLENGE; a QR shown and never confirmed is cleared before a new enrolment; and only TOTP is ever enrolled.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GoTrueClient } from '@supabase/auth-js';
import { standing, startEnrolment, verifyCode } from './adminTwoStep.ts';

const b64u = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const now = () => Math.floor(Date.now() / 1000);
const tok = (aal) => `${b64u({ alg: 'ES256', typ: 'JWT' })}.${b64u({ sub: 'zz-demo-admin', aal, role: 'authenticated', aud: 'authenticated', exp: now() + 3600, iat: now(), email: 'zz-demo-admin@example.invalid', session_id: 'zz-s1', amr: [{ method: aal === 'aal2' ? 'totp' : 'otp', timestamp: now() }] })}.sig`;

function stubAuth() {
  const st = { factors: [], seq: 0, calls: [], enrolBodies: [] };
  const user = () => ({ id: 'zz-demo-admin', aud: 'authenticated', role: 'authenticated', email: 'zz-demo-admin@example.invalid', factors: st.factors, app_metadata: {}, user_metadata: {}, created_at: '2026-11-10T00:00:00Z' });
  const json = (b, status = 200) => new Response(JSON.stringify(b), { status, headers: { 'Content-Type': 'application/json' } });
  const fetch = async (input, init = {}) => {
    const u = new URL(typeof input === 'string' ? input : input.url);
    assert.equal(u.host, 'stub.invalid', 'the client must only ever reach the stub');
    const m = (init.method || 'GET').toUpperCase(); const p = u.pathname; const body = init.body ? JSON.parse(init.body) : {};
    st.calls.push(`${m} ${p}`);
    if (p === '/auth/v1/user') return json(user());
    if (p === '/auth/v1/factors' && m === 'POST') {
      st.enrolBodies.push(body);
      const id = 'zz-f' + (++st.seq);
      st.factors.push({ id, factor_type: body.factor_type, status: 'unverified', friendly_name: body.friendly_name, created_at: '2026-11-10T00:00:00Z', updated_at: '2026-11-10T00:00:00Z' });
      return json({ id, type: 'totp', friendly_name: body.friendly_name, totp: { qr_code: 'data:image/svg+xml;utf-8,<svg/>', secret: 'ZZDEMOSECRET' + st.seq, uri: 'otpauth://totp/zz' } });
    }
    let m2;
    if ((m2 = p.match(/^\/auth\/v1\/factors\/([^/]+)\/challenge$/))) return json({ id: 'zz-c-' + m2[1], type: 'totp', expires_at: now() + 300 });
    if ((m2 = p.match(/^\/auth\/v1\/factors\/([^/]+)\/verify$/))) {
      if (body.code !== '246810') return json({ code: 'mfa_verification_failed', msg: 'Invalid TOTP code entered', error_code: 'mfa_verification_failed' }, 422);
      st.factors = st.factors.map((f) => (f.id === m2[1] ? { ...f, status: 'verified' } : f));
      return json({ access_token: tok('aal2'), refresh_token: 'zz-r2', token_type: 'bearer', expires_in: 3600, expires_at: now() + 3600, user: user() });
    }
    if ((m2 = p.match(/^\/auth\/v1\/factors\/([^/]+)$/)) && m === 'DELETE') { st.factors = st.factors.filter((f) => f.id !== m2[1]); return json({ id: m2[1] }); }
    if (p === '/auth/v1/logout') return new Response(null, { status: 204 });
    return json({ msg: 'stub: not routed ' + m + ' ' + p }, 404);
  };
  const mem = new Map();
  const storage = { getItem: (k) => mem.get(k) ?? null, setItem: (k, v) => { mem.set(k, v); }, removeItem: (k) => { mem.delete(k); } };
  const auth = new GoTrueClient({ url: 'https://stub.invalid/auth/v1', headers: { apikey: 'zz-demo-key' }, storageKey: 'qd-admin-auth', storage,
    persistSession: true, autoRefreshToken: false, detectSessionInUrl: false, fetch });
  return { st, auth };
}

test('the first time: e-mail, then ENROL (not a refusal), a wrong code is rejected, the right one makes the session aal2', async () => {
  const { st, auth } = stubAuth();
  assert.equal((await standing(auth)).step, 'email', 'no session yet: the e-mail step');

  // Step 1 is login_otp's session (aal1), adopted the way the page adopts it.
  const { error } = await auth.setSession({ access_token: tok('aal1'), refresh_token: 'zz-r1' });
  assert.equal(error, null);
  assert.equal((await standing(auth)).step, 'enrol', 'an admin with no authenticator is sent to enrolment');

  const e = await startEnrolment(auth, new Date('2026-11-10T12:00:00Z'));
  assert.match(e.qr, /^data:image\/svg\+xml/);
  assert.equal(e.secret, 'ZZDEMOSECRET1');
  assert.deepEqual(st.enrolBodies, [{ factor_type: 'totp', issuer: 'QuotesDone', friendly_name: 'QuotesDone admin 2026-11-10' }]);

  assert.deepEqual(await verifyCode(auth, e.factorId, '12345'), { ok: false, reason: 'format' }, 'five digits never reach the server');
  assert.deepEqual(await verifyCode(auth, e.factorId, '111 111'), { ok: false, reason: 'rejected' });
  assert.equal((await auth.mfa.getAuthenticatorAssuranceLevel()).data.currentLevel, 'aal1', 'a wrong code leaves the session at aal1');

  assert.deepEqual(await verifyCode(auth, e.factorId, '246 810'), { ok: true });
  assert.equal((await auth.mfa.getAuthenticatorAssuranceLevel()).data.currentLevel, 'aal2');
  const s = await standing(auth);
  assert.equal(s.step, 'done');
  assert.equal(s.factor?.id, e.factorId);
});

test('a later sign-in with an enrolled authenticator is a CHALLENGE, and passing it is aal2', async () => {
  const { auth } = stubAuth();
  await auth.setSession({ access_token: tok('aal1'), refresh_token: 'zz-r1' });
  const e = await startEnrolment(auth);
  assert.deepEqual(await verifyCode(auth, e.factorId, '246810'), { ok: true });
  await auth.signOut();
  assert.equal((await standing(auth)).step, 'email');

  await auth.setSession({ access_token: tok('aal1'), refresh_token: 'zz-r3' });
  const s = await standing(auth);
  assert.equal(s.step, 'challenge', 'one verified authenticator: the code, not a second enrolment');
  assert.deepEqual(await verifyCode(auth, s.factor.id, '246810'), { ok: true });
  assert.equal((await standing(auth)).step, 'done');
});

test('a QR shown and never confirmed is removed before a new enrolment starts', async () => {
  const { st, auth } = stubAuth();
  await auth.setSession({ access_token: tok('aal1'), refresh_token: 'zz-r1' });
  const first = await startEnrolment(auth);
  const second = await startEnrolment(auth);
  assert.notEqual(first.factorId, second.factorId);
  assert.ok(st.calls.includes(`DELETE /auth/v1/factors/${first.factorId}`), 'the abandoned factor was unenrolled');
  assert.deepEqual(st.factors.map((f) => f.id), [second.factorId], 'one factor left, and it is the new one');
  assert.equal((await standing(auth)).step, 'enrol', 'still enrolment: an unverified factor opens nothing');
});
