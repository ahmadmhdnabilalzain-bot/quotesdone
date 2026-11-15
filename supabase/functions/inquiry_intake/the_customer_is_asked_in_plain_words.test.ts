// THE CUSTOMER IS ASKED IN PLAIN WORDS, IN THEIR LANGUAGE (15 Nov 2026, sales_engineer). The persona dry run (the REAL handler
// offline, a stand-in reader; scratchpad handbacks/PERSONAS.md) showed the cards were spec labels: a villa owner did not
// understand "Cooling capacity (BTU/h, TR or kW) per unit" or "Room use and area or heat-load calc"; an Arabic speaker saw
// every card in English, asked "شو يعني BTU؟", got no answer, was asked capacity again five turns later and left.
// Here the persona truth sheets (ZZ DEMO, a subset of scripts/e2e/journey_proof/personas/customers.mjs on the persona branch:
// what each person knows, does not know, and the words they do not understand) play the REAL inquiry_intake handler offline
// (_shared/twilio_free_harness.ts: nothing leaves the process) against a stubbed model that reads faithfully what was said.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { checklistsOf as loaderRows } from '../../../scripts/kb/load_trade_spec_checklists.mjs';
import { CUSTOMER_QUESTION, GLOSSARY, optionAr, saysNotSureAr } from '../_shared/customer_questions.ts';
import { interviewStep, optionsOf, questionsFor, tappedOption, type SpecField } from './interview.ts';
import { tappedHeldAnswer } from './slots.ts';

type Row = Record<string, unknown>;
// production's category_specs row for hvac (journey_a_replay.test.ts's copy) with its question_plain_ar (SELECT, 15 Nov 2026)
const AR: Record<string, string> = {
  system_type: 'ما نوع التكييف — وحدات سبليت جدارية، أم مخفية بمجارٍ، أم كاسيت سقفي، أم نظام مركزي، أم يعاين المورد وينصح؟',
  application_area: 'لأي غرض تُستخدم المساحة، وما حجمها التقريبي؟', new_or_replace: 'هل هو تركيب جديد، أم استبدال وحدات قديمة، أم إضافة، أم إصلاح؟',
  load_basis: 'هل لديك مخططات هندسية للتبريد، أم يحدد المورد الحجم المطلوب؟', brand_tier: 'هل تفضل علامة فاخرة، أم متوسطة، أم اقتصادية، أم الأفضل قيمة؟',
  electrical_supply: 'هل تعرف إن كان التيار الكهربائي أحادي الطور أم ثلاثي الطور؟ يمكنك الإجابة بـ«لا أعرف».',
  scope: 'هل تريد من المورد التوريد فقط، أم التركيب، أم تنفيذ كل شيء بما في ذلك المجاري والاختبار؟', amc: 'هل تريد تضمين عقد صيانة سنوي؟',
  location: 'في أي إمارة ومنطقة، وفي أي طابق، وأين يمكن وضع الوحدة الخارجية — على السطح أم الجدار أم الأرض؟', timeline: 'متى تحتاج إلى إنجازه؟',
};
const HVAC: SpecField[] = ([
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
] as SpecField[]).map((f) => ({ ...f, question_plain_ar: AR[String(f.key)] }));

