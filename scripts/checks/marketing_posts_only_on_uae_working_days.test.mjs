// MARKETING POSTS ONLY ON UAE WORKING DAYS, AND ONE "APPROVE" PUBLISHES (marketing, 24 Sep 2026).
//
// Founder, 24 Sep 2026: never post on the UAE weekend (Saturday, Sunday) or an official public holiday; a post that
// lands on one moves to the next working day. And: "It should be one shot. I say approve... it's done."
// This holds, offline:
//   1. every post in every docs/marketing/YYYY-MM_social_calendar.json is on a working day (the holidays are read
//      from the SQL that loads public.public_holidays, so a holiday added there is checked here too);
//   2. the database moves a blocked-day post (the a05 trigger) and the publish gate refuses one as a backstop;
//   3. the canonical publish gate no longer reads marketing_golive: the founder's approval plus the emergency stop
//      (marketing_publishing_enabled, default on) decide.
// The behaviour itself is run on production, in an aborted transaction, by
// scripts/sql/one_approve_schedules_and_publishes_the_month_on_working_days_probe.sql.
//
//   node --test scripts/checks/marketing_posts_only_on_uae_working_days.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const ONE = read('scripts/sql/one_approve_schedules_and_publishes_the_month_on_working_days.sql');
const HOLIDAY_SQL = [read('supabase/migrations_history/20260711192752_uae_public_holidays_working_days.sql'), ONE].join('\n');
const HOLIDAYS = new Set([...HOLIDAY_SQL.matchAll(/\('(\d{4}-\d{2}-\d{2})',\s*'[^']*(?:''[^']*)*',\s*(?:true|false)\)/g)].map((m) => m[1]));
const code = (s) => s.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
const fnBody = (sql, name) => {
  const i = sql.indexOf('create or replace function public.' + name + '(');
  assert.ok(i >= 0, name + ' is defined');
  return sql.slice(i, sql.indexOf('$fn$;', i));
};

test('the holiday list is read: 2026 and 2027, including the Hijri-calendar days of 2027', () => {
  for (const d of ['2026-01-01', '2026-03-20', '2026-05-27', '2026-12-02', '2027-03-10', '2027-05-16', '2027-12-03']) {
    assert.ok(HOLIDAYS.has(d), d + ' is a UAE public holiday in the SQL');
  }
});

test('every calendar post is on a UAE working day', () => {
  const files = readdirSync(join(REPO, 'docs/marketing')).filter((f) => /^\d{4}-\d{2}_social_calendar\.json$/.test(f));
  assert.ok(files.length > 0, 'at least one calendar file');
  for (const f of files) {
    const cal = JSON.parse(read('docs/marketing/' + f));
    for (const p of cal.posts) {
      const day = p.at_dubai.slice(0, 10);
      const dow = new Date(day + 'T12:00:00Z').getUTCDay();   // 0 Sunday .. 6 Saturday
      assert.ok(dow !== 0 && dow !== 6, `${f} ${p.key}: ${day} is a weekend day`);
      assert.ok(!HOLIDAYS.has(day), `${f} ${p.key}: ${day} is a UAE public holiday`);
      assert.equal(new Date(p.at_dubai + '+04:00').toISOString().replace('.000Z', 'Z'), p.at_utc, `${f} ${p.key}: at_utc must be at_dubai in UTC`);
    }
  }
});

test('the first calendar starts on Friday 25 Sep 2026 and nothing in it says October', () => {
  const cal = JSON.parse(read('docs/marketing/2026-09_social_calendar.json'));
  const days = [...new Set(cal.posts.map((p) => p.at_dubai.slice(0, 10)))].sort();
  assert.equal(days[0], '2026-09-25');
  assert.equal(days.length, 12, 'twelve video days');
  assert.equal(cal.posts.length, 70, '12 days x 6 channels, less X on the two days before X was added (channels_not_planned)');
  assert.doesNotMatch(JSON.stringify(cal.campaign) + cal.posts.map((p) => p.key).join(','), /october|oct26/i);
});

test('the database moves a blocked-day post and the gate refuses one', () => {
  const c = code(ONE);
  assert.match(c, /create trigger a05_marketing_post_on_a_working_day before insert or update of scheduled_at, status on public\.marketing_post/);
  assert.match(fnBody(c, 'fn_marketing_next_working_slot'), /while not public\.fn_is_working_day\(\(v at time zone 'Asia\/Dubai'\)::date\) loop/);
  assert.match(c, /create trigger public_holidays_move_the_posts after insert or update of holiday_date on public\.public_holidays/);
  assert.match(fnBody(c, 'fn_marketing_post_publish_refusal'), /if not public\.fn_is_working_day\(\(p\.scheduled_at at time zone 'Asia\/Dubai'\)::date\) then/);
});

test('one approve publishes: no marketing_golive in the gate, the emergency stop defaults on', () => {
  const gate = fnBody(code(ONE), 'fn_marketing_post_publish_refusal');
  assert.doesNotMatch(gate, /marketing_golive/, 'the calendar gate must not need a second go switch');
  assert.match(gate, /if not public\.fn_marketing_publishing_on\(\) then/);
  assert.match(fnBody(code(ONE), 'fn_marketing_publishing_on'), /'marketing_publishing_enabled'\), 'true'\) <> 'false'/, 'missing means on');
  // the canonical definition is the LAST file in MANIFEST order that defines the gate; this file must be after the old one
  const manifest = read('scripts/sql/MANIFEST.txt');
  const pending = readdirSync(join(REPO, 'scripts/sql/pending'));
  const inManifest = manifest.includes('scripts/sql/one_approve_schedules_and_publishes_the_month_on_working_days.sql');
  assert.ok(inManifest || pending.includes('one_approve_schedules_and_publishes_the_month_on_working_days.txt'), 'applied (MANIFEST) or pending with a note');
  const fn = read('supabase/functions/marketing_channels/index.ts');
  assert.match(fn, /publishing: String\(s\.marketing_publishing_enabled \?\? 'true'\)\.trim\(\)\.toLowerCase\(\) !== 'false'/);
});
