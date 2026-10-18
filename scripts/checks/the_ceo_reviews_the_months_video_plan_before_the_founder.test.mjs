// THE CEO REVIEWS THE MONTH'S VIDEO PLAN BEFORE THE FOUNDER SEES IT (it_engineer, 29 Sep 2026; ruling 1059).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: fn_marketing_month_plan_tick mails the founder (fn_marketing_mail_founder) anywhere but in its
//     'ceo_approved' branch, or stops leaving a month the argued path put to the CEO alone;
//   * static: fn_ceo_marketing_plan_watch measures the CEO's wait from plan_sent_at again (never set before the founder is
//     mailed, so the comparison was NULL and the watch never fired on the argued path);
//   * production (aborted, when a token is present): the probe drafts November, files it to the CEO, has the CEO reject
//     with reasons, marketing revise, the CEO approve, and only then mails the founder once; the watch fires on both
//     paths. Against production before the file it fails (no fn_reason_apply_ceo__marketing_month_plan).
//
//   node --test scripts/checks/the_ceo_reviews_the_months_video_plan_before_the_founder.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { manifestWithPending } from '../lib/pending_sql.mjs';
import { definitions } from '../lib/canonical_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FILE = 'scripts/sql/the_ceo_reviews_the_months_video_plan_before_the_founder_sees_it.sql';
const PROBE = 'scripts/sql/the_ceo_reviews_the_months_video_plan_before_the_founder_sees_it_probe.sql';

function canonical() {
  const out = new Map();
  for (const f of manifestWithPending()) {
    if (!existsSync(join(REPO, f))) continue;
    for (const d of definitions(readFileSync(join(REPO, f), 'utf8'))) out.set(d.name, d.stmt.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n'));
  }
  return out;
}

test('the tick mails the founder only after the CEO approved, and leaves the argued path alone', () => {
  const tick = canonical().get('fn_marketing_month_plan_tick');
  assert.ok(tick, 'fn_marketing_month_plan_tick is defined nowhere');
  const mail = tick.indexOf('fn_marketing_mail_founder(');
  const gate = tick.indexOf("if p.status is distinct from 'ceo_approved' then");
  assert.ok(gate > 0 && mail > gate, 'the founder is mailed before (or without) the CEO approval branch');
  assert.equal(tick.indexOf('fn_marketing_mail_founder(', mail + 1), -1, 'a second founder mail path');
  assert.match(tick.slice(0, gate), /return jsonb_build_object\('sent', false, 'month', v_month, 'with_ceo', true/, 'the ceo_reviewing branch does not return before the mail');
  assert.match(tick, /p\.status in \('with_ceo', 'agreed', 'brief_requested', 'sent_to_founder', 'accepted', 'rejected'\)/,
    'the tick no longer leaves a month the argued path owns');
  assert.match(canonical().get('fn_reason_apply_ceo__marketing_month_plan'), /public\.fn_ceo_decide\('marketing_month_plan'/, 'the CEO answer bypasses the ledger');
  assert.match(canonical().get('fn_ceo_revision_applies'), /'marketing_month_plan' then/, 'no revision route for the plan');
});

test('the stall watch measures when the plan reached the CEO on each path', () => {
  const w = canonical().get('fn_ceo_marketing_plan_watch');
  assert.doesNotMatch(w, /plan_sent_at\s*</, 'the watch measures from plan_sent_at again - NULL until the founder is mailed');
  assert.match(w, /t\.seat = 'marketing'/);
  assert.match(w, /p\.status = 'ceo_reviewing'/);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production, aborted: the probe answers PROBE OK', { skip: hasToken ? false : 'no Supabase management token in this environment', timeout: 600000 }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const text = [FILE, PROBE].map((f) => readFileSync(join(REPO, f), 'utf8')).join('\n;\n');
  let msg = '';
  try { await replaySql(text, { retry: false }); msg = 'the probe did not raise'; } catch (e) { msg = String(e.message); }
  const i = msg.indexOf('CHK<<');
  assert.ok(i >= 0, msg.slice(0, 1500));
  assert.match(msg.slice(i, msg.indexOf('>>', i)), /PROBE OK/, msg.slice(i, i + 3000));
});
