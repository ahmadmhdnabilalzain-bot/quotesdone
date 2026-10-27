// turn_clock — one clock per intake turn, inside the portal's 30 s wait, and a retried turn is one message, not two.
// deno test supabase/functions/inquiry_intake/turn_clock.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { MIN_STEP_MS, RESERVE_MS, TURN_BUDGET_MS, TurnClock, keptFor, placeUserTurn, storedReply, turnIdOf, within } from './turn_clock.ts';

// The portal's wait (src/components/me/CustomerPortal.tsx CALL_TIMEOUT_MS). The static check
// scripts/checks/the_intake_turn_answers_inside_the_portals_wait.test.mjs reads the real constant.
const PORTAL_WAIT_MS = 30_000;

Deno.test('the turn budget sits inside the portal wait with room for the edge and the network', () => {
  assert(TURN_BUDGET_MS + 5_000 <= PORTAL_WAIT_MS, `${TURN_BUDGET_MS} ms leaves under 5 s of the portal's ${PORTAL_WAIT_MS} ms`);
  assert(TURN_BUDGET_MS < 25_000, 'the target is a p95 turn under 25 s');
  assert(MIN_STEP_MS + RESERVE_MS < TURN_BUDGET_MS);
});

Deno.test('TurnClock: laps from the request, a deadline that keeps the reserve, and no step started too late', () => {
  let now = 50_000;
  const c = new TurnClock(now, TURN_BUDGET_MS, () => now);
  now += 1_200; assertEquals(c.lap('read'), 1_200);
  assertEquals(c.deadline(), 50_000 + TURN_BUDGET_MS - RESERVE_MS);
  now += 9_000; c.lap('model');
  assertEquals(c.laps, { read: 1_200, model: 10_200 });
  assert(c.canStart(), 'a step with 11 s left was refused');
  now = c.deadline() - MIN_STEP_MS + 1;
  assert(!c.canStart(), 'a step was allowed to start with less than MIN_STEP_MS left');
  assert(c.left() < MIN_STEP_MS);
});

// MOCKED TIMING: the worst production turn (27 Oct 11:33 UTC: 7.0 s interview call, 20.0 s plan, 41.0 s + 47.4 s answer
// passes) replayed against the clock. The interview call gets what is left; the exact-spec reading can only start
// with MIN_STEP_MS left and is cut at the deadline; the plan does not exist any more (reasoned_decisions.ts).
Deno.test('the measured worst turn, replayed on the clock, ends inside the budget', () => {
  let now = 0;
  const c = new TurnClock(now, TURN_BUDGET_MS, () => now);
  now += 2_000; c.lap('read');                                  // the reads (parallel now)
  now += Math.min(7_000, c.left()); c.lap('model');             // the interview call, cut at the clock if slower
  if (c.canStart()) now += Math.min(41_000 + 47_400, c.left()); // the reading: one pass now, cut at the deadline
  c.lap('exact_spec');
  now += RESERVE_MS; c.lap('done');                              // the save and the logs
  assert(c.laps.done <= TURN_BUDGET_MS, `the turn took ${c.laps.done} ms of a ${TURN_BUDGET_MS} ms budget`);
});

Deno.test('within: a read that outlasts the clock is not waited for, and one that finishes is', async () => {
  const slow = new Promise((r) => setTimeout(r, 300));
  const t0 = Date.now();
  assertEquals(await within(slow, 30), false);
  assert(Date.now() - t0 < 200, 'the turn waited for a read past the clock');
  assertEquals(await within(Promise.resolve(1), 1_000), true);
  assertEquals(await within(Promise.reject(new Error('x')), 1_000), true, 'a failed read is settled, not waited for');
  await slow;
});

