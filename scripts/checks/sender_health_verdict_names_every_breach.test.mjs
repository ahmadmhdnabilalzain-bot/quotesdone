// SENDER HEALTH: THE DAILY VERDICT NAMES EVERY BREACH, AND A HEALTHY DAY NAMES NONE.
// scripts/sql/sender_health_is_recorded_once_a_day_and_a_breach_is_named.sql
//
// Runs the verdict function AS WRITTEN IN THE FILE, not as deployed: the definition is lifted from
// the .sql, created in pg_temp inside a transaction that ends in raise exception 'CHK<<…>>', so
// nothing commits and the check proves the file before it is applied. It reads the live thresholds.
//
//   node --test scripts/checks/sender_health_verdict_names_every_breach.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';
import { replaySql } from '../lib/safe_replay.mjs';   // a rolled-back probe goes through the replay guard (13 Nov 2026)

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

const src = readFileSync(new URL('../sql/sender_health_is_recorded_once_a_day_and_a_breach_is_named.sql', import.meta.url), 'utf8');
const def = src.match(/create or replace function public\.fn_it_sender_health_verdict[\s\S]*?\$fn\$[\s\S]*?\$fn\$;/)[0]
  .replace('public.fn_it_sender_health_verdict', 'pg_temp.v');

const CASES = {
  complaints_0_5pct: [1000, 0, 5, 'GREEN', 0],
  complaints_0_2pct: [1000, 0, 2, 'GREEN', 0],
  bounces_3pct:      [1000, 30, 0, 'HIGH', 0],
  bounces_1pct:      [1000, 10, 0, 'HIGH', 0],
  below_min_sends:   [10, 5, 5, 'GREEN', 0],
  whatsapp_red:      [1000, 0, 0, 'RED', 0],
  whatsapp_unknown:  [1000, 0, 0, null, 0],
  blocklisted:       [1000, 0, 0, 'GREEN', 1],
};

test('0.5% complaints flags, 0.2% does not; every other breach is named', { skip: SKIP }, async () => {
  const lit = (v) => (v === null ? 'null' : typeof v === 'string' ? `'${v}'` : v);
  const sel = Object.entries(CASES).map(([k, a]) =>
    `'${k}', to_jsonb(pg_temp.v(${a.slice(0, 3).join(', ')}, ${lit(a[3])}::text, ${a[4]}))`).join(', ');
  let got;
  try {
    await replaySql(`do $p$ declare r jsonb; begin
      execute ${'$d$' + def.replace(/;$/, '') + '$d$'};
      select jsonb_build_object(${sel}) into r;
      raise exception 'CHK<<%>>', r; end $p$;`);
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    got = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(got, 'probe committed instead of rolling back');
  assert.deepEqual(got.complaints_0_5pct, ['complaint_rate']);
  assert.deepEqual(got.complaints_0_2pct, []);
  assert.deepEqual(got.bounces_3pct, ['bounce_rate']);
  assert.deepEqual(got.bounces_1pct, []);
  assert.deepEqual(got.below_min_sends, []);
  assert.deepEqual(got.whatsapp_red, ['whatsapp_quality']);
  assert.deepEqual(got.whatsapp_unknown, []);
  assert.deepEqual(got.blocklisted, ['blocklisted']);
});
