// Exact specs for a trade with no line reader: required specs from the pack, judged by reasoning, held when missing.
import { assert, assertEquals } from 'jsr:@std/assert';
import { assessQuote, type Line } from './assess.ts';
import { checklistAttrs, chooseChecklist, reasonLineSpecs, specCode, withReasoned, type Checklist } from './reasoned_specs.ts';
import type { ThinkDeps } from '../think.ts';

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
  const key = `L1__${SPECS[0].code}`;
  const found = await reasonLineSpecs(deps({ synth: [J({ answer: 'glass is stated, the handrail is not', decision: { fields: { [key]: { value: '6 tonne', evidence: '6 tonne rated capacity' } } } })] }),
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

Deno.test('a trade that HAS a line reader is unchanged by a checklist', () => {
  const withReader = assessQuote({ category: 'gypsum', lines: [{ line_no: 1, description: 'Gypsum false ceiling', qty: 100, unit: 'sqm', amount: 5000 }], terms: TERMS, checklist: checklistAttrs(SPECS) });
  assert(!withReader.lines[0].asked.includes(SPECS[0].code));
});
