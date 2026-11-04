// teardown_supplier_documents.test.mjs — a run's supplier-downloaded PDFs are removed by teardown (3 Nov 2026).
// node --test scripts/lib/teardown_supplier_documents.test.mjs
//
// THE FAILURE IT REPLAYS: nightly journey run 41598217377 (drawings step) — "none of the run's drawing files or BOQ PDFs
// is left in storage - 1 of 11 named objects remain". The object was agent-docs/supplier/154196/<ts>_QD-163059-RFQ-
// v2.3-inquiry-en.pdf: pdf_native files a supplier's documents under supplier/<lead id>/ and only
// supplier_document_cache names them, and teardown's agent-docs rule knew only the comparison PDF's file name.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BUCKET_SOURCES } from './demo_factory.mjs';

test("teardown's agent-docs rule takes the run's supplier folder and every cached supplier document", () => {
  const s = { lead: 'company_name like \'ZZ DEMO tag%\'', inq: 'false', quote: 'false', cust: 'false', redaction: 'false' };
  const src = BUCKET_SOURCES(s).filter((b) => b.bucket === 'agent-docs').map((b) => b.sql).join('\n');
  assert.match(src, /'supplier\/' \|\| l\.id::text \|\| '\/%'/, 'the supplier/<lead id>/ folder');
  assert.match(src, /supplier_document_cache/, 'the cache rows that name each document');
  assert.ok(src.includes(s.lead), 'scoped to the run\'s own leads only');
});
