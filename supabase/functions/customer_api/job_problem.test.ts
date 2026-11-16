// "A problem with this job" (customer_api job_problem, 16 Nov 2026, AFTER_REVEAL). Nothing real: ZZ DEMO ids, stubbed reads.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/customer_api/job_problem.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { jobProblem, type JobProblemIO } from './job_problem.ts';

const ME = '0c0c0c0c-0000-4000-8000-000000000001';
const Q = '0c0c0c0c-0000-4000-8000-0000000000a1';
const TX = '0c0c0c0c-0000-4000-8000-0000000000b1';
function io(sale: Awaited<ReturnType<JobProblemIO['saleOfQuote']>>, answer: Record<string, unknown> | null = { ok: true, rfq_no: '1043', locale: 'en', message_en: 'Thank you. It is with customer support.', message_ar: 'شكرًا' }) {
  const calls: unknown[] = [];
  const x: JobProblemIO = {
    saleOfQuote: () => Promise.resolve(sale),
    door: (a) => { calls.push(a); return Promise.resolve({ data: answer, error: null }); },
  };
  return { x, calls };
}

Deno.test('his own revealed job and his words go to the one door, channel portal, with the sale named', async () => {
  const { x, calls } = io({ id: TX, customer_id: ME, revealed_at: '2026-11-10T08:00:00Z' });
  const r = await jobProblem(x, ME, { quote_id: Q, message: '  ZZ DEMO he quoted 18,000 and now asks 24,000  ' });
  assertEquals(r.status, 200);
  assertEquals(calls, [{ p_customer: ME, p_message: 'ZZ DEMO he quoted 18,000 and now asks 24,000', p_channel: 'portal', p_transaction: TX }]);
  assertEquals(r.body.message, 'Thank you. It is with customer support.');
});
Deno.test('another customer\'s job, an unrevealed sale, a bad id or no words never reach the door', async () => {
  for (const [sale, body, code] of [
    [{ id: TX, customer_id: 'someone-else', revealed_at: 'x' }, { quote_id: Q, message: 'ZZ DEMO he never came' }, 'not_your_revealed_job'],
    [null, { quote_id: Q, message: 'ZZ DEMO he never came' }, 'not_your_revealed_job'],
    [{ id: TX, customer_id: ME, revealed_at: null }, { quote_id: Q, message: 'ZZ DEMO he never came' }, 'not_revealed'],
    [{ id: TX, customer_id: ME, revealed_at: 'x' }, { quote_id: 'nope', message: 'ZZ DEMO he never came' }, 'quote_id_required'],
    [{ id: TX, customer_id: ME, revealed_at: 'x' }, { quote_id: Q, message: '  short ' }, 'message_too_short'],
  ] as const) {
    const { x, calls } = io(sale as never);
    const r = await jobProblem(x, ME, body as never);
    assertEquals(r.body.code, code);
    assertEquals(calls.length, 0, `${code} reached the door`);
  }
});
Deno.test('the answer is in his language, and a refusal keeps its words', async () => {
  const { x } = io({ id: TX, customer_id: ME, revealed_at: 'x' }, { ok: true, locale: 'ar', message_en: 'en', message_ar: 'وصلت رسالتكم' });
  assertEquals((await jobProblem(x, ME, { quote_id: Q, message: 'ZZ DEMO المورد رفع السعر' })).body.message, 'وصلت رسالتكم');
  const { x: y } = io({ id: TX, customer_id: ME, revealed_at: 'x' }, { ok: false, code: 'empty', locale: 'en', message_en: 'Tell us what happened' });
  const r = await jobProblem(y, ME, { quote_id: Q, message: 'ZZ DEMO ten chars+' });
  assertEquals([r.status, r.body.code, r.body.message], [400, 'empty', 'Tell us what happened']);
});
Deno.test('the portal action is wired to the door, and the refund button still names its channel', async () => {
  const src = await Deno.readTextFile(new URL('./actions/reveal.ts', import.meta.url));
  assert(/action === 'job_problem'/.test(src), 'customer_api has a job_problem action');
  assert(/rpc\('fn_customer_after_reveal_message'/.test(src), 'job_problem calls the one door');
  assert(/p_channel: 'portal'/.test(src.slice(src.indexOf("action === 'request_refund'"))), 'the refund button names its channel');
  // no keyword decides what the customer meant (founder ruling 1664): nothing here tests his words against a pattern
  const mine = await Deno.readTextFile(new URL('./job_problem.ts', import.meta.url));
  assert(!/message\s*\.\s*(match|test|includes|search)\(|\.test\(message\)/.test(mine), 'the message is never pattern-read in code');
});
