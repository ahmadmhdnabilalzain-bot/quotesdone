// The prompt-diet cuts inside think() (think/diet.ts), each proved on a mocked model: the prompt shrinks or keeps its cached
// prefix, and what the task's rules require is still there (the person's own question, the settled facts and the founder's
// rulings, every source the answer cites). No network, no paid call.
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import type { GateAnswer } from './llm_hold.ts';
import { settledFacts, think, type LlmReply, type Phase, type ThinkDeps } from './think.ts';
import { keepTopRows, placeRetryNote, reviewSources } from './think/diet.ts';
import { approxTokens } from './company_brief.ts';
import type { DietOverrides } from './prompt_diet.ts';

type Call = { phase: Phase; system: string; input: string; o: Record<string, unknown> };
const J = (x: unknown) => JSON.stringify(x);
const QUESTION = 'What is the monthly Resend e-mail cap and who signs off a raise?';
// twelve rows a step, as production returns (927 of 927 steps, 14 days), similarities 0.90 down to 0.79
const ROWS = Array.from({ length: 12 }, (_, i) => ({ source: 'it_engineer_knowledge', id: 100 + i, title: 'entry ' + i,
  excerpt: ('Row ' + i + ' of the IT pack. ').repeat(60), similarity: Math.round((0.90 - i * 0.01) * 1000) / 1000 }));

function mock(o: { diet?: DietOverrides; synth: string[]; verify?: string[]; stakes?: boolean }) {
  const calls: Call[] = [];
  const queues: Record<string, string[]> = { synthesise: [...o.synth], verify: [...(o.verify ?? [])],
    decompose: [J({ steps: [{ id: 's1', goal: 'the cap', query: 'Resend monthly cap' }], facts: [], high_stakes: false })] };
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as unknown as GateAnswer),
    llm: (phase, system, input, opts) => {
      calls.push({ phase, system, input, o: opts as Record<string, unknown> });
      const next = queues[phase]?.shift();
      return Promise.resolve((next ? { content: next, model: phase === 'verify' ? 'qwen/qwen3.8-flash' : 'openai/gpt-6-luna-pro' } : { content: null, error: 'no mock reply' }) as LlmReply);
    },
    embed: () => Promise.resolve([0.1, 0.2, 0.3]),
    rpc: (fn) => Promise.resolve({ data: fn === 'fn_reason_retrieve' ? ROWS : fn === 'fn_case_recall' ? { cases: [] } : 1, error: null }),
    ...(o.diet ? { diet: () => Promise.resolve(o.diet!) } : {}),
  };
  return { deps, calls };
}
const GOOD = J({ answer: 'The Resend cap is 50,000 e-mails a month; a raise is the IT engineer seat\'s call within its authority.', reasoning: ['s1: entry 0'], cited: ['it_engineer_knowledge:100'], confidence: 0.8 });
const EVADE = J({ answer: 'I need to check and get back to you.', cited: [], confidence: 0.2 });
const sources = (c: Call) => (JSON.parse(c.input.split('\n\nYOUR PREVIOUS')[0].split('\n\nAN INDEPENDENT')[0]).sources ?? []) as { id: string }[];

Deno.test('ON by default: a re-pass keeps the first pass\'s system prompt and payload as its prefix; the note ends the input', async () => {
  const m = mock({ synth: [EVADE, GOOD] });
  const r = await think(m.deps, { seat: 'it_engineer', surface: 'test', question: QUESTION, context: { audience: 'internal' } });
  assertEquals(r.status, 'answered');
  const [a, b] = m.calls.filter((c) => c.phase === 'synthesise');
  assertEquals(b.system, a.system, 'the system prompt is byte-identical on the re-pass');
  assert(b.input.startsWith(a.input), 'the payload is the re-pass\'s prefix');
  assertStringIncludes(b.input.slice(a.input.length), 'YOUR PREVIOUS DRAFT WAS REFUSED');
  // switched off: the old placement, so the switch really is the difference
  const off = mock({ synth: [EVADE, GOOD], diet: { retry_notes_ride_after_the_payload: false } });
  await think(off.deps, { seat: 'it_engineer', surface: 'test', question: QUESTION, context: { audience: 'internal' } });
  const [c, d] = off.calls.filter((x) => x.phase === 'synthesise');
  assertStringIncludes(d.system, 'YOUR PREVIOUS DRAFT WAS REFUSED');
  assertEquals(d.input, c.input);
});

