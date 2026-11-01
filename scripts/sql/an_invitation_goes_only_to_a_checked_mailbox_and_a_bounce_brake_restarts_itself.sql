-- AN INVITATION GOES ONLY TO A CHECKED MAILBOX, AND A BOUNCE BRAKE RESTARTS ITSELF (2 Nov 2026, ledger 1449).
-- Assigned: sales_engineer. Audit docs/reports/WHOLE_PICTURE_AUDIT_2_NOV.md, items 2 and 11.
--
-- MEASURED on production, 2 Nov: 52 real sends, 18 still queued; 7 bounced (13.5%, limit 3%). The brakes read leads.invited_at,
-- which is QUEUE time, so they measured 7 of 70, and invite_schedule.sent counted 70 for the same reason. 17,330 eligible leads,
-- 14,202 never checked. Nothing resumed a pause. All 7 bounced addresses were on a domain with a real MX and all 7 are already
-- suppressed: a DNS check cannot see them, which is why the order of invitations also changes (fn_supplier_invite_candidates).
--
-- WHAT THIS DOES
--  1. public.lead_email_check holds a verdict per lead, bound to the address by hash (no second copy of the address).
--     fn_supplier_invite_eligible and _ids require 'verified'; fn_notifications_supplier_invite_is_whole already asks the former,
--     so the outbox itself refuses an unverified lead on every path. Duty sales_engineer.lead_email_check runs the batch
--     (sales_engineer/lead_email_check.ts: 200 leads, at most 40 DNS lookups a run).
--     UNTIL THE FIRST BATCHES RUN THE POOL IS EMPTY AND NOTHING IS QUEUED. 200 leads per 5 minutes covers 17,330 in about 7 hours.
--  2. public.invite_brake records a bounce brake. Duty sales_engineer.invite_restart suppresses the bounced addresses and may
--     resume ONCE in 30 days, no sooner than 3 days after the brake, and only if the real 3-day window would not fire the brake
--     again. The window is never reset. At most 10 a day until the first day that really sent has passed. Bounces over the limit on
--     the sends since the restart, or any brake, within 30 days are a second breach: it stays paused and opens a CEO task. A complaint pause, another seat's pause and the founder's go are never lifted.
--  3. fn_invite_send_health is the one read of real sends. invite_schedule.sent and v_invite_deliverability_daily count real sends.

create table if not exists public.lead_email_check (
  lead_id bigint primary key references public.leads(id) on delete cascade,
  email_md5 text not null,
  verdict text not null check (verdict in ('verified', 'rejected', 'retry')),
  reason text not null,
  mailbox text check (mailbox in ('named', 'role', 'free')),
  mx_kind text,
  checked_at timestamptz not null default now(),
  check (verdict <> 'verified' or mx_kind = 'mx')
);
alter table public.lead_email_check enable row level security;
drop policy if exists lead_email_check_service_role_only on public.lead_email_check;
create policy lead_email_check_service_role_only on public.lead_email_check as permissive for all to public using (false) with check (false);
revoke all on public.lead_email_check from anon, authenticated;

create table if not exists public.invite_brake (
  id bigserial primary key,
  source text not null,
  why text not null,
  fired_at timestamptz not null default now(),
  resumed_at timestamptz,
  resume_note text,
  restarted_by_seat boolean not null default false,
  ceo_task_opened_at timestamptz
);
create unique index if not exists invite_brake_one_open on public.invite_brake ((true)) where resumed_at is null;
alter table public.invite_brake enable row level security;
drop policy if exists invite_brake_service_role_only on public.invite_brake;
create policy invite_brake_service_role_only on public.invite_brake as permissive for all to public using (false) with check (false);
revoke all on public.invite_brake from anon, authenticated;

-- THE ONE READ OF REAL SENDS: an invitation the outbox actually sent, by when it was sent.
create or replace function public.fn_invite_send_health(p_since timestamptz)
returns table(sent integer, bounced integer, complained integer)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select count(*)::int,
         (count(*) filter (where l.invite_status = 'bounced'))::int,
         (count(*) filter (where l.invite_status = 'complained'))::int
    from public.notifications n
    join public.leads l on l.id = n.lead_id
   where n.type = 'supplier_invite' and n.sent_at is not null and n.sent_at > p_since
     and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(n.to_email)
$fn$;
revoke execute on function public.fn_invite_send_health(timestamptz) from public, anon, authenticated;

-- A SMALL FIRST BATCH: at most 10 a day from the seat's restart until the first Dubai day that really sent has passed. It follows
-- sends, not the clock, because a restart can land on a weekend when nothing goes.
create or replace function public.fn_invite_restart_cap(p_cap integer)
returns integer
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with r as (select max(b.resumed_at) as at from public.invite_brake b where b.restarted_by_seat),
       s as (select min(n.sent_at) as first_sent from public.notifications n, r
              where n.type = 'supplier_invite' and n.sent_at > r.at and not public.fn_is_demo_email(n.to_email))
  select case when r.at is not null
               and (s.first_sent is null or (s.first_sent at time zone 'Asia/Dubai')::date >= (now() at time zone 'Asia/Dubai')::date)
              then least(p_cap, 10) else p_cap end
    from r, s
$fn$;
revoke execute on function public.fn_invite_restart_cap(integer) from public, anon, authenticated;

-- A REMINDER TO A SUPPLIER WHO ALREADY STARTED IS NOT COLD MAIL. A pause does not hold it; the founder's go and a complaint do.
create or replace function public.fn_supplier_reminder_is_open(p_stage text)
returns boolean
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select public.fn_supplier_outreach_golive()
     and (coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          or (p_stage in ('started', 'incomplete')
              and (select h.complained from public.fn_invite_send_health(now() - interval '30 days') h) = 0
              and not exists (select 1 from public.it_watch_finding f
                               where f.detector_key = 'deliverability:supplier_invite' and f.status = 'open' and f.state = 'paused'
                                 and f.evidence->>'paused_by' <> 'invite_same_day_brake')))
$fn$;
revoke execute on function public.fn_supplier_reminder_is_open(text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_invite_same_day_brake()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_br_max numeric := coalesce((c->>'same_day_pause_bounce_rate')::numeric, 0.05);
  v_b_min  int     := coalesce((c->>'same_day_pause_min_bounces')::int, 3);
  v_cr_max numeric := coalesce((c->>'pause_complaint_rate')::numeric, 0.003);
  v_c_min  int     := coalesce((c->>'same_day_pause_min_complaints')::int, 1);
  v_day date := (now() at time zone 'Asia/Dubai')::date;
  v_sent int; v_b int; v_c int; v_why text;
begin
  if coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') <> 'true' then
    return null;  -- already stopped; nothing more to stop
  end if;

  select h.sent, h.bounced, h.complained into v_sent, v_b, v_c
    from public.fn_invite_send_health(v_day::timestamp at time zone 'Asia/Dubai') h;

  if v_c >= v_c_min and v_c::numeric / greatest(v_sent, 1) >= v_cr_max then
    v_why := v_c || ' spam complaint(s) on ' || v_sent || ' invitation(s) today';
  elsif v_b >= v_b_min and v_b::numeric / greatest(v_sent, 1) >= v_br_max then
    v_why := v_b || ' bounce(s) on ' || v_sent || ' invitation(s) today (' || round(v_b * 100.0 / greatest(v_sent, 1), 1) || '%)';
    insert into public.invite_brake(source, why) values ('invite_same_day_brake', v_why) on conflict do nothing;
  else
    return null;
  end if;

  perform public.fn_invite_campaign_pause('invite_same_day_brake', v_why,
    jsonb_build_object('dubai_day', v_day, 'sent', v_sent, 'bounced', v_b, 'complained', v_c),
    jsonb_build_object('sent_today', v_sent, 'bounced_today', v_b, 'complained_today', v_c));
  return null;
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_invite_ramp()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  -- founder ruling 1231: the dated founder cap is an upper bound only. It lowers the configured ceiling and the
  -- restart base; it never raises a cap set lower, and the back-off below can still halve.
  v_base int     := least(coalesce((c->>'base_cap')::int, 30), public.fn_invite_founder_cap((now() at time zone 'Asia/Dubai')::date));
  v_ceiling int  := least(coalesce((c->>'ceiling_cap')::int, 200), public.fn_invite_founder_cap((now() at time zone 'Asia/Dubai')::date));
  v_growth numeric := coalesce((c->>'growth_factor')::numeric, 1.5);
  v_used_pct numeric := coalesce((c->>'grow_if_used_pct')::numeric, 0.8);
  v_ok_b numeric := coalesce((c->>'grow_max_bounce_rate')::numeric, 0.02);
  v_ok_c numeric := coalesce((c->>'grow_max_complaint_rate')::numeric, 0.001);
  v_back_b numeric := coalesce((c->>'backoff_bounce_rate')::numeric, 0.035);
  v_back_n int   := coalesce((c->>'backoff_min_sends')::int, 20);
  v_pause_c numeric := coalesce((c->>'pause_complaint_rate')::numeric, 0.003);
  v_pause_n int  := coalesce((c->>'pause_min_complaints')::int, 2);
  v_cur int; v_new int; v_note text; v_status text := 'ok';
  v_sent_total int; v_last_sent timestamptz; v_last_day date; v_last_day_sent int;
  v_s48 int; v_b48 int; v_c48 int; v_br numeric; v_cr numeric;
  v_restart boolean := false; v_prev_restart boolean; v_grew_since boolean; v_uncontacted int;
  -- THE LANE'S OWN HISTORY (24 Sep 2026): '-infinity' while invite_lane_enabled is off (every scope below is
  -- then a no-op); the activation stamp while it is on, so the new subdomain restarts at day 1.
  v_since timestamptz := public.fn_invite_lane_since();
