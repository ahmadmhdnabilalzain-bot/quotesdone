// chat_answers_the_question — the five chat questions sandbox run 2 (tag 1c94fa6a) judged 2/5, "Does not answer
// the question", re-asked against the DEPLOYED site_assistant; since 19 Oct 2026 the answers are graded by the
// Claude agent running the test, never by a paid model. Seat: customer_support. Exit 1 when an answer is missing.
//
// Prevented by: this file. Run 2's deflections had two causes, measured in ai_cost_log: an estate-wide provider
// outage (16:39-16:54Z, every fn failed) and, with the model up, an Arabic portal question whose plan hit the
// gateway's 900-token output cap (think.ts now answers from a one-step plan), plus two how-to facts the reply had
// no source for (where a customer sees quotes; how a supplier revises a quote). Demo accounts only
// (ZZ DEMO / @example.invalid), torn down at the end:  QD_FIXTURES=1 node scripts/eval/chat_answers_the_question.mjs
import { openRun, closeRun, makeDemoCustomer, makeDemoSupplier, call, read, write } from '../e2e/fixtures.mjs';
import { internalCred } from '../lib/demo_factory.mjs';

// What the judge grades against: the published facts (company block section 1-3, the portal labels), stated
// once here so a correct answer is not marked "unverified" for knowing more than the judge.
const TRUTH = 'QuotesDone is a UAE procurement marketplace. Customers post requests free; verified suppliers quote anonymously; '
  + 'the customer compares free and pays a reveal fee of 3% of the chosen quote value (ex-VAT, no cap, no card surcharge, no VAT charged: '
  + 'QuotesDone is not VAT-registered) to unlock that supplier; every request gets a top-3 comparison report. Customer portal (/me), buttons '
  + '"New request", "My requests" (Arabic "طلب جديد", "طلباتي"): "My requests" lists each request and the anonymous quotes received for it; '
  + 'the assistant there reads the signed-in customer\'s own account. Supplier portal (/portal, English only): "Inquiries received" > open the job > '
  + '"Send your quotation to the sales engineer" (attach the file; in an open review "Attach a revised file") > "Submit to Job <n>", or '
  + '"Or type it into the quote form"; submitting again replaces the earlier quote for that option, and a quote may carry '
  + 'separate options; quotes are accepted until the customer selects a supplier (request Concluded). '
  + 'Published contact: +1 218 316 6814, management@quotesdone.com.';

export const QUESTIONS = [
  { who: 'visitor', lang: 'en', path: '/', msg: 'How much does it cost to reveal a supplier?' },
  { who: 'visitor', lang: 'ar', path: '/ar', msg: 'كم رسوم كشف بيانات المورد؟' },
  { who: 'customer', lang: 'en', path: '/me', msg: 'Where do I see my quotes?' },
  { who: 'customer', lang: 'ar', path: '/ar/me', msg: 'أين أجد عروض الأسعار؟' },
  { who: 'supplier', lang: 'en', path: '/portal', msg: 'How do I submit a revised quote?' },
];

if (import.meta.url === `file://${process.argv[1].replace(/\\/g, '/')}` || process.argv[1]?.endsWith('chat_answers_the_question.mjs')) {
  const run = await openRun({ label: 'chat-answers-the-question' });
  // The run tag lets these demo accounts reach a model inside this run's rehearsal window, as stage 2 does.
  // Models for this tag only, capped at USD 1, for at most 30 minutes, and switched off in the finally below.
  await write(`update public.rehearsal_window set models_allowed = true, cap_usd = 1, expires_at = now() + interval '30 minutes'
               where run_tag = 'qd_run:${run.tag}' and ended_at is null`, 'chat eval window: models for this tag only');
  process.env.QD_E2E_RUN_TAG = run.tag;
  const out = [];
  try {
    const jwt = {
      customer_en: (await makeDemoCustomer(run, { locale: 'en' })).jwt,
      customer_ar: (await makeDemoCustomer(run, { locale: 'ar' })).jwt,
      supplier_en: (await makeDemoSupplier(run, {})).jwt,
    };
    for (const q of QUESTIONS) {
      const since = (await read(`select coalesce(max(id),0)::bigint id from public.ai_cost_log`))[0].id;
      // SITE_ASSISTANT_URL proves a branch before merge: the function served locally (deno run) against production data.
      const body = { message: q.msg, lang: q.lang, path: q.path }, tok = jwt[`${q.who}_${q.lang}`] ?? null;
      const r = process.env.SITE_ASSISTANT_URL
        ? await fetch(process.env.SITE_ASSISTANT_URL, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(tok ? { Authorization: 'Bearer ' + tok } : {}), 'x-qd-e2e-run': run.tag,
            // a documentation address (RFC 5737) per run, so repeated local proofs do not share one visitor rate bucket
            'x-forwarded-for': `198.51.100.${1 + Math.floor(Math.random() * 254)}`, 'x-qd-e2e-secret': await internalCred() }, body: JSON.stringify(body) })
            .then(async (x) => ({ status: x.status, json: await x.json().catch(() => null) }))
        : await call('site_assistant', tok, body);
      const reply = String(r.json?.reply || '');
      const producers = (await read(`select distinct model_used from public.ai_cost_log where id > ${since} and fn='site_assistant' and model_used like '%/%'`)).map((x) => x.model_used);
      // FOUNDER RULE (19 Oct 2026, with ruling 1260): grading a test makes no paid call, and there is no paid judge.
      // Each answer is recorded ungraded (pass=null) with the facts it is graded against; the Claude agent running
      // the test grades it (score >= 4/5, answers what was asked, in the language asked, nothing invented).
      out.push({ ...q, facts: TRUTH, reply, routed: r.json?.routed ?? null, producers, judge: 'the Claude agent running this test', score: null, issues: null, pass: null });
      console.log(`UNGRADED ${q.who}/${q.lang} (producer ${producers.join(',') || 'none'}): ${reply.slice(0, 140).replace(/\n/g, ' ')}`);
    }
  } finally {
    await write(`update public.rehearsal_window set models_allowed = false where run_tag = 'qd_run:${run.tag}'`, 'chat eval window: models off').catch(() => {});
    await closeRun(run).catch((e) => console.error('teardown: ' + e.message)); }
  if (process.env.OUT) (await import('node:fs')).writeFileSync(process.env.OUT, JSON.stringify(out, null, 1));
  // Ungraded (pass null) is not a failure and not a pass: exit 0 only means every answer was collected and nothing graded failed.
  process.exit(out.length === QUESTIONS.length && out.every((x) => x.pass !== false && x.reply) ? 0 : 1);
}
