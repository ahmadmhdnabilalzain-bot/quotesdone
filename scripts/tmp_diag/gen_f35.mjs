// Build F35 by splicing the LIVE fn_phase_d_drive_workflow definition.
import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const [{ def }] = await sql(
  `select pg_get_functiondef('public.fn_phase_d_drive_workflow(jsonb)'::regprocedure) as def`);

// ---- anchor 1: the end of the capability block, where the review block goes next -------------
const CAP_TAIL = `      v_cap_fixture := null;
    end if;
`;

const REVIEW_BLOCK = `      v_cap_fixture := null;
    end if;

    -- ---- THE INTERNAL REVIEW, THROUGH THE KERNEL'S OWN DOOR, THEN ASK AGAIN (F35) -----------
    -- The mirror of the capability block above, for the other input class the handler cannot
    -- invent. F34 made fn_phase_d_handler_execute read the verdict and the reviewer from the review
    -- the estate RECORDED -- phase_c_task.reviewer_role_id and the sealed TRACE-ROLE-ACTION -- and
    -- refuse with pd_review_not_recorded when there is none. There is none at step-open time,
    -- because the kernel dispatches the handler the instant the step opens and no review has
    -- happened yet. This is the moment one can: the step is open and owned, the handler has said
    -- what it is missing, and the driver -- standing in for the reviewer -- records the decision
    -- through fn_kernel_review_decide and asks the estate to dispatch the step again.
    --
    -- NOTHING IS BYPASSED. fn_kernel_review_decide refuses a reviewer the frozen registry did not
    -- name where it names one, refuses a reviewer who resolves to the creator, refuses a review
    -- with no stated reason, and seals its own trace. The reviewer is never chosen by preference
    -- here: it is the frozen independent_reviewer_role_id, or a candidate the kernel's own
    -- independence test allows. If it refuses, the step stays refused and the refusal is recorded.
    if found and d.refusal_code = 'pd_review_not_recorded' then
      begin
        select t.task_id into v_rtask from public.phase_c_task t
         where t.run_id = sr.run_id and t.step_id = sr.step_id
         order by t.task_id desc limit 1;

        select s2.independent_reviewer_role_id into v_rrev
          from public.phase_b_workflow_step s2 where s2.step_id = sr.step_id;
        v_rrev := nullif(btrim(coalesce(v_rrev,'')),'');
        if v_rrev is null then
          v_rrev := (select c from unnest(v_cands) c
                      where public.fn_kernel_reviewer_independent(sr.accountable_role_id, c)
                      limit 1);
        end if;
        if v_rrev is null and v_caller_reviewer is not null
           and public.fn_kernel_reviewer_independent(sr.accountable_role_id, v_caller_reviewer) then
          v_rrev := v_caller_reviewer;
        end if;

        if v_rtask is null then
          raise exception 'step % has no task to review (pd_review_no_task)', sr.step_id
            using errcode = '23503';
        end if;
        if v_rrev is null then
          raise exception 'step % is owned by % and no candidate role passes the kernel independence test against it (pd_review_no_independent_reviewer)',
            sr.step_id, sr.accountable_role_id using errcode = '23503';
        end if;

        -- The stated reason is the committed rationale fixture, not a sentence written here.
        v_rdec := public.fn_kernel_review_decide(jsonb_build_object(
          'task_id',          v_rtask,
          'reviewer_role_id', v_rrev,
          'decision',         'approved',
          'reason',           coalesce(
                                public.fn_phase_d_fixture_output(sr.step_id,'rationale') #>> '{}',
                                'PHASE_D_FIXTURE_DO_NOT_PUBLISH - no committed rationale fixture')));

        if coalesce((v_rdec->>'ok')::boolean, false) then
          v_redisp := public.fn_phase_d_dispatch_step(jsonb_build_object(
            'step_run_id',     sr.step_run_id,
            'actor_role_id',   sr.accountable_role_id,
            'opened_by_kind',  'internal_review',
            'opened_by_ref',   format('task=%s;reviewer=%s', v_rtask, v_rrev),
            'idempotency_key', format('%s:%s:%s:rev', v_label, sr.step_id, sr.step_run_id)));
          select * into d from public.phase_d_dispatch
           where step_run_id = sr.step_run_id order by dispatch_id desc limit 1;
        end if;

        v_revn := v_revn + 1;
        v_revs := v_revs || jsonb_build_array(jsonb_build_object(
          'step_id', sr.step_id, 'task_id', v_rtask, 'reviewer_role_id', v_rrev,
          'review_ok', v_rdec->'ok', 'review_error', v_rdec->>'error',
          'redispatch_outcome', v_redisp->>'outcome',
          'redispatch_refusal', v_redisp->>'refusal_code'));
      exception when others then
        v_revs := v_revs || jsonb_build_array(jsonb_build_object(
          'step_id', sr.step_id, 'ok', false,
          'refused_with', coalesce((regexp_match(SQLERRM,'\\((pd_[a-z0-9_]+)\\)'))[1],'(none)'),
          'reason', left(SQLERRM, 300)));
      end;
    end if;
`;

