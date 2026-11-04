// A REPLY NEVER CITES ITS OWN KNOWLEDGE (customer_support, 3 Nov 2026; scripts/eval/conversation_quality.mjs).
// Measured on the live widget, villa_windows_sharjah run 3, turn 7: asked for a Sharjah office address, the reply opened
// "We're based in Dubai, and the brief doesn't give a public address" — the model naming the company brief it is given,
// which no customer has seen. The guard caught "system prompt" and our headings but not a reference to the brief.
// The customer's own job brief ("we turn it into a priceable brief", "quoted to the same brief") must still pass.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { replyViolations } from './support_reply_guard.ts';

Deno.test('a reply that cites the company brief or its sources is refused for a rewrite', () => {
  for (const t of ["We're based in Dubai, and the brief doesn't give a public address.", 'The company brief does not mention a Sharjah office.',
    'According to my brief, there is no showroom.', "My sources don't state an address.", 'The sources do not state it.'])
    assert(replyViolations(t).includes('prompt'), t);
});
Deno.test('the customer\'s own job brief is not our brief', () => {
  for (const t of ['We turn your description into a priceable brief and send it to verified suppliers.',
    'Every quote is normalised to the same brief, so you compare like for like.', 'In brief: posting is free.',
    'The brief does not mention the frame colour yet, so which do you prefer?', 'Your brief lists 14 windows.'])
    assertEquals(replyViolations(t), [], t);
});
