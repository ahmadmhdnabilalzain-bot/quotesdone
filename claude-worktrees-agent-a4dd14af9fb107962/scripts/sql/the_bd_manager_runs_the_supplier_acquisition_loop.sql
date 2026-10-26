-- THE BUSINESS DEVELOPMENT MANAGER RUNS THE SUPPLIER ACQUISITION LOOP (6 Sep 2026).
--
-- Founder, 6 Sep 2026 (final): "for suppliers we will start the invite campaign from the leads we
-- have, also there should be an agent who is keeping track of the emails and getting us new leads and
-- contacting them to register. monthly at least we have to register 300 suppliers. but of course none
-- of this will run till the app is perfect, which i will update about it." And: no new AI employees —
-- the work belongs to the existing employee that owns it. That employee is org_role.business_development
-- (Business Development Manager, org_agents.bd, department supply): responsibilities "supplier
-- acquisition", owner of employee_task, manager of onboarding / supplier_verification / supplier_coverage.
--
-- MEASURED before building (production, 6 Sep 2026 13:49 UTC): leads 21,965 (19,896 with an email, 0
-- fixtures); the August funnel — 171 invited, 161 delivered/no response, 10 bounced, 0 registered, 1 lead
-- in lifecycle_stage registered (a 12 Aug probe artefact); supplier_invites_daily (cron 2) already plans
-- a batch of 50 every 09:00 UTC and HOLDS it on app_secrets.invite_enabled=false; no follow-up exists;
-- inbound_messages holds 4 rows, all receipts forwarded to expenses@; there is no public.suppliers table
-- — leads IS the supplier table (registration timestamps: registration_submitted_at, accepted_terms_at,
-- approved_at); the staged directory (yello_staging) is promoted daily by supplier_discovery_daily
-- (cron 322): 11,289 duplicates, 1,500 promoted, 334 profiled rows without an email left.
--
-- WHAT THIS FILE BUILDS, all owned by business_development and ALL HELD behind ONE founder switch,
-- app_secrets.supplier_outreach_golive = 'false' (every sweep reads it and records "held" while false):
--   (0) fn_supplier_outreach_golive()        the switch, read by every sweep below AND by
--                                             enqueue_supplier_invites (restated here: both this switch
--                                             and invite_enabled must be true before an invitation is
--                                             written; the schedule row says which one holds the door).
--   (a) fn_supplier_invite_followups(tag)    follow-ups at +3 and +7 WORKING days (fn_add_working_days,
--                                             company holidays) after a delivered invitation, at most 2,
--                                             never to a lead that replied, registered, bounced, is
--                                             suppressed / blocked-pattern / MX-dead (fn_email_sendable),
--                                             queued through the normal notifications outbox
--                                             (type supplier_invite_followup) and recorded on the lead
--                                             (leads.invite_followups, invite_last_followup_at).
--   (b) fn_supplier_lead_intake(tag)         reads inbound_messages, classifies supplier-intent replies
--                                             DETERMINISTICALLY (keywords, no model) into register /
--                                             question / document / decline / bounce / other, links them
--                                             to a lead (inbound lead_id, then email, then domain), opens
--                                             ONE org_task on the BD manager with the templated reply,
--                                             suppresses a decline, marks a bounce. Record: supplier_lead_intake.
--   (c) fn_supplier_lead_sourcing(tag)       harvests new leads from what the estate holds without paid
--                                             inference or scraping: inbound senders on business domains
--                                             that match no lead become leads (source inbound_email). The
--                                             run row states the other estate sources honestly: the staged
--                                             directory is promoted by cron 322; RFQ and quote supplier
--                                             mentions cannot be harvested until an inquiry exists (0 today).
--   (d) the KPI                              company_goals.suppliers_registered_monthly (>= 300 a month)
--                                             and employee_kpi for agent bd, measured by the existing
--                                             fn_employee_kpi_measure from leads' registration timestamps.
--   (e) fn_supplier_outreach_daily()         the cron entry (supplier_outreach_daily, 05:30 UTC = 09:30
--                                             Dubai) wrapped and traced by the kernel under
--                                             business_development / supply, registered for the Phase D
--                                             door; the existing invite cron (2) is re-owned by the same role.
-- A rehearsal tag restricts every sweep to ZZ DEMO — / @example.invalid fixtures and bypasses the
-- reserved-TLD block for them; the switch is still read. scripts/staging/rehearse_supplier_loops.mjs
-- proves it inside an aborted transaction.
--
--   node scripts/apply_sql.mjs scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql --apply --ddl
begin;

