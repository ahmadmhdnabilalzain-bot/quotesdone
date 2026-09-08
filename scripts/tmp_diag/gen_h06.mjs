// H06 generator: fn_phase_d_drive_workflow — a run the scenario's own arrival started before the
// scenario was complete gets its open step dispatched again, through the same kernel door.
import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const HEAD = `-- H06 — the scenario's own arrival started the run before the scenario was finished building
--
-- MEASURED 23 Aug 2026, and it took an instrumented probe to see. The scenario factory inserts a
-- quotation at stage 150. public.quotes carries a product trigger that submits a kernel arrival,
-- and fn_kernel_workflow_start opened a W14 run and dispatched W14-S01 at that instant -- before
-- stages 160 (quotation_revision) and 170 (quotation_comparison) had run. BR-018 and BR-019 then
-- refused W14-S01 for want of a revision and a comparison that did not yet exist, which was true.
-- The same factory inserts an inquiry at stage 30 (W05 started, S01 executed before the route
-- set, documents and answers existed) and a transaction at stage 190 (W16 started before the
-- provider event, reconciliation case and reveal existed).
--
-- When this driver then called fn_kernel_workflow_start for the same business object, the kernel
-- answered duplicate = true with the run the trigger had opened, and this driver carried on with a
-- run whose first dispatch had been made against half a world. Re-dispatching W14-S01 a few
-- statements later, with the scenario complete, EXECUTED -- measured with the same step run, same
-- transaction, same idempotency key.
--
-- Nothing is bypassed and no new key is invented: when the kernel reports the run pre-existed, the
-- open step run whose latest dispatch was a refusal is dispatched once more through
-- fn_phase_d_dispatch_step with the KERNEL'S OWN idempotency key for that step, opened_by_kind
-- 'scenario_complete'. The premature dispatch row stays on the table -- it is a true record of the
-- product starting the workflow on the arrival -- and the return object says
-- premature_arrival_run = true and how many steps were re-dispatched, so a reader can tell a run
-- the driver started from one the product started.
--
-- In production the same trigger fires on a real supplier's quote and the same rule refuses until a
-- revision exists; that is the rule being conservative about a quotation window with no quotation
-- in it, and it is not changed here.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_drive_workflow (phase_d_g07 is the last file
-- that defines it). No DDL.
--
-- Three anchors, each required to match exactly once. The rest of the routine is byte-identical.`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_drive_workflow'`);
let def = r[0].def;
const once = (anchor, label) => { const n = def.split(anchor).length - 1; if (n !== 1) throw new Error(`${label}: anchor matched ${n} times`); };

const a1 = `  v_founder_cmd   bigint := null; -- G05: the fixture founder command this run arises from, where one applies
begin`;
once(a1, 'A1');
def = def.replace(a1, `  v_founder_cmd   bigint := null; -- G05: the fixture founder command this run arises from, where one applies
  v_premature     boolean := false;   -- H06: the kernel reported the run already existed
  v_redispatched  int := 0;           -- H06: open steps dispatched again once the scenario was complete
begin`);

const a2 = `  v_run := (v_start->>'run_id')::bigint;
  if v_run is null then
    return jsonb_build_object('ok', false, 'workflow_id', v_wf,
      'stopped_because', 'the kernel returned no run_id', 'kernel_result', v_start);
  end if;
`;
once(a2, 'A2');
def = def.replace(a2, a2 + `
  -- H06. THE RUN ALREADY EXISTED: the scenario's own arrival started it before the scenario was
  -- complete, and its first dispatch judged half a world. Each open step run whose latest dispatch
  -- was a refusal is dispatched once more, through the same door, under the kernel's own key.
  if coalesce((v_start->>'duplicate')::boolean, false) then
    v_premature := true;
    for sr in select * from public.phase_c_workflow_step_run
               where run_id = v_run
                 and state in ('ready','active','not_ready','waiting_input','waiting_review','blocked')
               order by step_run_id
    loop
      select * into d from public.phase_d_dispatch
       where step_run_id = sr.step_run_id order by dispatch_id desc limit 1;
      if found and d.outcome <> 'EXECUTED' then
        begin
          perform public.fn_phase_d_dispatch_step(jsonb_build_object(
            'step_run_id',     sr.step_run_id,
            'actor_role_id',   sr.accountable_role_id,
            'opened_by_kind',  'scenario_complete',
            'opened_by_ref',   format('the scenario finished after the arrival opened %s', sr.step_id),
            'idempotency_key', (select ws.idempotency_scope from public.phase_b_workflow_step ws
                                 where ws.step_id = sr.step_id) || '|' || v_run || '|' || sr.step_id || '|kernel'));
          v_redispatched := v_redispatched + 1;
        exception when others then null;
        end;
      end if;
    end loop;
  end if;
`);

const a3 = `    'capability_results_accepted', v_capn,`;
once(a3, 'A3');
def = def.replace(a3, `    'capability_results_accepted', v_capn,
    'premature_arrival_run', v_premature,
    'steps_redispatched_after_scenario', v_redispatched,`);

writeFileSync('scripts/sql/phase_d_h06_the_arrival_started_the_run_before_the_scenario_was_built.sql', HEAD + '\n' + def + '\n');
console.log('H06 written');
