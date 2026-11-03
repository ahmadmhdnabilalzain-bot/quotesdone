// siteReplyCheck(): the widget/portal check answerFromBrief runs on every draft. Pure, no network.
import { assert, assertEquals } from 'jsr:@std/assert';
import { siteReplyCheck } from './reply_check.ts';

const BRIEF = 'REVEAL FEE: the customer pays 3.00% of the selected quotation value. No card fee is added.';
const SYS = 'If they ask for a person, give the published contact: +1 218 316 6814, management@quotesdone.com.';

Deno.test('a figure the brief never states is refused (before: only the reply rules ran, so it went out)', () => {
  const p = siteReplyCheck(BRIEF, SYS, 'en')('Our reveal fee is 7% of the quotation, paid once you choose a supplier.');
  assert(p.some((x) => x.includes('7%')), JSON.stringify(p));
});

Deno.test('a phone number or email that is in neither the brief nor the prompt is refused', () => {
  const p = siteReplyCheck(BRIEF, SYS, 'en')('You can reach the supplier directly on +971 50 123 4567 or ali@example.ae for the site visit.');
  assert(p.some((x) => x.includes('contact or licence details')), JSON.stringify(p));
});

Deno.test('a clean reply that repeats the brief and the published contact passes', () => {
  assertEquals(siteReplyCheck(BRIEF, SYS, 'en')('The reveal fee is 3.00% of the quotation you select. For a person, WhatsApp +1 218 316 6814 or write to management@quotesdone.com.'), []);
});

Deno.test('one sentence that defers passes: the check runs per streamed sentence, deferral is a whole-answer rule', () => {
  for (const s of ['A member of the team will contact you shortly.', "I'll check with the team and come back to you.",
    "I'm not sure which trade covers that, so tell me what the job is."]) assertEquals(siteReplyCheck(BRIEF, SYS, 'en')(s), [], s);
});

Deno.test('site_assistant hands this check to answerFromBrief', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(src.includes('check: siteReplyCheck(brief, sys, replyLang),'));
});
