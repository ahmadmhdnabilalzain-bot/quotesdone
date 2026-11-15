// scripts/e2e/journey_proof/personas/intake_bridge.ts — THE REAL INTAKE HANDLER, offline, for the persona dry run. Seat:
// customer_support. dry_run.mjs (Node) plays the person; this Deno process runs supabase/functions/inquiry_intake/index.ts
// itself through _shared/twilio_free_harness.ts (fetch, env and Deno.serve replaced before the import: NO request can leave
// this process, so nothing here can reach production) and answers one JSON line per turn on stdout.
//
//   deno run --no-lock --node-modules-dir=none --allow-read=. scripts/e2e/journey_proof/personas/intake_bridge.ts
//   stdin, one JSON per line: { text, lang, reads: { key: value }, evidence: { key: words }, req: { ... }, not_sure: bool }
//   stdout, one JSON per line: { ok, status, next_question, assistant_message, details, unknown, writer_calls }
//
// THE STAND-IN READER (labelled ZZ DEMO, never recorded output) is the same faithful reader journey_a_replay.test.ts uses:
// the platform's interview model is replaced by one that returns, under its key, every spec the person has said so far
// (dry_run.mjs hands it what was said, from the truth sheet), and files "not sure" against the question just asked. What is
// measured is what CODE then does with a faithful reading: which question it asks, when it repeats, when it is ready.
// HVAC is production's category_specs row for `hvac` as journey_a_replay.test.ts carries it (read 15 Nov 2026); the
// checklist is the repository pack knowledge/packs/hvac.json mapped by the loader, as the blocking test reads it.
import { invoke, loadFunction, type Stub } from '../../../../supabase/functions/_shared/twilio_free_harness.ts';
import { checklistsOf as loaderRows } from '../../../kb/load_trade_spec_checklists.mjs';

type Row = Record<string, unknown>;
const HVAC = [
  { key: 'system_type', type: 'select', options: ['Wall/floor split', 'Ducted (concealed) split', 'Cassette', 'VRF/VRV', 'Chiller (air/water-cooled)', 'Package unit', 'FAHU/AHU (fresh air)', 'Not sure - need site survey'], question: 'What type of AC system?', required: true, question_plain_en: 'What kind of air conditioning — wall split units, hidden ducted, ceiling cassettes, a central system, or should the supplier survey and advise?', same_as: 'spec_unit_type' },
  { key: 'application_area', type: 'text', options: [], question: 'What is the space used for (office, villa, retail, restaurant, server room, warehouse), and roughly what area in m² and ceiling height?', required: true, question_plain_en: 'What is the space used for, and roughly how big is it?',
    not_needed_when: { answered: ['spec_cooling_capacity'], text: "each unit's cooling capacity is stated (BTU/h, TR or kW)" }, same_as: 'spec_room_use_and_area_or_heat_load_calc' },
  { key: 'new_or_replace', type: 'select', options: ['New installation', 'Replacement of existing', 'Extension of existing', 'Service / repair / maintenance'], question: 'Is this new, replacement, or a service/repair?', required: true, question_plain_en: 'Is this a new installation, replacing old units, adding more, or a repair?' },
  { key: 'load_basis', type: 'select', options: ['Yes, I have heat-load calc / MEP drawings', 'No - supplier to size it'], question: 'Do you have a cooling-load calculation or MEP drawings?', required: false, question_plain_en: 'Do you have engineering drawings for the cooling, or should the supplier work out the size?' },
  { key: 'brand_tier', type: 'select', options: ['Premium (Daikin/Mitsubishi/Trane/Carrier)', 'Mid (LG/Gree/O-General)', 'Economy', 'Best value - recommend'], question: 'Preferred brand tier / efficiency?', required: false, question_plain_en: 'Would you like a premium brand, mid-range, economy, or the best value?' },
  { key: 'electrical_supply', type: 'select', options: ['Single-phase 230V', 'Three-phase 400V', 'Not sure'], question: 'Electrical supply available?', required: false, question_plain_en: 'Do you know whether the power supply is single-phase or three-phase? "Not sure" is fine.' },
  { key: 'scope', type: 'select', options: ['Supply only', 'Supply and install', 'Turnkey (incl. ducting, MEP drawings, testing & commissioning)'], question: 'Scope?', required: true, question_plain_en: 'Should the supplier only deliver, install, or do everything including ducts and testing?' },
  { key: 'amc', type: 'select', options: ['Yes, include AMC', 'No', 'Not sure'], question: 'Include an annual maintenance contract (AMC)?', required: false, question_plain_en: 'Would you like a yearly maintenance contract included?' },
  { key: 'location', type: 'text', options: [], question: 'Which emirate/area, floor level, and condenser location (roof/wall/ground)?', required: true, question_plain_en: 'Which emirate and area, which floor, and where can the outdoor unit go — roof, wall or ground?' },
  { key: 'timeline', type: 'select', options: ['Within 2 weeks', '2-4 weeks', '1-2 months', 'Flexible'], question: 'When do you need it done?', required: false, question_plain_en: 'When do you need it done?' },
];
const ROOT = new URL('../../../../', import.meta.url);
// deno-lint-ignore no-explicit-any
const hvacRows = () => loaderRows(JSON.parse(Deno.readTextFileSync(new URL('knowledge/packs/hvac.json', ROOT))), 'hvac.json').map(({ refused: _r, ...r }: any) => r);
const JA = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });

