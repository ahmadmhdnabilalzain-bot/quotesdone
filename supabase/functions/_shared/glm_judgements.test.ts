// glm_judgements with a MOCKED model and database: each judgement answered each way; the hold and a reading
// outside the format all leave the row queued (never a word-list answer); every model step is billed to GLM.
//   deno test --no-lock supabase/functions/_shared/glm_judgements.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { GateAnswer } from './llm_hold.ts';
import type { LlmReply, Phase, ThinkDeps } from './think.ts';
import { answerLines, cellVerdict, chunks, differingCells, drain, GLM_CLASS, type Row } from './glm_judgements.ts';

const J = (x: unknown) => JSON.stringify(x);
const PLAN = J({ steps: [{ id: 's1', goal: 'read what was given', needs_knowledge: false }], facts: [] });
const HOLD = { allowed: false, rule: 'founder_hold', held: 1, routes: 8 };

function mock(o: { rows: Row[]; hold?: boolean; synth?: unknown[]; taxonomy?: { code: string; label: string }[] }) {
  const rpcs: [string, Record<string, unknown>][] = [];
  const classes: string[] = [];
  const synth = [...(o.synth ?? [])].map((x) => J(x));
  const deps: ThinkDeps = {
    gate: () => Promise.resolve((o.hold ? HOLD : { allowed: false, rule: 'route_not_registered' }) as GateAnswer),
    llm: (phase: Phase, _s, _i, opt) => {
      classes.push(opt.taskClass);
      const content = phase === 'decompose' ? PLAN : phase === 'synthesise' ? synth.shift() ?? null : J({ verdict: 'agree', problems: [] });
      return Promise.resolve({ content, model: 'z-ai/glm-5.3-flash' } as LlmReply);
    },
    embed: () => Promise.resolve(null),
    rpc: (fn, args) => {
      rpcs.push([fn, args]);
      if (fn === 'fn_glm_judgement_due') return Promise.resolve({ data: o.rows, error: null });
      if (fn === 'fn_glm_taxonomy_trades') return Promise.resolve({ data: o.taxonomy ?? [], error: null });
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      if (fn === 'fn_reason_retrieve') return Promise.resolve({ data: [], error: null });
      return Promise.resolve({ data: null, error: null });
    },
  };
  const calls = (f: string) => rpcs.filter(([n]) => n === f).map(([, a]) => a);
  return { deps, rpcs, classes, calls };
}
const row = (kind: Row['kind'], input: Record<string, unknown>): Row => ({ id: 9, kind, subject_key: 'k', input, attempts: 0 });

// ── 1. quote spec match ──
const CELLS = [{ line_no: 1, attr: 'Grade', requested: 'SS316', quoted: 'SS304' }, { line_no: 2, attr: 'Thickness', requested: '1.2 mm', quoted: '1.5 mm' }];
Deno.test('spec match: SS304 for SS316 is a mismatch with its reason, a thicker sheet meets; billed to GLM', async () => {
  const m = mock({ rows: [row('quote_spec_match', { quote_id: 'q1', cells: CELLS })], synth: [{
    answer: 'c0: mismatch - SS304 quoted, SS316 requested, lower corrosion grade\nc1: meets', decision: { choice: 'some_mismatch' } }] });
  const r = await drain(m.deps);
  assertEquals(r, { done: 1, held: 0, failed_reading: 0 });
  const res = m.calls('fn_glm_judgement_resolve')[0].p_result as { cells: { mismatch: boolean; why: string | null }[] };
  assertEquals(res.cells.map((c) => c.mismatch), [true, false]);
  assert(res.cells[0].why!.startsWith('SS304 quoted'));
  assert(m.classes.length > 0 && m.classes.every((c) => c === GLM_CLASS), 'a step left the GLM class: ' + m.classes.join(','));
});
Deno.test('spec match: a cell answered outside the format is a failed reading, deferred and counted - never guessed', async () => {
  const m = mock({ rows: [row('quote_spec_match', { quote_id: 'q1', cells: CELLS })], synth: [{ answer: 'c0: probably fine\nc1: meets', decision: { choice: 'all_meet' } }] });
  const r = await drain(m.deps);
  assertEquals(r.failed_reading, 1);
  assertEquals(m.calls('fn_glm_judgement_resolve').length, 0);
  assertEquals(m.calls('fn_glm_judgement_defer')[0].p_counts, true);
});
Deno.test('spec match: a decision that contradicts its own cell lines is refused', async () => {
  const m = mock({ rows: [row('quote_spec_match', { quote_id: 'q1', cells: CELLS })], synth: [{ answer: 'c0: mismatch - grade\nc1: meets', decision: { choice: 'all_meet' } }] });
  assertEquals((await drain(m.deps)).failed_reading, 1);
});

