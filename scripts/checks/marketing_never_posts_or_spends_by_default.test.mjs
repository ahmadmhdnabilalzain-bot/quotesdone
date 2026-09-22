// THE MARKETING SEAT NEVER POSTS OR SPENDS BY DEFAULT (marketing, 22 Sep 2026).
//
// The build rule for the marketing seat: nothing posts publicly and no ad money is spent until the founder
// turns it on. The behaviour is proved with mock HTTP in supabase/functions/_shared/marketing_channels.test.ts;
// this check holds the WIRING those tests cannot see, so a later edit cannot quietly route around them:
//   1. the edge function publishes live only when app_secrets.marketing_golive reads exactly 'true' AND the
//      post is not a ZZ DEMO post;
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
const code = (s) => s.split('\n').filter((l) => !/^\s*(\/\/|--)/.test(l)).join('\n');

test('live publishing needs marketing_golive to read exactly true, and never applies to a demo post', () => {
  assert.match(code(FN), /golive:\s*String\(s\.marketing_golive \|\| 'false'\)\.toLowerCase\(\) === 'true'/, 'the switch defaults to off');
  assert.match(code(FN), /const isLive = e\.golive && !p\.is_demo;/, 'a demo post or a switched-off seat must not go live');
  assert.match(code(FN), /publishPost\(fetch, [^)]*isLive,/, 'publishPost must receive the gated flag');
});

test('the only outside writes are Postiz upload and post, after the dry-run return', () => {
  const lib = code(LIB);
  const posts = [...lib.matchAll(/method:\s*'(POST|PUT|PATCH|DELETE)'/g)];
  assert.equal(posts.length, 2, 'exactly two writes (Postiz /upload and /posts) are expected in the shared module');
  const fnStart = lib.indexOf('export async function publishPost(');
  const dryReturn = lib.indexOf("return { mode: 'dry_run'", fnStart);
  assert.ok(fnStart > 0 && dryReturn > fnStart, 'publishPost returns the dry run');
  for (const m of posts) assert.ok(m.index > dryReturn && m.index < lib.indexOf('export async function postizReleases('), 'a write outside publishPost, or before its dry-run return');
  assert.doesNotMatch(code(FN), /method:\s*'(POST|PUT|PATCH|DELETE)'/, 'the edge function writes to no outside service itself');
  assert.doesNotMatch(lib + FN, /graph[^\n]*method:\s*'POST'/i, 'nothing may POST to Graph');
});

test('ad spend never reaches the ledger, and demo amounts never reach the accountant', () => {
  const sql = code(SQL);
  assert.doesNotMatch(sql, /insert\s+into\s+public\.(gl_|journal|expense_entries|expenses\b|transactions\b)/i, 'the marketing file must book nothing');
  assert.match(sql, /where s\.account_id = p_account and not s\.is_demo and s\.day < v_today/, 'only closed, non-demo days are handed off');
  assert.match(sql, /if coalesce\(\(a\.detail->>'is_demo'\)::boolean, true\) then/, 'the accountant refuses a demo or unmarked amount');
  assert.match(sql, /p_account is distinct from v_expected_acct or p_business_id is distinct from v_business/, 'an account outside the company is refused');
});
