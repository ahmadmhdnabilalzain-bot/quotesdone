-- ROOT CAUSE 3 — AN ACTIVE SOURCE MAY NOT POINT AT A SIGNAL TYPE THAT REFUSES IT.
--
-- The final Phase C acceptance found 12 ACTIVE EXISTING_WORKFLOW_SIGNAL sources and 10 of them
-- naming a signal type whose activation_state is 'inactive'. fn_kernel_signal_submit refuses those
-- at step 3 — proved by execution, not inferred:
--
--   signal type 'supplier.quote_revision' is registered with activation_state 'inactive' and does
--   not accept submissions.
--
-- fn_kernel_cutover_measure nevertheless gave all 12 the verdict CUT_OVER, because its test is
-- "the routine named in disposition_evidence calls one of the three kernel doors". It asked whether
-- the caller knocks. It never asked whether the door opens.
--
-- WHAT THIS FILE DOES NOT DO: it does not flip a flag. Five signal types are activated, and each
-- one is activated because its handler is already implemented in fn_kernel_signal_submit and was
-- driven end to end by a fixture before this file was written. The other five stay inactive and are
-- said to stay inactive, with the reason recorded, because no active source points at them.
--
--   ACTIVATED (option A, IMPLEMENT_AND_ACTIVATE — handler present, behaviour declared in Phase B)
--     clarification.response    COMPLETE_STEP    W18, from edge:messages_api and ui:/[locale]/me
--     followup.due              ATTACH_ONLY      W12, from inquiry_matches:notify_matched_supplier
--     provider.callback         ATTACH_ONLY      W09/W16/W17, four sources
--     supplier.acknowledgement  ATTACH_ONLY      any run, from edge:supplier_ack
--     supplier.quote_revision   ATTACH_ONLY      W14, from quote_items_roll and edge:supplier_portal
--
--   LEFT INACTIVE, deliberately, and no ACTIVE source points at any of them
--     deadline.due, retry.due, sla.breach        no source emits them yet
--     review.verdict                             reviews are recorded through fn_kernel_review_decide
--                                                by the reviewer, not by an external signal
--     run.cancellation_requested                 cancellation has a founder-facing control and the
--                                                canonical fn_kernel_cancel; a third door is not
--                                                needed and would be a second way to cancel
--
-- THE RULE IS NOW ENFORCED, NOT ASSERTED. Two triggers make "an active source may not point at an
-- inactive signal type" impossible to reintroduce from either side: deactivating a type that an
-- ACTIVE source names is refused, and activating a source whose type is inactive is refused.
--
-- Rollback: scripts/sql/rollback/rc3_active_signals_are_executable.rollback.sql

alter table public.kernel_signal_type
  add column if not exists activation_reason text,
  add column if not exists activation_changed_at timestamptz;

comment on column public.kernel_signal_type.activation_reason is
  'Why this type is in its current activation_state, in words. Added 17 Aug 2026 (root cause 3): an '
  'activation_state with no recorded reason is a flag, and a flag is what let ten active sources '
  'point at a door that refused them.';

-- ---------------------------------------------------------------------------------------------
-- The five types an ACTIVE source depends on. Each handler already exists in fn_kernel_signal_submit
-- and each was driven by a fixture before activation; the reason says which handler and why.
update public.kernel_signal_type set
  activation_state = 'active',
  activation_changed_at = now(),
  activation_reason =
    'Activated 17 Aug 2026, root cause 3, option A IMPLEMENT_AND_ACTIVATE. The COMPLETE_STEP handler '
    'is implemented in fn_kernel_signal_submit: it finds the run''s active step, refuses when the '
    'payload carries no output object (an empty answer is not an answer), and otherwise completes '
    'the step through fn_kernel_step_complete with the signal as its evidence. edge:messages_api and '
    'ui:/[locale]/me are ACTIVE sources for it and were being refused.'
where signal_type = 'clarification.response';