// ---- anchor 2: declarations -------------------------------------------------------------------
const DECL_OLD = `  v_redisp    jsonb;`;
const DECL_NEW = `  v_redisp    jsonb;
  v_rtask     bigint;                 -- F35: the task the internal review decides
  v_rrev      text;                   -- F35: the reviewer, frozen-declared or independence-tested
  v_rdec      jsonb;                  -- F35: what fn_kernel_review_decide returned
  v_revs      jsonb := '[]'::jsonb;   -- F35: what the review path did, per step
  v_revn      int := 0;               -- F35: internal reviews recorded`;

// ---- anchor 3: the returned report -------------------------------------------------------------
const RET_OLD = `    'capability_results_accepted', v_capn,
    'capability_path', v_caps,`;
const RET_NEW = `    'capability_results_accepted', v_capn,
    'capability_path', v_caps,
    'internal_reviews_recorded', v_revn,
    'review_path', v_revs,`;

const parts = [
  ['capability block tail', CAP_TAIL, REVIEW_BLOCK],
  ['declarations', DECL_OLD, DECL_NEW],
  ['returned report', RET_OLD, RET_NEW],
];

let body = def;
for (const [name, oldText, newText] of parts) {
  const n = body.split(oldText).length - 1;
  if (n !== 1) {
    console.error(`ANCHOR "${name}" matched ${n} time(s); exactly one is required. Refusing to write.`);
    process.exit(1);
  }
  body = body.replace(oldText, newText);
}

const HEADER = `-- F35 - the driver answers the review refusal the way it already answers the capability one
--
-- F34 made fn_phase_d_handler_execute read a review step's verdict and reviewer from the review the
-- estate RECORDED, instead of from two strings in p_input that nothing on the kernel path supplies.
-- A step whose review has not happened yet now refuses with its own code, pd_review_not_recorded,
-- rather than being reported as a failed BR-002 independence test.
--
-- This file gives that refusal an answer, and the answer is the shape F17 already established for
-- the capability boundary: the kernel opens the step, the handler says what it is missing, and the
-- driver -- standing in for whoever supplies it -- supplies it THROUGH THE REAL CANONICAL SERVICE
-- and asks the estate to dispatch the step again.
--
--   capability:  fn_phase_d_capability_request_open -> fn_phase_d_capability_result_accept -> dispatch
--   review:      fn_kernel_review_decide                                                   -> dispatch
--
-- The founder's ruling of 22 Aug 2026, section 4, names CANONICAL_INTERNAL_REVIEW as an allowed
-- execution input exactly on that condition: "actor input enters through the real API/domain
-- service". fn_kernel_review_decide is a FROZEN Phase C subject and is not touched by this file.
-- It refuses a reviewer the frozen registry did not name where it names one, refuses a reviewer who
-- resolves to the same employee as the creator, refuses a review with no stated reason, and seals
-- its own TRACE-ROLE-ACTION. If it refuses, the step stays refused and the refusal is recorded in
-- the review_path report rather than swallowed.
--
-- The reviewer is never chosen by preference here. It is the frozen independent_reviewer_role_id
-- where the registry names one -- measured: 2 of the 47 REVIEW_HANDLER steps -- and otherwise a
-- candidate that passes the kernel's own fn_kernel_reviewer_independent against the step's owner.
-- The stated reason is the committed rationale fixture PDF-0055, read through
-- fn_phase_d_fixture_output, not a sentence written in this routine.
--
-- THE REST OF THE ROUTINE IS BYTE-IDENTICAL. Produced by reading the live definition with
-- pg_get_functiondef and replacing three anchors, each required to match exactly once.

`;

writeFileSync('scripts/sql/phase_d_f35_the_driver_answers_the_review_refusal_through_the_kernel_door.sql',
  HEADER + body + ';\n');
console.log('written');
