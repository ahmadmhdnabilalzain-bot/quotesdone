// cross_check.test — the model's reading of a PDF set is cross-checked by code's complete count (3 Nov 2026).
//   deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/drawing_boq/cross_check.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { crossCheck, crossCheckNotes, mergeReading, setIdentityTerms } from './cross_check.ts';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import { seedTerms } from '../_shared/anonymise.ts';
import { setBeforeModel } from './drawing_set.ts';
import { zzPdfSet, zzPdfSheet, PDF_COUNTS } from '../_shared/doc_read/zz_demo_drawings.fixtures.ts';

// The 27 Oct 2026 failure, replayed: the model doubled EF-1 and missed WC/L-1 on a set code read exactly.
const code = [
  { item: 'EF-1 Exhaust fan', description: 'EF-1 — Exhaust fan', qty: 1, unit: 'nos', type: 'tag:EF-1' },
  { item: 'RTU-1 Rooftop unit', description: 'RTU-1 — Rooftop unit', qty: 1, unit: 'nos', type: 'tag:RTU-1' },
  { item: 'WC/L-1 Wall cap', description: 'WC/L-1 — Wall cap', qty: 1, unit: 'nos', type: 'tag:WC/L-1:new' },
];
const model = [
  { section: 'HVAC', description: 'EF-1 exhaust fan', qty: 2, unit: 'nos' },
  { section: 'HVAC', description: 'RTU 1 rooftop unit', qty: 1, unit: 'nos' },
  { section: 'Ceiling', description: 'Suspended ceiling, ground floor', qty: 120, unit: 'sqm' },
];

Deno.test('agreement is confirmed, disagreement keeps the tag count and is flagged, model-only scope is an estimate', () => {
  const x = crossCheck(model, code);
  const by = (t: string) => x.boq.find((l) => l.type === t)!;
  assertEquals(by('tag:RTU-1').cross_check, { by: 'model', model_qty: 1, agrees: true });
  assertEquals(by('tag:EF-1').qty, 1, 'the printed-tag count stays the quantity');
  assertEquals(by('tag:EF-1').qty_status, 'to_confirm', 'a disagreement is asked, never waved through');
  assertEquals(by('tag:EF-1').cross_check.model_qty, 2);
  assertEquals(by('tag:WC/L-1:new').cross_check.agrees, null, 'the model did not list it: kept, marked');
  const ceiling = x.boq.find((l) => /ceiling/i.test(l.description))!;
  assertEquals([ceiling.qty_status, ceiling.estimate], ['to_confirm', 120], "the model's own scope is an estimate to confirm");
  assertEquals([x.agreed, x.disagreed.length, x.code_only, x.model_only], [1, 1, ['WC/L-1'], 1]);
  assertEquals(crossCheckNotes(x).length, 3);
});

Deno.test('a tag is matched as a whole token: FD-1 is not FD-10', () => {
  const x = crossCheck([{ description: 'FD-10 floor drain', qty: 7 }], [{ description: 'FD-1 — Floor drain', qty: 7, type: 'tag:FD-1:new' }]);
  assertEquals(x.boq.find((l) => l.type)!.cross_check.agrees, null);
  assertEquals(x.model_only, 1);
});

Deno.test('on the journey fixture, a model that reads the sheet right is confirmed line by line and nothing is lost', async () => {
  const set = setBeforeModel(await pdfPages(zzPdfSheet(), undefined, { layers: false }))!;
  assert(set, 'the ZZ DEMO plumbing + HVAC sheet must be counted completely by code');
  const right = [{ description: 'FD-1 - floor drain', qty: 7, unit: 'nos' }, { description: 'WC-1 - water closet', qty: 5, unit: 'nos' },
    { description: 'FCU-1 - fan coil unit', qty: 1, unit: 'nos' }, { description: 'FCU-2 - fan coil unit', qty: 1, unit: 'nos' }, { description: 'FCU-3 - fan coil unit', qty: 1, unit: 'nos' }];
  const x = crossCheck(right, set.boq);
  assertEquals([x.agreed, x.disagreed, x.model_only], [5, [], 0]);
  const sum = (re: RegExp) => x.boq.filter((l) => re.test(String(l.description))).reduce((a, l) => a + Number(l.qty), 0);
  assertEquals([sum(/FD-1/), sum(/WC-1/), sum(/FCU-\d/)], [PDF_COUNTS['FD-1'], PDF_COUNTS['WC-1'], PDF_COUNTS.FCU]);
});