-- ---------------------------------------------------------------- (0) the founder's one switch
insert into public.app_secrets (key, value) values ('supplier_outreach_golive', 'false')
on conflict (key) do nothing;

create or replace function public.fn_supplier_outreach_golive()
returns boolean
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  select coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'supplier_outreach_golive'), false);
$function$;
revoke execute on function public.fn_supplier_outreach_golive() from public, anon, authenticated;
grant execute on function public.fn_supplier_outreach_golive() to service_role;

-- the record of a follow-up lives on the lead, next to the invitation it follows
alter table public.leads add column if not exists invite_followups integer not null default 0;
alter table public.leads add column if not exists invite_last_followup_at timestamptz;

-- ---------------------------------------------------------------- the invite sweep reads the switch
CREATE OR REPLACE FUNCTION public.enqueue_supplier_invites(p_cap integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_site text;
  v_today date := (now() at time zone 'UTC')::date;
  v_planned int; v_used int; v_remaining int; v_subj text; v_body text; v_count int;
  v_inv_recent int; v_bounced_recent int; v_rate numeric; v_max_rate numeric; v_target int; v_cap int;
  v_pause boolean := false; v_why text; v_go boolean; v_pool int;
  v_hol_name text; v_hol_action text; v_hol_end date;
begin
  -- THE CALENDAR THE COMPANY KEEPS ABOUT ITSELF. Checked before anything is planned or written, so
  -- a frozen day leaves no invite_schedule row claiming it planned sends it never made.
  select c.event_name, c.action, c.ends_on into v_hol_name, v_hol_action, v_hol_end
    from public.company_calendar c
   where c.kind = 'public_holiday'
     and v_today between c.starts_on and coalesce(c.ends_on, c.starts_on)
   order by c.starts_on limit 1;
  if v_hol_name is not null then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'calendar_paused', true, 'resumes_on', coalesce(v_hol_end, v_today) + 1),
            'Invites held: company_calendar has "' || v_hol_name || '" covering today. Its recorded action: '
            || coalesce(v_hol_action, '(none recorded)'), now(), now());
    return 0;
  end if;

  -- THE PLAN, before the gate. The batch is the ramp's cap bounded by the pool that can be written
  -- to today; the row says whether the day is open or held and why.
  -- 6 SEP 2026: the founder's ONE switch for supplier outreach (app_secrets.supplier_outreach_golive) is read
  -- first; invite_enabled stays the deliverability ramp's own gate. Both must be true before an invitation
  -- is written, and the schedule row names what holds the door.
  v_go  := (coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') = 'true')
           and public.fn_supplier_outreach_golive();
  v_cap := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), 10);
  select count(*) into v_pool from leads l
   where l.email is not null and l.email <> '' and l.invite_status is null
     and coalesce(l.source,'') <> 'self_registered' and coalesce(l.claimed,false) = false
     and coalesce(l.banned,false) = false;
  v_planned := least(coalesce(p_cap, v_cap), v_cap, v_pool);
  insert into invite_schedule(day, planned, status, note)
  values (v_today, greatest(v_planned, 0),
          case when v_go then 'approved' else 'pending' end,
          'batch of ' || greatest(v_planned, 0) || ' from a pool of ' || v_pool || ' never-invited lead(s) with an email, cap ' || v_cap
          || case when v_go then '; sending open'
                  when not public.fn_supplier_outreach_golive() then '; HELD — real invitations wait for the founder''s go (app_secrets.supplier_outreach_golive is false)'
                  else '; HELD — real invitations wait for the founder''s go (app_secrets.invite_enabled)' end)
    on conflict (day) do update
      set planned = excluded.planned, status = excluded.status, note = excluded.note;

  if not v_go then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'planned', greatest(v_planned, 0), 'pool', v_pool, 'cap', v_cap, 'held', true),
            'Invites planned and HELD: ' || greatest(v_planned, 0) || ' of a pool of ' || v_pool
            || ' would be queued at cap ' || v_cap || '; '
            || case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive' else 'invite_enabled' end
            || ' is false, so nothing was written to the outbox.', now(), now());
    return 0;
  end if;
  if v_planned <= 0 then return 0; end if;

  v_max_rate := coalesce((select nullif(value,'')::numeric from app_secrets where key='invite_max_bounce_rate'), 0.08);
  select count(*) into v_inv_recent from leads where invited_at > now() - interval '3 days';
  select count(*) into v_bounced_recent from leads where invite_status='bounced' and invited_at > now() - interval '3 days';
  v_rate := round(v_bounced_recent::numeric / greatest(v_inv_recent,1), 3);

  if v_inv_recent >= 15 and v_rate > v_max_rate then
    v_pause := true;
    v_why := 'bounce rate '||(v_rate*100)||'% over 3 days ('||v_bounced_recent||'/'||v_inv_recent||') exceeds the '||(v_max_rate*100)||'% limit';
  end if;
  -- SCALES WITH THE RAMP (12 Aug 2026). See the header: five was right at a cap of ten and wrong at
  -- two hundred. greatest() ignores nulls, so both arms are non-null by construction.
  if not v_pause and v_bounced_recent >= greatest(5, ceil(v_inv_recent * v_max_rate)::int) then
    v_pause := true;
    v_why := v_bounced_recent||' hard bounces in 3 days against '||v_inv_recent||' sent. Regardless of rate, that is a list-quality problem';
  end if;

  if v_pause then
    update app_secrets set value='false' where key='invite_enabled';
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; auto-paused: ' || v_why where day = v_today;
    if not exists (select 1 from founder_alerts where event='invite_paused_bounce' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values('crit','invite_paused_bounce','Supplier invites AUTO-PAUSED: '||v_why||'. Clean the list before resuming.','system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('invite_paused_bounce', coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com'),'admin','email','Supplier invites paused - deliverability risk','Invites were auto-paused: '||v_why||'. Validate the list, then re-enable.','queued');
    end if;
    return 0;
  end if;

  select coalesce(nullif(btrim(value),''), 'https://quotesdone.com') into v_site
    from app_secrets where key='public_site_url';
  select value into v_subj from app_secrets where key='invite_subject';
  select value into v_body from app_secrets where key='invite_body';
  select count(*) into v_used from notifications where type='supplier_invite' and (created_at at time zone 'UTC')::date = v_today;
  v_remaining := greatest(0, v_planned - v_used);
  if v_remaining <= 0 then return 0; end if;

  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_category'),
                       (select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 10);

  -- MATERIALIZED, 4 Aug 2026, and it is load-bearing. Both CTEs are referenced exactly once, from
  -- inside the correlated subquery in `prio`. Without this keyword Postgres inlines them there and
  -- re-runs the whole leads x lead_subcategory aggregate once per candidate - 19,632 times, twice
  -- over, ~220 s against a 120 s timeout. Neither depends on the outer row, so computing them once
  -- is semantically identical and 54x faster. Do not remove.
  with activated as materialized (
    select ls.domain_slug, count(distinct l.id) ct
    from leads l join lead_subcategory ls on ls.lead_id = l.id
    where coalesce(l.claimed,false) = true
    group by ls.domain_slug
  ),
  under as materialized (
    select d.slug as domain_slug, coalesce(a.ct,0) as have
    from catalog_domains d left join activated a on a.domain_slug = d.slug
    where coalesce(a.ct,0) < v_target
  ),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified
    from leads l
    where l.email is not null and l.email <> '' and l.invite_status is null
      and coalesce(l.source,'') <> 'self_registered' and coalesce(l.claimed,false) = false
      and (public.fn_email_sendable(l.email)->>'ok')::boolean
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain,
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      case when c.email_verified in ('verified','true') then 0 else 1 end as unverified_rank,
      -- ROLE ADDRESSES LAST (12 Aug 2026). All five bounces to date are role addresses on domains
      -- with live MX, every one flagged email_verified by the scrape, so neither the MX cull nor
      -- that flag protects against them. Not excluded: 5,870 of 19,835 eligible leads publish no
      -- other address and dropping them would drop the supplier. Ranked behind a named human at the
      -- same verification rank, so a run reaches people first and works down to shared inboxes only
      -- when it runs out of them.
      case when split_part(lower(c.email),'@',1) in
             ('info','sales','admin','contact','enquiry','enquiries','inquiry','office','mail',
              'support','hello','marketing','general','accounts','reception','careers','hr')
           then 1 else 0 end as role_rank
    from cand c
  ),
  elig as (
    select id, email, company_name, claim_token from (
      select id, email, company_name, claim_token, pdomain, unverified_rank, role_rank,
        case when pdomain='~none' then 1 else 0 end as is_none,
        row_number() over (partition by pdomain order by unverified_rank, role_rank, id) as rk,
        row_number() over (partition by coalesce(email_domain, split_part(email,'@',2)) order by unverified_rank, role_rank, id) as domain_rk
      from prio
    ) r
    where domain_rk <= 5
    order by is_none, rk, unverified_rank, role_rank, pdomain
    limit v_remaining
  ),
  ins as (
    insert into notifications(type,to_email,to_role,lead_id,subject,body,status,created_at)
    select 'supplier_invite', email, 'supplier', id, v_subj,
           replace(
             replace(v_body, '{{company}}', coalesce(nullif(btrim(company_name),''), 'there')),
             '{{link}}', v_site || '/en/portal?t=' || claim_token::text), 'queued', now()
    from elig returning to_email
  )
  update leads set invite_status='queued', invited_at=now()
  where invite_status is null and lower(email) in (select lower(to_email) from ins);
  get diagnostics v_count = row_count;
  update invite_schedule set sent = sent + v_count where day = v_today;
  insert into agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('supplier_invites', 'ok',
          jsonb_build_object('queued', v_count, 'planned', v_planned, 'pool', v_pool, 'cap', v_cap, 'held', false),
          'Invites: ' || v_count || ' queued of ' || v_planned || ' planned (pool ' || v_pool || ', cap ' || v_cap || ').', now(), now());
  return v_count;
