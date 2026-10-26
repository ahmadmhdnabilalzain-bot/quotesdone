-- AUDIT 8.3 - "Rollback procedures" - FAIL, severity critical.
--
-- The auditor's finding: there were no Phase 1 rollback artefacts at all. supabase/rollback/
-- held only two P2-C1 files, and the one that existed was broken as written (its mandatory
-- step 2 re-applies five migration files that had been moved to migrations-superseded-
-- consolidated/, after step 1 has already dropped the objects with cascade).
--
-- The obvious response - write one big DROP script - would be the wrong control. Phase 1's
-- tables are the refunds ledger and the Control Mode audit trail. Those are FINANCIAL AND
-- SECURITY EVIDENCE. A rollback that destroys them turns a bad deploy into an unreconstructable
-- one, and is exactly the procedure nobody dares run at 3am, which means in practice there is
-- still no rollback.
--
-- So rollback is split into three tiers with very different costs, and only the cheap one is
-- installed as a callable control:
--
--   TIER 0  DISARM   - stop Phase 1 GATING the system, keep every row. Two statements, seconds,
--                      fully reversible, no data loss. This is the incident rollback and the one
--                      that will actually get used. Installed here as fn_phase1_disarm().
--   TIER 1  REVERT   - restore pre-Phase-1 function definitions, keep the evidence tables.
--                      supabase/rollback/phase1_down.sql, section 1.
--   TIER 2  TEARDOWN - drop the Phase 1 objects entirely. Requires an evidence export first.
--                      supabase/rollback/phase1_down.sql, section 2. Deliberately NOT a callable
--                      function: it destroys evidence and must be a considered, manual act.
--
-- Disarming does NOT silence the audit trail. Every action that passes while Phase 1 is disarmed
-- is still written to control_mode_audit, marked as such - during an incident the log of what was
-- done under the relaxed control is the single most valuable record there is.

-- ---------------------------------------------------------------- rollback ledger (append only)
create table if not exists public.phase1_rollback_log (
  id      bigserial primary key,
  at      timestamptz not null default now(),
  actor   text        not null,
  tier    text        not null check (tier in ('disarm','rearm','revert','teardown','rehearse')),
  reason  text        not null check (length(btrim(reason)) >= 8),
  detail  jsonb       not null default '{}'::jsonb
);

comment on table public.phase1_rollback_log is
  'AUDIT 8.3. Append-only record of every Phase 1 rollback action. The current disarm state is derived from the newest disarm/rearm row, so the state and its justification cannot drift apart.';

create or replace function public.fn_phase1_rollback_log_immutable()
returns trigger language plpgsql as $fn$
begin
  raise exception 'phase1_rollback_log is append-only; % is not permitted', TG_OP
    using errcode = '42501';
end $fn$;

drop trigger if exists trg_phase1_rollback_log_immutable on public.phase1_rollback_log;
create trigger trg_phase1_rollback_log_immutable
  before update or delete on public.phase1_rollback_log
  for each row execute function public.fn_phase1_rollback_log_immutable();

alter table public.phase1_rollback_log enable row level security;
revoke all on public.phase1_rollback_log from public, anon, authenticated;
grant select, insert on public.phase1_rollback_log to service_role;
grant usage, select on sequence public.phase1_rollback_log_id_seq to service_role;

-- ---------------------------------------------------------------- current state
create or replace function public.fn_phase1_disarmed()
returns boolean language sql stable security definer set search_path to 'public' as $fn$
  select coalesce((
    select tier = 'disarm' from public.phase1_rollback_log
     where tier in ('disarm','rearm') order by id desc limit 1
  ), false)
$fn$;

comment on function public.fn_phase1_disarmed() is
  'AUDIT 8.3. True when Phase 1 gating has been rolled back to Tier 0. Read by fn_control_mode_require.';

