// The intake's two decisions run inside a customer's turn, on its clock, and still fill only what the customer's own
// words prove (27 Oct 2026, sales_engineer; inquiry_intake/turn_clock.ts has the production measurements). No network,
// no paid call: the model is a mock that records each phase it was asked for and how long it was allowed.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { GateAnswer } from './llm_hold.ts';
import { MIN_STEP_MS, SYNTH_FOR_READERS, withDeadline, type LlmReply, type Phase, type ThinkDeps } from './think.ts';
import { statedSpecs, tradeOf } from './reasoned_decisions.ts';

const J = (x: unknown) => JSON.stringify(x);
function mock(synth: () => unknown, delayMs = 0) {
  const calls: { phase: Phase; timeoutMs?: number; max?: number; effort?: string }[] = [];
  const rpcs: string[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: false, rule: 'route_not_registered' } as GateAnswer),
    llm: async (phase, _s, _i, o) => {
      calls.push({ phase, timeoutMs: o.timeoutMs, max: o.max, effort: o.effort });
      await new Promise((r) => setTimeout(r, delayMs));
      const content = phase === 'synthesise' ? J(synth()) : J({ steps: [{ id: 's1', goal: 'x', query: 'x' }], facts: [] });
      return { content, model: 'openai/gpt-6-luna-pro' } as LlmReply;
    },
    embed: () => Promise.resolve([0.1, 0.2, 0.3]),
    rpc: (fn) => { rpcs.push(fn); return Promise.resolve({ data: fn === 'fn_reason_retrieve' ? [] : fn === 'fn_case_recall' ? { cases: [] } : 1, error: null }); },
    search: () => Promise.resolve([]),
    read: () => Promise.resolve(null),
  };
  return { deps, calls, rpcs };
}

const WINDOWS = 'Aluminium windows for our villa: supply and install 40 units, each 1200 x 1500 mm, powder coated white.';
const FIELDS = [
  { key: 'dimensions_qty', question: 'How many pieces, and how big is each?' },
  { key: 'scope', question: 'Supply only, or supply and install?' },
  { key: 'glazing', question: 'What glass?' },
];

Deno.test('withDeadline: no model call starts with under MIN_STEP_MS left, and none may run past the deadline', async () => {
  const m = mock(() => ({}));
  const now = 1_000_000;
  const late = withDeadline(m.deps, now + MIN_STEP_MS - 1, MIN_STEP_MS, () => now);
  const r = await late.llm('synthesise', 's', 'i', { taskClass: 'x', seat: 'sales_engineer' });
  assertEquals(r.content, null);
  assert(/^turn_deadline/.test(String(r.error)), String(r.error));
  assertEquals(m.calls.length, 0, 'a call was started that could not finish in time');
  const ok = withDeadline(m.deps, now + 12_000, MIN_STEP_MS, () => now);
  await ok.llm('synthesise', 's', 'i', { taskClass: 'x', seat: 'sales_engineer', timeoutMs: 45_000 });
  assertEquals(m.calls[0].timeoutMs, 12_000, 'the call was allowed longer than the turn has left');
});

Deno.test('the exact-spec reading plans nothing, retrieves nothing, makes ONE call (low: the effort that fits the turn), and has room for its fields', async () => {
  const m = mock(() => ({ answer: 'read', decision: { fields: {
    dimensions_qty: { value: '40 units, each 1200 x 1500 mm', evidence: 'supply and install 40 units, each 1200 x 1500 mm' },
    scope: { value: 'supply and install', evidence: 'supply and install 40 units' },
  } } }));
  const r = await statedSpecs(m.deps, { conversation: WINDOWS, category: 'aluminium', fields: FIELDS, deadline: Date.now() + 20_000 });
  assertEquals(m.calls.map((c) => c.phase), ['synthesise'], 'more than one model call: ' + J(m.calls));
  // corrected 12 Nov 2026 (ledger 1642): it decides, but it runs inside the customer's chat turn, where high finished 0 of 22
  // times; it asks the effort measured inside the turn, low (effort_policy.ts SURFACES clock), never "proven low"
  assertEquals(m.calls[0].effort, 'low');
  assertEquals(m.calls[0].max, SYNTH_FOR_READERS);
  assert(!m.rpcs.includes('fn_reason_retrieve') && !m.rpcs.includes('fn_reason_retrieve_ml'), 'knowledge was retrieved: ' + J(m.rpcs));
  assertEquals(r.value?.dimensions_qty?.value, '40 units, each 1200 x 1500 mm');
  assertEquals(r.value?.scope?.value, 'supply and install');
  assertEquals(r.value?.glazing, undefined, 'a spec the customer never stated was filled');
});