// ── the truth sheets (ZZ DEMO; the persona branch's customers.mjs, the facts this chat asks about) ─────────────────────────
type Fact = { id: string; knows: boolean; says: string; keys: string[]; reads?: Record<string, string>; req?: Row; file?: Record<string, string> };
type Persona = { key: string; lang: 'en' | 'ar'; opener: string; opener_reads: Record<string, string>; facts: Fact[]; jargon: RegExp[]; asks: (term: string) => string };
const VILLA: Persona = {
  key: 'villa_owner', lang: 'en', opener: 'Hi, my AC is not cooling properly. 4 units in the villa. Not sure of the size sorry',
  opener_reads: { spec_number_of_units_per_type: '4 units' },
  facts: [
    { id: 'units', knows: true, says: 'Four. The normal ones on the wall, in the bedrooms and the living room.', keys: ['system_type', 'spec_unit_type', 'spec_number_of_units_per_type'], reads: { system_type: 'Wall/floor split', spec_unit_type: 'Wall split', spec_number_of_units_per_type: '4 wall splits' } },
    { id: 'repair_or_replace', knows: true, says: 'If they can be fixed, fix them, if not replace them.', keys: ['new_or_replace'], reads: { new_or_replace: 'Service / repair / maintenance; Replacement of existing (if repair is not worth it)' } },
    { id: 'location', knows: true, says: 'A villa in Dubai.', keys: ['location', 'spec_site_location_and_emirate'], reads: { location: 'A villa in Dubai', spec_site_location_and_emirate: 'Dubai' } },
    // he does not know the capacity; he has a phone photo of the nameplate, which the question now asks for
    { id: 'capacity', knows: false, says: 'No idea sorry, here is a photo of the sticker on the outside unit.', keys: ['spec_cooling_capacity'], file: { spec_cooling_capacity: '18,000 BTU/h (1.5 TR) per unit, read from the nameplate photo' } },
    { id: 'rooms', knows: true, says: '3 bedrooms and the living room, maybe 5 by 6 metres.', keys: ['application_area', 'spec_room_use_and_area_or_heat_load_calc'], reads: { application_area: 'Villa: 3 bedrooms and a living room of about 5 x 6 m', spec_room_use_and_area_or_heat_load_calc: '3 bedrooms, living room about 30 m2' } },
    { id: 'outdoor', knows: true, says: 'The outside units are on the roof.', keys: ['spec_outdoor_unit_mounting'], reads: { spec_outdoor_unit_mounting: 'Roof' } },
    { id: 'inverter', knows: false, says: "I don't know. Whatever is cheaper to run?", keys: ['spec_inverter_or_fixed_speed'] },
    { id: 'pipes', knows: false, says: 'No idea, the pipes are inside the walls.', keys: ['spec_copper_pipe_length_included_per_unit'] },
    { id: 'scope', knows: true, says: 'They should do everything.', keys: ['scope', 'installation'], reads: { scope: 'Supply and install' }, req: { installation: 'yes' } },
    { id: 'brand', knows: true, says: 'No preference.', keys: ['brand_tier', 'material.brand', 'spec_brand_preference_or_equivalent_tier'], reads: { brand_tier: 'Best value - recommend' }, req: { 'material.brand': 'no_preference' } },
    { id: 'timeline', knows: true, says: 'As soon as possible please.', keys: ['timeline', 'required_by'], reads: { timeline: 'Within 2 weeks' }, req: { required_by: { date: '2026-11-29', text: 'as soon as possible' } } },
    { id: 'warranty', knows: true, says: 'At least a year?', keys: ['warranty', 'spec_warranty'], req: { warranty: { months: 12 } } },
    { id: 'removal', knows: true, says: 'Yes take the old ones away.', keys: ['spec_old_unit_removal_and_refrigerant_recover'], reads: { spec_old_unit_removal_and_refrigerant_recover: 'Take the old units away' } },
    { id: 'ducting', knows: true, says: 'No ducts.', keys: ['material.ducting'], req: { 'material.ducting': 'not_needed' } },
    { id: 'payment', knows: true, says: 'Half now half after.', keys: ['payment_terms'], reads: { payment_terms: '50% advance, 50% on completion' } },
  ],
  jargon: [/\bbtu\b/i, /\btr\b/i, /heat.?load/i, /refrigerant|\br32\b|\br410/i, /three.?phase|single.?phase/i, /\bmep\b/i, /\besma\b/i, /\bt3\b/i, /condensate/i],
  asks: (t) => `what does "${t}" mean?`,
};
const ARABIC: Persona = {
  key: 'arabic_mixed', lang: 'ar', opener: 'السلام عليكم، عندي 3 مكيفات split في الفيلا في مردف، واحد ما يبرد أبداً. أبي أبدلهم كلهم new',
  opener_reads: { system_type: 'Wall/floor split', spec_unit_type: 'Wall split', spec_number_of_units_per_type: '3 wall splits', new_or_replace: 'Replacement of existing', location: 'A villa in Dubai', spec_site_location_and_emirate: 'Dubai' },
  facts: [
    { id: 'capacity', knows: false, says: 'والله ما أعرف الـ size، يمكن 1.5 طن؟ مو متأكد', keys: ['spec_cooling_capacity'] },
    { id: 'rooms', knows: true, says: 'غرفتين نوم والصالة، الصالة كبيرة شوي', keys: ['application_area', 'spec_room_use_and_area_or_heat_load_calc'], reads: { application_area: 'Villa: 2 bedrooms and a fairly large hall', spec_room_use_and_area_or_heat_load_calc: '2 bedrooms and a large hall' } },
    { id: 'scope', knows: true, says: 'توريد وتركيب، كل شي عليهم', keys: ['scope', 'installation'], reads: { scope: 'Supply and install' }, req: { installation: 'yes' } },
    { id: 'brand', knows: true, says: 'أي brand زين، LG أو Gree', keys: ['brand_tier', 'material.brand', 'spec_brand_preference_or_equivalent_tier'], reads: { brand_tier: 'Mid (LG/Gree/O-General)' }, req: { 'material.brand': { other: 'LG or Gree' } } },
    { id: 'timeline', knows: true, says: 'قبل نهاية الشهر إن شاء الله', keys: ['timeline', 'required_by'], reads: { timeline: '2-4 weeks' }, req: { required_by: { date: '2026-11-30', text: 'before the end of the month' } } },
    { id: 'inverter', knows: true, says: 'inverter أحسن للكهرباء صح؟ خلها inverter', keys: ['spec_inverter_or_fixed_speed'], reads: { spec_inverter_or_fixed_speed: 'Inverter' } },
    { id: 'pipes', knows: false, says: 'ما أدري عن المواسير', keys: ['spec_copper_pipe_length_included_per_unit'] },
    { id: 'outdoor', knows: true, says: 'الوحدات الخارجية على السطح', keys: ['spec_outdoor_unit_mounting'], reads: { spec_outdoor_unit_mounting: 'Roof' } },
    { id: 'warranty', knows: false, says: 'الضمان؟ اللي عادي عندكم', keys: ['warranty', 'spec_warranty'], req: { warranty: 'not_sure' } },
    { id: 'removal', knows: true, says: 'إيه شيلوا القديمة', keys: ['spec_old_unit_removal_and_refrigerant_recover'], reads: { spec_old_unit_removal_and_refrigerant_recover: 'Remove the old units' } },
    { id: 'ducting', knows: true, says: 'ما في duct', keys: ['material.ducting'], req: { 'material.ducting': 'not_needed' } },
    { id: 'payment', knows: true, says: 'نص مقدم ونص بعد التركيب', keys: ['payment_terms'], reads: { payment_terms: '50% advance, 50% after installation' } },
  ],
  jargon: [/\bbtu\b/i, /heat.?load/i, /refrigerant|\br32\b|\br410/i, /three.?phase|single.?phase/i, /\bmep\b/i, /\besma\b/i, /\bt3\b/i, /condensate/i],
  asks: (t) => `شو يعني "${t}"؟`,
};