// ── 2. repeat request ──
Deno.test('repeat: English and Arabic of the same job is judged the same', async () => {
  const m = mock({ rows: [row('repeat_request', { inquiry_id: 'b', earlier_id: 'a', earlier: 'Paint 3-bedroom villa interior', later: 'دهان فيلا ثلاث غرف من الداخل' })],
    synth: [{ answer: 'The same villa painting job, written in Arabic.', decision: { choice: 'same' } }] });
  await drain(m.deps);
  assertEquals((m.calls('fn_glm_judgement_resolve')[0].p_result as { verdict: string }).verdict, 'same');
});

// ── 3. supplier trade words ──
const TAX = [{ code: 'hvac', label: 'HVAC' }, { code: 'electrical', label: 'Electrical' }, { code: 'plumbing', label: 'Plumbing' }];
Deno.test('trade words: one exact trade is offered as that code, with nothing to ask', async () => {
  const m = mock({ taxonomy: TAX, rows: [row('supplier_trade_words', { proposal_id: 5, words: 'AC ducting and chillers' })],
    synth: [{ answer: 'Air-conditioning work is the HVAC trade.', decision: { choice: 'hvac' } }] });
  await drain(m.deps);
  assertEquals(m.calls('fn_glm_judgement_resolve')[0].p_result, { proposal_id: 5, codes: ['hvac'], ask: null });
});
Deno.test('trade words: combined MEP maps to several EXACT trades, with the question to ask', async () => {
  const m = mock({ taxonomy: TAX, rows: [row('supplier_trade_words', { proposal_id: 5, words: 'combined MEP works' })],
    synth: [{ answer: 'MEP spans three listed trades.\ncodes: hvac, electrical, plumbing\nask: Which of HVAC, electrical and plumbing do you do yourselves?', decision: { choice: 'several' } }] });
  await drain(m.deps);
  const res = m.calls('fn_glm_judgement_resolve')[0].p_result as { codes: string[]; ask: string };
  assertEquals(res.codes, ['hvac', 'electrical', 'plumbing']);
  assert(res.ask.startsWith('Which'));
});
Deno.test('trade words: a code outside the taxonomy is refused and counted, never written', async () => {
  const m = mock({ taxonomy: TAX, rows: [row('supplier_trade_words', { proposal_id: 5, words: 'tents and shades' })],
    synth: [{ answer: 'Shade work.\ncodes: shade-structures, hvac', decision: { choice: 'several' } }] });
  assertEquals((await drain(m.deps)).failed_reading, 1);
  assertEquals(m.calls('fn_glm_judgement_resolve').length, 0);
});
Deno.test('trade words: none is an answer - no code, the question to ask kept', async () => {
  const m = mock({ taxonomy: TAX, rows: [row('supplier_trade_words', { proposal_id: 5, words: 'tents and shades' })],
    synth: [{ answer: 'We list no shade-structure trade.\nask: Do you fabricate the steel frames, or supply the fabric only?', decision: { choice: 'none' } }] });
  await drain(m.deps);
  const res = m.calls('fn_glm_judgement_resolve')[0].p_result as { codes: string[]; ask: string };
  assertEquals(res.codes, []);
  assert(res.ask.startsWith('Do you'));
});

