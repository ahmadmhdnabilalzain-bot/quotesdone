// A VOID JOURNAL NEVER MOVES A BALANCE (accountant, 28 Sep 2026).
//
// gl_account_balances put its "posted" test in the ON clause of an outer join to gl_journal, so a void
// journal's lines were still summed: the forecast showed AED 395.11 cash against a posted ledger of 582.96.
// This fails if the view again reaches gl_journal through an outer join, or stops testing status posted.
// Source: the fix file while its scripts/sql/pending note exists, then the live mirror.
//
//   node --test scripts/checks/a_void_journal_never_moves_a_balance.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FIX = 'scripts/sql/a_void_journal_never_moves_a_balance.sql';
const PENDING = 'scripts/sql/pending/a_void_journal_never_moves_a_balance.txt';
const SRC = existsSync(join(REPO, PENDING)) ? read(FIX) : read('supabase/schema/full_schema.sql');

test('gl_account_balances sums only lines of posted journals', () => {
  const m = /create or replace view public\.gl_account_balances\b[\s\S]*?;\s*\n/i.exec(SRC);
  assert.ok(m, 'gl_account_balances is defined');
  const body = m[0].split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
  assert.match(body, /status\s*=\s*'posted'/i, 'the view no longer tests status posted');
  assert.doesNotMatch(body, /left\s+join\s+(public\.)?gl_journal\s/i, 'gl_journal is outer-joined again: void lines are summed');
});
