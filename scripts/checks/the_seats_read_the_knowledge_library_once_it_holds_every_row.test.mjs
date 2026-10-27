// THE SEATS READ THE KNOWLEDGE LIBRARY ONCE IT HOLDS EVERY ROW (27 Oct 2026, it_engineer; ledger 889, 1085 phase 2).
//
// Measured 27 Oct 2026: the library held 56 of ~74,000 origins and its switch was an app_secrets value nobody set, so
// "turn the flag on" would have starved every seat. The switch now follows the recorded reconciliation verdict.
//
// WHAT FAILS IF THE CAUSE RETURNS (static, over the SQL file and the fill script):
//   * the read switch goes back to deciding on a secret alone (it must read knowledge_library_state.reconciled);
//   * a missing verdict row reads as 'library' (it must coalesce to false: an unfilled library is never read);
//   * the kill switch is lost ('off' in app_secrets must still force legacy);
//   * the recorder stops recording fn_knowledge_library_reconcile()'s own verdict, or loses its revoke / pinned path;
//   * the state table loses RLS, its policy, its revoke, its one-row check or its export registry row;
//   * the fill script stops recording the verdict it computes (then a complete fill never switches the seats);
//   * this file writes app_secrets (the switch must never need anyone to set a value).
//
//   node --test scripts/checks/the_seats_read_the_knowledge_library_once_it_holds_every_row.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const strip = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const sqlCode = strip(readFileSync(join(REPO, 'scripts/sql/the_seats_read_the_knowledge_library_once_it_holds_every_row.sql'), 'utf8'));
const fill = readFileSync(join(REPO, 'scripts/kb/fill_knowledge_library.mjs'), 'utf8')
  .split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');
const body = (name) => {
  const m = sqlCode.match(new RegExp(`create or replace function public\\.${name}\\([^)]*\\)[\\s\\S]*?\\$fn\\$([\\s\\S]*?)\\$fn\\$`));
  assert.ok(m, `${name} is not defined in the file`);
  return m[1];
};

test('the switch follows the recorded verdict, defaults to legacy, and keeps the kill switch', () => {
  const b = body('fn_knowledge_library_read');
  assert.match(b, /coalesce\(\(select reconciled from public\.knowledge_library_state where id = 1\), false\) then 'library'/);
  assert.match(b, /key = 'knowledge_library_read'\) = 'off' then 'legacy'/);
  assert.match(b, /else 'legacy' end/);
  assert.doesNotMatch(b, /= 'library' then 'library'/, 'a secret alone must not switch the seats onto the library');
});

test('the recorder records the reconcile verdict and is revoked and pinned', () => {
  const b = body('fn_knowledge_library_record_reconcile');
  assert.match(b, /public\.fn_knowledge_library_reconcile\(\)/);
  assert.match(b, /\(v ->> 'reconciled'\)::boolean/);
  assert.match(sqlCode, /fn_knowledge_library_record_reconcile\(\)\s+returns jsonb\s+language plpgsql security definer\s+set search_path to 'public', 'pg_temp'/);
  assert.match(sqlCode, /revoke execute on function public\.fn_knowledge_library_record_reconcile\(\) from public, anon, authenticated;/);
});

test('the state table has one row, RLS, a policy, a revoke and a registry row', () => {
  assert.match(sqlCode, /constraint knowledge_library_state_one_row_ck check \(id = 1\)/);
  assert.match(sqlCode, /alter table public\.knowledge_library_state enable row level security;/);
  assert.match(sqlCode, /create policy knowledge_library_state_service_role_only on public\.knowledge_library_state/);
  assert.match(sqlCode, /revoke all on public\.knowledge_library_state from anon, authenticated;/);
  assert.match(sqlCode, /\('knowledge_library_state', true, 'knowledge',/);
});

test('nothing here writes app_secrets', () => {
  assert.doesNotMatch(sqlCode, /(insert\s+into|update|delete\s+from)\s+(public\.)?app_secrets/i);
});

test('the fill script records every verdict it computes', () => {
  assert.match(fill, /fn_knowledge_library_record_reconcile/);
  assert.match(fill, /const rec = await reconcile\(/);
  assert.match(fill, /r: await reconcile\(/);
});
