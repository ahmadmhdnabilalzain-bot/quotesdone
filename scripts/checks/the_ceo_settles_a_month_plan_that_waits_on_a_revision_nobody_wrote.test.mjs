// THE CEO SETTLES A MONTH PLAN THAT WAITS ON A REVISION NOBODY WROTE.   seat: ceo · 10 Nov 2026 · ledger 1609, 1059 (P11)
//
// Measured 10 Nov 2026: the November and December marketing plans sat in ceo_reviewing after the CEO rejected them,
// waiting on a model revision that never came. This fails if the settle stops deciding by the idea's audience field
// (instruction 890), stops recording reasons on the decision ledger, mails anyone, or (with a token) its probe rolled
// back is not PROBE OK.
//   node --test scripts/checks/the_ceo_settles_a_month_plan_that_waits_on_a_revision_nobody_wrote.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/the_ceo_settles_a_month_plan_that_waits_on_a_revision_nobody_wrote.sql';
const read = (p) => readFileSync(path.join(REPO, p), 'utf8');
const src = read(FILE).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(SUPABASE_TOKEN_FILE) ? readFileSync(SUPABASE_TOKEN_FILE, 'utf8') : '')).trim();

test('the CEO settles in code, by the audience field, with reasons, and mails nobody', () => {
  assert.match(src, /coalesce\(e->>'audience', 'both'\) <> 'customer'/, 'the customer-only rule no longer reads the audience field');
  assert.doesNotMatch(src, /~\*|ilike '%|position\s*\(/, 'the settle decides by matching words');
  assert.equal((src.match(/public\.fn_ceo_decide\('marketing_month_plan'/g) || []).length, 3, 'a branch settles without the decision ledger');
  assert.doesNotMatch(src, /insert into public\.notifications|fn_notify_founder|fn_seat_duty_reason/, 'the settle mails someone or asks a model');
  assert.match(src, /v_last\.decided_at > p_at - interval '3 days'/, 'a fresh rejection is settled before marketing had 3 days');
  assert.ok(pendingNotes().has(FILE) !== read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

test('the file and its probe, rolled back', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const text = (pendingNotes().has(FILE) ? read(FILE) + '\n;\n' : '') + read(FILE.replace('.sql', '_probe.sql'));
  await assert.rejects(replaySql(text, { label: 'the month-plan settle probe' }), /PROBE OK/, 'the probe did not end PROBE OK');
});
