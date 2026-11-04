// A CAPPED VISITOR WHO ASKS FOR A PERSON GETS THE PUBLISHED CONTACT (customer_support, 3 Nov 2026).
// Measured on the live widget (scripts/eval/conversation_quality.mjs, villa_windows_sharjah x5, the independent judge's
// reading): the 10th message "I want to talk to a real person" came after the visitor's 8 messages, and 4 of 5 replies gave
// only "sign up, our sales engineer will carry on" with no WhatsApp line or email. Root cause: the cap rule told the model
// "give no number" and its facts held the sign-up link alone, so the published contact (site_assistant's own rule: "If they
// ask for a person, give the published contact") was withheld exactly when it was asked for.
import { assert, assertMatch } from 'jsr:@std/assert';
import { capReplyByModel, capRules } from './visitor_scope.ts';
import type { ThinkDeps } from '../_shared/think.ts';

Deno.test('the cap rule tells the model to give the published contact when a person is asked for', () => {
  for (const [aud, lang] of [['unknown', 'en'], ['customer', 'ar'], ['supplier', 'en']] as const) {
    const r = capRules(aud, lang);
    assertMatch(r, /ask(?:s|ed)? for a person/i, aud + ' ' + lang);
    assertMatch(r, /\+1 218 316 6814/);
    assertMatch(r, /management@quotesdone\.com/);
    assert(!/give no number/i.test(r), 'the old blanket "give no number" withheld the contact');
  }
});

Deno.test('the capped reply is given the published contact as a fact, beside the sign-up link', async () => {
  let facts = '';
  // deno-lint-ignore no-explicit-any
  const write = (async (_d: ThinkDeps, req: any) => { facts = String(req.facts); return { reply: 'ok', outage: false, attempts: [] }; }) as never;
  await capReplyByModel({} as ThinkDeps, { audience: 'unknown', lang: 'en', message: 'I want to talk to a real person.' }, write);
  assertMatch(facts, /THE SIGN-UP LINK: \/me/);
  assertMatch(facts, /\+1 218 316 6814/);
  assertMatch(facts, /management@quotesdone\.com/);
});
