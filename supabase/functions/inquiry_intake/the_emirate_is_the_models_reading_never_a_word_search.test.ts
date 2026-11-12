// THE EMIRATE IS WHAT THE MODEL UNDERSTOOD FROM THE CONVERSATION (12 Nov 2026, founder rulings 1664 and 1666; LLM-first
// audit finding A1). Until this date classify.ts detectEmirate searched every customer message for an emirate's letters,
// "rak" included, and its answer came BEFORE the model's: it was the supplier count shown to the customer and the emirate
// the blocking gate filled the location with, and it became the brief's emirate when the model gave none.
//
// MEASURED on origin/main 3baffbc9a by the real handler below (offline: fetch and env stubbed, _shared/twilio_free_harness.ts):
// "this is Mubarak ... garage door brake" with no emirate said counted suppliers in Ras Al Khaimah and filed the brief there;
// a customer in Abu Dhabi who mentioned moving from Dubai was counted in Dubai although the model read Abu Dhabi. (The
// audit's own examples "crack", "brackets", "track" do not contain the letters r-a-k and were never affected; "Mubarak",
// "Barakat", "brake", "rake" are.)
//
// THE MODEL ANSWERS BELOW ARE STAND-INS WRITTEN FOR THIS TEST (labelled ZZ DEMO), not recorded model output: they fix what
// the model said so the test proves only the plumbing — that code takes the emirate from the model's structured answer,
// accepts it only when it is one of the emirates on the closed list, and never reads the customer's text for one.
// 12 Nov 2026, independent review of #1979: an emirate read on a turn that is not ready is kept; the outage path counts in
// the emirate its brief holds; spelling variants of one name are normalised; with none held the location is ASKED once.
//
// AGAINST origin/main: classify.ts has no emirateOf, so this file does not load there. Each scenario below was run through
// main's handler with the import replaced by a stub (deno test --no-check); the result on main is written beside it.
// Run: deno test --no-lock --node-modules-dir=none supabase/functions/inquiry_intake/the_emirate_is_the_models_reading_never_a_word_search.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { emirateOf } from './classify.ts';

type Row = Record<string, unknown>;
const EMAIL = 'zz-demo-emirate-customer@example.invalid';
const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
const fn = () => loadFunction('inquiry_intake', () => import('./index.ts'));
const FIELDS = [
  { key: 'element', type: 'text', options: [], question: 'What work?', required: true },
  { key: 'location', type: 'text', options: [], question: 'Which emirate and area?', required: true },
];
// A ready model turn for carpentry: every checklist key and the four sales-engineer answers, so the brief is built and counted.
const modelTurn = (emirate: unknown, location: string, status = 'ready') => ({
  category: 'carpentry', status, claims_ready: status === 'ready', assistant_message: 'ZZ DEMO stand-in reply', questions: status === 'ready' ? [] : ['How wide?'], readiness: 100,
  requirements: { 'material.board': 'no_preference', 'material.finish': 'no_preference', 'material.hardware': 'no_preference', installation: 'yes', warranty: { months: 12 }, required_by: 'flexible' },
  brief: { summary: 'ZZ DEMO carpentry', category: 'carpentry', scope: '', quantity: '', location, emirate, timeline: '', budget: '', details: { element: 'TV wall unit and garage door', location } },
});

async function turn(text: string, model: Row | null, o: { locale?: string; brief?: Row; turns?: Row[] } = {}) {
  const w = { match: [] as Row[], intake: { id: 'ii-zz-emirate', email: EMAIL, status: 'needs_info', turns: o.turns ?? [], customer_id: 'c-zz-emirate', category: 'carpentry', brief: o.brief ?? { category: 'carpentry', details: {} } } as Row };
  const stub: Stub = {
    user: { id: 'u-zz-emirate', email: EMAIL },
    rows: { customers: [{ id: 'c-zz-emirate', locale: o.locale ?? 'en' }], category_specs: [{ category: 'carpentry', label: 'Carpentry', fields: FIELDS }] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      if (u.pathname === '/functions/v1/ai_gateway') {
        const b = await req.clone().json();
        if (typeof b.sys === 'string' && b.sys.includes('Return STRICT JSON only')) return model ? J({ ok: true, model: 'stub/model', content: JSON.stringify(model) }) : J({ error: 'stub_down' }, 502);
        return J({ ok: true, model: 'stub/model', content: JSON.stringify({ answer: 'ZZ DEMO voiced reply.' }) });
      }
      const r = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1];
      if (r === 'fn_match_capability') { w.match.push(await req.clone().json()); return J([]); }
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      if (t === 'inquiry_intake') {
        if (req.method === 'GET') return J([{ ...w.intake }]);
        if (req.method === 'PATCH') { Object.assign(w.intake, await req.clone().json()); return J([]); }
      }
      return undefined;
    },
  };
  const res = await invoke(await fn(), stub, { intake_id: 'ii-zz-emirate', turn_id: 't-zz-emirate-' + crypto.randomUUID(), lang: o.locale ?? 'en', text });
  return { res, w, saved: (w.intake.brief ?? {}) as Row, next: (res.json?.next_question?.key ?? null) as string | null };
}

