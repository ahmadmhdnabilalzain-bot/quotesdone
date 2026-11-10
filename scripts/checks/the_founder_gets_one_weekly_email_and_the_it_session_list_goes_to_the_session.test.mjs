// THE FOUNDER GETS ONE WEEKLY E-MAIL; THE IT SESSION LIST GOES TO THE SESSION.   seats: it_engineer, ceo · 10 Nov 2026 · 1609
//
// Measured 28 Oct - 10 Nov 2026: the IT digest mailed him a session's to-do list under "No decision of yours is needed
// today", and every Monday brought two weekly e-mails an hour apart (board_report, ceo_weekly_review). This fails if the
// digest mails without a decision of his, if the session list stops being kept for the session, if the company report is
// mailed on its own again, or if the review stops carrying it; with a token, if the probe rolled back is not PROBE OK.
//   node --test scripts/checks/the_founder_gets_one_weekly_email_and_the_it_session_list_goes_to_the_session.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/the_founder_gets_one_weekly_email_and_the_it_session_list_goes_to_the_session.sql';
const read = (p) => readFileSync(path.join(REPO, p), 'utf8');
const src = read(FILE).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const body = (name) => { const m = src.match(new RegExp('function public\\.' + name + '\\([\\s\\S]*?\\$fn\\$[\\s\\S]*?\\$fn\\$', 'i')); assert.ok(m, name); return m[0]; };
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(SUPABASE_TOKEN_FILE) ? readFileSync(SUPABASE_TOKEN_FILE, 'utf8') : '')).trim();

test('P5: the digest mails him only a decision of his; the session list is kept for the session', () => {
  const it = body('fn_customer_support_sends_the_it_digest');
  assert.match(it, /insert into public\.it_session_fix_day/, 'the session list is not kept for the session');
  assert.match(it, /if jsonb_array_length\(v_items\) = 0 then/, 'the digest can mail without a decision of his');
  assert.doesNotMatch(it, /'What a working session must fix/, 'the session list is mailed to him again');
});

test('P6: one weekly e-mail carries the review and the company report', () => {
  const rep = body('fn_ceo_weekly_report_deliver');
  assert.doesNotMatch(rep, /insert into public\.notifications|fn_notify_founder/, 'the company report is mailed on its own again');
  const rev = body('fn_ceo_weekly_review_deliver');
  assert.match(rev, /from public\.ceo_weekly_report r where r\.week_end = w\.week - 1/, 'the review does not find the week\'s company report');
  assert.match(rev, /QuotesDone_Weekly_Company_Report_/, 'the review does not attach the company report');
  assert.ok(pendingNotes().has(FILE) !== read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

test('the file and its probe, rolled back', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const text = (pendingNotes().has(FILE) ? read(FILE) + '\n;\n' : '') + read(FILE.replace('.sql', '_probe.sql'));
  await assert.rejects(replaySql(text, { label: 'the one-weekly-email probe' }), /PROBE OK/, 'the probe did not end PROBE OK');
});
