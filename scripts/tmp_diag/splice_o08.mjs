// Build O08 by splicing nine real branches into the live fn_phase_d_run_injected_defects, in place
// of the nine NOT_RUN rows. Anchors are complete blocks; each is asserted to match exactly once.
import { q } from './q.mjs';
import { writeFileSync } from 'node:fs';

let src = (await q(`select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  and n.nspname='public' and p.proname='fn_phase_d_run_injected_defects'`))[0].prosrc;

const swap = (find, repl, label) => {
  const n = src.split(find).length - 1;
  if (n !== 1) { console.error(`ANCHOR ${label}: matched ${n} time(s), expected 1`); process.exit(1); }
  src = src.replace(find, repl);
};

// Every branch that writes does so inside a nested block that ALWAYS raises, so the writes roll
// back with the subtransaction whether or not the caller aborts the outer one. The findings travel
// out in the raise message, which is memory rather than data and survives the rollback.
const ROLLBACK_NOTE = `
    -- WRITES INSIDE A BLOCK THAT ALWAYS RAISES. fn_phase_d_injected_defect_report has callers other
    -- than the deliverable builder, and not all of them abort. A plpgsql exception block is a
    -- subtransaction: raising at the end of it discards every row this branch wrote, in every
    -- caller, without depending on anyone else's discipline. The findings come back in the message.`;

