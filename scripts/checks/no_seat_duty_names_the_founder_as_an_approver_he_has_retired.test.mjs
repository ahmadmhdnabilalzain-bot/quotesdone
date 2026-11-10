// NO SEAT DUTY NAMES THE FOUNDER AS AN APPROVER HE HAS RETIRED.        seat: marketing (with ceo) · 10 Nov 2026 · ledger 1058, 1609
//
// Measured 10 Nov 2026: seat_duty 'marketing.article_release' still said 'sent to the founder for "approve"; only his
// approval releases it', six weeks after ledger 1058 moved article approval to the CEO. The code obeyed the ruling; the
// job description did not, and the job description is what the seat audit, the senior verdict and an auditor read.
// This fails if a registered duty text again makes the founder the approver of something he has handed to the CEO.
// The approvals he kept are named below with their ruling, so a new one is a decision, not an accident.
//
//   node --test scripts/checks/no_seat_duty_names_the_founder_as_an_approver_he_has_retired.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { pendingNotes } from '../lib/pending_sql.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/the_article_release_duty_says_the_ceo_approves_and_the_founder_is_only_told.sql';
const REGISTER = 'scripts/sql/the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql';
// The approvals the founder kept, each with the ruling that keeps it. Anything else that names him as approver fails.
const KEPT = {
  'marketing.month_plan': 'ledger 1059 / 24 Sep 2026: the monthly social calendar is his one approval',
  'marketing.launch_plan': '28 Sep 2026: the January 2027 launch plan goes to him for a one-shot approval from 1 December',
  'ceo.pricing_monitor': 'pricing is in the signed terms; a change is his (the proposal goes to him)',
};
const NAMES_HIM_APPROVER = /(to the founder for ["“]?approve|only his approval|founder approves|founder'?s approval|for his (one-shot )?approval|sent for approval)/i;
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(SUPABASE_TOKEN_FILE) ? readFileSync(SUPABASE_TOKEN_FILE, 'utf8') : '')).trim();

test('the registered article-release text names the CEO, in the file that registers it and in the fix', () => {
  const reg = readFileSync(path.join(REPO, REGISTER), 'utf8');
  const row = reg.match(/\('marketing\.article_release',[\s\S]*?\n\s*'([^\n]*?)',\n/);
  assert.ok(row, 'the article-release duty row is not in its register file');
  assert.doesNotMatch(row[1], NAMES_HIM_APPROVER, 'ledger 1058: the article-release duty names the founder as approver again');
  assert.match(row[1], /reviewed by the CEO seat/, 'the article-release duty no longer says who approves');
  const fix = readFileSync(path.join(REPO, FILE), 'utf8');
  assert.match(fix, /update public\.seat_duty\s+set what = 'One article draft a Dubai week is reviewed by the CEO seat/, 'the production fix is gone');
});

test('live: no enabled duty makes the founder an approver he has not kept', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  if (pendingNotes().has(FILE)) { t.skip('pending: not applied yet'); return; }
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select duty, what from public.seat_duty where enabled`, { readOnly: true });
  const bad = rows.filter((r) => NAMES_HIM_APPROVER.test(r.what || '') && !KEPT[r.duty]).map((r) => `${r.duty}: ${r.what}`);
  assert.deepEqual(bad, [], 'a duty names the founder as an approver he has handed to the CEO (ledger 1058, 1609)');
});