update public.kernel_signal_type set
  activation_state = 'active',
  activation_changed_at = now(),
  activation_reason =
    'Activated 17 Aug 2026, root cause 3, option A IMPLEMENT_AND_ACTIVATE. ATTACH_ONLY is fully '
    'implemented in fn_kernel_signal_submit and is the same path document.arrived_for_run already '
    'runs on: the signal is validated against the run''s current state, attached to its active step '
    'run, and recorded with correlation and causation. It does NOT complete a step, which is the '
    'point — the clock arriving is not evidence the follow-up produced anything. '
    'dbtrigger:public.inquiry_matches:notify_matched_supplier is an ACTIVE source and was refused.'
where signal_type = 'followup.due';

update public.kernel_signal_type set
  activation_state = 'active',
  activation_changed_at = now(),
  activation_reason =
    'Activated 17 Aug 2026, root cause 3, option A IMPLEMENT_AND_ACTIVATE. ATTACH_ONLY, same '
    'implemented handler. Four ACTIVE sources depend on it and every one was refused: '
    'notifications:trg_invite_status_on_send (W09), supplier_dues:trg_due_paid (W16), '
    'transactions:trg_refund_resolved (W17) and edge:stripe_confirm (W16). The NEW payment event '
    'that opens W16 is a trigger type and stays in the trigger inbox; this is only the callback '
    'about an object already inside a run.'
where signal_type = 'provider.callback';

update public.kernel_signal_type set
  activation_state = 'active',
  activation_changed_at = now(),
  activation_reason =
    'Activated 17 Aug 2026, root cause 3, option A IMPLEMENT_AND_ACTIVATE. ATTACH_ONLY, same '
    'implemented handler. edge:supplier_ack is an ACTIVE source and was refused. It stays '
    'ATTACH_ONLY and not COMPLETE_STEP for the reason already recorded against it: acknowledging '
    'contact is not finishing the step, and closing work on the strength of a click would certify '
    'work nobody did.'
where signal_type = 'supplier.acknowledgement';

update public.kernel_signal_type set
  activation_state = 'active',
  activation_changed_at = now(),
  activation_reason =
    'Activated 17 Aug 2026, root cause 3, option A IMPLEMENT_AND_ACTIVATE. ATTACH_ONLY, same '
    'implemented handler, declared for W14 so a revision cannot land on another workflow''s run. '
    'dbtrigger:public.quote_items:quote_items_roll and edge:supplier_portal are ACTIVE sources and '
    'both were refused.'
where signal_type = 'supplier.quote_revision';

-- The one type that was ALREADY active carried no reason either, which is the same gap seen from
-- the other side: it worked, so nobody wrote down why it was allowed to.
update public.kernel_signal_type set
  activation_reason =
    'Active before root cause 3 and left active. ATTACH_ONLY, the reference implementation of the '
    'handler: a document arriving for an inquiry already being worked is evidence on that run, not '
    'a new intake. W07 already owns the workflow for a NEW document, and opening a second run for a '
    'file attached to live work would be a duplicate. Reason recorded 17 Aug 2026 — it was the only '
    'type that accepted submissions, and nothing said why it was the only one.'
where signal_type = 'document.arrived_for_run' and activation_reason is null;

-- The five that stay inactive say so, so that "inactive" is a decision on the record rather than an
-- absence somebody has to guess at.
update public.kernel_signal_type set
  activation_reason = coalesce(activation_reason,
    'Left inactive 17 Aug 2026, root cause 3. No ACTIVE source in phase_c_source_cutover names this '
    'type, so nothing is being refused. It is registered and its handler is implemented; activating '
    'it before a source exists would open a door with nobody behind it.')
where activation_state <> 'active' and activation_reason is null;

update public.kernel_signal_type set
  activation_reason =
    'Left inactive 17 Aug 2026, root cause 3. A review verdict is recorded by the reviewer through '
    'fn_kernel_review_decide, where independence is enforced against the task''s own owner. An '
    'external signal that could record a verdict would be a second way to approve work, and the '
    'independence check is the whole value of the first one.'
