-- THE INVITE RAMP COULD ACCELERATE INTO A BOUNCE RATE IT WAS NOT YET ALLOWED TO BRAKE ON.
--
-- Read from agent_runs on production, the campaign's own history in its own words:
--
--   2026-08-06 08:45  "healthy: 42 issued lifetime, stage 25, 7d bounce 10.0% (1/10); cap 10->20"
--   2026-08-07 08:45  "throttle: 7d bounce 13.3% (4/30) >= 5%; cap 20->10"
--   2026-08-10 08:45  "PAUSED: invite_enabled is false. 19841 lead(s) ... never been invited"
--   2026-08-11 08:45  "PAUSED: ..."
--
-- On 6 August the ramp observed a 10% bounce rate - twice its own 5% threshold - and DOUBLED the
-- daily cap. It was not a bug in the arithmetic. The throttle branch is guarded by
-- `v_sent7 >= 20 and v_rate >= 0.05`, and only 10 invites had gone out in the preceding week, so
-- the brake was not yet allowed to engage. The accelerator carried no such guard: `least(v_stage,
-- v_cur * 2)` runs whenever the throttle does not.
--
-- So during warm-up - precisely when a young sending domain is most fragile and a bad list does the
-- most lasting damage - the ramp speeds up and the brake cannot reach it. The next day it saw 4
-- bounces in 30 and halved back, and the campaign was paused shortly after. 5 of 62 lifetime
-- invites bounced.
--
-- THE FIX IS ONE BRANCH, and it is the asymmetry that matters: a small sample is a reason to be
-- SLOWER to accelerate, never a licence to. Too few sends to justify halving the cap is still far
-- too many bounces to double it, so the cap HOLDS. Nothing else changes - the throttle, the hard
-- pause at 8%, the volume-staged ceiling and the stall detector are all untouched and all correct.
--
-- THIS DOES NOT RESUME THE CAMPAIGN. app_secrets.invite_enabled stays 'false'. Sending to 19,841
-- real UAE companies is the founder's call and carries live deliverability risk to the sending
-- domain; it is not an engineering decision and this file does not make it.

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
  v_uncontacted int;
begin
  v_cur := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), v_base);

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
    v_note := 'throttle: 7d bounce '||round(v_rate*100,1)||'% ('||v_bounced7||'/'||v_sent7||') >= 5%; cap '||v_cur||'->'||v_new;
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
    insert into agent_runs(agent,status,counts,note,finished_at)
      values('invite_ramp','ok',jsonb_build_object('old_cap',v_cur,'new_cap',v_new,'sent_total',v_sent_total),coalesce(v_note,''),now());
    if v_new < v_cur then
      insert into founder_alerts(level,event,detail,channel)
        values('warn','invite_cap_throttled','Supplier-invite cap reduced '||v_cur||'->'||v_new||' — '||coalesce(v_note,'')||'. Hard auto-pause still triggers at 8%.','system');
    end if;
  end if;
  return v_new;
end; $function$;
