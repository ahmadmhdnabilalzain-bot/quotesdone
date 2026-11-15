// THE SALES ENGINEER'S FOUR QUESTIONS ARE UNDERSTOOD BY THE MODEL (12 Nov 2026, founder rulings 1664 and 1666; LLM-first
// audit finding A7). Installation, warranty, materials and needed-by were asked by code, and on the turn after each question
// the customer's reply was read by code (_shared/intake_requirements.ts parseRequirementAnswer and statedAnswers), with the
// model's reading of the same turn only filling what code had not, and an earlier answer always beating the model's newer one.
//
// MEASURED on origin/main 3baffbc9a by the real handler below (offline: fetch and env stubbed, _shared/twilio_free_harness.ts):
//   * "What's the difference between supply only and installing it?" was recorded as installation "yes" (it contains
//     "install"), and the Gulf Arabic "شنو الفرق بين التوريد بس والتركيب؟" the same (it contains "تركيب");
//   * "Actually make the warranty two years" left the warranty at one year although the model read two;
//   * "Supply and fix please", which the model had not filed, got "I couldn't match that to one of the answers".
//
// THE MODEL ANSWERS BELOW ARE STAND-INS WRITTEN FOR THIS TEST (labelled ZZ DEMO), not recorded model output: they fix what
// the model understood so the test proves the plumbing — the model's reading of the turn is the answer, a tapped option is
// read by code, and code never reads the customer's words for these answers while a model reading exists.
// AGAINST origin/main: intake_requirements.ts has no tappedAnswer and slots.ts no mergeRequirements/answerToQuestion, so this
// file does not load there. Run through main's handler with those imports stubbed (deno test --no-check): the two controls
// (a tap; the model's mixed-installation reading) and the kept date pass on main; every other scenario fails there, as
// each test's comment says; the mergeRequirements test cannot run on main (no such function).
// Run: deno test --no-lock --node-modules-dir=none supabase/functions/inquiry_intake/the_four_questions_are_understood_by_the_model.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { requirementsStep, requirementQuestions, tappedAnswer, type Answers } from '../_shared/intake_requirements.ts';
import { answerToQuestion, mergeRequirements } from './slots.ts';

type Row = Record<string, unknown>;
const EMAIL = 'zz-demo-four-questions@example.invalid';
const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
const fn = () => loadFunction('inquiry_intake', () => import('./index.ts'));
const FIELDS = [
  { key: 'element', type: 'text', options: [], question: 'What work?', required: true },
  { key: 'location', type: 'text', options: [], question: 'Which emirate and area?', required: true },
];
const MATERIALS = { 'material.board': { v: 'mr_mdf' }, 'material.finish': { v: 'laminate' }, 'material.hardware': { v: 'standard' } };
const QUESTION: Record<string, string> = {
  installation: 'Do you need the supplier to install it, or only deliver it?',
  required_by: 'By when do you need it done or delivered? Tap one, or type a date.',
};
// The stand-in model turn: the job is fully described; `requirements` and `answer_to_question` are what it understood.
const modelTurn = (requirements: Row, answer = '') => ({
  category: 'carpentry', status: 'ready', claims_ready: true, assistant_message: 'ZZ DEMO stand-in reply', questions: [], readiness: 100,
  requirements, answer_to_question: answer,
  brief: { summary: 'ZZ DEMO majlis and kitchen joinery', category: 'carpentry', scope: '', quantity: '', location: 'Al Barsha, Dubai', emirate: 'Dubai', timeline: '', budget: '', details: { element: 'Majlis and kitchen cabinets', location: 'Al Barsha, Dubai' } },
});

