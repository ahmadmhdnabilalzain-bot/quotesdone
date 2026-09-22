// The nightly's "Arabic quotation is not the English file" step compares real bytes (22 Sep 2026, sales_engineer).
//
// WHY THIS EXISTS. Run 35671806988 (00:40Z) FAILED "the Arabic quotation is not the English file" in
// the same minute it read the English quotation as 3 pages / 0% Arabic and the Arabic one as 2 pages /
// 79% Arabic. The product was right. pdfjs-dist 4.x transfers the buffer it parses to its worker, so
// the Uint8Array the journey kept as `bytes` was detached (1,475 bytes before getDocument, 0 after,
// measured on the fixture below), and the step compared two empty buffers — always equal.
// This replays that input: it fails if the reader hands the caller's buffer to pdfjs again, if an
// empty side is ever called "the same file", or if journey h stops using the reader's comparison.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = process.cwd();
const { pdfFactsFromBytes, sameDocument, languageOf } = await import(pathToFileURL(join(ROOT, 'scripts/e2e/pdf_facts.mjs')).href);
const QUOTE = readFileSync(join(ROOT, 'supabase/functions/supplier_api/fixtures/ZZDEMO_quotation_D958E1EA.pdf'));
const OTHER = readFileSync(join(ROOT, 'supabase/functions/_shared/catalogue_fixtures/zz_demo_it_wholesaler_catalogue.pdf'));

test('reading a PDF leaves its bytes intact, for the caller and in the result', async () => {
  const mine = new Uint8Array(QUOTE);
  const f = await pdfFactsFromBytes(mine);
  assert.equal(f.ok, true);
  assert.equal(mine.length, QUOTE.length, 'the caller\'s buffer was detached by the parser');
  assert.equal(f.bytes.length, QUOTE.length, 'the facts carry an emptied buffer — the 22 Sep defect');
});

test('two different PDFs are different, the same PDF twice is the same', async () => {
  const a = await pdfFactsFromBytes(new Uint8Array(QUOTE));
  const a2 = await pdfFactsFromBytes(new Uint8Array(QUOTE));
  const b = await pdfFactsFromBytes(new Uint8Array(OTHER));
  assert.deepEqual([sameDocument(a, b).comparable, sameDocument(a, b).same], [true, false]);
  assert.deepEqual([sameDocument(a, a2).comparable, sameDocument(a, a2).same], [true, true],
    'the same file served twice (the real defect: lang ignored, one cached file) must read as the same');
});

test('an empty or unread side is not comparable, never "the same file"', async () => {
  const a = await pdfFactsFromBytes(new Uint8Array(QUOTE));
  const empty = { ...a, bytes: new Uint8Array(0) };
  assert.equal(sameDocument(a, empty).comparable, false);
  assert.equal(sameDocument(empty, empty).comparable, false);
  assert.equal(sameDocument(a, { ok: false, why: 'HTTP 500' }).comparable, false);
});

test('the language reading: Arabic presentation forms count as Arabic', () => {
  assert.equal(languageOf({ arabicShare: 0.79 }), 'ar');
  assert.equal(languageOf({ arabicShare: 0 }), 'en');
});

test('journey h decides the step with sameDocument and the Arabic language, not a raw buffer compare', () => {
  const src = readFileSync(join(ROOT, 'scripts/e2e/journey_audit_buttons.mjs'), 'utf8');
  const at = src.indexOf("'the Arabic quotation is not the English file'");
  assert.notEqual(at, -1, 'the step is gone from journey h');
  const block = src.slice(src.lastIndexOf('const d = sameDocument(pdfs.en, pdfs.ar)', at), at + 400);
  assert.match(block, /sameDocument\(pdfs\.en, pdfs\.ar\)/);
  assert.match(block, /languageOf\(pdfs\.ar\) === 'ar'/);
  assert.doesNotMatch(block, /Buffer\.compare/);
});
