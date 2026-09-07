-- The three governance monitors that did not exist.
--
-- Section 39 names six monitors and requires each to have an ACTIVE cron that has SUCCEEDED inside
-- a fortnight — because a view with no schedule behind it monitors nothing. Three were already
-- running: policy_consistency_weekly, autonomy_audit_weekly, security_selfaudit_daily. The other
-- three had no routine at all:
--
--   missing approvals      actions that took effect with nobody recorded as having decided them
--   conflicting decisions  the same subject decided two different ways
--   regulatory changes     compliance items raised and then left unattended
--
-- Each writes a founder_alert only when it finds something, so a clean run is silent rather than
-- noisy. Each returns its own finding count so the run is inspectable.
--
--   node scripts/apply_sql.mjs scripts/sql/governance_monitors.sql --ddl --promote

-- ── MISSING APPROVALS ────────────────────────────────────────────────────────────────────────
create or replace function public.fn_approval_trace_audit()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare v_unattributed int; v_gated int; v_msg text;
begin
  -- An action that reached a terminal state with no decider recorded. The authority model exists
  -- precisely so that somebody is accountable for each of these.
  select count(*) into v_unattributed from public.agent_actions
   where status in ('approved','done','auto_done','resolved')
     and coalesce(btrim(decided_by), '') = '';

  -- An action whose department requires approval for its class, that carries no approval at all.
  select count(*) into v_gated from public.agent_actions a
   where a.status in ('approved','done','auto_done','resolved')
     and coalesce(btrim(a.decided_by), '') = ''
     and exists (select 1 from public.org_authority o
                  where o.action_class = a.kind and coalesce(o.max_tier, '') = 'gated');

  if v_unattributed > 0 then
    v_msg := v_unattributed || ' action(s) reached a terminal state with no decider recorded'
          || case when v_gated > 0 then ', ' || v_gated || ' of them in a gated action class' else '' end || '.';
    insert into public.founder_alerts(level, event, detail, channel)
      values (case when v_gated > 0 then 'warn' else 'info' end,
              'Governance monitor — missing approvals', v_msg, 'os');
  end if;
  return jsonb_build_object('monitor', 'missing_approvals', 'unattributed', v_unattributed,
    'gated_without_approval', v_gated, 'ran_at', now());
end $function$;

-- ── CONFLICTING DECISIONS ────────────────────────────────────────────────────────────────────
create or replace function public.fn_decision_conflict_scan()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare v_conflicts int; v_sample text;
begin
  -- The same actor and kind reaching two different verdicts inside a week is either a change of
  -- mind nobody recorded or an inconsistency. Either way the founder should be told which.
  with pairs as (
    select l.actor, l.kind, count(distinct l.decision) k,
           string_agg(distinct l.decision, ' vs ') verdicts
      from public.decision_log l
     where l.created_at > now() - interval '7 days' and coalesce(l.decision,'') <> ''
     group by l.actor, l.kind
    having count(distinct l.decision) > 1)
  select count(*), coalesce(string_agg(actor || '/' || kind || ': ' || verdicts, '; '), '')
    into v_conflicts, v_sample from pairs;

  if v_conflicts > 0 then
    insert into public.founder_alerts(level, event, detail, channel)
      values ('info', 'Governance monitor — conflicting decisions',
              v_conflicts || ' actor/kind pair(s) reached more than one verdict in 7 days. ' || left(v_sample, 900), 'os');
  end if;
  return jsonb_build_object('monitor', 'conflicting_decisions', 'conflicts', v_conflicts, 'ran_at', now());
end $function$;

-- ── REGULATORY CHANGES ───────────────────────────────────────────────────────────────────────
create or replace function public.fn_regulation_watch()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare v_open int; v_stale int; v_sources int;
begin
  select count(*) into v_sources from public.compliance_sources;
  -- Regulatory items the compliance agent raised and nobody has closed.
  select count(*), count(*) filter (where a.created_at < now() - interval '14 days')
    into v_open, v_stale
    from public.agent_actions a
   where a.status in ('pending','needs_review','held_for_review')
     and (a.title ~* '(regulat|municipal|compliance|licen[cs]e|code update|law|decree)'
          or coalesce(a.recommendation,'') ~* '(regulat|municipal|code update|decree)');

  if v_stale > 0 then
    insert into public.founder_alerts(level, event, detail, channel)
      values ('warn', 'Governance monitor — regulatory changes',
              v_stale || ' regulatory item(s) have been open more than 14 days, of ' || v_open
              || ' open in total, against ' || v_sources || ' tracked compliance source(s).', 'os');
  end if;
  return jsonb_build_object('monitor', 'regulatory_changes', 'open', v_open, 'stale', v_stale,
    'sources', v_sources, 'ran_at', now());
end $function$;

-- ── SCHEDULES ────────────────────────────────────────────────────────────────────────────────
-- Weekly, on the same Monday-morning rhythm the three existing governance monitors already use,
-- staggered so they do not contend. Unscheduled first so re-running this file is idempotent.
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.


insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('approval_trace_audit_weekly', 'Approval Trace Audit', 'Governance',
   'Finds actions that reached a terminal state with nobody recorded as having decided them, and flags those in a gated action class.'),
  ('decision_conflict_scan_weekly', 'Decision Conflict Scan', 'Governance',
   'Finds the same actor and action kind reaching more than one verdict inside a week.'),
  ('regulation_watch_weekly', 'Regulation Watch', 'Governance',
   'Finds regulatory and licensing items raised by the compliance agent and left open more than 14 days.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
