-- THE BOUNDARY REFUSED THE WRONG ACTOR BUT NOT THE WRONG ORDER.
--
-- docs/phase-c/PHASE_C_PHASE_D_HANDOFF.md makes one claim about every item it hands to Phase D:
--
--     "Every item below already has an accountable canonical owner, a SAFE ENTRY BOUNDARY THAT
--      REFUSES AN UNAUTHORISED OR OUT-OF-ORDER CALL, and no active bypass. That is the difference
--      between a gap and a hole: none of these can be reached around."
--
-- Tested by execution against a real W05 run, the first half of that is true and the second is not:
--
--     wrong owner (cfo)                    ok=false  not_the_accountable_owner
--     category overlay as actor            ok=false  not_the_accountable_owner
--     service_role                         ok=false  actor_not_resolvable
--     W05-S09 advanced before W05-S01      ok=TRUE   ← the last step of the workflow, run first
--
-- fn_phase_c_step_advance validates that the step belongs to the run's workflow, that the actor
-- resolves, that it is the accountable owner, the gates, the authority, reviewer independence and
-- the output contract. It never asks whether the step's prerequisites are satisfied. So the
-- inquiry-qualification workflow would accept its final step as its first, seal a trace for it, and
-- report ok — and Phase D would inherit a boundary documented as ordered that is not.
--
-- THE ORDER IS ALREADY DECLARED, which is what makes this a defect rather than a design decision.
-- public.phase_b_handoff carries a from_step_id -> to_step_id edge for every ordered pair, and
-- public.phase_b_step_state already defines the vocabulary: not_ready is "Prerequisites are not
-- satisfied", ready is "Prerequisites are satisfied and the step may start". Phase B modelled the
-- prerequisite. Phase C bound everything except the check.
--
-- MEASURED BEFORE WRITING, because the shape decides whether the rule is even expressible:
--   161 of 257 steps have exactly one declared predecessor
--    96 of 257 have none and are entry points, which must stay startable
--     0 of 257 have more than one predecessor
-- No joins anywhere, so there is no AND/OR ambiguity to guess at: a step has one predecessor or it
-- has none. A rule requiring ALL predecessors would have been indistinguishable from one requiring
-- ANY on this data, and picking between them without joins to test on would have been a guess
-- dressed as a decision.
--
-- SATISFIED means the predecessor reached a terminal state that represents work not outstanding:
-- completed, skipped ("conditionally not applicable with an approved reason") or superseded
-- ("a newer step/output version replaces this one"). failed and cancelled do NOT satisfy it — a
-- successor that runs after its predecessor failed is precisely the out-of-order call being
-- refused here.
--
-- The check sits immediately after step_not_in_this_workflow and BEFORE the actor is resolved, so
-- an out-of-order call is refused whoever makes it. Ordering is a property of the run, not of the
-- caller, and checking it after ownership would report the wrong reason to a correct owner.

begin;

