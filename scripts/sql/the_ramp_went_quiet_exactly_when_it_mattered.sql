-- THE RAMP WENT QUIET EXACTLY WHEN IT MATTERED
--
-- He asked me to watch the invite ramp. Measured on production at 00:10 UTC on 13 Aug:
--
--     invite_enabled  true      invite_daily_cap  10      invite_max_bounce_rate  0.05
--     7-day sends 29    7-day bounces 3    RATE 10.3%  — twice the threshold
--
-- fn_invite_ramp runs daily at 08:45. On its next run it will take the throttle branch, because
-- v_sent7 (29) >= 20 and v_rate (0.1034) >= 0.05. And then:
--
--     v_new := greatest(v_base, floor(v_cur * 0.5))   ->  greatest(10, 5)  ->  10
--     ...
--     if v_new <> v_cur then          <- 10 <> 10 is FALSE
--       update app_secrets ...
--       insert into agent_runs ...    <- the only record this function writes
--       if v_new < v_cur then
--         insert into founder_alerts  <- the only warning it raises
--
-- Both the record and the warning live inside `if v_new <> v_cur`. Once the cap is at its floor of
-- 10 the cap cannot go lower, so the condition can never be true, so a list bouncing at twice the
-- pause threshold produces **no agent_runs row and no alert at all**. The cron reports success.
-- Ask whether this recovery path has ever run and the answer is that it cannot: the louder the
-- problem, the quieter this function gets, because loudness is gated on the cap still having room
-- to fall.
--
-- That is backwards, and it is worse than a missing alert. "I would throttle you but you are
-- already as slow as I can make you" is MORE serious than a throttle, not less — it is the ramp
-- saying it has run out of ways to protect the sending domain.
--
-- Two changes, both narrow:
--   1. The agent_runs row is written on EVERY run, not only when the number moves. A daily
--      instrument that only files a report on days it changes something cannot be used to answer
--      "is this healthy", which is the only question anyone asks it.
--   2. The founder alert fires when the throttle branch is taken AND the cap is already at the
--      floor — the case that previously produced silence.
--
-- Also corrected: the throttle alert's own text said "Hard auto-pause still triggers at 8%". The
-- pause threshold was changed to 0.05 on 12 Aug and the string was not. It now reads the live value
-- out of app_secrets instead of asserting a number from memory.
create or replace function public.fn_invite_ramp()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_base int := 10; v_ceiling int := 200;
  v_sent_total int; v_last_sent timestamptz; v_stage int;
  v_sent7 int; v_bounced7 int; v_rate numeric;
  v_cur int; v_new int; v_note text;
  v_uncontacted int; v_max_rate numeric; v_at_floor boolean := false;
