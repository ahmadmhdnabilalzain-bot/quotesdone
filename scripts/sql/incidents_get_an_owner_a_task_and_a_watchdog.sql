-- INCIDENTS GET AN OWNER, A LINKED TASK, AND A WATCHDOG (org audit A2).
--
-- THE GAP, MEASURED. os_incidents carried opened_by but no owner, no acknowledged_at, no due_at.
-- fn_os_incident_open (and the four other writers that INSERT into os_incidents directly:
-- fn_edge_health_scan, fn_kernel_trigger_state, fn_phase_d_effect_state, fn_ai_spend_guard) set no
-- owner and opened no tracked work, so six high/medium incidents (#27-#32) sat OPEN and unowned for
-- 16-18 days with nothing chasing them. There was no watchdog: cron.job held no incident/escalation
-- job, and fn_notify_founder was never reached from the incident path.
--
-- THE FIX, AT THE TABLE not the caller. Ownership is set by TRIGGERS on os_incidents, so every one
-- of the five writers gets it, not only fn_os_incident_open:
--   * BEFORE INSERT  -> owner (the security.event "incident response" subscriber, else 'security')
--                       and due_at (an SLA off opened_at by severity) when not already given.
--   * AFTER  INSERT  -> ONE linked org_task in the owner's department (best-effort), its id stored
--                       on os_incidents.org_task_id so the two are tied.
--   * status sync    -> resolving the incident closes its task; completing the task resolves the
--                       incident; the task starting stamps acknowledged_at. Guarded so it terminates.
--   * fn_os_incident_watchdog() re-escalates any OPEN high/critical incident past its due_at via
--     fn_notify_founder, with a 24h re-escalation cooldown (escalated_at) so it chases without
--     spamming. Registered as a plain hourly pg_cron job, the way ~180 of the 206 jobs already run.
--
-- The six existing open incidents are backfilled (owner + due_at + linked task) and stamped
-- escalated_at=now() so the watchdog does not blast six founder notices the moment it first runs;
-- they are known stand-down/unfunded-cron artefacts and are now owned and tracked rather than orphaned.
--
--   node scripts/apply_sql.mjs scripts/sql/incidents_get_an_owner_a_task_and_a_watchdog.sql --apply --ddl

begin;

-- 1. THE COLUMNS. Additive and nullable; no existing writer breaks.
alter table public.os_incidents add column if not exists owner           text;
alter table public.os_incidents add column if not exists acknowledged_at timestamptz;
alter table public.os_incidents add column if not exists due_at          timestamptz;
alter table public.os_incidents add column if not exists org_task_id     bigint;
alter table public.os_incidents add column if not exists escalated_at    timestamptz;

-- 2. OWNER + SLA at insert. The security.event subscriber that "owns incident response" is 'security'
-- (cybersecurity_engineer, department assurance); risk_governance_mgr owns the record. We take the
-- response owner, falling back to any active subscriber, then to the literal 'security'.
create or replace function public.fn_os_incident_set_owner_and_due()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $fn$
declare v_sla interval;
begin
  if new.owner is null then
    new.owner := coalesce(
      (select agent_key from public.event_subscription
        where event_type='security.event' and active
        order by (reason ilike '%incident response%') desc, agent_key
        limit 1),
      'security');
  end if;
  if new.due_at is null then
    v_sla := case coalesce(new.severity,'medium')
               when 'critical' then interval '4 hours'
               when 'high'     then interval '24 hours'
               when 'medium'   then interval '72 hours'
               else interval '7 days' end;
    new.due_at := coalesce(new.opened_at, now()) + v_sla;
  end if;
  return new;
end $fn$;

-- 3. THE LINKED TASK. Best-effort: an incident must record even if its task hiccups. dept = owner's
-- department; assigned_agent left null so a05_org_task_fill_ownership places the doer within the
-- department respecting caps and the reviewer rule (the OWNER on the incident is the accountable one).
create or replace function public.fn_os_incident_open_task()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $fn$
declare v_task bigint; v_dept text;
begin
  if new.org_task_id is not null then return new; end if;
  begin
    v_dept := coalesce((select department from public.org_agents where agent_key = new.owner), 'assurance');
    insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
    values (
      v_dept,
      'Incident #'||new.id||': '||new.title,
      'Severity '||coalesce(new.severity,'medium')||', kind '||coalesce(new.kind,'other')
        ||'. Owner '||coalesce(new.owner,'security')
        ||'. Due '||to_char(new.due_at,'YYYY-MM-DD HH24:MI')||' UTC. '
        ||coalesce(new.detail->>'description', left(new.detail::text,300)),
      'assigned',
      case when coalesce(new.severity,'medium') in ('critical','high') then 'supervised' else 'advisory' end,
      false,
      'incident')
    returning id into v_task;
    update public.os_incidents set org_task_id = v_task where id = new.id;
  exception when others then
    -- the incident is recorded regardless; the task is a best-effort companion
    null;
  end;
  return new;
end $fn$;

-- 4. RESOLVING THE INCIDENT CLOSES ITS TASK. Fires only on a real status transition into a resolved
-- state and only when the task is not already done, so the reciprocal trigger (5) below no-ops and
-- the pair terminates.
create or replace function public.fn_os_incident_close_task()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $fn$
begin
  if new.status in ('resolved','closed') and coalesce(old.status,'') not in ('resolved','closed')
     and new.org_task_id is not null then
    update public.org_tasks
       set status='done', updated_at=now()
     where id = new.org_task_id and status <> 'done';
  end if;
  return new;
end $fn$;

-- 5. THE TASK DRIVES THE INCIDENT. Starting the task acknowledges the incident; completing it
-- resolves the incident. Scoped by WHEN (action_class='incident') so it fires for nothing else.
create or replace function public.fn_org_task_incident_sync()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $fn$
begin
  if new.status='in_progress' and coalesce(old.status,'') <> 'in_progress' then
    update public.os_incidents set acknowledged_at = now()
     where org_task_id = new.id and acknowledged_at is null;
  elsif new.status='done' and coalesce(old.status,'') <> 'done' then
    update public.os_incidents
       set status='resolved', resolved_at=coalesce(resolved_at, now()),
           resolution=coalesce(resolution, 'Linked task '||new.id||' completed')
     where org_task_id = new.id and status='open';
  end if;
  return new;
end $fn$;

drop trigger if exists t10_os_incident_set_owner   on public.os_incidents;
create trigger t10_os_incident_set_owner
  before insert on public.os_incidents
  for each row execute function public.fn_os_incident_set_owner_and_due();

drop trigger if exists t20_os_incident_open_task    on public.os_incidents;
create trigger t20_os_incident_open_task
  after insert on public.os_incidents
  for each row execute function public.fn_os_incident_open_task();

drop trigger if exists t30_os_incident_close_task   on public.os_incidents;
create trigger t30_os_incident_close_task
  after update of status on public.os_incidents
  for each row execute function public.fn_os_incident_close_task();

drop trigger if exists t40_org_task_incident_sync   on public.org_tasks;
create trigger t40_org_task_incident_sync
  after update of status on public.org_tasks
  for each row when (new.action_class = 'incident')
  execute function public.fn_org_task_incident_sync();

-- 6. THE WATCHDOG. Re-escalates OPEN high/critical incidents past their due_at through
-- fn_notify_founder, once per 24h per incident (escalated_at cooldown). It does not silence itself on
-- the founder stand-down: an overdue high-severity incident is exactly the signal that must still
-- travel. Building the wiring; whether the cron actually fires is the runtime's business (proved here
-- by an aborted-transaction probe, not by waiting for the schedule).
create or replace function public.fn_os_incident_watchdog()
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $fn$
declare r record; v_esc int := 0;
begin
  for r in
    select * from public.os_incidents
     where status='open' and coalesce(severity,'medium') in ('high','critical')
       and due_at is not null and due_at < now()
       and (escalated_at is null or escalated_at < now() - interval '24 hours')
     order by due_at
  loop
    perform public.fn_notify_founder(
      'OS incident #'||r.id||' ('||coalesce(r.severity,'medium')||') past SLA: '||r.title,
      'Opened '||to_char(r.opened_at,'YYYY-MM-DD HH24:MI')||' UTC; owner '||coalesce(r.owner,'unassigned')
        ||'; due '||to_char(r.due_at,'YYYY-MM-DD HH24:MI')||' UTC and still open. '
        ||coalesce(r.detail->>'description',''),
      case when coalesce(r.severity,'medium')='critical' then 'critical' else 'high' end);
    update public.os_incidents set escalated_at = now() where id = r.id;
    v_esc := v_esc + 1;
  end loop;
  insert into public.agent_runs(agent, started_at, finished_at, status, counts, note)
  values ('os_incident_watchdog', now(), now(), 'ok',
          jsonb_build_object('reescalated', v_esc),
          'Incident watchdog re-escalated '||v_esc||' overdue high/critical incident(s).');
  return jsonb_build_object('ok', true, 'reescalated', v_esc);
