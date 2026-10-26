// supplier_doc_trades — a supplier's document is read by code and its trades come back with evidence.
// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/supplier_doc_trades.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { mergeEvidence, proposedFrom, readDocForTrades, tradesFromText, type DocEvidence } from './supplier_doc_trades.ts';
import { makeDrawingPdf } from './pdf_measure.fixtures.ts';

// A slice of production taxonomy_trade (read 15 Sep 2026), aliases verbatim.
const VOCAB = [
  { code: 'hvac', aliases: ['hvac', 'air conditioning', 'air-conditioning', 'chiller', 'ducting', 'ventilation'] },
  { code: 'plumbing', aliases: ['plumbing', 'plumber', 'sanitary', 'drainage', 'pipework'] },
  { code: 'building_materials', aliases: ['building material', 'building materials', 'cement', 'ready mix'] },
  { code: 'aluminium', aliases: ['aluminium', 'aluminum', 'cladding', 'facade', 'curtain wall'] },
  { code: 'electrical', aliases: ['electrical', 'electric', 'wiring', 'switchgear'] },
  { code: 'packaging', aliases: ['packaging company', 'packaging material', 'corrugated'] },
];
const codes = (h: { code: string }[]) => h.map((x) => x.code).sort();

Deno.test('mirrors fn_norm_trades: hyphens are spaces, word-start anchored, open-ended', () => {
  const hits = tradesFromText('ZZ DEMO Trading LLC\nWe supply building-materials and Aluminum Cladding.\nPrehvac is not a word here.', VOCAB);
  // 'building-materials' becomes 'building materials' before matching, as in the SQL.
  assertEquals(codes(hits), ['aluminium', 'building_materials']);
  // 'hvac' inside 'Prehvac' is not at a word start, so it is not a trade.
  assert(!hits.some((h) => h.code === 'hvac'));
  // Open-ended like '\m': 'electricity' starts with the alias 'electric'.
  assertEquals(codes(tradesFromText('Electricity works', VOCAB)), ['electrical']);
});

Deno.test('the evidence is the phrase and the line it was found on', () => {
  const [h] = tradesFromText('About us\nActivities: Plumbing works and drainage maintenance\nContact', VOCAB);
  assertEquals(h.code, 'plumbing');
  assertEquals(h.phrases, ['plumbing', 'drainage']);
  assertEquals(h.snippet, 'Activities: Plumbing works and drainage maintenance');
});

Deno.test('exact or none: a near word is not a trade', () => {
  assertEquals(tradesFromText('We sell cardboard boxes and pack goods.', VOCAB), []);
  assertEquals(tradesFromText('', VOCAB), []);
});

Deno.test('a PDF with a text layer is read by code and proposes its trades', async () => {
  const pdf = makeDrawingPdf(['ZZ DEMO COMPANY PROFILE', 'Air conditioning and chiller maintenance', 'Plumbing and drainage'], '');
  const ev = await readDocForTrades({ path: 'profiles/1/p.pdf', name: 'p.pdf', kind: 'profile', bytes: pdf, mime: 'application/pdf' }, VOCAB);
  assertEquals(ev.status, 'read');
  assertEquals(ev.format, 'pdf');
  assertEquals(codes(ev.trades), ['hvac', 'plumbing']);
  assert(ev.trades.find((t) => t.code === 'hvac')!.snippet.toLowerCase().includes('air conditioning'));
});

Deno.test('a scan with no text layer is needs_ocr, never a false zero', async () => {
  const scan = makeDrawingPdf([], '0.7 w 100 100 141.73 113.39 re S');
  const ev = await readDocForTrades({ path: 'catalogs/1/s.pdf', name: 's.pdf', kind: 'catalogue', bytes: scan, mime: 'application/pdf' }, VOCAB);
  assertEquals(ev.status, 'needs_ocr');
  assertEquals(ev.trades, []);
});

Deno.test('a refused file is unreadable with the reason', async () => {
  const html = new TextEncoder().encode('<html><script>alert(1)</script></html>');
  const ev = await readDocForTrades({ path: 'catalogs/1/x.pdf', name: 'x.pdf', kind: 'catalogue', bytes: html, mime: 'application/pdf' }, VOCAB);
  assertEquals(ev.status, 'unreadable');
  assert(ev.reason && ev.reason.length > 0);
});

Deno.test('a new licence replaces the old one; catalogues accumulate; proposal is the union', () => {
  const e = (path: string, kind: DocEvidence['kind'], c: string[]): DocEvidence =>
    ({ path, name: path, kind, status: 'read', read_at: 'x', trades: c.map((code) => ({ code, phrases: [code], snippet: code })) });
  const prev = [e('licenses/1/a.pdf', 'licence', ['plumbing']), e('catalogs/1/c1.pdf', 'catalogue', ['hvac'])];
  const merged = mergeEvidence(prev, [e('licenses/1/b.pdf', 'licence', ['electrical']), e('catalogs/1/c2.pdf', 'catalogue', ['aluminium'])]);
  assertEquals(merged.map((d) => d.path).sort(), ['catalogs/1/c1.pdf', 'catalogs/1/c2.pdf', 'licenses/1/b.pdf']);
  assertEquals(proposedFrom(merged), ['aluminium', 'electrical', 'hvac']);
});
