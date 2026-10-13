-- Assigned: marketing (the campaign) with it_engineer (deliverability). Founder ruling 1231, 13 Oct 2026.
--
-- THE DAILY INVITATION CAP IS THE FOUNDER'S CALENDAR, NOT THE ADAPTIVE RAMP. Working days only:
--   until 18 Oct 2026: 20 a day; from 19 Oct: 30; from 26 Oct: 40; from 2 Nov: 50, and 50 is the ceiling.
-- Before this file fn_invite_ramp grew the cap x1.5 per healthy send day up to invite_warmup.ceiling_cap
-- (200), so the ruling would have held only by convention (a config value someone must remember to move).
--
--   1. fn_invite_founder_cap(day) returns the ruling's number for a Dubai day. It is the only place the
--      schedule lives.
--   2. fn_invite_ramp: the founder cap is an UPPER BOUND on the configured base and ceiling. Healthy growth
--      (x1.5 once per send day) reaches the week's number and stops there; a cap set lower is never raised;
--      the bounce back-off halves (it used to floor at base, a no-op that paged daily). The configured
--      ceiling_cap goes to 50 with this apply (bottom of the file).
--   3. enqueue_supplier_invites clamps whatever invite_daily_cap holds to the founder cap, so a hand edit
--      of app_secrets cannot send more than the ruling allows either.
-- Weekends and UAE holidays already send nothing (enqueue holds itself), so the schedule needs no
-- working-day logic of its own.

create or replace function public.fn_invite_founder_cap(p_day date)
returns integer
language sql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select case
    when p_day < date '2026-10-19' then 20
    when p_day < date '2026-10-26' then 30
    when p_day < date '2026-11-02' then 40
    else 50
  end;
$fn$;
revoke execute on function public.fn_invite_founder_cap(date) from public, anon, authenticated;

create or replace function public.fn_invite_ramp()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
  select count(*),
         count(*) filter (where invite_status = 'bounced'),
         count(*) filter (where invite_status = 'complained')
    into v_s48, v_b48, v_c48
    from leads where invited_at > now() - interval '48 hours' and not coalesce(is_demo, false) and not public.fn_is_demo_email(email);
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
    v_restart := true; v_new := least(v_cur, v_base);   -- ruling 1231 review: a restart lowers to base, never raises
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
$fn$;
revoke execute on function public.fn_invite_ramp() from public, anon, authenticated;

create or replace function public.enqueue_supplier_invites(p_cap integer default null::integer)
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
  v_gate text;
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

  -- PLACEMENT GATE (24 Sep 2026, it_engineer). Nothing is queued unless this morning's seed invitation landed
  -- in the Inbox of both seed mailboxes under today's effective sender (fn_invite_placement_gate). Fail closed: a check
  -- that is still running, failed, or never ran all hold the batch.
  v_gate := public.fn_invite_placement_gate((now() at time zone 'Asia/Dubai')::date);
  if v_gate <> 'pass' then
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; held: inbox placement ' || v_gate where day = v_today;
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'planned', v_planned, 'placement_gate', v_gate, 'held', true),
            'Invites held: the morning inbox placement check answered ' || v_gate || ', so nothing was written to the outbox.', now(), now());
    return 0;
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
  -- ONE daily cap for invitations and their nudges (review of #1007, 29 Sep 2026): a nudge queued today spends it too,
  -- as fn_sales_engineer_nudges_invited_suppliers already counts the invitations queued today against the same cap.
  select count(*) into v_used from notifications where type in ('supplier_invite', 'supplier_invite_nudge') and (created_at at time zone 'UTC')::date = v_today
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

-- CONFIG WITH THE APPLY (founder:1231): configured ceiling_cap becomes 50 so healthy x1.5 growth can reach each
-- week's founder cap (20 -> 30 -> 40 -> 50); fn_invite_founder_cap keeps it at or below the ruling. Written here and
-- not before, because the ramp live until this file would grow to the configured ceiling with no schedule above it.
set local app.change_reason = 'founder:1231';
update public.app_secrets set value = (value::jsonb || '{"ceiling_cap": 50}'::jsonb)::text where key = 'invite_warmup';

-- PROBE (verdict row; DDL in this file, so it does not raise). Reads only; writes nothing.
select case
  when public.fn_invite_founder_cap(date '2026-10-14') <> 20 then 'PROBE FAILED: 14 Oct is not 20'
  when public.fn_invite_founder_cap(date '2026-10-18') <> 20 then 'PROBE FAILED: 18 Oct is not 20'
  when public.fn_invite_founder_cap(date '2026-10-19') <> 30 then 'PROBE FAILED: 19 Oct is not 30'
  when public.fn_invite_founder_cap(date '2026-10-26') <> 40 then 'PROBE FAILED: 26 Oct is not 40'
  when public.fn_invite_founder_cap(date '2026-11-02') <> 50 then 'PROBE FAILED: 2 Nov is not 50'
  when public.fn_invite_founder_cap(date '2027-06-01') <> 50 then 'PROBE FAILED: the ceiling is not 50'
  when position('fn_invite_founder_cap' in pg_get_functiondef('public.fn_invite_ramp()'::regprocedure)) = 0 then 'PROBE FAILED: the ramp does not read the founder cap'
  when position('fn_invite_founder_cap' in pg_get_functiondef('public.enqueue_supplier_invites(integer)'::regprocedure)) = 0 then 'PROBE FAILED: the sender does not clamp to the founder cap'
  else 'PROBE OK' end as verdict;