async function turn(o: { prev: Answers; asked: string; text: string; model: Row | null; locale?: 'en' | 'ar' }) {
  const w = { drafts: [] as string[], sys: '',
    intake: { id: 'ii-zz-four', email: EMAIL, status: 'needs_info', customer_id: 'c-zz-four', category: 'carpentry',
      turns: [{ role: 'user', text: 'ZZ DEMO: cabinets for the majlis and the kitchen, Al Barsha, Dubai' }, { role: 'assistant', text: QUESTION[o.asked] ?? 'ZZ DEMO question' }],
      brief: { category: 'carpentry', state: 'interview', details: { element: 'Majlis and kitchen cabinets', location: 'Al Barsha, Dubai' }, req_answers: o.prev, req_asked: o.asked } } as Row };
  const stub: Stub = {
    user: { id: 'u-zz-four', email: EMAIL },
    rows: { customers: [{ id: 'c-zz-four', locale: o.locale ?? 'en' }], category_specs: [{ category: 'carpentry', label: 'Carpentry', fields: FIELDS }] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      if (u.pathname === '/functions/v1/ai_gateway') {
        const b = await req.clone().json();
        const interview = typeof b.sys === 'string' && b.sys.includes('Return STRICT JSON only');
        if (interview) w.sys = String(b.sys) + '\n' + (Array.isArray(b.input) ? b.input : []).map((m: { content?: unknown }) => typeof m?.content === 'string' ? m.content : JSON.stringify(m?.content ?? '')).join('\n');   // the whole prompt: the turn's records ride in the message (15 Nov 2026)
        if (interview) return o.model ? J({ ok: true, model: 'stub/model', content: JSON.stringify(o.model) }) : J({ error: 'stub_down' }, 502);
        w.drafts.push(JSON.stringify(b));   // the reply writer: what code asked it to say
        return J({ ok: true, model: 'stub/model', content: JSON.stringify({ answer: 'ZZ DEMO voiced reply.' }) });
      }
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      if (t === 'inquiry_intake') {
        if (req.method === 'GET') return J([{ ...w.intake }]);
        if (req.method === 'PATCH') { Object.assign(w.intake, await req.clone().json()); return J([]); }
      }
      return undefined;
    },
  };
  const res = await invoke(await fn(), stub, { intake_id: 'ii-zz-four', turn_id: 't-zz-four-' + crypto.randomUUID(), lang: o.locale ?? 'en', text: o.text });
  const brief = (w.intake.brief ?? {}) as Row;
  return { res, saved: (brief.req_answers ?? {}) as Answers, next: (res.json?.next_question?.key ?? null) as string | null, drafts: w.drafts.join('\n'), sys: w.sys };
}

const COULD_NOT_MATCH = /couldn't match|لم أتمكن من مطابقة/;

Deno.test('A7: a reply that asks something back is answered and the question asked again, never recorded as an answer', async () => {
  const r = await turn({ prev: MATERIALS, asked: 'installation', text: "ZZ DEMO: what's the difference between supply only and installing it?",
    model: modelTurn({ 'material.board': 'mr_mdf', 'material.finish': 'laminate', 'material.hardware': 'standard' }, 'Supply only means the supplier delivers the cabinets and your own team fits them; with installation the supplier fits them too.') });
  assertEquals(r.res.status, 200, JSON.stringify(r.res.json).slice(0, 300));
  assertEquals(r.saved.installation, undefined, 'a question is not an answer');
  assertEquals(r.next, 'installation', 'asked again');
  assert(r.drafts.includes('Supply only means the supplier delivers'), 'the model\'s answer to their question is in what the reply says');
  assert(r.drafts.length > 0 && !COULD_NOT_MATCH.test(r.drafts), 'never "I couldn\'t match that"');
});

Deno.test('A7 (Gulf Arabic): "شنو الفرق بين التوريد بس والتركيب؟" is a question, not an installation answer', async () => {
  const r = await turn({ prev: MATERIALS, asked: 'installation', locale: 'ar', text: 'ZZ DEMO: شنو الفرق بين التوريد بس والتركيب؟',
    model: modelTurn({ 'material.board': 'mr_mdf', 'material.finish': 'laminate', 'material.hardware': 'standard' }, 'التوريد فقط يعني أن المورّد يسلّم الخزائن ويركّبها فريقكم، ومع التركيب يتولّى المورّد تركيبها.') });
  assertEquals(r.saved.installation, undefined);
  assertEquals(r.next, 'installation');
  assert(r.drafts.length > 0 && !COULD_NOT_MATCH.test(r.drafts));
});