// ── 4. unknown sender mail ──
Deno.test('mail: a category from the fixed list and a summary', async () => {
  const m = mock({ rows: [row('unknown_sender_mail', { message_id: 3, from: 'x@example.invalid', subject: 'partnership', body: 'We would like to list our marketplace with you.' })],
    synth: [{ answer: 'The sender asks to partner and list their marketplace with us.', decision: { choice: 'partnership' } }] });
  await drain(m.deps);
  assertEquals((m.calls('fn_glm_judgement_resolve')[0].p_result as { category: string }).category, 'partnership');
});

// ── held paths ──
Deno.test('the model hold: no model call, deferred without counting (waiting is not a failure)', async () => {
  const m = mock({ hold: true, rows: [row('unknown_sender_mail', { body: 'hello' })] });
  const r = await drain(m.deps);
  assertEquals(r, { done: 0, held: 1, failed_reading: 0 });
  assertEquals(m.classes.length, 0);
  assertEquals(m.calls('fn_glm_judgement_defer')[0].p_counts, false);
});
Deno.test('no daily cap: nothing asks for a slot before the model', async () => {
  const m = mock({ rows: [row('unknown_sender_mail', { message_id: 3, body: 'hello' })], synth: [{ answer: 'A greeting.', decision: { choice: 'other' } }] });
  await drain(m.deps);
  assertEquals(m.rpcs.filter(([n]) => /take|cap|budget/.test(n)).length, 0);
  assertEquals(m.calls('fn_glm_judgement_resolve').length, 1);
});
Deno.test('a reading outside the format counts toward the three tries (the loop bound)', async () => {
  const m = mock({ rows: [row('unknown_sender_mail', { message_id: 3, body: 'hello' })], synth: [{ answer: 'x', decision: { choice: 'not-a-category' } }, { answer: 'x', decision: { choice: 'not-a-category' } }] });
  const r = await drain(m.deps);
  assertEquals(r.failed_reading, 1);
  assertEquals(m.calls('fn_glm_judgement_defer')[0].p_counts, true);
});

// ── pure helpers ──
Deno.test('cellVerdict reads only the leading verdict word', () => {
  assertEquals(cellVerdict('mismatch: x'), 'mismatch');
  assertEquals(cellVerdict('Meets.'), 'meets');
  assertEquals(cellVerdict('it meets'), null);
  assertEquals(answerLines('c0: meets\nCodes: a, b'), { c0: 'meets', codes: 'a, b' });
});
Deno.test('differingCells takes only ≠ cells of the quote that have a request; chunks bound one judgement', () => {
  const t = { lines: [{ row: 1, request_line: { line_no: 4 }, attributes: [
    { code: 'grade', label_en: 'Grade', requested: 'SS316', cells: [{ quote_id: 'q1', value: 'SS304', flag: 'differs' }, { quote_id: 'q2', value: 'SS316', flag: 'match' }] },
    { code: 'finish', label_en: 'Finish', requested: null, cells: [{ quote_id: 'q1', value: 'brushed', flag: 'stated' }] }] }] };
  assertEquals(differingCells(t, 'q1'), [{ line_no: 4, attr: 'Grade', requested: 'SS316', quoted: 'SS304' }]);
  assertEquals(differingCells(t, 'q2'), []);
  assertEquals(chunks([1, 2, 3, 4, 5], 2).length, 3);
});
Deno.test('a refused draft (model_failed) counts toward the three tries; only the model hold waits uncounted', async () => {
  const m = mock({ rows: [row('repeat_request', { earlier: 'a', later: 'b' })], synth: [] });
  const r = await drain(m.deps);
  assertEquals(r, { done: 0, held: 0, failed_reading: 1 });
  assertEquals(m.calls('fn_glm_judgement_defer')[0].p_counts, true);
});
