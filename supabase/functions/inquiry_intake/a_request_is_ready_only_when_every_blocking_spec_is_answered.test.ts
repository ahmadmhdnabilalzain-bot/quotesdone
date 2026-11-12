// A REQUEST IS READY ONLY WHEN EVERY BLOCKING SPEC IS ANSWERED (10 Nov 2026, sales_engineer; founder ledger 1587: "the
// interview with the customer happens ONCE, with no back-and-forth, and the inquiry must be complete enough that every
// supplier can quote without asking for a missing detail").
//
// Offline. The checklists are the REPOSITORY packs, mapped by the loader's own code (scripts/kb/load_trade_spec_checklists.mjs
// checklistsOf: what --apply writes into public.trade_spec_checklist) and read back by the runtime's own reader
// (_shared/inquiry_trades.ts checklistsOf: what tradeContext returns), so the test runs the path production runs.
// Six trades from six groups: swimming_pools (construction), staff_transport (transport), legal_services (professional),
// corrugated_packaging (materials), hvac (MEP), medical_equipment (health).
//   1. the blocking specs of the job's checklist are REQUIRED and asked FIRST, under a generic slug and under a real one;
//   2. NOT ready while one blocking spec is missing (and the missing one is what is asked); READY when all are answered;
//   3. "customer does not know" (recorded) counts as answered and goes to the suppliers as "supplier to advise";
//   4. the site-visit condition is carried into the brief as a known condition;
//   5. a universal spec (payment terms, location and emirate) is ONE question for a two-trade request, a missing emirate
//      blocks a trade whose location is blocking, and "supplier to advise" still counts for it;
//   6. a trade whose rows carry no blocking list yet keeps the earlier rule (nothing read as "nothing blocks");
//   7. the real handler: a model that says "ready" with a blocking spec missing is answered needs_info, with the spec open.
// Run: deno test --no-lock --node-modules-dir=auto -A supabase/functions/inquiry_intake/a_request_is_ready_only_when_every_blocking_spec_is_answered.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { checklistsOf as loaderRows } from '../../../scripts/kb/load_trade_spec_checklists.mjs';
import { activeChecklists, checklistsOf, packFields, readinessOf, SUPPLIER_TO_ADVISE, tradeBlock, UNIVERSAL_QUESTION, universalAnswers, universalOf,
  type TradeContext } from '../_shared/inquiry_trades.ts';
import { blockingGate, briefConditions, withPack } from './blocking_gate.ts';
import { CONVERGE_AT } from '../_shared/inquiry_state.ts';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const ROOT = new URL('../../../', import.meta.url);
type Row = Record<string, unknown>;
// deno-lint-ignore no-explicit-any
const packOf = (code: string): any => JSON.parse(Deno.readTextFileSync(new URL(`knowledge/packs/${code}.json`, ROOT)));
/** The table rows the loader writes for these trades (the column names of public.trade_spec_checklist). */
function tableRows(codes: string[]): Row[] {
  // deno-lint-ignore no-explicit-any
  return codes.flatMap((c) => loaderRows(packOf(c), c + '.json').map(({ refused: _r, ...r }: any) => r));
}
function ctxOf(codes: string[], strip = false): TradeContext {
  const rows = tableRows(codes).map((r) => (strip ? { ...r, spec_guide: [], blocking: [], site_visit_required_when: null } : r));
  const checklists = checklistsOf(rows);
  const specs = Object.fromEntries(codes.map((c) => [c, (checklists[c] ?? []).flatMap((k) => k.specs)]));
  return { codes, trades: codes.map((c) => ({ code: c, label: c.replace(/_/g, ' '), group_code: null })), services: [], specs, approvals: {}, checklists };
}
/** The job's blocking specs of one trade, as readinessOf keys them (a universal spec under its one key). */
function blockingKeys(ctx: TradeContext, topics: string[] = []): string[] {
  const out: string[] = [];
  for (const lists of Object.values(activeChecklists(ctx, topics))) for (const c of lists) for (const code of c.blocking) {
    const k = universalOf(c.specs.find((s) => s.code === code)!.label_en) ?? code;
    if (!out.includes(k)) out.push(k);
  }
  return out;
}
const answer = (keys: string[]) => Object.fromEntries(keys.map((k) => [k, 'ZZ DEMO stated']));

const SIX = ['swimming_pools', 'staff_transport', 'legal_services', 'corrugated_packaging', 'hvac', 'medical_equipment'];

