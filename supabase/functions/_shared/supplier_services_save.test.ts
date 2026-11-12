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
    // The confirmation ledger, newest last: capabilityConfirm reads the latest version and inserts the next one.
    supplier_capability_confirmation: [],
  };
  const q = (table: string) => {
    let write: Row | null = null;
    let lo = 0, hi = Infinity; // .range() pages, as PostgREST does: past the last row a page is empty
    const b: Record<string, unknown> = {};
    const chain = () => b;
    Object.assign(b, {
      select: chain, eq: chain, in: chain, order: chain, limit: chain,
      range: (a: number, z: number) => { lo = a; hi = z; return b; },
      maybeSingle: async () => ({ data: table === 'supplier_capabilities' ? cap : table === 'supplier_capability_confirmation' ? tables[table].at(-1) ?? null : (tables[table] || [])[0] ?? null, error: null }),
      upsert: (r: Row | Row[]) => { if (table === 'supplier_capabilities') Object.assign(cap, r as Row); write = r as Row; return b; },
      insert: (r: Row) => { if (table === 'supplier_capability_confirmation') tables[table].push(r); write = r; return b; },
      update: (r: Row) => { write = r; return b; },
      then: (res: (v: unknown) => void) => res(write ? { error: null } : { data: (tables[table] || []).slice(lo, hi + 1), error: null }),
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

// ── WORDS HE NEVER WROTE ARE NOT "KEPT IN YOUR OWN WORDS" (10 Nov 2026, customer_support, supplier-journey audit) ──
// Measured on production 10 Nov 2026: 14,733 of the 14,745 unconfirmed supplier_capabilities rows are review_status
// 'derived' and carry free-text `services` from the directory import ('installation', 'supply', 'construction machinery
// accessories', in 13 rows the company's own name). servicesState gated the TICKED keys on the first run, but returned
// every free-text word as extra_services, which the Services tab shows under "Kept in your own words ... exactly as you
// wrote them" and re-sends as own_words on Confirm. Pressing Confirm untouched therefore confirmed him, with services
// nobody stated, past the very "nothing ticked is not a confirmation" rule the tests above pin: two readings of one
// rule (ticked was first-run aware, extras were not). An unconfirmed row holds nothing that is his.
Deno.test('862: a derived row\'s words are not offered as his own, and Confirm untouched still confirms nothing', async () => {
  const { admin, cap } = fakeDb({}, null);
  cap.services = ['installation', 'supply'];   // what the directory import left on a derived row
  const st = await servicesState(admin, 7);
  assertEquals(st.first_run, true);
  assertEquals(st.extra_services, [], 'a word the import wrote is not the supplier\'s own word');
  const [s, out] = await servicesSaveRewrite(admin, 7, { ...base, trades: st.checklist.map((c) => c.code), services: st.selected_services, own_words: st.extra_services });
  assertEquals(s, 400, JSON.stringify(out));
  assertEquals((out as Row).code, 'services_none_ticked');
  assertEquals(cap.confirmed_at, null, 'nothing he stated, so nothing is confirmed');
});

Deno.test('862: the older capability_confirm route refuses an empty portfolio too', async () => {
  const { admin, cap } = fakeDb({}, null);
  const { capabilityConfirm } = await import('./supplier_capability.ts');
  const [s, out] = await capabilityConfirm(admin, 7, { trades: ['gypsum'], roles: ['contractor'], services: [] });
  assertEquals(s, 400, JSON.stringify(out));
  assertEquals((out as Row).code, 'services_none_ticked');
  assertEquals(cap.confirmed_at, null);
});

// ── A CONFIRM WITH A TRADE ANSWERS BEFORE REASONING (27 Oct 2026, sales_engineer) ──────────────────────────────
// Measured on production (supplier registration walk): reading three own words by reasoning kept the confirm open
// 37-67 s, and a browser whose path gives up near 30 s said "Could not save your services." for a save that landed.
// When the save already names a trade it is confirmed and answered at once; the words are read after the response.
const proposalsOf = (admin: { from: (t: string) => Record<string, unknown> }) => {
  const seen: Row[] = [];
  const from = admin.from;
  admin.from = (t: string) => {
    const b = from(t);
    if (t === 'taxonomy_trade_proposal') { const up = b.upsert as (r: Row[]) => unknown; b.upsert = (r: Row[]) => { seen.push(...r); return up(r); }; }
    return b;
  };
  return seen;
};
const gate = () => { let open!: () => void; const p = new Promise<void>((r) => { open = r; }); return { p, open }; };

Deno.test('a confirm with a trade answers before reasoning; the trade the words name is added after the answer', async () => {
  const { admin, cap } = fakeDb({});
  const proposals = proposalsOf(admin);
  const g = gate(); const bg: Promise<unknown>[] = []; let reads = 0;
  const reason = async (t: string) => { reads++; await g.p; return t === 'Painting works' ? { codes: ['painting'], held: false } : { codes: [], held: true }; };
  const save = servicesSaveRewrite(admin, 7, { ...base, trades: ['gypsum'], services: ['gypsum.false_ceiling'], own_words: ['Painting works', 'Helicopter window polishing'] }, [],
    { waitUntil: (p) => { bg.push(p); }, reason });
  let timer: ReturnType<typeof setTimeout> | undefined;
  const answered = await Promise.race([save, new Promise((r) => { timer = setTimeout(() => r('still waiting on the reasoning'), 1000); })]);
  clearTimeout(timer);
  assert(Array.isArray(answered), String(answered));
  const [s, out] = answered as [number, Row];
  assertEquals(s, 200, JSON.stringify(out));
  assertEquals(out.reading_words, ['Painting works', 'Helicopter window polishing']);
  assertEquals(cap.trades, ['gypsum'], 'answered with what was known');
  assert(cap.confirmed_at, 'confirmed before the words were read');
  assertEquals(bg.length, 1, 'the reading was handed to waitUntil');
  g.open(); await Promise.all(bg);
  assertEquals(reads, 2);
  assertEquals([...(cap.trades as string[])].sort(), ['gypsum', 'painting'], 'the trade the words named was added');
  assertEquals(proposals.map((r) => r.label_en), ['Helicopter window polishing'], 'words no trade was found for reach the sales engineer');
});

Deno.test('with no trade named yet, the words are read before answering (nothing else to confirm)', async () => {
  const { admin, cap } = fakeDb({});
  const bg: Promise<unknown>[] = [];
  const [s, out] = await servicesSaveRewrite(admin, 7, { ...base, trades: [], services: [], own_words: ['Painting works'] }, [],
    { waitUntil: (p) => { bg.push(p); }, reason: async () => ({ codes: ['painting'], held: false }) });
  assertEquals(s, 200, JSON.stringify(out));
  assertEquals(cap.trades, ['painting']);
  assertEquals(bg.length, 0, 'nothing deferred');
});

Deno.test('a trade the supplier removed stays removed when the deferred reading names it', async () => {
  const { admin, cap } = fakeDb({});
  const bg: Promise<unknown>[] = [];
  const [s] = await servicesSaveRewrite(admin, 7, { ...base, trades: ['gypsum'], removed_trades: ['painting'], services: ['gypsum.false_ceiling'], own_words: ['Painting works'] }, [],
    { waitUntil: (p) => { bg.push(p); }, reason: async () => ({ codes: ['painting'], held: false }) });
  assertEquals(s, 200);
  await Promise.all(bg);
  assertEquals(cap.trades, ['gypsum']);
});

Deno.test('a word that resolves exactly counts at once, with no reasoning and nothing deferred', async () => {
  const { admin, cap } = fakeDb({ 'painting': ['painting'], 'Painting': ['painting'] });
  const bg: Promise<unknown>[] = []; let reads = 0;
  const [s] = await servicesSaveRewrite(admin, 7, { ...base, trades: ['gypsum'], services: ['gypsum.false_ceiling'], own_words: ['painting'] }, [],
    { waitUntil: (p) => { bg.push(p); }, reason: async () => { reads++; return { codes: [], held: true }; } });
  assertEquals(s, 200);
  assertEquals([...(cap.trades as string[])].sort(), ['gypsum', 'painting']);
  assertEquals(reads, 0); assertEquals(bg.length, 0);
});

// ── THE DEFERRED READING NEVER OVERWRITES A NEWER CONFIRM (27 Oct 2026, reviewer) ─────────────────────────────
// The reading runs for 37-67 s after the answer, and the tab reloads at once, so the supplier can save again inside
// that window. The second confirm used to be built from the FIRST save's body, which put back what the newer save had
// changed (services, roles, coverage) and wrote a ledger row for a version he never confirmed. It now adds the trades
// the words named only while the first save is still the latest confirm; otherwise it leaves the newer confirm alone.
Deno.test('a newer save inside the reading window is not overwritten by the deferred confirm', async () => {
  const { admin, cap } = fakeDb({});
  const g = gate(); const bg: Promise<unknown>[] = [];
  const [s1] = await servicesSaveRewrite(admin, 7, { ...base, trades: ['gypsum'], services: ['gypsum.false_ceiling'], own_words: ['Painting works'] }, [],
    { waitUntil: (p) => { bg.push(p); }, reason: async () => { await g.p; return { codes: ['painting'], held: false }; } });
  assertEquals(s1, 200);
  const [s2] = await servicesSaveRewrite(admin, 7, { ...base, trades: ['gypsum'], services: ['gypsum.partitions'], own_words: ['Painting works'] }, [],
    { waitUntil: (p) => { bg.push(p); }, reason: async () => ({ codes: [], held: true }) });
  assertEquals(s2, 200);
  const newer = cap.confirmed_version;
  g.open(); await Promise.all(bg);
  assertEquals(cap.confirmed_version, newer, 'no confirm was written over the newer one');
  assert((cap.services as string[]).includes('gypsum.partitions') && !(cap.services as string[]).includes('gypsum.false_ceiling'), JSON.stringify(cap.services));
});

// ── HIS OWN WORDS FOR WHAT HE CONFIRMED (10 Nov 2026, sales_engineer; ledger 1573) ─────────────────────────────────────
Deno.test('the services his profile states are offered UNTICKED (founder 862), with the line and the licence check', async () => {
  const { admin, cap } = fakeDb({}, null);
  cap.source_docs = { docs: [], licence_check: { read: true, activities: ['Painting Contracting'], licence_trades: ['painting'], not_covered: ['gypsum.false_ceiling'] },
    proposed_services: [
      { key: 'gypsum.false_ceiling', trade: 'gypsum', label_en: 'False ceilings', via: 'exact_name', phrase: 'Gypsum false ceilings', snippet: 'Gypsum false ceilings and partitions', licence: 'not_covered', doc: 'p.pdf' },
      { key: 'gone.retired', trade: 'gone', label_en: 'Retired', via: 'meaning', phrase: 'x', snippet: 'x', licence: 'unclear', doc: 'p.pdf' },
    ] };
  const st = await servicesState(admin, 7);
  assertEquals(st.proposed_services.map((p) => [p.key, p.licence, p.stated]), [['gypsum.false_ceiling', 'not_covered', false]], 'a retired key was offered, or a proposal arrived ticked');
  assertEquals(st.selected_services, [], 'first run starts unticked');
  assertEquals(st.licence_check?.not_covered, ['gypsum.false_ceiling']);
});

Deno.test('a confirm files his own short phrases for the services he CONFIRMED to the alias queue, and never fails on it', async () => {
  const { admin, cap } = fakeDb({});
  cap.source_docs = { proposed_services: [
    { key: 'gypsum.false_ceiling', trade: 'gypsum', label_en: 'False ceilings', via: 'meaning', phrase: 'Gypsum board ceilings', snippet: 'Gypsum board ceilings for villas', licence: 'supported', doc: 'p.pdf' },
    { key: 'painting.interior', trade: 'painting', label_en: 'Interior painting', via: 'meaning', phrase: 'Wall colour works', snippet: 'Wall colour works', licence: 'supported', doc: 'p.pdf' },
  ] };
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const rpc = admin.rpc;
  (admin as { rpc: unknown }).rpc = async (fn: string, args: Record<string, unknown>) => {
    calls.push({ fn, args });
    return fn === 'fn_service_alias_propose' ? { data: { ok: true, proposed: 1 }, error: null } : rpc(fn, args as { p_text: string });
  };
  const [s, out] = await servicesSaveRewrite(admin, 7, { ...base, trades: ['gypsum'], services: ['gypsum.false_ceiling'], own_words: [],
    phrases: [{ phrase: 'Drop ceilings in gypsum board', key: 'gypsum.false_ceiling' }, { phrase: 'Wall colour works', key: 'painting.interior' }] });
  assertEquals(s, 200, JSON.stringify(out));
  const q = calls.find((c) => c.fn === 'fn_service_alias_propose');
  assert(q, 'nothing was filed to the alias queue');
  // only services he CONFIRMED (painting.interior was proposed but not ticked), his own words, short names only
  assertEquals(q.args.p_pairs, [{ phrase: 'Gypsum board ceilings', key: 'gypsum.false_ceiling' }, { phrase: 'Drop ceilings in gypsum board', key: 'gypsum.false_ceiling' }]);
  assertEquals((out as { aliasing?: { proposed: number } }).aliasing?.proposed, 1);

  // the queue unreachable (the SQL not yet applied): the confirm still succeeds and says why nothing was filed
  (admin as { rpc: unknown }).rpc = async (fn: string, args: Record<string, unknown>) =>
    fn === 'fn_service_alias_propose' ? { data: null, error: { message: 'function public.fn_service_alias_propose does not exist' } } : rpc(fn, args as { p_text: string });
  const [s2, out2] = await servicesSaveRewrite(admin, 7, { ...base, trades: ['gypsum'], services: ['gypsum.false_ceiling'], own_words: [] });
  assertEquals(s2, 200);
  assert(String((out2 as { aliasing?: { error?: string } }).aliasing?.error).includes('does not exist'));
});

// ── review round 2 of the two-step reading (12 Nov 2026): a trade ON FILE stays his at Confirm ───────────────────────────────────────
// 14,744 unconfirmed listed suppliers hold a trade from the directory listing. The tab sends it again (ServicesTab, 'on_file'), and the
// real confirm path keeps it: confirmed when it lists nothing to tick, and, as on main (founder 857/862), asked to tick one service when it
// does. A trade only his DOCUMENTS proposed and he ticked nothing in is dropped (keepTickedProposed).
Deno.test('a trade on file, nothing newly ticked: the real confirm path keeps it; a proposed trade with no tick is dropped', async () => {
  const { admin, cap } = fakeDb({}, null);
  cap.trades = ['gypsum']; cap.proposed_trades = ['gypsum', 'painting'];
  // gypsum lists services: confirming it with nothing ticked asks for a tick, exactly as on main
  const [s1, b1] = await servicesSaveRewrite(admin, 7, { roles: ['contractor'], raw_text: '', trades: ['gypsum'], services: [], own_words: [] });
  assertEquals([s1, (b1 as { code?: string }).code], [400, 'services_none_ticked']);
  // one service ticked in the trade on file, and a documents-proposed trade (painting) sent with nothing ticked in it
  const [s2] = await servicesSaveRewrite(admin, 7, { roles: ['contractor'], raw_text: '', trades: ['gypsum', 'painting'], services: ['gypsum.false_ceiling'], own_words: [] });
  assertEquals(s2, 200);
  assertEquals([...(cap.trades as string[])].sort(), ['gypsum'], 'the trade on file is kept; the proposed trade with no tick is not his');
});
