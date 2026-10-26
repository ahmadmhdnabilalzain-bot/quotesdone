// A SUPPLIER'S DOCUMENTS ARE READ BY CODE, A NEW TRADE IS REVIEWED, AND MATCHING IS EXACT OR NONE.
//
// 15 Sep 2026 (sales_engineer). Founder: "The sales engineer must actually read company profiles and
// catalogues", exact trade match or none, and categories are open. Measured before: every supplier
// document read went through the held model; a refused catalogue read was stored 'no_products_found';
// customer_api fell back to fuzzy keyword matching when the sales engineer errored. These assertions
// hold the wiring in place; the reading itself is proved by the deno tests beside the code
// (supabase/functions/_shared/supplier_doc_trades.test.ts, supplier_catalog_ingest/rows_from_text.test.ts).
//
//   node --test scripts/checks/supplier_documents_are_read_by_code.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const read = (p) => readFileSync(fileURLToPath(new URL('../../' + p, import.meta.url)), 'utf8');
const SQL = 'scripts/sql/a_suppliers_documents_propose_trades_and_a_new_trade_is_reviewed_not_dropped.sql';

test('every supplier upload path reads the document by code into a trade proposal', () => {
  for (const f of ['supabase/functions/supplier_api/index.ts', 'supabase/functions/supplier_portal/index.ts', 'supabase/functions/supplier_catalog_ingest/index.ts']) {
    assert.match(read(f), /proposeTradesFromDocs\(admin, /, `${f} does not read uploads into the proposal`);
  }
});

test('a model refusal on a catalogue is unread_llm_hold, not a false zero', () => {
  const src = read('supabase/functions/supplier_catalog_ingest/index.ts');
  assert.match(src, /return await fail\('unread_llm_hold', /);
  assert.match(src, /products = productsFromText\(docRead\.text\)/, 'a PDF text layer is not tried by code first');
});

test('every customer_api path asks the sales engineer, and a matcher failure raises a finding', () => {
  // The turnkey path was the last keyword caller; it now shares the sales engineer route. The full
  // no-fuzzy-matcher guard is scripts/checks/supplier_matching_is_exact_or_none.test.mjs.
  const src = read('supabase/functions/customer_api/index.ts');
  assert.doesNotMatch(src, /useRouter/, 'a path that skips the sales engineer is back');
  assert.match(src, /p_issue_key: 'sales_engineer_match_unavailable'/, 'a matcher failure raises no finding');
});

test('a trade outside the list becomes a reviewed proposal, and the ledger records what the documents said', () => {
  const src = read('supabase/functions/_shared/supplier_capability.ts');
  assert.match(src, /from\('taxonomy_trade_proposal'\)\.upsert\(/);
  assert.match(src, /proposed: \{ on_file_trades: onFile, document_trades: fromDocs \}/);
  assert.match(src, /source_docs: obj\(before\?\.source_docs\)/);
});

test('the dead capability_agent scope prompt is gone', () => {
  assert.doesNotMatch(read('supabase/functions/supplier_portal/index.ts'), /confirm_questions/);
});

test('the SQL is in the index, and its table and routine are closed', () => {
  assert.ok(read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(SQL), 'MANIFEST has no line for the SQL');
  const sql = read(SQL);
  assert.match(sql, /alter table public\.taxonomy_trade_proposal enable row level security;/);
  assert.match(sql, /create policy taxonomy_trade_proposal_service_role_only/);
  assert.match(sql, /revoke execute on function public\.fn_trade_proposal_decide\(bigint, text, text, text, text, text\) from public, anon, authenticated;/);
  assert.match(sql, /set search_path to 'public', 'pg_temp'/);
});
