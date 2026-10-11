// EVERY ATTACHMENT IS READ (12 Oct 2026; Assigned: sales_engineer + customer_support, it_engineer for this check).
//
// Founder ruling 1177, verbatim: "it should always read. there is no reason not to unless its extremely bad quality of
// attachment. the same applies to any attachment."
//
// Code first (_shared/doc_read), then the vision model with one more asking (the gateway adds the route's second model),
// and "unreadable" only when both fail — then the uploader is asked for a clearer copy (suppliers in English, customers
// in their inquiry language). _shared/read_every_attachment.ts holds the rule; read_every_attachment.test.ts proves it
// on inputs. THIS check fails the day an upload path stops calling it, or goes back to holding a scan unread.
//
// What fails if that breaks (every row is a path from the inventory in the PR / READ_EVERY_ATTACHMENT_INVENTORY.md):
//   * the helper stops reading code first, stops asking the model, or asks more than twice
//   * a path below stops routing its no-text-layer files to the model, or stops asking for a clearer copy
//   * supporting documents go back to a status doc_extract never reads
//
//   node --test scripts/checks/every_attachment_is_read.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const F = (p) => join(ROOT, 'supabase', 'functions', p);
// Comments are taken out first: a sentence explaining the rule must not satisfy the check (apply-discipline §7).
const code = (p) => readFileSync(F(p), 'utf8').split('\n').map((l) => l.replace(/^\s*\/\/.*$/, '').replace(/\s\/\/\s.*$/, '')).join('\n');

test('the helper reads code first, then the model at most twice, and says unreadable only after both', () => {
  const s = code('_shared/read_every_attachment.ts');
  const iCode = s.indexOf('await readDocument('), iModel = s.indexOf('await vision(');
  assert.ok(iCode > 0 && iModel > iCode, 'readDocument must run before the vision model');
  assert.match(s, /for \(let attempt = 1; attempt <= 2; attempt\+\+\)/, 'one more asking, never a third');
  assert.match(s, /status: 'unreadable', by: null, text: '', kind, model_attempts: 2/, 'unreadable only after two askings');
  assert.match(s, /fn: opts\.fn \|\| 'extract_text'/, 'the existing extract_text route, no new route');
  assert.match(code('_shared/clearer_copy.ts'), /audience === 'customer' && String\(lang/, 'customers are asked in their inquiry language');
});

const PATHS = [
  ['drawing_boq/index.ts', /readEveryAttachment\(b64Bytes\(/, 'a customer photo/scan BOQ with no browser OCR is read by the model'],
  ['customer_api/index.ts', /message: clearerCopyAsk\('customer', documentLocale\(body\.lang, cust\.locale\), name\)/, 'an unreadable customer file asks for a clearer copy in the customer\'s language'],
  ['supplier_api/quote_review_flow.ts', /readEveryAttachment\(bytes, filename, mime, vision\)/, 'a scanned supplier quotation is transcribed and priced by the same parser'],
  ['supplier_api/quote_review_actions.ts', /envGatewayVision\(\{ subject:/, 'the quotation review is given the vision reader'],
  ['quote_extract/index.ts', /\{ const d = await detQuote\(/, 'quote_extract reads the file by code before asking the model'],
  ['quote_extract/index.ts', /for \(let attempt = 1; attempt <= 2; attempt\+\+\)/, 'quote_extract asks once more on an unparseable answer'],
  ['doc_extract/index.ts', /for\(let attempt=1; attempt<=2; attempt\+\+\)/, 'doc_extract asks once more'],
  ['doc_extract/index.ts', /type: 'file', file: \{ filename: \(doc\.file_name \|\| 'doc\.pdf'\)/, 'a scanned PDF goes to the model as a file when the render path fails'],
  ['doc_extract/index.ts', /await readDocument\(new Uint8Array\(await fr\.arrayBuffer\(\)\)/, 'Word/Excel/zip documents are read by code, not skipped'],
  ['accountant/index.ts', /readEveryAttachment\(att\.bytes, att\.name, att\.mime, envGatewayVision\(\)\)/, 'a scanned or photographed receipt is read'],
  ['resend_inbound/index.ts', /readEveryAttachment\(att\.bytes, att\.name, att\.mime, envGatewayVision\(\)\)/, 'an e-mailed receipt scan is read'],
  ['resend_inbound/index.ts', /unreadDocs\.map\(\(n\) => clearerCopyAsk\('supplier', 'en', n\)\)/, 'a supplier e-mailing an unreadable document is asked for a clearer copy'],
  ['inbound_email/index.ts', /readEveryAttachment\(san\.bytes,/, 'inbound e-mail attachments are read, not only counted'],
  ['supplier_catalog_ingest/index.ts', /readableMime === 'application\/pdf' \? \{ type: 'file'/, 'a catalogue PDF reaches the model as a file'],
  ['supplier_catalog_ingest/index.ts', /clearerCopyAsk\('supplier', 'en', fileName\)/, 'an unreadable catalogue asks the supplier for a clearer copy'],
  ['supplier_portal/supporting_documents.ts', /ref_id: String\(supId\), status: 'pending'/, 'supporting documents are queued for doc_extract'],
  ['supplier_portal/supporting_documents.ts', /upd\.status = 'pending'; upd\.attempts = 0;/, 'a replaced supporting document is read again'],
  ['supplier_portal/index.ts', /unread: true, message: clearerCopyAsk\('supplier', 'en'/, 'an unread certificate or licence carries the clearer-copy request'],
  ['extract_text/index.ts', /if\(!text\)\{\s*try\{\s*const r = await fetch\(GW/, 'a scanned PDF is asked again without the text-only engine'],
  ['wa_inbound/index.ts', /clearerCopyAsk\('supplier', 'en', 'the document'\)/, 'a WhatsApp document that could not be read asks for a clearer copy'],
];
for (const [file, re, what] of PATHS) {
  test(`${file}: ${what}`, () => assert.match(code(file), re, `${file} no longer does this: ${what}`));
}