for (const code of SIX) {
  Deno.test(`${code}: blocking specs are required and first; not ready while one is missing; ready when all answered; supplier to advise counts; site visit carried`, () => {
    const ctx = ctxOf([code]);
    const keys = blockingKeys(ctx);
    assert(keys.length >= 3, `${code}: only ${keys.length} blocking specs read`);
    // 1. required, and first, under a generic slug and under a real one (a slug's own keys stay the dispatch contract)
    const generic = withPack([], ctx, 'general');
    assertEquals(generic.filter((f) => f.required).map((f) => f.key).sort(), keys.slice().sort(), 'the required fields are not the blocking specs');
    assertEquals(generic.slice(0, keys.length).map((f) => f.key).sort(), keys.slice().sort(), 'the blocking specs are not asked first');
    const slug = withPack([{ key: 'zz_slug_key', question: 'ZZ slug question', required: true }], ctx, 'zz-real-slug');
    for (const k of keys) assert(slug.find((f) => f.key === k)?.required, `${k} is not required under a real slug`);
    assertEquals(slug.findIndex((f) => f.key === 'zz_slug_key'), keys.length, 'the blocking specs do not come before the slug\'s own');
    // within the 100-message cap: one blocking spec a turn, two messages each, still before the converge stage
    assert(keys.length * 2 + 2 < CONVERGE_AT, `${code}: ${keys.length} blocking specs cannot be asked before message ${CONVERGE_AT}`);
    // 2. not ready while one is missing
    const missing = keys[keys.length - 1];
    const partial = answer(keys.slice(0, -1));
    const g1 = blockingGate('ready', ctx, [], partial, []);
    assertEquals(g1.status, 'needs_info', 'ready while a blocking spec is missing');
    assertEquals(g1.verdict.open.map((o) => o.key), [missing]);
    assertEquals(g1.questions.length, 1);
    // ...and as the state stores them ({value, turn})
    const asState = Object.fromEntries(Object.entries(answer(keys)).map(([k, v]) => [k, { value: v, turn: 3 }]));
    assertEquals(blockingGate('ready', ctx, [], asState, []).status, 'ready', 'the state\'s {value} specs are not read as answers');
    assertEquals(blockingGate('ready', ctx, [], answer(keys), []).status, 'ready', 'not ready with every blocking spec answered');
    // the gate never makes a request ready that another gate held
    assertEquals(blockingGate('needs_info', ctx, [], answer(keys), []).status, 'needs_info');
    // 3. "does not know", recorded, counts as answered and goes to the suppliers as theirs to advise
    const g3 = blockingGate('ready', ctx, [], partial, [missing]);
    assertEquals(g3.status, 'ready', 'a recorded "does not know" did not count as answered');
    assertEquals(g3.verdict.advised.map((o) => o.key), [missing]);
    assertEquals(blockingGate('ready', ctx, [], { ...partial, [missing]: SUPPLIER_TO_ADVISE }, []).status, 'ready', 'the explicit value does not count');
    const brief: Row = { details: { ...partial } };
    briefConditions(brief, g3.verdict);
    assertEquals((brief.details as Row)[missing], SUPPLIER_TO_ADVISE, 'the supplier is not told to advise');
    // 4. the site-visit condition is a known condition on the brief, never hidden
    const svw = (ctx.checklists![code][0].site_visit_required_when ?? '');
    if (svw) {
      assertEquals(g3.verdict.site_visits.map((v) => v.when), [svw]);
      assert(String((brief.details as Row).site_visit).includes(svw), 'the site-visit condition is not in the details the supplier reads');
      assertEquals((brief.known_conditions as Row[])[0].kind, 'site_visit');
      const applies = readinessOf(ctx, [], answer(keys), [], [code]);
      assert(applies.site_visits[0].text.startsWith('Site visit needed before a final price.'), applies.site_visits[0].text);
    }
    // the prompt shows the guide (why, options, follow-up) for the blocking specs, and only for the placed trade
    const block = tradeBlock(ctx, 'en');
    const guide = ctx.checklists![code][0].guide.find((g) => g.blocking && !universalOf(g.spec))!;
    assert(block.includes('BLOCKING:') && block.includes(`[${guide.code}]`) && block.includes('why: ' + guide.why_needed_to_price.slice(0, 40)), 'the blocking guide is not in the prompt');
    for (const other of SIX.filter((c) => c !== code)) assert(!block.includes(`[${other}]`), `another trade (${other}) is in the prompt`);
  });
}

