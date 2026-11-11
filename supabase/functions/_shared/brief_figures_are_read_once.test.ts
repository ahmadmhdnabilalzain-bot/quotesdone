// THE BRIEF'S FIGURES ARE READ ONCE PER BRIEF, AND THE CHECK ACCEPTS EXACTLY WHAT IT ACCEPTED BEFORE (it_engineer,
// 11 Nov 2026, load test, ruling 1622). company_brief.ts memoises figureSource and briefNumbers by the brief's exact text;
// allowedNumbers reads the brief and a turn's prompt apart; ai_reply.ts allowedForms lower-cases and digit-strips a turn's
// allowed text once. Measured before: 25% + 8% of site_assistant's JS time re-read the same ~80-100 KB on every turn and
// sentence, on a path whose workers were killed at the 2 s CPU budget (HTTP 546 x 11 at 50 concurrent chats).
// These fail when the memo is removed (the scan counters move) or when the split read changes the accepted set.
//   DENO_NO_PACKAGE_JSON=1 deno test --no-lock --allow-read=. supabase/functions/_shared/brief_figures_are_read_once.test.ts
import { assert, assertEquals, assertNotStrictEquals, assertStrictEquals } from 'jsr:@std/assert@1';
import { FIGURE_SCANS, allowedNumbers, briefNumbers, companyBrief, figureSource } from './company_brief.ts';
import { allowedForms, replyProblems } from './ai_reply.ts';

// A brief built the way site_assistant builds it: the compiled core, a live company block and price guide with figures,
// and the published FAQ in both languages, so the figure source is the real shape (tens of KB, every kind of figure).
const rpc = (fn: string) => Promise.resolve({ error: null, data: fn === 'fn_company_context'
  ? { block: 'ZZ company block. Reveal fee 3% of the quote, minimum job AED 500. Supplier registration AED 1,000 a year after 25 free.' }
  : fn === 'fn_price_brief' ? '- kitchens: AED 18,000 to 45,000 per kitchen\n- flooring: AED 35 - 70 per sqm\n- tiling: 60 to 120 AED per sqm' : null });
// production's figure source was ~77 KB (302 published FAQ rows); 80 rows a language keeps the fixture the same shape
const FAQ = [
  { id: 1, language: 'en', question: 'What does it cost?', answer: 'Posting is free; the reveal fee is 3% of the final quoted price.' },
  { id: 2, language: 'en', question: 'Minimum?', answer: 'The minimum job value is AED 500, and the fee is 25 for nothing.' },
  { id: 3, language: 'ar', question: 'كم الرسوم؟', answer: 'رسوم الكشف 3٪ من السعر النهائي، والحد الأدنى خمسمائة درهم.' },
  ...Array.from({ length: 160 }, (_, i) => ({ id: 10 + i, language: i % 2 ? 'ar' : 'en',
    question: (i % 2 ? 'سؤال منشور رقم ' : 'Published question number ') + i,
    answer: i % 2 ? 'إجابة معتمدة تشرح كيف تعمل المنصة خطوة بخطوة، دون أي رقم جديد.' : 'An approved answer that explains how the platform works, step by step, with no new figure in it.' })),
];
const SYS_EN = "You are QuotesDone's customer support on the quotesdone.com website chat. Under about 90 words. If they ask for a person, give the published contact: +1 218 316 6814 (WhatsApp, Mon-Fri 9am-6pm GST), management@quotesdone.com, /contact/.";
const SYS_AR = SYS_EN + '\n- Reply in Arabic in the customer\'s own register. رسوم قدرها 7 لا تُذكر.';
const FACTS = 'THEIR OWN REQUESTS: 2 quotes, band AED 4,000 to 5,000; a fee of 12 is not ours.';

const brief = await companyBrief(rpc, FAQ, 'SHARED FACTS: minimum job value is AED 500.', 'en');

Deno.test('the split read accepts exactly the figures the joined read accepted (site check, aiReply, portal shapes)', () => {
  assert(brief.length > 2_000, 'the brief is long enough to be memoised');
  for (const rest of [[SYS_EN], [SYS_AR], [FACTS, SYS_EN], [FACTS, '\n\n' + SYS_AR], ['']]) {
    const joined = briefNumbers(figureSource(brief) + '\n' + rest.join('\n'));
    assertEquals([...allowedNumbers(brief, ...rest)].sort(), [...joined].sort(), 'rest ' + JSON.stringify(rest).slice(0, 60));
  }
  // the figures the live sources state are there, and the authored knowledge licenses none (figureSource drops it)
  const known = allowedNumbers(brief, SYS_EN);
  for (const k of ['pct:3', 'aed:500', 'aed:18000', 'aed:45000']) assert(known.has(k), k);
});

Deno.test('the brief is scanned once however many turns and sentences check against it', () => {
  figureSource(brief); briefNumbers(figureSource(brief));   // warm
  const s0 = FIGURE_SCANS.source, n0 = FIGURE_SCANS.numbers;
  for (let i = 0; i < 25; i++) {
    allowedNumbers(brief, SYS_EN + ' turn ' + i, FACTS);    // the site check, the portal and aiReply: a new prompt every turn
    briefNumbers(figureSource(brief));                      // answerFromBrief's own known set
  }
  assertEquals(FIGURE_SCANS.source - s0, 0, 'the figure source was rebuilt on a turn');
  assertEquals(FIGURE_SCANS.numbers - n0, 0, "the brief's figures were read again on a turn");
  // a different brief is its own entry, never the first one's answer
  const other = brief + '\n\nAN EXTRA LINE: a fee of AED 777.';
  assert(allowedNumbers(other).has('aed:777'));
  assert(!allowedNumbers(brief).has('aed:777'));
  assertEquals(FIGURE_SCANS.source - s0, 1);
});

Deno.test('a caller that adds to its set never changes the next caller\'s', () => {
  const a = briefNumbers(figureSource(brief));
  a.add('aed:999999');
  assert(!briefNumbers(figureSource(brief)).has('aed:999999'));
  assertNotStrictEquals(briefNumbers(figureSource(brief)), briefNumbers(figureSource(brief)));
});

Deno.test('the allowed text is lower-cased and digit-stripped once per turn, and replyProblems answers the same', () => {
  const allowed = figureSource(brief) + '\n' + SYS_EN;
  const f1 = allowedForms(allowed);
  assertStrictEquals(allowedForms(allowed), f1, 'the same turn\'s allowed text was read again for a second sentence');
  assertEquals(f1.lower, allowed.toLowerCase());
  assertEquals(f1.digits, allowed.replace(/\D/g, ''));
  const known = allowedNumbers(brief, SYS_EN);
  // the published contact is allowed; a number the brief and prompt never carry is refused as a leak
  assertEquals(replyProblems('Call us on +1 218 316 6814 or email management@quotesdone.com.', known, { allowed }), []);
  assert(replyProblems('Call the supplier on +971 50 123 4567.', known, { allowed }).some((p) => /contact or licence/.test(p)));
  assert(replyProblems('The fee is AED 750.', known, { allowed }).some((p) => /AED 750/.test(p)));
});
