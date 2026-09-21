// THE MEANING LAYER'S RULES, on hand-made vectors (no model, no network). What gte-small itself does with
// real lines is proved against the live model by scripts/checks/a_catalogue_line_is_understood_by_meaning.test.mjs.
//   deno test -A supabase/functions/_shared/service_meaning.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { headWords, MEANING_FLOOR, parseVec, proposeByMeaning, TWO_LINE_FLOOR, type MeaningService } from './service_meaning.ts';

// Unit vectors on a few axes: cos(a, b) is exactly what the test says it is.
const v = (...xs: number[]) => { const n = Math.hypot(...xs); return xs.map((x) => x / n); };
const at = (sim: number) => v(sim, Math.sqrt(1 - sim * sim), 0, 0);   // cos with [1,0,0,0] = sim
const svc = (trade_code: string, code: string, label_en: string, vec: number[], aliases: string[] = []): MeaningService =>
  ({ trade_code, code, label_en, label_ar: 'خدمة', aliases, vec });
const COPIERS = svc('office_equipment', 'photocopiers', 'Photocopiers & copiers', [1, 0, 0, 0], ['photocopier', 'copier']);
const TRAYS = svc('electrical', 'cable_tray', 'Cable trays & containment', [1, 0, 0, 0], ['cable tray']);
const SERVICING = svc('office_equipment', 'printer_service', 'Printer & copier servicing', [1, 0, 0, 0]);

Deno.test('head words are what the service IS', () => {
  assertEquals(headWords('Photocopiers & copiers'), ['photocopier', 'copier']);
  assertEquals(headWords('Cable trays & containment'), ['tray', 'containment']);
  assertEquals(headWords('Office machines (shredders, laminators, binders)'), ['machine', 'shredder', 'laminator', 'binder']);
  assertEquals(headWords('Hardware supply'), ['hardware']);
  assertEquals(headWords('UPS systems'), ['ups']);
});

Deno.test('a line whose words hold the head of the nearest service is proposed, with the line as the reason', () => {
  const p = proposeByMeaning([{ text: 'we distribute office printers and copiers', vec: at(0.90) }], [COPIERS]);
  assertEquals(p.map((x) => [x.key, x.because, x.word]), [['office_equipment.photocopiers', 'head_word', 'copier']]);
  assertEquals(p[0].lines, ['we distribute office printers and copiers']);
});

Deno.test('a nearest neighbour alone is never accepted', () => {
  assertEquals(proposeByMeaning([{ text: 'Gold partner', vec: at(0.95) }], [COPIERS]), []);
  // A shared word that is not the head ("cable" is not "cable trays") is not corroboration either.
  assertEquals(proposeByMeaning([{ text: 'Cables', vec: at(0.95) }], [TRAYS]), []);
});

Deno.test('below the floor nothing is proposed, whatever words it shares', () => {
  assertEquals(proposeByMeaning([{ text: 'copiers', vec: at(MEANING_FLOOR - 0.01) }], [COPIERS]), []);
});

Deno.test('two separate lines agreeing are corroboration only above the stricter floor', () => {
  const lines = (s: number) => [{ text: 'first line about office kit', vec: at(s) }, { text: 'another unrelated wording', vec: at(s) }];
  assertEquals(proposeByMeaning(lines(TWO_LINE_FLOOR - 0.01), [COPIERS]), []);
  assertEquals(proposeByMeaning(lines(TWO_LINE_FLOOR + 0.01), [COPIERS]).map((x) => x.because), ['two_lines']);
});

Deno.test('installation work is a candidate only for a line that speaks of that work, and never for a supplier of goods', () => {
  // SERVICING is exactly as near as COPIERS; without a work word it is not even a candidate.
  assertEquals(proposeByMeaning([{ text: 'we distribute printers and copiers', vec: at(0.9) }], [SERVICING, COPIERS]).map((x) => x.key), ['office_equipment.photocopiers']);
  assertEquals(proposeByMeaning([{ text: 'we repair printers and copiers', vec: at(0.9) }], [SERVICING]).map((x) => x.key), ['office_equipment.printer_service']);
  assertEquals(proposeByMeaning([{ text: 'we repair printers and copiers', vec: at(0.9) }], [SERVICING], { supplyOnly: true }), []);
});

Deno.test('what the word rules already found is not proposed again; a pgvector string parses', () => {
  assertEquals(proposeByMeaning([{ text: 'copiers', vec: at(0.9) }], [COPIERS], { stated: ['office_equipment.photocopiers'] }), []);
  assertEquals(parseVec('[0.5,-0.25]'), [0.5, -0.25]);
  assertEquals(parseVec(null), null);
  assert(parseVec('not a vector') === null);
});
