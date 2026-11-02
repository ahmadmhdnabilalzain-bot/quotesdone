// Exact specs for a trade with no line reader: required specs from the pack, judged by reasoning, held when missing.
import { assert, assertEquals } from 'jsr:@std/assert';
import { assessQuote, type Line } from './assess.ts';
import { checklistAttrs, chooseChecklist, LINES_PER_CALL, needsChecklist, reasonLineSpecs, specCode, unionOf, withReasoned, type Checklist } from './reasoned_specs.ts';
import { labelUnit, shapeDecides } from './field_format.ts';
import type { ThinkDeps } from '../think.ts';
import { forgetReads } from '../reasoned_matching.ts';

const J = JSON.stringify;
function deps(opts: { held?: boolean; synth?: string[] }): ThinkDeps {
  const queue = [...(opts.synth ?? [])];
  return {
    gate: () => Promise.resolve(opts.held ? { allowed: false, rule: 'founder_hold' } : { allowed: false, rule: 'route_not_registered' }),
    llm: (phase) => Promise.resolve(phase === 'decompose'
      ? { content: J({ steps: [{ id: 's1', goal: 'read the lines', needs_knowledge: false }], facts: [] }), model: 'm' }
      : { content: queue.shift() ?? null, model: 'm' }),
    embed: () => Promise.resolve(null),
    rpc: (fn) => Promise.resolve({ data: fn === 'fn_reason_hold' ? 1 : null, error: null }),
  };
}
const SPECS = [
  { code: specCode('rated capacity (tonnes)'), label_en: 'rated capacity (tonnes)' },
  { code: specCode('lip type and length'), label_en: 'lip type and length' },
];
const LISTS: Checklist[] = [
  { topic_id: 'glazing:spec-checklist-facade-igu', topic: 'Spec checklist: facade / window IGU', specs: [{ code: 'spec_outer_pane', label_en: 'outer pane: thickness' }] },
  { topic_id: 'glazing:spec-checklist-balustrade', topic: 'Spec checklist: glass balustrade', specs: SPECS },
];
// A trade with no line reader (a dock leveller): no keyword of model.ts reads this line.
const LINES: Line[] = [{ line_no: 1, description: 'Hydraulic dock leveller 2.0 x 2.5 m, 6 tonne rated capacity', qty: 2, unit: 'nos', amount: 30000 }];
const TERMS = { terms_spec: { delivery: { value: '4 weeks' } } } as never;

Deno.test('a code is stable and readable', () => {
  assertEquals(specCode('cavity width and gas fill (air/argon %)'), 'spec_cavity_width_and_gas_fill');
});

Deno.test('which checklist applies is reasoned; under the hold every checklist is asked', async () => {
  const live = await chooseChecklist(deps({ synth: [J({ answer: 'the lines price a dock leveller', decision: { choice: 'glazing:spec-checklist-balustrade' } })] }),
    { checklists: LISTS, lines: LINES, trade: 'glazing', quoteId: 'q1' });
  assertEquals([live.topic, live.reasoned, live.rows.length], ['glazing:spec-checklist-balustrade', true, 2]);
  // A reading once answered is settled (reasoned_matching.ts settledRead); the hold case is lines never read, on a new worker.
  forgetReads();
  const held = await chooseChecklist(deps({ held: true }), { checklists: LISTS, lines: LINES, trade: 'glazing', quoteId: 'q1' });
  assertEquals([held.topic, held.reasoned, held.rows.length], [null, false, 3]);
});

Deno.test('under the model hold nothing is judged, every required spec is missing, and the quote is held', async () => {
  const checklist = checklistAttrs(SPECS);
  const found = await reasonLineSpecs(deps({ held: true }), { lines: LINES, checklist, trade: 'glazing', quoteId: 'q1' });
  assertEquals(found, null);
  const a = assessQuote({ category: 'zz-demo-readerless-trade', lines: withReasoned(LINES, found), terms: TERMS, checklist });
  assert(a.held);
  assertEquals(a.missing.filter((m) => m.scope === 'line').map((m) => m.attr).sort(), SPECS.map((s) => s.code).sort());
});

