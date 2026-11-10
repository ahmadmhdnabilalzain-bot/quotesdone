// THE REAL inquiry_intake HANDLER AS AN EXPERT (10 Nov 2026, sales_engineer; founder ledger 1572, 1579, 1586). Offline: fetch
// and env stubbed (_shared/twilio_free_harness.ts); the model is a stub that records the prompt it was given.
//   1. the prompt carries the ADVISE rule (the old "Do not pitch / only job is to collect" ban is gone), the reference options
//      for the conversation's trade, the solution so far from the state, and the trade's own pack; and what the model
//      answered (the options it put, the one chosen, the condition, the budget, the trade codes) reaches the state, with the
//      chosen option's service keys under specs.service_keys;
//   2. a bus rental (no category_specs slug covers it) is placed in the whole taxonomy: the prompt lists every group, the
//      model's staff_transport is kept, and that trade's own checklist holds the request: "ready" from the model is not ready
//      while the core specs a bus quote needs are missing.
// Run: deno test --no-lock --node-modules-dir=none -A supabase/functions/inquiry_intake/the_expert_advises_and_places_the_trade.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

type Row = Record<string, unknown>;
const EMAIL = 'zz-demo-expert-customer@example.invalid';
const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
const fn = () => loadFunction('inquiry_intake', () => import('./index.ts'));
const TAX = [
  { code: 'wallpaper', label: 'Wallpaper', label_ar: 'ورق الجدران', group_code: 'construction_building', authority_required: [] },
  { code: 'joinery', label: 'Joinery', group_code: 'construction_building', authority_required: [] },
  { code: 'staff_transport', label: 'Staff transport', group_code: 'transport_mobility', authority_required: [] },
  { code: 'corrugated_packaging', label: 'Corrugated packaging', group_code: 'materials_packaging', authority_required: [] },
];

function world(o: { category: string | null; fields: Row[]; state: Row | null; model: Row; turns?: Row[]; specs: Row[]; services: Row[] }) {
  const w = { prompts: [] as string[], rpcs: [] as { fn: string; args: Row }[], saves: [] as Row[],
    intake: { id: 'ii-zz-expert', email: EMAIL, status: 'needs_info', turns: o.turns ?? [], customer_id: 'c-zz-expert', category: o.category, brief: o.category ? { category: o.category, category_by: 'reasoning' } : {} } as Row };
  const stub: Stub = {
    user: { id: 'u-zz-expert', email: EMAIL },
    rows: { customers: [{ id: 'c-zz-expert', locale: 'en' }], category_specs: [{ category: o.category ?? 'general', label: 'x', fields: o.fields }], taxonomy_trade: TAX,
      taxonomy_trade_service: o.services, trade_spec_checklist: o.specs, sales_knowledge: [] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      const r = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1];
      if (u.pathname.startsWith('/functions/v1/')) {
        const body = await req.clone().json().catch(() => ({}));
        if (body.fn === 'inquiry_intake' && body.response_format) { w.prompts.push(String(body.sys)); return J({ ok: true, content: JSON.stringify(o.model), model: 'stub/model' }); }
        return J({ ok: true, content: JSON.stringify({ answer: 'ZZ DEMO: noted. Which emirate is it in?' }), model: 'stub/model' });
      }
      if (r) { const args = await req.clone().json().catch(() => ({})); w.rpcs.push({ fn: r, args }); if (r === 'rl_check') return J(true); return J(null); }
      if (t === 'inquiry_state' && req.method === 'GET') return J(o.state ? [o.state] : []);
      if (t === 'inquiry_intake') {
        if (req.method === 'GET') return J([{ ...w.intake }]);
        if (req.method === 'PATCH') { const body = await req.clone().json(); w.saves.push(body); Object.assign(w.intake, body); return J([]); }
      }
      return undefined;
    },
  };
  return { w, stub };
}
const mergeOf = (w: { rpcs: { fn: string; args: Row }[] }) => w.rpcs.filter((x) => x.fn === 'fn_inquiry_state_merge').map((x) => x.args.p_patch as Row).at(-1)!;

