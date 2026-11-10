// THE ACCOUNTANT'S FORECAST CARRIES EVERY RECURRING COST AND THE BREAK-EVEN LINE.   seat: accountant · 10 Nov 2026 (P13)
//
// Measured 10 Nov 2026: the 13-week cash forecast projected Anthropic, OpenAI and the Mashreq fee only, and none of the
// seven other vendors the books carry with 2+ receipts in 120 days; it had no break-even line. This fails if the books
// stop being a source, if an excluded line (Actions off, ledger 1564) comes back, if the break-even line goes, or (with a
// token) if the probe rolled back is not PROBE OK.
//   node --test scripts/checks/the_accountant_forecast_carries_every_recurring_cost_and_the_break_even_line.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/the_accountant_forecast_carries_every_recurring_cost_and_the_break_even_line.sql';
const BE = 'scripts/sql/the_ceo_plans_on_a_break_even_ledger_to_june_2027.sql';
const OPEN = 'scripts/sql/a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.sql';
const read = (p) => readFileSync(path.join(REPO, p), 'utf8');
const src = read(FILE).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(SUPABASE_TOKEN_FILE) ? readFileSync(SUPABASE_TOKEN_FILE, 'utf8') : '')).trim();

test('the books are a source, the excluded lines stay out, the break-even line is there', () => {
  assert.match(src, /select 'books_recurring'/, 'the books are not a forecast source');
  assert.match(src, /having count\(\*\) >= 2 and max\(e\.charged_on\) > v_as_of - 75/, 'the recurring rule changed');
  assert.match(src, /c\.kind = 'excluded'/, 'a line the break-even ledger marks off is forecast again');
  assert.match(src, /'break_even', \(select jsonb_build_object/, 'the break-even line is gone');
  assert.ok(pendingNotes().has(FILE) !== read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

test('the files and the probe, rolled back', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const pend = pendingNotes();
  const text = [OPEN, BE, FILE].filter((f) => pend.has(f)).map(read).join('\n;\n') + '\n;\n' + read(FILE.replace('.sql', '_probe.sql'));
  await assert.rejects(replaySql(text, { label: 'the forecast probe' }), /PROBE OK/, 'the probe did not end PROBE OK');
});
