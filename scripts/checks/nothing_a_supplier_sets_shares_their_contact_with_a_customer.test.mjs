// NOTHING A SUPPLIER SETS SHARES THEIR CONTACT WITH A CUSTOMER (12 Nov 2026, sales_engineer, built by it_engineer;
// founder ruling, ledger 1668: "How the whole concept of this app is about being anonymous. And we never share because
// otherwise no one will pay a reveal fee.").
//
// Supplier Settings carried a switch "Share my e-mail with customers I have quoted" (English and Arabic), saved by
// supplier_api save_settings into leads.email_shared. Nothing ever read that column (no edge function, no website
// code, 0 routines, views, policies or triggers in the live database, measured 12 Nov 2026), so it shared nothing; it
// only offered what the product must never do. A supplier's contact reaches a customer through the paid reveal alone
// (customer_api reveal / stripe_confirm, both behind _shared/reveal_guard.ts). This fails if the offer, its parameter
// or a reader of the column comes back.
//   node --test scripts/checks/nothing_a_supplier_sets_shares_their_contact_with_a_customer.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';
import { REPO, functionSource } from '../lib/function_sources.mjs';

const read = (f) => readFileSync(join(REPO, f), 'utf8');
const settings = read('src/components/portal/supplier/SupplierSettings.tsx');
const supplierApi = functionSource('supplier_api');

// Every source file under these roots; tests are left out because a test names what it forbids (this one does).
const walk = (dir, out = []) => {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    if (name === 'node_modules' || name.startsWith('.')) continue;
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(ts|tsx|mjs|js|sql|json)$/.test(name) && !/\.test\.(ts|mjs|tsx)$/.test(name)) out.push(p);
  }
  return out;
};

test('supplier Settings offers no switch to share the supplier e-mail with customers', () => {
  assert.doesNotMatch(settings, /email_shared/, 'Settings must not read or send email_shared');
  assert.doesNotMatch(settings, /emailShare/, 'the emailShare strings must not come back');
  assert.doesNotMatch(settings, /Share my e-?mail/i, 'no English offer to share the e-mail');
  assert.doesNotMatch(settings, /مشاركة بريدي/, 'no Arabic offer to share the e-mail');
});

test('supplier_api neither accepts nor returns email_shared', () => {
  assert.doesNotMatch(supplierApi, /email_shared/, 'save_settings must not write it and settings must not select it');
  // The action itself stays: an old page that still posts email_shared is answered ok and the value is ignored.
  assert.match(supplierApi, /if \(action === 'save_settings'\)/);
});

test('leads.email_shared is read by nothing in the website, the edge functions or the SQL the repository applies', () => {
  const roots = ['src', 'supabase/functions', 'scripts/sql'].map((r) => join(REPO, r));
  const readers = roots.flatMap((r) => walk(r)).filter((f) => /email_shared/.test(readFileSync(f, 'utf8'))).map((f) => relative(REPO, f));
  assert.deepEqual(readers, [], 'a reader of leads.email_shared came back: ' + readers.join(', '));
});

test('no supplier-facing copy offers to share the supplier contact with customers', () => {
  const roots = ['src/components/portal/supplier', 'supabase/functions/supplier_api', 'supabase/functions/supplier_portal', 'supabase/functions/supplier_onboard'];
  const OFFER = /share (my|your|our) (e-?mail|phone|number|mobile|whatsapp|contact|website|company name|licen[cs]e)/i;
  const hits = roots.flatMap((r) => walk(join(REPO, r))).flatMap((f) => read(relative(REPO, f)).split('\n')
    .map((l, i) => (OFFER.test(l) ? `${relative(REPO, f)}:${i + 1}` : null)).filter(Boolean));
  assert.deepEqual(hits, [], 'supplier-facing copy offers to share contact details outside the paid reveal');
});
