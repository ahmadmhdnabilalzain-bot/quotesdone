// THE MARKETING SEAT NEVER POSTS OR SPENDS BY DEFAULT (marketing, 22 Sep 2026).
//
// The build rule for the marketing seat: nothing posts publicly and no ad money is spent until the founder
// turns it on. The behaviour is proved with mock HTTP in supabase/functions/_shared/marketing_channels.test.ts;
// this check holds the WIRING those tests cannot see, so a later edit cannot quietly route around them:
//   1. the edge function publishes live only when the database's verdict (the founder's approval of exactly
//      this content) lets it, the emergency stop app_secrets.marketing_publishing_enabled is not 'false'
//      (default on since 24 Sep 2026: one "approve" publishes), AND the post is not a ZZ DEMO post;
//   2. the only writes to the outside world are Postiz's /upload and /posts inside publishPost, after the
//      dry-run return -- nothing POSTs to Graph, so no campaign, ad set or budget can be touched;
//   3. the ad spend never reaches the ledger: the marketing SQL books nothing, a demo row is never handed
//      off, and the accountant's handler refuses a demo or unmarked amount.
//
//   node --test scripts/checks/marketing_never_posts_or_spends_by_default.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FN = read('supabase/functions/marketing_channels/index.ts');
const LIB = read('supabase/functions/_shared/marketing_channels.ts');
const SQL = read('scripts/sql/the_marketing_seat_publishes_measures_and_reports_spend.sql');
const MONTH = read('scripts/sql/a_month_of_posts_is_approved_once_and_goes_out_exactly_as_approved.sql');
const code = (s) => s.split('\n').filter((l) => !/^\s*(\/\/|--)/.test(l)).join('\n');

test('live publishing needs the switch, no ZZ DEMO by flag OR text, and the database\'s verdict', () => {
  assert.match(code(FN), /publishing: String\(s\.marketing_publishing_enabled \?\? 'true'\)\.trim\(\)\.toLowerCase\(\) !== 'false'/, 'only an explicit emergency stop holds an approved month');
  assert.match(code(FN), /const demo = p\.is_demo \|\| isDemoText\(/, 'the demo rule must read the text as well as the flag');
  assert.match(code(FN), /const isLive = e\.publishing && !demo && !why;/, 'a demo post, a stopped seat or a refused post must not go live');
  assert.match(code(FN), /publishPost\(fetch, [^\n]*input\(media, cover\), true,/, 'only the claimed path publishes live');
  assert.doesNotMatch(code(LIB), /export function postBody\(/, 'the joined EN+AR body is gone: variants carry the text per platform');
});

test('the database refuses publishing without the founder\'s approval of exactly this content', () => {
  const m = code(MONTH);
  assert.match(m, /create trigger marketing_post_guard_publish before insert or update of status on public\.marketing_post/);
  assert.match(m, /if c\.approved_hash <> public\.fn_marketing_campaign_hash\(c\.id\) then/, 'an edit must void the approval');
  assert.match(m, /check \(is_demo or \(text_en \|\| ' ' \|\| text_ar \|\| ' ' \|\| coalesce\(title, ''\)\) !~\* 'zz\[ _-\]\?demo'\)/, 'ZZ DEMO text needs the flag');
  assert.match(m, /spend_policy\s+text not null default 'organic_only' check \(spend_policy = 'organic_only'\)/, 'organic only');
});

test('the only outside writes are to Postiz: upload and post after the dry-run return, and a cancel\'s delete', () => {
  const lib = code(LIB);
  const writes = [...lib.matchAll(/method:\s*'(POST|PUT|PATCH|DELETE)'/g)];
  assert.equal(writes.length, 3, 'expected Postiz /upload, /posts and DELETE /posts/{id} only');
  const fnStart = lib.indexOf('export async function publishPost(');
  const dryReturn = lib.indexOf("return { mode: 'dry_run'", fnStart);
  const uploadAt = lib.indexOf('async function upload(');
  assert.ok(fnStart > 0 && dryReturn > fnStart, 'publishPost returns the dry run');
  for (const w of writes) {
    const inUpload = w.index > uploadAt && w.index < fnStart;
    const inPublish = w.index > dryReturn && w.index < lib.indexOf('export function postizIds(');
    const inDelete = w[1] === 'DELETE' && w.index > lib.indexOf('export async function deletePostizPost(');
    assert.ok(inUpload || inPublish || inDelete, 'a write outside upload/publishPost/deletePostizPost');
  }
  assert.ok(lib.indexOf('await upload(', dryReturn) > dryReturn && lib.indexOf('await upload(') > dryReturn, 'upload is only called after the dry-run return');
  assert.doesNotMatch(code(FN), /method:\s*'(POST|PUT|PATCH|DELETE)'/, 'the edge function writes to no outside service itself');
  assert.doesNotMatch(lib + FN, /graph[^\n]*method:\s*'POST'/i, 'nothing may POST to Graph');
  assert.doesNotMatch(lib + FN, /\/boost|boost\w*\(|\/(adsets|campaigns)['`?]/i,'nothing in the publish path can buy reach');
});

test('ad spend never reaches the ledger, and demo amounts never reach the accountant', () => {
  const sql = code(SQL);
  assert.doesNotMatch(sql, /insert\s+into\s+public\.(gl_|journal|expense_entries|expenses\b|transactions\b)/i, 'the marketing file must book nothing');
  assert.match(sql, /where s\.account_id = p_account and not s\.is_demo and s\.day < v_today and s\.handed_off_at is null and s\.spend > 0/, 'only closed, non-demo, non-zero days are handed off');
  assert.match(sql, /v_test := coalesce\(\(d->>'test'\)::boolean, false\) or coalesce\(d->>'source_ref', ''\) ~\* 'zz\[ _-\]\?demo';/, 'the accountant marks test money');
  assert.match(sql, /if not v_test then\s+insert into public\.ad_spend_reported/, 'test money never reaches the accountant\'s record');
  assert.match(sql, /'recorded_handoff', p_id/, 'adspend.booked names the adspend.recorded it answers (#836 contract)');
  assert.match(sql, /return jsonb_build_object\('verified', v_ok,/, 'marketing\'s handler returns evidence.verified (#836 contract)');
  assert.match(sql, /p_account is distinct from v_expected_acct or p_business_id is distinct from v_business/, 'an account outside the company is refused');
});
