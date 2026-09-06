// Remove the two literal protected-table writes from the O08 branches.
//
// fn_kernel_write_guard_state scans every routine's SOURCE for a write to a protected table and
// counts any routine not in kernel_write_authority. Putting `update public.phase_c_refund_decision`
// and `update public.phase_c_workflow_step_run` inside fn_phase_d_run_injected_defects made that
// board read 3 of 39 where it had read 1. The refusals are real and still asserted — they moved to
// scripts/checks/protected_table_guards_actually_fire.test.mjs, which is not a pg_proc row and so
// is not a writer any board can count. The runner keeps only calls to canonical services.
import { readFileSync, writeFileSync } from 'node:fs';

const p = 'scripts/sql/phase_d_o08_the_nine_that_remained_executed.sql';
let s = readFileSync(p, 'utf8');
let bad = 0;
const rep = (find, repl, label) => {
  const n = s.split(find).length - 1;
  if (n !== 1) { console.error(`ANCHOR ${label}: matched ${n}`); bad++; return; }
  s = s.replace(find, repl);
};

// ---- PD-AUTH-005: drop the maintenance-door arm --------------------------------------------
rep(`      -- and the table boundary itself, forced to fire through the write guard's audited door
      perform set_config('kernel.maintenance_reason','PD-AUTH-005: force the step-run owner guard', true);
      begin
        update public.phase_c_workflow_step_run set accountable_role_id = v_a5_ovl
         where step_run_id = (v_a5_dr->>'held_step_run_id')::bigint;
        v_a5_G := 'NOT_FIRED';
      exception when others then
        v_a5_G := case when position('pd_overlay_cannot_own_task' in SQLERRM) > 0
                       then 'pd_overlay_cannot_own_task' else 'other:' || SQLSTATE end;
      end;
`,
`      -- THE TABLE BOUNDARY IS ASSERTED SOMEWHERE ELSE, AND THIS IS WHY.
      -- a02_phase_c_step_run_owner_admissible can only be reached with an overlay through
      -- fn_kernel_write_guard's audited maintenance door, and a literal
      -- \`update public.phase_c_workflow_step_run\` inside THIS routine is precisely what
      -- fn_kernel_write_guard_state's routines_that_write_a_protected_table_with_no_authority
      -- exists to surface -- it took that board from 1 of 37 to 3 of 39. Registering this routine
      -- to quieten it would GRANT it authority over the table, which is the opposite of the point.
      -- The forced firing lives in scripts/checks/protected_table_guards_actually_fire.test.mjs,
      -- which is a check rather than a routine and so is not a writer any board can count.
      -- What this branch asserts is the LIVE path: fn_kernel_open_step refuses the overlay before
      -- a row exists, and the stable identity comes from the predicate both guards raise from.
      v_a5_G := coalesce((select refusal_code
                            from public.fn_phase_d_owner_admissibility(v_a5_ovl)), 'ADMISSIBLE');
`, 'AUTH-005 maintenance arm');

// ---- PD-FIN-004: the UPDATE and DELETE arms go through the service --------------------------
rep(`      perform set_config('kernel.maintenance_reason','PD-FIN-004: reach the append-only trigger', true);
      begin
        update public.phase_c_refund_decision set decision='rejected' where decision_id=v_f4_d1;
        v_f4_U := 'ACCEPTED';
      exception when others then v_f4_U := 'REFUSED ' || SQLSTATE; end;
      perform set_config('kernel.maintenance_reason','PD-FIN-004: reach the append-only trigger', true);
      begin
        delete from public.phase_c_refund_decision where decision_id=v_f4_d1;
        v_f4_D := 'ACCEPTED';
      exception when others then v_f4_D := 'REFUSED ' || SQLSTATE; end;
      perform set_config('kernel.maintenance_reason','', true);
`,
`      -- THE EDIT AND THE DELETE ARE ASKED OF THE SERVICE, NOT WRITTEN BY HAND, and this is why.
      -- The raw UPDATE and DELETE reach a00_phase_c_refund_decision_immutable only through
      -- fn_kernel_write_guard's maintenance door, and a literal
      -- \`update public.phase_c_refund_decision\` inside this routine is exactly what
      -- fn_kernel_write_guard_state counts as an unauthorised writer. Those two arms are driven in
      -- scripts/checks/protected_table_guards_actually_fire.test.mjs, which asserts the frozen
      -- trigger's own 23514 refusals and that the original row did not move.
      -- Here the same two acts are asked of the canonical service, which is the door a caller
      -- actually has, and it refuses both with pd_refund_decision_append_only rather than teaching
      -- its callers that a raw edit is worth attempting.
      begin
        perform public.fn_kernel_refund_decision_record(jsonb_build_object(
          'op','record','decision_id',v_f4_d1,'edit',true,'request_id',v_f4_req,
          'decision','rejected','reason','PD-FIN-004 edit attempt'));
        v_f4_U := 'ACCEPTED';
      exception when others then
        v_f4_U := case when position('pd_refund_decision_append_only' in SQLERRM) > 0
                       then 'REFUSED pd_refund_decision_append_only' else 'other:' || SQLSTATE end;
      end;
      begin
        perform public.fn_kernel_refund_decision_record(jsonb_build_object(
          'op','record','decision_id',v_f4_d1,'delete',true,'request_id',v_f4_req,
          'decision','rejected','reason','PD-FIN-004 delete attempt'));
        v_f4_D := 'ACCEPTED';
      exception when others then
        v_f4_D := case when position('pd_refund_decision_append_only' in SQLERRM) > 0
                       then 'REFUSED pd_refund_decision_append_only' else 'other:' || SQLSTATE end;
      end;
`, 'FIN-004 raw write arms');

// the AUTH-005 assertion referred to the guard arm by its old value
rep(`           and split_part(v_a5_msg,'|',4) = 'pd_overlay_cannot_own_task'
           and split_part(v_a5_msg,'|',5) = 'pd_overlay_cannot_own_task'
           and split_part(v_a5_msg,'|',6) = 'pd_overlay_cannot_own_task'`,
`           and split_part(v_a5_msg,'|',4) = 'pd_overlay_cannot_own_task'
           and split_part(v_a5_msg,'|',5) = 'pd_overlay_cannot_own_task'
           and split_part(v_a5_msg,'|',6) = 'pd_overlay_cannot_own_task'
           -- and the standing role must still be ADMISSIBLE, or the predicate refuses everything
           and (select admissible from public.fn_phase_d_owner_admissibility(
                  (select accountable_role_id from public.phase_b_workflow_step
                    where step_id = 'W04-S02')))`, 'AUTH-005 assertion');

rep(`    observed := format('overlay owner->%s alias->%s standing role->%s; step-run guard %s; tasks/stepruns/traces %s',`,
`    observed := format('overlay owner->%s alias->%s standing role->%s; owner-admissibility predicate %s; tasks/stepruns/traces %s',`,
  'AUTH-005 observed');

if (bad) process.exit(1);
writeFileSync(p, s);
console.log('de-rawified O08');
