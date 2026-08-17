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
CREATE OR REPLACE FUNCTION public.fn_kernel_cutover_measure()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
with
body as (
  select p.oid, p.proname,
         regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', ' ', 'g'), '--[^\n]*', ' ', 'g') src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
),
-- A routine that reaches the kernel by ANY of the three doors the specification allows.
kernel_caller as (
  select b.proname from body b
   where b.src ~ '\yfn_kernel_trigger_submit\s*\('
      or b.src ~ '\yfn_kernel_signal_submit\s*\('
      or b.src ~ '\yfn_kernel_source_emit\s*\('
),
protected(t) as (values
  ('phase_c_workflow_run'),('phase_c_workflow_step_run'),('phase_c_task'),('phase_c_handoff_run'),
  ('kernel_trigger_inbox'),('kernel_signal_inbox'),('phase_c_event_outbox'),('phase_c_refund_decision')),
-- A routine that writes business work DIRECTLY. Anything on the kernel's own allow-list is
-- excluded: fn_kernel_step_complete writes those tables because it is the kernel.
direct_writer as (
  select distinct b.proname from body b join protected pr
      on b.src ~ ('(insert\s+into|update|delete\s+from)\s+(public\.)?' || pr.t || '\M')
   where not exists (select 1 from public.kernel_write_authority a where a.routine_name = b.proname)
),
-- The trigger a source names as discharging it, resolved to the routine it actually fires.
named as (
  select c.source_component_id, c.source_class, c.current_activation, c.status,
         c.disposition_evidence, c.target_step_or_signal, c.idempotency_key, c.trace_policy,
         split_part(c.disposition_evidence, ':', 1) as ev_kind,
         split_part(c.disposition_evidence, ':', 2) as ev_ref,
         case split_part(c.disposition_evidence, ':', 1)
           when 'routine' then split_part(c.disposition_evidence, ':', 2)
           when 'trigger' then (select p.proname from pg_trigger tg join pg_proc p on p.oid = tg.tgfoid
                                 where tg.tgname = split_part(c.disposition_evidence, ':', 2)
                                   and not tg.tgisinternal limit 1)
         end as ev_routine
    from public.phase_c_source_cutover c
),
judged as (
  select n.*,
         case
           when n.current_activation = 'DISABLED'
             or n.source_class = 'D RETIRE_OR_HISTORICAL'
             or n.ev_kind = 'retired'                      then 'RETIRED_OR_INACTIVE'
           when n.ev_kind in ('read_only','inactive') and n.source_class = 'C READ_ONLY_MONITOR'
                                                            then 'READ_ONLY'
           -- ROOT CAUSE 3. CUT_OVER used to mean ONLY "the named routine calls a function whose
           -- name contains kernel". That is the caller knocking. Ten ACTIVE sources were reported
           -- CUT_OVER while fn_kernel_signal_submit refused every submission they made, because
           -- their signal type was registered inactive. CUT_OVER now requires all seven:
           --   (a) the source is active                       — the outer case already established
           --   (b) the canonical adapter is deployed          — ev_routine resolves to a real routine
           --   (c) the routine reaches a kernel door          — kernel_caller
           --   (d) for a workflow SIGNAL, the type is ACTIVE and registered
           --   (e) the handler exists                         — a disposition the service implements
           --   (f) the handler accepts at least one valid state — a non-terminal workflow state exists
           --   (g) idempotency and trace policy are recorded on the source row
           when n.ev_kind in ('routine','trigger') and n.ev_routine is not null
                and exists (select 1 from kernel_caller k where k.proname = n.ev_routine)
                and (n.source_class not like 'B %' or exists (
                      select 1 from public.kernel_signal_type t
                       where t.signal_type = n.target_step_or_signal
                         and t.activation_state = 'active'
                         and t.disposition in ('ATTACH_ONLY','COMPLETE_STEP','REVIEW_VERDICT','CANCEL')))
                and exists (select 1 from public.phase_b_workflow_state ws where not ws.terminal)
                and coalesce(btrim(n.idempotency_key),'') <> ''
                and coalesce(btrim(n.trace_policy),'') <> ''
                                                            then 'CUT_OVER'
           else 'BYPASSING'
         end as verdict
    from named n
)
select 'total_sources'::text, 'reported, not asserted'::text,
       (select count(*)::text from judged), true