const ROOT = new URL('../../../', import.meta.url);
// deno-lint-ignore no-explicit-any
const hvacRows = () => loaderRows(JSON.parse(Deno.readTextFileSync(new URL('knowledge/packs/hvac.json', ROOT))), 'hvac.json').map(({ refused: _r, ...r }: any) => r);
const JA = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });

type Turn = { n: number; said: string; status: string; next: { key: string | null; text: string; options: string[] | null } | null; message: string; writer: string; details: Row };
/** The person plays the chat: each card is answered from the truth sheet by its key; a card built on a word they do not know
 *  gets "what does that mean?" (`forceAsk` makes one card do so, as a sticker reading "18000 BTU" would). The stubbed model is a
 *  faithful reader: it returns what was said under its keys, "does not know" for the card asked, and explain_terms. */
async function play(p: Persona, o: { forceAsk?: { key: string; term: string }; maxTurns?: number } = {}) {
  const acc = { details: { ...p.opener_reads } as Record<string, string>, evidence: {} as Record<string, string>, unknown: [] as string[], req: {} as Row, explain: [] as string[] };
  for (const k of Object.keys(p.opener_reads)) acc.evidence[k] = p.opener.slice(0, 120);
  const w = { writer: [] as unknown[], intake: { id: 'ii-zz-plain-' + p.key, email: `zz-demo-plain-${p.key}@example.invalid`, status: 'needs_info', turns: [] as Row[], customer_id: 'c-zz-plain', category: null, brief: {} } as Row };
  const stub: Stub = {
    user: { id: 'u-zz-plain', email: `zz-demo-plain-${p.key}@example.invalid` },
    rows: { customers: [{ id: 'c-zz-plain', locale: p.lang }], category_specs: [{ category: 'hvac', label: 'Air conditioning', fields: HVAC }],
      taxonomy_trade: [{ code: 'hvac', label: 'HVAC', label_ar: 'التكييف', group_code: 'mep_building_systems', authority_required: [] }], taxonomy_trade_service: [], trade_spec_checklist: hvacRows(), sales_knowledge: [] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      if (u.pathname === '/functions/v1/ai_gateway') {
        const b = await req.clone().json().catch(() => ({}));
        if (!(typeof b.sys === 'string' && b.sys.includes('Return STRICT JSON only'))) { w.writer.push(b); return JA({ ok: true, model: 'stub/model', content: JSON.stringify({ answer: 'ZZ DEMO voiced reply.' }) }); }
        return JA({ ok: true, model: 'stub/model', content: JSON.stringify({ category: 'hvac', trades: ['hvac'], urgency: 'normal', status: 'needs_info', assistant_message: 'ZZ DEMO stand-in reply', claims_ready: false,
          questions: [], readiness: 50, missing: [], dialect: p.lang === 'ar' ? 'gulf' : 'english', trade_codes: ['hvac'], service_keys: [], checklist_topics: ['hvac:spec-split-ac'], site_visit: [], condition: {}, problem: '',
          options_offered: [], chosen_option: '', budget: '', requirements: { ...acc.req }, changed_answers: [], answer_to_question: '', spec_evidence: { ...acc.evidence }, unknown_keys: [...acc.unknown], not_needed: {}, asked_keys: [],
          explain_terms: [...acc.explain],
          brief: { summary: 'ZZ DEMO plain-words persona', category: 'hvac', scope: '', quantity: '', location: acc.details.location ?? '', site_location: '', emirate: 'Dubai', al_ain: false, timeline: '', budget: '', details: { ...acc.details } } }) });
      }
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      if (t === 'inquiry_state' && req.method === 'GET') return JA([]);
      if (t === 'inquiry_intake') {
        if (req.method === 'GET') return JA([{ ...w.intake }]);
        if (req.method === 'PATCH') { Object.assign(w.intake, await req.clone().json()); return JA([]); }
      }
      return undefined;
    },
  };
  const h = await loadFunction('inquiry_intake', () => import('./index.ts'));
  const out: Turn[] = [];
  let said = p.opener; let asked = false;
  for (let n = 1; n <= (o.maxTurns ?? 16); n++) {
    w.writer = [];
    const r = await invoke(h, stub, { intake_id: w.intake.id, turn_id: `t-zz-plain-${p.key}-${n}`, lang: p.lang, text: said });
    if (r.status !== 200) throw new Error(`turn ${n}: HTTP ${r.status} ${JSON.stringify(r.json).slice(0, 300)}`);
    const next = r.json.next_question ?? null;
    out.push({ n, said, status: String(r.json.status), next, message: String(r.json.assistant_message ?? ''), writer: JSON.stringify(w.writer), details: ((w.intake.brief as Row)?.details ?? {}) as Row });
    if (r.json.status === 'ready' || !next) break;
    // the person's next message
    acc.explain = [];
    const key = String(next.key ?? '');
    const jar = p.jargon.find((re) => re.test(String(next.text)));
    const force = o.forceAsk && !asked && o.forceAsk.key === key ? o.forceAsk.term : null;
    if (jar || force) { const term = force ?? String(String(next.text).match(jar!)![0]); said = p.asks(term); acc.explain = [term]; asked = true; continue; }
    const fact = p.facts.find((f) => f.keys.includes(key));
    if (!fact) { said = p.lang === 'ar' ? 'ما أعرف' : 'Not sure'; if (key && !acc.unknown.includes(key)) acc.unknown.push(key); continue; }
    said = fact.says;
    for (const [k, v] of Object.entries(fact.reads ?? fact.file ?? {})) { acc.details[k] = v; acc.evidence[k] = said.slice(0, 120); }
    Object.assign(acc.req, fact.req ?? {});
    if (!fact.knows && !fact.file) for (const k of fact.keys) if (k.startsWith('spec_') && !acc.unknown.includes(k)) acc.unknown.push(k);
  }
  return out;
}
const cards = (ts: Turn[]) => ts.filter((t) => t.next).map((t) => t.next!);
const LABEL: Record<string, string> = Object.fromEntries(hvacRows().flatMap((r: { specs: { code: string; label_en: string }[] }) => r.specs.map((s) => [s.code, s.label_en])));

