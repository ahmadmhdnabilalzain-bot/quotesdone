// THE SECURITY SWEEP TELLS AN OPEN DOOR FROM A SIGNED-IN ONE, AND THE BASELINE ONLY ACCEPTS WITH A REASON.
//
// fn_it_security_exposures (scripts/sql/the_it_engineer_runs_its_duties_every_hour.sql):
//   anon_executable_definer          anon can run a SECURITY DEFINER routine            -> raised
//   authenticated_executable_definer only a signed-in user can, and it never asks who  -> raised
//   a signed-in RPC scoped by auth.uid()/auth.email()/auth.jwt()                        -> not a finding
// and it_security_baseline refuses a row with no reason or nobody named.
// Against production; the probe ends in raise exception 'CHK<<…>>', so nothing commits.
//
//   node --test scripts/checks/it_security_sweep_splits_anon_from_signed_in.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';
import { replaySql } from '../lib/safe_replay.mjs';   // a rolled-back probe goes through the replay guard (13 Nov 2026)

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('anon, signed-in-unscoped and signed-in-scoped definer routines are told apart; a reasonless baseline row is refused', { skip: SKIP }, async () => {
  let res;
  try {
    await replaySql(`do $p$
      declare v_refused boolean := false;
      begin
        create function public.zz_demo_open() returns int language sql security definer set search_path to 'public' as 'select 1';
        create function public.zz_demo_unscoped() returns int language sql security definer set search_path to 'public' as 'select 2';
        create function public.zz_demo_scoped() returns uuid language sql security definer set search_path to 'public' as 'select auth.uid()';
        create function public.zz_demo_delegates() returns uuid language sql security definer set search_path to 'public' as 'select public.zz_demo_scoped()';
        revoke execute on function public.zz_demo_unscoped(), public.zz_demo_scoped(), public.zz_demo_delegates() from public, anon;
        grant execute on function public.zz_demo_unscoped(), public.zz_demo_scoped(), public.zz_demo_delegates() to authenticated;
        grant execute on function public.zz_demo_open() to anon;
        begin
          insert into public.it_security_baseline (object, kind, reason, accepted_by) values ('zz', 'rls_off', '', 'probe');
        exception when others then v_refused := true; end;
        raise exception 'CHK<<%>>', json_build_object(
          'open', (select kind from public.fn_it_security_exposures() where object = 'zz_demo_open()'),
          'unscoped', (select kind from public.fn_it_security_exposures() where object = 'zz_demo_unscoped()'),
          'scoped', (select count(*) from public.fn_it_security_exposures() where object in ('zz_demo_scoped()', 'zz_demo_delegates()')),
          'reasonless_refused', v_refused);
      end $p$;`);
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    res = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(res, 'the probe committed instead of rolling back');
  assert.deepEqual(res, { open: 'anon_executable_definer', unscoped: 'authenticated_executable_definer', scoped: 0, reasonless_refused: true });
});
