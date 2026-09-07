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
create or replace function public.fn_supplier_invite_followups(p_rehearsal_tag text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_reh    boolean := p_rehearsal_tag is not null;
  v_today  date := (now() at time zone 'Asia/Dubai')::date;
  v_cap    int; v_site text; v_subj text; v_body text; v_pool int := 0;
  v_n int := 0; v_first int := 0; v_second int := 0;
  r record;
begin
  if not public.fn_supplier_outreach_golive() then
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('supplier_invite_followups', 'ok', jsonb_build_object('held', true, 'queued', 0, 'switch', 'supplier_outreach_golive'),
            'HELD: app_secrets.supplier_outreach_golive is false — the founder flips it when the app is ready; no follow-up was queued.', now(), now());
    return jsonb_build_object('held', true, 'queued', 0);
  end if;
  if not v_reh and not public.fn_is_working_day(v_today) then
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('supplier_invite_followups', 'ok', jsonb_build_object('held', false, 'queued', 0, 'skipped', 'non_working_day'),
            'No follow-ups on a non-working day (' || v_today || ' Dubai).', now(), now());
    return jsonb_build_object('held', false, 'queued', 0, 'skipped', 'non_working_day');
  end if;

  v_cap := coalesce((select nullif(value, '')::int from public.app_secrets where key = 'invite_daily_cap'), 10);
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  select value into v_subj from public.app_secrets where key = 'invite_subject';
  select value into v_body from public.app_secrets where key = 'invite_body';
  v_subj := coalesce((select nullif(value, '') from public.app_secrets where key = 'invite_followup_subject'),
                     'Following up: ' || coalesce(v_subj, 'your invitation to QuotesDone'));
  v_body := coalesce((select nullif(value, '') from public.app_secrets where key = 'invite_followup_body'),
                     'Hello {{company}},' || E'\n\n' ||
                     'We wrote to you recently and wanted to make sure our invitation reached you. The original message follows; '
                     'the registration link in it is still yours: {{link}}' || E'\n\n' || '---' || E'\n\n' || coalesce(v_body, ''));

  -- the pool: delivered, unanswered, unregistered, deliverable, and due by the working-day clock
  create temp table tmp_followup_pool on commit drop as
    select l.id, l.email, l.company_name, l.claim_token, l.invite_followups,
           case when l.invite_followups = 0 then 1 else 2 end as nth, l.invited_at
      from public.leads l
     where l.invite_status = 'sent' and l.invited_at is not null
       and coalesce(l.claimed, false) = false and coalesce(l.banned, false) = false
       and l.lifecycle_stage in ('contacted', 'no_response')
       and l.invite_followups < 2
       and ((l.invite_followups = 0 and now() >= public.fn_add_working_days(l.invited_at, 3))
         or (l.invite_followups = 1 and now() >= public.fn_add_working_days(l.invited_at, 7)))
       and not exists (select 1 from public.inbound_messages m where m.lead_id = l.id and m.created_at > l.invited_at)
       and not exists (select 1 from public.notifications n where n.type = 'supplier_invite_followup' and n.lead_id = l.id
                          and n.created_at > now() - interval '2 days')
       and case when v_reh then (l.email ilike '%@example.invalid' and l.company_name like 'ZZ DEMO — %')
                else (coalesce(l.email, '') not ilike '%@example.invalid'
                      and coalesce(l.company_name, '') not like 'ZZ DEMO — %'
                      and (public.fn_email_sendable(l.email) ->> 'ok')::boolean) end;
  select count(*) into v_pool from tmp_followup_pool;

  for r in select * from tmp_followup_pool order by invited_at, id limit v_cap loop
    insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, created_at)
    values ('supplier_invite_followup', r.email, 'supplier', r.id, v_subj,
            replace(replace(v_body, '{{company}}', coalesce(nullif(btrim(r.company_name), ''), 'there')),
                    '{{link}}', v_site || '/en/portal?t=' || r.claim_token::text),
            'queued', now());
    update public.leads set invite_followups = invite_followups + 1, invite_last_followup_at = now() where id = r.id;
    v_n := v_n + 1;
    if r.nth = 1 then v_first := v_first + 1; else v_second := v_second + 1; end if;
  end loop;

  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('supplier_invite_followups', 'ok',
          jsonb_build_object('held', false, 'queued', v_n, 'first', v_first, 'second', v_second, 'pool', v_pool, 'cap', v_cap, 'rehearsal', v_reh),
          'Invite follow-ups: ' || v_n || ' queued (' || v_first || ' at +3 working days, ' || v_second || ' at +7) of ' || v_pool
          || ' due, cap ' || v_cap || case when v_reh then ' [rehearsal ' || p_rehearsal_tag || ']' else '' end || '.', now(), now());
  return jsonb_build_object('held', false, 'queued', v_n, 'first', v_first, 'second', v_second, 'pool', v_pool, 'cap', v_cap);