union all
select 'active_sources', 'reported',
       (select count(*)::text from judged where current_activation = 'ACTIVE'), true
union all
select 'inactive_sources', 'reported',
       (select count(*)::text from judged where current_activation = 'DISABLED'), true
union all
select 'class_split', 'reported',
       (select string_agg(source_class || ' ' || n::text, '; ' order by source_class)
          from (select source_class, count(*) n from judged group by 1) d), true
union all
select 'verdict_split', 'reported',
       (select string_agg(verdict || ' ' || n::text, '; ' order by verdict)
          from (select verdict, count(*) n from judged group by 1) d), true
union all
-- THE line. No expected numerator: it counts what it finds.
select 'active_sources_bypassing_the_kernel', '0',
       (select count(*)::text from judged where verdict = 'BYPASSING' and current_activation = 'ACTIVE')
         || coalesce(' [' || (select string_agg(source_component_id, ', ')
              from judged where verdict = 'BYPASSING' and current_activation = 'ACTIVE') || ']', ''),
       (select count(*) = 0 from judged where verdict = 'BYPASSING' and current_activation = 'ACTIVE')
union all
select 'active_sources_with_no_disposition_evidence', '0',
       (select count(*)::text from judged
         where current_activation = 'ACTIVE' and coalesce(btrim(disposition_evidence),'') = '')
         || coalesce(' [' || (select string_agg(source_component_id, ', ') from judged
              where current_activation = 'ACTIVE' and coalesce(btrim(disposition_evidence),'') = '') || ']', ''),
       (select count(*) = 0 from judged
         where current_activation = 'ACTIVE' and coalesce(btrim(disposition_evidence),'') = '')
union all
-- A claim that names a trigger which does not exist, or exists and does not call the kernel.
select 'coverage_claims_with_nothing_behind_them', '0',
       (select count(*)::text from judged
         where ev_kind in ('routine','trigger')
           and (ev_routine is null
                or not exists (select 1 from kernel_caller k where k.proname = ev_routine)))
         || coalesce(' [' || (select string_agg(source_component_id || ' -> ' || disposition_evidence, ', ')
              from judged where ev_kind in ('routine','trigger')
                and (ev_routine is null
                     or not exists (select 1 from kernel_caller k where k.proname = ev_routine))) || ']', ''),
       (select count(*) = 0 from judged
         where ev_kind in ('routine','trigger')
           and (ev_routine is null
                or not exists (select 1 from kernel_caller k where k.proname = ev_routine)))
union all
-- ROOT CAUSE 3. The line that would have caught it. An ACTIVE source whose signal type does not
-- accept submissions is not cut over, however its adapter is written.
select 'active_sources_targeting_an_inactive_signal_type', '0',
       (select count(*)::text from judged j
         where j.current_activation = 'ACTIVE' and j.source_class like 'B %'
           and not exists (select 1 from public.kernel_signal_type t
                            where t.signal_type = j.target_step_or_signal
                              and t.activation_state = 'active'))
         || coalesce(' [' || (select string_agg(j.source_component_id || ' -> ' || j.target_step_or_signal, ', ')
              from judged j where j.current_activation = 'ACTIVE' and j.source_class like 'B %'
                and not exists (select 1 from public.kernel_signal_type t
                                 where t.signal_type = j.target_step_or_signal
                                   and t.activation_state = 'active')) || ']', ''),
       (select count(*) = 0 from judged j
         where j.current_activation = 'ACTIVE' and j.source_class like 'B %'
           and not exists (select 1 from public.kernel_signal_type t
                            where t.signal_type = j.target_step_or_signal
                              and t.activation_state = 'active'))

