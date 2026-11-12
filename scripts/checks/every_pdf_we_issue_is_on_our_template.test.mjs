// Runs every_pdf_we_issue_is_on_our_template.mjs inside npm test, and proves it can fail.
import test from 'node:test';
import assert from 'node:assert/strict';
import { findingsFor, scan } from './every_pdf_we_issue_is_on_our_template.mjs';

test('no code path hands a person a PDF that is not on the QuotesDone template', () => {
  assert.deepEqual(scan(), []);
});

test('the check catches each shape, and a comment describing it does not trip it', () => {
  const fn = 'supabase/functions/zz_demo/index.ts';
  assert.equal(findingsFor(fn, "const u = inv.hosted_invoice_url; return J({ url: u });").length, 1);
  assert.equal(findingsFor(fn, "const u = j?.invoice_pdf;").length, 1);
  assert.equal(findingsFor(fn, "const u = o['receipt_url'];").length, 1);
  assert.equal(findingsFor(fn, "import { PDFDocument } from 'https://esm.sh/pdf-lib@1.17.1'; await PDFDocument.create();").length, 2);
  assert.equal(findingsFor(fn, "return new Response(b, { headers: { 'Content-Type': 'application/pdf' } });").length, 1);
  assert.equal(findingsFor('src/components/zz.tsx', "<a href={'https://invoice.stripe.com/i/' + id}>").length, 1);
  // Prose and the allowed homes do not count.
  assert.equal(findingsFor(fn, "// the old code read j.invoice_pdf and returned it\nconst x = 1;").length, 0);
  assert.equal(findingsFor(fn, "/* inv.hosted_invoice_url was served here */ const x = 1;").length, 0);
  assert.equal(findingsFor('supabase/functions/stripe_webhook/index.ts', "const pdfUrl = String(inv.invoice_pdf || '');").length, 0);
  assert.equal(findingsFor('supabase/functions/pdf_native/render.ts', "const pdf = await PDFDocument.create();").length, 0);
  assert.equal(findingsFor(fn, "await fetch(URL + '/functions/v1/pdf_native', { body })").length, 0);
  // The customer's-drawing editor may load and save that drawing, and nothing more.
  const red = 'supabase/functions/_shared/pdf_vector_redact.ts';
  assert.equal(findingsFor(red, "import { PDFDocument } from 'https://esm.sh/pdf-lib@1.17.1'; await PDFDocument.load(b);").length, 0);
  assert.equal(findingsFor(red, "await PDFDocument.create();").length, 1);
  assert.equal(findingsFor(red, "return new Response(b, { headers: { 'Content-Type': 'application/pdf' } });").length, 1);
  assert.equal(findingsFor('supabase/functions/_shared/scan_takeoff.ts', "import { PDFDocument } from 'https://esm.sh/pdf-lib@1.17.1';").length, 1);
  // Review of #1056: every other way to author a PDF there is caught too.
  for (const shape of [
    "await PDFDocument['create']();",
    'await PDFDocument[`create`]();',
    "import { PDFDocument as D } from 'https://esm.sh/pdf-lib@1.17.1'; await D.load(b);",
    'const D = PDFDocument;\nawait D.load(b);',
    'const { create } = PDFDocument; await create();',
    'const p = doc.addPage([10, 10]);',
    "page.drawText('x', { x: 1, y: 1 });",
    'const f = await doc.embedFont(StandardFonts.Helvetica);',
    'const D = PDFDocument, X = 1;\nawait D.load(b);',
    'let n = 0, D = PDFDocument;',
    'const [p] = await doc.copyPages(src, [0]);',
  ]) assert.equal(findingsFor(red, shape).length, 1, shape);
  // What the editor really does is not flagged: load, read the pages, save.
  assert.equal(findingsFor(red, "const doc = await PDFDocument.load(bytes, { updateMetadata: false }); const pl = doc.getPages(); const out = await doc.save({ useObjectStreams: false });").length, 0);
  // Review of #1796: a dynamic import() of the library is caught like a static one, anywhere but the two editors.
  assert.equal(findingsFor(fn, "const { PDFDocument } = await import('https://esm.sh/pdf-lib@1.17.1');").length, 1);
  assert.equal(findingsFor(fn, 'const m = await import(`npm:jspdf`);').length, 1);
  // The profile cutter may load, remove pages and save the supplier's own PDF, and nothing more.
  const cut = 'supabase/functions/_shared/supplier_docs_later.ts';
  assert.equal(findingsFor(cut, "const { PDFDocument } = await import('https://esm.sh/pdf-lib@1.17.1'); const doc = await PDFDocument.load(b); doc.removePage(11); await doc.save();").length, 0);
  assert.equal(findingsFor(cut, "const out = await PDFDocument.create();").length, 1);
  assert.equal(findingsFor(cut, 'const [p] = await out.copyPages(src, [0]);').length, 1);
  assert.equal(findingsFor(cut, "return new Response(b, { headers: { 'Content-Type': 'application/pdf' } });").length, 1);
});

// 22 Sep 2026 (audit finding 2): supplier_pay turned invoice_creation on for both supplier checkouts, so a
// supplier's only document for a payment was Stripe's. E replays that input.
test('E: Stripe is never asked to make or send a document a person receives as ours', () => {
  const pay = 'supabase/functions/supplier_pay/index.ts';
  assert.equal(findingsFor(pay, "f.set('invoice_creation[enabled]', 'true');").length, 1);
  assert.equal(findingsFor('supabase/functions/stripe_checkout/index.ts', "form.set('invoice_creation[enabled]', 'true');").length, 0);
  assert.equal(findingsFor(pay, "form.set('payment_intent_data[receipt_email]', e);").length, 1);
  assert.equal(findingsFor(pay, "await stripe('invoices/' + id + '/send', new URLSearchParams());").length, 1);
  assert.equal(findingsFor('supabase/functions/zz/index.ts', "attachments: [{ bucket: 'finance-docs', path: 'invoices/stripe/' + p }]").length, 1);
  assert.equal(findingsFor('supabase/functions/stripe_webhook/index.ts', "const path = 'invoices/stripe/' + day;").length, 0);
  // reading who a receipt went to is not asking Stripe to send one
  assert.equal(findingsFor('supabase/functions/_shared/it_duty_readings.ts', "const e = x?.charge?.receipt_email ?? null;").length, 0);
  assert.equal(findingsFor(pay, "// we used to set invoice_creation[enabled] here\nconst x = 1;").length, 0);
});

// 12 Nov 2026 (customer_support): a door may answer with a PDF only when renderPdf drew it.
test('a door answering with a PDF passes only when the template renderer drew it', () => {
  const door = 'supabase/functions/my_data_pdf/door.ts';
  const answer = "return new Response(out.bytes, { headers: { 'Content-Type': 'application/pdf' } });";
  assert.equal(findingsFor(door, "import { renderPdf } from '../pdf_native/render.ts';\nconst out = await renderPdf(b, d);\n" + answer).length, 0);
  assert.deepEqual(findingsFor(door, answer), [`${door}: answers with a PDF body outside pdf_native (B)`]);
  assert.ok(findingsFor(door, "import { renderPdf } from '../pdf_native/render.ts';\nimport { PDFDocument } from 'https://esm.sh/pdf-lib@1.17.1';\n" + answer)
    .some((f) => f.endsWith('(B)')), 'a door that also holds a PDF library is not on the template');
  assert.equal(findingsFor(door, "// import { renderPdf } from '../pdf_native/render.ts';\n" + answer).length, 1, 'a comment is not an import');
});
