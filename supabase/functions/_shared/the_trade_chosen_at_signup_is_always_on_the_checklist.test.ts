// THE TRADE A SUPPLIER CHOSE AT SIGN-UP IS ON HIS SERVICES CHECKLIST, AND CONFIRMABLE, WHEN NOTHING WAS PROPOSED.
// Seat: customer_support. 11 Nov 2026, supplier registration certification (ruling 1620), finding 4.
//
// Measured in the free round (tags f331a927, 506f549f): with the readers out, J1, J4 and J5 had nothing proposed, the trade
// they picked in "Register your company" (leads.sector, written by create_company) was not on the Services checklist, so
// "Confirm my services" stayed disabled and each stayed "Pending, services unconfirmed". That is every registration during a
// model outage. servicesState is replayed here through a fake `admin`: no network, no production row.
//
//   cd supabase/functions && deno test --no-lock --node-modules-dir=none _shared/the_trade_chosen_at_signup_is_always_on_the_checklist.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { preparedTrades, servicesSaveRewrite, servicesState, signupTradeOf } from './supplier_services.ts';

type Row = Record<string, unknown>;

/** A PostgREST-shaped stub. `cap` null = the new supplier has no supplier_capabilities row yet (the free round's case). */
function fakeDb(sector: string | null, cap: Row | null) {
  const tables: Record<string, Row[]> = {
    taxonomy_trade_service: [
      { trade_code: 'building_materials', code: 'cement_supply', label_en: 'Cement and aggregates supply', label_ar: '', sort: 1 },
      { trade_code: 'building_materials', code: 'blocks_supply', label_en: 'Blocks supply', label_ar: '', sort: 2 },
      { trade_code: 'plumbing', code: 'sanitary_ware', label_en: 'Sanitary ware', label_ar: '', sort: 1 },
    ],
    taxonomy_trade: [{ code: 'building_materials', label: 'Building materials' }, { code: 'plumbing', label: 'Plumbing' }],
    taxonomy_role: [{ code: 'trader', label: 'Trader' }],
    leads: [{ id: 7, sector }],
    supplier_capability_confirmation: [],
  };
  let capRow: Row | null = cap;
  const q = (table: string) => {
    let write: Row | null = null;
    let lo = 0, hi = Infinity; // .range() pages as PostgREST does: past the last row a page is empty
    const b: Record<string, unknown> = {};
    const chain = () => b;
    Object.assign(b, {
      select: chain, eq: chain, in: chain, order: chain, limit: chain,
      range: (a: number, z: number) => { lo = a; hi = z; return b; },
      maybeSingle: async () => ({ data: table === 'supplier_capabilities' ? capRow : table === 'supplier_capability_confirmation' ? tables[table].at(-1) ?? null : (tables[table] || [])[0] ?? null, error: null }),
      upsert: (r: Row) => { if (table === 'supplier_capabilities') capRow = { ...(capRow || {}), ...r }; write = r; return b; },
      insert: (r: Row) => { if (table === 'supplier_capability_confirmation') tables[table].push(r); write = r; return b; },
      update: (r: Row) => { if (table === 'supplier_capabilities') capRow = { ...(capRow || {}), ...r }; write = r; return b; },
      then: (res: (v: unknown) => void) => res(write ? { error: null } : { data: (tables[table] || []).slice(lo, hi + 1), error: null }),
    });
    return b;
  };
  return { admin: { from: q, rpc: async () => ({ data: [], error: null }) }, cap: () => capRow };
}

Deno.test('nothing proposed, no capability row: the trade chosen at sign-up is on the checklist with its services', async () => {
  const { admin } = fakeDb('building_materials', null);
  const st = await servicesState(admin, 7);
  assertEquals(st.checklist.map((t) => [t.code, t.source]), [['building_materials', 'signup']]);
  assertEquals(st.checklist[0].services.map((s) => s.key), ['building_materials.cement_supply', 'building_materials.blocks_supply']);
  assertEquals(st.selected_services, [], 'offered, never ticked for him (founder 862)');
});

Deno.test('the chosen trade is confirmable: a confirm naming it is accepted and stored as his', async () => {
  const { admin, cap } = fakeDb('building_materials', null);
  const st = await servicesState(admin, 7);
  const [s, out] = await servicesSaveRewrite(admin, 7, { roles: ['trader'], trades: st.checklist.map((t) => t.code), services: ['building_materials.cement_supply'] });
  assertEquals(s, 200, JSON.stringify(out));
  assert(((cap()?.trades as string[]) || []).includes('building_materials'), JSON.stringify(cap()));
});

Deno.test('the chosen trade sits beside what is on file and what the documents propose, never twice', () => {
  const cap = { trades: ['plumbing'], proposed_trades: ['building_materials', 'plumbing'] };
  assertEquals(preparedTrades(cap, false, {}, 'building_materials'), [
    { code: 'plumbing', source: 'on_file' }, { code: 'building_materials', source: 'signup' },
  ]);
  assertEquals(preparedTrades(cap, false, {}, 'plumbing'), [
    { code: 'plumbing', source: 'on_file' }, { code: 'building_materials', source: 'documents' },
  ]);
});

Deno.test('after a confirm the list is what he confirmed: a trade he removed does not come back from sign-up', () => {
  assertEquals(preparedTrades({ trades: ['plumbing'] }, true, {}, 'building_materials'), [{ code: 'plumbing', source: 'confirmed' }]);
});

Deno.test('"my trade isn\'t listed" words are not a code, so they are not offered as a checklist trade', async () => {
  const vocab = [{ code: 'building_materials' }];
  assertEquals(signupTradeOf('building_materials', vocab), 'building_materials');
  assertEquals(signupTradeOf('Helicopter window polishing', vocab), null);
  assertEquals(signupTradeOf(null, vocab), null);
  const { admin } = fakeDb('Helicopter window polishing', null);
  assertEquals((await servicesState(admin, 7)).checklist, []);
});
