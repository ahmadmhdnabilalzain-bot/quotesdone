// WHERE HE WORKS IS ONE LIST (12 Nov 2026, sales_engineer, built by it_engineer; walk of 12 Nov 2026, blocker B1).
// Replayed against an in-memory database through the real writers: the Services save (servicesSaveRewrite -> capabilityConfirm),
// the Profile save (supplier_api save_profile, the handler itself) and the reads both screens draw (servicesState, `me`).
// "What the matcher holds" is fn_match_capability's `loc` CTE as it is live (read 12 Nov 2026; the last definition is
// scripts/sql/the_sales_engineer_owns_onboarding_performance_and_supply_gaps.sql:392-393): the distinct lower-cased union of
// supplier_capabilities.coverage_emirates and leads.service_emirates. fn_sales_engineer_supply_gap reads the same union.
// Known-bad control: on origin/main each save wrote only its own column, so after unticking Sharjah in either place the
// union still held 'sharjah' and the first two tests fail; the two screens also showed different lists (the third test).
//   deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY supabase/functions/_shared/where_he_works.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { emirateList, homeEmirateFor, leadColumnsFor } from './where_he_works.ts';
import { servicesSaveRewrite, servicesState } from './supplier_services.ts';
import { supplierOf } from '../supplier_api/lib/me_row.ts';

type Row = Record<string, unknown>;
const ID = 7;

/** A PostgREST-shaped stub over named tables: .eq filters, reads resolve to the rows, writes are applied in memory. */
function fakeDb(lead: Row, cap: Row) {
  const tables: Record<string, Row[]> = {
    leads: [lead],
    supplier_capabilities: [cap],
    supplier_capability_confirmation: [],
    taxonomy_trade_service: [{ trade_code: 'gypsum', code: 'false_ceiling', label_en: 'False ceilings', label_ar: 'أسقف معلقة', sort: 1, active: true }],
    taxonomy_trade: [{ code: 'gypsum', label: 'Gypsum', label_ar: 'جبس', active: true }],
    taxonomy_role: [{ code: 'contractor', label: 'Contractor', active: true }],
  };
  const from = (table: string) => {
    const rows = () => tables[table] ||= [];
    const filters: [string, unknown][] = [];
    let op: { kind: 'read' } | { kind: 'update'; v: Row } | { kind: 'upsert'; v: Row } | { kind: 'insert'; v: Row } = { kind: 'read' };
    let lo = 0, hi = Infinity;   // .range() pages, as PostgREST does: past the last row a page is empty
    const hit = () => rows().filter((r) => filters.every(([k, v]) => String(r[k]) === String(v))).slice(lo, hi + 1);
    const run = () => {
      const o = op;
      if (o.kind === 'update') { for (const r of hit()) Object.assign(r, o.v); return { data: null, error: null }; }
      if (o.kind === 'upsert') { const r = rows().find((x) => x.supplier_id === o.v.supplier_id); if (r) Object.assign(r, o.v); else rows().push({ ...o.v }); return { data: null, error: null }; }
      if (o.kind === 'insert') { rows().push(o.v); return { data: null, error: null }; }
      return { data: hit(), error: null };
    };
    const b: Record<string, unknown> = {};
    const self = () => b;
    Object.assign(b, {
      select: self, in: self, order: self, limit: self, range: (a: number, z: number) => { lo = a; hi = z; return b; }, is: self, neq: self, not: self, gte: self, lte: self,
      eq: (k: string, v: unknown) => { filters.push([k, v]); return b; },
      update: (v: Row) => { op = { kind: 'update', v }; return b; },
      upsert: (v: Row) => { op = { kind: 'upsert', v }; return b; },
      insert: (v: Row) => { op = { kind: 'insert', v }; return b; },
      maybeSingle: () => Promise.resolve(run()).then((r) => {
        if (op.kind !== 'read') return r;
        const one = table === 'supplier_capability_confirmation' ? hit().at(-1) : hit()[0];
        // `me` embeds the capability row (supplier_capabilities(coverage_emirates)), as PostgREST answers a one-to-one embed
        if (one && table === 'leads') return { data: { ...one, supplier_capabilities: tables.supplier_capabilities.find((c) => c.supplier_id === one.id) ?? null }, error: null };
        return { data: one ?? null, error: null };
      }),
      single: () => Promise.resolve({ data: hit()[0] ?? null, error: null }),
      then: (res: (v: unknown) => void, rej?: (e: unknown) => void) => Promise.resolve(run()).then(res, rej),
    });
    return b;
  };
  const rpc = (fn: string) => Promise.resolve(fn === 'fn_sales_engineer_verifies_supplier'
    ? { data: { ok: true, approval_status: 'approved', missing: [], reason: null, licence_expired: false }, error: null }
    : { data: [], error: null });
  return { admin: { from, rpc }, tables };
}