end;
$function$;

-- ---------------------------------------------------------------- (a) follow-ups at +3 and +7 working days
-- ROUTINE REMOVED 7 September 2026. public.fn_supplier_invite_followups was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke execute on function public.fn_supplier_invite_followups(text) from public, anon, authenticated;
grant execute on function public.fn_supplier_invite_followups(text) to service_role;

-- ---------------------------------------------------------------- (b) lead intake: the inbox, classified without a model
create table if not exists public.supplier_lead_intake (
  inbound_id    bigint primary key references public.inbound_messages(id) on delete cascade,
  lead_id       bigint references public.leads(id) on delete set null,
  intent        text not null check (intent in ('register', 'question', 'document', 'decline', 'bounce', 'other')),
  matched_by    text,
  task_id       bigint,
  suppressed    boolean not null default false,
  classified_at timestamptz not null default now(),
  run_tag       text
);
alter table public.supplier_lead_intake enable row level security;
revoke all on public.supplier_lead_intake from public, anon, authenticated;

-- ROUTINE REMOVED 7 September 2026. public.fn_supplier_lead_intake was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke execute on function public.fn_supplier_lead_intake(text) from public, anon, authenticated;
grant execute on function public.fn_supplier_lead_intake(text) to service_role;

-- ---------------------------------------------------------------- (c) sourcing from what the estate already holds
-- ROUTINE REMOVED 7 September 2026. public.fn_supplier_lead_sourcing was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke execute on function public.fn_supplier_lead_sourcing(text) from public, anon, authenticated;
grant execute on function public.fn_supplier_lead_sourcing(text) to service_role;