Deno.test('the villa owner: every card is in plain words with "Not sure", none is a spec label, nothing is asked twice', async () => {
  const ts = await play(VILLA);
  const cs = cards(ts);
  assert(cs.length >= 4, 'too few cards to judge: ' + cs.length);
  for (const c of cs) {
    for (const re of VILLA.jargon) assert(!re.test(c.text), `a card he does not understand: [${c.key}] ${c.text}`);
    if (c.key && LABEL[c.key]) assert(!c.text.toLowerCase().includes(LABEL[c.key].toLowerCase()), `the supplier's label read out: [${c.key}] ${c.text}`);
    // "Not sure" (a preference question's "No preference", a date's "Flexible", are their own way to say it)
    assert((c.options ?? []).some((x) => /not sure|no preference|flexible/i.test(x)), `no "Not sure" on [${c.key}] ${c.text}: ${JSON.stringify(c.options)}`);
  }
  // the capacity question offers the photo of the label he has on his phone
  const cap = cs.find((c) => c.key === 'spec_cooling_capacity');
  assert(cap && /photo of the sticker/i.test(cap.text), 'capacity not asked with the photo alternative: ' + JSON.stringify(cap));
  // never asked twice
  const keys = cs.map((c) => c.key).filter(Boolean);
  assertEquals(keys.length, new Set(keys).size, 'asked twice: ' + keys.join(', '));
  // what he could not answer went to the supplier, and the photo answered the capacity
  const last = ts.at(-1)!;
  assertEquals(String(last.details.spec_cooling_capacity ?? ''), '18,000 BTU/h (1.5 TR) per unit, read from the nameplate photo');
});