Deno.test('A7: an answer the customer changes is the model\'s latest reading, and one message can answer two questions', async () => {
  const r = await turn({ prev: { ...MATERIALS, installation: { v: 'yes' }, warranty: { v: 'yes', min_months: 12 } }, asked: 'required_by',
    text: 'ZZ DEMO: actually make the warranty two years, and we need it within a month',
    model: { ...modelTurn({ 'material.board': 'mr_mdf', 'material.finish': 'laminate', 'material.hardware': 'standard', installation: 'yes', warranty: { months: 24 }, required_by: { days: 30, text: 'within a month' } }), changed_answers: ['warranty'] } });
  assertEquals(r.saved.warranty, { v: 'yes', min_months: 24 }, 'the newer answer replaces the earlier one');
  assertEquals(r.saved.required_by?.v, 'date', 'the same message answered the date');
  assertEquals(r.next, null, 'nothing left to ask');
  assertEquals(r.res.json?.status, 'ready');
});

Deno.test('A7: "Supply and fix please" the model did not file is asked again plainly; code does not read it, and never says it could not match', async () => {
  const r = await turn({ prev: MATERIALS, asked: 'installation', text: 'ZZ DEMO: Supply and fix please',
    model: modelTurn({ 'material.board': 'mr_mdf', 'material.finish': 'laminate', 'material.hardware': 'standard' }) });
  assertEquals(r.saved.installation, undefined);
  assertEquals(r.next, 'installation');
  assert(r.drafts.length > 0 && !COULD_NOT_MATCH.test(r.drafts), r.drafts.slice(0, 400));
});

Deno.test('A7: "No installation in the kitchen, but the majlis needs it" is what the model read it as (yes), not supply only', async () => {
  const r = await turn({ prev: MATERIALS, asked: 'installation', text: 'ZZ DEMO: no installation in the kitchen, but the majlis needs full installation',
    model: modelTurn({ 'material.board': 'mr_mdf', 'material.finish': 'laminate', 'material.hardware': 'standard', installation: 'yes' }) });
  assertEquals(r.saved.installation, { v: 'yes' });
  assertEquals(r.next, 'warranty');
});

Deno.test('A7: a tapped option is a fixed payload and is recorded by code, in English and Arabic', async () => {
  for (const [locale, text] of [['en', 'Supply only, no installation'], ['ar', 'توريد فقط، بدون تركيب']] as const) {
    const r = await turn({ prev: MATERIALS, asked: 'installation', locale, text, model: modelTurn({ 'material.board': 'mr_mdf', 'material.finish': 'laminate', 'material.hardware': 'standard' }) });
    assertEquals(r.saved.installation, { v: 'supply_only' }, locale);
    assertEquals(r.next, 'warranty', locale);
  }
});

Deno.test('A7: with a model reading, requirementsStep reads nothing of the words; without one (OpenRouter down) code still does', () => {
  const now = new Date('2026-11-12T10:00:00Z');
  const conv = 'ZZ DEMO kitchen cabinets. No installation in the kitchen, but the majlis needs full installation. 2 year warranty.';
  const withModel = requirementsStep('carpentry', MATERIALS, 'installation', 'Supply and fix please', {}, 'en', now, conv, { modelRead: true });
  assertEquals(withModel.answers.installation, undefined, 'statedAnswers is not read over the model');
  assertEquals(withModel.answers.warranty, undefined);
  assertEquals([withModel.unanswered, withModel.retry], [true, false]);
  assertEquals(withModel.next?.key, 'installation');
  const outage = requirementsStep('carpentry', MATERIALS, 'installation', 'Supply and fix please', {}, 'en', now, conv);
  assertEquals(outage.answers.warranty, { v: 'yes', min_months: 24 }, 'no model reading: code\'s reading is all there is');
  // the highlighted suggestion is a fixed payload too: tapping it records it
  const inst = requirementQuestions('cleaning').find((q) => q.key === 'installation')!;
  assertEquals(tappedAnswer(inst, 'Not needed for this job'), { v: 'not_needed' });
  assertEquals(tappedAnswer(inst, 'supply and fix please'), null);
  const tapS = requirementsStep('cleaning', { 'material.products': { v: 'standard' } }, 'installation', 'غير مطلوب لهذا العمل', {}, 'ar', now, '', { modelRead: true });
  assertEquals(tapS.answers.installation, { v: 'not_needed' });
});

// ── independent review of #1979, 12 Nov 2026 ──────────────────────────────────────────────────────────────────────────
const M3 = { 'material.board': 'mr_mdf', 'material.finish': 'laminate', 'material.hardware': 'standard' };