-- ---------------------------------------------------------------- (e) the cron entry
-- ROUTINE REMOVED 7 September 2026. public.fn_supplier_outreach_daily was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke execute on function public.fn_supplier_outreach_daily() from public, anon, authenticated;
grant execute on function public.fn_supplier_outreach_daily() to service_role;

-- ---------------------------------------------------------------- (d) the KPI: 300 registered suppliers a month
insert into public.company_goals (key, goal, metric, target_value, unit, period, owner_dept, measure_sql, active, sort, category, horizon, direction)
values ('suppliers_registered_monthly', '300 suppliers registered every month', 'Suppliers registered this calendar month', 300, 'suppliers', 'monthly', 'supply',
        'select count(*)::numeric from leads where lifecycle_stage = ''registered'' and coalesce(registration_submitted_at, accepted_terms_at, approved_at) >= date_trunc(''month'', now()) and coalesce(email, '''') not ilike ''%@example.invalid'' and coalesce(company_name, '''') not like ''ZZ DEMO — %''',
        true, 21, 'Supplier', 'year_1', 'at_least')
on conflict (key) do update set goal = excluded.goal, metric = excluded.metric, target_value = excluded.target_value, unit = excluded.unit,
  period = excluded.period, owner_dept = excluded.owner_dept, measure_sql = excluded.measure_sql, active = true, direction = excluded.direction;

