// THE BACKUPS ARE HELD TO A STATED RPO AND RTO, THE DRILL IS WEEKLY, AND ROTATION AGE IS WATCHED.
//
// scripts/sql/the_backups_are_held_to_a_stated_rpo_and_rto_and_a_credential_past_its_rotation_age_is_raised.sql
// scripts/sql/the_it_engineer_reviews_capacity_and_code_health_every_month.sql
//
// Runs both files and their routines inside ONE transaction that ends in raise exception 'CHK<<...>>', so
// nothing is kept (no threshold, no duty, no finding, no scratch schema). Fails when (the 28 Sep 2026 gap):
//   1. no RPO/RTO target is recorded, or the restore drill is not weekly, or the duties are not scheduled;
//   2. a drill that last ran 13 days ago and never restored a row is NOT raised as stale / RTO unproven;
//   3. a credential past its rotation age is not raised;
//   4. the full-database compare does not see an equal copy as equal and a changed row as a mismatch,
//      or accepts 'public' as the restore schema;
//   5. the monthly capacity and code-health reviews do not run.
//
//   node --test scripts/checks/the_backups_are_held_to_a_stated_rpo_and_rto.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const ddl = [
  'scripts/sql/the_backups_are_held_to_a_stated_rpo_and_rto_and_a_credential_past_its_rotation_age_is_raised.sql',
  'scripts/sql/the_it_engineer_reviews_capacity_and_code_health_every_month.sql',
].map(f => readFileSync(join(REPO, f), 'utf8').split('\n-- PROBE')[0]).join('\n');

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('targets, weekly drill, RPO/RTO misses, rotation age, full-restore compare, monthly reviews', { skip: hasToken ? false : 'no management token' }, async () => {
  const body = `do $p$ declare o jsonb := '{}'; r jsonb; refused boolean := false; begin
      o := o || jsonb_build_object(
        'targets', (select count(*) from public.it_threshold where key in ('backup_rpo_hours','backup_rto_hours','restore_drill_every_days')),
        'drill_every_days', (select extract(day from every) from public.it_duty_schedule where duty = 'restore_table'),
        'duties', (select count(*) from public.seat_duty where enabled and duty in ('it_engineer.backup_objectives',
                     'it_engineer.credential_rotation_age','it_engineer.dr_review','it_engineer.capacity_review','it_engineer.code_health')));
      r := public.fn_it_engineer_backup_objectives();
      o := o || jsonb_build_object('bo', r, 'bo_keys', (select jsonb_agg(issue_key) from public.it_engineer_finding
                                      where closed_at is null and issue_key like 'duty:backup\\_objectives:%'));
      update public.it_threshold set value = -30 where key = 'credential_rotate_days';
      r := public.fn_it_engineer_credential_rotation_age();
      o := o || jsonb_build_object('rot_overdue', r->'overdue');
      create schema zz_restore_probe;
      create table zz_restore_probe.it_threshold as select * from public.it_threshold;
      o := o || jsonb_build_object('equal', public.fn_it_full_restore_compare('zz_restore_probe', array['it_threshold'])->'mismatched');
      update zz_restore_probe.it_threshold set value = value + 1 where key = 'backup_rpo_hours';
      o := o || jsonb_build_object('changed', public.fn_it_full_restore_compare('zz_restore_probe', array['it_threshold'])->'mismatched');
      begin perform public.fn_it_full_restore_compare('public'); exception when others then refused := true; end;
      o := o || jsonb_build_object('public_refused', refused,
                                   'dr', public.fn_it_engineer_dr_review()->'settled'->'failing',
                                   'cap', public.fn_it_engineer_capacity_review()->'db_bytes',
                                   'code', public.fn_it_engineer_code_health()->'unpinned');
      raise exception 'CHK<<%>>', o;
    end $p$;`;
  let r;
  try { await sql('begin;\n' + ddl + '\n' + body); } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    r = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(r, 'the probe must end in CHK');
  assert.equal(Number(r.targets), 3, 'RPO, RTO and drill cadence are recorded');
  assert.ok(Number(r.drill_every_days) <= 7, 'the restore drill is weekly');
  assert.equal(Number(r.duties), 5, 'all five seat duties are scheduled');
  assert.ok(r.bo?.rpo?.target_hours != null && r.bo?.rpo?.hours_since_export != null, JSON.stringify(r.bo));
  const keys = r.bo_keys ?? [];
  // Production on 28 Sep: last drill 15 Sep, none ever restored a row. Both must be raised.
  assert.ok(keys.includes('duty:backup_objectives:drill_stale'), JSON.stringify(keys));
  assert.ok(keys.includes('duty:backup_objectives:rto_unproven'), JSON.stringify(keys));
  assert.ok(Number(r.rot_overdue) > 0, 'a credential past its rotation age is raised');
  assert.equal(Number(r.equal), 0, 'an identical restored table compares equal');
  assert.equal(Number(r.changed), 1, 'a changed restored row is a mismatch');
  assert.equal(r.public_refused, true, "'public' is never accepted as the restore schema");
  assert.ok(Number(r.dr) >= 1, 'no full restore ever -> the quarterly DR review raises it');
  assert.ok(Number(r.cap) > 0);
  assert.equal(Number(r.code), 0);
});
