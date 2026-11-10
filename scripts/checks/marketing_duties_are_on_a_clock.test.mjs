// THE MARKETING SEAT'S PLAN, GEO, ARTICLE, LAUNCH AND COMPETITOR WORK IS ON A CLOCK (marketing, 28 Sep 2026).
//
// Measured 28 Sep 2026: public.seat_duty held three marketing rows; the monthly plan, the GEO check, the article
// release, the competitor refresh and the January 2027 launch plan had no owner/clock/check row, the 4 article
// drafts had no path to the founder's approval, and the studio's blog links pointed at quotesdone.com.
// This fails when any of the five duties loses its seat_duty row or its routine, when his approval reply stops
// being routed, or when a blog link points at quotesdone.com.
// Since 29 Sep 2026 (founder 1058, 1059; BLOG below) the founder never approves a blog: the assertion that only he
// could approve one is REPLACED, not softened, by the assertions that only the CEO seat can, with six reasons the
// database enforces, at most one a week, and that publishing mails nobody but his FYI.
//
//   node --test scripts/checks/marketing_duties_are_on_a_clock.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { functionModuleSource, functionSource } from '../lib/function_sources.mjs';

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

// ── BLOG (founder 1058, 1059) ──────────────────────────────────────────────────────────────────────────────────
const BLOG = 'scripts/sql/a_blog_article_is_a_market_topic_the_ceo_reviews_until_it_is_useful.sql';
const routine = (sql, fn) => {
  const m = sql.match(new RegExp(`create or replace function public\\.${fn}\\([\\s\\S]*?\\$fn\\$;`));
  assert.ok(m, `${fn} is not defined in ${BLOG}`);
  return m[0];
};

test('only the CEO seat approves a blog, and it is released on a working day, at most one a Dubai week', () => {
  const sql = read(BLOG);
  assert.match(routine(sql, 'fn_marketing_article_approve'), /if p_by is distinct from 'ceo' then return/);
  const rel = routine(sql, 'fn_marketing_article_release_due');
  assert.match(rel, /if not public\.fn_is_working_day\(v_now::date\) then/);
  assert.match(rel, /if v_week >= 1 or v_today > 0 then/);
  assert.match(rel, /where status = 'approved' and approved_by = 'ceo' and kind = 'market_topic' and not is_demo/);
  assert.match(rel, /if not public\.fn_marketing_publishing_live\(\) then/);
});

