// H05 generator: fn_phase_d_dispatch_step — an APPEND_ONLY object gets a new key per appending step.
import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const HEAD = `-- H05 — an append-only object was written under the key it had already been written under
--
-- F13 derives the business key a step writes, inside a verified Phase D fixture run, from the
-- record the scenario already created for that object: "this step mutates THAT record". That is
-- right for every MUTABLE_CONTROLLED, CASE_RECORD, VERSIONED and TRANSACTION_RECORD object. It is
-- wrong for an APPEND_ONLY one, whose own policy says "a correction is a NEW key, never a second
-- version of this one" -- and fn_phase_d_object_write says exactly that when it refuses:
--
--     customer_selection is APPEND_ONLY (append_only_decision) and business key <uuid> already
--     holds record <n>. A correction is a NEW key, never a second version of this one.
--
-- Measured 23 Aug 2026 on W15-S05 (customer_selection) and W30-S10 (organization_change_request).
-- The writer is right and is not touched. The dispatch now derives an APPEND_ONLY object's key
-- deterministically from (fixture run, object, run, STEP) -- the same shape F13 uses when the
-- scenario created nothing, with the step added -- so each appending step produces its own record
-- and a replay of the same step run collides with itself. The policy family is read from
-- public.phase_d_business_object_binding, never listed here.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_dispatch_step (phase_d_f37 is the last file
-- that defines it). No DDL.
--
-- One anchor, required to match exactly once. The rest of the routine is byte-identical.`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_dispatch_step'`);
let def = r[0].def;
const once = (anchor, label) => { const n = def.split(anchor).length - 1; if (n !== 1) throw new Error(`${label}: anchor matched ${n} times`); };

const a1 = `    if v_bkey is null and public.fn_phase_d_fixture_context() is not null then
      select coalesce(sc.contributed_value, sc.business_key) into v_bkey
        from public.phase_d_scenario_record sc
       where sc.fixture_run_id = public.fn_phase_d_fixture_context()
         and sc.object_id = (v_cx#>>'{business_object,object_id}')
       order by sc.scenario_record_id limit 1;`;
once(a1, 'A1');
def = def.replace(a1, `    if v_bkey is null and public.fn_phase_d_fixture_context() is not null then
      -- H05. AN APPEND_ONLY OBJECT IS NEVER WRITTEN UNDER THE SCENARIO'S EXISTING KEY. Its policy is
      -- that a correction is a NEW key, so the scenario's record is not "the record this step
      -- mutates" -- this step appends beside it. The key is derived from the step as well as the
      -- run, so each appending step is its own record and a replay of one step run is one record.
      if exists (select 1 from public.phase_d_business_object_binding bb
                  where bb.object_id = (v_cx#>>'{business_object,object_id}')
                    and bb.policy_family = 'APPEND_ONLY') then
        v_bkey := md5(format('phase_d_fixture:%s:%s:%s:%s',
                             public.fn_phase_d_fixture_context(),
                             v_cx#>>'{business_object,object_id}', sr.run_id, sr.step_id))::uuid::text;
      end if;
    end if;
    if v_bkey is null and public.fn_phase_d_fixture_context() is not null then
      select coalesce(sc.contributed_value, sc.business_key) into v_bkey
        from public.phase_d_scenario_record sc
       where sc.fixture_run_id = public.fn_phase_d_fixture_context()
         and sc.object_id = (v_cx#>>'{business_object,object_id}')
       order by sc.scenario_record_id limit 1;`);

writeFileSync('scripts/sql/phase_d_h05_an_append_only_object_written_under_its_own_old_key.sql', HEAD + '\n' + def + '\n');
console.log('H05 written');