begin
  v_cur := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), v_base);
  v_max_rate := coalesce((select nullif(value,'')::numeric from app_secrets where key='invite_max_bounce_rate'), 0.05);

  -- PAUSED IS A REPORTABLE STATE, NOT A SILENT ONE. Previously this returned here and said nothing,
  -- so a campaign auto-paused on bounce rate looked identical to a healthy one: both crons
  -- 'succeeded', no agent_runs row, no alert, and the stall detector below unreachable.
  if coalesce((select value from app_secrets where key='invite_enabled'),'false') <> 'true' then
    select count(*), max(invited_at) into v_sent_total, v_last_sent from leads where invited_at is not null;
    select count(*) into v_sent7    from leads where invited_at > now() - interval '7 days';
    select count(*) into v_bounced7 from leads where invite_status='bounced' and invited_at > now() - interval '7 days';
    select count(*) into v_uncontacted from leads
      where invited_at is null and coalesce(btrim(email),'') <> '';

    v_note := 'PAUSED: invite_enabled is false. '||v_uncontacted||' lead(s) with an email have never '
      ||'been invited, of '||(select count(*) from leads)||' total. Last invite '
      ||coalesce(to_char(v_last_sent at time zone 'UTC','YYYY-MM-DD HH24:MI')||'Z','never')
      ||'; '||v_sent_total||' issued lifetime; 7d bounce '
      ||round((v_bounced7::numeric / greatest(v_sent7,1))*100,1)||'% ('||v_bounced7||'/'||v_sent7||').';

    insert into agent_runs(agent,status,counts,note,finished_at)
    values('invite_ramp','ok',
           jsonb_build_object('paused',true,'cap',v_cur,'sent_total',v_sent_total,
                              'uncontacted_with_email',v_uncontacted),
           v_note, now());

    if v_uncontacted > 0
       and not exists (select 1 from founder_alerts
                        where event='invite_campaign_paused' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
      values('warn','invite_campaign_paused',
             'Supplier invites are PAUSED and nothing is being sent. '||v_note
             ||' Re-enabling sends into this bounce rate risks the sending domain — verify the list '
             ||'before setting app_secrets.invite_enabled back to true.','system');
    end if;

    return v_cur;
  end if;

  select count(*), max(invited_at) into v_sent_total, v_last_sent from leads where invited_at is not null;
  select count(*) into v_sent7    from leads where invited_at > now() - interval '7 days';
  select count(*) into v_bounced7 from leads where invite_status='bounced' and invited_at > now() - interval '7 days';
  v_rate := v_bounced7::numeric / greatest(v_sent7,1);

  -- STAGE ON VOLUME ISSUED, NOT ON THE CALENDAR. The previous ladder read
  -- (today - min(invited_at)::date), so it advanced while the enqueuer was timing out and nothing
  -- was being sent. A warm-up schedule that ratchets on a domain that is not sending is a
  -- deliverability incident held in escrow until somebody fixes the sender.
  v_stage := case when v_sent_total <  25 then 10
                  when v_sent_total <  75 then 25
                  when v_sent_total < 200 then 50
                  when v_sent_total < 500 then 100
                  else v_ceiling end;

  if v_last_sent is null then
    v_new := v_base;
    v_note := 'nothing issued yet; cap held at base '||v_base;
  elsif v_last_sent < now() - interval '3 days' then
    -- Silence is now a reportable state. Seven days of daily statement timeouts went unnoticed
    -- because the only thing watching filed its alarm into a queue with no reader.
    v_new := v_base;
    v_note := 'stalled: nothing issued since '||to_char(v_last_sent at time zone 'UTC','YYYY-MM-DD HH24:MI')||'Z; cap held at base '||v_base;
    if not exists (select 1 from founder_alerts where event='invite_sender_stalled' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
      values('crit','invite_sender_stalled',
             'Supplier invites: nothing issued since '||to_char(v_last_sent at time zone 'UTC','YYYY-MM-DD HH24:MI')
             ||'Z, but invite_enabled is true. The enqueuer is FAILING, not paused. '
             ||'Check select * from public.v_cron_failing.','system');
    end if;
  elsif v_sent7 >= 20 and v_rate >= 0.05 then
    v_new := greatest(v_base, floor(v_cur * 0.5)::int);   -- deliverability wobble: throttle down
    v_at_floor := (v_new = v_cur);
    v_note := case when v_at_floor
      then 'THROTTLE WANTED BUT ALREADY AT THE FLOOR: 7d bounce '||round(v_rate*100,1)||'% ('||v_bounced7||'/'||v_sent7
           ||') >= 5%, and the cap is already at the base of '||v_base||' so there is nothing left to reduce.'
      else 'throttle: 7d bounce '||round(v_rate*100,1)||'% ('||v_bounced7||'/'||v_sent7||') >= 5%; cap '||v_cur||'->'||v_new end;
    -- THE CASE THAT USED TO BE SILENT. Every record this function wrote lived inside
    -- `if v_new <> v_cur`, so once the cap sat at its floor a list bouncing at twice the threshold
    -- produced no row and no warning — the louder the problem, the quieter the instrument.
    if v_at_floor and not exists (select 1 from founder_alerts
                                   where event='invite_throttle_exhausted' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
      values('crit','invite_throttle_exhausted',
             'Supplier invites: '||v_note||' The ramp has run out of ways to protect the sending domain '
             ||'short of stopping. Hard auto-pause triggers at '||round(v_max_rate*100,1)||'% or '
             ||greatest(5, ceil(v_sent7 * v_max_rate))::int||' hard bounces in the window, and '
             ||v_bounced7||' have been recorded. Verify the list, or set app_secrets.invite_enabled '
             ||'to false yourself.','system');
    end if;
  -- ---- ADDED 11 Aug 2026: THE ACCELERATOR NOW OBEYS THE SAME NUMBER THE BRAKE DOES -------------
  -- On 2026-08-06 this function recorded "healthy: ... 7d bounce 10.0% (1/10); cap 10->20". The
  -- throttle above needs v_sent7 >= 20 before it may act; the warm-up below needed nothing at all,
  -- so a rate at twice the threshold still doubled the cap. A sample too small to justify HALVING
  -- is not a sample that licenses DOUBLING. It holds instead.
  elsif v_bounced7 > 0 and v_rate >= 0.05 then
    v_new  := v_cur;
    v_note := 'hold: 7d bounce '||round(v_rate*100,1)||'% ('||v_bounced7||'/'||v_sent7||') is at or above 5% '
           ||'but only '||v_sent7||' send(s) in 7d - too few to throttle on, far too many to warm up into. '
           ||'Cap held at '||v_cur||' rather than doubled.';
    if not exists (select 1 from founder_alerts where event='invite_ramp_held' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
      values('warn','invite_ramp_held',
             'Supplier-invite cap HELD at '||v_cur||' instead of warming up: '||v_note
             ||' The list needs verifying before volume increases.','system');
    end if;
  -- ----------------------------------------------------------------------------------------------
  else
    v_new := least(v_stage, v_cur * 2);                   -- healthy: warm up, at most 2x/day, capped by the volume-stage
    v_note := 'healthy: '||v_sent_total||' issued lifetime, stage '||v_stage||', 7d bounce '||round(v_rate*100,1)||'% ('||v_bounced7||'/'||greatest(v_sent7,0)||'); cap '||v_cur||'->'||v_new;
  end if;

  v_new := greatest(v_base, least(v_new, v_ceiling));

  if v_new <> v_cur then
    update app_secrets set value = v_new::text where key='invite_daily_cap';
  end if;

  -- EVERY RUN FILES A REPORT, NOT ONLY THE RUNS THAT CHANGED A NUMBER. A daily instrument that
  -- writes a row only on the days it moves something cannot answer "is this healthy today", which
  -- is the only question anyone asks it — and its silence was previously indistinguishable from
  -- not having run.
  insert into agent_runs(agent,status,counts,note,finished_at)
    values('invite_ramp', case when v_at_floor then 'error' else 'ok' end,
           jsonb_build_object('old_cap',v_cur,'new_cap',v_new,'sent_total',v_sent_total,
                              'sent_7d',v_sent7,'bounced_7d',v_bounced7,
                              'bounce_pct_7d',round(v_rate*100,1),'at_floor',v_at_floor),
           coalesce(v_note,''), now());

  if v_new < v_cur then
    insert into founder_alerts(level,event,detail,channel)
      values('warn','invite_cap_throttled','Supplier-invite cap reduced '||v_cur||'->'||v_new||' — '
             ||coalesce(v_note,'')||'. Hard auto-pause triggers at '||round(v_max_rate*100,1)
             ||'% — read live from app_secrets.invite_max_bounce_rate rather than asserted, because '
             ||'this string said 8% for a day after the value became 0.05.','system');
  end if;
  return v_new;
end; $function$;