// main: installation stays supply_only (main's earlier answer always won). Branch before this fix: overwritten with "yes".
Deno.test('A7: a model slip on another question never rewrites a recorded answer; a change the model declares does', async () => {
  const slip = await turn({ prev: { ...MATERIALS, installation: { v: 'supply_only' } }, asked: 'warranty', text: '2 years',
    model: modelTurn({ ...M3, installation: 'yes', warranty: { months: 24 } }) });
  assertEquals(slip.saved.installation, { v: 'supply_only' }, 'the tapped answer stands');
  assertEquals(slip.saved.warranty, { v: 'yes', min_months: 24 }, 'the question asked is answered');
  const changed = await turn({ prev: { ...MATERIALS, installation: { v: 'yes' } }, asked: 'warranty', text: 'ZZ DEMO: actually supply only, our own team will fit it',
    model: { ...modelTurn({ ...M3, installation: 'supply_only' }), changed_answers: ['installation'] } });
  assertEquals(changed.saved.installation, { v: 'supply_only' });
  // what the model is shown: the recorded answers and the rule
  assert(slip.sys.includes('RECORDED (what the customer already answered): "material.board": "mr_mdf"') && slip.sys.includes('"installation": "supply_only"'), 'recorded answers are in the prompt');
  assert(slip.sys.includes('changed_answers'));
});

// main: the date stays (the earlier answer won). Branch before this fix: re-anchored to the later turn.
Deno.test('A7: an unchanged needed-by date keeps its date when a later turn re-reads "within a month"', async () => {
  const r = await turn({ prev: { ...MATERIALS, required_by: { v: 'date', date: '2026-12-01', text: 'within a month' } }, asked: 'installation', text: 'Yes, install it',
    model: modelTurn({ ...M3, installation: 'yes', required_by: { days: 30, text: 'within a month' } }) });
  assertEquals(r.saved.required_by, { v: 'date', date: '2026-12-01', text: 'within a month' });
  assertEquals(r.saved.installation, { v: 'yes' });
});

// main and branch before this fix: ready with only "Thank you — that is everything suppliers need", the answer dropped.
Deno.test('A7: a question asked in the message that completes the four is answered in the ready reply', async () => {
  const r = await turn({ prev: { ...MATERIALS, installation: { v: 'yes' }, warranty: { v: 'yes', min_months: 12 } }, asked: 'required_by', text: 'ZZ DEMO: within a month. Does the price include VAT?',
    model: modelTurn({ ...M3, installation: 'yes', warranty: { months: 12 }, required_by: { days: 30, text: 'within a month' } }, 'ZZ DEMO each supplier states VAT in the quote.') });
  assertEquals(r.res.json?.status, 'ready');
  assert(r.drafts.includes('ZZ DEMO each supplier states VAT in the quote.'), 'the answer reaches the reply');
});

Deno.test('A7: the prompt bounds the answer to a question, bans promises, and gives Gulf Arabic examples', async () => {
  const r = await turn({ prev: MATERIALS, asked: 'installation', text: 'Yes, install it', model: modelTurn({ ...M3, installation: 'yes' }) });
  for (const t of ['under 300 characters', 'never promise a delivery or completion date, installation, a supplier, a price, a discount, a refund', '"بس توريد" is "supply_only"', '"ضمان سنتين" is warranty {"months": 24}'])
    assert(r.sys.includes(t), t);
  const long = answerToQuestion('ZZ DEMO ' + 'word '.repeat(200));
  assert(long.length <= 401 && !/wor$/.test(long), long.slice(-20));
  assertEquals(answerToQuestion('Short answer.'), 'Short answer.');
  assertEquals(answerToQuestion(42), '');
});

Deno.test('A7: mergeRequirements: a new key is taken, a recorded one only when declared changed or it is the question asked', () => {
  const rec: Answers = { installation: { v: 'supply_only' }, warranty: { v: 'yes', min_months: 12 } };
  const model: Answers = { installation: { v: 'yes' }, warranty: { v: 'yes', min_months: 24 }, required_by: { v: 'flexible', date: null, text: 'Flexible' } };
  assertEquals(mergeRequirements(rec, model, [], null), { ...rec, required_by: model.required_by });
  assertEquals(mergeRequirements(rec, model, ['warranty'], null).warranty, model.warranty);
  assertEquals(mergeRequirements(rec, model, 'warranty', 'installation').installation, model.installation, 'the question asked; a non-array is ignored');
});
