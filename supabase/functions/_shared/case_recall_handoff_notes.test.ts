// The receiving seat's recall shows the handoff note FIRST (founder instruction 1013 item 6, 29 Sep 2026).
// Fails if the note stops being fetched for a named case, is fetched with no case, or no longer leads the
// prompt block ahead of past cases.
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { precedentBlock, recallCases } from './case_recall.ts';

const note = {
  handoff_id: 7, from: 'accountant', conversation: 'refund.settled', opened_at: '2026-09-29T00:00:00Z', status: 'pending',
  summary: { known: { case: 'zz_demo_case#ZZ-DEMO-1' }, tried: { actions: [] }, needed: { ask: 'tell the customer' }, evidence: ['public.zz_demo_case?id=eq.ZZ-DEMO-1'] },
};
const pastCase = {
  case_id: 3, seat: 'sales_engineer', case_kind: 'x', trade: null, situation: 'ZZ DEMO past', decision: null, reasoning: null,
  outcome: null, finalised: true, finalised_at: null, lessons: [], correction: null, corrected_by: null, similarity: 0.9, opened_at: '',
  source: null,
};

function fakeAdmin(calls: string[]) {
  return {
    rpc: (fn: string, args: Record<string, unknown>) => {
      calls.push(fn + ':' + JSON.stringify(args));
      if (fn === 'fn_seat_handoff_notes') return Promise.resolve({ data: [note], error: null });
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [pastCase] }, error: null });
      return Promise.resolve({ data: 1, error: null });
    },
  };
}

Deno.test('a named case brings its handoff note, and the note leads the block', async () => {
  const calls: string[] = [];
  const m = await recallCases(fakeAdmin(calls), {
    seat: 'sales_engineer', path: 'test', situation: 'ZZ DEMO', embedding: '[0]', exclude: { table: 'zz_demo_case', id: 'ZZ-DEMO-1' },
  });
  assertEquals(m.handoffs?.[0]?.handoff_id, 7);
  const block = precedentBlock(m);
  assert(block.indexOf('HANDOFF NOTES') >= 0 && block.indexOf('HANDOFF NOTES') < block.indexOf('PAST CASES'), block);
});

Deno.test('no case named, no handoff note fetched', async () => {
  const calls: string[] = [];
  const m = await recallCases(fakeAdmin(calls), { seat: 'sales_engineer', path: 'test', situation: 'ZZ DEMO', embedding: '[0]' });
  assertEquals(m.handoffs, []);
  assert(!calls.some((c) => c.startsWith('fn_seat_handoff_notes')));
});