Deno.test('the Arabic speaker: every card and every button is Arabic, with «لست متأكداً», and none is asked twice', async () => {
  const ts = await play(ARABIC);
  const cs = cards(ts);
  assert(cs.length >= 4, 'too few cards to judge: ' + cs.length);
  for (const c of cs) {
    assert(/[؀-ۿ]/.test(c.text) && !/[A-Za-z]{2,}/.test(c.text), `an English card on an Arabic chat: [${c.key}] ${c.text}`);
    // every button is an Arabic label (a brand or a code may stand inside one: "ممتاز (Daikin/...)")
    for (const x of c.options ?? []) assert(/[\u0600-\u06FF]/.test(x), `an English button on an Arabic chat: [${c.key}] ${x}`);
    assert((c.options ?? []).some((x) => saysNotSureAr(x) || x.includes('لا تفضيل') || x.includes('مرن')), `no «لست متأكداً» on [${c.key}] ${c.text}: ${JSON.stringify(c.options)}`);
    for (const re of ARABIC.jargon) assert(!re.test(c.text), `jargon on [${c.key}] ${c.text}`);
  }
  const keys = cs.map((c) => c.key).filter(Boolean);
  assertEquals(keys.length, new Set(keys).size, 'asked twice: ' + keys.join(', '));
  // she does not leave stuck: every reply that is not ready asks something
  for (const t of ts) if (t.status === 'needs_info') assert(t.next, `turn ${t.n}: needs_info and no question`);
});