Deno.test('drawing_boq merges the coded set into the model reading instead of answering before the model', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const model = src.indexOf('const payload = { __secret: key, fn: \'drawing_boq\'');
  const merge = src.indexOf('const g = mergeReading(ai, codeSet, idTerms);');
  assert(model > 0 && merge > model, 'the cross-check must run on the model reading, after the model call');
  assert(/idTerms = setIdentityTerms\(pages\)/.test(src), 'the merged take-off is gated on every page and the title strip, not on the model\'s 12k copy');
  assert(/if \(g\.boq\) return J\([^\n]*\n\s*\/\/[^\n]*\n\s*console\.warn\([^\n]*g\.found\.map\(\(f\) => \(f\.startsWith\('seed:'\) \? 'seed' : f\)\)[^\n]*\n\s*return codeAnswer\(\);/.test(src),
    'a reading not merged is said (never a seed by value: it is the party\'s name), and the coded set answers');
  // 10 Nov 2026: the terms are read for every PDF (the model's reading alone is gated with them too), still before the set is kept.
  assert(/idTerms = setIdentityTerms\(pages\);\n\s*if \(set\) codeSet = set;/.test(src), 'a coded set is never kept without its identity terms');
  assert(/if \(codeSet && !key\) return codeAnswer\(\);/.test(src) && /ok === false\) \{ if \(codeSet\) return codeAnswer\(\);/.test(src), 'without the model the coded set still answers');
});

// ── independent review of #1837 (3 Nov 2026) ─────────────────────────────────────────────────────────────────────────
// What index.ts makes of a reply that is prose ("I cannot read this drawing") or JSON cut off mid-line: parseJson gives {}
// and the normalisation leaves exactly this. Merged as it was, it blanked the coded set's summary and signed it 'low'.
const unread = { boq: [], summary: '', drawing_type: '', scale_detected: '', category: '', total_area_sqm: null, keywords: [], assumptions: [], missing_info: [], confidence: 'low', author_model: 'some/model' };

Deno.test('a prose, truncated or empty model reply on a countable set leaves the code answer unchanged', async () => {
  const pages = await pdfPages(zzPdfSheet(), undefined, { layers: false });
  const set = setBeforeModel(pages)!;
  const g = mergeReading(unread, set, setIdentityTerms(pages));
  assertEquals(g.boq, null, 'no line from the model = the coded set answers alone (index.ts codeAnswer)');
  assertEquals(mergeReading({ ...unread, boq: undefined }, set, []).boq, null);
});

Deno.test("a model that gives lines but no summary keeps the coded set's summary, drawing type and scale", async () => {
  const pages = await pdfPages(zzPdfSheet(), undefined, { layers: false });
  const set = { ...setBeforeModel(pages)!, summary: 'Plumbing and HVAC fixtures, ground floor' };
  const g = mergeReading({ ...unread, boq: [{ description: 'FD-1 - floor drain', qty: 7, unit: 'nos' }] }, set, setIdentityTerms(pages));
  assert(g.boq, 'a clean merge answers');
  assertEquals([g.boq.summary, g.boq.drawing_type, g.boq.scale_detected], [set.summary, set.drawing_type, set.scale_detected]);
  assertEquals(g.boq.author_model, 'some/model', 'lines the model read carry its name');
});

Deno.test("the merged take-off is gated on every page and the title strip: a model summary naming the title-block party is removed whole", async () => {
  const pages = await pdfPages(zzPdfSet(), undefined, { layers: false });
  const set = setBeforeModel(pages)!;
  const terms = setIdentityTerms(pages);
  // The 12k space-joined copy lost the drafter and made "consulting" a seed (measured on zzPdfSet); every page does not.
  // Asserted on the SEEDS the gate builds (seedTerms splits each term into words), not on the terms list.
  const seeds = seedTerms({ extra: terms });
  assert(seeds.includes('drafter'), 'the drafter printed in the strip is a seed');
  for (const w of ['consulting', 'client', 'drawn', 'invalid']) assert(!seeds.includes(w), `"${w}" is a label or a common word, not a party`);
  const line = { section: 'Plumbing', description: 'FD-1 - floor drain', qty: 7, unit: 'nos' };
  for (const party of ['ZZ DEMO ORBIT CONSULTING ENGINEERS LLC', 'ZZ Demo Drafter', 'ZZ DEMO Harbour Tower']) {
    const g = mergeReading({ ...unread, boq: [line], summary: `Ground floor plumbing by ${party}` }, set, terms);
    // Measured with the old terms: "by ZZ DEMO █ █", "by ZZ Demo Drafter" (untouched), "by ZZ DEMO █ Tower".
    assertEquals(g.boq?.summary, 'Ground floor plumbing by █', `"${party}" must be redacted as one name, not word by word`);
    assertEquals([g.dropped_lines, g.boq?.boq.length], [0, set.boq.length], 'every clean coded line stays');
  }
});

Deno.test('when the model agrees, every coded line leaves the gate byte-identical (no label word is a seed)', async () => {
  for (const pdf of [zzPdfSet, zzPdfSheet]) {
    const pages = await pdfPages(pdf(), undefined, { layers: false });
    const set = setBeforeModel(pages)!;
    const agree = set.boq.map((l: any) => ({ description: l.description, qty: l.qty, unit: l.unit }));
    const g = mergeReading({ ...unread, boq: agree, summary: 'the client confirms the layout; or approved equal' }, set, setIdentityTerms(pages));
    assert(g.boq, 'a clean agreeing merge answers');
    const pick = (l: any) => ({ item: l.item, description: l.description, basis: l.basis, section: l.section, qty: l.qty });
    assertEquals(g.boq.boq.map(pick), set.boq.map(pick), 'measured before this fix: "tag FD-1 drawn 7x" became "tag FD-1 █ 7x"');
    assertEquals(g.boq.summary, 'the client confirms the layout; or approved equal');
  }
});
