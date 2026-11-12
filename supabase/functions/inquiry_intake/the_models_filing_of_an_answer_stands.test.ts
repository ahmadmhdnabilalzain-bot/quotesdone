// THE MODEL'S FILING OF AN ANSWER STANDS (12 Nov 2026, founder rulings 1664 and 1666; LLM-first audit finding A6). Since
// 10 Nov (df1fc21ed, evidence run finding b2) slots.ts reconcileSlots MOVED a value the model filed under a checklist key
// whenever the value "looked like" only a date, money, a warranty or an emirate (interview.ts answersAnotherKind, a word
// list): it was refiled under the timeline, budget, warranty or location, and the asked spec stayed open and was asked again.
//
// MEASURED on origin/main 3baffbc9a (reconcileSlots, the function the real turn calls):
//   * "AMC contract period?" answered "12 months" was moved to the timeline, so the request carried a 12-month deadline it
//     never had and the AMC period was asked again; "Hire period?" -> "2 weeks" the same;
//   * "Payment terms?" answered "30 days" was moved to the timeline;
//   * "Which area / community?" answered "دبي" ("Dubai") was moved to location and the area asked again.
// (The audit's own "JLT, Dubai" example is NOT moved on main: "JLT" is a word of no universal kind, so the guard let it stand.)
//
// The incident the guard was written for (RFQ 164464, 10 Nov): the model filed "We need it finished by 15 December 2026." under
// "MEP scope" and "At least 2 years warranty ..." under "Authority approvals". That is now the model's instruction (rule 16 of
// the interview prompt, extended below with the duration and the area cases), not a word list over its answer. Whether the
// model follows it is proven by a paid replay of that one turn, not here: THE MODEL ANSWERS BELOW ARE STAND-INS (ZZ DEMO).
// Run: deno test --no-lock --node-modules-dir=none supabase/functions/inquiry_intake/the_models_filing_of_an_answer_stands.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { type SpecField } from './interview.ts';
import { reconcileSlots } from './slots.ts';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const slots = (fields: SpecField[], det: Record<string, string>, extra: Record<string, unknown> = {}, said?: string) =>
  reconcileSlots(fields, {}, { brief: { details: det }, ...extra }, 'en', {}, [], said);
const f = (key: string, question: string, required = true) => ({ key, question, type: 'text', required }) as SpecField;

Deno.test('A6: a duration the model filed under a period spec is that spec\'s answer, never moved to a deadline', () => {
  const AMC = [f('amc_contract_period', 'AMC contract period?'), f('timeline', 'By when do you need it?', false)];
  const s = slots(AMC, { amc_contract_period: '12 months' });
  assertEquals(s.details.amc_contract_period, '12 months');
  assertEquals(s.details.timeline, undefined, 'no deadline was invented');
  assertEquals(s.complete, true);
  const HIRE = [f('hire_period', 'Hire period'), f('required_by', 'Needed by', false)];
  assertEquals(slots(HIRE, { hire_period: '2 weeks' }).details, { hire_period: '2 weeks' });
  const PAY = [f('payment_terms', 'Payment terms?'), f('timeline', 'When?', false)];
  assertEquals(slots(PAY, { payment_terms: '30 days' }).details, { payment_terms: '30 days' });
});

Deno.test('A6 (Arabic): "دبي" filed by the model as the area stands; the model, not a word list, decides what it answers', () => {
  const AREA = [f('area_community', 'Which area / community?'), f('location', 'Which emirate?', false)];
  const s = slots(AREA, { area_community: 'دبي' });
  assertEquals(s.details.area_community, 'دبي');
  assertEquals(s.missingKeys, []);
  const ar = slots([f('amc_contract_period', 'مدة عقد الصيانة؟'), f('timeline', 'متى؟', false)], { amc_contract_period: '١٢ شهر' });
  assertEquals(ar.details.amc_contract_period, '١٢ شهر');
});

