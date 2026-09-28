// Stubbed model and stubbed database: the high-stakes challenge proceeds ONLY on the second seat's agreement.
import { assertEquals } from 'jsr:@std/assert';
import { challengeBeforeDeciding } from './high_stakes_challenge.ts';

type Call = { fn: string; args: Record<string, unknown> };

// A database stub that plays the deliberation: blind then compare, and a clearance read from what was recorded.
function stubDb(o: { hold?: boolean; openError?: string } = {}) {
  const calls: Call[] = [];
  const turns: Record<string, Record<string, unknown>> = {};
  const admin = {
    rpc: (fn: string, args: Record<string, unknown>) => {
      calls.push({ fn, args });
      if (fn === 'fn_high_stakes_challenge') return Promise.resolve(o.openError ? { data: null, error: { message: o.openError } } : { data: 7, error: null });
      if (fn === 'fn_seat_deliberation_step') {
        if (o.hold) return Promise.resolve({ data: { action: 'held', why: 'founder_hold' }, error: null });
        const phase = turns.blind ? (turns.compare ? null : 'compare') : 'blind';
        if (!phase) return Promise.resolve({ data: { action: 'none' }, error: null });
        return Promise.resolve({ data: { action: 'call_model', phase, task_class: 'seat_deliberation_' + phase, model: 'openai/gpt-5.6-sol',
          counterpart_model: 'z-ai/glm-5.3-flash', reviewer_seat: 'ceo', max_tokens: 600, payload: { evidence: {} }, system: 's' }, error: null });
      }
      if (fn === 'fn_seat_deliberation_record') { turns[String(args.p_phase)] = args; return Promise.resolve({ data: 1, error: null }); }
      if (fn === 'fn_high_stakes_clearance') {
        const c = turns.compare?.p_output as Record<string, string> | undefined;
        const state = c ? (c.verdict === 'approve' ? 'agreed' : 'disagreed') : (o.hold ? 'held' : 'pending');
        return Promise.resolve({ data: { cleared: state === 'agreed', state, verdict: c?.verdict ?? null,
          reason: c ? (state === 'agreed' ? c.agreements : c.disagreements) : 'founder_hold', reviewer_model: turns.compare?.p_model ?? null }, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { admin, calls, turns };
}

// A stubbed model: answers every phase with the verdict given, from another family than the author's.
const stubModel = (verdict: string, disagreements = 'none') => (_m: string[], _d: unknown) =>
  (_sys: string, _input: unknown, _max?: number, _s?: string, opts?: { counterpartModel?: string }) =>
    Promise.resolve({ used_llm: true, model: 'openai/gpt-5.6-sol', counterpart: opts?.counterpartModel,
      content: JSON.stringify({ verdict, steelman_against: 'the refund sets a precedent', agreements: 'amount matches the ledger', disagreements }) });

const base = { kind: 'refund' as const, seat: 'customer_support', subject: { table: 'refund_requests', id: 'zz-demo-1' },
  question: 'ZZ DEMO should this customer be refunded?', evidence: { ledger: 'paid AED 150' }, proposal: { refund_aed: 150 },
  authorModel: 'z-ai/glm-5.3-flash', authorTaskClass: 'routine_employee_reasoning' };

Deno.test('the second seat agrees: the decision is cleared, on a reviewer of another family', async () => {
  const db = stubDb();
  const c = await challengeBeforeDeciding(db.admin, { ...base, makeLlm: stubModel('approve') });
  assertEquals([c.cleared, c.state, c.reviewer_model], [true, 'agreed', 'openai/gpt-5.6-sol']);
  assertEquals(Object.keys(db.turns).sort(), ['blind', 'compare']);   // blind first, then the comparison
  assertEquals(db.calls[0].args.p_kind, 'refund');
});

Deno.test('the second seat disagrees: not cleared, and the reason is on record', async () => {
  const db = stubDb();
  const c = await challengeBeforeDeciding(db.admin, { ...base, makeLlm: stubModel('reject', 'the goods were delivered and signed for') });
  assertEquals([c.cleared, c.state, c.reason], [false, 'disagreed', 'the goods were delivered and signed for']);
});

Deno.test('under the model hold: no model is called and the decision waits', async () => {
  const db = stubDb({ hold: true });
  let called = 0;
  const c = await challengeBeforeDeciding(db.admin, { ...base, makeLlm: () => () => { called++; return Promise.resolve({}); } });
  assertEquals([c.cleared, c.state, called], [false, 'held', 0]);
});

Deno.test('a challenge that cannot open is not a clearance', async () => {
  const db = stubDb({ openError: 'not a high-stakes kind' });
  const c = await challengeBeforeDeciding(db.admin, { ...base, makeLlm: stubModel('approve') });
  assertEquals([c.cleared, c.state], [false, 'failed']);
  assertEquals(db.calls.map((x) => x.fn), ['fn_high_stakes_challenge']);
});