const acc = { details: {} as Record<string, string>, evidence: {} as Record<string, string>, unknown: [] as string[], req: {} as Row };
let now: { text: string; reads?: Record<string, string>; evidence?: Record<string, string>; req?: Row; not_sure?: boolean } = { text: '' };
let writerCalls = 0;
const intake: Row = { id: 'ii-zz-persona', email: 'zz-demo-persona@example.invalid', status: 'needs_info', turns: [] as Row[], customer_id: 'c-zz-persona', category: null, brief: {} };
const stub: Stub = {
  user: { id: 'u-zz-persona', email: 'zz-demo-persona@example.invalid' },
  rows: { customers: [{ id: 'c-zz-persona', locale: 'en' }], category_specs: [{ category: 'hvac', label: 'Air conditioning', fields: HVAC }],
    taxonomy_trade: [{ code: 'hvac', label: 'HVAC', group_code: 'mep_building_systems', authority_required: [] }], taxonomy_trade_service: [], trade_spec_checklist: hvacRows(), sales_knowledge: [] },
  rpc: { rl_check: true },
  handle: async (req, u) => {
    if (u.pathname === '/functions/v1/ai_gateway') {
      const b = await req.clone().json().catch(() => ({}));
      if (!(typeof b.sys === 'string' && b.sys.includes('Return STRICT JSON only'))) {
        // the reply writer: a stand-in voice, never a model's words (the question card is what the person reads)
        writerCalls++;
        return JA({ ok: true, model: 'stub/model', content: JSON.stringify({ answer: 'ZZ DEMO stand-in reply.' }) });
      }
      for (const [k, v] of Object.entries(now.reads ?? {})) { acc.details[k] = v; acc.evidence[k] = now.evidence?.[k] ?? now.text.slice(0, 200); }
      if (now.not_sure) {   // a faithful reader of "I don't know" to the question just asked
        const lastA = (intake.turns as Row[]).filter((x) => x.role === 'assistant').at(-1) as Row | undefined;
        const k = String((((lastA?.slots as Row)?.reply as Row)?.next_question as Row)?.key ?? '');
        if (k === 'required_by') acc.req[k] = 'flexible';
        else if (k.startsWith('material.') || k === 'installation' || k === 'warranty') acc.req[k] = 'not_sure';
        else if (k && !acc.unknown.includes(k)) acc.unknown.push(k);
      }
      Object.assign(acc.req, now.req ?? {});
      return JA({ ok: true, model: 'stub/model', content: JSON.stringify({ category: 'hvac', trades: ['hvac'], urgency: 'normal', status: 'needs_info',
        assistant_message: 'ZZ DEMO stand-in reply', claims_ready: false, questions: [], readiness: 50, missing: [], dialect: 'english', trade_codes: ['hvac'], service_keys: [],
        checklist_topics: ['hvac:spec-split-ac'], site_visit: [], condition: {}, problem: '', options_offered: [], chosen_option: '', budget: '', requirements: { ...acc.req }, changed_answers: [],
        answer_to_question: '', spec_evidence: { ...acc.evidence }, unknown_keys: [...acc.unknown], not_needed: {}, asked_keys: [],
        brief: { summary: 'ZZ DEMO persona dry run', category: 'hvac', scope: '', quantity: '', location: acc.details.location ?? '', site_location: '', emirate: acc.details.spec_site_location_and_emirate ?? '', al_ain: false, timeline: '', budget: '', details: { ...acc.details } } }) });
    }
    const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
    if (t === 'inquiry_state' && req.method === 'GET') return JA([]);
    if (t === 'inquiry_intake') {
      if (req.method === 'GET') return JA([{ ...intake }]);
      if (req.method === 'PATCH') { Object.assign(intake, await req.clone().json()); return JA([]); }
    }
    return undefined;
  },
};

const h = await loadFunction('inquiry_intake', () => import('../../../../supabase/functions/inquiry_intake/index.ts'));
const enc = new TextEncoder();
let buf = ''; let n = 0;
const write = (o: unknown) => Deno.stdout.write(enc.encode(JSON.stringify(o) + '\n'));
for await (const chunk of Deno.stdin.readable.pipeThrough(new TextDecoderStream())) {
  buf += chunk;
  let i: number;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
    if (!line) continue;
    try {
      now = JSON.parse(line); writerCalls = 0; n++;
      const r = await invoke(h, stub, { intake_id: intake.id, turn_id: `t-zz-persona-${n}`, lang: (now as Row).lang || 'en', text: now.text });
      const brief = (intake.brief ?? {}) as Row;
      await write({ ok: r.status === 200, http: r.status, status: r.json?.status ?? null, next_question: r.json?.next_question ?? null, assistant_message: r.json?.assistant_message ?? '',
        details: { ...((brief.details ?? {}) as Row) }, unknown: [...acc.unknown], writer_calls: writerCalls, error: r.status === 200 ? null : JSON.stringify(r.json).slice(0, 300) });
    } catch (e) { await write({ ok: false, error: String((e as Error)?.stack || e).slice(0, 500) }); }
  }
}