Deno.test('A6: what stays code — a cited detail must be the customer\'s own words, and "supplier to advise" counts', () => {
  const MEP = [f('spec_mep_scope', 'MEP scope')];
  const said = 'ZZ DEMO MEP: no electrical or AC work near the wall.';
  assertEquals(slots(MEP, { spec_mep_scope: 'No MEP works' }, { spec_evidence: { spec_mep_scope: 'no electrical or AC work near the wall' } }, said).details.spec_mep_scope, 'No MEP works');
  assertEquals(slots(MEP, { spec_mep_scope: 'No MEP works' }, { spec_evidence: { spec_mep_scope: 'the customer confirmed no MEP' } }, said).details.spec_mep_scope, undefined);
  assertEquals(slots(MEP, { spec_mep_scope: 'Customer does not know: supplier to advise' }).complete, true);
});

// ── the real handler: the model is told where an answer goes, and its filing is what the turn records ────────────────────
type Row = Record<string, unknown>;
const EMAIL = 'zz-demo-a6-customer@example.invalid';
const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
Deno.test('A6 on the real handler: "12 months" to the AMC period is recorded there, and the prompt carries the filing rule', async () => {
  const h = await loadFunction('inquiry_intake', () => import('./index.ts'));
  const FIELDS = [f('equipment', 'Which equipment is covered?'), f('amc_contract_period', 'AMC contract period?'), f('location', 'Which emirate and area?')];
  const model = { category: 'hvac', status: 'ready', claims_ready: true, assistant_message: 'ZZ DEMO stand-in', questions: [], readiness: 100,
    requirements: { 'material.brand': 'no_preference', 'material.ducting': 'no_preference', installation: 'not_needed', warranty: 'not_needed', required_by: 'flexible' },
    spec_evidence: { equipment: 'six split units', amc_contract_period: '12 months', location: 'Al Barsha, Dubai' },
    brief: { summary: 'ZZ DEMO AMC', category: 'hvac', emirate: 'Dubai', location: 'Al Barsha, Dubai', details: { equipment: 'six split units', amc_contract_period: '12 months', location: 'Al Barsha, Dubai' } } };
  const sys: string[] = [];
  const intake: Row = { id: 'ii-zz-a6', email: EMAIL, status: 'needs_info', customer_id: 'c-zz-a6', category: 'hvac',
    turns: [{ role: 'user', text: 'ZZ DEMO AMC for six split units, Al Barsha, Dubai' }, { role: 'assistant', text: 'What AMC contract period do you need?' }],
    brief: { category: 'hvac', state: 'interview', details: { equipment: 'six split units', location: 'Al Barsha, Dubai' }, asked_key: 'amc_contract_period' } };
  const stub: Stub = {
    user: { id: 'u-zz-a6', email: EMAIL },
    rows: { customers: [{ id: 'c-zz-a6', locale: 'en' }], category_specs: [{ category: 'hvac', label: 'HVAC', fields: FIELDS }] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      if (u.pathname === '/functions/v1/ai_gateway') {
        const b = await req.clone().json();
        if (typeof b.sys === 'string' && b.sys.includes('Return STRICT JSON only')) { sys.push(b.sys); return J({ ok: true, model: 'stub/model', content: JSON.stringify(model) }); }
        return J({ ok: true, model: 'stub/model', content: JSON.stringify({ answer: 'ZZ DEMO voiced reply.' }) });
      }
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      if (t === 'inquiry_intake') {
        if (req.method === 'GET') return J([{ ...intake }]);
        if (req.method === 'PATCH') { Object.assign(intake, await req.clone().json()); return J([]); }
      }
      return undefined;
    },
  };
  const r = await invoke(h, stub, { intake_id: 'ii-zz-a6', text: '12 months', turn_id: 't-zz-a6-1', lang: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.json).slice(0, 300));
  const details = ((intake.brief as Row).details ?? {}) as Row;
  assertEquals(details.amc_contract_period, '12 months', 'the model\'s filing stands');
  assertEquals(details.timeline, undefined);
  assert(!(r.json.missing_keys as string[] ?? []).includes('amc_contract_period'), 'the AMC period is not asked again');
  assert(sys[0]?.includes('AN ANSWER GOES UNDER THE SPEC IT ANSWERS') && sys[0].includes('a duration asked for'), 'the filing rule is the model\'s instruction');
});