// THE SAFEGUARD: exact specs or nothing. A value the customer did not write, or evidence they did not write, fills nothing.
Deno.test('the exact-spec reading drops a field whose value is not in the customer\'s own words, and keeps the proven ones', async () => {
  const m = mock(() => ({ answer: 'read', decision: { fields: {
    scope: { value: 'supply and install', evidence: 'supply and install 40 units' },
    glazing: { value: 'double glazed', evidence: 'double glazed units throughout' },   // never said
    dimensions_qty: { value: '60 units', evidence: 'supply and install 40 units' },     // value not inside the evidence
  } } }));
  const r = await statedSpecs(m.deps, { conversation: WINDOWS, category: 'aluminium', fields: FIELDS, deadline: Date.now() + 20_000 });
  assertEquals(Object.keys(r.value ?? {}).sort(), ['scope'], J(r.value));
});

Deno.test('the exact-spec reading with no time left makes no call, fills nothing and queues nothing', async () => {
  const m = mock(() => ({ answer: 'read', decision: { fields: { scope: { value: 'supply and install', evidence: 'supply and install 40 units' } } } }));
  const r = await statedSpecs(m.deps, { conversation: WINDOWS, category: 'aluminium', fields: FIELDS, deadline: Date.now() + 1_000 });
  assertEquals(r.value, null, 'a spec was filled although the reading never ran');
  assertEquals(m.calls.length, 0);
  assert(!m.rpcs.includes('fn_reason_hold'), 'the unrun reading was filed for a paid replay nothing consumes: ' + J(m.rpcs));
});

Deno.test('the trade is a choice among given options: no planner, one call (low: the effort that fits the turn)', async () => {
  const m = mock(() => ({ answer: 'They want aluminium windows.', reasoning: ['decide: windows'], cited: [], confidence: 0.9, decision: { choice: 'aluminium' } }));
  const r = await tradeOf(m.deps, { conversation: WINDOWS, candidates: [{ slug: 'aluminium', label: 'aluminium' }, { slug: 'flooring', label: 'flooring' }], deadline: Date.now() + 20_000 });
  assertEquals(m.calls.map((c) => c.phase), ['synthesise'], J(m.calls));
  // corrected 12 Nov 2026 (ledger 1642): it decides, but it runs inside the customer's chat turn, where high finished 0 of 22
  // times; it asks the effort measured inside the turn, low (effort_policy.ts SURFACES clock), never "proven low"
  assertEquals(m.calls[0].effort, 'low');
  assertEquals(r.value, 'aluminium');
});

// A MOCKED TIMING TEST: a model that would take 40 s (what the answer pass measured at p95) is cut at the turn's clock.
Deno.test('a slow model is cut at the clock: the reading ends by the deadline with nothing filled', async () => {
  const deps = mock(() => ({})).deps;
  const slow: ThinkDeps = { ...deps, llm: (_p, _s, _i, o) => new Promise((res) => {
    const t = setTimeout(() => res({ content: J({ answer: 'late', decision: { fields: { scope: { value: 'supply and install', evidence: 'supply and install 40 units' } } } }) }), 40_000);
    setTimeout(() => { clearTimeout(t); res({ content: null, error: 'timeout after ' + o.timeoutMs + ' ms' }); }, o.timeoutMs ?? 40_000);
  }) };
  const t0 = Date.now();
  const r = await statedSpecs(slow, { conversation: WINDOWS, category: 'aluminium', fields: FIELDS, deadline: t0 + MIN_STEP_MS + 300 });
  const took = Date.now() - t0;
  assert(took < MIN_STEP_MS + 1_500, `the reading ran ${took} ms past a ${MIN_STEP_MS + 300} ms clock`);
  assertEquals(r.value, null);
});