Deno.test('what the supplier\'s own words state is filled; only what they do not state holds the quote', async () => {
  const checklist = checklistAttrs(SPECS);
  // the capacity is read by SHAPE (one "<n> tonne", one spec in tonnes); the model is asked only the lip, and finds it unstated
  const found = await reasonLineSpecs(deps({ synth: [J({ answer: 'the lip is not stated', decision: { fields: {} } })] }),
    { lines: LINES, checklist, trade: 'glazing', quoteId: 'q1' });
  assertEquals(found, { 1: { [SPECS[0].code]: '6 tonne' } });
  const a = assessQuote({ category: 'zz-demo-readerless-trade', lines: withReasoned(LINES, found), terms: TERMS, checklist });
  assertEquals(a.lines[0].source[SPECS[0].code], 'reasoned');
  assertEquals(a.missing.filter((m) => m.scope === 'line').map((m) => m.attr), [SPECS[1].code]);
});

Deno.test('a value the supplier did not write is refused by the validator, so it is never filled', async () => {
  const checklist = checklistAttrs(SPECS);
  const invented = J({ answer: 'x', decision: { fields: { [`L1__${SPECS[1].code}`]: { value: 'telescopic 500 mm', evidence: 'telescopic 500 mm lip' } } } });
  const found = await reasonLineSpecs(deps({ synth: [invented, invented] }), { lines: LINES, checklist, trade: 'glazing', quoteId: 'q1' });
  assertEquals(found, null, 'refused twice: the reasoning is held, nothing is filled');
});

Deno.test('a composite trade (fit-out, MEP) is read by the trades its lines name, never the pack checklist', () => {
  assertEquals([needsChecklist('fitout'), needsChecklist('combined-mep'), needsChecklist('gypsum'), needsChecklist('zz-demo-dock-equipment')], [false, false, false, true]);
  const fit = assessQuote({ category: 'fitout', lines: LINES, terms: TERMS, checklist: checklistAttrs(SPECS) });
  assert(!fit.lines[0].asked.includes(SPECS[0].code));
});

Deno.test('reasoning never overwrites a value the supplier entered', () => {
  const entered: Line[] = [{ ...LINES[0], spec: { [SPECS[0].code]: '6.5 t' }, spec_source: { [SPECS[0].code]: 'supplier_portal' } }];
  const out = withReasoned(entered, { 1: { [SPECS[0].code]: '6 tonne', [SPECS[1].code]: 'hinged 400 mm' } });
  assertEquals(out[0].spec, { [SPECS[0].code]: '6.5 t', [SPECS[1].code]: 'hinged 400 mm' });
  assertEquals(out[0].spec_source, { [SPECS[0].code]: 'supplier_portal', [SPECS[1].code]: 'reasoned' });
});

Deno.test('a long quote is reasoned a few lines at a time, so every answer fits and every line keeps its own words', async () => {
  let synthCalls = 0;
  const d = deps({ synth: [] });
  const base = d.llm;
  d.llm = (phase, sys, input, o) => { if (phase === 'synthesise') synthCalls++; return base(phase, sys, input, o); };
  const many: Line[] = Array.from({ length: 7 }, (_, i) => ({ line_no: i + 1, description: 'Hydraulic dock leveller bay ' + (i + 1), qty: 1, unit: 'nos', amount: 1000 }));
  await reasonLineSpecs(d, { lines: many, checklist: checklistAttrs(SPECS), trade: 'x', quoteId: 'q2' });
  assertEquals(synthCalls >= 3, true, 'three batches of at most ' + LINES_PER_CALL + ' lines');
});

