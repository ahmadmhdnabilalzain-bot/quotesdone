// seat_pool: every seat's model path reads the same shared pool (ceo, 13 Nov 2026, founder ledger 1688). No network: the
// routine is stubbed with the shape fn_seat_pool_context returns. Red before: think() and aiReply carried no pool at all.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { POOL_HEADER, POOL_MAX_CHARS, POOL_TIMEOUT_MS, SQL_BUDGET, poolSubject, seatPool } from './seat_pool.ts';
import { think, type LlmReply, type ThinkDeps } from './think.ts';
import { aiReply } from './ai_reply.ts';

const BLOCK = 'WHAT EVERY SEAT DID ON THIS SUBJECT (newest first):\n13 Nov 12:47 sales_engineer: supplier.approved -- verified=true\n'
  + 'THE COMPANY TODAY (built 12:48 Dubai): Last 24 h: 1 supplier.approved.';
type Call = { fn: string; args: Record<string, unknown> };
function rpcStub(block: string | null, calls: Call[] = [], hang = false) {
  return (fn: string, args: Record<string, unknown> = {}) => {
    calls.push({ fn, args });
    if (fn === 'fn_seat_pool_context') {
      if (hang) return new Promise<never>(() => {});
      return Promise.resolve(block == null ? { data: null, error: { message: 'function does not exist' } } : { data: { block, chars: block.length }, error: null });
    }
    return Promise.resolve({ data: fn === 'fn_judgement_record' ? 41 : fn.startsWith('fn_case_recall') ? { cases: [] } : [], error: null });
  };
}

Deno.test('poolSubject: the keys a seat names its subject by, and {table, id}; nothing else', () => {
  assertEquals(poolSubject({ supplier_id: 'L1', phone: '+971...', note: 'x' }, { inquiry_id: 7 }), { supplier_id: 'L1', inquiry_id: '7' });
  assertEquals(poolSubject({ table: 'leads', id: 9 }), { table: 'leads', id: '9' });
  assertEquals(poolSubject(null, 'x', [], { fixture: true }), null);
});

Deno.test('seatPool: the header fits beside a full block; the important first line is never cut; nothing on failure', async () => {
  assert(POOL_HEADER.length + 1 + SQL_BUDGET <= POOL_MAX_CHARS, 'the header must fit inside the budget');
  const full = 'YOUR HAND-OVERS: NO ANSWER YET: sales_engineer on knowledge.request #9.\n' + 'x'.repeat(SQL_BUDGET - 74);
  const calls: Call[] = [];
  const r = await seatPool({ rpc: rpcStub(full, calls) }, 'it_engineer', null, 'internal');
  assertEquals(calls[0].args.p_budget, SQL_BUDGET, 'the SQL is told the budget it must fit');
  assert(r.block.startsWith(POOL_HEADER + '\nYOUR HAND-OVERS: NO ANSWER YET'), 'the important line comes first and stays');
  assert(r.block.endsWith('x'), 'nothing is cut here');
  assert(r.chars <= POOL_MAX_CHARS, 'at most ' + POOL_MAX_CHARS + ', got ' + r.chars);
  // a block over its budget is a defect in the SQL: refused whole, never cut (a cut drops the end, not the least important)
  assertEquals((await seatPool({ rpc: rpcStub('x'.repeat(SQL_BUDGET + 1)) }, 'ceo', null, 'internal')).chars, 0);
  assertEquals(await seatPool({ rpc: rpcStub(null) }, 'ceo', null, 'internal'), { block: '', chars: 0 });
  const t0 = Date.now();
  assertEquals(await seatPool({ rpc: rpcStub(BLOCK, [], true) }, 'ceo', null, 'internal'), { block: '', chars: 0 });
  assert(Date.now() - t0 < POOL_TIMEOUT_MS + 500, 'a slow database never holds the reply');
});

