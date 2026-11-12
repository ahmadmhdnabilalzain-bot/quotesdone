// A person is answered ONCE after a holding line (re-check of 12 Nov 2026, R1, BLOCKER). On production, on 3 of 3 turns where the
// line went, the reply was delivered AND the turn was filed "no reply after the holding line"; the re-ask then wrote a second
// answer 44-87 s later. Cause (the auditor's proof_reask_after_delivered_reply.mjs): the reply being ready settled the line
// through the registered wrapper, which also forgot the registration, so sendWa's answeredHoldingFor found nothing.
// This drives the REAL order of a slow turn through the handler's own functions: newTurn, makeSay (its adopt), armWaHolding,
// replies.ts sendWa (on a reserved fixture number: wa_send.ts captures it, nothing leaves) and holding.ts endTurnHolding, the
// turn's end in index.ts. Only the notifications table the line is claimed in, and the re-ask filing, are stubbed.
// Fails on 0b612866e (the first test: answered false, a re-ask filed).
import { assert, assertEquals } from 'jsr:@std/assert@1';
(Deno.env as unknown as { get: (k: string) => string | undefined }).get = (k) => ({ SUPABASE_URL: 'https://db.invalid', SUPABASE_SERVICE_ROLE_KEY: 'stub-service-role' } as Record<string, string>)[k];
import type { HoldingDeps } from './holding.ts';
import type { WaTurn } from './turn.ts';
const { newTurn } = await import('./turn.ts');
const { makeSay } = await import('./say.ts');
const { armWaHolding, endTurnHolding } = await import('./holding.ts');
const { sendWa } = await import('./replies.ts');

// the database never answers in this test: every request to the stub host fails at once, as a dead database would
const realFetch = globalThis.fetch;
globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
  const u = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
  if (u.hostname === 'db.invalid') return Promise.resolve(new Response('{"message":"stub"}', { status: 503 }));
  return realFetch(input, init);
}) as typeof fetch;

/** notifications as the claim reads and writes it (holding.ts), in memory */
function lineDeps(): HoldingDeps {
  const rows: Record<string, unknown>[] = [];
  const admin = { from: () => { const q: Record<string, unknown> = { select: () => q, order: () => q, eq: () => q, gte: () => q,
    limit: () => Promise.resolve({ data: [], error: null }), update: () => q, then: (ok: (v: unknown) => unknown) => Promise.resolve({ data: null, error: null }).then(ok),
    insert: (r: Record<string, unknown>) => ({ select: () => ({ maybeSingle: () => { rows.push(r); return Promise.resolve({ data: { id: rows.length, status: r.status }, error: null }); } }) }) }; return q; } };
  return { admin, setting: (k) => Promise.resolve(k === 'wa_autoreply_enabled' ? 'true' : ''), send: () => Promise.resolve({ ok: true }),
    typing: () => Promise.resolve({ ok: true }), finding: () => Promise.resolve() };
}
const FROM = 'whatsapp:+971500000004';   // reserved fixture block: sendWa captures, Twilio is never called
function slowTurn(): { t: WaTurn; filed: string[] } {
  const t = newTurn();
  Object.assign(t, { From: FROM, Body: 'ZZ DEMO how many quotes will I see?', MessageSid: 'SM' + 'c'.repeat(32), receivedAt: new Date(Date.now() - 20_000).toISOString(), timings: {} });
  makeSay(t);
  const filed: string[] = [];
  t.heldTurn = (_a, _l, _s, why) => { filed.push(why); t.heldFiled = true; return Promise.resolve({ notice: '', sent: false, err: null, held_id: 1 }); };
  armWaHolding(t, 'customer', 'en', lineDeps());   // 20 s since the message: the line fires at once
  return { t, filed };
}
const tick = (ms = 40) => new Promise((r) => setTimeout(r, ms));

Deno.test('the real order of a slow turn (line fires, reply adopted, reply sent, turn ends): answered once, no re-ask', async () => {
  const { t, filed } = slowTurn();
  await tick();
  assert(t.holdingWent, 'the line went');
  t.adopt({ text: 'ZZ DEMO there is no fixed number; every quote that arrives is listed.', model: 'stub', attempts: [], ms: 1, escalate: false, outage: false } as never);
  const sent = await sendWa(FROM, 'ZZ DEMO there is no fixed number; every quote that arrives is listed.');
  assertEquals(sent.ok, false, 'a fixture number is captured, never handed to Twilio');
  assert(t.holding!.answered, 'the delivered reply did not count as the answer');
  assertEquals([await endTurnHolding(t), filed], [false, []], 'a re-ask was filed for a turn whose reply was delivered');
});

Deno.test('the real order of a turn that dies after the line: re-asked exactly once', async () => {
  const { t, filed } = slowTurn();
  await tick();
  assert(t.holdingWent);
  // the reply is never written or sent: the turn threw
  assertEquals([await endTurnHolding(t), filed], [true, ['no_reply_after_holding']]);
  assertEquals(await endTurnHolding(t), false, 'filed once, never twice');
});

Deno.test('a reply written but refused by the send is not an answer: re-asked once', async () => {
  const { t, filed } = slowTurn();
  await tick();
  t.adopt({ text: 'ZZ DEMO written', model: 'stub', attempts: [], ms: 1, escalate: false, outage: false } as never);
  // nothing reaches sendWa (the guard refused it): the line stays unanswered
  assertEquals([await endTurnHolding(t), filed], [true, ['no_reply_after_holding']]);
});
