-- THE RAMP MEASURES AN INVITATION BY WHEN IT LEFT, NOT WHEN IT WAS QUEUED (it_engineer, 3 Nov 2026).
--
-- fn_invite_ramp read "the last invitation issued" as max(leads.invited_at). invited_at is written when the row is
-- QUEUED (enqueue_supplier_invites, about 05:00Z), not when the outbox sends it across the working day. The brakes were
-- moved to real sends on 2 Nov (fn_invite_send_health); the ramp's own three reads were not. MEASURED on production:
--   * Fri 30 Oct: 30 invitations sent 06:02-12:46Z, all queued 05:00:01.14Z; the run grew the cap 20 -> 30.
--   * Mon 2 Nov 05:00:01.92Z: max(invited_at) was 0.78 s older than three days, so the run was a RESTART and cut the
--     cap 30 -> 20 (agent_runs 4645786). By send time the last invitation had left 64 h earlier, not 72.
--     Both run on the same 05:00Z tick, so Monday is a restart whenever its run starts any later in the tick than Friday's
--     batch was queued: the ladder rarely survives a weekend.
--   * Tue 3 Nov 05:00Z: Monday sent nothing (the bounce brake 4 fired at 05:00Z, the founder resumed at 07:07Z), so the
--     second restart in a row paged invite_sender_stalled (agent_runs 4682555), naming "the enqueuer or the outbox".
--   * A backlog row queued on 28 Oct and sent on 3 Nov (notifications 116650, lead 25284) counted as issued on 28 Oct.
-- Now the three reads (last sent, the last send day, what that day issued) read the outbox's sent rows by sent_at,
-- with the same demo filters as fn_invite_send_health, from the lane's activation stamp. And because a Monday is then no
-- longer a restart, growth needs at least backoff_min_sends sent in the 48 h health window (Monday's window is the weekend:
-- 0 bounces of 0 sends is not health), else it holds. Nothing else in the body changes.
-- CREATE OR REPLACE keeps the routine's closed ACL (no revoke needed). Seat: it_engineer.
-- prevented by: scripts/checks/the_invite_ramp_measures_sends_not_queue_time.test.mjs; probe _probe.sql.
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

  -- ISSUED MEANS SENT, AND WHEN IT WAS SENT (3 Nov 2026): the same rows fn_invite_send_health reads, from the lane's stamp.
  select count(distinct n.lead_id), max(n.sent_at), max((n.sent_at at time zone 'Asia/Dubai')::date)
    into v_sent_total, v_last_sent, v_last_day
    from public.notifications n join public.leads l on l.id = n.lead_id
   where n.type = 'supplier_invite' and n.status = 'sent' and n.sent_at >= v_since
     and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(n.to_email);
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
  elsif v_s48 < v_back_n then
    -- NO GROWTH ON AN EMPTY WINDOW (3 Nov 2026). A Monday is no longer a restart, and its 48 h window holds the weekend's
    -- zero sends: "0 bounces of 0" is not health. It holds until the window carries enough sends to judge.
    v_new := v_cur;
    v_note := 'hold: ' || v_s48 || ' invitation(s) sent in 48 h, too few to judge health; growth needs ' || v_back_n || '.';
  else
    -- GROW ON VOLUME ISSUED, ONCE PER SEND DAY. Weekends and holidays run no batch, so a calendar-based
    -- ladder would ratchet on days the domain sent nothing.
    select count(*) into v_last_day_sent
      from public.notifications n join public.leads l on l.id = n.lead_id
     where n.type = 'supplier_invite' and n.status = 'sent' and n.sent_at >= v_since
       and (n.sent_at at time zone 'Asia/Dubai')::date = v_last_day
       and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(n.to_email);
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