do $mig$
declare v_def text; v_new text; v_anchor text; v_insert text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_phase_c_step_advance';
  if v_def is null then raise exception 'fn_phase_c_step_advance not found'; end if;

  if v_def like '%out_of_order%' then
    raise notice 'fn_phase_c_step_advance already enforces step order; nothing to do';
    return;
  end if;

  v_anchor := $q$  select role_id into v_owner from public.fn_phase_c_resolve_actor(p_actor);$q$;
  if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 then
    raise exception 'the actor-resolution anchor is not unique in fn_phase_c_step_advance';
  end if;

  v_insert :=
    $q$  -- PREREQUISITES. phase_b_handoff declares from_step_id -> to_step_id for every ordered$q$ || chr(10) ||
    $q$  -- pair; a step with no incoming edge is an entry point and always startable. Checked$q$ || chr(10) ||
    $q$  -- before the actor is resolved, because order is a property of the run rather than of$q$ || chr(10) ||
    $q$  -- the caller, and a correct owner arriving early should be told the step is not ready$q$ || chr(10) ||
    $q$  -- rather than that they are the wrong person.$q$ || chr(10) ||
    $q$  if exists (select 1 from public.phase_b_handoff h where h.to_step_id = p_step_id) then$q$ || chr(10) ||
    $q$    if not exists (select 1 from public.phase_b_handoff h$q$ || chr(10) ||
    $q$                    join public.phase_c_workflow_step_run pr$q$ || chr(10) ||
    $q$                      on pr.step_id = h.from_step_id and pr.run_id = p_run_id$q$ || chr(10) ||
    $q$                   where h.to_step_id = p_step_id$q$ || chr(10) ||
    $q$                     and pr.state in ('completed','skipped','superseded')) then$q$ || chr(10) ||
    $q$      return jsonb_build_object('ok', false, 'error','out_of_order',$q$ || chr(10) ||
    $q$        'step', p_step_id,$q$ || chr(10) ||
    $q$        'awaiting', (select string_agg(h.from_step_id, ', ' order by h.from_step_id)$q$ || chr(10) ||
    $q$                       from public.phase_b_handoff h where h.to_step_id = p_step_id),$q$ || chr(10) ||
    $q$        'message', 'Phase B declares a predecessor for this step and it has not reached '$q$ || chr(10) ||
    $q$                   'completed, skipped or superseded in this run.');$q$ || chr(10) ||
    $q$    end if;$q$ || chr(10) ||
    $q$  end if;$q$ || chr(10) || chr(10);

  v_new := replace(v_def, v_anchor, v_insert || v_anchor);
  if v_new = v_def then raise exception 'no substitution took effect'; end if;
  execute v_new;
end $mig$;

-- ------------------------------------------------------------------------------------------------
-- PROVED BY EXECUTION, both directions. A boundary that refuses everything is an outage, not a
-- boundary, so the correct call must still be accepted — and an entry point, which has no declared
-- predecessor, must remain startable or 96 of the 257 steps become unreachable.
-- ------------------------------------------------------------------------------------------------
-- The test drives a REAL run through the REAL entry point, so it writes rows. Those writes are
-- confined to an inner block: in plpgsql a BEGIN ... EXCEPTION is a subtransaction, so raising
-- inside it discards everything it wrote while the migration itself proceeds to commit. A genuine
-- failure is re-raised rather than swallowed — only the rollback marker is caught.
do $mig$
declare v_run bigint; first_step text; first_owner text; last_step text; last_owner text; r jsonb;
begin
 begin
  select public.fn_phase_c_workflow_start('W05','VERIFY-ORDER','{}'::jsonb) into v_run;
  select s.step_id, s.accountable_role_id into first_step, first_owner
    from public.phase_c_step_binding s where s.workflow_id='W05' order by s.step_id limit 1;
  select h.to_step_id, b.accountable_role_id into last_step, last_owner
    from public.phase_b_handoff h
    join public.phase_c_step_binding b on b.step_id = h.to_step_id
   where h.workflow_id='W05' order by h.to_step_id desc limit 1;

  -- a step WITH a declared predecessor, run first, must now be refused
  select public.fn_phase_c_step_advance(v_run, last_step, last_owner, '{}'::jsonb) into r;
  if coalesce((r->>'ok')::boolean, true) then
    raise exception 'STILL OUT OF ORDER: % advanced before its predecessor', last_step;
  end if;
  if (r->>'error') <> 'out_of_order' then
    raise exception 'refused % for the wrong reason: %', last_step, r->>'error';
  end if;

  -- the entry point must still be accepted
  select public.fn_phase_c_step_advance(v_run, first_step, first_owner, '{}'::jsonb) into r;
  if not coalesce((r->>'ok')::boolean, false) then
    raise exception 'ENTRY POINT REFUSED: % -> %', first_step, r::text;
  end if;

  -- and its successor is now unblocked
  select public.fn_phase_c_step_advance(v_run, 'W05-S02',
    (select accountable_role_id from public.phase_c_step_binding where step_id='W05-S02'), '{}'::jsonb) into r;
  if not coalesce((r->>'ok')::boolean, false) then
    raise exception 'SUCCESSOR STILL BLOCKED after its predecessor completed: %', r::text;
  end if;

  raise exception 'QD_ROLLBACK_MARKER';
 exception when others then
   if sqlerrm <> 'QD_ROLLBACK_MARKER' then raise; end if;
 end;
 raise notice 'VERIFIED AND ROLLED BACK: out-of-order refused, entry point accepted, successor unblocked';
end $mig$;

commit;
