// THE CEO APPROVES THE JANUARY LAUNCH PLAN; THE FOUNDER READS IT IN HIS BRIEF.   seat: ceo · 10 Nov 2026 · ledger 1616
//
// Measured 10 Nov 2026: fn_marketing_launch_plan_run mailed the founder "[approve <token>]" from 1 Dec and waited for his
// reply, on the all-categories rule. This fails if the plan goes to him again, if the CEO stops deciding it with reasons,
// if the brief stops carrying the CEO's decisions, or (with a token) the files and probe rolled back are not PROBE OK.
//   node --test scripts/checks/the_ceo_approves_the_january_launch_plan_and_the_founder_reads_it_in_his_brief.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/the_ceo_approves_the_january_launch_plan_and_the_founder_reads_it_in_his_brief.sql';
const BEFORE = ['scripts/sql/a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.sql', 'scripts/sql/the_ceo_plans_on_a_break_even_ledger_to_june_2027.sql'];
const read = (p) => readFileSync(path.join(REPO, p), 'utf8');
const src = read(FILE).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const body = (name) => { const m = src.match(new RegExp('function public\\.' + name + '\\([\\s\\S]*?\\$fn\\$[\\s\\S]*?\\$fn\\$')); assert.ok(m, name); return m[0]; };
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(SUPABASE_TOKEN_FILE) ? readFileSync(SUPABASE_TOKEN_FILE, 'utf8') : '')).trim();

test('the CEO decides the plan with reasons; nobody is mailed; the brief carries the decision', () => {
  const run = body('fn_marketing_launch_plan_run');
  assert.doesNotMatch(run, /fn_marketing_mail_founder|fn_notify_founder|insert into public\.notifications/, 'the launch plan is mailed again');
  assert.match(run, /fn_ceo_decide_launch_plan\(d\.id\)/, 'the CEO does not decide the plan');
  assert.match(run, /trade_customer_opening/, 'the plan is not drawn trade by trade (ledger 1614)');
  assert.doesNotMatch(run, /until every category/i, 'the all-categories rule is back');
  const dec = body('fn_ceo_decide_launch_plan');
  assert.match(dec, /'ceo_review', jsonb_build_object\('decided_by', 'ceo'/, 'the decision carries no reasons on the document');
  assert.match(dec, /fn_marketing_paid_allowed\(\)/, 'the paid-channel rule is gone');
  assert.match(dec, /fn_ceo_brief_line\(/, 'the decision is not told in the brief');
  assert.match(body('fn_founder_brief'), /v_body := v_body \|\| public\.fn_founder_brief_ceo_lines\(v_from, v_to\);/, 'the brief does not carry the CEO section');
  assert.ok(pendingNotes().has(FILE) !== read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

test('the files and the probe, rolled back', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const pend = pendingNotes();
  const text = [...BEFORE, FILE].filter((f) => pend.has(f)).map(read).join('\n;\n') + '\n;\n' + read(FILE.replace('.sql', '_probe.sql'));
  await assert.rejects(replaySql(text, { label: 'the launch-plan probe' }), /PROBE OK/, 'the probe did not end PROBE OK');
});