Deno.test('the reviewer\'s correction rides after the payload too', async () => {
  const m = mock({ synth: [GOOD, GOOD], verify: [J({ verdict: 'disagree', problems: ['the cap is per day'] })] });
  await think(m.deps, { seat: 'it_engineer', surface: 'test', question: QUESTION, context: { audience: 'internal' }, stakes: 'high' });
  const [a, b] = m.calls.filter((c) => c.phase === 'synthesise');
  assertEquals(b.system, a.system);
  assert(b.input.startsWith(a.input) && b.input.endsWith('Correct them.'));
});

Deno.test('OFF by default: every retrieved row reaches the answer; ON: the top rows near the best, the cited one kept, the prompt smaller', async () => {
  const base = mock({ synth: [GOOD] });
  await think(base.deps, { seat: 'it_engineer', surface: 'test', question: QUESTION, context: { audience: 'internal' } });
  const before = base.calls.find((c) => c.phase === 'synthesise')!;
  assertEquals(sources(before).length, 12);
  const cut = mock({ synth: [GOOD], diet: { retrieval_keeps_the_top_rows_above_a_floor: true } });
  const r = await think(cut.deps, { seat: 'it_engineer', surface: 'test', question: QUESTION, context: { audience: 'internal' } });
  const after = cut.calls.find((c) => c.phase === 'synthesise')!;
  const ids = sources(after).map((s) => s.id);
  assertEquals(ids, ['it_engineer_knowledge:100', 'it_engineer_knowledge:101', 'it_engineer_knowledge:102', 'it_engineer_knowledge:103']);
  assert(approxTokens(after.input) < approxTokens(before.input) * 0.5, `${approxTokens(after.input)} vs ${approxTokens(before.input)}`);
  // what the task's rules need is still in the call: the question as asked, the settled facts, the founder's rulings
  assertStringIncludes(after.input, QUESTION);
  assertEquals(after.o.sysStable, settledFacts('internal', 'it_engineer'));
  assertStringIncludes(after.system, 'Standing rulings of the founder');
  assertEquals(r.status, 'answered');
  const step = r.steps.find((s) => s.kind === 'retrieve')!;
  assertEquals((step.detail as Record<string, unknown>).rows, 12, 'the step still records what the routine returned');
  assertEquals((step.detail as Record<string, unknown>).kept, 4);
  // scoped: an outside audience's answer class is not in the default scope, so a customer's reply keeps every row
  const cust = mock({ synth: [GOOD], diet: { retrieval_keeps_the_top_rows_above_a_floor: true } });
  await think(cust.deps, { seat: 'sales_engineer', surface: 'test', question: QUESTION, context: { audience: 'customer' } });
  assertEquals(sources(cust.calls.find((c) => c.phase === 'synthesise')!).length, 12);
});

Deno.test('OFF by default: the reviewer reads every source; ON: only the cited ones, and never nothing', async () => {
  const run = async (diet?: DietOverrides) => {
    const m = mock({ synth: [GOOD], verify: [J({ verdict: 'agree', problems: [] })], ...(diet ? { diet } : {}) });
    await think(m.deps, { seat: 'it_engineer', surface: 'test', question: QUESTION, context: { audience: 'internal' }, stakes: 'high' });
    return m.calls.find((c) => c.phase === 'verify')!;
  };
  const all = await run();
  assertEquals(JSON.parse(all.input).sources.length, 12);
  const mine = await run({ the_reviewer_reads_the_cited_sources_only: true });
  const v = JSON.parse(mine.input);
  assertEquals(v.sources.map((s: { id: string }) => s.id), ['it_engineer_knowledge:100']);
  assertEquals(v.question, QUESTION);
  assertStringIncludes(v.answer, '50,000');
  assertEquals(mine.o.sysStable, settledFacts('internal', 'it_engineer'), 'the reviewer still reads the settled facts (the routing eval: a judge must see the brief)');
  assert(approxTokens(mine.input) < approxTokens(all.input) * 0.2);
  assertEquals(reviewSources(true, [{ id: 'a' }, { id: 'b' }], []), [{ id: 'a' }, { id: 'b' }], 'cites nothing: reviewed against everything');
});

Deno.test('the pure cuts', () => {
  assertEquals(placeRetryNote(true, 'S', 'I', ''), { system: 'S', input: 'I' });
  assertEquals(placeRetryNote(true, 'S', 'I', '\n\nNOTE'), { system: 'S', input: 'I\n\nNOTE' });
  assertEquals(placeRetryNote(false, 'S', 'I', '\n\nNOTE'), { system: 'S\n\nNOTE', input: 'I' });
  assertEquals(keepTopRows(ROWS, { k: 10, delta: 0.025 }).length, 3, 'within 0.025 of 0.90: 0.90, 0.89, 0.88');
  assertEquals(keepTopRows([{ similarity: 'x' }, { similarity: null }], { k: 1 }).length, 1);
  assertEquals(keepTopRows([], { k: 4 }), []);
});