Deno.test('"شو يعني BTU؟": the next reply explains it first and asks the same question again in plain words; then it moves on', async () => {
  const ts = await play(ARABIC, { forceAsk: { key: 'spec_cooling_capacity', term: 'BTU' }, maxTurns: 8 });
  const i = ts.findIndex((t) => t.said.startsWith('شو يعني'));
  assert(i > 0, 'the question about the word was never asked: ' + ts.map((t) => t.next?.key).join(','));
  const before = ts[i - 1], after = ts[i];
  assertEquals(before.next?.key, 'spec_cooling_capacity');
  // the same question again, in plain Arabic, nothing else first
  assertEquals(after.next?.key, 'spec_cooling_capacity', 'moved on to another question before explaining');
  assert(/[؀-ۿ]/.test(after.next!.text) && !/[A-Za-z]{2,}/.test(after.next!.text), after.next!.text);
  // the reply the writer is given starts with the explanation, in Arabic (GLOSSARY), before the question
  const btu = GLOSSARY.find((g) => g.terms.includes('btu'))!.ar;
  assert(after.writer.includes(JSON.stringify(btu).slice(1, -1)), 'the explanation never reached the reply: ' + after.writer.slice(0, 400));
  // the turn after: she answers, and it is not asked a third time
  const third = ts[i + 1];
  assert(third && third.next?.key !== 'spec_cooling_capacity', 'capacity asked a third time');
});

Deno.test('"what does BTU mean?" in English: explained from the glossary, the same card again, counted once more in the asks', async () => {
  const ts = await play(VILLA, { forceAsk: { key: 'spec_cooling_capacity', term: 'BTU' }, maxTurns: 8 });
  const i = ts.findIndex((t) => t.said.startsWith('what does'));
  assert(i > 0);
  assertEquals(ts[i].next?.key, 'spec_cooling_capacity');
  assert(ts[i].writer.includes(JSON.stringify(GLOSSARY.find((g) => g.terms.includes('btu'))!.en).slice(1, -1)));
  assert(ts[i].next?.text === ts[i - 1].next?.text, 'the rephrase is the same plain question');
});

// ── review REVIEW_plain items 3 and 4 (15 Nov 2026) ──────────────────────────────────────────────────────────────────────────