test('a CEO decision without its six reasons is refused by the database, a decided round is never rewritten, and a fifth revise is refused', () => {
  const sql = read(BLOG);
  assert.match(sql, /constraint marketing_article_round_decision_has_its_reasons\s+check \(decision is null or public\.fn_marketing_review_reasons_ok\(decision, reasons\)\)/);
  const ok = routine(sql, 'fn_marketing_review_reasons_ok');
  for (const k of ['useful', 'market_topic_not_quotesdone', 'accurate_grounded', 'no_supplier_named', 'language_quality', 'seo_geo']) assert.ok(ok.includes(`'${k}'`), k);
  assert.match(ok, /when 'approve' then not exists \(select 1 from jsonb_each\(p_reasons\) r where r\.value->>'verdict' <> 'pass'\)/);
  const guard = routine(sql, 'fn_marketing_article_round_guard');
  assert.match(guard, /its history is never overwritten/);
  assert.match(guard, />= 4 then\s+raise exception 'after 4 revise rounds/);
  assert.match(guard, /the revision does not say what changed for the CEO''s reason\(s\)/);
});

test('publishing a blog mails nobody but the founder\'s FYI, and article approval by him is retired', () => {
  const sql = read(BLOG);
  for (const fn of ['fn_marketing_article_release_due', 'fn_marketing_article_mark_live', 'fn_marketing_article_release_duty',
                    'fn_marketing_blog_submit', 'fn_marketing_blog_review', 'fn_marketing_blog_topic_pick', 'fn_marketing_blog_topic_replace']) {
    const body = routine(sql, fn);
    assert.doesNotMatch(body, /insert into public\.notifications|fn_notify_|send_outbox|fn_enqueue/, `${fn} writes a message`);
    for (const m of body.matchAll(/fn_marketing_mail_founder\('([a-z_]+)'/g)) assert.equal(m[1], 'marketing_article_live', `${fn} mails ${m[1]}`);
  }
  assert.match(routine(sql, 'fn_marketing_article_mark_live'), /fn_marketing_mail_founder\('marketing_article_live',/);
  assert.doesNotMatch(routine(sql, 'fn_marketing_article_mark_live'), /approve\+/);
  assert.match(sql, /\('marketing_article_approval', false,/);
  assert.match(routine(sql, 'fn_marketing_approval_reply'), /return jsonb_build_object\('outcome', 'article_approval_retired'\)/);
  assert.match(sql, /set status = 'withdrawn', withdrawn_at = now\(\), updated_at = now\(\), approval_token = null,/);
});

test('no side door approves or hand-ingests a blog article: the old action and command are gone', () => {
  // the coordinator's review of #1114: a door the database refuses is still a door; it is removed, not relied on
  // comments are stripped first: the headers say, in words, that these doors were removed
  const code = (f) => read(f).replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  const outreach = code('supabase/functions/marketing_outreach/index.ts');
  assert.doesNotMatch(outreach, /['"`](approve_article|ingest_article)['"`]/);
  assert.doesNotMatch(outreach, /fn_marketing_article_(approve|ingest)/);
  const cli = code('scripts/marketing/business_development.mjs');
  assert.doesNotMatch(cli, /['"`](approve|ingest-article|approve_article|ingest_article)['"`]/);
});

test('the three blog model steps are one duty (one call a beat) and record a refusal before raising it', () => {
  const duty = functionModuleSource('marketing/duties');
  assert.match(duty, /reviews, blogArticle,/);
  for (const fn of ['fn_marketing_blog_draft_due', 'fn_marketing_blog_review_due', 'fn_marketing_blog_revise_due', 'fn_marketing_blog_submit', 'fn_marketing_blog_review']) {
    assert.ok(duty.includes(`'${fn}'`), fn);
  }
  const run = duty.slice(duty.indexOf('export async function runOneJob'), duty.indexOf('const dubaiDay'));
  assert.ok(run.indexOf('await io.recordFailed(job, subject, reason, model);') < run.indexOf('throw new Error(job.step'), 'a refusal is raised before it is recorded');
  assert.match(run, /if \(failed\.some\(\(f\) => f\.run_day === today\)\) \{ waiting\.push/);
  assert.match(duty, /taskClass: 'ceo_article_review', max: 4000, counterpart: r\.drafted_by_model/);
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
  const inbound = functionSource('resend_inbound');
  assert.match(inbound, /approvalTokenOf\(\{ to, subject \}\)/);
  assert.match(inbound, /rpc\('fn_marketing_approval_reply'/);
});

test('GEO asks the answer engines, and every new route is held like the rest', () => {
  const sql = read(OWNER);
  assert.match(sql, /values \('answer_search'\), \('answer_online'\)/);
  assert.match(sql, /\('marketing_geo_search', 'small', 'perplexity\/sonar'/);
  assert.match(sql, /insert into public\.llm_route_health \(model_id, open_until, opened_reason, updated_at\)/);
  assert.doesNotMatch(sql, /set open_until = null/);
  const duty = functionModuleSource('marketing/duties');
  assert.match(duty, /if \(await modelHeld\(ctx\.admin\)\) return \{ due: false, held: true/);
  assert.doesNotMatch(duty, /duckSearch\(/);
});

test('no blog link points at quotesdone.com', () => {
  assert.doesNotMatch(read('src/content/blog.json'), /https?:\/\/(www\.)?quotesdone\.com/);
  assert.match(read('supabase/functions/_shared/marketing_outreach.ts'), /export const SITE = 'https:\/\/quotesdone\.ae'/);
  const studio = read(OWNER).match(/CREATE OR REPLACE FUNCTION public\.fn_marketing_studio\(\)[\s\S]*?\$function\$;/)[0];
  assert.doesNotMatch(studio, /quotesdone\.com/);
});
