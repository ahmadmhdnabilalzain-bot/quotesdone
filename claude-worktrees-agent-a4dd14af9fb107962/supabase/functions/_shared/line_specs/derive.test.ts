// line_specs/derive.test.ts — the auditor's own form text (21 Sep 2026, finding 15) reaches the columns.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { deriveLineFields, deriveTermsFromScope } from './derive.ts';

Deno.test('"Brand: Jotun – Product: Fenomastic" on a line fills brand and model; a filled column is kept', () => {
  assertEquals(deriveLineFields({ description: 'Internal walls, Brand: Jotun – Product: Fenomastic Emulsion, 2 coats' }), { brand: 'Jotun', model: 'Fenomastic Emulsion' });
  assertEquals(deriveLineFields({ description: 'Brand: Jotun', brand: 'Dulux' }), {});
  assertEquals(deriveLineFields({ description: 'Ceiling painting, brand: equivalent' }), {});
  assertEquals(deriveLineFields({ description: 'الماركة: جوتن، الموديل: فينوماستك' }), { brand: 'جوتن', model: 'فينوماستك' });
});

Deno.test('"Installation included … Exclusions: …" in the scope gives the exclusions and says installation is included', () => {
  const r = deriveTermsFromScope('Supply and apply two coats to all walls. Installation included, 5 working days. Exclusions: ceilings and external walls.', '');
  assertEquals(r, { installation_included: true, exclusions: 'ceilings and external walls' });
  const s = deriveTermsFromScope('Supply only.', 'scaffolding');
  assert(!s.installation_included); assertEquals(s.exclusions, undefined);
});
