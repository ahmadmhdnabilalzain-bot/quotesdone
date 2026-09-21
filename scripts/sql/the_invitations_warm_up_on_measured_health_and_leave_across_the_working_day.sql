-- customer_support, 22 Sep 2026. Founder instruction 633: "prepare it really well so our emails do not go
-- to spam or junk; they must land in the inbox ... Avoid this from the beginning."
--
-- MEASURED (22 Sep 2026, production, read-only):
--   * fn_invite_ramp HAS NO CALLER. pg_cron went on 7 Sep; its only mention in any routine body is the
--     description text in fn_founder_settings. fn_sales_engineer_supplier_outreach_tick (the daily caller
--     of enqueue_supplier_invites since 21 Sep) never calls it. So on the founder's "go" the domain would
--     send invite_daily_cap = 50 on day one and 50 every day after: no warm-up, and no throttle.
--   * Its last issue was 2026-08-15 (50 that day). Had it been wired as it stood, the first run after
--     "go" would have hit the "nothing issued for 3 days" branch and paged the founder CRITICAL that the
--     enqueuer is FAILING — on the day it started working.
--   * Complaints are invisible. resend_webhook wrote invite_status='bounced' for a spam complaint, and
--     nothing measured a complaint rate. Gmail/Yahoo require < 0.3% and advise < 0.1%.
--   * enqueue_supplier_invites queued the whole day's batch in one statement at the first heartbeat after
--     09:00 Dubai, and the outbox drains 20 per tick: a burst, not a working day of mail.
--   * Pool 17,926 eligible leads. Domain MX kind: mx 17,479, a_implicit (A record, no MX) 361, error 86.
--     44 are careers@/hr@/jobs@-style mailboxes (the wrong reader for a supplier invitation). Lifetime
--     bounce 10/171 = 5.8%, every bounce on a domain WITH an MX (a mailbox, not a domain, failure).
--
-- WHAT THIS CHANGES
--   1. app_secrets.invite_warmup — ONE jsonb holding every warm-up number. The cap itself stays
--      app_secrets.invite_daily_cap (what enqueue_supplier_invites already reads); the ramp moves it.
--   2. fn_invite_ramp: health over the last 48 h. Grow x1.5 only while bounce < 2% AND complaint < 0.1%,
--      only after a send day that used >= 80% of the cap, and at most once per send day. Hold when either
--      rate is over its line; halve (floor = base) when bounce >= 3.5% or any complaint on >= 20 sends;
--      PAUSE (invite_enabled=false, critical alert) on >= 2 complaints at >= 0.3%. A campaign resuming
--      after >3 days of silence restarts at the base cap (the domain is cold again) — a restart, not a
--      stall; a stall is two consecutive restarts with nothing issued between them.
--   3. fn_sales_engineer_supplier_outreach_tick calls fn_invite_ramp() before the batch, on open days only.
--   4. enqueue_supplier_invites gives every queued invitation a not_before spread evenly from now to the
--      end of the Dubai working window (invite_warmup.window_end_hour, 17:00), and holds when the window
--      has passed. notifications.not_before is new; send_outbox skips a row until it is due (channels.ts).
--   5. fn_supplier_invite_eligible: a cold invitation now needs a domain whose MX was measured
--      (email_domain_mx.kind = 'mx'), and never goes to a careers/hr/jobs/webmaster/legal-type mailbox.
--      447 + 44 leads leave the pool. fn_email_sendable (all mail) is NOT changed.
--   6. v_invite_deliverability_daily: sent / bounced / complained and the two rates per Dubai day, from
--      leads — the records the brakes read.
--
-- NOT CHANGED: invite_enabled / supplier_outreach_golive stay 'false' (the founder's go). The hard brake in
-- enqueue_supplier_invites (invite_max_bounce_rate 5% over 3 days) is unchanged and still pauses on its own.
-- The complaint status itself is written by resend_webhook (resend_webhook/invite_status.ts, same PR).
-- The invitation copy, subject and From name are the founder's and are not touched here.
--
-- Prevented by: scripts/sql/the_invitations_warm_up_on_measured_health_and_leave_across_the_working_day_probe.sql
-- (verdict row) and supabase/functions/send_outbox/channels.test.ts (the not_before filter).

-- 1. ONE place for the warm-up numbers --------------------------------------------------------------
insert into public.app_secrets (key, value)
values ('invite_warmup', jsonb_build_object(
          'base_cap', 30, 'ceiling_cap', 200, 'growth_factor', 1.5, 'grow_if_used_pct', 0.8,
          'grow_max_bounce_rate', 0.02, 'grow_max_complaint_rate', 0.001,
          'backoff_bounce_rate', 0.035, 'backoff_min_sends', 20,
          'pause_complaint_rate', 0.003, 'pause_min_complaints', 2,
          'window_start_hour', 9, 'window_end_hour', 17)::text)
on conflict (key) do nothing;

-- 6 (first: the ramp reads the same numbers). -----------------------------------------------------
create or replace view public.v_invite_deliverability_daily with (security_invoker = true) as
select (l.invited_at at time zone 'Asia/Dubai')::date as dubai_day,
       count(*)                                                   as sent,
       count(*) filter (where l.invite_status = 'bounced')        as bounced,
       count(*) filter (where l.invite_status = 'complained')     as complained,
       round(count(*) filter (where l.invite_status = 'bounced')::numeric / count(*), 4)    as bounce_rate,
       round(count(*) filter (where l.invite_status = 'complained')::numeric / count(*), 4) as complaint_rate
  from public.leads l
 where l.invited_at is not null
 group by 1;
revoke all on public.v_invite_deliverability_daily from public, anon, authenticated;
comment on view public.v_invite_deliverability_daily is
  'Supplier invitations per Dubai day with hard-bounce and spam-complaint counts and rates, from leads.invite_status (written by resend_webhook). The numbers fn_invite_ramp and enqueue_supplier_invites brake on.';

-- 2. The ramp --------------------------------------------------------------------------------------
create or replace function public.fn_invite_ramp()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  c jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_base int     := coalesce((c->>'base_cap')::int, 30);
  v_ceiling int  := coalesce((c->>'ceiling_cap')::int, 200);
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
begin
  v_cur := coalesce((select nullif(value,'')::int from app_secrets where key = 'invite_daily_cap'), v_base);

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

  select count(*), max(invited_at) into v_sent_total, v_last_sent from leads where invited_at is not null;
  select count(*),
         count(*) filter (where invite_status = 'bounced'),
         count(*) filter (where invite_status = 'complained')
    into v_s48, v_b48, v_c48
    from leads where invited_at > now() - interval '48 hours';
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
    v_restart := true; v_new := v_base;
    select coalesce((a.counts->>'restart')::boolean, false) into v_prev_restart
      from agent_runs a where a.agent = 'invite_ramp' and coalesce((a.counts->>'paused')::boolean, false) = false
     order by a.id desc limit 1;
    v_note := 'restart: nothing issued since ' || coalesce(to_char(v_last_sent at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z', 'ever')
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
    v_new := greatest(v_base, floor(v_cur * 0.5)::int);
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
    select max((invited_at at time zone 'Asia/Dubai')::date) into v_last_day from leads where invited_at is not null;
    select count(*) into v_last_day_sent from leads where (invited_at at time zone 'Asia/Dubai')::date = v_last_day;
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

  v_new := greatest(v_base, least(v_new, v_ceiling));
  if v_new <> v_cur then
    update app_secrets set value = v_new::text where key = 'invite_daily_cap';
  end if;

  insert into agent_runs(agent, status, counts, note, finished_at)
  values ('invite_ramp', v_status,
          jsonb_build_object('old_cap', v_cur, 'new_cap', v_new, 'sent_total', v_sent_total, 'restart', v_restart,
                             'sent_48h', v_s48, 'bounced_48h', v_b48, 'complained_48h', v_c48,
                             'bounce_pct_48h', round(v_br * 100, 2), 'complaint_pct_48h', round(v_cr * 100, 3)),
          v_note, now());
  if v_new < v_cur and not v_restart then
    insert into founder_alerts(level, event, detail, channel)
    values ('warn', 'invite_cap_throttled', 'Supplier-invite cap reduced ' || v_cur || '->' || v_new || ' — ' || v_note, 'system');
  end if;
  return v_new;
end
$fn$;
revoke execute on function public.fn_invite_ramp() from public, anon, authenticated;

-- 3. The ramp has a caller ------------------------------------------------------------------------
create or replace function public.fn_sales_engineer_supplier_outreach_tick(p_force boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_now_dxb timestamp := now() at time zone 'Asia/Dubai';
  v_go boolean; v_weekend boolean; v_invited int; r record; s jsonb; v_cap int;
  v_due int := 0; v_sent int := 0; v_failed jsonb := '[]'::jsonb; v_clock jsonb; v_out jsonb; v_why text;
begin
  if not p_force then
    if extract(hour from v_now_dxb) < 9 then return jsonb_build_object('due', false, 'reason', 'before 09:00 Dubai'); end if;
    if exists (select 1 from public.agent_runs a
                where a.agent = 'sales_engineer' and a.counts->>'job' = 'supplier_outreach'
                  and a.started_at > now() - interval '1 day'
                  and (a.started_at at time zone 'Asia/Dubai')::date = v_now_dxb::date) then
      return jsonb_build_object('due', false, 'reason', 'already ran this Dubai day');
    end if;
  end if;

  v_go := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive();
  v_weekend := extract(isodow from v_now_dxb) in (6, 7);
  v_why := case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
                when not v_go then 'invite_enabled is false'
                when v_weekend then 'it is the UAE weekend' end;

  -- 0. THE WARM-UP (22 Sep 2026). fn_invite_ramp sets today's invite_daily_cap from the last 48 h of
  --    bounces and complaints. Open days only: a held day sends nothing, so it must not move the cap.
  if v_why is null then v_cap := public.fn_invite_ramp(); end if;

  -- 1. The batch. enqueue_supplier_invites holds itself (gates, weekend, holiday, bounce brake, cap).
  v_invited := public.enqueue_supplier_invites(null);

  -- 2. Reminders: always counted; written only on an open weekday.
  for r in select * from public.fn_supplier_registration_reminders_due() loop
    v_due := v_due + 1;
    if v_why is not null then continue; end if;
    s := public.fn_sales_engineer_sends_registration_reminder(r.lead_id, r.stage, r.step, r.last_activity);
    if coalesce((s->>'ok')::boolean, false) then v_sent := v_sent + 1;
    else v_failed := v_failed || jsonb_build_array(jsonb_build_object('lead_id', r.lead_id, 'reason', s->>'reason'));
    end if;
  end loop;

  -- 3. The 24-hour clock: internal, so not held by the campaign gates.
  v_clock := public.fn_sales_engineer_raises_undecided_submissions(false);

  v_out := jsonb_build_object('job', 'supplier_outreach', 'dubai_day', v_now_dxb::date, 'held', v_why is not null, 'held_because', v_why,
    'invites', jsonb_build_object('queued', v_invited, 'cap', v_cap),
    'reminders', jsonb_build_object('due', v_due, 'sent', v_sent, 'failed', v_failed),
    'submissions', v_clock);
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('sales_engineer', case when jsonb_array_length(v_failed) > 0 then 'warn' else 'ok' end, now(), now(), v_out,
          case when v_why is not null
               then 'Supplier outreach HELD (' || v_why || '): ' || v_invited || ' invitation(s) queued, ' || v_due
                    || ' reminder(s) due and none written; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.'
               else 'Supplier outreach: ' || v_invited || ' invitation(s) queued at a cap of ' || coalesce(v_cap::text, '?') || ', ' || v_sent || ' of ' || v_due
                    || ' reminder(s) sent; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.' end);
  return v_out;
end
$fn$;
revoke execute on function public.fn_sales_engineer_supplier_outreach_tick(boolean) from public, anon, authenticated;

-- 4. Spread across the working day --------------------------------------------------------------
alter table public.notifications add column if not exists not_before timestamptz;
comment on column public.notifications.not_before is
  'Earliest time send_outbox may send this row (NULL = now). Supplier invitations are spread across the Dubai working window by enqueue_supplier_invites so a new domain never sends its day in one burst.';

create or replace function public.enqueue_supplier_invites(p_cap integer default null)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_today date := (now() at time zone 'UTC')::date;
  v_planned int; v_used int; v_remaining int; v_count int;
  v_inv_recent int; v_bounced_recent int; v_rate numeric; v_max_rate numeric; v_cap int;
  v_pause boolean := false; v_why text; v_go boolean; v_pool int;
  v_hol_name text; v_hol_action text; v_hol_end date;
  v_cfg jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_win_start timestamptz; v_win_end timestamptz;
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
  select count(*) into v_inv_recent from leads where invited_at > now() - interval '3 days';
  select count(*) into v_bounced_recent from leads where invite_status='bounced' and invited_at > now() - interval '3 days';
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
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; auto-paused: ' || v_why where day = v_today;
    if not exists (select 1 from founder_alerts where event='invite_paused_bounce' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values('crit','invite_paused_bounce','Supplier invites AUTO-PAUSED: '||v_why||'. Clean the list before resuming.','system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('invite_paused_bounce', coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com'),'admin','email','Supplier invites paused - deliverability risk','Invites were auto-paused: '||v_why||'. Validate the list, then re-enable.','queued');
    end if;
    return 0;
  end if;

  -- test-path rows (fixture addresses) are not invitations and must not spend the day's cap:
  -- measured in the rolled-back rehearsal, two test sends plus one real row cut a batch of 5 to 2.
  select count(*) into v_used from notifications where type='supplier_invite' and (created_at at time zone 'UTC')::date = v_today
     and not public.fn_is_demo_email(to_email);
  v_remaining := greatest(0, v_planned - v_used);
  if v_remaining <= 0 then return 0; end if;

  with c as (
    select c.*, row_number() over () as rn, count(*) over () as n
      from public.fn_supplier_invite_candidates(v_remaining) c
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
  update invite_schedule set sent = sent + v_count where day = v_today;
  insert into agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('supplier_invites', 'ok',
          jsonb_build_object('queued', v_count, 'planned', v_planned, 'pool', v_pool, 'cap', v_cap, 'held', false,
                             'window_ends', v_win_end),
          'Invites: ' || v_count || ' queued of ' || v_planned || ' planned (pool ' || v_pool || ', cap ' || v_cap
          || '), spread until ' || to_char(v_win_end at time zone 'Asia/Dubai', 'HH24:MI') || ' Dubai.', now(), now());
  return v_count;
end;
$fn$;
revoke execute on function public.enqueue_supplier_invites(integer) from public, anon, authenticated;

-- 5. Who a cold invitation may go to -------------------------------------------------------------
create or replace function public.fn_supplier_invite_eligible(p leads)
returns boolean
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
     -- 22 Sep 2026: a COLD invitation needs a measured MX. An A-record-only domain (361 leads), a lookup
     -- that errored (86) or a domain never asked is a bounce risk on a domain with no history to spend.
     and exists (select 1 from public.email_domain_mx m
                  where m.domain = split_part(lower(btrim(p.email)), '@', 2) and m.kind = 'mx')
     -- ... and never a mailbox whose reader is not the business (44 leads): a recruiter or a lawyer
     -- presses "spam", they do not register.
     and split_part(lower(btrim(p.email)), '@', 1) !~
         '^(careers?|jobs?|hr|recruit(ment|ing)?|cv|webmaster|hostmaster|mailer-daemon|privacy|legal|newsletters?|unsubscribe|donotreply)$'
$fn$;
revoke execute on function public.fn_supplier_invite_eligible(leads) from public, anon, authenticated;

-- 7. The allocation ledger names the policy it now follows (the text said 7-day, 2x, volume stage). --
create or replace function public.trg_invite_cap_allocation()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_old numeric; v_new numeric;
begin
  if new.key <> 'invite_daily_cap' then return new; end if;

  -- A non-numeric or absent value is not a reallocation; nothing is recorded rather than guessed.
  begin
    v_old := nullif(btrim(coalesce(old.value, '')), '')::numeric;
    v_new := nullif(btrim(coalesce(new.value, '')), '')::numeric;
  exception when others then
    return new;
  end;
  if v_old is null or v_new is null then return new; end if;

  -- A move to the same number moved nothing. s23-reallocation-policy-cited counts a no-op as a
  -- finding, correctly, so one is never written.
  if v_old is not distinct from v_new then return new; end if;

  insert into public.allocation_change (resource, subject, from_value, to_value, reason, policy)
  values ('supplier_onboarding_capacity', 'invite_daily_cap', v_old, v_new,
          case when v_new > v_old
               then 'Daily supplier-invite capacity raised from ' || v_old || ' to ' || v_new
                    || '. Deliverability is inside tolerance, so more onboarding capacity is released.'
               else 'Daily supplier-invite capacity reduced from ' || v_old || ' to ' || v_new
                    || '. Deliverability is outside tolerance or the campaign restarted cold, so onboarding capacity is withdrawn to '
                    || 'protect the sending domain.' end,
          'invite warm-up (app_secrets.invite_warmup): capacity follows the 48-hour bounce and complaint rates, '
          || 'growing x1.5 at most once per send day, floored at the base cap and ceilinged at the configured ceiling');
  return new;
end
$fn$;
revoke execute on function public.trg_invite_cap_allocation() from public, anon, authenticated;