// main: brief.emirate "Ras Al Khaimah", counted in RAK, status ready.
Deno.test('A1: a name or a word with the letters "rak" in it is no emirate: nothing is filed in RAK, and the emirate is asked', async () => {
  const { res, w, saved, next } = await turn('ZZ DEMO: this is Mubarak, I need a TV wall unit fixed and the garage door brake replaced', modelTurn('', 'Al Barsha villa'));
  assertEquals([res.json?.status, next], ['needs_info', 'emirate'], 'asked, never skipped because a location detail is filled');
  assert(saved.emirate !== 'Ras Al Khaimah');
  assertEquals(w.match.length, 0, 'nothing counted before the emirate is known');
});

// main: "Ras Al Khaimah".
Deno.test('A1 (Gulf Arabic): "معك Mubarak ... أبي" with no emirate stated is not read as Ras Al Khaimah; asked in Arabic', async () => {
  const { res, saved, next } = await turn('ZZ DEMO: مرحبا، معك Mubarak، أبي أحد يركّب وحدة تلفزيون ويصلّح فرامل باب الكراج', modelTurn('', 'فيلا في البرشاء'), { locale: 'ar' });
  assertEquals(next, 'emirate');
  assertEquals(res.json?.next_question?.options?.[0], 'دبي');
  assert(saved.emirate !== 'Ras Al Khaimah');
});

// main: counted in Dubai (code's list order) although the model read Abu Dhabi.
Deno.test('A1: the emirate the model understood is the one counted, never a code reading of the words over it', async () => {
  const { w, saved } = await turn('ZZ DEMO: we just moved from Dubai, the new villa is in Khalifa City, Abu Dhabi. Barakat family.', modelTurn('Abu Dhabi', 'Khalifa City, Abu Dhabi'));
  assertEquals(saved.emirate, 'Abu Dhabi');
  assertEquals(w.match[0]?.p_emirate, 'Abu Dhabi');
});

// main: no emirate question; the raw model value ("JLT", "UAE" ...) stored as brief.emirate and the request ready.
Deno.test('A1: a model value that is an area, two emirates or "UAE" is not stored: the emirate is asked once, and only once', async () => {
  for (const v of ['JLT', 'Dubai Marina', 'DXB', 'UAE', 'Abu Dhabi and Dubai']) {
    const first = await turn('ZZ DEMO: TV wall unit in JLT', modelTurn(v, 'JLT'));
    assertEquals([first.next, first.saved.emirate ?? ''], ['emirate', ''], v);
    // the second turn: the model still gives none; it is not asked again and the request goes on, counted across the UAE
    const second = await turn('ZZ DEMO: not sure which', modelTurn(v, 'JLT'), { brief: first.saved, turns: first.w.intake.turns as Row[] });
    assertEquals([second.res.json?.status, second.w.match[0]?.p_emirate], ['ready', null], v);
  }
});

// main: no emirate question exists; the tap is not recorded and the count has no emirate.
Deno.test('A1: the tapped answer to the emirate question is recorded (a fixed payload), in English and Arabic', async () => {
  for (const [locale, tap, want] of [['en', 'Sharjah', 'Sharjah'], ['ar', 'رأس الخيمة', 'Ras Al Khaimah']] as const) {
    const t = await turn(tap, modelTurn('', 'Al Majaz'), { locale, brief: { category: 'carpentry', details: {}, emirate_asked: true } });
    assertEquals([t.saved.emirate, t.w.match[0]?.p_emirate], [want, want], locale);
  }
});

// main: the not-ready brief holds no emirate after turn 1 (fails here); main's count read "Dubai" off the words instead.
Deno.test('A1: an emirate the model read on a turn that is not ready is kept when a later turn gives none', async () => {
  const t1 = await turn('ZZ DEMO: TV wall unit, Dubai', modelTurn('Dubai', '', 'needs_info'));
  assertEquals(t1.saved.emirate, 'Dubai');
  const t2 = await turn('Al Barsha', modelTurn('', 'Al Barsha'), { brief: t1.saved, turns: t1.w.intake.turns as Row[] });
  assertEquals([t2.saved.emirate, t2.w.match[0]?.p_emirate], ['Dubai', 'Dubai']);
});