where signal_type = 'review.verdict';

update public.kernel_signal_type set
  activation_reason =
    'Left inactive 17 Aug 2026, root cause 3. Cancellation already has exactly two doors: the '
    'founder-facing fn_founder_command_control, which as of root cause 2 delegates to it, and '
    'fn_kernel_cancel itself. A third would be a second way to cancel, and root cause 2 exists '
    'because there were two.'
where signal_type = 'run.cancellation_requested';

-- ---------------------------------------------------------------------------------------------
-- ENFORCEMENT, from both sides.
create or replace function public.fn_kernel_signal_type_activation_guard()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $rc3a$
declare v_srcs text;
begin
  if new.activation_state = 'active' or new.activation_state = old.activation_state then
    return new;
  end if;
  select string_agg(c.source_component_id, ', ' order by c.source_component_id) into v_srcs
    from public.phase_c_source_cutover c
   where c.current_activation = 'ACTIVE' and c.target_step_or_signal = new.signal_type;
  if v_srcs is not null then
    raise exception
      'signal type %L cannot be moved to %L: % ACTIVE source(s) still point at it (%). Deactivate '
      'or repoint the source first — an active source pointing at an inactive type is refused at '
      'submission and reported as cut over, which is the defect root cause 3 closed.',
      new.signal_type, new.activation_state,
      (select count(*) from public.phase_c_source_cutover c
        where c.current_activation='ACTIVE' and c.target_step_or_signal = new.signal_type),
      v_srcs
      using errcode = '23514';
  end if;
  return new;
end
$rc3a$;

revoke execute on function public.fn_kernel_signal_type_activation_guard() from public, anon, authenticated;

drop trigger if exists z10_signal_type_activation_guard on public.kernel_signal_type;
create trigger z10_signal_type_activation_guard
  before update on public.kernel_signal_type
  for each row execute function public.fn_kernel_signal_type_activation_guard();

create or replace function public.fn_kernel_source_signal_guard()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $rc3b$
declare v_state text;
begin
  if new.current_activation <> 'ACTIVE' or new.source_class not like 'B %' then
    return new;
  end if;
  select t.activation_state into v_state
    from public.kernel_signal_type t where t.signal_type = new.target_step_or_signal;
  if v_state is null then
    raise exception
      'source % is ACTIVE and names signal type %L, which is not registered in kernel_signal_type. '
      'A signal the kernel has never heard of is refused at submission, so the source would be '
      'recorded as cut over while every delivery from it failed.',
      new.source_component_id, coalesce(new.target_step_or_signal,'(null)') using errcode = '23503';
  end if;
  if v_state <> 'active' then
    raise exception
      'source % is ACTIVE and names signal type %L, whose activation_state is %L. '
      'fn_kernel_signal_submit refuses every submission of an inactive type, so this source would '
      'be reported CUT_OVER while nothing it emits is ever accepted. Activate the type with a '
      'recorded reason, or set the source to DISABLED.',
      new.source_component_id, new.target_step_or_signal, v_state using errcode = '23514';
  end if;
  return new;
end
$rc3b$;

revoke execute on function public.fn_kernel_source_signal_guard() from public, anon, authenticated;

drop trigger if exists z10_source_signal_guard on public.phase_c_source_cutover;
create trigger z10_source_signal_guard
  before insert or update on public.phase_c_source_cutover
  for each row execute function public.fn_kernel_source_signal_guard();

-- ---------------------------------------------------------------------------------------------
-- CUT_OVER now means the door opens.
-- ROUTINE REMOVED 7 September 2026. public.fn_kernel_cutover_measure was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ---------------------------------------------------------------------------------------------
-- CUT_OVER now means the door opens.
-- ROUTINE REMOVED 7 September 2026. public.fn_kernel_cutover_measure was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