end $fn$;

-- New SECURITY DEFINER functions: every CREATE grants EXECUTE to PUBLIC; revoke it.
revoke execute on function public.fn_os_incident_set_owner_and_due() from public;
revoke execute on function public.fn_os_incident_open_task()         from public;
revoke execute on function public.fn_os_incident_close_task()        from public;
revoke execute on function public.fn_org_task_incident_sync()        from public;
revoke execute on function public.fn_os_incident_watchdog()          from public;

-- 7. BACKFILL the six existing open incidents: owner, due_at, a linked task, and escalated_at=now()
-- so the watchdog does not fire six notices at once. (The AFTER-INSERT trigger only fires for new
-- rows, so pre-existing incidents are handled here explicitly.)
update public.os_incidents i
   set owner = coalesce(i.owner,
         coalesce((select agent_key from public.event_subscription
                    where event_type='security.event' and active
                    order by (reason ilike '%incident response%') desc, agent_key limit 1),'security')),
       due_at = coalesce(i.due_at, i.opened_at + case coalesce(i.severity,'medium')
                    when 'critical' then interval '4 hours' when 'high' then interval '24 hours'
                    when 'medium' then interval '72 hours' else interval '7 days' end),
       escalated_at = coalesce(i.escalated_at, now())
 where i.status='open';

do $backfill$
declare r record; v_task bigint; v_dept text;
begin
  for r in select * from public.os_incidents where status='open' and org_task_id is null loop
    begin
      v_dept := coalesce((select department from public.org_agents where agent_key = r.owner), 'assurance');
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
      values (v_dept, 'Incident #'||r.id||': '||r.title,
        'Severity '||coalesce(r.severity,'medium')||', kind '||coalesce(r.kind,'other')||'. Owner '
          ||coalesce(r.owner,'security')||'. Backfilled owner and tracked task for a long-open incident.',
        'assigned', case when coalesce(r.severity,'medium') in ('critical','high') then 'supervised' else 'advisory' end,
        false, 'incident')
      returning id into v_task;
      update public.os_incidents set org_task_id = v_task where id = r.id;
    exception when others then null;
    end;
  end loop;
end $backfill$;

-- 8. THE SCHEDULE. A plain pg_cron job, idiomatic here (most of the 206 jobs run a direct select).
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.

commit;
