// THE CROSS-ROLE REFUSAL COMES ONLY AFTER THE CODE (6 Oct 2026, review of #1245). role_guard no longer
// says before a code is sent whether an address or number belongs to the other role; login_otp says it
// at verify, once the caller has proved the mailbox or the handset, and mints no session when it does.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, REAL_LOOKING, type Stub } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('login_otp', () => import('./index.ts'));
const approved = (_r: Request, u: URL) => u.pathname.endsWith('/VerificationCheck') ? new Response(JSON.stringify({ status: 'approved' }), { headers: { 'content-type': 'application/json' } }) : undefined;
const minted = (calls: { url: string }[]) => calls.some((c) => c.url.includes('/auth/v1/admin/generate_link'));
// A supplier holds the number / address; no customer row does.
const supplierHolds: Stub = { rows: { leads: [{ claimed_by: 'qd-stub-sup@example.invalid', id: 7 }] }, twilio: approved };

Deno.test('phone: a customer sign-in on a supplier number is texted, then refused at verify with no session', async () => {
  const send = await invoke(await fn(), supplierHolds, { action: 'send', user_kind: 'customer', identifier: REAL_LOOKING });
  assertEquals(send.status, 200, JSON.stringify(send.json));
  assertEquals(send.twilio.length, 1, 'the code goes to the handset before anything is said about the role');
  const v = await invoke(await fn(), supplierHolds, { action: 'verify', user_kind: 'customer', identifier: REAL_LOOKING, code: '123456' });
  assertEquals(v.status, 409, JSON.stringify(v.json));
  assertEquals([v.json.code, v.json.conflict], ['role_conflict', 'supplier']);
  assert(!minted(v.calls), 'a role conflict must not mint a session');
});

Deno.test('phone: a wrong code on that number says only "wrong code", never the role', async () => {
  const v = await invoke(await fn(), { ...supplierHolds, twilio: undefined }, { action: 'verify', user_kind: 'customer', identifier: REAL_LOOKING, code: '000000' });
  assertEquals(v.status, 400);
  assertEquals(v.json.code, 'wrong_code');
});

Deno.test('phone control: the number\'s own role signs in, with no conflict', async () => {
  const v = await invoke(await fn(), supplierHolds, { action: 'verify', user_kind: 'supplier', identifier: REAL_LOOKING, code: '123456' });
  assert(v.json?.code !== 'role_conflict', JSON.stringify(v.json));
  assert(minted(v.calls), 'the control must reach the session step, or it proves nothing');
});

Deno.test('phone control: a number nobody holds is still refused before any text', async () => {
  const send = await invoke(await fn(), {}, { action: 'send', user_kind: 'customer', identifier: REAL_LOOKING });
  assertEquals(send.status, 404);
  assertEquals(send.twilio.length, 0);
});

Deno.test('email: a customer sign-in on a supplier address is refused after the code, with no session', async () => {
  const stub: Stub = { ...supplierHolds, rpc: { rl_check: true, fn_login_otp_email_verify: 'ok' } };
  const v = await invoke(await fn(), stub, { action: 'verify', user_kind: 'customer', identifier: 'qd-stub-sup@example.invalid', code: '123456' });
  assertEquals(v.status, 409, JSON.stringify(v.json));
  assertEquals([v.json.code, v.json.conflict], ['role_conflict', 'supplier']);
  assert(!minted(v.calls));
});

Deno.test('email: a wrong code never reaches the role check', async () => {
  const stub: Stub = { ...supplierHolds, rpc: { rl_check: true, fn_login_otp_email_verify: 'wrong' } };
  const v = await invoke(await fn(), stub, { action: 'verify', user_kind: 'customer', identifier: 'qd-stub-sup@example.invalid', code: '000000' });
  assertEquals(v.json.code, 'wrong_code');
  assert(!v.calls.some((c) => c.url.includes('/rest/v1/leads')), 'the role was looked up before the code was proved');
});