Deno.test('every checklist together names its list and the honest way out', () => {
  const u = unionOf(LISTS);
  assertEquals(u.length, 3);
  assert(/^glass balustrade — rated capacity \(tonnes\) \(if you are not quoting this, write "not applicable" and why\)$/.test(u[1].label_en), u[1].label_en);
});

Deno.test('a trade that HAS a line reader is unchanged by a checklist', () => {
  const withReader = assessQuote({ category: 'gypsum', lines: [{ line_no: 1, description: 'Gypsum false ceiling', qty: 100, unit: 'sqm', amount: 5000 }], terms: TERMS, checklist: checklistAttrs(SPECS) });
  assert(!withReader.lines[0].asked.includes(SPECS[0].code));
});

// ── the routine path stays code: each test FAILS if the line goes back to the model ──
function counting(o: { cache?: Record<string, unknown> } = {}) {
  const calls = { llm: 0, put: [] as unknown[] };
  const d: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true, rule: 'ok' }),
    llm: () => { calls.llm++; return Promise.resolve({ content: null, model: 'm' }); },
    embed: () => Promise.resolve(null),
    rpc: (fn, args) => {
      if (fn === 'fn_line_spec_reading_get') return Promise.resolve({ data: o.cache ?? {}, error: null });
      if (fn === 'fn_line_spec_reading_put') calls.put.push(args);
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { d, calls };
}
const NUMERIC = checklistAttrs([{ code: 'spec_cap', label_en: 'capacity (litres)' }, { code: 'spec_bin', label_en: 'bin capacity (kg)' }]);

Deno.test('shape: a unit named in the label is read by format, never by meaning', () => {
  assertEquals([labelUnit('rated capacity (tonnes)'), labelUnit('camera count (DORI)'), labelUnit('bin capacity (L)')], ['tonne', null, 'l']);
  assertEquals(shapeDecides('Water heater 80 litres, 20 kg bin', NUMERIC).present, { spec_cap: '80 litres', spec_bin: '20 kg' });
  assertEquals(shapeDecides('Water heater, supply only', NUMERIC).absent, ['spec_cap', 'spec_bin']);
  assertEquals(shapeDecides('80 litres or 100 litres', NUMERIC).ambiguous.map((a) => a.code), ['spec_cap', 'spec_bin'], 'two readings, or none: the model decides');
});

Deno.test('a line whose numeric specs are settled by shape never reaches the model', async () => {
  const { d, calls } = counting();
  const found = await reasonLineSpecs(d, { lines: [{ line_no: 1, description: 'Heater 80 litres, bin 20 kg', qty: 1 }, { line_no: 2, description: 'Labour and transport' }], checklist: NUMERIC, trade: 'x', quoteId: 'q9' });
  assertEquals(calls.llm, 0);
  assertEquals(found, { 1: { spec_cap: '80 litres', spec_bin: '20 kg' } });
});

Deno.test('a line already reasoned (same text, same checklist) is reused by its hash, never paid for twice', async () => {
  const first = counting();
  const line: Line = { line_no: 1, description: 'Hydraulic dock leveller with telescopic lip' };
  const cl = checklistAttrs(SPECS);
  await reasonLineSpecs(first.d, { lines: [line], checklist: cl, trade: 'x', quoteId: 'q9' });
  assert(first.calls.llm > 0, 'the first sight is reasoned');
  // the model returned nothing usable, so nothing was stored; now the store holds an answer for that hash
  const k = [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(line.description + '|' + cl.map((a) => a.code).sort().join(','))))].map((b) => b.toString(16).padStart(2, '0')).join('');
  const again = counting({ cache: { [k]: { [SPECS[1].code]: 'telescopic lip' } } });
  const found = await reasonLineSpecs(again.d, { lines: [line], checklist: cl, trade: 'x', quoteId: 'q9' });
  assertEquals(again.calls.llm, 0);
  assertEquals(found, { 1: { [SPECS[1].code]: 'telescopic lip' } });
});
