// A NUMBER ABROAD THAT ENDS IN THE SAME NINE DIGITS IS NOT THE ACCOUNT (security review 17 Nov 2026). +44 7501 234567 and
// +971 50 123 4567 share their last nine digits; the phone door matched `ilike '%' || last9`, so the holder of the UK
// number proved HIS handset and was handed the UAE customer's session. The door now asks for the whole E.164 number.
// The harness ignores PostgREST filters, so `handle` applies the phone filter the way PostgREST would (eq, or ilike '%tail').
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, REAL_LOOKING, type Stub } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('login_otp', () => import('./index.ts'));
const approved = (_r: Request, u: URL) => u.pathname.endsWith('/VerificationCheck') ? new Response(JSON.stringify({ status: 'approved' }), { headers: { 'content-type': 'application/json' } }) : undefined;
const minted = (calls: { url: string }[]) => calls.some((c) => c.url.includes('/auth/v1/admin/generate_link'));
const ABROAD = '+44' + '7' + REAL_LOOKING.slice(-9);   // a UK mobile ending in the same nine digits

function phoneMatches(filter: string | null, phone: string): boolean {
  if (filter === null) return true;
  if (filter.startsWith('eq.')) return filter.slice(3) === phone;
  if (filter.startsWith('ilike.%')) return phone.endsWith(filter.slice(7));
  return false;
}
function holds(table: 'customers' | 'leads', row: Record<string, unknown>): Stub {
  return {
    twilio: approved,
    handle: (req, u) => {
      if (req.method !== 'GET' || !u.pathname.endsWith('/rest/v1/' + table)) return undefined;
      const ok = [...u.searchParams].every(([k, v]) => v !== 'eq.true' || row[k] === true) && phoneMatches(u.searchParams.get('phone'), String(row.phone));
      return new Response(JSON.stringify(ok ? [row] : []), { headers: { 'content-type': 'application/json' } });
    },
  };
}
const cust = holds('customers', { email: 'qd-stub-cust@example.invalid', phone: REAL_LOOKING, phone_verified: true, email_verified: true });
const lead = holds('leads', { claimed_by: 'qd-stub-sup@example.invalid', id: 7, phone: REAL_LOOKING, owner_phone_verified: true, owner_email_verified: true });
const verify = (kind: string, id: string, stub: Stub) => fn().then((h) => invoke(h, stub, { action: 'verify', user_kind: kind, identifier: id, code: '123456' }));

for (const [kind, stub] of [['customer', cust], ['supplier', lead]] as const) {
  Deno.test(`${kind}: a number abroad with the same last nine digits gets no session`, async () => {
    const v = await verify(kind, ABROAD, stub);
    assertEquals([v.status, v.json.code], [404, 'no_account_for_number'], JSON.stringify(v.json));
    assert(!minted(v.calls));
  });
  Deno.test(`${kind} control: the whole number, typed in local form, signs in`, async () => {
    const v = await verify(kind, '0' + REAL_LOOKING.slice(-9), stub);
    assert(minted(v.calls), JSON.stringify(v.json));
  });
}
