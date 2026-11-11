// Ruling 1631: a message sent twice in a row is answered once. Replays assistant_logs 4875 (the same portal message 1 s apart).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { lastTurn, replayOf } from './turn_replay.ts';

const first = { id: 4874, message: 'Whatever Civil Defence accepts; we have no preference.', reply: 'Understood: the system must connect…', created_at: '2026-10-27T10:00:00Z' };
const t = (s: number) => Date.parse('2026-10-27T10:00:00Z') + s * 1000;

Deno.test('the same message 1 s later gets the stored answer, not a second model call', () => {
  assertEquals(replayOf(first, 'Whatever Civil Defence accepts;  we have no preference.', t(1))?.id, 4874);
});
Deno.test('a different message, an old one, or an unanswered one is answered as normal', () => {
  assertEquals(replayOf(first, 'And the server room?', t(1)), null);
  assertEquals(replayOf(first, first.message, t(61)), null, 'past the window it is asked again on purpose');
  assertEquals(replayOf({ ...first, reply: null }, first.message, t(1)), null, 'the first is still being answered or failed');
  assertEquals(replayOf(null, first.message, t(1)), null);
  assertEquals(replayOf(first, '   ', t(1)), null);
});
Deno.test('an unreadable conversation never blocks the turn', async () => {
  const bad = { from: () => ({ select: () => ({ eq: () => ({ order: () => ({ limit: () => ({ maybeSingle: () => Promise.resolve({ data: null, error: { message: 'x' } }) }) }) }) }) }) };
  assertEquals(await lastTurn(bad, 'a-c-1'), null);
  assertEquals(await lastTurn({ from: () => { throw new Error('reset'); } }, 'a-c-1'), null);
});
Deno.test('the portal turn checks for a double send before it calls the model', async () => {
  const src = await Deno.readTextFile(new URL('../sales_engineer/actions/portal.ts', import.meta.url));
  const replay = src.indexOf('replayOf(await lastTurn(admin, acct), message)'), model = src.indexOf('await answerFromBrief(');
  assert(replay > 0 && replay < model);
});