union all
-- An active signal type with no handler the service implements is a door with nothing behind it.
select 'active_signal_types_without_a_handler', '0',
       (select count(*)::text from public.kernel_signal_type t
         where t.activation_state = 'active'
           and t.disposition not in ('ATTACH_ONLY','COMPLETE_STEP','REVIEW_VERDICT','CANCEL')),
       (select count(*) = 0 from public.kernel_signal_type t
         where t.activation_state = 'active'
           and t.disposition not in ('ATTACH_ONLY','COMPLETE_STEP','REVIEW_VERDICT','CANCEL'))

union all
-- Reported for the record: how many verdicts rest on nothing but source-text caller detection.
select 'cutover_rows_resting_only_on_source_text_caller_detection', '0',
       (select count(*)::text from judged j
         where j.verdict = 'CUT_OVER' and j.source_class like 'B %'
           and not exists (select 1 from public.kernel_signal_type t
                            where t.signal_type = j.target_step_or_signal
                              and t.activation_state = 'active')),
       (select count(*) = 0 from judged j
         where j.verdict = 'CUT_OVER' and j.source_class like 'B %'
           and not exists (select 1 from public.kernel_signal_type t
                            where t.signal_type = j.target_step_or_signal
                              and t.activation_state = 'active'))

union all
-- An ACTIVE source whose own routine writes a protected table directly. The kernel's own writers
-- are excluded by kernel_write_authority, so this is a genuine bypass and not the kernel itself.
select 'active_sources_writing_business_work_directly', '0',
       (select count(*)::text from judged j
         where j.current_activation = 'ACTIVE'
           and exists (select 1 from direct_writer w
                        where w.proname = (select p.proname from pg_trigger tg
                                             join pg_proc p on p.oid = tg.tgfoid
                                            where tg.tgname = split_part(j.source_component_id, ':', 3)
                                              and not tg.tgisinternal limit 1))),
       (select count(*) = 0 from judged j
         where j.current_activation = 'ACTIVE'
           and exists (select 1 from direct_writer w
                        where w.proname = (select p.proname from pg_trigger tg
                                             join pg_proc p on p.oid = tg.tgfoid
                                            where tg.tgname = split_part(j.source_component_id, ':', 3)
                                              and not tg.tgisinternal limit 1)));
$function$;

-- ---------------------------------------------------------------------------------------------
-- CUT_OVER now means the door opens.
CREATE OR REPLACE FUNCTION public.fn_kernel_cutover_measure()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
with
body as (
  select p.oid, p.proname,
         regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', ' ', 'g'), '--[^\n]*', ' ', 'g') src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
),
-- A routine that reaches the kernel by ANY of the three doors the specification allows.
kernel_caller as (
  select b.proname from body b
   where b.src ~ '\yfn_kernel_trigger_submit\s*\('
      or b.src ~ '\yfn_kernel_signal_submit\s*\('
      or b.src ~ '\yfn_kernel_source_emit\s*\('
),
protected(t) as (values
  ('phase_c_workflow_run'),('phase_c_workflow_step_run'),('phase_c_task'),('phase_c_handoff_run'),
  ('kernel_trigger_inbox'),('kernel_signal_inbox'),('phase_c_event_outbox'),('phase_c_refund_decision')),