end $function$;
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

create or replace function public.fn_supplier_lead_intake(p_rehearsal_tag text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_reh boolean := p_rehearsal_tag is not null;
  FREE constant text[] := array['gmail.com','googlemail.com','yahoo.com','ymail.com','yahoo.co.uk','hotmail.com','hotmail.co.uk','hotmail.fr',
                                'outlook.com','outlook.sa','live.com','msn.com','icloud.com','me.com','mac.com','aol.com','mail.com','gmx.com',
                                'gmx.net','protonmail.com','proton.me','yandex.com','zoho.com','rediffmail.com'];
  r record; v_lead record; v_intent text; v_matched text; v_task bigint; v_text text; v_site text;
  v_fee numeric; v_reveal numeric; v_title text; v_detail text; v_dom text;
  v_n int := 0; v_tasks int := 0; v_supp int := 0; v_counts jsonb := '{}'::jsonb;
begin
  if not public.fn_supplier_outreach_golive() then
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('supplier_lead_intake', 'ok', jsonb_build_object('held', true, 'classified', 0, 'switch', 'supplier_outreach_golive'),
            'HELD: app_secrets.supplier_outreach_golive is false — the founder flips it when the app is ready; the inbox was not classified.', now(), now());
    return jsonb_build_object('held', true, 'classified', 0);
  end if;
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  select supplier_reg_fee, standard_reveal_rate into v_fee, v_reveal from public.pricing_config order by id limit 1;

  for r in
    select m.* from public.inbound_messages m
     where not exists (select 1 from public.supplier_lead_intake i where i.inbound_id = m.id)
       and coalesce(m.from_email, '') <> ''
       and lower(coalesce(m.to_email, '')) not like 'expenses@%'        -- receipts are the bookkeeper's (resend_inbound)
       and case when v_reh then m.from_email ilike '%@example.invalid' else m.from_email not ilike '%@example.invalid' end
     order by m.id limit 200
  loop
    v_text := lower(coalesce(r.subject, '') || ' ' || left(coalesce(r.body, ''), 4000));
    v_dom  := lower(split_part(r.from_email, '@', 2));
    v_matched := null;
    select l.id, l.company_name, l.claim_token, l.invite_status into v_lead from public.leads l where l.id = r.lead_id;
    if v_lead.id is not null then
      v_matched := 'inbound.lead_id';
    else
      select l.id, l.company_name, l.claim_token, l.invite_status into v_lead from public.leads l
       where lower(l.email) = lower(r.from_email) or lower(coalesce(l.claimed_by, '')) = lower(r.from_email)
       order by l.id limit 1;
      if v_lead.id is not null then
        v_matched := 'email';
      elsif v_dom <> all(FREE) then
        select l.id, l.company_name, l.claim_token, l.invite_status into v_lead from public.leads l
         where l.email_domain is not null and lower(l.email_domain) = v_dom order by l.id limit 1;
        if v_lead.id is not null then v_matched := 'domain'; end if;
      end if;
    end if;

    v_intent := case
      when v_text ~ '(undeliverable|delivery (has )?failed|mail delivery|mailer-daemon|address not found|could not be delivered|delivery status notification)' then 'bounce'
      when v_text ~ '(unsubscribe|remove (me|us)|not interested|stop (emailing|sending|contacting)|do not contact|opt[- ]?out|take (me|us) off)' then 'decline'
      when v_text ~ '(register|sign[- ]?up|interested|join|onboard|how (do|can) (i|we)|send (me|us) the link|create (an )?account|want to (be )?list|would like to (be )?list)' then 'register'
      when coalesce(r.attachments_count, 0) > 0 or v_text ~ '(trade licen[cs]e|licen[cs]e cop|vat certificate|company profile|catalog(ue)?|\mtrn\M)' then 'document'
      when v_text ~ '(\?|\mfees?\M|\mcost|\mprice|how much|charges|commission|what is|pricing)' then 'question'
      else 'other' end;

    v_task := null;
    if v_intent = 'decline' then
      insert into public.email_suppressions (email, reason, source)
      values (lower(r.from_email), 'asked to be removed (inbound reply #' || r.id || ')', 'supplier_lead_intake')
      on conflict (email) do nothing;
      v_supp := v_supp + 1;
    elsif v_intent = 'bounce' then
      if v_lead.id is not null then
        update public.leads set invite_status = 'bounced' where id = v_lead.id and invite_status in ('queued', 'sent');
      end if;
    elsif v_intent in ('register', 'question', 'document') then
      v_title := 'Supplier reply (' || v_intent || '): ' || coalesce(v_lead.company_name, r.from_email)
                 || case when v_lead.id is not null then ' — lead #' || v_lead.id else '' end;
      select id into v_task from public.org_tasks where title = v_title and status not in ('done', 'cancelled') order by id limit 1;
      if v_task is null then
        v_detail := 'Inbound email #' || r.id || ' from ' || r.from_email || ' on ' || to_char(r.created_at, 'DD Mon YYYY HH24:MI')
          || ' UTC, subject: ' || coalesce(left(r.subject, 140), '(none)') || '. Classified deterministically as ' || v_intent
          || ' (keywords, no model). Linked to ' || coalesce('lead #' || v_lead.id || ' (' || coalesce(v_lead.company_name, '?') || ') by ' || v_matched, 'no lead (unknown sender)') || '.'
          || E'\n\n' || 'TEMPLATED REPLY TO SEND:' || E'\n'
          || case v_intent
               when 'register' then 'Thank you for your interest in QuotesDone. Registration takes a few minutes here: ' || v_site || '/en/portal'
                                    || coalesce('?t=' || v_lead.claim_token::text, '') || ' — your trade licence and company details are all you need. Reply to this email if anything is unclear.'
               when 'question' then 'Thank you for your question. QuotesDone matches your company to real customer requests in your trade'
                                    || coalesce('; the supplier registration fee is AED ' || v_fee::text, '')
                                    || coalesce(' and the platform fee on a won job is ' || round(v_reveal * 100, 1) || '% of the quoted value', '')
                                    || '. Registration: ' || v_site || '/en/portal' || coalesce('?t=' || v_lead.claim_token::text, '') || '.'
               else 'Thank you for sending your documents. They are attached to your supplier record and the verification team will review them; you will hear from us once the review is complete.' end
          || E'\n\n' || 'Queue the reply through the notifications outbox to ' || r.from_email || ' (type supplier_invite_reply); never send by hand. Close this task with the notification id as the deliverable.';
        insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, assigned_agent)
        values ('supply', v_title, v_detail, 'assigned', 'autonomous', false, 'outreach_draft', 'bd')
        returning id into v_task;
        v_tasks := v_tasks + 1;
      end if;
    end if;

    insert into public.supplier_lead_intake (inbound_id, lead_id, intent, matched_by, task_id, suppressed, run_tag)
    values (r.id, v_lead.id, v_intent, v_matched, v_task, v_intent = 'decline', p_rehearsal_tag);
    v_n := v_n + 1;
    v_counts := jsonb_set(v_counts, array[v_intent], to_jsonb(coalesce((v_counts ->> v_intent)::int, 0) + 1));
  end loop;

  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('supplier_lead_intake', 'ok',
          jsonb_build_object('held', false, 'classified', v_n, 'tasks_opened', v_tasks, 'suppressed', v_supp, 'rehearsal', v_reh) || v_counts,
          'Lead intake: ' || v_n || ' inbound message(s) classified by keyword (' || coalesce(v_counts::text, '{}') || '); '
          || v_tasks || ' reply task(s) opened on the BD manager; ' || v_supp || ' address(es) suppressed at their request'
          || case when v_reh then ' [rehearsal ' || p_rehearsal_tag || ']' else '' end || '.', now(), now());
  return jsonb_build_object('held', false, 'classified', v_n, 'tasks_opened', v_tasks, 'suppressed', v_supp) || v_counts;