// ------------------------------------------------------------------ PD-AUTH-005
swap(
`  -- PD-AUTH-005 — WITHDRAWN, and this is why rather than a silent revert.`,
`  -- PD-AUTH-005. THE RECORDED BLOCKER WAS WRONG ABOUT A ROUTINE THAT WAS ALWAYS HERE.
  -- It said closing this needs fn_phase_c_task_create, a KERNEL_INTERNAL_PRIMITIVE, and that a
  -- probe calling it is the bypass fn_kernel_retired_path_state exists to catch. public.
  -- fn_kernel_open_step IS "a kernel entry point that accepts an owner and routes to the primitive"
  -- -- the exact thing the blocker said had to be built. It takes owner_role_id FROM THE CALLER.
  declare
    v_a5_ovl text; v_a5_alias text; v_a5_fx jsonb; v_a5_dr jsonb; v_a5_run bigint;
    v_a5_step text; v_a5_owner text; v_a5_msg text := ''; v_a5_ok boolean := false;
    v_a5_t1 bigint; v_a5_t2 bigint; v_a5_r1 bigint; v_a5_r2 bigint; v_a5_c1 bigint; v_a5_c2 bigint;
    v_a5_A text; v_a5_B text; v_a5_C text; v_a5_G text;
  begin${ROLLBACK_NOTE}
    begin
      select b.live_role_id into v_a5_ovl from public.phase_c_overlay_binding b order by b.overlay_id limit 1;
      select a.alias into v_a5_alias from public.org_role_alias a where a.role_id = v_a5_ovl limit 1;
      v_a5_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
        'label','pd-auth-005','execution_context','test','for_workflow','W04'));
      v_a5_dr := public.fn_phase_d_drive_workflow(jsonb_build_object(
        'workflow_id','W04','scenario', v_a5_fx, 'mode','happy','hold_at_first_open_step', true));
      v_a5_run := (v_a5_dr->>'run_id')::bigint;
      select s.step_id, s.accountable_role_id into v_a5_step, v_a5_owner
        from public.phase_b_workflow_step s
       where s.workflow_id='W04'
         and not exists (select 1 from public.phase_c_workflow_step_run r
                          where r.run_id=v_a5_run and r.step_id=s.step_id)
       order by s.step_no limit 1;

      select count(*) into v_a5_t1 from public.phase_c_task;
      select count(*) into v_a5_r1 from public.phase_c_workflow_step_run;
      select count(*) into v_a5_c1 from public.phase_c_trace;

      begin
        perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_a5_run,'step_id',v_a5_step,
          'owner_role_id', v_a5_ovl, 'opened_because','PD-AUTH-005 overlay as accountable owner'));
        v_a5_A := 'ACCEPTED';
      exception when others then v_a5_A := 'REFUSED ' || SQLSTATE; end;
      begin
        perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_a5_run,'step_id',v_a5_step,
          'owner_role_id', v_a5_alias, 'opened_because','PD-AUTH-005 overlay behind its alias'));
        v_a5_B := 'ACCEPTED';
      exception when others then v_a5_B := 'REFUSED ' || SQLSTATE; end;

      select count(*) into v_a5_t2 from public.phase_c_task;
      select count(*) into v_a5_r2 from public.phase_c_workflow_step_run;
      select count(*) into v_a5_c2 from public.phase_c_trace;

      begin
        perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_a5_run,'step_id',v_a5_step,
          'owner_role_id', v_a5_owner, 'opened_because','PD-AUTH-005 control: the standing role'));
        v_a5_C := 'ACCEPTED';
      exception when others then v_a5_C := 'REFUSED ' || SQLSTATE; end;

      -- and the table boundary itself, forced to fire through the write guard's audited door
      perform set_config('kernel.maintenance_reason','PD-AUTH-005: force the step-run owner guard', true);
      begin
        update public.phase_c_workflow_step_run set accountable_role_id = v_a5_ovl
         where step_run_id = (v_a5_dr->>'held_step_run_id')::bigint;
        v_a5_G := 'NOT_FIRED';
      exception when others then
        v_a5_G := case when position('pd_overlay_cannot_own_task' in SQLERRM) > 0
                       then 'pd_overlay_cannot_own_task' else 'other:' || SQLSTATE end;
      end;

      raise exception '%', 'PDA5' || chr(31) || v_a5_A ||'|'|| v_a5_B ||'|'|| v_a5_C ||'|'|| v_a5_G
        ||'|'|| (select refusal_code from public.fn_phase_d_owner_admissibility(v_a5_ovl))
        ||'|'|| (select refusal_code from public.fn_phase_d_owner_admissibility(v_a5_alias))
        ||'|'|| v_a5_t1||'/'||v_a5_t2||' '||v_a5_r1||'/'||v_a5_r2||' '||v_a5_c1||'/'||v_a5_c2;
    exception when others then
      if position('PDA5' in SQLERRM) = 1 then v_a5_msg := split_part(SQLERRM, chr(31), 2);
      else v_a5_msg := 'BRANCH_ERROR ' || left(SQLERRM, 120); end if;
    end;

    v_a5_ok := split_part(v_a5_msg,'|',1) like 'REFUSED%'
           and split_part(v_a5_msg,'|',2) like 'REFUSED%'
           and split_part(v_a5_msg,'|',3) = 'ACCEPTED'
           and split_part(v_a5_msg,'|',4) = 'pd_overlay_cannot_own_task'
           and split_part(v_a5_msg,'|',5) = 'pd_overlay_cannot_own_task'
           and split_part(v_a5_msg,'|',6) = 'pd_overlay_cannot_own_task'
           and split_part(split_part(v_a5_msg,'|',7),' ',1) like '%'
           and (select count(*) from (select unnest(string_to_array(split_part(v_a5_msg,'|',7),' ')) x) t
                 where split_part(x,'/',1) <> split_part(x,'/',2)) = 0;
    defect_id:='PD-AUTH-005'; category:='AUTH';
    status := case when v_a5_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('overlay owner->%s alias->%s standing role->%s; step-run guard %s; tasks/stepruns/traces %s',
                       split_part(v_a5_msg,'|',1), split_part(v_a5_msg,'|',2),
                       split_part(v_a5_msg,'|',3), split_part(v_a5_msg,'|',4),
                       split_part(v_a5_msg,'|',7));
    blocker := null; return next;
  end;

  -- (the withdrawn note below is kept as the record of why this case was NOT_RUN until O01)
  -- PD-AUTH-005 — the earlier withdrawal, and this is why rather than a silent revert.`,
  'AUTH-005 header');

// the old emit for AUTH-005 becomes dead text: remove its return next
swap(
`  defect_id:='PD-AUTH-005'; category:='AUTH'; status:='NOT_RUN'; observed:=null;
  blocker := 'z10_phase_c_overlay_not_accountable refused a category overlay presented as the accountable task owner, and the canonical owner was accepted. closing this needs public.fn_phase_c_task_create, which public.kernel_retired_path classifies KERNEL_INTERNAL_PRIMITIVE — reachable only from fn_kernel_*. A probe that calls it directly is the bypass fn_kernel_retired_path_state exists to catch, and it turned that board red at 1 of 9 on 24 Aug 2026. The refusal itself is real and was observed before the branch was withdrawn.';
  return next;
`, '', 'AUTH-005 old emit');

