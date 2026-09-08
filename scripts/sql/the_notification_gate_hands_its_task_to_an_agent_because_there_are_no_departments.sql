-- THE NOTIFICATION GATE HANDS ITS TASK TO AN AGENT, BECAUSE THERE ARE NO DEPARTMENTS (9 Sep 2026).
--
-- A LIVE, CUSTOMER-FACING DEFECT. MEASURED on htdblwldjkcgjvmqkbeh, 9 Sep 2026:
--   public.founder_alerts holds 5 rows with event = 'founder_mail:route_failed', four of them on
--   7 Sep 2026, detail:
--     "kind support_agent / A new quotation for inquiry RFQ-1042 — insert or update on table
--      \"org_tasks\" violates foreign key constraint \"org_tasks_dept_key_fkey\""
--     and its Arabic twin, "عرض سعر جديد على طلبك RFQ-1042", and one
--     "kind exception_alert / QuotesDone ALERT: cron_failing".
--   public.org_departments: 0 rows. public.org_tasks: 0 rows. public.org_agents: exactly two,
--   'ceo' and 'customer_support', both active and available, both with department = null.
--
-- THE CAUSE. On 7 Sep 2026 the founder removed every department: the org is exactly TWO agents and
-- NO departments, and that is standing, not temporary. fn_founder_mail_route still resolved a
-- DEPARTMENT for the task it opens, and when it could not find one it fell back to the literal
-- 'exec' — a dept_key that no longer exists in a table that now has no rows at all. Every insert
-- therefore violated org_tasks_dept_key_fkey. a10_notifications_founder_mail_policy catches that,
-- logs 'founder_mail:route_failed' and returns null, so the notification row was DROPPED: a real
-- customer-facing message ("a new quotation on your inquiry") was silently discarded on the
-- surviving customer_support agent's own delivery path.
--
-- THE FIX, in two parts:
--
--   1. org_tasks_dept_key_fkey is DROPPED. It points at org_departments, which has 0 rows and is
--      never repopulated, so the constraint can no longer be satisfied by anything except NULL: it
--      is a guard whose subject was retired, and it fails every writer rather than catching one.
--      Eight live routines insert into org_tasks supplying dept_key (fn_agent_action_hand_to_owner,
--      fn_decision_record_route, fn_founder_mail_route, fn_os_incident_open_task,
--      fn_receipt_hand_to_bookkeeper, fn_report_recommendation_approve,
--      fn_supplier_sanctions_screen, fn_workflow_step_sweep — measured by a prosrc scan, not a repo
--      grep) and all eight raise the same violation today. Dropping the constraint fixes all eight.
--
--      THE dept_key COLUMN STAYS, and this file says so deliberately. 33 live routine bodies still
--      read or write org_tasks.dept_key (prosrc scan), and index ix_org_tasks_dept_status depends on
--      it (pg_depend on the column's attnum). Dropping the column would cascade into a rewrite of
--      all 33; that is a separate piece of work and is not what is on fire. The column is now a
--      label with no referent, and this routine stops writing one.
--
--   2. fn_founder_mail_route stops resolving a department at all. The task it opens is owned by an
--      AGENT: the named agent if it is active and available, else the policy role's runtime agent,
--      else — because the two seats that remain are the whole company — customer_support for the
--      customer-, comms- and marketplace-facing roles and the ceo for everything else. dept_key is
--      no longer supplied, so it stays null. assigned_agent already carries a FK to
--      org_agents(agent_key), so ownership is still enforced, against a table that has rows.
--
-- Nothing is deleted: the five founder_alerts rows are the evidence and stay exactly as they are.
--
--   node scripts/apply_sql.mjs scripts/sql/the_notification_gate_hands_its_task_to_an_agent_because_there_are_no_departments.sql --apply --ddl

alter table public.org_tasks drop constraint if exists org_tasks_dept_key_fkey;

create or replace function public.fn_founder_mail_route(
  p_kind text, p_subject text, p_body text, p_level text default 'high', p_owner_agent text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_pol record; v_owner_role text; v_reason text; v_agent text;
  v_sig text; v_task bigint; v_new boolean := false; v_prio int; v_title text;
begin
  select * into v_pol from public.founder_mail_policy where kind = p_kind;
  v_owner_role := coalesce(v_pol.owner_role, 'cto');
  v_reason := coalesce(v_pol.reason,
    'kind ''' || coalesce(p_kind, '(null)') || ''' is not registered in founder_mail_policy, and an unregistered kind is never emailed');

  -- WHO OWNS IT. 7 Sep 2026: the org is exactly two agents and NO departments, so a task is owned by
  -- an AGENT and never by a department. The named agent wins; else the policy role's runtime agent;
  -- else the seat whose work this is — customer_support for anything customer-, comms- or
  -- marketplace-facing, the ceo for the rest. If neither seat is active the owner is left null and
  -- a05_org_task_fill_ownership picks, exactly as before.
  if p_owner_agent is not null and exists (
       select 1 from public.org_agents o
        where o.agent_key = p_owner_agent and o.active and coalesce(o.available, true)) then
    v_agent := p_owner_agent;
  else
    select r.runtime_agent_key into v_agent
      from public.org_role r
      join public.org_agents o on o.agent_key = r.runtime_agent_key and o.active and coalesce(o.available, true)
     where r.role_id = v_owner_role and r.status = 'active';
  end if;
  if v_agent is null then
    v_agent := case when v_owner_role ~* 'support|success|customer|communicat|deliver|marketplace|sales'
                    then 'customer_support' else 'ceo' end;
  end if;
  if not exists (select 1 from public.org_agents o
                  where o.agent_key = v_agent and o.active and coalesce(o.available, true)) then
    v_agent := null;
  end if;

  -- THE CONDITION: kind + subject with a leading [TAG] removed and every number replaced by '#', so
  -- "[HIGH] Backup may have failed" from the trigger and "Backup may have failed" from the sweep, or run #80
  -- and run #82 of one stalled handoff, are one condition.
  v_title := regexp_replace(coalesce(nullif(p_subject, ''), p_kind, 'engine signal'), '^\[[^\]]*\]\s*', '');
  v_sig := coalesce(p_kind, 'unregistered') || ':' || left(regexp_replace(v_title, '[0-9]+', '#', 'g'), 150);
  insert into public.alert_signature (watcher, signature) values ('founder_mail', v_sig)
    on conflict (watcher, signature) do update
      set last_seen_at = now(), seen_count = alert_signature.seen_count + 1, resolved_at = null;

  -- ONE OPEN TASK PER CONDITION. An open task is bumped; a closed one lets the condition open a new one,
  -- because the condition coming back after the owner closed it IS new information.
  select t.id into v_task
    from public.org_tasks t
   where t.status in ('proposed', 'assigned', 'in_progress', 'blocked', 'escalated')
     and t.result -> 'founder_mail' ->> 'signature' = v_sig
   order by t.id desc limit 1;

  if v_task is not null then
    update public.org_tasks
       set result = jsonb_set(coalesce(result, '{}'::jsonb), '{founder_mail}',
                     coalesce(result -> 'founder_mail', '{}'::jsonb)
                     || jsonb_build_object('last_seen_at', now(),
                                           'seen_count', coalesce((result -> 'founder_mail' ->> 'seen_count')::int, 1) + 1,
                                           'latest', left(coalesce(p_body, ''), 600))),
           updated_at = now()
     where id = v_task;
  else
    v_prio := case when lower(coalesce(p_level, '')) in ('critical', 'urgent', 'danger', 'high', 'error', 'action', 'alert', 'escalation', 'fail', 'failed')
                   then 2 else 1 end;
    insert into public.org_tasks (title, detail, status, tier, needs_founder, decided_by,
                                  action_class, assigned_agent, priority, result)
    values (left(v_title, 200),
            '[founder_mail:' || coalesce(p_kind, 'unregistered') || '] ' || coalesce(p_body, '')
              || E'\n\nThis signal was routed to you instead of the founder''s inbox: ' || v_reason
              || '. Resolve the condition and close this task; it re-opens only if the condition returns.',
            'assigned', 'advisory', false, 'fn_founder_mail_route',
            'routine_operational_decision', v_agent, v_prio,
            jsonb_build_object('founder_mail', jsonb_build_object(
              'kind', p_kind, 'signature', v_sig, 'owner_role', v_owner_role, 'level', p_level,
              'registered', v_pol.kind is not null, 'routed_at', now(), 'seen_count', 1)))
    returning id into v_task;
    v_new := true;
  end if;

  -- the ledger resolves on merit: a signature whose task the owner closed is no longer open
  update public.alert_signature s
     set resolved_at = now()
   where s.watcher = 'founder_mail' and s.resolved_at is null and s.signature <> v_sig
     and not exists (select 1 from public.org_tasks t
                      where t.result -> 'founder_mail' ->> 'signature' = s.signature
                        and t.status in ('proposed', 'assigned', 'in_progress', 'blocked', 'escalated'));

  return jsonb_build_object('mode', 'routed', 'task_id', v_task, 'new', v_new, 'signature', v_sig,
                            'kind', p_kind, 'registered', v_pol.kind is not null,
                            'owner', v_agent, 'owner_role', v_owner_role);
end
$fn$;

-- AND THE KIND THAT WAS BEING DROPPED IS NAMED. 'support_agent' — the chat widget / support agent's
-- own customer-facing messages, "A new quotation for inquiry RFQ-1042" and its Arabic twin — was
-- unregistered, so it fell to the default owner_role 'cto', a seat nobody holds since 7 Sep, and the
-- task landed on the ceo. It is the customer_support agent's work. Registered here, still NOT
-- emailed to the founder (it is routine, not an exception), with the owner named rather than guessed.
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values ('support_agent', false,
        'a customer-facing message from the support agent is that agent''s own work, not an exception for the founder',
        'customer_support')
on conflict (kind) do update
  set allowed_to_email = excluded.allowed_to_email,
      reason = excluded.reason,
      owner_role = excluded.owner_role,
      updated_at = now();

-- THE ASSERTION. Raises if the change did not land.
do $chk$
declare v_fk int; v_dept_writes int; v_col int;
begin
  select count(*) into v_fk from pg_constraint
   where conrelid = 'public.org_tasks'::regclass and conname = 'org_tasks_dept_key_fkey';
  if v_fk <> 0 then
    raise exception 'org_tasks_dept_key_fkey is still on org_tasks; the dead FK did not drop';
  end if;

  select count(*) into v_col from information_schema.columns
   where table_schema = 'public' and table_name = 'org_tasks' and column_name = 'dept_key';
  if v_col <> 1 then
    raise exception 'org_tasks.dept_key was expected to REMAIN (33 routines and ix_org_tasks_dept_status still use it); found % copies', v_col;
  end if;

  select count(*) into v_dept_writes from pg_proc
   where pronamespace = 'public'::regnamespace and proname = 'fn_founder_mail_route'
     and (prosrc ~* 'org_departments' or prosrc ~* 'dept_key');
  if v_dept_writes <> 0 then
    raise exception 'fn_founder_mail_route still names a department; the live body was not replaced';
  end if;

  if not exists (select 1 from pg_proc
                  where pronamespace = 'public'::regnamespace and proname = 'fn_founder_mail_route'
                    and prosrc ~* 'customer_support') then
    raise exception 'fn_founder_mail_route does not carry the agent fallback; the live body was not replaced';
  end if;

  if not exists (select 1 from public.founder_mail_policy
                  where kind = 'support_agent' and owner_role = 'customer_support' and not allowed_to_email) then
    raise exception 'founder_mail_policy does not own support_agent to customer_support';
  end if;
end
$chk$;