end $function$;
revoke execute on function public.fn_supplier_lead_intake(text) from public, anon, authenticated;
grant execute on function public.fn_supplier_lead_intake(text) to service_role;

-- ---------------------------------------------------------------- (c) sourcing from what the estate already holds
create or replace function public.fn_supplier_lead_sourcing(p_rehearsal_tag text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_reh boolean := p_rehearsal_tag is not null;
  FREE constant text[] := array['gmail.com','googlemail.com','yahoo.com','ymail.com','yahoo.co.uk','hotmail.com','hotmail.co.uk','hotmail.fr',
                                'outlook.com','outlook.sa','live.com','msn.com','icloud.com','me.com','mac.com','aol.com','mail.com','gmx.com',
                                'gmx.net','protonmail.com','proton.me','yandex.com','zoho.com','rediffmail.com'];
  r record; v_dom text; v_label text; v_n int := 0; v_cand int := 0; v_refused int := 0; v_dup int := 0;
  v_staged int; v_inq int; v_quotes int;
begin
  if not public.fn_supplier_outreach_golive() then
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('supplier_lead_sourcing', 'ok', jsonb_build_object('held', true, 'harvested', 0, 'switch', 'supplier_outreach_golive'),
            'HELD: app_secrets.supplier_outreach_golive is false — the founder flips it when the app is ready; no lead was harvested.', now(), now());
    return jsonb_build_object('held', true, 'harvested', 0);
  end if;

  for r in
    select m.id, m.from_email, m.subject, m.created_at
      from public.inbound_messages m
     where m.from_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$'
       and lower(coalesce(m.to_email, '')) not like 'expenses@%'
       and lower(split_part(m.from_email, '@', 2)) <> all(FREE)
       and case when v_reh then m.from_email ilike '%@example.invalid'
                else m.from_email not ilike '%@example.invalid'
                     and not exists (select 1 from public.email_block_pattern p where p.active and lower(m.from_email) ~ p.pattern) end
       and not exists (select 1 from public.leads l
                        where lower(l.email) = lower(m.from_email)
                           or lower(coalesce(l.claimed_by, '')) = lower(m.from_email)
                           or (l.email_domain is not null and lower(l.email_domain) = lower(split_part(m.from_email, '@', 2))))
       and not exists (select 1 from public.email_suppressions s where lower(s.email) = lower(m.from_email))
       and not exists (select 1 from public.supplier_lead_intake i where i.inbound_id = m.id and i.intent in ('decline', 'bounce'))
     order by m.id limit 100
  loop
    v_cand := v_cand + 1;
    v_dom   := lower(split_part(r.from_email, '@', 2));
    v_label := initcap(replace(split_part(v_dom, '.', 1), '-', ' '));
    -- one lead per domain, also within a run (the loop's query was planned before the first insert)
    if exists (select 1 from public.leads l where l.email_domain is not null and lower(l.email_domain) = v_dom) then
      v_dup := v_dup + 1; continue;
    end if;
    begin
      insert into public.leads (company_name, email, email_domain, domain, website, source, notes, scraped_at)
      values (case when v_reh then 'ZZ DEMO — ' || v_label else v_label end, lower(r.from_email), v_dom, v_dom, 'https://' || v_dom,
              'inbound_email',
              'Harvested by the BD manager from inbound email #' || r.id || ' ("' || left(coalesce(r.subject, ''), 80) || '", '
              || to_char(r.created_at, 'DD Mon YYYY') || '). The company name is the mail domain until enrichment corrects it.',
              current_date);
      v_n := v_n + 1;
    exception when others then
      v_refused := v_refused + 1;     -- e.g. the disposable-domain guard on leads; the sender stays an inbound row
    end;
  end loop;

  select count(*) filter (where stage = 'profiled') into v_staged from public.yello_staging;
  select count(*) into v_inq from public.inquiries;
  select count(*) into v_quotes from public.quotes;
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('supplier_lead_sourcing', 'ok',
          jsonb_build_object('held', false, 'harvested', v_n, 'candidates', v_cand, 'refused', v_refused, 'duplicate_domain', v_dup,
                             'staged_directory_profiled_left', v_staged, 'inquiries', v_inq, 'quotes', v_quotes, 'rehearsal', v_reh),
          'Lead sourcing: ' || v_n || ' new lead(s) from ' || v_cand || ' inbound business-domain sender(s) with no lead (' || v_refused
          || ' refused by a guard, ' || v_dup || ' same-domain duplicate(s)). Other estate sources: the staged directory is promoted daily by supplier_discovery_daily (cron 322; '
          || v_staged || ' profiled rows without an email remain); RFQ and quote supplier mentions need an inquiry to exist (' || v_inq
          || ' inquiries, ' || v_quotes || ' quotes). No scraping, no paid inference.'
          || case when v_reh then ' [rehearsal ' || p_rehearsal_tag || ']' else '' end, now(), now());
  return jsonb_build_object('held', false, 'harvested', v_n, 'candidates', v_cand, 'refused', v_refused, 'duplicate_domain', v_dup, 'staged_directory_profiled_left', v_staged);
end $function$;
revoke execute on function public.fn_supplier_lead_sourcing(text) from public, anon, authenticated;
grant execute on function public.fn_supplier_lead_sourcing(text) to service_role;

-- ---------------------------------------------------------------- (e) the cron entry
create or replace function public.fn_supplier_outreach_daily()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_f jsonb; v_i jsonb; v_s jsonb;
begin
  v_f := public.fn_supplier_invite_followups(null);
  v_i := public.fn_supplier_lead_intake(null);
  v_s := public.fn_supplier_lead_sourcing(null);
  return jsonb_build_object('golive', public.fn_supplier_outreach_golive(), 'followups', v_f, 'intake', v_i, 'sourcing', v_s);
end $function$;
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