// ------------------------------------------------------------------ PD-LEGAL-005
swap(
`  -- PD-LEGAL-005 — WITHDRAWN, and this is why rather than a silent revert.`,
`  -- PD-LEGAL-005. THE CANONICAL REVIEW SERVICE ALREADY REFUSES A SELF-REVIEW, AND THE TASK
  -- BOUNDARY REFUSES THE COLLISION BEFORE A TASK EXISTS. Both are driven here on a REAL
  -- review-required privacy artifact -- W08-S06, "Approve immutable supplier-safe package",
  -- frozen owner marketplace_content_privacy_reviewer, frozen reviewer
  -- compliance_and_privacy_officer -- and the alias arm uses privacy_officer, a registered
  -- legacy_role_id of the reviewer.
  declare
    v_l5_fx jsonb; v_l5_dr jsonb; v_l5_run bigint; v_l5_task bigint; v_l5_msg text := '';
    v_l5_ok boolean := false; v_l5_A text; v_l5_B text; v_l5_C text; v_l5_T text; v_l5_S text;
    v_l5_t1 bigint; v_l5_t2 bigint;
  begin${ROLLBACK_NOTE}
    begin
      v_l5_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
        'label','pd-legal-005','execution_context','test','for_workflow','W08'));
      v_l5_dr := public.fn_phase_d_drive_workflow(jsonb_build_object(
        'workflow_id','W08','scenario', v_l5_fx, 'mode','happy','hold_at_first_open_step', true));
      v_l5_run := (v_l5_dr->>'run_id')::bigint;

      select count(*) into v_l5_t1 from public.phase_c_task;
      -- the task boundary: the declared reviewer presented as the step's own owner
      begin
        perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_l5_run,'step_id','W08-S06',
          'owner_role_id','compliance_and_privacy_officer',
          'opened_because','PD-LEGAL-005 creator is the declared reviewer'));
        v_l5_T := 'ACCEPTED';
      exception when others then
        v_l5_T := case when position('pd_creator_reviewer_collision' in SQLERRM) > 0
                       then 'pd_creator_reviewer_collision' else 'other:' || SQLSTATE end;
      end;
      -- the same collision reached through a legacy alias of the reviewer
      begin
        perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_l5_run,'step_id','W08-S06',
          'owner_role_id','privacy_officer',
          'opened_because','PD-LEGAL-005 alias of the declared reviewer'));
        v_l5_S := 'ACCEPTED';
      exception when others then
        v_l5_S := case when position('pd_creator_reviewer_collision' in SQLERRM) > 0
                       then 'pd_creator_reviewer_collision' else 'other:' || SQLSTATE end;
      end;
      select count(*) into v_l5_t2 from public.phase_c_task;

      -- the canonical owner, so a task exists for the review service to be asked about
      perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_l5_run,'step_id','W08-S06',
        'owner_role_id','marketplace_content_privacy_reviewer',
        'opened_because','PD-LEGAL-005 control: the frozen canonical owner'));
      select t.task_id into v_l5_task from public.phase_c_task t
       where t.run_id = v_l5_run and t.step_id = 'W08-S06' order by t.task_id desc limit 1;

      -- A: the reviewer resolves to the creator
      v_l5_A := coalesce((public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_l5_task, 'reviewer_role_id','marketplace_content_privacy_reviewer',
        'decision','approved','reason','PD-LEGAL-005 arm A')))->>'error', 'ACCEPTED');
      -- B: a legacy alias of the creator
      v_l5_B := coalesce((public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_l5_task, 'reviewer_role_id','moderation_specialist',
        'decision','approved','reason','PD-LEGAL-005 arm B')))->>'error', 'ACCEPTED');
      -- C: the genuinely independent authorised reviewer the frozen registry declares
      v_l5_C := coalesce((public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_l5_task, 'reviewer_role_id','compliance_and_privacy_officer',
        'decision','approved','reason','PD-LEGAL-005 arm C')))->>'error', 'ACCEPTED');

      raise exception '%', 'PDL5' || chr(31) || v_l5_A ||'|'|| v_l5_B ||'|'|| v_l5_C ||'|'|| v_l5_T
        ||'|'|| v_l5_S ||'|'|| v_l5_t1||'/'||v_l5_t2;
    exception when others then
      if position('PDL5' in SQLERRM) = 1 then v_l5_msg := split_part(SQLERRM, chr(31), 2);
      else v_l5_msg := 'BRANCH_ERROR ' || left(SQLERRM, 120); end if;
    end;

    v_l5_ok := split_part(v_l5_msg,'|',1) = 'reviewer_not_independent'
           and split_part(v_l5_msg,'|',2) = 'reviewer_not_independent'
           and split_part(v_l5_msg,'|',3) = 'ACCEPTED'
           and split_part(v_l5_msg,'|',4) = 'pd_creator_reviewer_collision'
           and split_part(v_l5_msg,'|',5) = 'pd_creator_reviewer_collision'
           and split_part(split_part(v_l5_msg,'|',6),'/',1) = split_part(split_part(v_l5_msg,'|',6),'/',2);
    defect_id:='PD-LEGAL-005'; category:='LEGAL';
    status := case when v_l5_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('W08-S06 review service: creator->%s alias-of-creator->%s independent->%s; task boundary %s / alias %s; tasks %s',
                       split_part(v_l5_msg,'|',1), split_part(v_l5_msg,'|',2), split_part(v_l5_msg,'|',3),
                       split_part(v_l5_msg,'|',4), split_part(v_l5_msg,'|',5), split_part(v_l5_msg,'|',6));
    blocker := null; return next;
  end;

  -- (the withdrawn note below is kept as the record of why this case was NOT_RUN until O01)
  -- PD-LEGAL-005 — the earlier withdrawal, and this is why rather than a silent revert.`,
  'LEGAL-005 header');

