// Stubbed model and stubbed database: a high-stakes decision proceeds on the second seat's agreement, or, under the
// model hold, with the review owed; after the lift it is reviewed in the call and blocked until the second seat agrees.
import { assertEquals } from 'jsr:@std/assert';
import { challengeBeforeDeciding } from './high_stakes_challenge.ts';

type Call = { fn: string; args: Record<string, unknown> };

// A database stub that plays fn_high_stakes_gate and the deliberation (blind, then compare).
function stubDb(o: { held?: boolean; gateError?: string } = {}) {
  const calls: Call[] = [];
  const turns: Record<string, Record<string, unknown>> = {};
  let proceededAt: string | null = null;
  const admin = {
    rpc: (fn: string, args: Record<string, unknown>) => {
      calls.push({ fn, args });
      if (fn === 'fn_high_stakes_gate') {
        if (o.gateError) return Promise.resolve({ data: null, error: { message: o.gateError } });
        const c = turns.compare?.p_output as Record<string, string> | undefined;
        const state = c ? (c.verdict === 'approve' ? 'agreed' : 'disagreed') : (o.held ? 'held' : 'pending');
        const cleared = state === 'agreed';
        const proceed = cleared || (!!o.held && state !== 'disagreed');
        if (proceed && !cleared) proceededAt ??= 'now';
        return Promise.resolve({ data: { deliberation_id: 7, state, cleared, proceed, owed: proceed && !cleared, model_held: !!o.held,
          verdict: c?.verdict ?? null, reason: c ? (cleared ? c.agreements : c.disagreements) : 'waiting',
          reviewer_model: turns.compare?.p_model ?? null }, error: null });
      }
      if (fn === 'fn_seat_deliberation_step') {
        if (o.held) return Promise.resolve({ data: { action: 'held', why: 'founder_hold' }, error: null });
        const phase = turns.blind ? (turns.compare ? null : 'compare') : 'blind';
        if (!phase) return Promise.resolve({ data: { action: 'none' }, error: null });
        return Promise.resolve({ data: { action: 'call_model', phase, task_class: 'seat_deliberation_' + phase, model: 'openai/gpt-5.6-sol',
          counterpart_model: 'z-ai/glm-5.3-flash', reviewer_seat: 'ceo', max_tokens: 600, payload: { evidence: {} }, system: 's' }, error: null });
      }
      if (fn === 'fn_seat_deliberation_record') { turns[String(args.p_phase)] = args; return Promise.resolve({ data: 1, error: null }); }
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { admin, calls, turns, owed: () => proceededAt };
}

// A stubbed model: answers every phase with the verdict given, from another family than the author's.
let modelCalls = 0;
const stubModel = (verdict: string, disagreements = 'none') => (_m: string[], _d: unknown) =>
  (_sys: string, _input: unknown) => {
    modelCalls++;
    return Promise.resolve({ used_llm: true, model: 'openai/gpt-5.6-sol',
      content: JSON.stringify({ verdict, steelman_against: 'the refund sets a precedent', agreements: 'amount matches the ledger', disagreements }) });
  };

const base = { kind: 'refund' as const, seat: 'ceo', subject: { table: 'refunds', id: 'zz-demo-1' },
  question: 'ZZ DEMO should this refund be approved?', evidence: { ledger: 'paid AED 150' }, proposal: { refund_aed: 150 },
  authorModel: 'deterministic' };

Deno.test('after the lift, the second seat agrees in the call: the decision proceeds, reviewed on another family', async () => {
  const db = stubDb();
  const g = await challengeBeforeDeciding(db.admin, { ...base, makeLlm: stubModel('approve') });
  assertEquals([g.proceed, g.state, g.reviewer_model, g.owed], [true, 'agreed', 'openai/gpt-5.6-sol', false]);
  assertEquals(Object.keys(db.turns).sort(), ['blind', 'compare']);   // blind first, then the comparison
});

Deno.test('after the lift, the second seat disagrees: the decision is blocked and the reason is on record', async () => {
  const db = stubDb();
  const g = await challengeBeforeDeciding(db.admin, { ...base, makeLlm: stubModel('reject', 'the goods were delivered and signed for') });
  assertEquals([g.proceed, g.state, g.reason], [false, 'disagreed', 'the goods were delivered and signed for']);
});

Deno.test('under the model hold: the decision proceeds, the review is owed, and no model is called', async () => {
  const db = stubDb({ held: true });
  modelCalls = 0;
  const g = await challengeBeforeDeciding(db.admin, { ...base, makeLlm: stubModel('approve') });
  assertEquals([g.proceed, g.owed, g.state, modelCalls, db.owed()], [true, true, 'held', 0, 'now']);
  assertEquals(db.calls.filter((c) => c.fn === 'fn_high_stakes_gate').length, 1);   // proceeded: not re-asked
});

Deno.test('a gate that cannot answer is not a clearance', async () => {
  const db = stubDb({ gateError: 'boom' });
  const g = await challengeBeforeDeciding(db.admin, { ...base, makeLlm: stubModel('approve') });
  assertEquals([g.proceed, g.state], [false, 'failed']);
  assertEquals(db.calls.map((x) => x.fn), ['fn_high_stakes_gate']);
});