Deno.test('a trade with several checklists: the job\'s checklist decides, the pack\'s first until the job is matched', () => {
  const ctx = ctxOf(['hvac']);
  assertEquals(activeChecklists(ctx)['hvac'].map((c) => c.topic_id), ['hvac:spec-split-ac'], 'the pack\'s first checklist is not the default');
  const chiller = blockingKeys(ctx, ['hvac:spec-chiller']);
  const split = blockingKeys(ctx);
  assert(chiller.some((k) => !split.includes(k)), 'the chiller job asks the split AC blockers');
  const onlySplit = split.filter((k) => !chiller.includes(k))[0];
  // a chiller request does not wait for a split-AC spec
  assertEquals(blockingGate('ready', ctx, ['hvac:spec-chiller'], answer(chiller), []).status, 'ready');
  assert(!readinessOf(ctx, ['hvac:spec-chiller'], answer(chiller), []).open.some((o) => o.key === onlySplit));
  // the prompt names the other checklists to choose from, in one line each
  const block = tradeBlock(ctx, 'en');
  assert(block.includes('THE CHECKLIST FOR THIS JOB: hvac:spec-split-ac') && block.includes("THIS TRADE'S OTHER CHECKLISTS") && block.includes('hvac:spec-chiller'));
});

Deno.test('universal specs: a two-trade request asks payment terms and the emirate ONCE', () => {
  const ctx = ctxOf(['swimming_pools', 'hvac']);
  // both packs list them (the pack rows stay: they say why each trade needs the field)
  for (const c of ['swimming_pools', 'hvac']) {
    const labels = ctx.checklists![c][0].specs.map((s) => s.label_en);
    assert(labels.some((l) => universalOf(l) === 'payment_terms') && labels.some((l) => universalOf(l) === 'location'), `${c} does not list both`);
  }
  const fields = packFields(ctx);
  assertEquals(fields.filter((f) => f.key === 'payment_terms').length, 1, 'payment terms is asked more than once');
  assertEquals(fields.filter((f) => f.key === 'location').length, 1, 'the location and emirate are asked more than once');
  assert(!fields.some((f) => universalOf(f.question) || /^spec_(payment_terms|site_location_and_emirate)$/.test(f.key)), 'a per-trade copy of a universal spec is still asked');
  assertEquals(fields.find((f) => f.key === 'payment_terms')!.required, false, 'payment terms blocks');
  assertEquals(fields.find((f) => f.key === 'location')!.required, true, 'the location is not blocking although both trades block on it');
  const block = tradeBlock(ctx, 'en');
  assertEquals(block.split(UNIVERSAL_QUESTION.payment_terms).length - 1, 1, 'the prompt asks payment terms more than once');
  assertEquals(block.split(UNIVERSAL_QUESTION.location).length - 1, 1, 'the prompt asks the location more than once');
  assert(!/\[spec_payment_terms\]|\[spec_site_location_and_emirate\]/.test(block), 'a trade still lists a universal spec as its own question');
  assert(block.includes('BLOCKING for: swimming_pools, hvac'), 'the one location question does not say which trades it blocks');
  // readiness reports the location once, not once per trade
  const own = blockingKeys(ctx).filter((k) => k !== 'location');
  const v = readinessOf(ctx, [], answer(own), [], [], universalAnswers({ specs: answer(own) }));
  assertEquals(v.open.map((o) => o.key), ['location']);
  // payment terms is asked once even of a trade whose checklist does not list it
  assertEquals(packFields(ctxOf(['legal_services'])).filter((f) => f.key === 'payment_terms').length, 1);
});

