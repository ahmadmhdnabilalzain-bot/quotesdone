// LINKEDIN IS NEVER AUTOMATED, AND THE SEAT'S LIST REACHES THE FOUNDER ONLY BEHIND THE SWITCH (marketing, 22 Sep 2026).
//
// Founder, instruction 722: the marketing seat messages two or three LinkedIn connections a day and "no one
// should feel he is an agent". LinkedIn's User Agreement 8.2 forbids bots, automated messaging and scraping,
// and a restricted account would be the FOUNDER'S personal one. The build therefore drafts and he sends. Every
// GitHub tool assessed for sending (browser-session drivers, Voyager-API clients, hosted "LinkedIn MCP"
// servers) works by automating a member session, so none is installed. This check FAILS if that comes back:
//
//   1. any non-test code under supabase/functions, src or scripts names a LinkedIn member API, the private
//      Voyager API, or drives a browser at linkedin.com (the company-page posts go through Postiz, #834);
//   2. the morning list is sent by anything other than fn_marketing_outreach_deliver, or that routine, or the
//      article cadence, stops reading the one switch (fn_marketing_publishing_live) before acting;
//   3. the edge function writes a founder notification itself instead of through that routine.
//
//   node --test scripts/checks/linkedin_is_never_automated.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (f) => readFileSync(join(REPO, f), 'utf8');
// Assembled, so this file cannot match its own scan.
const LI = 'linked' + 'in';
const MEMBER_API = new RegExp([`api\\.${LI}\\.com`, `${LI}\\.com/voyager`, `${LI}_api`, `${LI}-api`, `from ['"]${LI}`].join('|'), 'i');
const BROWSER = /puppeteer|playwright|selenium|webdriver|chromium\.launch/i;

function* walk(dir) {
  if (!existsSync(dir)) return;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name.startsWith('.') || e.name === 'vendor') continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) yield* walk(p);
    else if (/\.(ts|tsx|mjs|js|py)$/.test(e.name) && !/\.(test|spec)\./.test(e.name)) yield p;
  }
}

test('no code talks to LinkedIn as a member or drives a browser at it', () => {
  const hits = [];
  for (const root of ['supabase/functions', 'src', 'scripts']) {
    for (const f of walk(join(REPO, root))) {
      const rel = relative(REPO, f).split(sep).join('/');
      if (rel.startsWith('scripts/checks/')) continue;
      const body = readFileSync(f, 'utf8');
      if (MEMBER_API.test(body)) hits.push(`${rel}: names a LinkedIn member/Voyager API`);
      if (BROWSER.test(body) && new RegExp(`${LI}\\.com`, 'i').test(body)) hits.push(`${rel}: drives a browser and names ${LI}.com`);
    }
  }
  assert.deepEqual(hits, [], 'LinkedIn outreach is drafted for the founder to send by hand (instruction 722, User Agreement 8.2)');
});

const SQL = 'scripts/sql/the_marketing_seat_writes_articles_and_drafts_linkedin_outreach.sql';
const body = (fn) => {
  const s = read(SQL);
  const at = s.indexOf(`function public.${fn}(`);
  assert.ok(at > 0, `${fn} is not defined in ${SQL}`);
  return s.slice(at, s.indexOf('$fn$;', at));
};

test('the morning list and the article cadence read the switch before acting', () => {
  const deliver = body('fn_marketing_outreach_deliver');
  assert.ok(deliver.indexOf('fn_marketing_publishing_live()') > 0 && deliver.indexOf('fn_marketing_publishing_live()') < deliver.indexOf('fn_notify_founder('),
    'fn_marketing_outreach_deliver must check the switch before it notifies the founder');
  assert.match(deliver, /not is_demo/, 'a ZZ DEMO message is never emailed');
  const release = body('fn_marketing_article_release_due');
  assert.ok(release.indexOf('fn_marketing_publishing_live()') > 0 && release.indexOf('fn_marketing_publishing_live()') < release.indexOf("status = 'released'"),
    'fn_marketing_article_release_due must check the switch before it releases');
  const record = body('fn_marketing_outreach_record');
  assert.match(record, /when v_live and not p\.is_demo then 'listed' else 'draft'/, 'held or demo lists stay drafts');
  assert.match(body('fn_marketing_publishing_live'), /key = 'marketing_golive'/);
});

test('the edge function sends nothing to the founder except through the routine', () => {
  const fn = read('supabase/functions/marketing_outreach/index.ts');
  assert.doesNotMatch(fn, /fn_notify_founder|from\('notifications'\)|resend|twilio/i);
  assert.match(fn, /fn_marketing_outreach_deliver/);
});
