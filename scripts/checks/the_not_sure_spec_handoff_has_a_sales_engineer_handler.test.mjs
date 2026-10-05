// THE "NOT SURE" SPEC HANDOFF HAS A SALES ENGINEER HANDLER (5 Oct 2026, sales_engineer; review of #1186).
//
// MEASURED: the first draft registered spec.not_sure (customer_support -> sales_engineer) with
// fn_marketing_social_handoff_waits as its handler — a marketing routine owning a sales_engineer conversation.
//
// WHAT FAILS IF THE CAUSE RETURNS: the kind names a handler that is not a sales_engineer routine, the handler is not
// defined in the same file, or it loses its revoke or pinned search_path.
//
//   node --test scripts/checks/the_not_sure_spec_handoff_has_a_sales_engineer_handler.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const s = readFileSync(join(REPO, 'scripts/sql/a_not_sure_spec_opens_a_handoff_to_the_sales_engineer.sql'), 'utf8');

test('spec.not_sure is handled by a sales_engineer routine defined, revoked and pinned in its own file', () => {
  const row = s.match(/values \('spec\.not_sure', 'customer_support', 'sales_engineer',[\s\S]*?'(fn_[a-z_]+)', interval/);
  assert.ok(row, 'the spec.not_sure row is not registered in the file');
  const h = row[1];
  assert.match(h, /^fn_sales_engineer_/, `handler ${h} is not a sales_engineer routine`);
  assert.match(s, new RegExp(`create or replace function public\\.${h}\\(p_id bigint\\)[\\s\\S]{0,80}security definer set search_path to 'public', 'pg_temp'`));
  assert.match(s, new RegExp(`revoke execute on function public\\.${h}\\(bigint\\) from public, anon, authenticated;`));
});