Deno.test('universal specs: a missing emirate blocks a trade whose location is blocking; the stated emirate answers it; supplier to advise still counts', () => {
  const ctx = ctxOf(['hvac']);
  const own = blockingKeys(ctx).filter((k) => k !== 'location');
  assert(blockingKeys(ctx).includes('location'), 'hvac no longer blocks on the site location');
  const specs = answer(own);
  const none = blockingGate('ready', ctx, [], specs, [], [], universalAnswers({ specs, emirate: null }));
  assertEquals(none.status, 'needs_info', 'ready without the emirate');
  assertEquals(none.verdict.open.map((o) => o.key), ['location']);
  assertEquals(none.questions, [UNIVERSAL_QUESTION.location]);
  assertEquals(blockingGate('ready', ctx, [], specs, [], [], universalAnswers({ specs, emirate: 'Dubai' })).status, 'ready', 'the emirate the conversation states does not answer it');
  assertEquals(blockingGate('ready', ctx, [], { ...specs, location: 'Al Quoz, Dubai' }, []).status, 'ready', 'the held location key does not answer it');
  const adv = blockingGate('ready', ctx, [], specs, ['location'], [], universalAnswers({ specs }));
  assertEquals(adv.status, 'ready', '"supplier to advise" no longer counts for a universal spec');
  assertEquals(adv.verdict.advised.map((o) => o.key), ['location']);
  // a trade that does not block on location is ready without one
  const legal = ctxOf(['legal_services']);
  assertEquals(blockingGate('ready', legal, [], answer(blockingKeys(legal)), [], [], {}).status, 'ready');
});

Deno.test('the mapping is an explicit table: near wordings are trade specs', () => {
  assertEquals(universalOf('Site location and emirate'), 'location');
  assertEquals(universalOf('  payment terms '), 'payment_terms');
  for (const l of ['lead time', 'Delivery terms and location', 'inter-emirate travel', 'plot location and emirate', 'start date', 'budget breakdown', 'payment terms, advance and retention'])
    assertEquals(universalOf(l), null, l);
});

Deno.test('a trade whose rows carry no blocking list yet keeps the earlier rule, and is never read as "nothing blocks" by the slots', () => {
  const ctx = ctxOf(['staff_transport'], true);
  const generic = withPack([], ctx, 'general');
  assertEquals(generic.filter((f) => f.required).length, 6, 'the first six specs are no longer required before the load');
  assertEquals(withPack([{ key: 'k', required: true }], ctx, 'zz-real-slug').filter((f) => f.required).length, 1, 'a real slug gained required pack specs before the load');
  assertEquals(blockingGate('ready', ctx, [], {}, []).status, 'ready', 'the final gate invented a blocking list');
});

// ── the real handler ─────────────────────────────────────────────────────────────────────────────────────────────────
const EMAIL = 'zz-demo-blocking-customer@example.invalid';
const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
function world(model: Row, state: Row | null = null) {
  const w = { rpcs: [] as { fn: string; args: Row }[], prompts: [] as string[], intake: { id: 'ii-zz-blocking', email: EMAIL, status: 'needs_info', turns: [], customer_id: 'c-zz-blocking', category: null, brief: {} } as Row };
  const stub: Stub = {
    user: { id: 'u-zz-blocking', email: EMAIL },
    rows: { customers: [{ id: 'c-zz-blocking', locale: 'en' }], category_specs: [{ category: 'general', label: 'x', fields: [] }],
      taxonomy_trade: [{ code: 'hvac', label: 'HVAC', group_code: 'mep_building_systems', authority_required: [] }],
      taxonomy_trade_service: [], trade_spec_checklist: tableRows(['hvac']), sales_knowledge: [] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      const r = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1];
      if (u.pathname.startsWith('/functions/v1/')) {
        const body = await req.clone().json().catch(() => ({}));
        if (body.fn === 'inquiry_intake' && body.response_format) { w.prompts.push(String(body.sys)); return J({ ok: true, content: JSON.stringify(model), model: 'stub/model' }); }
        return J({ ok: true, content: JSON.stringify({ answer: 'ZZ DEMO: noted. How many units do you need?' }), model: 'stub/model' });
      }
      if (r) { const args = await req.clone().json().catch(() => ({})); w.rpcs.push({ fn: r, args }); if (r === 'rl_check') return J(true); return J(null); }
      if (t === 'inquiry_state' && req.method === 'GET') return J(state ? [state] : []);
      if (t === 'inquiry_intake') {
        if (req.method === 'GET') return J([{ ...w.intake }]);
        if (req.method === 'PATCH') { Object.assign(w.intake, await req.clone().json()); return J([]); }
      }
      return undefined;
    },
  };
  return { w, stub };
}
const fnOf = () => loadFunction('inquiry_intake', () => import('./index.ts'));
// 12 Nov 2026 (review of #1979): a blocking spec closes only on the model's own confirmation of the filing ({words, answers}),
// so the stand-in confirms each one, and the customer's message carries those words (they must be the customer's own).
const confirmed = (details: Record<string, string>) => Object.fromEntries(Object.entries(details).map(([k, v]) => [k, { words: v, answers: k }]));
const saying = (lead: string, details: Record<string, string>) => lead + ' ' + Object.values(details).join('. ');

