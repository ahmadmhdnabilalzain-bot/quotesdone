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
  assert.match(site, /CUSTOMER_ONLY_SPEC_KEYS = \['site_location', 'old_supplier_terms'\]/);
  const gate = code(F('supplier_api/what_a_supplier_receives.ts'));
  assert.match(gate, /supplierField<T>\(spec == null \? spec : supplierSpec\(spec, emirate\)/, 'supplierBrief must apply supplierSpec before the gate');
  assert.match(gate, /siteSeeds\(spec\)/, 'the stated site must be a seed');
  assert.match(gate, /old_supplier_terms/, 'the old supplier\'s terms must be seeds');
  assert.match(code(F('customer_api/actions/inquiry_create.ts')), /splitSite\(/, 'create_inquiry must keep the exact site under the customer-only key');
});

test('the portal inbox serves the summary, the brief and the budget through the one gate, and only a dated reveal unlocks them', () => {
  const inbox = code(F('supplier_api/actions/inbox.ts'));
  assert.match(inbox, /supplierField<string>\(forSource\(i\.summary/);
  assert.match(inbox, /supplierBrief\(i\.spec, i\.emirate, buyer, seeds, hits\)/);
  assert.match(inbox, /supplierField<string>\(i\.budget/);
  assert.match(inbox, /const seeds = requestSeeds\(buyer, i\.spec\)/);
  assert.match(inbox, /from\('transactions'\)\.select\('inquiry_id'\)\.eq\('supplier_id', sup\.id\)\.in\('inquiry_id', ids\)\.not\('revealed_at', 'is', null\)/, 'a transactions row without revealed_at is not a reveal');
  assert.doesNotMatch(inbox, /inboxField\(/, 'the inbox calls the shared gate, not inboxField directly');
});

test('the e-mails to suppliers are gated as the portal is', () => {
  const m = code(F('customer_api/lib/matching.ts'));
  assert.match(m, /newInquiryBody\(\{ resolved: br\.resolved/);
  assert.doesNotMatch(m, /scrubIdentity\(/, 'matching.ts must not scrub with the name alone (audit A, L3)');
  const life = code(F('customer_api/actions/inquiry_lifecycle.ts'));
  assert.match(life, /supplierField<string>\(String\(patch\.summary\)/, 'edit_inquiry gates the summary with the shared gate');
});

test('a priced document is never pictured for a supplier', () => {
  const docs = code(F('customer_api/actions/documents.ts'));
  assert.match(docs, /const pricedByCode = !isCad && pdfLines\.length > 0 && looksPriced\(/);
  assert.match(docs, /i < \(pricedByCode \? 0 : images\.length\)/, 'no page of a priced document is redacted for suppliers');
  assert.match(docs, /brief_source: 'quotation'[^\n]*drawing_redacted_paths: \[\]/, 'the quotation answer carries no page');
  const create = code(F('customer_api/actions/inquiry_create.ts'));
  assert.match(create, /rr\.paths\.length && briefSource !== 'quotation'/, 'create_inquiry drops a quotation\'s pages');
  assert.match(create, /isQuotationReading\(boqObj\) \? 'quotation'/, 'the reading decides the source, not the browser');
  assert.match(code(F('drawing_boq/index.ts')), /if \(isQuotationReading\(ai\)\) ai = quotationGate\(ai, quotationTerms\(pdfLines\)\)/, 'the model reading of a priced document passes the quotation gate');
});
