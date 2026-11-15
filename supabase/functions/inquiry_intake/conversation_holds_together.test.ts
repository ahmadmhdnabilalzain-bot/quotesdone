// THE REQUEST CHAT HOLDS TOGETHER (10 Nov 2026, sales_engineer; founder ledger 1572: "nothing said in message 2 may be
// forgotten by message 30+", "Hard limit 100 messages per inquiry", dialects). No network: the model is a fake that
// records what it was given.
// Run: deno test --no-lock --node-modules-dir=none supabase/functions/inquiry_intake/conversation_holds_together.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { intakeVoice, lastAskedKey, reconcileSlots, settleModelTurn, unknownHeldDraft } from './slots.ts';
import { isUnknown, type SpecField } from './interview.ts';
import { buildBrief } from './interview.ts';

const PARTITION: SpecField[] = [
  { key: 'size', type: 'text', options: [], question: 'What size is the partition?', required: true },
  { key: 'material', type: 'text', options: [], question: 'Which finish do you want on it?', required: true },
  { key: 'location', type: 'text', options: [], question: 'Which emirate and area?', required: true },
] as never;
const briefOf = (d: Record<string, string>) => buildBrief('wallpaper', d, '', null, '');

// deno-lint-ignore no-explicit-any
const fakeDeps = (seen: any[]) => ({ gate: () => Promise.resolve(null), embed: () => Promise.resolve(null), rpc: () => Promise.resolve({ data: null, error: null }),
  // deno-lint-ignore no-explicit-any
  llm: (_p: string, system: string, input: string, o: any) => { seen.push({ system, input, history: o?.history ?? [] }); return Promise.resolve({ content: JSON.stringify({ answer: 'Thanks. Which emirate and area is it in?' }), model: 'm' }); } }) as never;

Deno.test('message 2 reaches the reply writer at message 40: the whole conversation, not the last twelve turns', async () => {
  const conversation: { role: string; text: string }[] = [{ role: 'user', text: 'I have an MDF partition to clad.' }, { role: 'user', text: 'It is 2.4 x 1.2 m, one face, budget about 3,000 AED, kids room so no strong smell.' }];
  for (let i = 0; i < 38; i++) conversation.push({ role: i % 2 ? 'user' : 'assistant', text: 'distractor turn ' + i });
  const seen: unknown[] = [];
  const v = await intakeVoice(fakeDeps(seen), { draft: 'Thanks, noted. Which emirate and area?', lang: 'en', message: 'ok', conversation, state: 'THE REQUEST AS OUR SYSTEMS HOLD IT: - size: "2.4 x 1.2 m" (message 2)', rule: 'THIS CONVERSATION IS NEAR ITS LIMIT.' });
  assertEquals(v.by, 'model');
  // deno-lint-ignore no-explicit-any
  const call = seen[0] as any;
  const all = JSON.stringify(call.history) + call.input + call.system;
  assert(all.includes('2.4 x 1.2 m, one face, budget about 3,000 AED, kids room'), 'message 2 was cut from the reply writer');
  assertEquals(call.history.length, 40, 'every turn rides as history');
  assert(call.input.includes('(message 2)') && call.system.includes('NEAR ITS LIMIT'), 'the state and the cap rule ride with the turn');
});

Deno.test("a spec the customer does not know is never asked again: exhausted at once, the others still asked", () => {
  const out = { status: 'needs_info', questions: ['Which finish do you want on it?'], brief: { details: { size: '2.4 x 1.2 m' } }, claims_ready: false, assistant_message: 'Which finish?' };
  const s = reconcileSlots(PARTITION, {}, out, 'en', {}, ['material']);
  assertEquals(s.exhausted, ['material']);
  assert(!s.missing.includes('Which finish do you want on it?'), 'the unknown spec is still asked');
  assert(s.missing.includes('Which emirate and area?'));
  const settled = settleModelTurn(PARTITION, {}, { ...out }, 'en', briefOf, {}, ['material']);
  assertEquals(settled.held, false);
  // known-bad control: without the unknown key the same spec stays askable
  assert(reconcileSlots(PARTITION, {}, out, 'en', {}, []).missing.includes('Which finish do you want on it?'));
  // only unknown specs left: SENT AS IT IS (re-check of 15 Nov 2026, item 3; until then held for good, a dead end): the spec goes to
  // the suppliers as "Customer does not know: supplier to advise" and the request can be sent; it is never ready with the spec blank
  const h = settleModelTurn(PARTITION, { size: '2.4 x 1.2 m', location: 'JVC, Dubai' }, { status: 'ready', brief: { details: {} } }, 'en', briefOf, {}, ['material']);
  assertEquals([h.held, h.complete, h.details.material, h.sentAsIs], [false, true, 'Customer does not know: supplier to advise', ['material']]);
  assert(/sales engineer will settle them/.test(unknownHeldDraft(PARTITION, ['material'], 'en')));
  assert(unknownHeldDraft(PARTITION, ['material'], 'ar').includes('مهندس المبيعات'));
});

Deno.test("I don't know, in dialect, is read as the answer to the spec the last reply asked", () => {
  const turns = [{ role: 'user', text: 'partition' }, { role: 'assistant', text: 'Which finish?', slots: { reply: { next_question: { key: 'material', text: 'Which finish?' } } } }];
  assertEquals(lastAskedKey(turns), 'material');
  assertEquals(lastAskedKey([{ role: 'assistant', text: 'hi' }]), null);
  for (const t of ['مش عارف', 'معرفش', 'ما بعرف', 'مدري', 'ما أدري', 'mesh 3aref', 'ma ba3ref']) assert(isUnknown(t), t);
  assert(!isUnknown('2.4 x 1.2 m'));
});