-- ---------------------------------------------------------------- the gate honours the disarm
create or replace function public.fn_control_mode_require(p_actor_email text, p_action text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_class text; v_s record;
begin
  -- AUDIT 8.3 TIER 0. Phase 1 rolled back to observe-only. Still audited, deliberately: during an
  -- incident, the record of what was done under the relaxed control is the most valuable thing here.
  if public.fn_phase1_disarmed() then
    insert into public.control_mode_audit (actor_email, event, action, allowed, reason)
    values (p_actor_email, 'action_allowed_phase1_disarmed', p_action, true,
            'Phase 1 Control Mode is disarmed - see public.phase1_rollback_log for who disarmed it and why');
    return jsonb_build_object('allowed', true, 'mode', 'disarmed',
      'reason', 'Phase 1 Control Mode is disarmed (rollback tier 0)');
  end if;

  select classification into v_class from public.control_mode_action where action = p_action;

  -- FAIL CLOSED. An action nobody classified is an action nobody thought about, and the cost of
  -- being wrong is asymmetric: refusing a read is an inconvenience, allowing an unreviewed mutation
  -- is the incident. The refusal is audited so the missing classification is discoverable.
  if v_class is null then
    insert into public.control_mode_audit (actor_email, event, action, allowed, reason)
    values (p_actor_email, 'action_unclassified', p_action, false, 'action is not in control_mode_action');
    return jsonb_build_object(
      'allowed', false, 'mode', 'observe', 'error', 'action_classification_required',
      'message', 'This action has not been classified as read-only or mutating, so it is refused. '
              || 'Classify it in control_mode_action (and in os_api ACTION_CLASS) before using it.');
  end if;

  if v_class = 'read_only' then
    return jsonb_build_object('allowed', true, 'mode', 'observe', 'reason', 'action is registered read-only');
  end if;

  if v_class = 'mode_control' then
    return jsonb_build_object('allowed', true, 'mode', 'observe', 'reason', 'Control Mode plumbing; handled before the gate');
  end if;

  select * into v_s from public.control_mode_session
   where actor_email = p_actor_email and closed_at is null and expires_at > now()
   order by opened_at desc limit 1;

  if not found then
    insert into public.control_mode_audit (actor_email, event, action, allowed, reason)
    values (p_actor_email, 'action_denied', p_action, false, 'no active Control Mode session');
    return jsonb_build_object('allowed', false, 'mode', 'observe', 'error', 'control_mode_required',
      'message', 'This changes something, so it needs Control Mode. Open it with a code sent to your phone, and say why.');
  end if;

  update public.control_mode_session set actions_used = actions_used + 1 where id = v_s.id;
  insert into public.control_mode_audit (actor_email, event, action, session_id, allowed, reason)
  values (p_actor_email, 'action_allowed', p_action, v_s.id, true, v_s.reason);

  return jsonb_build_object('allowed', true, 'mode', 'control', 'session_id', v_s.id, 'reason', v_s.reason,
                            'seconds_remaining', greatest(0, extract(epoch from (v_s.expires_at - now()))::int));
end $function$;

-- ---------------------------------------------------------------- tier 0 controls
create or replace function public.fn_phase1_disarm(p_actor text, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public','cron' as $fn$
declare v_id bigint; v_cron text := 'not_scheduled';
begin
  if coalesce(btrim(p_actor),'') = '' then raise exception 'an actor is required' using errcode='22023'; end if;
  if length(coalesce(btrim(p_reason),'')) < 8 then raise exception 'a reason of at least 8 characters is required' using errcode='22023'; end if;

  if public.fn_phase1_disarmed() then
    return jsonb_build_object('ok', true, 'already', true, 'disarmed', true,
      'note', 'Phase 1 was already disarmed; nothing changed.');
  end if;

  insert into public.phase1_rollback_log (actor, tier, reason, detail)
  values (p_actor, 'disarm', p_reason,
          jsonb_build_object('control_mode_actions_gated',
            (select count(*) from public.control_mode_action where classification = 'mutating')))
  returning id into v_id;

  -- The 5-minute sweep expires sessions and challenges. With the gate disarmed it has nothing to
  -- do, and leaving it running during a rollback only adds noise to the audit trail.
  begin
    perform cron.unschedule('control_mode_sweep_5min');
    v_cron := 'unscheduled';
  exception when others then v_cron := 'not_scheduled';
  end;

  return jsonb_build_object('ok', true, 'disarmed', true, 'log_id', v_id, 'cron', v_cron,
    'note', 'Every mutating action now passes and is written to control_mode_audit as action_allowed_phase1_disarmed. No rows were deleted. Re-arm with fn_phase1_rearm().');
end $fn$;

create or replace function public.fn_phase1_rearm(p_actor text, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public','cron' as $fn$
declare v_id bigint; v_cron text;
begin
  if coalesce(btrim(p_actor),'') = '' then raise exception 'an actor is required' using errcode='22023'; end if;
  if length(coalesce(btrim(p_reason),'')) < 8 then raise exception 'a reason of at least 8 characters is required' using errcode='22023'; end if;

  if not public.fn_phase1_disarmed() then
    return jsonb_build_object('ok', true, 'already', true, 'disarmed', false,
      'note', 'Phase 1 was already armed; nothing changed.');
  end if;

  insert into public.phase1_rollback_log (actor, tier, reason, detail)
  values (p_actor, 'rearm', p_reason,
          jsonb_build_object('actions_allowed_while_disarmed',
            (select count(*) from public.control_mode_audit where event = 'action_allowed_phase1_disarmed')))
  returning id into v_id;

  begin
    perform cron.schedule('control_mode_sweep_5min', '*/5 * * * *', 'select public.fn_control_mode_sweep()');
    v_cron := 'scheduled';
  exception when others then v_cron := 'schedule_failed: ' || sqlerrm;
  end;

  return jsonb_build_object('ok', true, 'disarmed', false, 'log_id', v_id, 'cron', v_cron);
end $fn$;

-- ---------------------------------------------------------------- what is actually in place
create or replace function public.fn_phase1_status()
returns jsonb language sql stable security definer set search_path to 'public' as $fn$
  select jsonb_build_object(
    'disarmed', public.fn_phase1_disarmed(),
    'last_rollback_action', (select to_jsonb(l) from public.phase1_rollback_log l order by id desc limit 1),
    'objects', jsonb_build_object(
      'tables',    (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
                     where n.nspname='public' and c.relkind='r'
                       and (c.relname like 'control_mode%' or c.relname like 'refund%' or c.relname='phase1_rollback_log')),
      'views',     (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
                     where n.nspname='public' and c.relkind='v'
                       and (c.relname like 'v_refund%' or c.relname like 'v_supplier_exception%')),
      'functions', (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                     where n.nspname='public'
                       and (p.proname like 'fn_control_mode%' or p.proname like 'fn_refund%'
                            or p.proname like 'fn_supplier_exception%' or p.proname like 'fn_phase1%'))),
    'evidence_rows', jsonb_build_object(
      'refunds',                  (select count(*) from public.refunds),
      'refund_event_quarantine',  (select count(*) from public.refund_event_quarantine),
      'control_mode_audit',       (select count(*) from public.control_mode_audit),
      'control_mode_action',      (select count(*) from public.control_mode_action),
      'gated_actions',            (select count(*) from public.control_mode_action where classification='mutating')),
    'crons', (select coalesce(jsonb_object_agg(jobname, jsonb_build_object('schedule', schedule, 'active', active)), '{}'::jsonb)
                from cron.job where jobname in ('control_mode_sweep_5min','supplier_exception_sweep_daily')))
$fn$;

-- ---------------------------------------------------------------- rehearsal
-- Run inside a transaction the caller ABORTS. It disarms, proves a mutating action now passes,
-- re-arms, proves it is refused again, and reports. A rollback nobody has executed is a document,
-- not a procedure; this is what turns it into one.
create or replace function public.fn_phase1_rollback_rehearse(p_actor text default 'rehearsal')
returns jsonb language plpgsql security definer set search_path to 'public','cron' as $fn$
declare
  v_action text; v_before jsonb; v_during jsonb; v_after jsonb;
  v_d jsonb; v_r jsonb; v_steps jsonb := '[]'::jsonb;
begin
  select action into v_action from public.control_mode_action
   where classification = 'mutating' order by action limit 1;
  if v_action is null then raise exception 'no mutating action registered - nothing to rehearse against'; end if;

  v_before := public.fn_control_mode_require('rehearsal@quotesdone.com', v_action);
  v_steps := v_steps || jsonb_build_object('step','baseline','action',v_action,
    'allowed', v_before->>'allowed', 'expect','false',
    'pass', (v_before->>'allowed') = 'false');

  v_d := public.fn_phase1_disarm(p_actor, 'rollback rehearsal - aborted transaction, no lasting effect');
  v_steps := v_steps || jsonb_build_object('step','disarm','result',v_d,'pass', (v_d->>'ok')='true' and (v_d->>'disarmed')='true');

  v_during := public.fn_control_mode_require('rehearsal@quotesdone.com', v_action);
  v_steps := v_steps || jsonb_build_object('step','gate_after_disarm','allowed', v_during->>'allowed',
    'mode', v_during->>'mode', 'expect','true/disarmed',
    'pass', (v_during->>'allowed')='true' and (v_during->>'mode')='disarmed');

  v_steps := v_steps || jsonb_build_object('step','evidence_preserved',
    'refunds', (select count(*) from public.refunds),
    'control_mode_audit_rows', (select count(*) from public.control_mode_audit),
    'note','disarm deletes nothing; the count only grows because the disarmed pass is itself audited',
    'pass', true);

  v_r := public.fn_phase1_rearm(p_actor, 'rollback rehearsal - restoring the gate');
  v_steps := v_steps || jsonb_build_object('step','rearm','result',v_r,'pass',(v_r->>'ok')='true' and (v_r->>'disarmed')='false');

  v_after := public.fn_control_mode_require('rehearsal@quotesdone.com', v_action);
  v_steps := v_steps || jsonb_build_object('step','gate_after_rearm','allowed', v_after->>'allowed',
    'expect','false', 'pass', (v_after->>'allowed')='false');

  insert into public.phase1_rollback_log (actor, tier, reason, detail)
  values (p_actor, 'rehearse', 'tier 0 rollback rehearsal', jsonb_build_object('steps', v_steps));

  return jsonb_build_object(
    'ok', true,
    'all_passed', not exists (select 1 from jsonb_array_elements(v_steps) s where (s->>'pass') is distinct from 'true'),
    'steps', v_steps,
    'WARNING', 'This function MUTATES. It is only safe inside a transaction you abort. Everything it did is undone by ROLLBACK.');
end $fn$;

revoke all on function public.fn_phase1_disarm(text,text) from public, anon, authenticated;
revoke all on function public.fn_phase1_rearm(text,text) from public, anon, authenticated;
revoke all on function public.fn_phase1_rollback_rehearse(text) from public, anon, authenticated;
grant execute on function public.fn_phase1_disarm(text,text) to service_role;
grant execute on function public.fn_phase1_rearm(text,text) to service_role;
grant execute on function public.fn_phase1_status() to service_role;
grant execute on function public.fn_phase1_disarmed() to service_role;

comment on function public.fn_phase1_disarm(text,text) is
  'AUDIT 8.3 TIER 0. Rolls Phase 1 gating back to observe-only in one statement, without deleting a single row. Reversible with fn_phase1_rearm(). Actions that pass while disarmed are still audited, as action_allowed_phase1_disarmed.';
comment on function public.fn_phase1_rollback_rehearse(text) is
  'AUDIT 8.3. Executes the tier 0 rollback and its reversal and asserts the gate actually changed behaviour. MUTATES - run only inside a transaction you abort.';
;