/** One Arabic chat against the REAL handler: `model` is the stubbed interview reading for each turn (null: the model is down). */
async function arabicTurns(says: string[], model: (n: number) => Row | null, category: string | null = null) {
  const w = { intake: { id: 'ii-zz-plain-r', email: 'zz-demo-plain-r@example.invalid', status: 'needs_info', turns: [] as Row[], customer_id: 'c-zz-plain', category, brief: {} } as Row };
  let n = 0;
  const stub: Stub = {
    user: { id: 'u-zz-plain', email: 'zz-demo-plain-r@example.invalid' },
    rows: { customers: [{ id: 'c-zz-plain', locale: 'ar' }], category_specs: [{ category: 'hvac', label: 'Air conditioning', fields: HVAC }],
      taxonomy_trade: [{ code: 'hvac', label: 'HVAC', label_ar: 'التكييف', group_code: 'mep_building_systems', authority_required: [] }], taxonomy_trade_service: [], trade_spec_checklist: hvacRows(), sales_knowledge: [] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      if (u.pathname === '/functions/v1/ai_gateway') {
        const b = await req.clone().json().catch(() => ({}));
        if (!(typeof b.sys === 'string' && b.sys.includes('Return STRICT JSON only'))) return JA({ ok: false, error: 'down' }, 503);
        const m = model(n);
        return m ? JA({ ok: true, model: 'stub/model', content: JSON.stringify(m) }) : JA({ ok: false, error: 'openrouter down' }, 503);
      }
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      if (t === 'inquiry_state' && req.method === 'GET') return JA([]);
      if (t === 'inquiry_intake') {
        if (req.method === 'GET') return JA([{ ...w.intake }]);
        if (req.method === 'PATCH') { Object.assign(w.intake, await req.clone().json()); return JA([]); }
      }
      return undefined;
    },
  };
  const h = await loadFunction('inquiry_intake', () => import('./index.ts'));
  const out: Array<{ json: Row; details: Row }> = [];
  for (n = 1; n <= says.length; n++) {
    const r = await invoke(h, stub, { intake_id: w.intake.id, turn_id: `t-zz-plain-r-${n}`, lang: 'ar', text: says[n - 1] });
    if (r.status !== 200) throw new Error(`turn ${n}: HTTP ${r.status} ${JSON.stringify(r.json).slice(0, 300)}`);
    out.push({ json: r.json as Row, details: ((w.intake.brief as Row)?.details ?? {}) as Row });
  }
  return out;
}

Deno.test('item 3: an Arabic tap is stored as its English option, on the model-down path as on the held path', async () => {
  const sys = HVAC.find((f) => f.key === 'system_type')!;
  const ar = optionsOf(sys, 'ar')!;
  const cassetteAr = optionAr('Cassette')!;
  assert(cassetteAr && ar.includes(cassetteAr), 'the Arabic card does not offer Cassette: ' + JSON.stringify(ar));
  // the code: the one reader, both paths
  assertEquals(tappedOption(sys, cassetteAr), 'Cassette');
  assertEquals(tappedHeldAnswer(HVAC, 'system_type', cassetteAr), 'Cassette');
  const step = interviewStep(HVAC, { details: {}, asked_key: 'system_type' }, cassetteAr, cassetteAr, 'ar');
  assertEquals(step.details.system_type, 'Cassette');
  // a card option of a pack spec (customer_questions.ts) comes back as its English card value too
  const card = { key: 'spec_unit_type', question: 'Unit type', card_options: ['On the wall (split)', 'Square, in the ceiling (cassette)'], card_options_ar: ['على الجدار (سبليت)', 'مربعة في السقف (كاسيت)'] } as SpecField;
  assertEquals(interviewStep([{ ...card, required: true }], { details: {}, asked_key: 'spec_unit_type' }, 'مربعة في السقف (كاسيت)', '', 'ar').details.spec_unit_type, 'Square, in the ceiling (cassette)');
  // Arabic "Not sure" is the field's own not-sure option, never the Arabic words
  const elec = HVAC.find((f) => f.key === 'electrical_supply')!;
  assertEquals(interviewStep(HVAC, { details: {}, asked_key: 'electrical_supply' }, 'لست متأكداً', '', 'ar').details.electrical_supply, 'Not sure');
  assertEquals(elec.options!.includes('Not sure'), true);
  // the REAL handler with the model down (the request already placed in hvac): the first card asks the AC type in Arabic;
  // tapping its Arabic label stores "Cassette"
  const ts = await arabicTurns(['السلام عليكم، أبي مكيفات للفيلا في دبي', cassetteAr], () => null, 'hvac');
  const first = ts[0].json.next_question as { key: string; options: string[] } | null;
  assertEquals(first?.key, 'system_type', 'the model-down interview did not ask the AC type first: ' + JSON.stringify(first));
  assert(first!.options.includes(cassetteAr), 'the Arabic card does not offer ' + cassetteAr + ': ' + JSON.stringify(first!.options));
  assertEquals(ts[1].details.system_type, 'Cassette', 'stored: ' + JSON.stringify(ts[1].details));
});

