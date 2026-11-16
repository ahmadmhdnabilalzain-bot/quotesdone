// The investor pack of ledger 1547 holds every template, in one PDF, offline. Seat: accountant (L6_BOOKS), 16 Nov 2026.
// Fails if a document type the page checks prove is left out of the pack, if the drawing reaches the pack unredacted, if
// the expenses statement is missing, or if the contents' page numbers do not land on the document they name.
//   deno test --no-lock --node-modules-dir=none --allow-read=. scripts/investor_pack/every_template_in_one_pdf.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { PDFDocument } from 'https://esm.sh/pdf-lib@1.17.1';
import { buildPack, drawingPair, LISTED, packEntries } from './every_template_in_one_pdf.ts';
import { docs } from '../../supabase/functions/pdf_native/every_document_we_issue.fixtures.ts';
import { verifyPdfRedaction } from '../../supabase/functions/_shared/pdf_vector_redact.ts';
import { seedTerms } from '../../supabase/functions/_shared/anonymise.ts';
import { CUSTOMER, FILE_NAME, IDENTITY, zzPdfSheet } from '../../supabase/functions/_shared/doc_read/zz_demo_drawings.fixtures.ts';

Deno.test('every document the page checks prove is in the pack, plus my data and the emails', async () => {
  const entries = await packEntries();
  assertEquals(entries.length, docs.length + 4 + 4, 'fixtures + 4 "Download my data" + 4 emails');
  for (const want of ['bill of quantities', 'comparison report', 'reveal fee invoice', 'Supplier Agreement', 'Download my data', 'sign-in code'])
    assert(entries.some((e) => e.name.includes(want)), 'missing: ' + want);
  assert(!entries.some((e) => e.section === undefined || e.name === undefined), 'an entry has no section or name');
});

Deno.test('the drawing reaches the pack only after the identity cut', async () => {
  const d = await drawingPair();
  assert(d, 'the ZZ DEMO sheet was held by the redaction');
  const v = await verifyPdfRedaction(zzPdfSheet(), d!.after, seedTerms({ ...CUSTOMER, extra: [FILE_NAME] }), IDENTITY);
  assert(v.ok, v.problems.join('\n'));
});

Deno.test('one PDF: contents, every document, the drawing, the expenses statement and the listed page', async () => {
  const { bytes, rows } = await buildPack();
  const pdf = await PDFDocument.load(bytes);
  const total = pdf.getPageCount();
  const listed = rows.at(-1)!;
  // the last row is the "filled only from live records" page, and it is the last page
  assertEquals(listed[2], 'Templates filled only from live records');
  assertEquals(Number(listed[5]) + Number(listed[4]) - 1, total, 'the contents do not end on the last page');
  // each document starts where the previous one ended
  for (let i = 1; i < rows.length; i++) assertEquals(Number(rows[i][5]), Number(rows[i - 1][5]) + Number(rows[i - 1][4]), `row ${i + 1} page number`);
  assert(rows.some((r) => r[2].startsWith('Operating expenses statement')), 'the expenses statement is not in the pack');
  assert(rows.some((r) => r[2] === 'The same drawing as suppliers receive it'), 'the shared drawing is not in the pack');
  assert(LISTED.length >= 5);
});
