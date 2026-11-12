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
// Run: deno test --no-lock --node-modules-dir=none supabase/functions/inquiry_intake/the_emirate_is_the_models_reading_never_a_word_search.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
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
const modelTurn = (emirate: string, location: string) => ({
  category: 'carpentry', status: 'ready', claims_ready: true, assistant_message: 'ZZ DEMO stand-in reply', questions: [], readiness: 100,
  requirements: { 'material.board': 'no_preference', 'material.finish': 'no_preference', 'material.hardware': 'no_preference', installation: 'yes', warranty: { months: 12 }, required_by: 'flexible' },
  brief: { summary: 'ZZ DEMO carpentry', category: 'carpentry', scope: '', quantity: '', location, emirate, timeline: '', budget: '', details: { element: 'TV wall unit and garage door', location } },
});

async function turn(text: string, model: Row, locale = 'en') {
  const w = { match: [] as Row[], intake: { id: 'ii-zz-emirate', email: EMAIL, status: 'needs_info', turns: [], customer_id: 'c-zz-emirate', category: 'carpentry', brief: { category: 'carpentry', details: {} } } as Row };
  const stub: Stub = {
    user: { id: 'u-zz-emirate', email: EMAIL },
    rows: { customers: [{ id: 'c-zz-emirate', locale }], category_specs: [{ category: 'carpentry', label: 'Carpentry', fields: FIELDS }] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      if (u.pathname === '/functions/v1/ai_gateway') {
        const b = await req.clone().json();
        return J({ ok: true, model: 'stub/model', content: b.fn === 'inquiry_intake' ? JSON.stringify(model) : JSON.stringify({ answer: 'ZZ DEMO voiced reply.' }) });
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
  const res = await invoke(await fn(), stub, { intake_id: 'ii-zz-emirate', turn_id: 't-zz-emirate', lang: locale, text });
  return { res, w, brief: (res.json?.brief ?? {}) as Row };
}

Deno.test('A1: a name or a word with the letters "rak" in it is no emirate: the request is not filed or counted in Ras Al Khaimah', async () => {
  const { res, w, brief } = await turn('ZZ DEMO: this is Mubarak, I need a TV wall unit fixed and the garage door brake replaced', modelTurn('', 'Al Barsha villa'));
  assertEquals(res.json?.status, 'ready', JSON.stringify(res.json).slice(0, 400));
  assertEquals(brief.emirate, '', 'no emirate was said and the model read none');
  assertEquals(w.match.length, 1, 'the supplier count ran');
  assertEquals(w.match[0].p_emirate, null, 'counted across the UAE, not in Ras Al Khaimah');
});

Deno.test('A1 (Gulf Arabic): "معك Mubarak ... أبي" with no emirate stated is not read as Ras Al Khaimah', async () => {
  const { res, w, brief } = await turn('ZZ DEMO: مرحبا، معك Mubarak، أبي أحد يركّب وحدة تلفزيون ويصلّح فرامل باب الكراج', modelTurn('', 'فيلا في البرشاء'), 'ar');
  assertEquals(res.json?.status, 'ready', JSON.stringify(res.json).slice(0, 400));
  assertEquals(brief.emirate, '');
  assertEquals(w.match[0]?.p_emirate, null);
});

Deno.test('A1: the emirate the model understood is the one counted, never a code reading of the words over it', async () => {
  // The job is in Abu Dhabi; Dubai is only where they moved from. The first emirate on code's list (Dubai) used to win.
  const { w, brief } = await turn('ZZ DEMO: we just moved from Dubai, the new villa is in Khalifa City, Abu Dhabi. Barakat family.', modelTurn('Abu Dhabi', 'Khalifa City, Abu Dhabi'));
  assertEquals(brief.emirate, 'Abu Dhabi');
  assertEquals(w.match[0]?.p_emirate, 'Abu Dhabi');
});

Deno.test('A1: a model emirate that is not on the closed list is not stored or counted: code does not guess a better one', async () => {
  const { w, brief } = await turn('ZZ DEMO: the job is in JLT, Mubarak tower', modelTurn('JLT', 'JLT'));
  assertEquals(brief.emirate, '', 'an area is not an emirate');
  assertEquals(w.match[0]?.p_emirate, null);
});

Deno.test('A1: emirateOf accepts only an emirate on the closed list, as the model wrote it', () => {
  for (const [v, e] of [['Dubai', 'Dubai'], [' abu dhabi ', 'Abu Dhabi'], ['RAS AL KHAIMAH', 'Ras Al Khaimah'], ['RAK', 'Ras Al Khaimah'], ['UAQ', 'Umm Al Quwain'],
    ['Umm Al Quwain', 'Umm Al Quwain'], ['Fujairah', 'Fujairah'], ['Ajman', 'Ajman'], ['Sharjah', 'Sharjah'], ['Al Ain', 'Al Ain'],
    ['دبي', 'Dubai'], ['أبوظبي', 'Abu Dhabi'], ['أبو ظبي', 'Abu Dhabi'], ['الشارقة', 'Sharjah'], ['رأس الخيمة', 'Ras Al Khaimah'], ['عجمان', 'Ajman'], ['الفجيرة', 'Fujairah'], ['أم القيوين', 'Umm Al Quwain']] as const) {
    assertEquals(emirateOf(v), e, v);
  }
  for (const v of ['', null, undefined, 'Mubarak', 'brake', 'Dubai Marina', 'JLT, Dubai', 'Dubai or Sharjah', 'UAE', 'rak road', 42]) assertEquals(emirateOf(v), null, String(v));
});
