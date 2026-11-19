// Ruling 1405 on the reasoned path: "the model answers from its own knowledge; the collected knowledge is a look-up for hard
// questions" (customer_support, 19 Nov 2026). Until today synthesisPrompt told the model to answer from the settled facts and
// the sources and to reason for itself only "where sources are thin". These pin the new framing AND every rule it must keep.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { synthesisPrompt, VERIFY_PROMPT } from './prompts.ts';
import { BRIEF_SOURCE_ID } from './tunables.ts';

const P = synthesisPrompt('customer_support', 'customer', 'en');

Deno.test('a trade question is answered from the model\'s own expertise; the knowledge is a look-up', () => {
  assert(P.includes('Answer a trade or technical question'), 'the own-expertise instruction is missing');
  assert(P.includes('from your own expertise, as a senior UAE practitioner would'));
  assert(P.includes('are your look-up'));
  assert(P.includes('on a hard or uncertain question, to confirm or correct what you know'));
  // the old framing is gone: the knowledge base no longer bounds the answer
  assert(!P.includes('Answer from the SETTLED COMPANY FACTS above and the sources;'), 'the knowledge base frames the answer again');
  assert(!/Where sources are thin/i.test(P), 'own reasoning is again only the fallback for thin sources');
});

Deno.test('a company fact still comes only from the settled facts or a source, and beats the model', () => {
  assert(P.includes("QuotesDone's own prices, fees, process, policies and promises, and this person's own records"));
  assert(P.includes('never from you: never invent one'));
  assert(P.includes('the settled fact or the source is right'));
  assert(P.includes('Where a source contradicts a settled fact, the settled fact is right.'));
  assert(P.includes(`a settled fact as "${BRIEF_SOURCE_ID}"`));
  assert(P.includes('IS established: state it plainly'));
});

Deno.test('every safety rule the prompt carried is still there', () => {
  for (const rule of ['never invent an unpublished price', 'UAE and GCC law only', 'Never decide what a message means by spotting a word',
    'never mention another customer\'s or supplier\'s job', 'only a fact explicitly labelled as THEIR OWN belongs to them']) assert(P.includes(rule), rule);
  // the internal audience is not told the sources are someone else's general material (unchanged)
  assert(!synthesisPrompt('accountant', 'internal', 'en').includes('THEIR OWN'));
  // a decision still decides; a decline is still offered only when asked for
  const d = synthesisPrompt('customer_support', 'customer', 'en', { name: 'x', options: [{ id: 'a', meaning: 'A' }] });
  assert(d.includes('This is a DECISION'));
  assert(!P.includes('"declined"'));
  assert(synthesisPrompt('customer_support', 'customer', 'en', undefined, undefined, true).includes('"declined"'));
  // the independent reviewer is unchanged: an unsupported legal limit, sum or safety statement is still a problem
  assert(VERIFY_PROMPT.includes('a stated legal or regulatory limit, a sum of money, or a safety statement'));
  assertEquals(synthesisPrompt('customer_support', 'customer', 'ar').includes('formal Gulf Arabic'), true);
});
