// MARKETING WATCHES TRENDS, AUDITS GEO AND REVIEWS THE BRAND (marketing, 24 Sep 2026; ledger 983, GAPS.md marketing 3, 5, 7, 8).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * a trend's relevance is decided by anything but think() (a keyword list), or the plan stops reading trends;
//   * trend_watch, geo_audit or reviews drops out of the marketing duty list;
//   * a new table loses RLS + its policy, or a new routine its revoke;
//   * the quarterly review loses the January 2027 customer-launch proposal, or 'marketing.review' is unregistered;
//   * marketing's funnel duty claims the invitation queue again (instr 625);
//   * marketingChannels goes back to more than one live send or heavy phase per beat (the 546 CPU cap).
//   node --test scripts/checks/marketing_watches_trends_audits_geo_and_reviews_the_brand.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const SQL = read('scripts/sql/marketing_watches_trends_audits_answer_engines_and_reviews_the_brand_each_quarter.sql');
const code = (t) => t.split('\n').filter((l) => !/^\s*(\/\/|--)/.test(l)).join('\n');

test('trend relevance is reasoned by think(), and the plan reads the trends', () => {
  const d = code(read('supabase/functions/marketing/duties.ts'));
  assert.ok(d.includes("surface: 'marketing.trend_relevance'") && d.includes('await think(deps'), 'trend relevance is not asked of think()');
  assert.ok(/profileText, trendWatch, geoAudit, reviews,/.test(d), 'a new duty is missing from DUTIES');
  assert.ok(code(read('supabase/functions/_shared/marketing_judgement.ts')).includes("rpc('fn_marketing_trends_for_plan'"), 'the plan no longer reads trends');
});

test('every new table has RLS and a policy; every new routine is revoked', () => {
  const s = code(SQL);
  for (const [, t] of s.matchAll(/create table if not exists public\.(\w+)/g)) {
    assert.ok(s.includes(`alter table public.${t} enable row level security`), `${t}: no RLS`);
    assert.ok(new RegExp(`create policy \\w+ on public\\.${t} `).test(s), `${t}: no policy`);
  }
  for (const [, f] of s.matchAll(/create or replace function public\.(\w+)\(/g)) {
    assert.ok(new RegExp(`revoke execute on function public\\.${f}\\(`).test(s), `${f}: no revoke`);
  }
  assert.ok(!/^\s*(begin|commit)\s*;/im.test(s), 'the applier runs the file as one transaction');
  assert.ok(s.includes("select verdict from _marketing_trend_probe"), 'the probe must end with a verdict row');
});

test('the quarterly review carries the January 2027 launch proposal and goes to the CEO', () => {
  assert.ok(SQL.includes("'customer_launch_2027'") && SQL.includes("'decision_owner', 'ceo'"));
  assert.ok(/\('marketing\.review', 'marketing', 'ceo',/.test(SQL), 'marketing.review is not a registered handoff kind');
});

test('marketing does not own the supplier invitation (instr 625)', () => {
  const owning = read('scripts/sql/marketing_recruits_where_supply_is_short_and_keeps_the_companys_reputation.sql');
  for (const t of [owning, SQL]) assert.ok(!/its leads go first in the invitation queue; an empty pool/.test(t), 'the funnel duty claims the invitation queue');
});

test('marketingChannels does one heavy phase per beat (gap 1)', () => {
  const f = code(read('supabase/functions/marketing_channels/index.ts'));
  assert.ok(f.includes('>= MAX_LIVE_PER_BEAT) break;'), 'publishDue is not capped per beat');
  assert.ok(f.includes('const spent = publishSpentTheBeat('), 'a send no longer ends the beat');
  assert.ok(f.includes('.slice(0, 1)) out[r.campaign_key] = await calendarSend('), 'more than one calendar render per beat');
});
