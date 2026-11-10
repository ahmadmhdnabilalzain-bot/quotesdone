// AN UNANSWERED REQUEST IS A STRIKE, AND A QUOTE CLEARS THE RUN (customer_support for the sales engineer's matching,
// 10 Nov 2026; supplier follow-up of #1909, item 6).
//
// MEASURED on origin/main: fn_is_matchable gates on leads.chat_strikes < fn_matching_strike_limit() (the founder's 3 Aug
// 2026 rule: three consecutive unanswered RFQs and the matcher stops), and the supplier portal names that gate, but no
// routine and no edge function ever wrote chat_strikes: the gate could not close. This holds that something writes it,
// with the rule's shape: ended requests only (never a customer's cancel), the platform's existing "no quote in time"
// window (no invented number), and a quote clearing the run (consecutive).
//
//   node --test scripts/checks/an_unanswered_request_is_a_strike_and_a_quote_clears_the_run.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const REPO = join(import.meta.dirname, '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/an_unanswered_request_is_a_strike_and_a_quote_clears_the_run.sql';
const WRITES = /chat_strikes\s*=\s*(?:coalesce\(chat_strikes, 0\) \+ 1|0)\b/g;

test('something writes leads.chat_strikes, in the database (applied) or in a file waiting to be applied', () => {
  const sqlFiles = readdirSync(join(REPO, 'scripts/sql')).filter((f) => f.endsWith('.sql') && !f.endsWith('_probe.sql'));
  const writers = sqlFiles.filter((f) => (read('scripts/sql/' + f).match(WRITES) || []).length > 0);
  const mirror = readSchemaMirror();
  assert.ok(writers.length > 0 || (mirror.match(WRITES) || []).length > 0, 'the strike gate in fn_is_matchable is read and never written');
});

test('a strike is an ended request he had the full window to answer, never a cancel; a quote clears the run', () => {
  const sql = read(FILE);
  const trg = sql.slice(sql.indexOf('function public.trg_request_end_counts_unanswered_suppliers'), sql.indexOf('create trigger z32_request_end_counts_unanswered_suppliers'));
  const ends = [.../NEW\.status, ''\) in \(([^)]*)\)/.exec(trg)[1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).sort();
  assert.deepEqual(ends, ['completed', 'expired', 'lost'], 'cancelled is the customer\'s choice and closed a split parent');
  assert.match(trg, /NEW\.rfq_ready is true/, 'a request still waiting for the customer\'s details is nobody\'s silence');
  assert.match(sql, /fn_seat_clock_policy\('request_no_quote_expiry_days', 21\)/, 'the window is the platform\'s own, not a new number');
  assert.match(sql, /not exists \(select 1 from public\.quotes q where q\.inquiry_id = p_inquiry and q\.supplier_id = m\.supplier_id\)/);
  assert.match(sql, /create trigger z32_a_quote_clears_the_strike_run after insert on public\.quotes/);
  assert.match(sql, /supplier_strike_event_one_per_request on public\.supplier_strike_event \(lead_id, inquiry_id\) where kind = 'strike'/);
});

test('the gate the strikes close is the one the portal explains', () => {
  const mirror = readSchemaMirror();
  assert.match(mirror, /coalesce\(p_chat_strikes, 0\) < public\.fn_matching_strike_limit\(\)/);
  assert.match(read('supabase/functions/supplier_portal/overview.ts'), /went unanswered ' \+ Number\(r\.chat_strikes \|\| 0\) \+ ' times/);
});