Deno.test('seatPool: a customer, supplier or visitor without a subject asks nothing; the founder reads as an insider', async () => {
  const calls: Call[] = [];
  assertEquals((await seatPool({ rpc: rpcStub(BLOCK, calls) }, 'customer_support', null, 'customer')).chars, 0);
  assertEquals(calls.length, 0);
  await seatPool({ rpc: rpcStub(BLOCK, calls) }, 'ceo', null, 'founder');
  assertEquals(calls[0].args.p_audience, 'internal');
  await seatPool({ rpc: rpcStub(BLOCK, calls) }, 'customer_support', { customer_id: 'C1' }, 'supplier');
  assertEquals(calls[1].args.p_audience, 'supplier', 'the SQL then returns kinds and states only');
});

Deno.test('think(): every seat\'s synthesis reads the pool for its subject (founder 1688); a lean choice does not ask', async () => {
  for (const seat of ['customer_support', 'sales_engineer', 'marketing', 'it_engineer', 'ceo', 'accountant'] as const) {
    const calls: Call[] = []; const inputs: string[] = [];
    const deps = {
      gate: () => Promise.resolve(null),
      llm: (phase: string, _s: string, input: string) => {
        inputs.push(phase + ':' + input);
        return Promise.resolve({ content: phase === 'decompose'
          ? JSON.stringify({ steps: [], facts: [], high_stakes: false })
          : JSON.stringify({ answer: 'The supplier was verified by the sales engineer today.', reasoning: ['pool'], cited: [], asked_back: null, confidence: 0.9 }), model: 'stub' } as LlmReply);
      },
      embed: () => Promise.resolve([0.1, 0.2]),
      rpc: rpcStub(BLOCK, calls),
    } as unknown as ThinkDeps;
    await think(deps, { seat, surface: seat + '.pool_probe', question: 'What is the state of this supplier?', research: false,
      context: { audience: 'internal', case: { supplier_id: 'L1' } }, subject: { supplier_id: 'L1' } });
    const pc = calls.find((c) => c.fn === 'fn_seat_pool_context');
    assert(pc, seat + ': the pool was not read');
    assertEquals(pc.args, { p_seat: seat, p_subject: { supplier_id: 'L1' }, p_audience: 'internal', p_budget: SQL_BUDGET });
    assert(inputs.some((i) => i.startsWith('synthesise:') && i.includes('sales_engineer: supplier.approved')), seat + ': the synthesis did not carry the pool');
  }
  const calls: Call[] = [];
  const deps = { gate: () => Promise.resolve(null), embed: () => Promise.resolve([0.1]), rpc: rpcStub(BLOCK, calls),
    llm: () => Promise.resolve({ content: JSON.stringify({ answer: 'x', reasoning: [], cited: [], asked_back: null, decision: { choice: 'none' } }), model: 'stub' }) } as unknown as ThinkDeps;
  await think(deps, { seat: 'customer_support', surface: 'wa_inbound.intent_table', question: 'hi', context: { audience: 'customer' } as never,
    decision: { name: 'q', options: [{ id: 'none', meaning: 'none' }, { id: 'x', meaning: 'x' }] }, plan: { steps: [] }, lean: true });
  assertEquals(calls.filter((c) => c.fn === 'fn_seat_pool_context').length, 0);
});

Deno.test('aiReply: a reply about a subject carries the pool in its input, and none without one', async () => {
  for (const withSubject of [true, false]) {
    const calls: Call[] = []; const inputs: string[] = [];
    const deps = {
      gate: () => Promise.resolve(null), embed: () => Promise.resolve(null),
      llm: (_p: string, _s: string, input: string) => { inputs.push(input); return Promise.resolve({ content: JSON.stringify({ answer: 'Your request has two quotations so far.' }), model: 'stub' } as LlmReply); },
      rpc: rpcStub('12 Nov 23:57 sales_engineer: quote.received (recorded)', calls),
    } as unknown as ThinkDeps;
    await aiReply(deps, { seat: 'customer_support', channel: 'portal', audience: 'customer', lang: 'en', message: 'Any quotes yet?',
      ...(withSubject ? { poolSubject: { inquiry_id: '12' } } : {}) });
    assertEquals(calls.some((c) => c.fn === 'fn_seat_pool_context'), withSubject);
    assertEquals(inputs.some((i) => i.includes('quote.received')), withSubject);
  }
});