Deno.test('the expert: options for its trade, the solution so far and the trade pack in the prompt; the choice and its services kept', async () => {
  const h = await fn();
  const { w, stub } = world({
    category: 'wallpaper',
    fields: [{ key: 'size', type: 'text', options: [], question: 'What size is the wall?', required: true }, { key: 'location', type: 'text', options: [], question: 'Which emirate?', required: true }],
    state: { conv_key: 'intake:ii-zz-expert', surface: 'request_chat', specs: { size: { value: '2.4 x 1.2 m', turn: 2 } }, unknown: {}, asked: {}, message_count: 4, status: 'open',
      trade_codes: ['wallpaper'], condition: { object: { value: 'small MDF partition', turn: 1 }, constraint: { value: 'kids room', turn: 2 } },
      options_offered: [{ problem: 'cover_existing_board', option: 'pvc_wpc_panels', turn: 2 }, { problem: 'cover_existing_board', option: 'architectural_film', turn: 2 }], chosen_option: null },
    turns: [{ role: 'user', text: 'ZZ DEMO small MDF partition, cover it with PVC or a wrap?' }, { role: 'assistant', text: 'PVC panels, a vinyl film or paint. Which suits you?' },
      { role: 'user', text: 'ZZ DEMO 2.4 x 1.2 m, kids room' }, { role: 'assistant', text: 'Which emirate?' }],
    specs: [{ trade_code: 'wallpaper', topic_id: 'wallpaper:spec-checklist', specs: [{ code: 'spec_material_and_finish', label_en: 'material and finish' }, { code: 'spec_area', label_en: 'area in square metres' }] }],
    services: [{ trade_code: 'wallpaper', code: 'wall_panels', label_en: 'Wall panels' }, { trade_code: 'wallpaper', code: 'supply_install', label_en: 'Wallpaper supply & installation' }],
    model: { category: 'wallpaper', trades: ['wallpaper'], status: 'needs_info', assistant_message: 'The film keeps the shape and suits a small partition. Which emirate is it in?', claims_ready: false,
      questions: ['Which emirate is it in?'], already_provided: ['2.4 x 1.2 m'], missing: ['Which emirate?'], readiness: 60, dialect: 'english',
      trade_codes: ['wallpaper', 'not_a_trade'], service_keys: ['wallpaper.supply_install', 'wallpaper.invented'], condition: { object: 'small MDF partition', constraint: 'kids room' },
      problem: 'cover_existing_board', options_offered: [], chosen_option: 'cover_existing_board/architectural_film', budget: 'about 3,000 AED',
      brief: { details: { size: '2.4 x 1.2 m' } } },
  });
  const r = await invoke(h, stub, { intake_id: 'ii-zz-expert', text: 'ZZ DEMO the film please, budget about 3,000 AED', turn_id: 't-zz-expert-3', lang: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.json).slice(0, 400));
  const sys = w.prompts[0];
  assert(sys, 'the model was not called');
  assert(sys.includes('ADVISE LIKE AN EXPERT WHEN THEY ARE DECIDING') && sys.includes('two or three suitable options'), 'no advising rule');
  assert(!sys.includes('Do not pitch') && !sys.includes('your only job is to collect'), 'the old ban is still in the prompt');
  assert(sys.includes('cover_existing_board/architectural_film: Architectural vinyl film wrap') && sys.includes('Trade-off:'), 'no reference options for the trade');
  assert(sys.includes('THE SOLUTION SO FAR') && sys.includes('options already put to them: PVC or WPC decorative wall panels; Architectural vinyl film wrap'), 'the state\'s options are not in the prompt');
  assert(sys.includes('constraint: "kids room"'), 'the condition is not carried');
  assert(sys.includes('[wallpaper] Wallpaper') && sys.includes('material and finish') && sys.includes('wallpaper.wall_panels = Wall panels'), 'the trade pack is not in the prompt');
  assert(!sys.includes('THE TRADE TAXONOMY (every trade'), 'the whole taxonomy is sent although the trade is held');
  assert(sys.includes('"chosen_option"') && sys.includes('"trade_codes"'), 'the JSON contract lacks the expert fields');
  const p = mergeOf(w);
  assertEquals((p.chosen_option as Row).option, 'architectural_film');
  assertEquals((p.specs as Row).service_keys, 'interior_fitout.decoration, wallpaper.supply_install', 'the chosen option names the services');
  assertEquals(p.trade_codes, ['wallpaper']);
  assertEquals(p.budget, 'about 3,000 AED');
  assertEquals((p.condition as Row).problem, 'cover_existing_board');
});

Deno.test('a bus rental is placed in the whole taxonomy, and its own checklist holds the request until a bus can be quoted', async () => {
  const h = await fn();
  const { w, stub } = world({
    category: null,
    fields: [{ key: 'describe', type: 'text', question: 'Describe it', required: true }],
    state: null,
    specs: [{ trade_code: 'staff_transport', topic_id: 'staff_transport:spec-checklist', specs: [
      { code: 'spec_number_of_passengers_and_routes', label_en: 'number of passengers and routes' }, { code: 'spec_vehicle_type_and_seating_capacity', label_en: 'vehicle type and seating capacity' },
      { code: 'spec_vehicle_age_and_air_conditioning', label_en: 'vehicle age and air-conditioning' }, { code: 'spec_trips_per_day_and_schedule', label_en: 'trips per day and schedule' }] }],
    services: [],
    model: { category: 'general', trades: ['general'], status: 'ready', claims_ready: true, assistant_message: 'All set.', questions: [], missing: [], readiness: 100, dialect: 'english',
      trade_codes: ['staff_transport'], service_keys: [], condition: { use: 'staff to work' }, problem: '', options_offered: [], chosen_option: '', budget: '',
      brief: { summary: 'bus', details: { describe: 'bus for staff', spec_number_of_passengers_and_routes: '40 staff, Sharjah to JAFZA' } } },
  });
  const r = await invoke(h, stub, { text: 'ZZ DEMO I need a bus for 40 staff from Sharjah to JAFZA every day', turn_id: 't-zz-bus-1', lang: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.json).slice(0, 400));
  const sys = w.prompts[0];
  assert(sys.includes('THE TRADE TAXONOMY (every trade') && sys.includes('Transport, vehicles, marine & aviation: staff_transport') && sys.includes('Materials, chemicals & packaging: corrugated_packaging'), 'the whole taxonomy is not offered');
  assert(sys.includes('REFERENCE SITUATIONS'), 'no situation index while no trade is known');
  assertEquals(r.json.status, 'needs_info', 'ready while the bus specs are missing: ' + JSON.stringify(r.json).slice(0, 300));
  const missing = r.json.missing_keys as string[];
  assert(missing.includes('spec_vehicle_type_and_seating_capacity') && missing.includes('spec_trips_per_day_and_schedule'), JSON.stringify(missing));
  assert(!missing.includes('spec_number_of_passengers_and_routes'), 'a spec they stated is asked');
  assertEquals(mergeOf(w).trade_codes, ['staff_transport']);
});
