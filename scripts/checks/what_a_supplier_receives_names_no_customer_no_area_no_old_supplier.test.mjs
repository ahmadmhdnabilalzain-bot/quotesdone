// WHAT A SUPPLIER RECEIVES NAMES NO CUSTOMER, NO AREA AND NO OLD SUPPLIER (13 Nov 2026, sales_engineer; founder ruling 1683;
// anonymity audit A, L1, L2, L3, L6). The behaviour is proved by the Deno tests named below on planted fixtures; this check pins
// the WIRING those tests cannot see: that every door through which a customer's request reaches a supplier before a reveal
// calls the one gate, so a door added or edited later cannot drift back to a scrubber of its own.
//   * The customer's exact site lives under the customer-only key `site_location` (and the old supplier's terms under
//     `old_supplier_terms`); every supplier door drops them (supplierSpec through supplierBrief) and seeds them.
//   * The portal inbox, the new-inquiry e-mail, the job-awarded-other notice and the edited summary call
//     supplier_api/what_a_supplier_receives.ts; none calls scrubIdentity with a name alone any more (the measured L3 leak).
//   * The inbox treats only a transactions row with revealed_at as a reveal (L6).
//   * A priced document is never pictured for a supplier: analyze_drawing returns no redacted page for it, and create_inquiry
//     drops the drawing paths of a quotation (L2).
// Behaviour: supplier_api/nothing_below_the_emirate_reaches_a_supplier.test.ts, drawing_boq/a_quotation_reaches_suppliers_as_our_inquiry.test.ts
//   node --test scripts/checks/what_a_supplier_receives_names_no_customer_no_area_no_old_supplier.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const F = (p) => readFileSync(join(ROOT, 'supabase/functions', p), 'utf8');
// code only: a check that greps source must not match its own comment (quotesdone-apply-discipline)
const code = (s) => s.split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n');

test('the customer-only keys are dropped and seeded at every door', () => {
  const site = code(F('_shared/site_location.ts'));
  assert.match(site, /CUSTOMER_ONLY_SPEC_KEYS = \['site_location', 'old_supplier_terms', 'site_keys', 'customer_rates', 'site_photos'\]/);
  const gate = code(F('supplier_api/what_a_supplier_receives.ts'));
  assert.match(gate, /supplierField<T>\(spec == null \? spec : supplierSpec\(spec, emirate\)/, 'supplierBrief must apply supplierSpec before the gate');
  assert.match(gate, /if \(o\.revealed\) return \{ summary: forSource\([^\n]*revealedSpec\(/, 'a revealed supplier gets forSource and never the old supplier\'s terms');
  assert.match(gate, /siteSeeds\(spec\)/, 'the stated site must be a seed');
  assert.match(gate, /old_supplier_terms/, 'the old supplier\'s terms must be seeds');
  assert.match(code(F('customer_api/actions/inquiry_create.ts')), /splitSite\(/, 'create_inquiry must keep the exact site under the customer-only key');
});

test('the portal inbox serves every row through the one gate, and only a dated reveal unlocks it', () => {
  const inbox = code(F('supplier_api/actions/inbox.ts'));
  assert.match(inbox, /const c = supplierCopy\(i, \{ revealed, ownerResolved, buyer \}, hits\)/);
  assert.match(inbox, /from\('transactions'\)\.select\('inquiry_id'\)\.eq\('supplier_id', sup\.id\)\.in\('inquiry_id', ids\)\.not\('revealed_at', 'is', null\)/, 'a transactions row without revealed_at is not a reveal');
  assert.doesNotMatch(inbox, /inboxField\(|inboxBoq\(/, 'the inbox calls the shared gate, not a scrubber directly');
});

test('every door that e-mails a customer\'s words to the matched suppliers reads the owner and passes the gate', () => {
  const life = code(F('customer_api/actions/inquiry_lifecycle.ts'));
  assert.doesNotMatch(life, /scrubIdentity\(/, 'rfq_note / add_missing_specs must not scrub with the name alone (review of F2, item 1)');
  assert.match(life, /const toSup = forSuppliers\(clean, owner\)/);
  assert.match(life, /const clean = forSuppliers\(String\(v\), seen\)/);
  assert.match(code(F('messages_api/index.ts')), /const supplierCopy = forSuppliers\(text, owner\)/, 'clarify_answer');
  assert.match(code(F('_shared/supplier_english.ts')), /const english = await textForSuppliers\(admin, String\(row\.inquiry_id\), english0\)/, 'the English replay');
  assert.match(code(F('supplier_api/actions/quotes.ts')), /summary: owner \? forSuppliers\(/, 'the quotation reader gets the supplier copy');
  for (const f of ['supplier_portal/actions/dashboard.ts', 'supplier_portal/actions/market.ts']) assert.match(code(F(f)), /BeforeReveal\(/, f + ' applies the reveal rule at its door');
});

test('the e-mails to suppliers are gated as the portal is', () => {
  const m = code(F('customer_api/lib/matching.ts'));
  assert.match(m, /newInquiryBody\(\{ resolved: br\.resolved/);
  assert.doesNotMatch(m, /scrubIdentity\(/, 'matching.ts must not scrub with the name alone (audit A, L3)');
  const life = code(F('customer_api/actions/inquiry_lifecycle.ts'));
  assert.match(life, /const d = editDecision\(patch,/, 'edit_inquiry decides through ./lib/edit_summary.ts (the shared gate, only what changed)');
  assert.match(code(F('customer_api/lib/edit_summary.ts')), /supplierField<string>\(next, owner\.buyer, seeds\)/);
});

test('a priced document is never pictured for a supplier, and a drawing beside it is kept', () => {
  const docs = code(F('customer_api/actions/documents.ts'));
  assert.match(docs, /const pricedByCode = !isCad && pdfLines\.length > 0 && looksPriced\(/);
  // Round 4 (drawing_deadline): the loop counts batches under the request's clock; a priced document still runs none.
  // 17 Nov 2026: the batches' paths are kept in page order between the two lines (pages run side by side); nothing else.
  assert.match(docs, /const batches = pricedByCode \? 0 : Math\.ceil\(images\.length \/ REDACT_BATCH\);\s*(?:\/\/[^\n]*\n\s*)*const pathsOf: string\[\]\[\] = \[\], jobsOf: string\[\]\[\] = \[\];\s*const ran = await eachPageInTime\(batches,/, 'no page of a priced document is redacted for suppliers');
  assert.match(docs, /const priced = pricedRoute\(\{ isCad, pdfLines, reading: jd\.boq \|\| null \}\);\s*if \(priced\) return J/, 'the priced route answers before the drawing route');
  const create = code(F('customer_api/actions/inquiry_create.ts'));
  assert.match(create, /const drawingRedacted = rr\.paths\.length \? rr\.paths\.slice\(0, 24\) : null/, 'a drawing attached beside a quotation keeps its pages');
  assert.match(create, /isQuotationReading\(boqObj\) \? 'quotation'/, 'the reading decides the source, not the browser');
  assert.match(create, /const emirate = oneOfSeven\(body\.emirate\)/, 'the emirate is one of the seven');
  assert.match(code(F('drawing_boq/index.ts')), /if \(isQuotationReading\(ai\)\) ai = quotationGate\(ai, quotationTerms\(pdfLines\)\)/, 'the model reading of a priced document passes the quotation gate');
});