Deno.test('the handler: the model says "ready" with a blocking spec missing; the request is needs_info and that spec is open', async () => {
  const keys = blockingKeys(ctxOf(['hvac']));
  const missing = 'spec_number_of_units_per_type';
  assert(keys.includes(missing), JSON.stringify(keys));
  const details = { ...answer(keys.filter((k) => k !== missing && k !== 'location')), location: 'Al Barsha, Dubai' };
  const { w, stub } = world({ category: 'general', trades: ['general'], status: 'ready', claims_ready: true, assistant_message: 'All set.', questions: [], missing: [], readiness: 100,
    dialect: 'english', trade_codes: ['hvac'], service_keys: [], checklist_topics: ['hvac:spec-split-ac'], site_visit: ['hvac'], condition: {}, problem: '', options_offered: [], chosen_option: '', budget: '',
    spec_evidence: confirmed(details), brief: { summary: 'split AC', emirate: 'Dubai', details } }, { conv_key: 'intake:ii-zz-blocking', surface: 'request_chat', specs: {}, unknown: {}, asked: {}, message_count: 2, status: 'open', trade_codes: ['hvac'] });
  const r = await invoke(await fnOf(), stub, { intake_id: 'ii-zz-blocking', text: saying('ZZ DEMO wall splits for a villa in Al Barsha, Dubai', details), turn_id: 't-zz-blocking-1', lang: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.json).slice(0, 400));
  assertEquals(r.json.status, 'needs_info', 'ready with a blocking spec missing: ' + JSON.stringify(r.json).slice(0, 300));
  assertEquals((r.json.blocking as Row).open, [missing]);
  assert((r.json.missing_keys as string[]).includes(missing));
  assert(!(r.json.missing_keys as string[]).includes('location'), 'the stated location is asked again');
  assert(((r.json.blocking as Row).site_visits as string[])[0].startsWith('Site visit needed before a final price.'), 'the site visit the model judged is not carried');
  const sys = w.prompts[0];
  assert(sys.includes('THE CHECKLIST FOR THIS JOB: hvac:spec-split-ac') && sys.includes('BLOCKING:') && sys.includes('"checklist_topics"') && sys.includes('ASKED ONCE FOR THE WHOLE REQUEST'), 'the guide or the contract is not in the prompt');
});

Deno.test('the handler: "does not know" to the last blocking spec is answered as supplier to advise and is never held for', async () => {
  const keys = blockingKeys(ctxOf(['hvac']));
  const missing = 'spec_number_of_units_per_type';
  const details = { ...answer(keys.filter((k) => k !== missing && k !== 'location')), location: 'Al Barsha, Dubai' };
  const { w, stub } = world({ category: 'general', trades: ['general'], status: 'ready', claims_ready: true, assistant_message: 'All set.', questions: [], missing: [], readiness: 100,
    dialect: 'english', trade_codes: ['hvac'], service_keys: [], checklist_topics: ['hvac:spec-split-ac'], unknown_keys: [missing], condition: {}, problem: '', options_offered: [], chosen_option: '', budget: '',
    spec_evidence: confirmed(details), brief: { summary: 'split AC', emirate: 'Dubai', details } }, { conv_key: 'intake:ii-zz-blocking', surface: 'request_chat', specs: {}, unknown: {}, asked: {}, message_count: 2, status: 'open', trade_codes: ['hvac'] });
  const r = await invoke(await fnOf(), stub, { intake_id: 'ii-zz-blocking', text: saying('ZZ DEMO not sure how many, the supplier can advise.', details), turn_id: 't-zz-blocking-2', lang: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.json).slice(0, 400));
  assert(r.json.status !== 'held', 'held for a spec the customer does not know');
  assertEquals((r.json.blocking as Row).open, []);
  assertEquals((r.json.blocking as Row).advised, [missing]);
  const patch = w.rpcs.filter((x) => x.fn === 'fn_inquiry_state_merge').map((x) => x.args.p_patch as Row).at(-1)!;
  assertEquals((patch.specs as Row)[missing], SUPPLIER_TO_ADVISE, 'the state does not record it as supplier to advise');
  assert(!('site_visit' in (patch.specs as Row)), 'our own known condition was stored as something the customer said');
});
