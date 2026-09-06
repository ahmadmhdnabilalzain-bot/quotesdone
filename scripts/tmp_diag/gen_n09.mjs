// GENERATE N09 — execute PD-STATE-003 and PD-STATE-004 against the frozen registry's real refusals.
import { q } from './q.mjs';
import { writeFileSync } from 'node:fs';

const [{ d: live }] = await q(`select pg_get_functiondef(p.oid) d
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname='public' and p.proname='fn_phase_d_run_injected_defects'`);

function replaceEmit(src, defectId, repl) {
  const find = `  defect_id:='${defectId}';`;
  const n = src.split(find).length - 1;
  if (n !== 1) { console.error(`${defectId}: anchor matched ${n} times, expected 1.`); process.exit(2); }
  const start = src.indexOf(find);
  const end = src.indexOf('return next;', start) + 'return next;'.length;
  return src.slice(0, start) + repl + src.slice(end);
}

// PD-STATE-004 — a successor with no owner. Two facts, and the second is the interesting one:
// a10_phase_b_owner_guard refuses it EVEN WITH a change reason set, so the state is unreachable
// regardless of change-request authority, not merely frozen.
const S004 = `  -- PD-STATE-004 a successor step with no accountable owner.
  -- THE OLD BLOCKER SAID THE SUBJECT IS A FROZEN PHASE B PROPERTY AND SO CANNOT BE INJECTED. The
  -- frozen registry REFUSING the injection is itself a discriminating result — it is what makes the
  -- state unreachable — and refusing to execute it left that refusal unmeasured.
  --
  -- TWO ARMS, and the second is the one that matters. Blanking the owner is refused by
  -- a10_phase_b_owner_guard; blanking it again with app.phase_b_change_reason SET is refused by the
  -- SAME guard, so an unowned successor cannot be created even by a caller holding change-request
  -- authority. That is stronger than "it is frozen": freezing can be amended, and this cannot.
  begin
    select step_id into v_s4_step from public.phase_b_workflow_step
     where workflow_id='W04' order by step_no limit 1;
    begin
      update public.phase_b_workflow_step set accountable_role_id = '' where step_id = v_s4_step;
      v_s4_bare := 'ACCEPTED — an unowned successor was written';
    exception when others then v_s4_bare := left(SQLERRM, 120);
    end;
    begin
      perform set_config('app.phase_b_change_reason',
        'PBCR-probe: a probe is not a change request; this exists to show the guard does not care', true);
      update public.phase_b_workflow_step set accountable_role_id = '' where step_id = v_s4_step;
      v_s4_reason := 'ACCEPTED with a change reason set';
    exception when others then v_s4_reason := left(SQLERRM, 120);
    end;
    perform set_config('app.phase_b_change_reason', '', true);
    v_ok := v_s4_bare not like 'ACCEPTED%' and v_s4_reason not like 'ACCEPTED%';
    v_msg := format('blanking the accountable owner of %s was refused [%s]; and refused again with '
                 || 'app.phase_b_change_reason set [%s]. A successor with no accountable owner cannot '
                 || 'be created in this estate even by a caller holding change-request authority, so '
                 || 'the state the defect names is unreachable by construction rather than by policy.',
                    v_s4_step, v_s4_bare, v_s4_reason);
  exception when others then
    v_ok := false; v_msg := 'the probe raised outside its own handlers: ' || left(SQLERRM, 160);
  end;
  defect_id:='PD-STATE-004'; category:='STATE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;`;

