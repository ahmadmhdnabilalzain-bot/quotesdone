// A PHONE SIGNS IN ONLY TO A ROW WHOSE PHONE AND EMAIL ARE VERIFIED (13 Oct 2026, security review).
// An unverified number on an attacker's own row must not capture the handset owner's sign-in.
// The harness ignores PostgREST filters, so `handle` applies the eq.true filters the way the database would.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, REAL_LOOKING, type Stub } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('login_otp', () => import('./index.ts'));
const approved = (_r: Request, u: URL) => u.pathname.endsWith('/VerificationCheck') ? new Response(JSON.stringify({ status: 'approved' }), { headers: { 'content-type': 'application/json' } }) : undefined;
const minted = (calls: { url: string }[]) => calls.some((c) => c.url.includes('/auth/v1/admin/generate_link'));

function holds(table: 'customers' | 'leads', row: Record<string, unknown>): Stub {
  return {
    twilio: approved,
    handle: (req, u) => {
      if (req.method !== 'GET' || !u.pathname.endsWith('/rest/v1/' + table)) return undefined;
      const ok = [...u.searchParams].every(([k, v]) => v !== 'eq.true' || row[k] === true);
      return new Response(JSON.stringify(ok ? [row] : []), { headers: { 'content-type': 'application/json' } });
    },
  };
}
const verify = (kind: string, stub: Stub) => fn().then((h) => invoke(h, stub, { action: 'verify', user_kind: kind, identifier: REAL_LOOKING, code: '123456' }));

const cust = (pv: boolean, ev: boolean) => holds('customers', { email: 'qd-stub-cust@example.invalid', phone: REAL_LOOKING, phone_verified: pv, email_verified: ev });
const lead = (pv: boolean, ev: boolean) => holds('leads', { claimed_by: 'qd-stub-sup@example.invalid', id: 7, phone: REAL_LOOKING, owner_phone_verified: pv, owner_email_verified: ev });

Deno.test('customer: an unverified phone gets no_account_for_number and no session', async () => {
  const v = await verify('customer', cust(false, true));
  assertEquals([v.status, v.json.code], [404, 'no_account_for_number'], JSON.stringify(v.json));
  assert(!minted(v.calls));
});
Deno.test('customer control: phone and email verified signs in', async () => {
  const v = await verify('customer', cust(true, true));
  assert(minted(v.calls), JSON.stringify(v.json));
});
Deno.test('supplier: an unverified owner phone gets no_account_for_number and no session', async () => {
  const v = await verify('supplier', lead(false, true));
  assertEquals([v.status, v.json.code], [404, 'no_account_for_number'], JSON.stringify(v.json));
  assert(!minted(v.calls));
});
Deno.test('supplier control: owner phone and email verified signs in', async () => {
  const v = await verify('supplier', lead(true, true));
  assert(minted(v.calls), JSON.stringify(v.json));
});
