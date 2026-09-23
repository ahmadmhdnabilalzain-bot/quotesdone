// THE SERVICES SAVE, REPLAYED AGAINST AN IN-MEMORY DATABASE. Seat: it_engineer. 21 Sep 2026.
//
// Audit 21 Sep 2026 (ZZ DEMO Interiors, gypsum), findings 9 and 10, replayed through the real
// servicesSaveRewrite and servicesState with a fake `admin` — no network, no production row:
//   9.  a phrase kept "in your own words" must survive Update + reload and come back as the supplier's
//       own words (extra_services), and survive a SECOND Update the client sends without a rewrite;
//   10. "Remove this trade" must drop the trade from supplier_capabilities.trades — including when an
//       own word ("الدهانات") resolves back to that trade — and stay dropped on the next Update.
//
//   deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/supplier_services_save.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { servicesSaveRewrite, servicesState } from './supplier_services.ts';

type Row = Record<string, unknown>;

/** A PostgREST-shaped stub: every read resolves to the table's rows, every write is applied in memory. */
function fakeDb(normTrades: Record<string, string[]>, confirmedAt: string | null = '2026-09-20T00:00:00Z') {
  const cap: Row = { supplier_id: 7, trades: ['gypsum', 'painting'], roles: ['contractor'], services: [], confirmed_at: confirmedAt };
  const tables: Record<string, Row[]> = {
    taxonomy_trade_service: [
      { trade_code: 'gypsum', code: 'false_ceiling', label_en: 'False ceilings', label_ar: 'أسقف معلقة', sort: 1 },
      { trade_code: 'gypsum', code: 'partitions', label_en: 'Gypsum partitions', label_ar: 'قواطع جبس', sort: 2 },
      { trade_code: 'painting', code: 'interior', label_en: 'Interior painting', label_ar: 'دهان داخلي', sort: 1 },
    ],
    taxonomy_trade: [{ code: 'gypsum', label: 'Gypsum', label_ar: 'جبس' }, { code: 'painting', label: 'Painting & finishes', label_ar: 'دهانات' }],
    taxonomy_role: [{ code: 'contractor', label: 'Contractor' }],
    supplier_capabilities: [cap],
  };
  const q = (table: string) => {
    let write: Row | null = null;
    const b: Record<string, unknown> = {};
    const chain = () => b;
    Object.assign(b, {
      select: chain, eq: chain, in: chain, order: chain, limit: chain,
      maybeSingle: async () => ({ data: table === 'supplier_capabilities' ? cap : (tables[table] || [])[0] ?? null, error: null }),
      upsert: (r: Row | Row[]) => { if (table === 'supplier_capabilities') Object.assign(cap, r as Row); write = r as Row; return b; },
      insert: (r: Row) => { write = r; return b; },
      update: (r: Row) => { write = r; return b; },
      then: (res: (v: unknown) => void) => res(write ? { error: null } : { data: tables[table] || [], error: null }),
    });
    return b;
  };
  const admin = {
    from: q,
    rpc: async (_fn: string, args: { p_text: string }) => ({ data: normTrades[args.p_text] || [], error: null }),
  };
  return { admin, cap };
}

const base = { roles: ['contractor'], raw_text: 'نقوم بأعمال الجبس والأسقف المستعارة والدهانات' };

Deno.test('finding 9: an own-words phrase survives Update, reload, and a second Update with no rewrite', async () => {
  const { admin, cap } = fakeDb({});
  const [s1] = await servicesSaveRewrite(admin, 7, { ...base, trades: ['gypsum'], services: ['gypsum.false_ceiling'], own_words: ['تلميع نوافذ المروحيات'] });
  assertEquals(s1, 200);
  const st = await servicesState(admin, 7);
  assertEquals(st.extra_services, ['تلميع نوافذ المروحيات'], 'reload returns the words as the supplier\'s own');
  // The tab, reloaded, re-sends what it holds: the ticks and the stored own words.
  const [s2] = await servicesSaveRewrite(admin, 7, { ...base, trades: ['gypsum'], services: st.selected_services, own_words: st.extra_services });
  assertEquals(s2, 200);
  assert((cap.services as string[]).includes('تلميع نوافذ المروحيات'), JSON.stringify(cap.services));
});