Deno.test('keptFor: the vocabulary is read once per worker for its TTL; an empty or failed read is not kept', async () => {
  let now = 0, loads = 0;
  const vocab = keptFor(300_000, () => { loads++; return Promise.resolve(['ducting']); }, () => now);
  await vocab(); await vocab(); now += 299_999; await vocab();
  assertEquals(loads, 1, 'the vocabulary was read again inside its TTL');
  now += 2; await vocab();
  assertEquals(loads, 2, 'a stale vocabulary was kept past its TTL');
  let n = 0;
  const flaky = keptFor(300_000, () => (++n === 1 ? Promise.reject(new Error('timeout')) : n === 2 ? Promise.resolve([]) : Promise.resolve(['x'])), () => 0);
  assertEquals(await flaky(), []);
  assertEquals(await flaky(), [], 'a failed read was kept');
  assertEquals(await flaky(), ['x'], 'an empty read was kept');
});

Deno.test('turnIdOf: a plain id or nothing', () => {
  assertEquals(turnIdOf('t-1730000000-ab12'), 't-1730000000-ab12');
  assertEquals(turnIdOf('  abcdef  '), 'abcdef');
  assertEquals(turnIdOf('abc'), null);
  assertEquals(turnIdOf("x'; drop table"), null);
  assertEquals(turnIdOf(42), null);
});

Deno.test('placeUserTurn: a message is added once; a retry of a turn that landed adds nothing', () => {
  const turns: any[] = [];
  assertEquals(placeUserTurn(turns, 'Aluminium windows, 40 units', 'turn-aaaa'), 'added');
  assertEquals(turns, [{ role: 'user', text: 'Aluminium windows, 40 units', turn_id: 'turn-aaaa' }]);
  // The first attempt has not been answered (nothing saved after it): the same id is not a landed turn.
  assertEquals(placeUserTurn([{ role: 'user', text: 'x', turn_id: 'turn-bbbb' }], 'x', 'turn-bbbb'), 'none');
  turns.push({ role: 'assistant', text: 'How big is each window?' });
  assertEquals(placeUserTurn(turns, 'Aluminium windows, 40 units', 'turn-aaaa'), 'landed');
  assertEquals(turns.length, 2, 'the retried message was added a second time');
  // A new message after it is added as usual; an old id is not the latest message and changes nothing.
  assertEquals(placeUserTurn(turns, '1200 x 1500 mm', 'turn-cccc'), 'added');
  assertEquals(placeUserTurn(turns, 'Aluminium windows, 40 units', 'turn-aaaa'), 'none');
  assertEquals(turns.filter((t) => t.role === 'user').length, 2);
  // No id (an older portal): every message is added, as before.
  assertEquals(placeUserTurn(turns, 'white', null), 'added');
  assertEquals(placeUserTurn(turns, '', 'turn-dddd'), 'none');
});

Deno.test('storedReply: a landed turn is answered from the row, with the question it asked and its options', () => {
  const row = { id: 'i1', status: 'needs_info', category: 'aluminium', readiness: 60, missing: ['How big is each window?'], brief: { details: {} },
    turns: [
      { role: 'user', text: 'Aluminium windows', turn_id: 'turn-aaaa' },
      { role: 'assistant', text: 'Thanks, noted. Supply only, or supply and install?', slots: { status: 'needs_info', missing_keys: ['scope'],
        reply: { next_question: { key: 'scope', text: 'Supply only, or supply and install?', options: ['Supply and install', 'Supply only'] }, remaining_questions: ['Supply only, or supply and install?'], readiness: { filled: 2, required: 4 } } } },
    ] };
  const r = storedReply(row);
  assertEquals(r.replayed, true);
  assertEquals(r.assistant_message, 'Thanks, noted. Supply only, or supply and install?');
  assertEquals((r.next_question as any).options, ['Supply and install', 'Supply only']);
  assertEquals(r.missing_keys, ['scope']);
  assertEquals(r.readiness, { filled: 2, required: 4 });
  assertEquals(r.brief, null, 'a brief was returned for a request that is not ready');
  const ready = storedReply({ ...row, status: 'ready', brief: { summary: 'x' } });
  assertEquals(ready.brief, { summary: 'x' });
  assertEquals(ready.remaining_questions, []);
});
