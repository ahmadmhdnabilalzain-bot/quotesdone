// THE MARKETING SEAT'S PLAN, GEO, ARTICLE, LAUNCH AND COMPETITOR WORK IS ON A CLOCK (marketing, 28 Sep 2026).
//
// Measured 28 Sep 2026: public.seat_duty held three marketing rows; the monthly plan, the GEO check, the article
// release, the competitor refresh and the January 2027 launch plan had no owner/clock/check row, the 4 article
// drafts had no path to the founder's approval, and the studio's blog links pointed at quotesdone.com.
// This fails when any of the five duties loses its seat_duty row or its routine, when his approval reply stops
// being routed, when an article can be approved by anyone but him, or when a blog link points at quotesdone.com.
//
//   node --test scripts/checks/marketing_duties_are_on_a_clock.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (f) => readFileSync(join(REPO, f), 'utf8');
const OWNER = 'scripts/sql/the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql';

const DUTIES = {
  'marketing.month_plan': 'fn_marketing_month_plan_duty',
  'marketing.geo_check': 'fn_marketing_geo_check_duty',
  'marketing.article_release': 'fn_marketing_article_release_duty',
  'marketing.launch_plan': 'fn_marketing_launch_plan_duty',
  'marketing.competitor_refresh': 'fn_marketing_competitor_refresh_duty',
};

test('each marketing duty is registered in seat_duty with a routine its file defines', () => {
  const sql = read(OWNER);
  const reg = sql.slice(sql.indexOf('insert into public.seat_duty'));
  for (const [duty, fn] of Object.entries(DUTIES)) {
    assert.match(reg, new RegExp(`\\('${duty.replace('.', '\\.')}', 'marketing', interval '[^']+', '${fn}'`), `${duty} is not registered`);
    assert.match(sql, new RegExp(`create or replace function public\\.${fn}\\(\\)\\s+returns jsonb`), `${fn}() is not defined`);
    assert.match(sql, new RegExp(`revoke execute on function public\\.${fn}\\(\\) from public, anon, authenticated`), `${fn}() is not revoked`);
  }
});

test('only the founder approves an article, and releases happen on a working day', () => {
  const sql = read(OWNER);
  assert.match(sql, /if p_by is distinct from 'founder' then return/);
  assert.match(sql, /where status = 'approved' and approved_by = 'founder' and not is_demo order by approved_at/);
  assert.match(sql, /if not public\.fn_is_working_day\(v_now::date\) then/);
});

test('the launch plan is re-sent only when it changed, carries his changes, and an empty reply changes nothing', () => {
  const sql = read(OWNER);
  // review of #1039: change_requested alone re-mailed the same plan every day with a new token
  assert.match(sql, /and \(d\.status = 'draft' or \(d\.status = 'change_requested' and v_hash is distinct from d\.sent_hash\)\)/);
  assert.match(sql, /founder_changes = founder_changes \|\| to_jsonb\(/);
  assert.match(sql, /'founder_changes', v_changes,/);
  assert.match(sql, /elsif btrim\(coalesce\(p->>'text', ''\)\) = '' then\s+-- an empty reply is not a change/);
});

test('his reply to approve+<token> reaches fn_marketing_approval_reply', () => {
  const inbound = read('supabase/functions/resend_inbound/index.ts');
  assert.match(inbound, /approvalTokenOf\(\{ to, subject \}\)/);
  assert.match(inbound, /rpc\('fn_marketing_approval_reply'/);
});

test('GEO asks the answer engines, and every new route is held like the rest', () => {
  const sql = read(OWNER);
  assert.match(sql, /values \('answer_search'\), \('answer_online'\)/);
  assert.match(sql, /\('marketing_geo_search', 'small', 'perplexity\/sonar'/);
  assert.match(sql, /insert into public\.llm_route_health \(model_id, open_until, opened_reason, updated_at\)/);
  assert.doesNotMatch(sql, /set open_until = null/);
  const duty = read('supabase/functions/marketing/duties.ts');
  assert.match(duty, /if \(await modelHeld\(ctx\.admin\)\) return \{ due: false, held: true/);
  assert.doesNotMatch(duty, /duckSearch\(/);
});

test('no blog link points at quotesdone.com', () => {
  assert.doesNotMatch(read('src/content/blog.json'), /https?:\/\/(www\.)?quotesdone\.com/);
  assert.match(read('supabase/functions/_shared/marketing_outreach.ts'), /export const SITE = 'https:\/\/quotesdone\.ae'/);
  const studio = read(OWNER).match(/CREATE OR REPLACE FUNCTION public\.fn_marketing_studio\(\)[\s\S]*?\$function\$;/)[0];
  assert.doesNotMatch(studio, /quotesdone\.com/);
});
