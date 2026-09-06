-- THE FOUNDER IS EMAILED EXCEPTIONS ONLY (6 Sep 2026). Founder's order, his words: "send an agent to audit
-- the emails sent from info@quotesdone.com. So many errors were sent to me from the engine." His standing
-- rule: he receives exceptions, not routine; nothing routes to his approval except a Stripe refund.
--
-- MEASURED on htdblwldjkcgjvmqkbeh, 6 Sep 2026 09:00 UTC, public.notifications addressed to him, 30 days
-- (docs/EMAIL_AUDIT_info_at_quotesdone_2026-09-06.md has the full table): 244 emails sent, of which
--   88  "[Action needed] Scheduled runs failed"      fn_watch_failed_runs  -> alert_founder  (product_eng's work)
--   42  "Scheduled job stopped/failing: <job>"       fn_agent_silence_watch                  (product_eng's work)
--   20  "Resilience: the platform needs attention"   fn_resilience_watch   -> alert_founder  (14 identical bodies)
--   14  "AI credit low"                              cost_snapshot         -> alert_founder  (daily, on the paid hold)
--   12  "Business health N%"                         fn_watch_health       -> alert_founder  (daily by design)
--    6  "Stalled handoff run #80/#82"                fn_handoff_watchdog   -> fn_notify_founder (the receiver's lead's work)
--    6  "data-integrity check failed"                fn_smoke              (counted 6-10 queued WhatsApp rows as an email backlog)
--    5  backup overdue / [HIGH] backup / [Attention] backup  = THREE emails for ONE backup event (fn_backup_watch writes a
--       notification, an agent_action that trg_page_high_agent_action emails, and fn_agent_action_work_sweep emails again)
--   10  legal / security / terms / regulatory / auth-hardening notices  fn_agent_action_work_sweep "no approval is required of you"
-- Of the 244, the ones that were HIS to act on: 16 daily briefs, 2 board reports, 1 CFO report, 2 monthly reports,
-- 7 burn snapshots, 2 payment reminders, 1 "cron watchdog is down". Everything else was a department's work that
-- reached his inbox because 20+ producers each decided for themselves whether to email him and none of them
-- had a policy to ask.
--
-- THE MECHANISM, one table and one gate:
--   * founder_mail_policy: kind -> allowed_to_email, reason, owner_role (an org_role.role_id). Seeded below from
--     the audit. Allowed: the daily brief and the periodic reports he reads, refund approvals, money anomalies
--     (ledger imbalance, Stripe webhook failure, unexpected charge, spend above his AED 10,000 boundary),
--     platform-down (site or scheduler down, backup still failing after retry), security-critical (customer-data
--     exposure, secret leak). Everything else is NOT emailed.
--   * fn_founder_mail_route(kind, subject, body, level, owner_agent): the one door for a disallowed or unlisted
--     kind. It opens ONE org_task for the owner role (the role's runtime agent, else its department lead, else
--     the lane's own picker) and, while that task is open, an identical condition only bumps the task's
--     seen_count. The condition is the kind plus the subject with a leading [TAG] removed and every number
--     replaced by '#', recorded in alert_signature under watcher = 'founder_mail'. So an unchanged condition
--     never repeats: not in his inbox, and not as a second task.
--   * a10_notifications_founder_mail_policy, BEFORE INSERT on notifications: every founder-bound email or
--     WhatsApp row (to_role founder/admin/owner, or his address, or his phone) is looked up by
--     coalesce(kind, type). Allowed -> the row is queued as before. Anything else -> routed and the insert is
--     refused WITHOUT an error (return null), so no producer needs to know. It fires before the digest
--     trigger (name order), so a routed row is not digested either.
--   * fn_notify_founder gains p_kind, p_dedupe_key (alert_founder's 24h-per-key contract, kept) and
--     p_owner_agent, and returns what it did. The 3-argument overload is dropped so the callers in
--     founder_mail_the_specific_senders.sql, which now name their kind, resolve to this one. A caller that
--     names no kind is routed, never emailed.
--   * fn_page_high_agent_action carries the agent_action's own kind onto the notification so the policy
--     row for backup_alert / security_incident / incident / finance_alert decides, and a CRITICAL security
--     action is the security_critical kind that may reach him.
-- The daily brief (founder_mail_the_brief_carries_what_was_routed.sql) lists what was routed under
-- WITH THE ORGANISATION; the OS shows the tasks. That is the only way this traffic reaches him now.
--
-- PROVED by aborted-transaction probes inside a declared rehearsal window, 6 Sep 2026 — see
-- scripts/checks/the_founder_is_emailed_exceptions_only.probe.mjs and the commit body.
--
--   node scripts/apply_sql.mjs scripts/sql/the_founder_is_emailed_exceptions_only.sql --apply --ddl

create table if not exists public.founder_mail_policy (
  kind             text primary key,
  allowed_to_email boolean not null default false,
  reason           text not null,
  owner_role       text not null,
  updated_at       timestamptz not null default now()
);
comment on table public.founder_mail_policy is
  'kind -> may this reach the founder''s inbox? Anything not allowed (or not listed) becomes ONE org_task for owner_role (an org_role.role_id) via fn_founder_mail_route and reaches him only in the daily brief.';
alter table public.founder_mail_policy enable row level security;
revoke all on public.founder_mail_policy from public, anon, authenticated;

alter table public.notifications add column if not exists kind text;
comment on column public.notifications.kind is
  'founder_mail_policy key for a founder-bound row; coalesce(kind, type) is what a10_notifications_founder_mail_policy looks up.';

insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role) values
  -- ALLOWED: what he reads, what is money, what is the platform being down, what is security-critical
  ('founder_brief',              true,  'the daily brief is how the company reports to him',                                              'chief_of_staff'),
  ('board_report',               true,  'the weekly board report is reading he asked for',                                                'chief_of_staff'),
  ('period_report',              true,  'the monthly business report is reading he asked for',                                            'chief_of_staff'),
  ('cfo_report',                 true,  'the weekly finance report is money',                                                             'cfo'),
  ('cost_snapshot',              true,  'weekly burn and revenue is money',                                                               'cfo'),
  ('finance_reminder',           true,  'a payment falling due is money he pays',                                                         'cfo'),
  ('refund_approval',            true,  'a Stripe refund is the one decision that is his (17 Aug 2026)',                                  'cfo'),
  ('refund_decision',            true,  'a Stripe refund is the one decision that is his (17 Aug 2026)',                                  'cfo'),
  ('spend_approval_needed',      true,  'spend above the AED 10,000 boundary is his to authorise, not an AI head''s',                     'cfo'),
  ('finance_alert',              true,  'a money anomaly raised by the finance agent',                                                    'cfo'),
  ('ledger_imbalance',           true,  'the ledger not balancing is a money anomaly',                                                    'cfo'),
  ('stripe_webhook_failed',      true,  'a Stripe webhook failing means money moved that the books did not see',                          'cfo'),
  ('unexpected_charge',          true,  'a charge nobody planned is a money anomaly',                                                     'cfo'),
  ('platform_down',              true,  'the site or the scheduler is down: a platform outage he must know about',                        'it_operations_engineer'),
  ('uptime_alert',               true,  'the site is down: a platform outage he must know about',                                         'it_operations_engineer'),
  ('backup_failed_after_retry',  true,  'the daily backup has failed two days running; there may be no restorable backup',                'it_operations_engineer'),
  ('security_critical',          true,  'customer data exposed to anon, or a secret leaked: security-critical',                           'cybersecurity_engineer'),
  -- NOT EMAILED: a department''s work. It opens one task for the owner and appears in the brief.
  ('scheduled_runs_failed',      false, 'a failed scheduled run is engineering''s to diagnose and fix',                                    'it_operations_engineer'),
  ('agent_silence',              false, 'a silent or failing cron job is engineering''s to restart',                                      'it_operations_engineer'),
  ('runner_silence',             false, 'a runner past its own cadence is the COO''s staffing question, then engineering''s',              'chief_operating_officer'),
  ('resilience',                 false, 'the self-healing watchdog''s leftovers are engineering''s to finish',                             'it_operations_engineer'),
  ('resilience_alert',           false, 'the self-healing watchdog''s leftovers are engineering''s to finish',                             'it_operations_engineer'),
  ('red_view',                   false, 'a red monitored view is engineering''s to turn green',                                            'it_operations_engineer'),
  ('smoke_alert',                false, 'a data-integrity check failing is engineering''s to repair',                                      'it_operations_engineer'),
  ('backup_alert',               false, 'one missed backup is engineering''s to rerun; after retry it becomes backup_failed_after_retry',  'it_operations_engineer'),
  ('ops_alert',                  false, 'the cron watchdog being down is engineering''s to restart',                                       'it_operations_engineer'),
  ('incident',                   false, 'an incident raised by an agent is engineering''s to run',                                         'it_operations_engineer'),
  ('os_incident',                false, 'an OS incident is engineering''s to run',                                                         'it_operations_engineer'),
  ('os_incident_past_sla',       false, 'an OS incident past its SLA escalates to engineering''s lead, not to him',                        'it_operations_engineer'),
  ('health_alert',               false, 'a health-check failure short of an outage is engineering''s',                                    'cto'),
  ('llm_drift',                  false, 'model drift is the CTO''s to retune',                                                             'cto'),
  ('ai_quality_alert',           false, 'AI output quality is the CTO''s to retune',                                                       'cto'),
  ('agent_escalation',           false, 'a high-risk agent action with no kind of its own is the CTO''s to classify',                     'cto'),
  ('security_incident',          false, 'a high-severity security event is the security engineer''s to close; only a CRITICAL one is his', 'cybersecurity_engineer'),
  ('business_health_at_risk',    false, 'a department at risk is the CEO''s to steer',                                                     'ceo'),
  ('handoff_stalled',            false, 'an unaccepted handoff is the receiving role''s department lead''s to accept or park',             'chief_of_staff'),
  ('handoff_stalled_7d',         false, 'a week-old stall escalates through the lane''s own SLA ladder (fn_org_task_sla_watch); flip this row to email him instead', 'chief_of_staff'),
  ('corrective_task_overdue',    false, 'a corrective task past twice its SLA is the chief of staff''s to unblock',                        'chief_of_staff'),
  ('remediation_escalated',      false, 'an employee failing remediation is the COO''s to retrain, reassign or downgrade',                 'chief_operating_officer'),
  ('agent_action_unclassified',  false, 'a work item with no kind policy is the chief of staff''s to classify',                            'chief_of_staff'),
  ('knowledge_coverage',         false, 'a knowledge gap is the COO''s knowledge function''s to fill',                                     'chief_operating_officer'),
  ('legal_flag',                 false, 'a legal flag is the general counsel''s',                                                          'general_counsel'),
  ('legal_docs_missing',         false, 'a missing legal document is the general counsel''s to draft',                                     'general_counsel'),
  ('terms_not_accepted',         false, 'customers on old terms are the general counsel''s to re-consent',                                 'general_counsel'),
  ('regulatory_change',          false, 'a regulatory change is the general counsel''s to assess',                                         'general_counsel'),
  ('pdpl_request',               false, 'a data-subject request is the general counsel''s, on its statutory clock',                        'general_counsel'),
  ('policy_inconsistency',       false, 'a contradiction between policies is the chief of staff''s to reconcile',                          'chief_of_staff'),
  ('ai_credit_low',              false, 'the OpenRouter balance is the CFO''s to top up from the subscriptions budget; the brief carries it', 'cfo'),
  ('expense_logged',             false, 'a booked expense is a record, not a decision',                                                    'cfo'),
  ('exception_alert',            false, 'an exception in the register is the COO''s to clear',                                             'chief_operating_officer'),
  ('rfq_sla_breach',             false, 'an RFQ past its SLA is the marketplace director''s to chase',                                     'marketplace_director'),
  ('customer_escalation',        false, 'a customer escalation is customer success''s to resolve',                                         'customer_success_director'),
  ('supply_health',              false, 'supplier-side health is business development''s',                                                'business_development'),
  ('doc_expiry',                 false, 'an expiring supplier document is business development''s to chase',                              'business_development'),
  ('supplier_registered',        false, 'a new supplier is business development''s to welcome',                                            'business_development'),
  ('invite_paused_bounce',       false, 'invite deliverability is business development''s to repair',                                     'business_development'),
  ('weekly_learnings',           false, 'weekly learnings are the COO''s to fold into playbooks',                                          'chief_operating_officer'),
  ('agent_created',              false, 'a new employee is the COO''s record',                                                             'chief_operating_officer')
on conflict (kind) do update
  set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason, owner_role = excluded.owner_role, updated_at = now();

-- ------------------------------------------------------------------------------------------------------------
-- THE ONE DOOR for a kind that may not reach his inbox.
create or replace function public.fn_founder_mail_route(
  p_kind text, p_subject text, p_body text, p_level text default 'high', p_owner_agent text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_pol record; v_owner_role text; v_reason text; v_agent text; v_dept text;
  v_sig text; v_task bigint; v_new boolean := false; v_prio int; v_title text;
begin
  select * into v_pol from public.founder_mail_policy where kind = p_kind;
  v_owner_role := coalesce(v_pol.owner_role, 'cto');
  v_reason := coalesce(v_pol.reason,
    'kind ''' || coalesce(p_kind, '(null)') || ''' is not registered in founder_mail_policy, and an unregistered kind is never emailed');

  -- WHO OWNS IT: the named agent, else the policy role's runtime agent, else that department's lead, else
  -- the lane's own picker (a05_org_task_fill_ownership) when assigned_agent is left null.
  select r.runtime_agent_key, r.primary_department_id into v_agent, v_dept
    from public.org_role r where r.role_id = v_owner_role and r.status = 'active';
  if p_owner_agent is not null then
    v_agent := p_owner_agent;
    select o.department into v_dept from public.org_agents o where o.agent_key = p_owner_agent and o.active;
  end if;
  if v_dept is null or not exists (select 1 from public.org_departments d where d.dept_key = v_dept and d.active) then
    select o.department into v_dept from public.org_agents o where o.agent_key = v_agent and o.active;
  end if;
  if v_dept is null or not exists (select 1 from public.org_departments d where d.dept_key = v_dept and d.active) then
    v_dept := 'exec';
  end if;
  if not exists (select 1 from public.org_agents o where o.agent_key = v_agent and o.active and coalesce(o.available, true)) then
    select d.lead_agent into v_agent from public.org_departments d where d.dept_key = v_dept;
    if not exists (select 1 from public.org_agents o where o.agent_key = v_agent and o.active and coalesce(o.available, true)) then
      v_agent := null;
    end if;
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
    insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, decided_by,
                                  action_class, assigned_agent, priority, result)
    values (v_dept, left(v_title, 200),
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
                            'owner', v_agent, 'dept', v_dept, 'owner_role', v_owner_role);
end $function$;
revoke execute on function public.fn_founder_mail_route(text, text, text, text, text) from public, anon, authenticated;

-- ------------------------------------------------------------------------------------------------------------
-- THE GATE on the queue itself: every founder-bound row asks the policy before it is queued.
create or replace function public.fn_notifications_founder_mail_policy()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_admin text; v_phone text; v_kind text; v_allowed boolean; v_level text;
begin
  if coalesce(NEW.channel, 'email') not in ('email', 'whatsapp') then return NEW; end if;
  if coalesce(NEW.to_email, '') ~* '@example[.]invalid$' then return NEW; end if;   -- a fixture is never him

  select lower(nullif(split_part(coalesce(value, ''), ',', 1), '')) into v_admin from public.app_secrets where key = 'admin_emails';
  select regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g') into v_phone from public.app_secrets where key = 'admin_mfa_phone';
  if not (coalesce(NEW.to_role, '') in ('founder', 'admin', 'owner')
          or (NEW.to_email is not null and lower(NEW.to_email) = coalesce(v_admin, 'management@quotesdone.com'))
          or (NEW.to_phone is not null and coalesce(v_phone, '') <> ''
              and regexp_replace(NEW.to_phone, '[^0-9]', '', 'g') = v_phone)) then
    return NEW;
  end if;

  v_kind := coalesce(nullif(btrim(NEW.kind), ''), nullif(btrim(NEW.type), ''), 'unregistered');
  select allowed_to_email into v_allowed from public.founder_mail_policy where kind = v_kind;
  if coalesce(v_allowed, false) then
    NEW.kind := v_kind;
    return NEW;
  end if;

  v_level := case when coalesce(NEW.subject, '') ~* 'critical|urgent' then 'critical'
                  when coalesce(NEW.subject, '') ~* '\[(HIGH|ERROR)\]|fail|down|stopped|stalled|overdue|breach' or NEW.type = 'founder_alert' then 'high'
                  else 'warn' end;
  begin
    perform public.fn_founder_mail_route(v_kind, NEW.subject, NEW.body, v_level);
  exception when others then
    -- the door failing must not become an email to him, and must not be silent either
    insert into public.founder_alerts (level, event, detail, channel)
    values ('high', 'founder_mail:route_failed', left('kind ' || v_kind || ' / ' || coalesce(NEW.subject, '') || ' — ' || sqlerrm, 1000), 'os');
  end;
  return null;   -- a refusal that is not an error: nothing is queued; the task is the record
end $function$;
revoke execute on function public.fn_notifications_founder_mail_policy() from public, anon, authenticated;

drop trigger if exists a10_notifications_founder_mail_policy on public.notifications;
create trigger a10_notifications_founder_mail_policy
  before insert on public.notifications
  for each row execute function public.fn_notifications_founder_mail_policy();

-- ------------------------------------------------------------------------------------------------------------
-- fn_notify_founder: the front door every routine calls. The 3-argument overload goes so that a caller naming
-- p_kind resolves here and a caller naming nothing lands on p_kind = null = routed.
drop function if exists public.fn_notify_founder(text, text, text);
create or replace function public.fn_notify_founder(
  p_event text, p_detail text, p_level text default 'high',
  p_kind text default null, p_dedupe_key text default null, p_owner_agent text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_email text; v_phone text; v_kind text; v_level text; v_allowed boolean; v_route jsonb;
begin
  v_level := coalesce(nullif(btrim(p_level), ''), 'high');
  v_kind  := coalesce(nullif(btrim(p_kind), ''), 'unregistered');
  select allowed_to_email into v_allowed from public.founder_mail_policy where kind = v_kind;

  if not coalesce(v_allowed, false) then
    v_route := public.fn_founder_mail_route(v_kind, p_event, p_detail, v_level, p_owner_agent);
    -- the console log (read by the OS and by fn_founder_brief) records what happened instead of an email
    insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
    values (v_level, p_event,
            coalesce(p_detail, '') || E'\n\n-> routed to ' || coalesce(v_route ->> 'owner', v_route ->> 'dept')
              || ' as org_task #' || (v_route ->> 'task_id') || ' (founder_mail_policy: ' || v_kind || ')',
            'routed', p_dedupe_key);
    return v_route || jsonb_build_object('emailed', false);
  end if;

  -- ALLOWED. At most one delivery per dedupe_key per 24 hours: alert_founder's contract, kept in the database.
  if p_dedupe_key is not null and exists (
       select 1 from public.founder_alerts f
        where f.dedupe_key = p_dedupe_key and f.channel in ('email', 'whatsapp')
          and f.created_at > now() - interval '24 hours') then
    insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
    values (v_level, p_event, p_detail, 'deduped', p_dedupe_key);
    return jsonb_build_object('mode', 'email', 'emailed', false, 'deduped', true, 'kind', v_kind);
  end if;

  select nullif(split_part(coalesce(value, ''), ',', 1), '') into v_email from public.app_secrets where key = 'admin_emails';
  v_email := coalesce(v_email, 'management@quotesdone.com');
  select nullif(btrim(value), '') into v_phone from public.app_secrets where key = 'admin_mfa_phone';

  insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
  values (v_level, p_event, p_detail, 'email', p_dedupe_key);

  -- the email queue (send_outbox / Resend)
  insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel)
  values ('founder_alert', v_kind, v_email, 'founder', '[Attention] ' || p_event, p_detail, 'queued', 'email');

  -- WhatsApp for severe levels (send_whatsapp / Twilio); trg_wa_fanout does NOT fan out founder rows.
  if v_phone is not null and lower(v_level) in ('critical', 'urgent', 'high', 'danger') then
    insert into public.notifications (type, kind, to_phone, to_role, subject, body, status, channel)
    values ('founder_alert', v_kind, v_phone, 'founder', p_event,
            'QuotesDone [' || v_level || ']: ' || p_event, 'queued', 'whatsapp');
  end if;
  return jsonb_build_object('mode', 'email', 'emailed', true, 'kind', v_kind);
end $function$;
revoke execute on function public.fn_notify_founder(text, text, text, text, text, text) from public, anon, authenticated;

-- ------------------------------------------------------------------------------------------------------------
-- fn_page_high_agent_action: the notification carries the action's own kind, so the policy row for
-- backup_alert / security_incident / incident / finance_alert decides; a CRITICAL security action is
-- security_critical. Every other line is the live definition (pg_get_functiondef, 6 Sep 2026).
CREATE OR REPLACE FUNCTION public.fn_page_high_agent_action()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_founder text; v_kind text;
BEGIN
  IF lower(coalesce(NEW.risk,'')) IN ('high','critical')
     -- K21. Was: NEW.agent IN ('finance_ai','security_ai','operations_ai'). That set could never
     -- match a security action. a00_agent_action_resolve_addressee runs BEFORE this trigger and
     -- resolves the addressee through org_agents, so a row written as 'security_ai' arrives here
     -- as 'security'. Measured: inserting agent='security_ai' reads back as 'security', and
     -- notifications has 0 rows of type 'agent_escalation' in its entire history — the founder has
     -- never been paged by this trigger. A prefix match survives the resolver in both directions
     -- and does not need a keep-list that has to be remembered every time an agent is renamed.
     AND NEW.agent ~ '^(finance|security|operations)'
     AND lower(coalesce(NEW.status,'pending')) = 'pending' THEN
  -- K20 cutover. A high or critical pending action from finance, security or operations is the declared start of W29. Placed INSIDE the risk branch, so an ordinary agent action does not open an incident.
  perform public.fn_kernel_source_emit('dbtrigger:public.agent_actions:trg_page_high_agent_action', jsonb_build_object(
    'source_ref',  NEW.id::text,
    'raw_payload', jsonb_build_object('incident_ref', 'agent_action:' || NEW.id::text, 'agent', NEW.agent, 'kind', NEW.kind, 'risk', NEW.risk, 'title', NEW.title)));
    v_founder := coalesce(
      (SELECT value FROM app_secrets WHERE key='founder_email'),
      nullif(split_part((SELECT value FROM app_secrets WHERE key='admin_emails'), ',', 1), ''),
      'management@quotesdone.com');
    -- 6 SEP 2026: the founder_mail_policy key is the action's own kind; a CRITICAL security action is
    -- the one security kind that may reach him (founder_mail_policy.security_critical).
    v_kind := CASE WHEN lower(coalesce(NEW.risk,'')) = 'critical' AND NEW.agent ~ '^security' THEN 'security_critical'
                   ELSE coalesce(nullif(NEW.kind,''), 'agent_escalation') END;
    IF NOT EXISTS (
      SELECT 1 FROM notifications
      WHERE type='agent_escalation' AND body LIKE '%action #'||NEW.id||'%'
        AND created_at > now() - interval '24 hours'
    ) THEN
      INSERT INTO notifications(type, kind, to_email, to_role, channel, status, subject, body)
      VALUES('agent_escalation', v_kind, v_founder, 'admin', 'email', 'queued',
        '['||upper(NEW.risk)||'] '||coalesce(NEW.title, NEW.kind, 'Agent escalation'),
        coalesce(NEW.recommendation, NEW.title, '')||E'\n\nAgent: '||coalesce(NEW.agent,'?')||' · action #'||NEW.id||' · open the OS to decide.');
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
