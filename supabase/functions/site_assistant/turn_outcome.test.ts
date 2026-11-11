// site_assistant/turn_outcome.ts: the widget turn has a clock, and a turn with no reply is HTTP 200, never a raw 5xx
// (it_engineer, 11 Nov 2026, load test, ruling 1622; the module header carries the measurement).
//   DENO_NO_PACKAGE_JSON=1 deno test --no-lock --allow-read=. supabase/functions/site_assistant/turn_outcome.test.ts
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { answerFromBrief } from '../_shared/brief_answer.ts';
import { SITE_TURN_MS, CLOCK, unansweredTurn } from './turn_outcome.ts';
import { busyReply } from './visitor_scope.ts';
import { siteReplyCheck, siteReplyLanguage } from './reply_check.ts';

Deno.test('the clock: the first call outlasts a slow real answer, the reserve still starts one more call, and it ends before the driver gives up', () => {
  assert(CLOCK.SITE_TURN_MS - CLOCK.RESERVE_MS >= 25_000, 'the streamed answer gets at least 25 s');
  assert(CLOCK.RESERVE_MS >= CLOCK.MIN_CALL_MS, 'the reserve can start another call');
  assert(CLOCK.SITE_TURN_MS <= 40_000, 'a visitor never waits six model calls again (production p95 was 41-46 s)');
});

// THE PRODUCTION TURN, REPLAYED ON A VIRTUAL CLOCK. Every draft is English in an Arabic conversation (the stub of 11 Nov),
// each model call takes 7 s. Measured on production: six calls, 35-54 s, HTTP 503. With the clock: four calls, under it.
async function ladder(deadline: boolean) {
  const realNow = Date.now; let vnow = 1_800_000_000_000; let calls = 0;
  Date.now = () => vnow;
  const en = 'Thank you, this is a reply. It is written in English. Is there anything else?';
  const f = ((_u: string, init: RequestInit) => {
    calls++; vnow += 7_000;
    return Promise.resolve(String(init.body).includes('"stream":true')
      ? new Response('data: ' + JSON.stringify({ choices: [{ delta: { content: en } }] }) + '\n\ndata: [DONE]\n\n', { headers: { 'content-type': 'text/event-stream' } })
      : new Response(JSON.stringify({ content: en, model: 'zz/model' }), { headers: { 'content-type': 'application/json' } }));
  }) as typeof fetch;
  try {
    const t0 = vnow;
    const a = await answerFromBrief({ gateway: 'https://fn.invalid/ai_gateway', secret: 's', fn: 'site_assistant', agent: null, taskClass: 'visitor_chat',
      brief: '# brief', sys: 'Reply in Arabic.', input: [{ role: 'user', content: 'كيف تعمل المنصة؟' }], max: 700,
      check: siteReplyCheck('# brief', 'Reply in Arabic.', 'ar'), checkWhole: siteReplyLanguage('ar'), ...(deadline ? { deadline: t0 + SITE_TURN_MS } : {}) }, () => {}, f);
    return { a, calls, ms: vnow - t0 };
  } finally { Date.now = realNow; }
}
Deno.test({ name: 'a turn whose every draft is refused stops at the clock instead of walking six model calls', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  const before = await ladder(false);
  assertEquals(before.calls, 6, 'the unbounded ladder (production, 11 Nov: stream, rewrite, rewrite, retry, third, again)');
  const after = await ladder(true);
  assert(after.calls <= 4, 'calls ' + after.calls);
  assert(after.ms <= SITE_TURN_MS, 'the turn took ' + after.ms + ' ms of model time');
  assertEquals(after.a.reply, '');
  assertEquals(after.a.outage, false, 'the model answered: this is not an outage, so no code text');
} });

Deno.test('no reply: the busy line only when no model was reached, never otherwise, and the body is a 200 the widget reads', () => {
  const busy = busyReply('unknown', 'en');
  const down = unansweredTurn({ reply: '', outage: true, attempts: ['stream:failed deadline: no time left for another call'] }, busy);
  assertEquals(down.reply, busy);
  assertEquals(down.outage, true);
  const up = unansweredTurn({ reply: '', outage: false, attempts: ['stream:figures it is not in Arabic'] }, busy);
  assertEquals(up.reply, '', 'founder_instruction 1339: no code-written reply while the model is up');
  assertEquals(up.error, 'no_answer', 'the widget reads no_answer and shows its own line (src/lib/portalReply.ts noVerdict)');
  assertStringIncludes(busyReply('unknown', 'ar'), 'management@quotesdone.com');
  assert(/[؀-ۿ]/.test(busyReply('customer', 'ar')));
  assert(!/[؀-ۿ]/.test(busyReply('supplier', 'ar')), 'a supplier is answered in English');
  // the busy line itself passes the widget's own reply check (the published contact, no figure, no forbidden word)
  for (const lang of ['en', 'ar'] as const) {
    const line = busyReply('unknown', lang);
    const sys = 'contact: +1 218 316 6814 (WhatsApp, Mon-Fri 9am-6pm GST), management@quotesdone.com';
    for (const s of line.split('\n')) assertEquals(siteReplyCheck('# brief', sys, lang)(s), [], lang + ': ' + s);
    assertEquals(siteReplyLanguage(lang)(line), []);
  }
});

Deno.test('index.ts gives the turn its clock and has no 5xx exit', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const code = src.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');
  assert(/answerFromBrief\(\{[^]*?deadline: s0 \+ SITE_TURN_MS,/.test(code), 'the reply call has no deadline');
  assertEquals(code.match(/J\([^\n]*,\s*5\d\d\)/g) ?? [], [], 'a J(..., 5xx) exit came back');
  assert(/return J\(\{ \.\.\.unansweredTurn\(a, busyReply\(audience, replyLang\)\)/.test(code), 'the no-reply exit does not go through unansweredTurn');
  assert(/logRun\('error', \{ no_answer: 1/.test(code), 'the failure is no longer recorded as an error run');
});
