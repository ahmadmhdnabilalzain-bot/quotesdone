// THE DEMO SUPPLIER FIXTURE CARRIES A READ LICENCE NAME (28 Sep 2026, it_engineer).
//
// The cause: since 24 Sep fn_sales_engineer_verifies_supplier holds a complete supplier at 'pending'
// when leads.licence_legal_name is empty (licence_name_unread). scripts/e2e/fixtures.mjs uploads the
// licence straight to storage, bypassing supplier_api's reader that fills that column, so every demo
// supplier stayed pending and the post-deploy smoke and nightly journey failed fixture setup
// ("approval_status=pending missing=[]", nightly run 36361031412).
//
// WHAT FAILS IF THE CAUSE RETURNS: the fixture's documents update stops writing licence_legal_name as
// the same company name the licence PDF prints; or the verifier stops reading that column (then this
// check is stale and must be revisited with it).
//
//   node --test scripts/checks/the_demo_supplier_fixture_carries_a_read_licence_name.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');

test('makeDemoSupplier writes licence_legal_name = the company its licence PDF names', () => {
  const src = read('scripts/e2e/fixtures.mjs');
  const fn = src.slice(src.indexOf('export async function makeDemoSupplier'));
  const upd = fn.slice(fn.indexOf('await write(`update public.leads set'), fn.indexOf("'demo supplier documents')"));
  assert.match(upd, /licence_legal_name = \$\{q\(company\)\}/, 'the demo supplier documents update does not write licence_legal_name');
  assert.match(fn, /demoTradeLicence\(\{ company,/, 'the licence PDF no longer prints the same company name');
});

test('the verifier still gates on a read licence name', () => {
  const schema = read('supabase/schema/full_schema.sql');
  const at = schema.indexOf('FUNCTION public.fn_sales_engineer_verifies_supplier(');
  assert.ok(at > 0, 'fn_sales_engineer_verifies_supplier is not in the schema mirror');
  assert.match(schema.slice(at, at + 6000), /licence_legal_name/, 'the verifier no longer reads licence_legal_name; revisit this check');
});