Deno.test('item 4: on an Arabic chat the category_specs required gate asks in Arabic, never the English label', () => {
  // the gate's wording (interview.ts questionsFor): every required hvac field, in Arabic, is its plain Arabic question
  const required = HVAC.filter((f) => f.required);
  const ar = questionsFor(required, 'ar');
  assertEquals(ar.length, required.length);
  for (const [i, q] of ar.entries()) {
    assert(/[\u0600-\u06FF]/.test(q) && !/[A-Za-z]{2,}/.test(q), 'an English question on an Arabic chat: ' + q);
    assert(q !== required[i].question, 'the English label itself: ' + q);
  }
  // a field with no Arabic of its own still gets Arabic (the frame), never its label; English reads the plain English
  assert(!/[A-Za-z]{2,}/.test(questionsFor([{ key: 'zz_odd', question: 'Odd technical label?' } as SpecField], 'ar')[0]));
  assertEquals(questionsFor([required[0]], 'en')[0], required[0].question_plain_en);
  // the gate itself asks through it. The offline handler could not be steered into this gate (the slots fill or settle every
  // category_specs key before it in every scenario tried), so its block is read: between the absent list and requiredGate it
  // must build both lists with questionsFor and never from the field's own label.
  const src = Deno.readTextFileSync(new URL('./handle.ts', import.meta.url));
  const block = src.slice(src.indexOf('const absent = required.filter(isAbsent);'), src.indexOf('requiredGate = { category, missing_keys'));
  assert(block.length > 100, 'the required gate block was not found in handle.ts');
  assert(/out\.missing = questionsFor\(absent, slotLang\)/.test(block) && /out\.questions = questionsFor\(absent\.slice\(0, 4\), slotLang\)/.test(block), 'the required gate does not ask through questionsFor');
  assert(!/String\(f\.question \|\| f\.key\)/.test(block), 'the required gate reads the English label again');
});

Deno.test('item 5: no question asks for a file the request chat cannot take (a video), and none reaches a supplier unchecked', () => {
  // The request chat's file input (src/components/me/NewRequest.tsx) is what the customer can send. A customer file goes to the
  // drawing/photo readers before any supplier sees it; there is no check for a video (its location metadata, a voice saying a
  // name or a number, a house number in frame), so the questions ask for photos only.
  const tsx = Deno.readTextFileSync(new URL('../../../src/components/me/NewRequest.tsx', import.meta.url));
  const accepts = [...tsx.matchAll(/accept="([^"]+)"/g)].map((m) => m[1]).join(',');
  assert(accepts.length > 10, 'the file inputs were not found');
  const takesVideo = /video\/|\.mp4|\.mov|\.webm|\.3gp/i.test(accepts);
  assertEquals(takesVideo, false, 'the request chat now takes video: give it the identity checks a customer file needs, then this test may change');
  const asks = Object.entries(CUSTOMER_QUESTION).flatMap(([k, q]) => [q.en, q.ar, q.eg_en, q.eg_ar, q.alt_en, q.alt_ar].filter(Boolean).map((t) => [k, String(t)] as const));
  const video = asks.filter(([, t]) => /\bvideo|فيديو|مقطع مصوّر/i.test(t));
  assertEquals(video, [], 'a question asks for a video the chat cannot take: ' + JSON.stringify(video));
});