// PD-STATE-003 — a step whose terminality is stated inconsistently. Empty population, and creating
// one is refused by the freeze itself. The refusal is a DIFFERENT one from PD-STATE-004's, which is
// what shows the registry is not simply refusing everything with one message.
const S003 = `  -- PD-STATE-003 a nonterminal step presented to the kernel as a closure step.
  -- THE POPULATION IS EMPTY — 0 of 257 frozen steps state their terminality inconsistently — and
  -- the old row stopped there, at NOT_DISCRIMINATED. But "why is it empty" is the measurable part:
  -- creating an inconsistent step is refused by z90_phase_b_freeze, which compares a DIGEST rather
  -- than a count, so flipping one boolean is refused even though no row count moves.
  --
  -- THE CONTROL IS THE OTHER REFUSAL. PD-STATE-004 above is refused by a10_phase_b_owner_guard with
  -- a different message. Two different guards answering two different injections is what shows the
  -- registry is judging the change rather than refusing every statement identically.
  begin
    select count(*) into v_n from public.phase_b_workflow_step
     where (next_step_if_pass = 'WORKFLOW_COMPLETE') <> is_closure_step;
    select step_id into v_s3_step from public.phase_b_workflow_step
     where workflow_id='W04' order by step_no limit 1;
    begin
      update public.phase_b_workflow_step set is_closure_step = not is_closure_step
       where step_id = v_s3_step;
      v_s3_flip := 'ACCEPTED — an inconsistent step was written';
    exception when others then v_s3_flip := left(SQLERRM, 130);
    end;
    v_ok := v_n = 0 and v_s3_flip not like 'ACCEPTED%';
    v_msg := format('%s of 257 frozen steps state their terminality inconsistently, and creating one '
                 || 'was refused: [%s]. The population is empty because the registry refuses to make '
                 || 'it non-empty, which is the fact this case is about; the refusal differs from the '
                 || 'one PD-STATE-004 receives, so the registry is judging the change rather than '
                 || 'refusing every statement alike.', v_n, v_s3_flip);
  exception when others then
    v_ok := false; v_msg := 'the probe raised outside its own handlers: ' || left(SQLERRM, 160);
  end;
  defect_id:='PD-STATE-003'; category:='STATE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;`;

let out = replaceEmit(live, 'PD-STATE-004', S004);
out = replaceEmit(out, 'PD-STATE-003', S003);

const DECL = 'AS $function$\ndeclare\n';
if (out.split(DECL).length - 1 !== 1) { console.error('declare anchor not unique.'); process.exit(2); }
out = out.replace(DECL, DECL +
  `  v_s4_step text; v_s4_bare text; v_s4_reason text; v_s3_step text; v_s3_flip text;\n`);

const header = `-- N09. TWO STATE CASES CLOSED ON THE FROZEN REGISTRY'S OWN REFUSAL.
--
-- PD-STATE-003 and PD-STATE-004 both carried PERMANENT_EXEMPTION, and both reasons ended at the
-- same place: the subject is a frozen Phase B property, so the injection cannot be written.
--
-- THAT IS THE ANSWER, NOT THE OBSTACLE. A real refusal from the frozen registry is a discriminating
-- result: it is precisely what makes the state the defect names unreachable. Recording "cannot
-- test" beside a control that demonstrably works left the control unmeasured.
--
-- Measured 24 Aug 2026, in an aborted transaction:
--
--   blank a step's accountable_role_id     -> a10_phase_b_owner_guard: "step W04-S01 is accountable
--                                             to "", which does not resolve to an active canonical
--                                             role"
--   the same, with app.phase_b_change_reason set
--                                          -> the SAME guard, same refusal. Change-request
--                                             authority does not open this door; the state is
--                                             unreachable by construction, not by policy.
--   flip a step's is_closure_step          -> z90_phase_b_freeze: "PHASE B IS FROZEN ... workflow_order
--                                             (30494857d67b != 318f4b51d2ab)" — a DIGEST comparison,
--                                             so one flipped boolean is refused although no row
--                                             count moves.
--
-- THE TWO REFUSALS ARE DIFFERENT, and that is the control. A registry that refused every statement
-- with one message would prove nothing about either injection; two guards answering two injections
-- with two messages shows it is judging the change.
--
-- Nothing here edits the frozen registry. Both arms run inside a transaction that is aborted, and
-- both are refused before that anyway.
--
-- Generated by scripts/tmp_diag/gen_n09.mjs against the LIVE body, each anchor asserted unique.

`;
writeFileSync('scripts/sql/phase_d_n09_two_state_cases_closed_on_the_frozen_registrys_own_refusal.sql',
  header + out + ';\n');
console.log(`written. live ${live.length} -> new ${out.length} chars`);
