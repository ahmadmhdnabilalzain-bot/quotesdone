// The founder's own request, replayed to a postable request with no model.
// deno test supabase/functions/inquiry_intake/generators_replay.test.ts
//
// 14 Sep 2026, 08:42 and 08:43 UTC: "I need Generators work (generators)" in the portal. The model
// routes were held, the keyword map had no word for generators, the router asked "Industrial
// Equipment Suppliers or something else", the category fell to 'general' at readiness 10, and no
// inquiry was created (inquiry_intake e94c7678, b08d3296). This replays the same words through the
// same deterministic pieces index.ts runs — classify, the category interview, the sales engineer's
// questions — and the same gate create_inquiry applies, and asserts that every turn has a next
// question until the request is postable.
//
// GENERATORS is production's category_specs row for `generators`, read 14 Sep 2026.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { detectCat, detectTrades } from './classify.ts';
import { interviewStep, type SpecField, type InterviewState } from './interview.ts';
import { requirementsStep, toStored, validateStored, type Answers } from '../_shared/intake_requirements.ts';

const GENERATORS: SpecField[] = [
  { key: 'application', type: 'select', options: ['Standby / backup power', 'Prime / continuous', 'Temporary site power'], question: 'Application?', required: true, question_plain_en: 'What is the generator for — backup when the power cuts, running all the time, or temporary site power?', question_plain_ar: 'لأي غرض المولد — احتياطي عند انقطاع الكهرباء، أم تشغيل مستمر، أم كهرباء مؤقتة للموقع؟' },
  { key: 'rating', type: 'select', options: ['Up to 100 kVA', '100-500 kVA', '500 kVA+', 'Not sure - advise'], question: 'Required power rating (kVA)?', required: true, question_plain_en: 'Do you know how much power you need? If not, tell me what it must run and the supplier will size it.', question_plain_ar: 'هل تعرف القدرة المطلوبة؟ إن لم تكن تعرف، أخبرنا بما يجب تشغيله وسيحدد المورد الحجم.' },
  { key: 'enclosure', type: 'select', options: ['Soundproof canopy', 'Open type', 'Containerized'], question: 'Enclosure type?', required: true, question_plain_en: 'Should it be in a quiet soundproof box, open, or in a container?', question_plain_ar: 'هل تريده داخل غطاء عازل للصوت، أم مكشوفاً، أم داخل حاوية؟' },
  { key: 'ats', type: 'select', options: ['Yes', 'No', 'Not sure'], question: 'Automatic mains failure (AMF/ATS) panel?', required: true, question_plain_en: 'Should it switch on by itself when the power goes off?', question_plain_ar: 'هل تريده أن يعمل تلقائياً عند انقطاع الكهرباء؟' },
  { key: 'fuel', type: 'select', options: ['8 hours', '24 hours', 'Extended', 'Not sure'], question: 'Fuel autonomy / runtime?', required: false },
  { key: 'scope', type: 'select', options: ['Supply only', 'Supply and install', 'Full incl. commissioning + AMC'], question: 'Scope?', required: false },
  { key: 'location', type: 'text', options: [], question: 'Property type and emirate/area?', required: false },
];
const NOW = new Date('2026-09-14T08:43:59Z');

/** index.ts's deterministic order: the category interview first, then the sales engineer's questions. */
function replay(turns: string[], lang: 'en' | 'ar') {
  let st: InterviewState = { details: {}, asked_key: null };
  let req: Answers = {};
  let reqAsked: string | null = null;
  const said: string[] = [];
  const asked: string[] = [];
  let postable = false;
  for (const t of turns) {
    said.push(t);
    const step = interviewStep(GENERATORS, st, t, said.join(' \n '), lang);
    st = { details: step.details, asked_key: step.next ? step.next.key : null };
    if (!step.complete) { asked.push(step.next!.text); continue; }
    const rs = requirementsStep('generators', req, reqAsked, t, step.details, lang, NOW);
    req = rs.answers;
    reqAsked = rs.next ? rs.next.key : null;
    if (rs.next) { assert(rs.next.options.length > 0, 'every sales-engineer question is answerable by a tap'); asked.push(rs.next.text); }
    else postable = true;
  }
  return { asked, stored: toStored('generators', req, NOW), postable, details: st.details };
}

Deno.test('"I need Generators work (generators)" is the generators trade — English and Arabic', () => {
  assertEquals(detectCat('I need Generators work (generators)'), 'generators');
  assertEquals(detectTrades('I need Generators work (generators)'), ['generators']);
  assertEquals(detectCat('أحتاج مولد كهرباء احتياطي لفيلا في دبي'), 'generators');
  assertEquals(detectCat('diesel genset for a warehouse'), 'generators');
});

Deno.test('replay: the founder\'s request reaches a postable request, with a next question on every turn before that', () => {
  const r = replay([
    'I need Generators work (generators)',
    'Standby / backup power', 'Not sure - advise', 'Soundproof canopy', 'Yes',
    'No preference', 'Stamford', 'Yes, install it', 'Yes, at least 2 years', 'Within 1 month',
  ], 'en');
  assertEquals(r.asked, [
    'What is the generator for — backup when the power cuts, running all the time, or temporary site power?',
    'Do you know how much power you need? If not, tell me what it must run and the supplier will size it.',
    'Should it be in a quiet soundproof box, open, or in a container?',
    'Should it switch on by itself when the power goes off?',
    'Any preference for the engine brand? Tap one, or type what you have in mind.',
    'Any preference for the alternator brand? Tap one, or type what you have in mind.',
    'Do you need the supplier to install it, or only deliver it?',
    'Do you need a warranty, and for how long at least?',
    'By when do you need it done or delivered? Tap one, or type a date.',
  ]);
  assert(r.postable, 'after the last answer nothing is left to ask');
  assertEquals(validateStored('generators', r.stored), { ok: true, missing: [] }, 'create_inquiry\'s gate accepts it');
  assertEquals(r.stored.recorded_by, 'sales_engineer');
  assertEquals(r.stored.installation, { required: 'yes' });
  assertEquals(r.stored.warranty, { required: 'yes', min_months: 24 });
  assertEquals(r.stored.materials.map((m) => [m.component, m.choice]), [['engine', 'no_preference'], ['alternator', 'stamford']]);
  assertEquals(r.stored.required_by, { flexible: false, date: '2026-10-14', text: 'Within 1 month' });
  assertEquals(r.details.application, 'Standby / backup power');
});

Deno.test('replay in Arabic: every question comes back in Arabic and the request becomes postable', () => {
  const r = replay([
    'أحتاج مولد كهرباء',
    'احتياطي عند انقطاع الكهرباء', 'لا أعرف', 'غطاء عازل للصوت', 'نعم',
    'لا تفضيل لدي', 'لا تفضيل لدي', 'لا، توريد فقط', 'لست متأكداً', 'مرن، لا يوجد موعد محدد',
  ], 'ar');
  for (const t of r.asked) assert(/[؀-ۿ]/.test(t), 'asked in Arabic: ' + t);
  assert(r.postable);
  assertEquals(validateStored('generators', r.stored).ok, true);
  assertEquals(r.stored.installation, { required: 'no' });
  assertEquals(r.stored.warranty, { required: 'not_sure', min_months: null });
  assertEquals(r.stored.required_by.flexible, true);
});