Deno.test('finding 10: a removed trade is dropped, even when an own word resolves back to it', async () => {
  const { admin, cap } = fakeDb({ 'الدهانات': ['painting'] });
  const [s, out] = await servicesSaveRewrite(admin, 7, {
    ...base, trades: ['gypsum'], removed_trades: ['painting'],
    services: ['gypsum.false_ceiling', 'painting.interior'], own_words: ['الدهانات'],
  });
  assertEquals(s, 200, JSON.stringify(out));
  assertEquals(cap.trades, ['gypsum']);
  assert(!(cap.services as string[]).includes('painting.interior'));
});

Deno.test('finding 10: the removal holds on the NEXT Update, when stored own words are re-sent', async () => {
  const { admin, cap } = fakeDb({ 'الدهانات': ['painting'] });
  // First save: the word is new, resolves to painting, and painting is on the card list.
  await servicesSaveRewrite(admin, 7, { ...base, trades: ['gypsum', 'painting'], services: ['gypsum.false_ceiling'], own_words: ['الدهانات'] });
  assertEquals([...(cap.trades as string[])].sort(), ['gypsum', 'painting']);
  // The supplier removes the painting card and presses Update.
  await servicesSaveRewrite(admin, 7, { ...base, trades: ['gypsum'], removed_trades: ['painting'], services: ['gypsum.false_ceiling'], own_words: ['الدهانات'] });
  assertEquals(cap.trades, ['gypsum']);
  // Reload and Update again, with no removal in hand: the stored word must not bring painting back.
  const st = await servicesState(admin, 7);
  await servicesSaveRewrite(admin, 7, { ...base, trades: st.checklist.map((c) => c.code), services: st.selected_services, own_words: st.extra_services });
  assertEquals(cap.trades, ['gypsum']);
});

// ── THE FIRST VISIT STARTS UNTICKED (founder_instruction 862, 23 Sep 2026) ─────────────────────────────
// "for suppliers it's as I told you it start unticked". Until this change servicesState ticked every
// service of every prepared trade — including trades the sales engineer only inferred — and the Services
// tab re-sends what services_state gave it, so one press of Confirm stored all of them as services the
// supplier stated. Under founder_instruction 857 a stated service is one he CONFIRMED he does. These
// replay that exact client: read the state, tick (or not), send back what it holds.
Deno.test('862: a first visit ticks nothing, and pressing Confirm untouched saves no service and confirms nothing', async () => {
  const { admin, cap } = fakeDb({}, null);
  const st = await servicesState(admin, 7);
  assertEquals(st.first_run, true);
  assertEquals(st.checklist.map((c) => c.code), ['gypsum', 'painting'], 'the prepared trades are still offered');
  assertEquals(st.selected_services, [], 'the first visit must start with nothing ticked');
  // The tab sends back exactly what it holds, with nothing ticked.
  const [s, out] = await servicesSaveRewrite(admin, 7, { ...base, trades: st.checklist.map((c) => c.code), services: st.selected_services, own_words: [] });
  assertEquals(s, 400, JSON.stringify(out));
  assertEquals((out as Row).code, 'services_none_ticked');
  assertEquals(cap.confirmed_at, null, 'an empty portfolio must not be confirmed as complete');
  assertEquals(cap.services, [], 'no service he did not tick may be stored as his');
});

Deno.test('862: a first visit saves exactly the services he ticked himself, and nothing else', async () => {
  const { admin, cap } = fakeDb({}, null);
  const st = await servicesState(admin, 7);
  const mine = ['gypsum.partitions'];
  const [s, out] = await servicesSaveRewrite(admin, 7, { ...base, trades: st.checklist.map((c) => c.code), services: [...st.selected_services, ...mine], own_words: [] });
  assertEquals(s, 200, JSON.stringify(out));
  assertEquals(cap.services, mine, 'only the service he ticked is stated');
  assert(cap.confirmed_at, 'a portfolio with a ticked service is confirmed');
});

Deno.test('862: the older capability_confirm route refuses an empty portfolio too', async () => {
  const { admin, cap } = fakeDb({}, null);
  const { capabilityConfirm } = await import('./supplier_capability.ts');
  const [s, out] = await capabilityConfirm(admin, 7, { trades: ['gypsum'], roles: ['contractor'], services: [] });
  assertEquals(s, 400, JSON.stringify(out));
  assertEquals((out as Row).code, 'services_none_ticked');
  assertEquals(cap.confirmed_at, null);
});