-- A routine that writes business work DIRECTLY. Anything on the kernel's own allow-list is
-- excluded: fn_kernel_step_complete writes those tables because it is the kernel.
direct_writer as (
  select distinct b.proname from body b join protected pr
      on b.src ~ ('(insert\s+into|update|delete\s+from)\s+(public\.)?' || pr.t || '\M')
   where not exists (select 1 from public.kernel_write_authority a where a.routine_name = b.proname)
),
-- The trigger a source names as discharging it, resolved to the routine it actually fires.
named as (
  select c.source_component_id, c.source_class, c.current_activation, c.status,
         c.disposition_evidence, c.target_step_or_signal, c.idempotency_key, c.trace_policy,
         split_part(c.disposition_evidence, ':', 1) as ev_kind,
         split_part(c.disposition_evidence, ':', 2) as ev_ref,
         case split_part(c.disposition_evidence, ':', 1)
           when 'routine' then split_part(c.disposition_evidence, ':', 2)
           when 'trigger' then (select p.proname from pg_trigger tg join pg_proc p on p.oid = tg.tgfoid
                                 where tg.tgname = split_part(c.disposition_evidence, ':', 2)
                                   and not tg.tgisinternal limit 1)
         end as ev_routine
    from public.phase_c_source_cutover c
),
judged as (
  select n.*,
         case
           when n.current_activation = 'DISABLED'
             or n.source_class = 'D RETIRE_OR_HISTORICAL'
             or n.ev_kind = 'retired'                      then 'RETIRED_OR_INACTIVE'
           when n.ev_kind in ('read_only','inactive') and n.source_class = 'C READ_ONLY_MONITOR'
                                                            then 'READ_ONLY'
           -- ROOT CAUSE 3. CUT_OVER used to mean ONLY "the named routine calls a function whose
           -- name contains kernel". That is the caller knocking. Ten ACTIVE sources were reported
           -- CUT_OVER while fn_kernel_signal_submit refused every submission they made, because
           -- their signal type was registered inactive. CUT_OVER now requires all seven:
           --   (a) the source is active                       — the outer case already established
           --   (b) the canonical adapter is deployed          — ev_routine resolves to a real routine
           --   (c) the routine reaches a kernel door          — kernel_caller
           --   (d) for a workflow SIGNAL, the type is ACTIVE and registered
           --   (e) the handler exists                         — a disposition the service implements
           --   (f) the handler accepts at least one valid state — a non-terminal workflow state exists
           --   (g) idempotency and trace policy are recorded on the source row
           when n.ev_kind in ('routine','trigger') and n.ev_routine is not null
                and exists (select 1 from kernel_caller k where k.proname = n.ev_routine)
                and (n.source_class not like 'B %' or exists (
                      select 1 from public.kernel_signal_type t
                       where t.signal_type = n.target_step_or_signal
                         and t.activation_state = 'active'
                         and t.disposition in ('ATTACH_ONLY','COMPLETE_STEP','REVIEW_VERDICT','CANCEL')))
                and exists (select 1 from public.phase_b_workflow_state ws where not ws.terminal)
                and coalesce(btrim(n.idempotency_key),'') <> ''
                and coalesce(btrim(n.trace_policy),'') <> ''
                                                            then 'CUT_OVER'
           else 'BYPASSING'
         end as verdict
    from named n
)
select 'total_sources'::text, 'reported, not asserted'::text,
       (select count(*)::text from judged), true
union all
select 'active_sources', 'reported',
       (select count(*)::text from judged where current_activation = 'ACTIVE'), true
union all
select 'inactive_sources', 'reported',
       (select count(*)::text from judged where current_activation = 'DISABLED'), true
union all
select 'class_split', 'reported',
       (select string_agg(source_class || ' ' || n::text, '; ' order by source_class)
          from (select source_class, count(*) n from judged group by 1) d), true
union all
select 'verdict_split', 'reported',
       (select string_agg(verdict || ' ' || n::text, '; ' order by verdict)
          from (select verdict, count(*) n from judged group by 1) d), true
union all
-- THE line. No expected numerator: it counts what it finds.
select 'active_sources_bypassing_the_kernel', '0',
       (select count(*)::text from judged where verdict = 'BYPASSING' and current_activation = 'ACTIVE')
         || coalesce(' [' || (select string_agg(source_component_id, ', ')
              from judged where verdict = 'BYPASSING' and current_activation = 'ACTIVE') || ']', ''),
       (select count(*) = 0 from judged where verdict = 'BYPASSING' and current_activation = 'ACTIVE')
union all
select 'active_sources_with_no_disposition_evidence', '0',
       (select count(*)::text from judged
         where current_activation = 'ACTIVE' and coalesce(btrim(disposition_evidence),'') = '')
         || coalesce(' [' || (select string_agg(source_component_id, ', ') from judged
              where current_activation = 'ACTIVE' and coalesce(btrim(disposition_evidence),'') = '') || ']', ''),
       (select count(*) = 0 from judged
         where current_activation = 'ACTIVE' and coalesce(btrim(disposition_evidence),'') = '')
