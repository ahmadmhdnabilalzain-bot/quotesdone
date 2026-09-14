// deno test supabase/functions/drawing_boq/confirm.test.ts
// The model CONFIRMS the coded draft and never becomes the source silently: agreement confirms,
// disagreement and model-only lines become the customer's question, no reply leaves the code standing.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { mergeConfirm, parseConfirm, confirmUserText } from './confirm.ts';
import { isOpen, lineKey, type Line } from '../_shared/boq_open_lines.ts';

const DRAFT: Line[] = [
  { description: 'Smoke detector', type: 'smoke_detector', qty: null, estimate: 8, unit: 'nos', qty_status: 'to_confirm', basis: 'template match' },
  { description: 'Heat detector', type: 'heat_detector', qty: null, estimate: 1, unit: 'nos', qty_status: 'to_confirm', basis: 'template match' },
  { description: 'Manual call point (break glass)', type: 'manual_call_point', qty: null, estimate: 23, unit: 'nos', qty_status: 'to_confirm' },
];
const KEYS = new Set(DRAFT.map(lineKey));

Deno.test('the reply is held to the contract; anything outside it is dropped', () => {
  assertEquals(parseConfirm('not json at all', KEYS), null);
  const r = parseConfirm('```json\n{"lines":[{"key":"boq_smoke_detector","verdict":"agree"},{"key":"boq_heat_detector","verdict":"disagree","value":4},{"key":"boq_unknown","verdict":"agree"},{"key":"boq_manual_call_point","verdict":"disagree"}],"missed":[{"description":"Sounder beacon FireSafetyCo LLC","qty":3}],"title_block":[{"x":0.83,"y":0.0,"w":0.17,"h":1},{"x":2,"y":0,"w":1,"h":1}]}\n```', KEYS)!;
  assertEquals(r.lines.map((v) => v.key), ['boq_smoke_detector', 'boq_heat_detector']);   // unknown key and a valueless disagree dropped
  assertEquals(r.title_block.length, 1);                                                   // an out-of-page box dropped
  // A line naming a company is scrubbed by scrubIdentity, which takes the whole "<words> LLC" phrase:
  // here nothing is left, so the line is dropped rather than shown. Never leaked either way.
  assert(r.missed.every((m) => !/llc|firesafetyco/i.test(m.description)));
});

Deno.test('agree confirms, disagree and model-only lines stay open for the customer', () => {
  const r = parseConfirm('{"lines":[{"key":"boq_smoke_detector","verdict":"agree"},{"key":"boq_heat_detector","verdict":"disagree","value":4},{"key":"boq_manual_call_point","verdict":"cannot_tell"}],"missed":[{"description":"Wall sounder beacon","qty":3,"unit":"nos"}]}', KEYS);
  const m = mergeConfirm(DRAFT, r);
  assertEquals(m.lines[0].qty, 8); assertEquals(m.lines[0].qty_status, 'check_confirmed'); assert(!isOpen(m.lines[0]));
  assert(isOpen(m.lines[1]) && /second reading counted 4/.test(m.lines[1].basis || ''));
  assert(isOpen(m.lines[2]));
  assertEquals(m.lines[3].estimate, 3); assert(isOpen(m.lines[3]));
  assertEquals([m.status, m.disagreements, m.model_only], ['partly_confirmed', 1, 1]);
});

Deno.test('no reply: the coded result stands, marked unconfirmed', () => {
  const m = mergeConfirm(DRAFT, null);
  assertEquals(m.status, 'unconfirmed');
  assert(m.lines.every((l) => l.qty === null && /not confirmed by a second reading/.test(l.basis || '')));
  assert(confirmUserText(DRAFT).includes('boq_manual_call_point | Manual call point (break glass) | 23 nos'));
});