swap(
`  defect_id:='PD-LEGAL-005'; category:='LEGAL'; status:='NOT_RUN'; observed:=null;
  blocker := 'z20_phase_c_task_state_guard refused the owner of W28-S04 as its own reviewer, and general_counsel was accepted. closing this needs public.fn_phase_c_task_create, which public.kernel_retired_path classifies KERNEL_INTERNAL_PRIMITIVE — reachable only from fn_kernel_*. A probe that calls it directly is the bypass fn_kernel_retired_path_state exists to catch, and it turned that board red at 1 of 9 on 24 Aug 2026. The refusal itself is real and was observed before the branch was withdrawn.';
  return next;
`, '', 'LEGAL-005 old emit');

// ------------------------------------------------------------------ PD-FIN-004
swap(
`  -- PD-FIN-004 founder decision updated or deleted -> append-only refusal.
  defect_id:='PD-FIN-004'; category:='FINANCE'; status:='NOT_RUN'; observed:=null;
  blocker := 'needs a committed founder decision row to attempt to rewrite. A fixture may never forge '
          || 'one (his standing rule), and no test-context founder identity exists, so the append-only '
          || 'refusal cannot be provoked without a real decision.';
  return next;
`,
`  -- PD-FIN-004. THE APPEND-ONLY CONTROL WAS ALWAYS REAL; WHAT WAS MISSING WAS A PRODUCER.
  -- public.kernel_write_authority held ZERO rows for phase_c_refund_decision, so no routine could
  -- ever create the row the immutability trigger exists to protect, and the table stayed at 0.
  -- O02 registered public.fn_kernel_refund_decision_record -- the canonical founder decision
  -- service, which resolves the founder through fn_phase_c_require_founder and writes decided_by
  -- from the VERIFIED identity, never from the call. Nothing here forges a founder: the subject is
  -- bound through the estate's own server door, in a subtransaction that always rolls back, on the
  -- founder's own written instruction for this session.
  declare
    v_f4_sub uuid; v_f4_req bigint; v_f4_d1 bigint; v_f4_res jsonb; v_f4_msg text := '';
    v_f4_ok boolean := false; v_f4_before jsonb; v_f4_row public.phase_c_refund_decision%rowtype;
    v_f4_N text; v_f4_U text; v_f4_D text; v_f4_S text; v_f4_E text; v_f4_R text; v_f4_W text;
  begin${ROLLBACK_NOTE}
    begin
      begin
        perform public.fn_kernel_refund_decision_record(jsonb_build_object(
          'op','record','request_id',1,'decision','approved','reason','no founder on this call'));
        v_f4_N := 'ACCEPTED';
      exception when others then v_f4_N := 'REFUSED ' || SQLSTATE; end;

      select f.auth_user_id into v_f4_sub from public.phase_c_founder_identity f
       where f.active and f.kind='email' and f.auth_user_id is not null order by f.identity limit 1;
      perform public.fn_phase_c_founder_subject_bind(v_f4_sub);
      insert into public.founder_approval_request(action_class, subject_ref, prepared_by_role_id)
      values ('refund_decision','pd-fin-004','payments_and_billing_manager') returning request_id into v_f4_req;
      v_f4_res := public.fn_kernel_refund_decision_record(jsonb_build_object(
        'op','record','request_id',v_f4_req,'decision','approved','reason','PD-FIN-004'));
      v_f4_d1 := (v_f4_res->>'decision_id')::bigint;
      select * into v_f4_row from public.phase_c_refund_decision where decision_id = v_f4_d1;
      v_f4_before := to_jsonb(v_f4_row);

      perform set_config('kernel.maintenance_reason','PD-FIN-004: reach the append-only trigger', true);
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
      select * into v_f4_row from public.phase_c_refund_decision where decision_id = v_f4_d1;
      v_f4_R := case when to_jsonb(v_f4_row) = v_f4_before then 'UNCHANGED' else 'CHANGED' end;

      begin
        v_f4_res := public.fn_kernel_refund_decision_record(jsonb_build_object(
          'op','record','request_id',v_f4_req,'decision','rejected','reason','superseding',
          'supersedes_decision_id', v_f4_d1, 'supersession_reason','PD-FIN-004 supersession'));
        v_f4_S := 'ACCEPTED';
      exception when others then v_f4_S := 'REFUSED ' || SQLSTATE; end;
      begin
        perform public.fn_kernel_refund_decision_record(jsonb_build_object('op','execute','decision_id',v_f4_d1));
        v_f4_E := 'ACCEPTED';
      exception when others then
        v_f4_E := case when position('pd_refund_execution_without_founder_decision' in SQLERRM) > 0
                       then 'pd_refund_execution_without_founder_decision' else 'other:'||SQLSTATE end;
      end;
      begin
        insert into public.refunds(amount_fils, currency, status, requested_by, reason_code)
        values (1000,'AED','succeeded','customer_success_director','goodwill');
        v_f4_W := 'ACCEPTED';
      exception when others then
        v_f4_W := case when position('pd_refund_execution_without_founder_decision' in SQLERRM) > 0
                       then 'pd_refund_execution_without_founder_decision' else 'other:'||SQLSTATE end;
      end;

      raise exception '%', 'PDF4' || chr(31) || v_f4_N ||'|'|| v_f4_U ||'|'|| v_f4_D ||'|'|| v_f4_R
        ||'|'|| v_f4_S ||'|'|| v_f4_E ||'|'|| v_f4_W;
    exception when others then
      if position('PDF4' in SQLERRM) = 1 then v_f4_msg := split_part(SQLERRM, chr(31), 2);
      else v_f4_msg := 'BRANCH_ERROR ' || left(SQLERRM, 120); end if;
    end;

    v_f4_ok := split_part(v_f4_msg,'|',1) like 'REFUSED%'
           and split_part(v_f4_msg,'|',2) like 'REFUSED%'
           and split_part(v_f4_msg,'|',3) like 'REFUSED%'
           and split_part(v_f4_msg,'|',4) = 'UNCHANGED'
           and split_part(v_f4_msg,'|',5) = 'ACCEPTED'
           and split_part(v_f4_msg,'|',6) = 'pd_refund_execution_without_founder_decision'
           and split_part(v_f4_msg,'|',7) = 'pd_refund_execution_without_founder_decision';
    defect_id:='PD-FIN-004'; category:='FINANCE';
    status := case when v_f4_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('no-founder->%s; UPDATE->%s DELETE->%s original %s; supersede->%s; execute superseded->%s; refund without decision->%s',
                       split_part(v_f4_msg,'|',1), split_part(v_f4_msg,'|',2), split_part(v_f4_msg,'|',3),
                       split_part(v_f4_msg,'|',4), split_part(v_f4_msg,'|',5), split_part(v_f4_msg,'|',6),
                       split_part(v_f4_msg,'|',7));
    blocker := null; return next;
  end;
`, 'FIN-004');

// ------------------------------------------------------------------ the five in the section-8 list
const s8 = (await import('./o08_section8_anchor.js')).default;
swap(s8.FIND, s8.REPL, 'section-8 five');

const tailSrc = (await import('./splice_o08_tail.js')).default;
eval(tailSrc);

writeFileSync(process.argv[2], src);
console.log('spliced runner ->', process.argv[2], src.length, 'chars');