// main: passes (counted in Dubai, read off the words). The branch before this fix: brief Dubai, count with no emirate.
Deno.test('A1, OpenRouter down: the count uses the emirate the deterministic interview\'s brief holds', async () => {
  const FULL = { 'material.board': { v: 'no_preference' }, 'material.finish': { v: 'no_preference' }, 'material.hardware': { v: 'no_preference' }, installation: { v: 'yes' }, warranty: { v: 'yes', min_months: 12 }, required_by: { v: 'flexible', date: null, text: 'Flexible' } };
  const t = await turn('Dubai Marina, Dubai', null, { brief: { category: 'carpentry', details: { element: 'TV wall unit' }, asked_key: 'location', req_answers: FULL },
    turns: [{ role: 'user', text: 'ZZ DEMO: TV wall unit made and installed' }, { role: 'assistant', text: 'Which emirate and area?' }] });
  assertEquals(t.saved.emirate, 'Dubai');
  assertEquals(t.w.match[0]?.p_emirate, 'Dubai');
});

Deno.test('A1: the prompt asks the model to place an area in its emirate as a person would, from the seven names', async () => {
  const sys: string[] = [];
  const h = await fn();
  await invoke(h, { user: { id: 'u-zz-emirate', email: EMAIL }, rows: { customers: [{ id: 'c-zz-emirate', locale: 'en' }], category_specs: [{ category: 'carpentry', label: 'Carpentry', fields: FIELDS }] }, rpc: { rl_check: true },
    handle: async (req, u) => {
      if (u.pathname === '/functions/v1/ai_gateway') { const b = await req.clone().json(); if (typeof b.sys === 'string') sys.push(b.sys); return J({ ok: true, model: 'stub/model', content: JSON.stringify(modelTurn('Dubai', 'JLT')) }); }
      if (u.pathname === '/rest/v1/inquiry_intake') return J([{ id: 'ii-zz-emirate', email: EMAIL, status: 'needs_info', turns: [], category: 'carpentry', brief: { category: 'carpentry', details: {} } }]);
      return undefined;
    } }, { intake_id: 'ii-zz-emirate', turn_id: 't-zz-emirate-sys', lang: 'en', text: 'ZZ DEMO TV unit in JLT' });
  const p = sys.find((x) => x.includes('Return STRICT JSON only')) ?? '';
  assert(p.includes('an area, community or city that lies in one emirate IS that emirate'), 'placed as a person would');
  assert(p.includes('Dubai, Abu Dhabi, Sharjah, Ajman, Ras Al Khaimah, Fujairah, Umm Al Quwain'));
  assert(!p.includes('never guessed from a name or a word'));
});

Deno.test('A1: emirateOf accepts only an emirate on the closed list, in any spelling of that one name', () => {
  for (const [v, e] of [['Dubai', 'Dubai'], [' abu dhabi ', 'Abu Dhabi'], ['RAS AL KHAIMAH', 'Ras Al Khaimah'], ['RAK', 'Ras Al Khaimah'], ['UAQ', 'Umm Al Quwain'],
    ['Umm Al Quwain', 'Umm Al Quwain'], ['Fujairah', 'Fujairah'], ['Ajman', 'Ajman'], ['Sharjah', 'Sharjah'], ['Al Ain', 'Al Ain'],
    ['Ras al-Khaimah', 'Ras Al Khaimah'], ['Dubai, UAE', 'Dubai'], ['Emirate of Sharjah', 'Sharjah'], ['Abu Dhabi city', 'Abu Dhabi'], ['إمارة دبي', 'Dubai'],
    ['دبي', 'Dubai'], ['أبوظبي', 'Abu Dhabi'], ['أبو ظبي', 'Abu Dhabi'], ['الشارقة', 'Sharjah'], ['رأس الخيمة', 'Ras Al Khaimah'], ['عجمان', 'Ajman'], ['الفجيرة', 'Fujairah'], ['أم القيوين', 'Umm Al Quwain']] as const) {
    assertEquals(emirateOf(v), e, v);
  }
  for (const v of ['', null, undefined, 'Mubarak', 'brake', 'Dubai Marina', 'JLT', 'DXB', 'JLT, Dubai', 'Dubai or Sharjah', 'Abu Dhabi and Dubai', 'UAE', 'rak road', 42]) assertEquals(emirateOf(v), null, String(v));
});