/** fn_match_capability's `loc.stated` for the supplier: what limits the emirates his requests come from. */
function matcherStated(t: Record<string, Row[]>): string[] {
  const l = t.leads.find((r) => r.id === ID)!; const c = t.supplier_capabilities.find((r) => r.supplier_id === ID)!;
  const all = [...(c.coverage_emirates as string[] ?? []), ...(l.service_emirates as string[] ?? [])].map((e) => e.trim().toLowerCase()).filter(Boolean);
  return [...new Set(all)].sort();
}

const approvedLead = (emirates: string[]): Row => ({ id: ID, company_name: 'ZZ DEMO Where He Works LLC', claimed_by: 'zz-demo-where@example.invalid',
  emirate: 'Dubai', approval_status: 'approved', registration_submitted_at: '2026-11-01T00:00:00Z', accepted_terms_at: null, phone: '+971500000099', service_emirates: emirates });
const confirmedCap = (emirates: string[]): Row => ({ supplier_id: ID, trades: ['gypsum'], roles: ['contractor'], services: ['gypsum.false_ceiling'],
  confirmed_at: '2026-11-01T00:00:00Z', confirmed_version: 1, coverage_emirates: emirates });

Deno.test('unticking Sharjah in Services removes it from what the matcher holds, though Profile had it too', async () => {
  const { admin, tables } = fakeDb(approvedLead(['Dubai', 'Sharjah']), confirmedCap(['Dubai', 'Sharjah', 'Ajman']));
  const [s, out] = await servicesSaveRewrite(admin, ID, { roles: ['contractor'], raw_text: '', trades: ['gypsum'], services: ['gypsum.false_ceiling'], coverage_emirates: ['Dubai', 'Ajman'] }, ['Dubai', 'Sharjah']);
  assertEquals(s, 200, JSON.stringify(out));
  assertEquals(matcherStated(tables), ['ajman', 'dubai'], 'Sharjah is still matched after he unticked it in Services');
  assertEquals(tables.leads[0].service_emirates, ['Dubai', 'Ajman']);
  assertEquals(tables.supplier_capabilities[0].coverage_emirates, ['Dubai', 'Ajman']);
});

Deno.test('unticking Sharjah on the Profile save removes it from what the matcher holds, though Services had it too', async () => {
  const { admin, tables } = fakeDb(approvedLead(['Dubai', 'Sharjah']), confirmedCap(['Dubai', 'Sharjah']));
  Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:9'); Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-not-a-key');
  const ctx = await import('../supplier_api/context.ts');
  Object.assign(ctx.admin, { from: admin.from, rpc: admin.rpc });   // the handler's own client, pointed at the stub
  const { profileActions } = await import('../supplier_api/actions/profile.ts');
  const req = new Request('http://127.0.0.1/', { method: 'POST' });
  const res = await profileActions({ req, email: 'zz-demo-where@example.invalid', action: 'save_profile', body: { action: 'save_profile', service_emirates: ['Dubai'] } } as never);
  assertEquals(res?.status, 200, await res?.clone().text());
  assertEquals(matcherStated(tables), ['dubai'], 'Sharjah is still matched after he unticked it on Profile');
  assertEquals(tables.supplier_capabilities[0].coverage_emirates, ['Dubai']);
});

Deno.test('both screens show one list, the one the matcher uses, while the two columns still disagree', async () => {
  const { admin, tables } = fakeDb(approvedLead(['Dubai', 'Sharjah']), confirmedCap(['ajman ', 'Dubai']));
  const st = await servicesState(admin, ID);
  const me = await supplierOf(admin, 'zz-demo-where@example.invalid', () => Promise.resolve(null)) as Row;
  const one = ['Dubai', 'Sharjah', 'Ajman'];
  assertEquals((st.capability as Row).coverage_emirates, one, 'Services "Where you work"');
  assertEquals(st.declared_emirates, one, 'Services, before he confirms');
  assertEquals(me.service_emirates, one, 'Profile');
  assert(!('supplier_capabilities' in me), 'the embedded row is not sent to the browser');
  assertEquals(one.map((e) => e.toLowerCase()).sort(), matcherStated(tables));
});

Deno.test('the list is the seven emirates by their one name, each once, in a fixed order; the home emirate follows it', () => {
  assertEquals(emirateList(['sharjah', 'Dubai '], ['DUBAI', 'Office 505, Business Bay, Dubai, UAE', 'umm  al quwain', null]), ['Dubai', 'Sharjah', 'Umm Al Quwain']);
  assertEquals(emirateList(undefined, 'Dubai'), []);
  assertEquals(homeEmirateFor(['Dubai', 'Ajman'], 'Ajman'), undefined, 'the home emirate still chosen stays');
  assertEquals(homeEmirateFor(['Dubai', 'Ajman'], 'Sharjah'), 'Dubai', 'a home emirate no longer chosen follows the list');
  assertEquals(homeEmirateFor([], 'Sharjah'), undefined, 'UAE-wide leaves the home emirate on file');
  assertEquals(leadColumnsFor(['Ajman'], null), { service_emirates: ['Ajman'], emirate: 'Ajman' });
});
