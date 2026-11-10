// The one door from a JWT to admin power (security checklist audit 10 Nov 2026, item 1). Fails if an admin e-mail on
// an aal1 session is ever admin again, if a non-admin's answer changes, or if the refusal stops naming the step.
// Run: deno test supabase/functions/_shared/admin_session.test.ts. ZZ DEMO identities only; no network.
import { assertEquals, assert } from 'jsr:@std/assert@1';
import { adminCaller, adminList, totpFactor, twoStepBody } from './admin_session.ts';

const b64u = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const now = Math.floor(Date.now() / 1000);
const tok = (p: Record<string, unknown>) => 'Bearer ' + `${b64u({ alg: 'ES256' })}.${b64u({ exp: now + 3600, ...p })}.sig`;
const ADMIN = { id: 'u-admin', email: 'ZZ-Demo-Admin@example.invalid' };
const CUST = { id: 'u-cust', email: 'zz-demo-customer@example.invalid' };
const secrets = async (k: string) => (k === 'admin_emails' ? ' zz-demo-admin@example.invalid ,zz-demo-two@example.invalid' : null);
// deno-lint-ignore no-explicit-any
const auth = (user: any) => ({ auth: { getUser: async () => ({ data: { user }, error: null }) } });
const verified = [{ factor_type: 'totp', status: 'verified' }];

Deno.test('admin_emails is parsed the way every site parsed it: comma list, trimmed, lower-cased, blanks dropped', () => {
  assertEquals(adminList(' A@x.invalid, ,b@X.invalid,'), ['a@x.invalid', 'b@x.invalid']);
  assertEquals(adminList(undefined), []);
});

Deno.test('an admin e-mail on an aal2 session is the admin', async () => {
  const r = await adminCaller(auth({ ...ADMIN, factors: verified }), secrets, tok({ sub: ADMIN.id, aal: 'aal2' }));
  assertEquals(r, { kind: 'admin', email: 'zz-demo-admin@example.invalid', userId: ADMIN.id });
});

Deno.test('an admin e-mail on an aal1 session is refused 403 and told the step: challenge when enrolled', async () => {
  const r = await adminCaller(auth({ ...ADMIN, factors: verified }), secrets, tok({ sub: ADMIN.id, aal: 'aal1' }));
  assertEquals(r.kind, 'two_step_required');
  if (r.kind !== 'two_step_required') return;
  assertEquals(r.status, 403);
  assertEquals(r.body.step, 'challenge');
  assert(r.body.message.startsWith('Two-step sign-in required'));
  assert(!JSON.stringify(r.body).includes('@'), 'the refusal carries no e-mail');
});

Deno.test('no authenticator enrolled (or only a half-finished one) sends the admin to enrolment, never a dead end', async () => {
  for (const factors of [undefined, [], [{ factor_type: 'totp', status: 'unverified' }]]) {
    const r = await adminCaller(auth({ ...ADMIN, factors }), secrets, tok({ sub: ADMIN.id, aal: 'aal1' }));
    assertEquals(r.kind === 'two_step_required' && r.body.step, 'enrol');
  }
  // A token with no aal claim at all is not aal2.
  const r = await adminCaller(auth({ ...ADMIN, factors: verified }), secrets, tok({ sub: ADMIN.id }));
  assertEquals(r.kind, 'two_step_required');
});

Deno.test('a phone factor is not the authenticator this estate enrols (phone MFA costs money: ledger 1606)', () => {
  assertEquals(totpFactor({ id: 'x', factors: [{ factor_type: 'phone', status: 'verified' }] }), 'none');
  assertEquals(twoStepBody('none').step, 'enrol');
});

Deno.test('a non-admin is not_admin on aal1 and aal2 alike, so its own path runs unchanged', async () => {
  for (const aal of ['aal1', 'aal2']) {
    assertEquals(await adminCaller(auth(CUST), secrets, tok({ sub: CUST.id, aal })), { kind: 'not_admin', email: CUST.email, userId: CUST.id });
  }
});

Deno.test('an admin e-mail resolved from a token whose subject is someone else is no session', async () => {
  const r = await adminCaller(auth({ ...ADMIN, factors: verified }), secrets, tok({ sub: 'u-other', aal: 'aal2' }));
  assertEquals(r, { kind: 'signed_out', status: 401, reason: 'subject_mismatch' });
});

Deno.test('no session, and an auth outage, are signed_out with signedInUser\'s status, and admin_emails is never read', async () => {
  let reads = 0;
  const count = async (k: string) => { reads++; return secrets(k); };
  assertEquals(await adminCaller(auth(null), count, ''), { kind: 'signed_out', status: 401, reason: 'malformed' });
  const hang = { auth: { getUser: () => new Promise<never>(() => {}) } };
  assertEquals(await adminCaller(hang, count, tok({ sub: ADMIN.id, aal: 'aal2' }), 30), { kind: 'signed_out', status: 503, reason: 'auth_timeout' });
  assertEquals(reads, 0);
});
