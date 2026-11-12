// THE READS AND WRITES THIS BRANCH ADDED ARE BUILT BY THE REAL supabase-js CLIENT (12 Nov 2026, customer_support; round-2 review of
// the portal shell). The first version called `q.imatch(...)`, which supabase-js does not have: every registration threw
// "q.imatch is not a function", while 235 tests passed against an in-memory table that defined its own imatch. Here the REAL jsr
// client builds every request createCompany (supplier_api) and nameFromLicence / buildNotifications (supplier_portal) make; fetch is
// replaced, so nothing leaves the process, and each URL is read back.
//   deno test -A --no-lock supabase/functions/supplier_api/create_company.real_client.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { createCompany, listingProbes } from './create_company.ts';
import { buildNotifications, nameFromLicence } from '../supplier_portal/overview.ts';

type Seen = { method: string; url: URL; body: string | null };
function realClient(answer: (s: Seen) => unknown = () => []) {
  const seen: Seen[] = [];
  const fetch = (input: Request | URL | string, init?: RequestInit) => {
    const s = { method: (init?.method || 'GET').toUpperCase(), url: new URL(typeof input === 'string' || input instanceof URL ? String(input) : input.url), body: (init?.body as string) ?? null };
    seen.push(s);
    return Promise.resolve(new Response(JSON.stringify(answer(s)), { status: 200, headers: { 'content-type': 'application/json' } }));
  };
  return { admin: createClient('http://stub.invalid', 'zz-demo-key', { auth: { persistSession: false }, global: { fetch } }), seen };
}

Deno.test('createCompany builds its listing read on the REAL client: filter imatch, both words, no throw', async () => {
  const { admin, seen } = realClient((s) => (s.method === 'POST' ? [{ id: 900777 }] : []));
  const name = "ZZ DEMO Mu'min (Al-Noor) & Sons Trading L.L.C.";
  const r = await createCompany(admin, 'qd-real-client@example.invalid', { company_name: name, role: 'supplier' }, {
    emailProven: () => Promise.resolve(true), sessionByCode: true, sanctionedLead: () => Promise.resolve(false),
    setRegistration: () => Promise.resolve(null), recordFirstTouch: () => Promise.resolve(), locale: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.body));
  const listing = seen.find((s) => s.url.pathname.endsWith('/leads') && s.url.searchParams.getAll('company_name').some((v) => v.startsWith('imatch.')));
  assert(listing, 'no listing read with company_name=imatch.<pattern>: ' + seen.map((s) => s.url.search).join(' | '));
  const sent = listing.url.searchParams.getAll('company_name').filter((v) => v.startsWith('imatch.')).map((v) => v.slice('imatch.'.length));
  assertEquals(sent, listingProbes(name), 'the client sent the patterns unchanged');
  assertEquals(listing.url.searchParams.get('claimed_by'), 'is.null');
  assertEquals(listing.url.searchParams.get('limit'), '300');
  // a pattern is letters, digits and two fixed character classes; nothing PostgREST reads as syntax in a plain column filter
  for (const p of sent) assert(!/[(),"]/.test(p), 'a pattern carries PostgREST syntax: ' + p);
  assert(seen.some((s) => s.method === 'POST' && s.url.pathname.endsWith('/leads')), 'the new row was not inserted');
});

Deno.test('nameFromLicence and buildNotifications build their reads on the REAL client', async () => {
  const { admin, seen } = realClient((s) => (s.url.pathname.endsWith('/agent_actions') ? [{ detail: { new_name: 'ZZ DEMO X LLC' } }] : []));
  assertEquals(await nameFromLicence(admin as never, { id: 7, company_name: 'ZZ DEMO X LLC' }), true);
  const aa = seen.find((s) => s.url.pathname.endsWith('/agent_actions'))!;
  assertEquals([aa.url.searchParams.get('agent'), aa.url.searchParams.get('kind'), aa.url.searchParams.get('target_id'), aa.url.searchParams.get('order'), aa.url.searchParams.get('limit')],
    ['eq.sales_engineer', 'eq.supplier_name_from_licence', 'eq.7', 'id.desc', '1']);
  const n = await buildNotifications(admin as never, 7);
  assertEquals(n.notices, []);
  assert(seen.some((s) => s.url.pathname.endsWith('/notifications') && (s.url.searchParams.get('select') || '').includes('failover_of')));
});
