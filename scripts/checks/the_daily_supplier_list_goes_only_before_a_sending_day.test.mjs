// THE 18:00 SUPPLIER LIST GOES ONLY BEFORE A SENDING DAY, SHOWS THE DAY-1 VOLUME, AND A COMPANY IS INVITED ONCE
// (marketing, 24 Sep 2026, ledger 993). Fails if any of the three fixes in
// scripts/sql/the_daily_supplier_list_goes_only_before_a_sending_day_and_a_company_is_invited_once.sql is undone:
//   1. the tick returns not-due when tomorrow is held (weekend or company_calendar public holiday);
//   2. the list sizes a cold-domain day at invite_warmup.base_cap, as fn_invite_ramp will;
//   3. the selection keeps one lead per company key and skips a company already invited.
// Behaviour was run on production in a rolled-back transaction (Fri/Sat 18:05 not due, Sun 18:05 due, 30 listed).
//
//   node --test scripts/checks/the_daily_supplier_list_goes_only_before_a_sending_day.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const code = (s) => s.split('\n').filter((l) => !/^\s*(--|\/\/)/.test(l)).join('\n');
const SQL = code(readFileSync(join(REPO, 'scripts/sql/the_daily_supplier_list_goes_only_before_a_sending_day_and_a_company_is_invited_once.sql'), 'utf8'));
const body = (name) => {
  const i = SQL.indexOf('create or replace function public.' + name + '(');
  assert.ok(i >= 0, name + ' is defined');
  return SQL.slice(i, SQL.indexOf('$fn$;', i));
};

test('the email goes only on the evening before a sending day, and the gate precedes any write', () => {
  const tick = body('fn_customer_support_campaign_list_tick');
  const gate = tick.indexOf('fn_supplier_invites_hold_reason(v_local::date + 1) is not null');
  assert.ok(gate > 0, 'tomorrow is checked');
  assert.ok(gate < tick.indexOf('insert into public.supplier_campaign_daily_list'), 'before the row is built');
  assert.match(tick.slice(gate, gate + 300), /'due', false/);
});

test('a cold domain is listed at the warm-up base cap, as fn_invite_ramp will set it', () => {
  const next = body('fn_supplier_campaign_next_list');
  assert.match(next, /max\(l\.invited_at\)/);
  assert.match(next, /interval '3 days'/);
  assert.match(next, /'base_cap'\)::int from public\.app_secrets where key = 'invite_warmup'\), 30\)/);
});

test('one invitation per company: best contact per key, and never a company already invited', () => {
  const c = body('fn_supplier_invite_candidates');
  assert.match(c, /r\.company_rk = 1 and r\.name_rk = 1/);
  assert.match(c, /partition by p\.dkey order by p\.unverified_rank, p\.role_rank, p\.id/);
  assert.match(c, /not exists \(select 1 from touched_d t where t\.dkey = k\.dkey\)/);
  assert.match(c, /not exists \(select 1 from touched_n t where t\.nkey = k\.nkey\)/);
  assert.match(c, /l\.invite_status is not null or l\.invited_at is not null/);
});

test('never an address on a known platform domain, unless it is the lead\'s own website; exact domain, no words', () => {
  const e = body('fn_supplier_invite_eligible');
  assert.match(e, /from public\.email_platform_domain d\s+where d\.domain = split_part\(lower\(btrim\(p\.email\)\), '@', 2\)/);
  assert.match(e, /d\.domain is distinct from lower\(regexp_replace\(regexp_replace\(btrim\(coalesce\(nullif\(btrim\(p\.website\), ''\), p\.maps_website/);
  assert.doesNotMatch(e.slice(e.indexOf('email_platform_domain')), /~\*?\s*'|ilike|like '%/);
  assert.match(SQL, /\('buildclub\.com', 'marketplace'/);
  assert.match(SQL, /\('hub\.com', 'directory'/);
  assert.match(SQL, /create policy email_platform_domain_service_role_only/);
});

test('invitations leave from 10:00 Dubai and the 18:00 email states the window from the same setting', () => {
  assert.match(SQL, /jsonb_set\(nullif\(value, ''\)::jsonb, '\{window_start_hour\}', '10'::jsonb\)/);
  const tick = body('fn_customer_support_campaign_list_tick');
  assert.match(tick, /'window_start_hour'\)::int, 9\), 0, 0\), 'HH24:MI'\)/);
  assert.match(tick, /', sent from ' \|\| v_win/);
});
