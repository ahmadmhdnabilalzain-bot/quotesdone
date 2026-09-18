// A CONFIGURATION GAP IS RECORDED ONCE, NOT EVERY TICK.
//
// The regression check for scripts/sql/configuration_that_is_missing_is_recorded_once_not_every_tick.sql.
//
// What it stops coming back: on 18 Sep 2026 two renewal findings had been re-raised 320 times each and
// five provider-cap findings 77-79 times each, because "no cap is recorded" and "the renewal date is not
// known" are facts about the ledger that cannot change between one tick and the next, and the duty
// settler bumped them anyway. And a token whose provider reports NO expiry at all had no way to be
// recorded as such, so the measured fact was dropped hourly and the question was asked again forever.
//
// Against production; every write sits in a transaction that ends in raise exception 'CHK<<…>>', so
// nothing commits. Demo subjects only (ZZ DEMO / zz_demo_*): the probe cannot reach a real finding, a
// real renewal item or a real person.
//
//   node --test scripts/checks/a_configuration_gap_is_recorded_once_not_every_tick.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

async function probe(body) {
  try { await sql(`do $p$ ${body} $p$;`); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (m) return JSON.parse(m[1].replace(/\\"/g, '"'));
    throw e;
  }
  throw new Error('probe committed instead of rolling back');
}

const ITEMS = `jsonb_build_array(
  jsonb_build_object('item', 'cap_unknown:zz_demo_metric', 'owner_seat', 'accountant', 'subject', 'zz_demo',
                     'title', 'ZZ DEMO check: a configuration gap', 'blast', 'internal', 'affected', 0),
  jsonb_build_object('item', 'zz_demo_item:date_unknown', 'owner_seat', 'accountant', 'subject', 'zz_demo',
                     'title', 'ZZ DEMO check: a date nobody has recorded', 'blast', 'internal', 'affected', 0),
  jsonb_build_object('item', 'zz_demo_ordinary', 'owner_seat', 'accountant', 'subject', 'zz_demo',
                     'title', 'ZZ DEMO check: an ordinary failing item', 'blast', 'internal', 'affected', 0))`;

test('a configuration finding is recorded once and stays open; an ordinary one keeps counting',
  { skip: SKIP }, async () => {
  const r = await probe(`
    declare i int; v jsonb;
    begin
      for i in 1..3 loop perform public.fn_it_duty_settle('zz_demo_cfg', ${ITEMS}); end loop;
      select jsonb_object_agg(replace(issue_key, 'duty:zz_demo_cfg:', ''),
                              jsonb_build_object('seen', seen_count, 'open', closed_at is null,
                                                 'refreshed', evidence ? 'reading_refreshed_at'))
        into v from public.it_engineer_finding where issue_key like 'duty:zz_demo_cfg:%';
      delete from public.it_engineer_finding where issue_key like 'duty:zz_demo_cfg:%';
      raise exception 'CHK<<%>>', v::text;
    end`);
  assert.equal(r['cap_unknown:zz_demo_metric'].seen, 1, 'a missing cap was re-raised by a later tick');
  assert.equal(r['zz_demo_item:date_unknown'].seen, 1, 'a missing date was re-raised by a later tick');
  assert.equal(r['zz_demo_ordinary'].seen, 3, 'an ordinary failing item stopped counting its recurrences');
  // One-shot must never mean closed-and-forgotten: the gap is still open until somebody fills it.
  for (const k of Object.keys(r)) assert.equal(r[k].open, true, `${k} was closed by its own duty`);
  // Held, but not frozen: the measurement inside a held finding is still today's.
  assert.equal(r['cap_unknown:zz_demo_metric'].refreshed, true, 'a held finding kept a stale reading');
  assert.equal(r['zz_demo_ordinary'].refreshed, false, 'an ordinary finding was marked as held');
});

test('a provider that reports no expiry at all settles its row, and a real date takes over',
  { skip: SKIP }, async () => {
  const r = await probe(`
    declare v jsonb;
    begin
      insert into public.it_expiry (item, kind, expires_on, owner_seat, route, source)
      values ('ZZ DEMO token:check', 'token', null, 'accountant', 'ZZ DEMO check', 'ZZ DEMO check');
      perform public.fn_it_expiry_measured(jsonb_build_object(
        'ZZ DEMO token:check', jsonb_build_object('basis', 'measured', 'never_expires', true)));
      select jsonb_build_object('never', never_expires, 'date', expires_on,
                                'in_watch', (kind <> 'tls' and not never_expires)) into v
        from public.it_expiry where item = 'ZZ DEMO token:check';
      perform public.fn_it_expiry_measured(jsonb_build_object(
        'ZZ DEMO token:check', jsonb_build_object('basis', 'measured', 'expires_on', '2030-01-01')));
      select v || jsonb_build_object('after_date_never', never_expires, 'after_date', expires_on) into v
        from public.it_expiry where item = 'ZZ DEMO token:check';
      -- a reading that was not taken must clear nothing
      perform public.fn_it_expiry_measured(jsonb_build_object(
        'ZZ DEMO token:check', jsonb_build_object('basis', 'unavailable', 'reason', 'ZZ DEMO check')));
      select v || jsonb_build_object('after_unread', expires_on) into v
        from public.it_expiry where item = 'ZZ DEMO token:check';
      delete from public.it_expiry where item = 'ZZ DEMO token:check';
      raise exception 'CHK<<%>>', v::text;
    end`);
  assert.equal(r.never, true, 'a measured "no expiry" reading did not settle the row');
  assert.equal(r.date, null, 'a never-expiring item was given a date');
  assert.equal(r.in_watch, false, 'a never-expiring item is still inside the renewal warning loop');
  assert.equal(r.after_date_never, false, 'a real expiry date did not take over from never_expires');
  assert.equal(r.after_date, '2030-01-01', 'a measured date was not stored');
  assert.equal(r.after_unread, '2030-01-01', 'a reading that was not taken cleared a real date');
});

test('every provider cap that is still unrecorded names the seat that must record it',
  { skip: SKIP }, async () => {
  // Not a guess-detector: it only insists that a null cap says so out loud, so "no cap" can never be
  // mistaken for "measured and fine". A cap with a value must say who set it and from what.
  const rows = await sql(`select key, value, basis from public.it_threshold
                           where key ~ '^(cap|floor)_' and key <> 'cap_warn_ratio' order by key`);
  assert.ok(rows.length > 0, 'the provider cap rows have gone from it_threshold');
  for (const r of rows) {
    if (r.value === null) {
      assert.match(String(r.basis), /not recorded/i, `${r.key} is null and does not say it is not recorded`);
    } else {
      assert.match(String(r.basis), /set by the|includes|plan/i, `${r.key} has a value and no provenance`);
    }
  }
});