begin
  v_cur := coalesce((select nullif(value,'')::int from app_secrets where key = 'invite_daily_cap'), v_base);
  -- ruling 1231 review: the restart base (a new lane's day 1) is never above the cap already set, so a restart
  -- lowers to base and never raises a cap set lower.
  v_base := least(v_base, v_cur);

  -- PAUSED IS A REPORTABLE STATE: a paused campaign files a row and leaves the cap alone. The daily tick
  -- calls this only on open days, so the previous body's daily "campaign paused" warning (which, called
  -- every day of a founder's deliberate hold, would page him daily) is not carried over.
  if coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') <> 'true' then
    select count(*) into v_uncontacted from leads where invited_at is null and coalesce(btrim(email),'') <> '';
    insert into agent_runs(agent, status, counts, note, finished_at)
    values ('invite_ramp', 'ok', jsonb_build_object('paused', true, 'cap', v_cur, 'uncontacted_with_email', v_uncontacted),
            'PAUSED: invite_enabled is false; cap left at ' || v_cur || '.', now());
    return v_cur;
  end if;

  select count(*), max(invited_at) into v_sent_total, v_last_sent from leads where invited_at is not null and invited_at >= v_since and (v_since = '-infinity'::timestamptz or public.fn_invite_lane_sent(id)) and not coalesce(is_demo, false) and not public.fn_is_demo_email(email);
  -- THE 48 h HEALTH READ IS NOT LANE-SCOPED (review of #963): complaints and bounces reflect the list and the
  -- copy, not the domain, so switching the lane on must never hide yesterday's complaints from the pause.
  select h.sent, h.bounced, h.complained into v_s48, v_b48, v_c48
    from public.fn_invite_send_health(now() - interval '48 hours') h;
  v_br := v_b48::numeric / greatest(v_s48, 1);
  v_cr := v_c48::numeric / greatest(v_s48, 1);

  if v_c48 >= v_pause_n and v_cr >= v_pause_c then
    -- SPAM COMPLAINTS STOP THE CAMPAIGN. Gmail and Yahoo reject bulk senders above 0.3%; two people
    -- pressing "spam" inside 48 hours is not noise at this volume.
    update app_secrets set value = 'false' where key = 'invite_enabled';
    v_new := v_base; v_status := 'error';
    v_note := 'PAUSED ON COMPLAINTS: ' || v_c48 || ' spam complaint(s) on ' || v_s48 || ' invitation(s) in 48 h ('
              || round(v_cr * 100, 2) || '% >= ' || round(v_pause_c * 100, 2) || '%). invite_enabled set to false; cap reset to base '
              || v_base || '.';
    if not exists (select 1 from founder_alerts where event = 'invite_paused_complaints' and created_at > now() - interval '24 hours') then
      insert into founder_alerts(level, event, detail, channel)
      values ('crit', 'invite_paused_complaints', 'Supplier invites AUTO-PAUSED: ' || v_note || ' Read the complaints before resuming.', 'system');
    end if;
  elsif v_last_sent is null or v_last_sent < now() - interval '3 days' then
    -- A RESTART, NOT A STALL. After days of silence the domain is cold again, so it starts at the base.
    -- It is a stall only if the previous run was ALSO a restart and still nothing has been issued.
    -- A lane that has just been switched on has issued nothing yet, so it lands here: day 1 of its own ramp.
    v_restart := true; v_new := v_base;
    select coalesce((a.counts->>'restart')::boolean, false) into v_prev_restart
      from agent_runs a where a.agent = 'invite_ramp' and coalesce((a.counts->>'paused')::boolean, false) = false
     order by a.id desc limit 1;
    v_note := 'restart: nothing issued since ' || coalesce(to_char(v_last_sent at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z', 'ever')
              || case when v_since > '-infinity'::timestamptz
                      then ' on the invitation lane (switched on ' || to_char(v_since at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z)' else '' end
              || '; cap set to the base ' || v_base || '.';
    if coalesce(v_prev_restart, false) then
      v_status := 'error';
      v_note := 'STALLED: the previous run was already a restart and nothing has been issued since. ' || v_note;
      if not exists (select 1 from founder_alerts where event = 'invite_sender_stalled' and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level, event, detail, channel)
        values ('crit', 'invite_sender_stalled', 'Supplier invites: ' || v_note || ' invite_enabled is true, so the enqueuer or the outbox is failing.', 'system');
      end if;
    end if;
  elsif v_s48 >= v_back_n and (v_br >= v_back_b or v_c48 >= 1) then
    v_new := greatest(1, floor(v_cur * 0.5)::int);   -- ruling 1231 review: a back-off must reduce, so no floor at base
    v_note := 'back off: 48 h bounce ' || round(v_br * 100, 1) || '% (' || v_b48 || '/' || v_s48 || '), complaints ' || v_c48
              || '; cap ' || v_cur || '->' || v_new || '.';
    if v_new = v_cur then
      v_status := 'error';
      if not exists (select 1 from founder_alerts where event = 'invite_throttle_exhausted' and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level, event, detail, channel)
        values ('crit', 'invite_throttle_exhausted', 'Supplier invites: ' || v_note || ' The cap is already at its base; the hard brake pauses at '
                || round(coalesce((select nullif(value,'')::numeric from app_secrets where key = 'invite_max_bounce_rate'), 0.05) * 100, 1) || '%.', 'system');
      end if;
    end if;
  elsif v_br >= v_ok_b or v_cr >= v_ok_c then
    v_new := v_cur;
    v_note := 'hold: 48 h bounce ' || round(v_br * 100, 1) || '% (' || v_b48 || '/' || v_s48 || '), complaint ' || round(v_cr * 100, 2)
              || '% — growth needs bounce < ' || round(v_ok_b * 100, 1) || '% and complaint < ' || round(v_ok_c * 100, 2) || '%.';
  else
    -- GROW ON VOLUME ISSUED, ONCE PER SEND DAY. Weekends and holidays run no batch, so a calendar-based
    -- ladder would ratchet on days the domain sent nothing.
    select max((invited_at at time zone 'Asia/Dubai')::date) into v_last_day from leads where invited_at is not null and invited_at >= v_since and (v_since = '-infinity'::timestamptz or public.fn_invite_lane_sent(id)) and not coalesce(is_demo, false) and not public.fn_is_demo_email(email);
    select count(*) into v_last_day_sent from leads where (invited_at at time zone 'Asia/Dubai')::date = v_last_day and invited_at >= v_since and (v_since = '-infinity'::timestamptz or public.fn_invite_lane_sent(id)) and not coalesce(is_demo, false) and not public.fn_is_demo_email(email);
    select exists (select 1 from agent_runs a where a.agent = 'invite_ramp' and a.finished_at > v_last_sent
                     and (a.counts->>'new_cap')::int > (a.counts->>'old_cap')::int) into v_grew_since;
    if v_grew_since then
      v_new := v_cur; v_note := 'hold: already grew once since the last send day.';
    elsif v_last_day_sent < ceil(v_cur * v_used_pct) then
      v_new := v_cur; v_note := 'hold: the last send day (' || v_last_day || ') issued ' || v_last_day_sent || ' of a cap of ' || v_cur
                                || '; growth needs ' || round(v_used_pct * 100) || '%.';
    else
      v_new := least(v_ceiling, ceil(v_cur * v_growth)::int);
      v_note := 'healthy: 48 h bounce ' || round(v_br * 100, 1) || '% (' || v_b48 || '/' || v_s48 || '), complaints ' || v_c48
                || '; last send day issued ' || v_last_day_sent || '; cap ' || v_cur || '->' || v_new || '.';
    end if;
  end if;

  v_new := greatest(1, least(v_new, v_ceiling));     -- ruling 1231: the schedule only ever lowers the cap
  if v_new <> v_cur then
    update app_secrets set value = v_new::text where key = 'invite_daily_cap';
  end if;

  insert into agent_runs(agent, status, counts, note, finished_at)
  values ('invite_ramp', v_status,
          jsonb_build_object('old_cap', v_cur, 'new_cap', v_new, 'sent_total', v_sent_total, 'restart', v_restart,
                             'sent_48h', v_s48, 'bounced_48h', v_b48, 'complained_48h', v_c48,
                             'bounce_pct_48h', round(v_br * 100, 2), 'complaint_pct_48h', round(v_cr * 100, 3))
          || case when v_since > '-infinity'::timestamptz then jsonb_build_object('lane_since', v_since) else '{}'::jsonb end,
          v_note, now());
  if v_new < v_cur and not v_restart then
    insert into founder_alerts(level, event, detail, channel)
    values ('warn', 'invite_cap_throttled', 'Supplier-invite cap reduced ' || v_cur || '->' || v_new || ' — ' || v_note, 'system');
  end if;
  return v_new;
end
$function$;

CREATE OR REPLACE FUNCTION public.enqueue_supplier_invites(p_cap integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (now() at time zone 'UTC')::date;
  v_planned int; v_used int; v_remaining int; v_count int;
  v_inv_recent int; v_bounced_recent int; v_rate numeric; v_max_rate numeric; v_cap int;
  v_pause boolean := false; v_why text; v_go boolean; v_pool int;
  v_hol_name text; v_hol_action text; v_hol_end date;
  v_cfg jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_win_start timestamptz; v_win_end timestamptz;
  v_gate text; v_open text[];
begin
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

  -- THE UAE WEEKEND IS SATURDAY AND SUNDAY. A cold invitation queued then waits under Monday's pile.
  -- Self-clearing like the holiday hold: nothing is switched off, Monday simply runs.
  if extract(isodow from (now() at time zone 'Asia/Dubai')) in (6, 7) then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'weekend_hold', true),
            'Invites held: it is the UAE weekend in Dubai; the next weekday batch runs as normal.', now(), now());
    return 0;
  end if;

  v_go  := (coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') = 'true')
           and public.fn_supplier_outreach_golive();
  v_cap := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), 10);
  -- founder ruling 1231: never more than the dated founder cap, whatever invite_daily_cap holds.
  v_cap := least(v_cap, public.fn_invite_founder_cap((now() at time zone 'Asia/Dubai')::date));
  v_cap := public.fn_invite_restart_cap(v_cap);   -- a small first batch after a restart
  select count(*) into v_pool from leads l where public.fn_supplier_invite_eligible(l);
  v_planned := least(coalesce(p_cap, v_cap), v_cap, v_pool);
  insert into invite_schedule(day, planned, status, note)
  values (v_today, greatest(v_planned, 0),
          case when v_go then 'approved' else 'pending' end,
          'batch of ' || greatest(v_planned, 0) || ' from a pool of ' || v_pool || ' eligible never-invited lead(s), cap ' || v_cap
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

  -- PLACEMENT GATE, PER MAILBOX CLASS (27 Oct 2026, it_engineer; was the morning seed, retired by #1696). Recipients
  -- go only in a class whose latest GlockApps verdict meets public.invite_placement_bar (fn_invite_placement_open_providers);
  -- the others are skipped, not failed. No class open, no verdict, or a stale one: the whole batch is held.
  v_open := public.fn_invite_placement_open_providers((now() at time zone 'Asia/Dubai')::date);
  v_gate := public.fn_invite_placement_class_verdicts(now()) ->> 'strict';
  if cardinality(v_open) = 0 then
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; held: inbox placement ' || v_gate where day = v_today;
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'planned', v_planned, 'placement_gate', v_gate, 'held', true),
            'Invites held: the GlockApps inbox placement verdict answered ' || v_gate || ' for every mailbox class, so nothing was written to the outbox.', now(), now());
    return 0;
  end if;
  if v_gate <> 'pass' then
    update invite_schedule set note = coalesce(note,'') || '; placement ' || v_gate || ': invited only ' || array_to_string(v_open, ', ') where day = v_today;
  end if;

  -- THE SENDING WINDOW (22 Sep 2026). Invitations leave between the later of now and the window's start
  -- and the end of the Dubai working day, evenly spaced. Past the window nothing is queued: a cold
  -- invitation at night lands under the morning's pile, and tomorrow's batch runs as normal.
  v_win_start := greatest(now(), ((now() at time zone 'Asia/Dubai')::date
                   + make_interval(hours => coalesce((v_cfg->>'window_start_hour')::int, 9))) at time zone 'Asia/Dubai');
  v_win_end := ((now() at time zone 'Asia/Dubai')::date + make_interval(hours => coalesce((v_cfg->>'window_end_hour')::int, 17)))
               at time zone 'Asia/Dubai';
  if v_win_end < v_win_start + interval '30 minutes' then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'planned', v_planned, 'outside_window', true),
            'Invites held: the Dubai sending window closes at ' || to_char(v_win_end at time zone 'Asia/Dubai', 'HH24:MI')
            || '; the next weekday batch runs as normal.', now(), now());
    return 0;
  end if;

  v_max_rate := coalesce((select nullif(value,'')::numeric from app_secrets where key='invite_max_bounce_rate'), 0.08);
  -- 2 Nov 2026: real sends only. A restart never resets this window.
  select h.sent, h.bounced into v_inv_recent, v_bounced_recent
    from public.fn_invite_send_health(now() - interval '3 days') h;
  v_rate := round(v_bounced_recent::numeric / greatest(v_inv_recent,1), 3);

  if v_inv_recent >= 15 and v_rate > v_max_rate then
    v_pause := true;
    v_why := 'bounce rate '||(v_rate*100)||'% over 3 days ('||v_bounced_recent||'/'||v_inv_recent||') exceeds the '||(v_max_rate*100)||'% limit';
  end if;
  if not v_pause and v_bounced_recent >= greatest(5, ceil(v_inv_recent * v_max_rate)::int) then
    v_pause := true;
    v_why := v_bounced_recent||' hard bounces in 3 days against '||v_inv_recent||' sent. Regardless of rate, that is a list-quality problem';
  end if;

  if v_pause then
    update app_secrets set value='false' where key='invite_enabled';
    insert into public.invite_brake(source, why) values ('enqueue_supplier_invites', v_why) on conflict do nothing;
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; auto-paused: ' || v_why where day = v_today;
    if not exists (select 1 from founder_alerts where event='invite_paused_bounce' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values('crit','invite_paused_bounce','Supplier invites AUTO-PAUSED: '||v_why||'. The sales engineer may resume once, after a 3-day cooldown; a second breach stays paused and goes to the CEO seat.','system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('invite_paused_bounce', coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com'),'admin','email','Supplier invites paused - deliverability risk','Invites were auto-paused: '||v_why||'. The sales engineer may resume once, after a 3-day cooldown; a second breach stays paused and goes to the CEO seat.','queued');
    end if;
    return 0;
  end if;

  -- test-path rows (fixture addresses) are not invitations and must not spend the day's cap:
  -- measured in the rolled-back rehearsal, two test sends plus one real row cut a batch of 5 to 2.
  -- ONE daily cap for invitations and their nudges (review of #1007, 29 Sep 2026): a nudge queued today spends it too,
  -- as fn_sales_engineer_nudges_invited_suppliers already counts the invitations queued today against the same cap.
  select count(*) into v_used from notifications where type in ('supplier_invite', 'supplier_invite_nudge') and (created_at at time zone 'UTC')::date = v_today
     and not public.fn_is_demo_email(to_email);
  v_remaining := greatest(0, v_planned - v_used);
  if v_remaining <= 0 then return 0; end if;

  with c as (
    select c.*, row_number() over () as rn, count(*) over () as n
      from public.fn_supplier_invite_candidates(v_remaining, v_open) c
  ), ins as (
    insert into notifications(type, to_email, to_role, lead_id, subject, body, lang, status, created_at, not_before)
    select 'supplier_invite', c.to_email, 'supplier', c.lead_id, c.subject, c.body, c.lang, 'queued', now(),
           v_win_start + (c.rn - 1) * ((v_win_end - v_win_start) / greatest(c.n, 1))
      from c
    on conflict (lower(btrim(to_email))) where type = 'supplier_invite' do nothing
    returning lead_id
  )
  update leads set invite_status='queued', invited_at=now()
  where invite_status is null and id in (select lead_id from ins);
  get diagnostics v_count = row_count;
  -- invite_schedule.sent is written when the outbox sends (trg_invite_schedule_counts_a_real_send), never here at queue time
  insert into agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('supplier_invites', 'ok',
          jsonb_build_object('queued', v_count, 'planned', v_planned, 'pool', v_pool, 'cap', v_cap, 'held', false,
                             'window_ends', v_win_end, 'placement_gate', v_gate, 'open_providers', to_jsonb(v_open)),
          'Invites: ' || v_count || ' queued of ' || v_planned || ' planned (pool ' || v_pool || ', cap ' || v_cap
          || '), spread until ' || to_char(v_win_end at time zone 'Asia/Dubai', 'HH24:MI') || ' Dubai.', now(), now());
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_nudges_invited_suppliers(p_now timestamp with time zone DEFAULT now(), p_cap integer DEFAULT NULL::integer, p_include_fixtures boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_dxb timestamp := p_now at time zone 'Asia/Dubai';
  v_cfg jsonb := coalesce((select nullif(value, '')::jsonb from public.app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_hol text; v_cap int; v_used int; v_left int; v_queued int := 0; v_due int := 0; r record; v_link text;
  v_res jsonb; v_not_before timestamptz;
  v_gate text; v_open text[]; v_skipped int := 0; v_inv_recent int; v_bounced_recent int; v_max_rate numeric;
begin
  select c.event_name into v_hol from public.company_calendar c
   where c.kind = 'public_holiday' and v_dxb::date between c.starts_on and coalesce(c.ends_on, c.starts_on) limit 1;
  if v_hol is not null then return jsonb_build_object('held', 'holiday: ' || v_hol, 'queued', 0); end if;
  if extract(isodow from v_dxb) in (6, 7) then return jsonb_build_object('held', 'UAE weekend', 'queued', 0); end if;
  -- THE SENDING WINDOW (review of #1007, 29 Sep 2026). The duty that calls this runs at 00:01 UTC (04:01 Dubai),
  -- before the window opens, so a start-hour HOLD would block every nudge. Instead a nudge queued before the
  -- window leaves no earlier than window_start_hour (default 9) Dubai the same day: not_before, exactly as
  -- enqueue_supplier_invites spreads its batch from the window's start. After window_end_hour it is held.
  v_not_before := greatest(p_now, (v_dxb::date + make_interval(hours => coalesce((v_cfg->>'window_start_hour')::int, 9)))
                                  at time zone 'Asia/Dubai');
  if extract(hour from v_dxb) >= coalesce((v_cfg->>'window_end_hour')::int, 17) then
    return jsonb_build_object('held', 'after the Dubai sending window', 'queued', 0); end if;
  -- THE GO SWITCH governs every mode, the probe's fixture mode included (30 Sep 2026).
  if not (coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive()) then
    return jsonb_build_object('held', 'the supplier campaign is not open (invite_enabled / supplier_outreach_golive)', 'queued', 0,
                              'due', (select count(*) from public.fn_supplier_invite_nudges_due(p_now, p_include_fixtures)));
  end if;
  -- THE BATCH'S BRAKES, for real mail (a fixture address never leaves: send_outbox suppresses @example.invalid).
  if not p_include_fixtures then
    -- per mailbox class (27 Oct 2026): held only when no class passes; a failing class is skipped in the loop
    v_open := public.fn_invite_placement_open_providers(v_dxb::date, p_now);
    v_gate := public.fn_invite_placement_class_verdicts(p_now) ->> 'strict';
    if cardinality(v_open) = 0 then
      return jsonb_build_object('held', 'inbox placement ' || v_gate, 'queued', 0); end if;
    -- enqueue_supplier_invites' 3-day bounce brake, read only (the batch owns the auto-pause)
    select h.sent, h.bounced into v_inv_recent, v_bounced_recent
      from public.fn_invite_send_health(p_now - interval '3 days') h;
    v_max_rate := coalesce((select nullif(value, '')::numeric from public.app_secrets where key = 'invite_max_bounce_rate'), 0.08);
    if (v_inv_recent >= 15 and v_bounced_recent::numeric / greatest(v_inv_recent, 1) > v_max_rate)
       or v_bounced_recent >= greatest(5, ceil(v_inv_recent * v_max_rate)::int) then
      return jsonb_build_object('held', 'bounce brake: ' || v_bounced_recent || ' of ' || v_inv_recent || ' in 3 days', 'queued', 0); end if;
  end if;

  -- ONE daily cap for the domain: invitations and nudges queued this day, same class (real or fixture). The day is
  -- the UTC date, exactly as enqueue_supplier_invites counts it (review of #1007): on a Dubai-date basis the two
  -- would disagree between 00:00 and 04:00 Dubai and could each spend a full cap.
  v_cap := coalesce((select nullif(value, '')::int from public.app_secrets where key = 'invite_daily_cap'), 10);
  v_cap := public.fn_invite_restart_cap(least(v_cap, coalesce(p_cap, v_cap)));
  select count(*) into v_used from public.notifications n
   where n.type in ('supplier_invite', 'supplier_invite_nudge')
     and (n.created_at at time zone 'UTC')::date = (p_now at time zone 'UTC')::date
     and public.fn_is_demo_email(n.to_email) = p_include_fixtures;
  v_left := greatest(0, v_cap - v_used);

  for r in select d.*, l.company_name, l.claim_token from public.fn_supplier_invite_nudges_due(p_now, p_include_fixtures) d
             join public.leads l on l.id = d.lead_id loop
    v_due := v_due + 1;
    -- a recipient whose mailbox class did not pass the GlockApps verdict is skipped, not failed (27 Oct 2026)
    if not p_include_fixtures and public.fn_mail_provider_of_email(r.to_email) <> all(v_open) then
      v_skipped := v_skipped + 1; continue; end if;
    continue when v_queued >= v_left;
    -- ALWAYS ENGLISH (review, 29 Sep 2026; founder rule: suppliers are always English): one copy, and the link is
    -- the invitation's own: fn_supplier_invite_link (#1051) - /en/portal with the claim token and the invitation ref.
    -- A lead with no claim token (the function then answers null) gets the plain English portal.
    v_link := coalesce(public.fn_supplier_invite_link(
                         (select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), r.claim_token, r.lead_id),
                       coalesce((select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com')
                       || '/en/portal');
    v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_invite_nudge', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.to_email, 'to_role', 'supplier', 'lead_id', r.lead_id, 'lang', 'en', 'dedupe_key', r.dedupe_key,
      'subject', case when r.step = 3 then 'A last reminder: ' else '' end || 'your invitation to join QuotesDone as a supplier',
      -- #1070's greeting guard: an Arabic-script company name is not written into an English letter
      'body', coalesce('Dear ' || nullif(btrim(case when r.company_name ~ '[\u0600-\u06FF]' then '' else r.company_name end), '') || ',',
                       'Dear Sir or Madam,') || E'\n\n'
          || 'A reminder of our invitation to register your company as a supplier on QuotesDone. It is free and takes a few minutes.'
          || E'\n\n' || v_link
          || case when r.step = 3 then E'\n\nThis is the last reminder we will send about it.' else '' end
          || E'\n\nIf you would rather not receive these e-mails, reply to this one and we will remove your address.')));
    -- support's handler queues the row without a not_before (it takes only the words and the address), so the
    -- requester sets the window start on the row it was just given back (by id, whatever the outbox's status:
    -- a fixture address is 'suppressed' on insert, a real one 'queued')
    update public.notifications set not_before = v_not_before
     where id = (v_res->0->>'notification_id')::bigint and type = 'supplier_invite_nudge';
    v_queued := v_queued + 1;
  end loop;
  return jsonb_build_object('held', null, 'due', v_due, 'queued', v_queued, 'cap', v_cap, 'used_before', v_used,
                            'placement_gate', v_gate, 'open_providers', to_jsonb(v_open), 'skipped_provider', v_skipped);
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_supplier_invite_eligible(p leads)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(btrim(p.email), '') <> ''
     and p.invite_status is null
     and coalesce(p.source, '') <> 'self_registered'
     and coalesce(p.claimed, false) = false
     and coalesce(p.banned, false) = false
     and coalesce(p.permanently_closed, false) = false
     -- a fixture is never a supplier: the flag, the naming convention, and the reserved domains
     and coalesce(p.is_demo, false) = false
     and coalesce(p.company_name, '') !~* '^\s*zz\s*demo'
     and not public.fn_is_demo_email(p.email)
     -- screened and matched but undecided is not cleared; a confirmed ban is total
     and not exists (select 1 from public.sanctions_ban b where b.lead_id = p.id)
     and not exists (select 1 from public.supplier_screening_hit h
                      where h.lead_id = p.id and h.status in ('open', 'confirmed'))
     -- never twice, read from the outbox rather than from a status column
     and not exists (select 1 from public.notifications n
                      where n.type = 'supplier_invite' and lower(btrim(n.to_email)) = lower(btrim(p.email)))
     and coalesce((public.fn_email_sendable(p.email)->>'ok')::boolean, false)
     -- 2 Nov 2026 (ledger 1449): the sales engineer's stored verdict for THIS address (public.lead_email_check)
     and exists (select 1 from public.lead_email_check ec
                  where ec.lead_id = p.id and ec.verdict = 'verified' and ec.email_md5 = md5(lower(btrim(p.email))))
     -- 22 Sep 2026: a COLD invitation needs a measured MX. An A-record-only domain (361 leads), a lookup
     -- that errored (86) or a domain never asked is a bounce risk on a domain with no history to spend.
     and exists (select 1 from public.email_domain_mx m
                  where m.domain = split_part(lower(btrim(p.email)), '@', 2) and m.kind = 'mx')
     -- ... and never a mailbox whose reader is not the business (44 leads): a recruiter or a lawyer
     -- presses "spam", they do not register.
     and split_part(lower(btrim(p.email)), '@', 1) !~
         '^(careers?|jobs?|hr|recruit(ment|ing)?|cv|webmaster|hostmaster|mailer-daemon|privacy|legal|newsletters?|unsubscribe|donotreply)$'
     -- 24 Sep 2026 (marketing, ledger 993): never an address on a directory, marketplace, hosting, template or
     -- placeholder domain (public.email_platform_domain, exact domain equality, no word is read) -- the reader is not
     -- the company. The one exception is a platform that IS the lead: its own website host is that domain.
     and not exists (select 1 from public.email_platform_domain d
                      where d.domain = split_part(lower(btrim(p.email)), '@', 2)
                        and d.domain is distinct from lower(regexp_replace(regexp_replace(btrim(coalesce(nullif(btrim(p.website), ''), p.maps_website, '')),
                                                          '^[A-Za-z]+://', ''), '^www\.|[/:?#].*$', '', 'gi')))
$function$;

CREATE OR REPLACE FUNCTION public.fn_supplier_invite_eligible_ids()
 RETURNS SETOF bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- The small reference tables (sanctions 46 rows, screening hits, 37 suppressions, block patterns,
  -- 47 platform domains) are read ONCE into arrays: with the leads estimate at 1 row the planner
  -- chose nested loops and re-read each of them 19,444 times (EXPLAIN ANALYZE, 4.8 s). NULLs are
  -- filtered out of each array, because `x <> all(array[..., null])` is null and would drop every lead.
  select p.id
    from public.leads p
   where coalesce(btrim(p.email), '') <> ''
     and p.invite_status is null
     and coalesce(p.source, '') <> 'self_registered'
     and coalesce(p.claimed, false) = false
     and coalesce(p.banned, false) = false
     and coalesce(p.permanently_closed, false) = false
     and coalesce(p.is_demo, false) = false
     and coalesce(p.company_name, '') !~* '^\s*zz\s*demo'
     and not public.fn_is_demo_email(p.email)
     and p.id <> all (array(select b.lead_id from public.sanctions_ban b where b.lead_id is not null))
     and p.id <> all (array(select h.lead_id from public.supplier_screening_hit h
                             where h.lead_id is not null and h.status in ('open', 'confirmed')))
     and not exists (select 1 from public.notifications n
                      where n.type = 'supplier_invite' and lower(btrim(n.to_email)) = lower(btrim(p.email)))
     -- fn_email_sendable(p.email)->>'ok', clause for clause
     and lower(btrim(p.email)) ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$'
     and lower(btrim(p.email)) <> all (array(select lower(s.email) from public.email_suppressions s where s.email is not null))
     and not exists (select 1 from public.email_domain_mx m0
                      where m0.domain = split_part(lower(btrim(p.email)), '@', 2) and m0.has_mx = false
                        and m0.kind in ('nxdomain', 'no_records'))
     and not coalesce(lower(btrim(p.email)) ~ any (array(select bp.pattern from public.email_block_pattern bp
                                                         where bp.active and bp.pattern is not null)), false)
     -- 2 Nov 2026 (ledger 1449): the sales engineer's stored verdict for THIS address (public.lead_email_check)
     and exists (select 1 from public.lead_email_check ec
                  where ec.lead_id = p.id and ec.verdict = 'verified' and ec.email_md5 = md5(lower(btrim(p.email))))
     -- a measured MX
     and exists (select 1 from public.email_domain_mx m
                  where m.domain = split_part(lower(btrim(p.email)), '@', 2) and m.kind = 'mx')
     and split_part(lower(btrim(p.email)), '@', 1) !~
         '^(careers?|jobs?|hr|recruit(ment|ing)?|cv|webmaster|hostmaster|mailer-daemon|privacy|legal|newsletters?|unsubscribe|donotreply)$'
     and not (split_part(lower(btrim(p.email)), '@', 2) = any (array(select d.domain from public.email_platform_domain d where d.domain is not null))
              and split_part(lower(btrim(p.email)), '@', 2) is distinct from
                  lower(regexp_replace(regexp_replace(btrim(coalesce(nullif(btrim(p.website), ''), p.maps_website, '')),
                                       '^[A-Za-z]+://', ''), '^www\.|[/:?#].*$', '', 'gi')))
$function$;

CREATE OR REPLACE FUNCTION public.fn_supplier_invite_candidates(p_limit integer, p_providers text[])
 RETURNS TABLE(lead_id bigint, to_email text, company_name text, lang text, subject text, body text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_site text; v_target int;
  v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  select value into v_subj    from app_secrets where key = 'invite_subject';
  select value into v_body    from app_secrets where key = 'invite_body';
  -- 27 Oct 2026: the founder's invitation carries no link ("safer to not send links"); a supplier registers at
  -- quotesdone.com or replies. Only an EMPTY template is refused now. A template that still has {{link}} is filled.
  if btrim(coalesce(v_body, '')) = '' then
    raise exception 'app_secrets.invite_body is empty: no invitation is built from nothing';
  end if;
  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_category'),
                       (select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 10);

  -- MATERIALIZED, 4 Aug 2026, and it is load-bearing (see enqueue_supplier_invites' history): both
  -- CTEs are read from a correlated subquery and would otherwise be recomputed per candidate.
  return query
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
  -- ONE COMPANY, ONE INVITATION (24 Sep 2026, marketing). A company is its email domain, unless the domain is
  -- a shared mailbox provider (gmail, emirates.net.ae ...: measured as a domain carrying 3+ different company
  -- names), where it is the address itself; and, independently, its normalised company name.
  shared as materialized (
    select split_part(lower(btrim(l.email)), '@', 2) as dom from leads l where coalesce(btrim(l.email), '') <> ''
    group by 1 having count(distinct lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g'))) >= 3
  ),
  keyed as materialized (
    select l.id,
           case when s.dom is null then split_part(lower(btrim(l.email)), '@', 2) else lower(btrim(l.email)) end as dkey,
           nullif(lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g')), '') as nkey,
           (l.invite_status is not null or l.invited_at is not null or coalesce(l.claimed, false)) as touched
    from leads l left join shared s on s.dom = split_part(lower(btrim(l.email)), '@', 2)
    where coalesce(btrim(l.email), '') <> ''
  ),
  touched_d as materialized (select distinct dkey from keyed where touched),
  touched_n as materialized (select distinct nkey from keyed where touched and nkey is not null),
  -- instr 1013: marketing's ranking of the trades below ten suppliers (the ranking orders the queue; since 27 Oct 2026
  -- every row stores the one approved text, not a per-trade variant)
  plans as materialized (select p.trade, p.emirate, p.rank from public.marketing_gap_recruitment_plan p),
  -- 29 Sep 2026 (ledger 1018): the trades and areas of the open, real stalled-request rescues (public.stalled_inquiry_rescue).
  -- A fixture rescue never moves the real queue.
  rescue as materialized (select x.trades, x.emirate from public.stalled_inquiry_rescue x where x.cleared_at is null and not x.fixture and cardinality(x.trades) > 0),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified,
           l.invite_trades, l.emirate, k.dkey, k.nkey, ec.mailbox,
           -- ALWAYS ENGLISH (24 Sep 2026, ledger 993 item 4; #1065): suppliers are always written in English.
           'en'::text as lang
    from leads l join keyed k on k.id = l.id left join public.lead_email_check ec on ec.lead_id = l.id
    where l.id in (select e.id from public.fn_supplier_invite_eligible_ids() e(id))   -- the set, read once (see header)
      -- 27 Oct 2026 (it_engineer): only recipients whose mailbox class passed the GlockApps verdict; null = every class
      and (p_providers is null or public.fn_mail_provider_of_email(l.email) = any(p_providers))
      -- a company already invited (bounced, unsubscribed or registered included) is not invited again at another address
      and not exists (select 1 from touched_d t where t.dkey = k.dkey)
      and (k.nkey is null or not exists (select 1 from touched_n t where t.nkey = k.nkey))
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain, c.lang, c.dkey, c.nkey,
      -- 29 Sep 2026 (ledger 1018): ahead of every tier below, a lead in the trade and area of a stalled request a customer waits on.
      -- 23 Sep 2026: a lead in a trade the sales engineer marked for recruitment (supply_gap 'recruit') goes first;
      -- 29 Sep 2026 (instr 1013): then a lead in any trade marketing planned, by the plan's rank.
      case when exists (select 1 from rescue x where x.trades && coalesce(c.invite_trades, '{}'::text[])
                          and (x.emirate is null or x.emirate = 'UAE' or x.emirate = c.emirate)) then -1
           when exists (select 1 from public.supply_gap g where g.status = 'recruit' and g.trade = any(coalesce(c.invite_trades, '{}'::text[]))
                          and (g.emirate = 'UAE' or g.emirate = c.emirate)) then 0
           when pl.rank is not null then 1 else 2 end as target_rank,
      coalesce(pl.rank, 2147483647) as plan_rank,
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      -- THE LIKELIEST MAILBOX FIRST (2 Nov 2026, ledger 1449). Measured on the 52 real sends: proven 'verified' 1 bounce of 22,
      -- proven 'true' 1 of 9, unproven role address 0 of 2, unproven named address 5 of 16. So an unproven info@ goes before
      -- an unproven named address (this used to be the other way round), and free mail last. ponytail: small sample, re-read at 200.
      case when c.email_verified in ('verified','true') then 0 when c.mailbox = 'free' then 3 when c.mailbox = 'role' then 1 else 2 end as mailbox_rank
    from cand c
    left join lateral (select p.rank from plans p
                        where p.trade = any(coalesce(c.invite_trades, '{}'::text[])) and (p.emirate = 'UAE' or p.emirate = c.emirate)
                        order by p.rank limit 1) pl on true
  ),
  elig as (
    select r.id, r.email, r.company_name, r.claim_token, r.lang from (
      select p.*,
        case when p.pdomain='~none' then 1 else 0 end as is_none,
        row_number() over (partition by p.pdomain order by p.mailbox_rank, p.id) as rk,
        row_number() over (partition by coalesce(p.email_domain, split_part(p.email,'@',2)) order by p.mailbox_rank, p.id) as domain_rk,
        -- the best contact per company, by mailbox_rank. ponytail: a lead that wins one key and loses the other waits a day.
        row_number() over (partition by p.dkey order by p.mailbox_rank, p.id) as company_rk,
        row_number() over (partition by coalesce(p.nkey, p.email) order by p.mailbox_rank, p.id) as name_rk
      from prio p
    ) r
    where r.domain_rk <= 5 and r.company_rk = 1 and r.name_rk = 1
    order by r.target_rank, r.plan_rank, r.mailbox_rank, r.is_none, r.rk, r.pdomain
    limit greatest(coalesce(p_limit, 0), 0)
  )
  select e.id, btrim(e.email), e.company_name, e.lang, v_subj,
         -- an Arabic-script company name is not written into an English letter (the 29 Sep probe found 11 of 200);
         -- with no usable name the greeting is the neutral "Hello," the Microsoft 365 lane also sends
         -- (a template that still carries {{link}} is filled as before; the approved one has none)
         replace(replace(case when n.nm = '' then replace(v_body, 'Hi {{company}} team,', 'Hello,') else v_body end,
                         '{{company}}', case when n.nm = '' then 'there' else n.nm end),
                 '{{link}}', public.fn_supplier_invite_link(v_site, e.claim_token, e.id))
  from elig e
  cross join lateral (select coalesce(nullif(btrim(case when e.company_name ~ '[؀-ۿ]' then '' else e.company_name end), ''), '') as nm) n;
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_outreach_tick(p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_now_dxb timestamp := now() at time zone 'Asia/Dubai';
  v_go boolean; v_weekend boolean; v_invited int; r record; s jsonb; v_cap int;
  v_due int := 0; v_sent int := 0; v_failed jsonb := '[]'::jsonb; v_clock jsonb; v_out jsonb; v_why text;
  v_cfg jsonb := coalesce((select nullif(value, '')::jsonb from public.app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_gate text; v_daily_done boolean; v_batch_done boolean; v_batch_why text; v_batch_wait boolean := false;
begin
  select exists (select 1 from public.agent_runs a
                  where a.agent = 'sales_engineer' and a.counts->>'job' = 'supplier_outreach'
                    and a.started_at > now() - interval '1 day'
                    and (a.started_at at time zone 'Asia/Dubai')::date = v_now_dxb::date),
         exists (select 1 from public.agent_runs a
                  where a.agent = 'sales_engineer'
                    and ((a.counts->>'job' = 'supplier_outreach' and coalesce(a.counts->>'batch_waiting', 'false') <> 'true')
                         or a.counts->>'job' = 'supplier_outreach_batch')
                    and a.started_at > now() - interval '1 day'
                    and (a.started_at at time zone 'Asia/Dubai')::date = v_now_dxb::date)
    into v_daily_done, v_batch_done;
  if not p_force then
    if extract(hour from v_now_dxb) < 9 then return jsonb_build_object('due', false, 'reason', 'before 09:00 Dubai'); end if;
    if v_daily_done and v_batch_done then
      return jsonb_build_object('due', false, 'reason', 'already ran this Dubai day');
    end if;
  end if;

  v_go := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive();
  v_weekend := extract(isodow from v_now_dxb) in (6, 7);
  v_why := case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
                when not v_go then 'invite_enabled is false'
                when v_weekend then 'it is the UAE weekend' end;

  -- 1. THE BATCH, behind the PLACEMENT GATE (24 Sep 2026, it_engineer). On an open day it goes only after that
  --    morning's seed landed in the Inbox of both seed mailboxes; while the check can still finish it waits (the
  --    next beat asks again); any other answer holds it (fail closed). enqueue_supplier_invites asks the same gate.
  if p_force or not v_batch_done then
    v_batch_why := v_why;
    if v_why is null then
      -- 27 Oct 2026: the GlockApps verdict, per mailbox class. The batch is held only when no class passes;
      -- enqueue_supplier_invites invites the passing classes and skips the rest. It never answers 'wait'.
      if cardinality(public.fn_invite_placement_open_providers(v_now_dxb::date)) = 0 then
        v_batch_why := 'the GlockApps inbox placement verdict cleared no mailbox class ('
                       || (public.fn_invite_placement_class_verdicts(now()) ->> 'strict') || ')';
      end if;
      v_gate := public.fn_invite_placement_class_verdicts(now()) ->> 'strict';
    end if;
    if not v_batch_wait then
      -- THE WARM-UP (22 Sep 2026). fn_invite_ramp sets today's invite_daily_cap from the last 48 h of bounces and
      -- complaints. Open days only: a held day sends nothing, so it must not move the cap.
      if v_batch_why is null then v_cap := public.fn_invite_ramp(); end if;
      -- enqueue_supplier_invites holds itself (gates, weekend, holiday, bounce brake, cap, placement).
      v_invited := public.enqueue_supplier_invites(null);
    end if;
  end if;

  -- A later beat of the same day: the daily work is done, only the batch was owed.
  if v_daily_done and not p_force then
    if v_batch_wait then
      return jsonb_build_object('due', false, 'reason', 'the batch waits for the morning inbox placement check');
    end if;
    v_out := jsonb_build_object('job', 'supplier_outreach_batch', 'dubai_day', v_now_dxb::date, 'held', v_batch_why is not null,
      'held_because', v_batch_why, 'placement_gate', v_gate, 'invites', jsonb_build_object('queued', v_invited, 'cap', v_cap));
    insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
    values ('sales_engineer', 'ok', now(), now(), v_out,
            case when v_batch_why is not null
                 then 'Supplier invitation batch HELD (' || v_batch_why || '): ' || coalesce(v_invited, 0) || ' queued.'
                 else 'Supplier invitation batch: ' || coalesce(v_invited, 0) || ' invitation(s) queued at a cap of ' || coalesce(v_cap::text, '?') || '.' end);
    return v_out;
  end if;

  -- 2. Reminders: always counted; written only on an open weekday (the campaign gates, not the placement gate).
  for r in select * from public.fn_supplier_registration_reminders_due() loop
    v_due := v_due + 1;
    -- 2 Nov 2026 (ledger 1449): a pause holds cold mail. A supplier who already started still hears from us, on a weekday inside
    -- the sending window, unless a complaint stopped the campaign (fn_supplier_reminder_is_open).
    if v_why is not null and (v_weekend or not public.fn_supplier_reminder_is_open(r.stage)
         or extract(hour from v_now_dxb) >= coalesce((v_cfg->>'window_end_hour')::int, 17)) then continue; end if;
    s := public.fn_sales_engineer_sends_registration_reminder(r.lead_id, r.stage, r.step, r.last_activity);
    if coalesce((s->>'ok')::boolean, false) then v_sent := v_sent + 1;
      if v_why is not null then
        update public.notifications set not_before = greatest(now(), (v_now_dxb::date + make_interval(hours => coalesce((v_cfg->>'window_start_hour')::int, 9))) at time zone 'Asia/Dubai')
         where id = (s->'delivery'->>'notification_id')::bigint and type = 'supplier_registration_reminder';
      end if;
    else v_failed := v_failed || jsonb_build_array(jsonb_build_object('lead_id', r.lead_id, 'reason', s->>'reason'));
    end if;
  end loop;

  -- 3. The 24-hour clock: internal, so not held by the campaign gates.
  v_clock := public.fn_sales_engineer_raises_undecided_submissions(false);

  v_out := jsonb_build_object('job', 'supplier_outreach', 'dubai_day', v_now_dxb::date, 'held', v_why is not null, 'held_because', v_why,
    'placement_gate', v_gate, 'batch_waiting', v_batch_wait, 'batch_held_because', v_batch_why,
    'invites', jsonb_build_object('queued', coalesce(v_invited, 0), 'cap', v_cap),
    'reminders', jsonb_build_object('due', v_due, 'sent', v_sent, 'failed', v_failed),
    'submissions', v_clock);
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('sales_engineer', case when jsonb_array_length(v_failed) > 0 then 'warn' else 'ok' end, now(), now(), v_out,
          case when v_why is not null
               then 'Supplier outreach HELD (' || v_why || '): ' || coalesce(v_invited, 0) || ' invitation(s) queued, ' || v_due
                    || ' reminder(s) due, ' || v_sent || ' written to suppliers who already started; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.'
               else 'Supplier outreach: '
                    || case when v_batch_wait then 'the invitation batch waits for the morning inbox placement check'
                            when v_batch_why is not null then 'the invitation batch was HELD (' || v_batch_why || ')'
                            else coalesce(v_invited, 0) || ' invitation(s) queued at a cap of ' || coalesce(v_cap::text, '?') end
                    || ', ' || v_sent || ' of ' || v_due
                    || ' reminder(s) sent; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.' end);
  return v_out;
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_sends_registration_reminder(p_lead_id bigint, p_stage text, p_step integer, p_last_activity timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare l public.leads; v_to text; v_fixture boolean; v_go boolean; m jsonb; v_key text; v_out jsonb;
begin
  select * into l from public.leads where id = p_lead_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'lead_not_found'); end if;
  v_to := lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email)));
  v_fixture := public.fn_is_demo_email(v_to);
  v_go := public.fn_supplier_reminder_is_open(p_stage);
  if not v_fixture and not v_go then
    return jsonb_build_object('ok', false, 'held', true, 'reason', 'the supplier campaign is not open (invite_enabled / supplier_outreach_golive)');
  end if;
  if not v_fixture and not public.fn_supplier_outreach_reachable(l, v_to) then
    return jsonb_build_object('ok', false, 'reason', 'not reachable: fixture, banned, screened, closed, bounced, suppressed or unsendable');
  end if;
  m := public.fn_supplier_registration_reminder_compose(l, p_stage, p_step);
  v_key := 'supplier_registration_reminder:' || l.id || ':' || extract(epoch from p_last_activity)::bigint || ':' || p_step;
  v_out := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
    'type', 'supplier_registration_reminder', 'requested_by', 'sales_engineer', 'channel', 'email',
    'to_email', v_to, 'to_role', 'supplier', 'lead_id', l.id, 'lang', m->>'lang',
    'subject', m->>'subject', 'body', m->>'body', 'dedupe_key', v_key)));
  return jsonb_build_object('ok', true, 'lead_id', l.id, 'stage', p_stage, 'step', p_step, 'lang', m->>'lang', 'fixture', v_fixture,
                            'delivery', v_out->0);
end
$function$;


-- 3. THE COUNT OF WHAT WAS SENT.
create or replace function public.trg_invite_schedule_counts_a_real_send()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if public.fn_is_demo_email(new.to_email) then return null; end if;
  insert into public.invite_schedule(day, planned, sent, status, note)
  values ((new.sent_at at time zone 'UTC')::date, 0, 1, 'approved', 'sent from an earlier day''s queue')
  on conflict (day) do update set sent = public.invite_schedule.sent + 1;
  return null;
end $fn$;
revoke execute on function public.trg_invite_schedule_counts_a_real_send() from public, anon, authenticated;
drop trigger if exists z81_invite_schedule_counts_a_real_send on public.notifications;
create trigger z81_invite_schedule_counts_a_real_send after update of sent_at on public.notifications
  for each row when (new.type = 'supplier_invite' and new.sent_at is not null and old.sent_at is null)
  execute function public.trg_invite_schedule_counts_a_real_send();

-- The days the outbox can speak for are corrected from it. Earlier days are left: their outbox rows may be gone.
with real as (
  select (n.sent_at at time zone 'UTC')::date as day, count(*)::int as sent
    from public.notifications n
   where n.type = 'supplier_invite' and n.sent_at is not null and not public.fn_is_demo_email(n.to_email)
   group by 1
), ins as (
  insert into public.invite_schedule(day, planned, sent, status, note)
  select r.day, 0, r.sent, 'approved', 'sent from an earlier day''s queue' from real r
  on conflict (day) do update set sent = excluded.sent
)
update public.invite_schedule s set sent = 0
 where s.day >= (select min(day) from real) and s.day not in (select day from real);

create or replace view public.v_invite_deliverability_daily as
  select (n.sent_at at time zone 'Asia/Dubai')::date as dubai_day,
         count(*) as sent,
         count(*) filter (where l.invite_status = 'bounced') as bounced,
         count(*) filter (where l.invite_status = 'complained') as complained,
         round((count(*) filter (where l.invite_status = 'bounced'))::numeric / count(*)::numeric, 4) as bounce_rate,
         round((count(*) filter (where l.invite_status = 'complained'))::numeric / count(*)::numeric, 4) as complaint_rate
    from public.notifications n
    join public.leads l on l.id = n.lead_id
   where n.type = 'supplier_invite' and n.sent_at is not null
     and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(n.to_email)
   group by 1;

-- 1. THE CHECK'S DOORS.
create or replace function public.fn_sales_engineer_email_check_batch(p_limit integer default 200)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('lead_id', x.id, 'email', x.email, 'email_verified', x.email_verified, 'mx_kind', x.kind)), '[]'::jsonb)
    from (
      select l.id, btrim(l.email) as email, l.email_verified, m.kind
        from public.leads l
        left join public.lead_email_check c on c.lead_id = l.id
        -- a cached answer younger than the recheck; a cached failure is asked again
        left join public.email_domain_mx m on m.domain = split_part(lower(btrim(l.email)), '@', 2)
                                          and m.checked_at > now() - interval '30 days' and m.kind <> 'error'
       where coalesce(btrim(l.email), '') <> ''
         and coalesce(l.invite_status, 'queued') = 'queued'
         and coalesce(l.source, '') <> 'self_registered'
         and not coalesce(l.claimed, false) and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)
         and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(l.email)
         and (c.lead_id is null
              or c.email_md5 <> md5(lower(btrim(l.email)))
              or c.checked_at < now() - interval '30 days'
              or (c.verdict = 'retry' and c.checked_at < now() - interval '1 hour'))
       -- an invitation already waiting in the outbox first, then never-checked, then the oldest verdict
       order by (l.invite_status = 'queued') desc nulls last, (c.lead_id is null) desc, c.checked_at nulls first, l.id
       limit greatest(coalesce(p_limit, 0), 0)
    ) x
$fn$;
revoke execute on function public.fn_sales_engineer_email_check_batch(integer) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_email_check_batch(integer) to service_role;

create or replace function public.fn_sales_engineer_records_email_checks(p_checks jsonb, p_domains jsonb default '[]'::jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_saved int; v_cancelled int;
begin
  -- a failed lookup never overwrites a real answer
  insert into public.email_domain_mx (domain, has_mx, kind, hosts, checked_at)
  select lower(d->>'domain'), d->>'kind' in ('mx', 'a_implicit', 'error'), d->>'kind',
         nullif(array(select jsonb_array_elements_text(coalesce(d->'hosts', '[]'::jsonb))), '{}'::text[]), now()
    from jsonb_array_elements(coalesce(p_domains, '[]'::jsonb)) d
  on conflict (domain) do update
     set has_mx = excluded.has_mx, kind = excluded.kind, hosts = excluded.hosts, checked_at = excluded.checked_at
   where excluded.kind <> 'error';

  insert into public.lead_email_check (lead_id, email_md5, verdict, reason, mailbox, mx_kind, checked_at)
  select (c->>'lead_id')::bigint, md5(lower(btrim(c->>'email'))), c->>'verdict', c->>'reason', c->>'mailbox', c->>'mx_kind', now()
    from jsonb_array_elements(coalesce(p_checks, '[]'::jsonb)) c
    join public.leads l on l.id = (c->>'lead_id')::bigint
  on conflict (lead_id) do update
     set email_md5 = excluded.email_md5, verdict = excluded.verdict, reason = excluded.reason,
         mailbox = excluded.mailbox, mx_kind = excluded.mx_kind, checked_at = excluded.checked_at;
  get diagnostics v_saved = row_count;

  -- an invitation already waiting for an address that has now failed never leaves
  update public.notifications n set status = 'cancelled'
    from public.lead_email_check c
   where n.type = 'supplier_invite' and n.status = 'queued' and n.lead_id = c.lead_id and c.verdict = 'rejected'
     and c.lead_id in (select (x->>'lead_id')::bigint from jsonb_array_elements(coalesce(p_checks, '[]'::jsonb)) x);
  get diagnostics v_cancelled = row_count;
  return jsonb_build_object('saved', v_saved, 'cancelled_queued', v_cancelled);
end $fn$;
revoke execute on function public.fn_sales_engineer_records_email_checks(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_records_email_checks(jsonb, jsonb) to service_role;

create or replace function public.fn_sales_engineer_lead_email_check()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_ref text; v_key text; v_cred text; v_due jsonb;
begin
  v_due := public.fn_sales_engineer_email_check_batch(1);   -- nothing due, no edge call
  if jsonb_array_length(v_due) = 0 then return jsonb_build_object('due', false); end if;
  select value into v_ref from public.app_secrets where key = 'project_ref';
  v_key := public.fn_gateway_client_key();
  select value into v_cred from public.app_secrets where key = 'cred_fn_sales_engineer';
  if v_ref is null or v_key is null or v_cred is null then
    raise exception 'fn_sales_engineer_lead_email_check: project_ref, the gateway key or cred_fn_sales_engineer is missing from app_secrets';
  end if;
  return jsonb_build_object('due', true, 'request', net.http_post(
    url := 'https://' || v_ref || '.supabase.co/functions/v1/sales_engineer',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key, 'apikey', v_key),
    body := jsonb_build_object('__secret', v_cred, 'action', 'lead_email_check'), timeout_milliseconds := 60000));
end $fn$;
revoke execute on function public.fn_sales_engineer_lead_email_check() from public, anon, authenticated;

-- 2. THE RESTART.
create or replace function public.fn_sales_engineer_restarts_invites_after_a_brake()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  b public.invite_brake; v_on boolean; v_suppressed int; v_batch int; v_sent int; v_bounced int; v_complaints int; v_max numeric; v_since timestamptz;
begin
  v_max := coalesce((select nullif(value, '')::numeric from public.app_secrets where key = 'invite_max_bounce_rate'), 0.08);
  select * into b from public.invite_brake where resumed_at is null order by id desc limit 1;
  if not found then
    -- A campaign somebody else stopped is not on probation.
    if not coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false) then
      return jsonb_build_object('open_brake', false);
    end if;
    -- PROBATION: for 30 days after a restart the batches sent SINCE the last resume answer for it, the seat's or a deliberate one
    -- (the CEO's after a second breach), so a resume is never charged with the bounces that came before it. The 3-day brake needs 15 sends or 5 bounces,
    -- which a batch of 10 cannot reach, so the limit is read here on those sends alone. Over it is the second breach.
    select max(x.resumed_at) into v_since from public.invite_brake x where x.resumed_at > now() - interval '30 days'
       and exists (select 1 from public.invite_brake y where y.restarted_by_seat and y.resumed_at > now() - interval '30 days');
    if v_since is null then return jsonb_build_object('open_brake', false); end if;
    select h.sent, h.bounced into v_sent, v_bounced from public.fn_invite_send_health(v_since) h;
    if v_bounced::numeric / greatest(v_sent, 1) <= v_max then
      return jsonb_build_object('open_brake', false, 'probation', true, 'sent', v_sent, 'bounced', v_bounced);
    end if;
    update public.app_secrets set value = 'false' where key = 'invite_enabled';
    update public.notifications set status = 'cancelled' where type = 'supplier_invite' and status = 'queued';
    insert into public.invite_brake(source, why)
    values ('invite_restart_probation', v_bounced || ' bounce(s) on ' || v_sent || ' invitation(s) sent since the restart')
    returning * into b;
  end if;
  v_on :=coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false);
  if v_on then
    update public.invite_brake set resumed_at = now(), resume_note = 'invite_enabled was already back on: not this seat''s restart' where id = b.id;
    return jsonb_build_object('open_brake', true, 'closed', 'already on');
  end if;

  -- The bounced addresses first: every real bounce is suppressed, whatever else holds the restart.
  insert into public.email_suppressions (email, reason, source)
  select distinct lower(btrim(l.email)), 'hard_bounce:permanent', 'sales_engineer_invite_restart'
    from public.notifications n join public.leads l on l.id = n.lead_id
   where n.type = 'supplier_invite' and n.sent_at is not null and l.invite_status = 'bounced'
     and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(l.email)
  on conflict (email) do nothing;
  get diagnostics v_suppressed = row_count;

  -- Not this seat's to lift: the founder's go, a complaint (a person pressed spam; read it, do not resend), another seat's pause.
  if not public.fn_supplier_outreach_golive() then
    return jsonb_build_object('open_brake', true, 'held', 'supplier_outreach_golive is false', 'suppressed', v_suppressed);
  end if;
  select h.sent, h.bounced, h.complained into v_sent, v_bounced, v_complaints from public.fn_invite_send_health(now() - interval '3 days') h;
  if v_complaints > 0 then
    return jsonb_build_object('open_brake', true, 'held', 'a complaint in the last 3 days', 'suppressed', v_suppressed);
  end if;
  if exists (select 1 from public.it_watch_finding f
              where f.detector_key = 'deliverability:supplier_invite' and f.status = 'open' and f.state = 'paused'
                and f.evidence->>'paused_by' <> 'invite_same_day_brake') then
    return jsonb_build_object('open_brake', true, 'held', 'another seat''s pause is open', 'suppressed', v_suppressed);
  end if;

  -- A SECOND BREACH inside 30 days of the seat's restart stays paused, and the CEO seat owns it.
  if exists (select 1 from public.invite_brake x where x.id <> b.id and x.restarted_by_seat and x.resumed_at > b.fired_at - interval '30 days') then
    if b.ceo_task_opened_at is null then
      perform public.fn_ceo_task_open('Supplier invitations stopped twice on bounces in 30 days',
        'The bounce brake fired again after the sales engineer''s restart: ' || b.why || '. Automatic restart is off for this breach. '
        || 'A free DNS check cannot see a missing mailbox on a live domain. Decide the list and the cap; invite_enabled stays false until then.');
      update public.invite_brake set ceo_task_opened_at = now() where id = b.id;
    end if;
    return jsonb_build_object('open_brake', true, 'held', 'second breach: the CEO seat decides', 'suppressed', v_suppressed);
  end if;

  -- THE COOLDOWN, and the window the brake itself reads. Neither is reset, so a restart cannot erase its own breach.
  if now() < b.fired_at + interval '3 days' then
    return jsonb_build_object('open_brake', true, 'held', 'cooldown', 'until', b.fired_at + interval '3 days', 'suppressed', v_suppressed);
  end if;
  if (v_sent >= 15 and v_bounced::numeric / greatest(v_sent, 1) > v_max) or v_bounced >= greatest(5, ceil(v_sent * v_max)::int) then
    return jsonb_build_object('open_brake', true, 'held', 'the 3-day window is still over the limit', 'sent', v_sent, 'bounced', v_bounced, 'suppressed', v_suppressed);
  end if;

  -- Somebody must be there to send to; candidates come only through the verdict gate, so this is a count, not a second check.
  select count(*) into v_batch from public.fn_supplier_invite_candidates(10, null::text[]) c;
  if v_batch = 0 then
    return jsonb_build_object('open_brake', true, 'held', 'no verified lead to send to yet', 'suppressed', v_suppressed);
  end if;

  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  update public.invite_brake set resumed_at = now(), restarted_by_seat = true,
         resume_note = 'bounced addresses suppressed (' || v_suppressed || ' new); first batch of at most ' || v_batch where id = b.id;
  update public.it_watch_finding set status = 'resolved', resolved_at = now()
   where detector_key = 'deliverability:supplier_invite' and status = 'open';
  insert into public.agent_runs(agent, status, counts, note, finished_at)
  values ('sales_engineer', 'ok', jsonb_build_object('action', 'invite_restart', 'brake', b.id, 'batch', v_batch, 'suppressed', v_suppressed),
          'Invitations resumed after the bounce brake of ' || to_char(b.fired_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z: ' || b.why, now());
  return jsonb_build_object('resumed', true, 'batch', v_batch, 'suppressed', v_suppressed);
end $fn$;
revoke execute on function public.fn_sales_engineer_restarts_invites_after_a_brake() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.lead_email_check', 'sales_engineer', interval '5 minutes', 'fn_sales_engineer_lead_email_check',
   'Checks a batch of leads before they can be invited: syntax, typo domains, local-part rules and DNS; stores a verdict per lead.',
   'scripts/sql/an_invitation_goes_only_to_a_checked_mailbox_and_a_bounce_brake_restarts_itself.sql'),
  ('sales_engineer.invite_restart', 'sales_engineer', interval '5 minutes', 'fn_sales_engineer_restarts_invites_after_a_brake',
   'After a bounce brake: suppresses the bounced addresses; resumes at most once in 30 days after a 3-day cooldown; a second breach goes to the CEO seat.',
   'scripts/sql/an_invitation_goes_only_to_a_checked_mailbox_and_a_bounce_brake_restarts_itself.sql')
on conflict (duty) do nothing;
