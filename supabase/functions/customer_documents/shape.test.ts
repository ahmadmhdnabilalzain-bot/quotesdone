// shape.test.ts — audit finding 11 (21 Sep 2026): the vault's row and answer, without a database.
//
//   deno test supabase/functions/customer_documents/shape.test.ts
//
// The rows below are what fn_customer_documents returns AFTER
// scripts/sql/the_customer_vault_lists_the_quote_pdf_and_reads_the_quotes_warranty.sql: the
// standardised quote PDF registered from quote_pdf_cache (bucket agent-docs, kind quote), and a
// quote document whose coverage comes from quotes.warranty. Whether the routine itself returns
// them is proved by that file's own probe at apply time; this test proves what the edge function
// does with them.
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { answerLine, shape, SOURCE_WORDS, sourceKind, type Doc } from './shape.ts';

const base: Doc = {
  id: 1, kind: 'quote', file_name: 'quotation-final.csv', bucket: 'quotes', path: 'x/quotation-final.csv',
  mime: 'text/csv', status: 'done', created_at: '2026-09-18T00:00:00Z', source: 'quote',
  ref_table: 'quotes', ref_id: 'q1', supplier: 'ZZ DEMO Interiors gypsum', supplier_revealed: true,
  expiry_date: null, expiry_source: null, covers: '2 years materials and workmanship', covers_source: 'quotes.warranty',
  summary: null, specifications: [], certifications: [], brands: [], extracted_at: '2026-09-18T00:01:00Z',
  match_reason: 'text', score: 0.5,
};

const INTERNAL = /\b(leads|quotes|extracted|documents)\.[a-z_]+/i;

Deno.test('the standardised quote PDF from quote_pdf_cache shapes as a quote document', () => {
  const pdf = shape({ ...base, id: 2, kind: 'quote', bucket: 'agent-docs',
    path: '2026-09-21/1789983012525_QD-8B287960-A-quotation-en.pdf',
    file_name: 'QD-8B287960-A-quotation-en.pdf', mime: 'application/pdf' });
  assertEquals(pdf.kind, 'quote');
  assertEquals(pdf.source, 'quote');
  assertEquals(pdf.file_name, 'QD-8B287960-A-quotation-en.pdf');
  assertEquals(pdf.covers, '2 years materials and workmanship');
  assertEquals(pdf.covers_source, 'quotation');
});

Deno.test('the warranty answer reads quotes.warranty ("2 years") when present, in EN and AR', () => {
  const row = shape(base);
  const en = answerLine(row, 'en');
  assertStringIncludes(en, 'covers 2 years materials and workmanship');
  assertStringIncludes(en, 'per the quotation');
  assert(!en.includes('no warranty or coverage stated'));
  const ar = answerLine(row, 'ar');
  assertStringIncludes(ar, 'يغطي 2 years materials and workmanship');
  assertStringIncludes(ar, 'بحسب عرض السعر');
});

Deno.test('a quote with no warranty is reported as none, never invented', () => {
  const en = answerLine(shape({ ...base, covers: null, covers_source: null }), 'en');
  assertStringIncludes(en, 'no warranty or coverage stated');
  assertStringIncludes(en, 'no expiry stated');
});

Deno.test('no internal column name reaches a user-facing string', () => {
  assertEquals(sourceKind('leads.license_expiry'), 'supplier_record');
  assertEquals(sourceKind('extracted.covers'), 'document');
  assertEquals(sourceKind('quotes.warranty'), 'quotation');
  assertEquals(sourceKind(null), null);
  const licence = shape({ ...base, id: 3, kind: 'licence', source: 'supplier', ref_table: 'leads', ref_id: '7',
    expiry_date: '2027-09-18', expiry_source: 'leads.license_expiry',
    covers: 'Gypsum works', covers_source: 'leads.license_activity' });
  for (const v of [licence.expiry_source, licence.covers_source]) assert(v && !INTERNAL.test(v), `internal key leaked: ${v}`);
  for (const lang of ['en', 'ar'] as const) {
    const line = answerLine(licence, lang);
    assert(!INTERNAL.test(line), `internal key leaked into the ${lang} answer: ${line}`);
    for (const w of Object.values(SOURCE_WORDS[lang])) assert(!INTERNAL.test(w), w);
  }
  assertStringIncludes(answerLine(licence, 'en'), "per the supplier's verified record");
});