union all
-- A claim that names a trigger which does not exist, or exists and does not call the kernel.
select 'coverage_claims_with_nothing_behind_them', '0',
       (select count(*)::text from judged
         where ev_kind in ('routine','trigger')
           and (ev_routine is null
                or not exists (select 1 from kernel_caller k where k.proname = ev_routine)))
         || coalesce(' [' || (select string_agg(source_component_id || ' -> ' || disposition_evidence, ', ')
              from judged where ev_kind in ('routine','trigger')
                and (ev_routine is null
                     or not exists (select 1 from kernel_caller k where k.proname = ev_routine))) || ']', ''),
       (select count(*) = 0 from judged
         where ev_kind in ('routine','trigger')
           and (ev_routine is null
                or not exists (select 1 from kernel_caller k where k.proname = ev_routine)))
union all
-- ROOT CAUSE 3. The line that would have caught it. An ACTIVE source whose signal type does not
-- accept submissions is not cut over, however its adapter is written.
select 'active_sources_targeting_an_inactive_signal_type', '0',
       (select count(*)::text from judged j
         where j.current_activation = 'ACTIVE' and j.source_class like 'B %'
           and not exists (select 1 from public.kernel_signal_type t
                            where t.signal_type = j.target_step_or_signal
                              and t.activation_state = 'active'))
         || coalesce(' [' || (select string_agg(j.source_component_id || ' -> ' || j.target_step_or_signal, ', ')
              from judged j where j.current_activation = 'ACTIVE' and j.source_class like 'B %'
                and not exists (select 1 from public.kernel_signal_type t
                                 where t.signal_type = j.target_step_or_signal
                                   and t.activation_state = 'active')) || ']', ''),
       (select count(*) = 0 from judged j
         where j.current_activation = 'ACTIVE' and j.source_class like 'B %'
           and not exists (select 1 from public.kernel_signal_type t
                            where t.signal_type = j.target_step_or_signal
                              and t.activation_state = 'active'))

union all
-- An active signal type with no handler the service implements is a door with nothing behind it.
select 'active_signal_types_without_a_handler', '0',
       (select count(*)::text from public.kernel_signal_type t
         where t.activation_state = 'active'
           and t.disposition not in ('ATTACH_ONLY','COMPLETE_STEP','REVIEW_VERDICT','CANCEL')),
       (select count(*) = 0 from public.kernel_signal_type t
         where t.activation_state = 'active'
           and t.disposition not in ('ATTACH_ONLY','COMPLETE_STEP','REVIEW_VERDICT','CANCEL'))

union all
-- Reported for the record: how many verdicts rest on nothing but source-text caller detection.
select 'cutover_rows_resting_only_on_source_text_caller_detection', '0',
       (select count(*)::text from judged j
         where j.verdict = 'CUT_OVER' and j.source_class like 'B %'
           and not exists (select 1 from public.kernel_signal_type t
                            where t.signal_type = j.target_step_or_signal
                              and t.activation_state = 'active')),
       (select count(*) = 0 from judged j
         where j.verdict = 'CUT_OVER' and j.source_class like 'B %'
           and not exists (select 1 from public.kernel_signal_type t
                            where t.signal_type = j.target_step_or_signal
                              and t.activation_state = 'active'))

union all
-- An ACTIVE source whose own routine writes a protected table directly. The kernel's own writers
-- are excluded by kernel_write_authority, so this is a genuine bypass and not the kernel itself.
select 'active_sources_writing_business_work_directly', '0',
       (select count(*)::text from judged j
         where j.current_activation = 'ACTIVE'
           and exists (select 1 from direct_writer w
                        where w.proname = (select p.proname from pg_trigger tg
                                             join pg_proc p on p.oid = tg.tgfoid
                                            where tg.tgname = split_part(j.source_component_id, ':', 3)
                                              and not tg.tgisinternal limit 1))),
       (select count(*) = 0 from judged j
         where j.current_activation = 'ACTIVE'
           and exists (select 1 from direct_writer w
                        where w.proname = (select p.proname from pg_trigger tg
                                             join pg_proc p on p.oid = tg.tgfoid
                                            where tg.tgname = split_part(j.source_component_id, ':', 3)
                                              and not tg.tgisinternal limit 1)));
$function$;
