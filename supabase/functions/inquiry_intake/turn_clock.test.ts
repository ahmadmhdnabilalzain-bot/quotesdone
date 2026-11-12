// turn_clock — one clock per intake turn, inside the portal's 30 s wait, and a retried turn is one message, not two.
// deno test supabase/functions/inquiry_intake/turn_clock.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { MIN_STEP_MS, MODEL_WAIT_MS, REPLY_END_MS, REPLY_MIN_MS, RESERVE_MS, TURN_BUDGET_MS, TurnClock, keptFor, placeUserTurn, storedReply, turnIdOf, within } from './turn_clock.ts';

// The portal's wait (src/components/me/CustomerPortal.tsx CALL_TIMEOUT_MS). The static check
// scripts/checks/the_intake_turn_answers_inside_the_portals_wait.test.mjs reads the real constant.
const PORTAL_WAIT_MS = 30_000;

Deno.test('the turn budget sits inside the portal wait with room for the edge and the network', () => {
  assert(TURN_BUDGET_MS + 5_000 <= PORTAL_WAIT_MS, `${TURN_BUDGET_MS} ms leaves under 5 s of the portal's ${PORTAL_WAIT_MS} ms`);
  assert(TURN_BUDGET_MS < 25_000, 'the target is a p95 turn under 25 s');
  assert(MIN_STEP_MS + RESERVE_MS < TURN_BUDGET_MS);
});

// The founder's ruling of 27 Oct 2026: a reply is written by the model unless OpenRouter fails, never by code for time.
Deno.test('a reply-writing call is never cut short by the turn budget', () => {
  let now = 0;
  const c = new TurnClock(now, TURN_BUDGET_MS, () => now);
  assertEquals(c.modelDeadline(), MODEL_WAIT_MS);
  assert(MODEL_WAIT_MS > TURN_BUDGET_MS && MODEL_WAIT_MS <= PORTAL_WAIT_MS - 2_000);
  now = 10_000;                                   // after a typical interview call (p50 8.4 s; the full 15 s fits up to 10 s since REPLY_END_MS is 25 s)
  assertEquals(c.replyDeadline(), now + REPLY_MIN_MS, 'the held reply was given less than REPLY_MIN_MS');
  now = 20_000;                                   // the turn budget is almost spent
  assert(!c.canStart(), 'a step that writes no reply may be skipped here');
  // corrected 12 Nov 2026 (ledger 1642, review finding 4): the reply's minimum no longer reaches past the turn's one end;
  // before, 20 s + 15 s = 35 s, past the portal's 30 s
  assertEquals(c.replyDeadline(), REPLY_END_MS, 'a reply step ran past the turn\'s end');
  now = 1_000;
  assertEquals(c.replyDeadline(), c.deadline(), 'early in the turn the reply keeps the turn deadline');
});

// EVERY STEP OF A TURN ENDS BY ONE DEADLINE (12 Nov 2026, ledger 1642; review of the effort fix, finding 4). Measured 10-12 Nov:
// the interview call then the held reply made turns of 26-29 s, and three reply steps in series could each take REPLY_MIN_MS.
Deno.test('every step of a turn ends by one deadline: steps in series cannot pass the portal\'s wait', () => {
  let now = 0;
  const c = new TurnClock(now, TURN_BUDGET_MS, () => now);
  // the gateway answers a cut call about 2 s after its timeout (15 s steps ended at 16.7-17.1 s, 9-12 Nov): a step cut at the
  // turn's end returns by REPLY_END_MS + 2 s, and the save and the network still need room (second review, 12 Nov 2026)
  const GATEWAY_LATE_MS = 2_100;
  assert(REPLY_END_MS + GATEWAY_LATE_MS + 2_500 <= PORTAL_WAIT_MS, 'a cut step returns too close to the portal\'s 30 s: ' + (REPLY_END_MS + GATEWAY_LATE_MS));
  assertEquals(MODEL_WAIT_MS, REPLY_END_MS, 'the interview call has its own end');
  // the worst case: a slow interview call (max 16.4 s measured), then the held reply, the voice and a guard rewrite in series
  now = 16_400; const held = c.replyDeadline(); now = held; const voice = c.replyDeadline(); now = voice; const rewrite = c.replyDeadline();
  for (const d of [held, voice, rewrite]) assert(d <= REPLY_END_MS, 'a reply step ends past the turn: ' + d);
  assertEquals(c.modelDeadline(), REPLY_END_MS, 'the interview call ends where the turn does');
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