insert into public.employee_kpi (agent_key, kpi, metric, target_value, unit, cadence, serves_goal, measure_sql, active, kpi_class)
values ('bd', 'Suppliers registered per month', 'Registered suppliers this calendar month (founder target: at least 300)', 300, 'suppliers', 'monthly',
        'suppliers_registered_monthly',
        'select count(*)::numeric from leads where lifecycle_stage = ''registered'' and coalesce(registration_submitted_at, accepted_terms_at, approved_at) >= date_trunc(''month'', now()) and coalesce(email, '''') not ilike ''%@example.invalid'' and coalesce(company_name, '''') not like ''ZZ DEMO — %''',
        true, 'conversion')
on conflict (agent_key, kpi) do update set metric = excluded.metric, target_value = excluded.target_value, unit = excluded.unit,
  cadence = excluded.cadence, serves_goal = excluded.serves_goal, measure_sql = excluded.measure_sql, active = true, kpi_class = excluded.kpi_class;

-- ---------------------------------------------------------------- the clock, the owner, the door
do $cron$
declare v_job bigint; v jsonb;
begin
  select jobid into v_job from cron.job where jobname = 'supplier_outreach_daily';
  if v_job is null then
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
  end if;
  v := public.fn_kernel_wrap_and_enable_cron(v_job, 'business_development', 'supply', 'routine_operational_decision');
  if coalesce((v ->> 'ok')::boolean, false) is not true then raise exception 'fn_kernel_wrap_and_enable_cron(%) refused: %', v_job, v; end if;
  update public.phase_c_component
     set accountable_role_id = 'business_development', department_id = 'supply',
         repair_or_keep_action = 'built 6 Sep 2026: the BD manager''s daily supplier acquisition sweep (follow-ups, inbox intake, lead sourcing), held behind app_secrets.supplier_outreach_golive',
         evidence = 'scheduled and wrapped 6 Sep 2026 (scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql)'
   where component_id = 'cron:supplier_outreach_daily';

  -- the invite sweep itself (cron 2) is the same employee's work
  update public.phase_c_component set accountable_role_id = 'business_development', department_id = 'supply'
   where component_id = 'cron:supplier_invites_daily';

  insert into public.cron_registry (jobname, human_name, category, purpose) values
    ('supplier_outreach_daily', 'Supplier acquisition sweep (BD manager)', 'Supply',
     'fn_supplier_outreach_daily() — 05:30 UTC daily: invite follow-ups at +3/+7 working days (max 2, deliverable addresses only), inbox intake classified by keyword into reply tasks on the BD manager, and lead sourcing from inbound business-domain senders. Every part is HELD while app_secrets.supplier_outreach_golive is false (founder decision 6 Sep 2026: nothing runs until the app is perfect).')
  on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
    (v_job, 'supplier_outreach_daily',
     'INSERTs public.notifications (type supplier_invite_followup) and UPDATEs public.leads (invite_followups, invite_last_followup_at, invite_status on a bounce); INSERTs public.org_tasks (BD reply tasks), public.email_suppressions, public.supplier_lead_intake, public.leads (source inbound_email) and public.agent_runs. While app_secrets.supplier_outreach_golive is false it INSERTs three held agent_runs rows and nothing else.',
     'Daily 05:30 UTC in its own transaction. Without a rehearsal tag it EXCLUDES every ZZ DEMO — / @example.invalid lead and inbound sender by predicate, so a scenario''s fixtures are invisible to it; with the switch off (the state on every day until the founder flips it) it writes only agent_runs. close() asserts scenario rows by id/marker.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
end $cron$;

-- ---------------------------------------------------------------- the ownership ledger follows the manifest
insert into public.kernel_routine_ownership (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file, justification, recorded_at)
values
  ('public', 'fn_supplier_outreach_golive', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql', null, now()),
  ('public', 'fn_supplier_invite_followups', 'p_rehearsal_tag text', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql', null, now()),
  ('public', 'fn_supplier_lead_intake', 'p_rehearsal_tag text', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql', null, now()),
  ('public', 'fn_supplier_lead_sourcing', 'p_rehearsal_tag text', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql', null, now()),
  ('public', 'fn_supplier_outreach_daily', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql', null, now())
on conflict (schema_name, routine_name, identity_args) do update set ownership_class = excluded.ownership_class, classified_by_rule = excluded.classified_by_rule,
  evidence = excluded.evidence, source_kind = excluded.source_kind, source_file = excluded.source_file, justification = null, recorded_at = now();
update public.kernel_routine_ownership
   set source_file = 'scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql', source_kind = 'MANIFEST',
       evidence = 'restated by scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql (6 Sep 2026): reads supplier_outreach_golive before invite_enabled', recorded_at = now()
 where schema_name = 'public' and routine_name = 'enqueue_supplier_invites';

-- ---------------------------------------------------------------- proof, in the same transaction
do $proof$
declare v_job bigint; t bigint; v_res text; n int; v jsonb;
begin
  if public.fn_supplier_outreach_golive() then raise exception 'supplier_outreach_golive must be false at build time'; end if;
  select jobid into v_job from cron.job where jobname = 'supplier_outreach_daily' and active and command ilike '%fn_kernel_cron_exec%';
  if v_job is null then raise exception 'supplier_outreach_daily is not wrapped and active'; end if;
  t := public.fn_kernel_cron_exec(v_job);
  select result into v_res from public.phase_c_system_execution where trace_id = t;
  if v_res is distinct from 'succeeded' then raise exception 'first traced run of supplier_outreach_daily ended %', v_res; end if;
  select count(*) into n from public.agent_runs
   where agent in ('supplier_invite_followups', 'supplier_lead_intake', 'supplier_lead_sourcing')
     and started_at > now() - interval '2 minutes' and (counts ->> 'held')::boolean;
  if n < 3 then raise exception 'expected three held run rows from the traced run, found %', n; end if;
  select count(*) into n from public.employee_kpi where agent_key = 'bd' and kpi = 'Suppliers registered per month' and active;
  if n <> 1 then raise exception 'the BD KPI row is missing'; end if;
  raise notice 'proof: switch false, cron % wrapped and traced (trace %), 3 held run rows, KPI row present', v_job, t;
end $proof$;

commit;
