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
});
