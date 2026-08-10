-- A PAUSED SUPPLIER-INVITE CAMPAIGN IS INVISIBLE, AND IT HAS BEEN PAUSED FOR FOUR DAYS.
--
-- Measured on production 2026-08-10:
--     leads                     20,470   (19,903 with an email address)
--     ever invited                  62   (0.30%)
--     lifecycle_stage not_contacted 20,399   (99.65%)
--     last invite sent      2026-08-06   — nothing for four days
--     app_secrets.invite_enabled 'false'
--
-- It auto-paused on deliverability, correctly: on 7 Aug fn_invite_ramp throttled the cap 20 -> 10
-- with "7d bounce 13.3% (4/30) >= 5%", and the hard auto-pause trips at 8%. Protecting the sending
-- domain is the right call.
--
-- THE DEFECT IS THAT NOTHING SAYS SO. Both invite routines bail out on the first line —
--     fn_invite_ramp:            if invite_enabled <> 'true' then return <cap>; end if;
--     enqueue_supplier_invites:  if invite_enabled <> 'true' then return 0;     end if;
-- — - so invite_ramp_daily (08:45) and supplier_invites_daily (09:00) both report 'succeeded' every
-- morning while issuing nothing, agent_runs gets no row, and no alert is raised. fn_invite_ramp
-- DOES have a stall detector, but it sits AFTER the enabled-check and can therefore never fire for
-- a paused campaign — the one state in which the founder most needs to hear about it.
--
-- So the company's only mechanism for working its 20,470 existing leads has been stopped since 6 Aug
-- and every dashboard reads green.
--
-- FIX: the paused branch reports instead of returning silently — one founder alert, deduped to 24h
-- so a deliberate pause is a daily line and not a flood, carrying the three numbers needed to decide
-- (how long, how many leads are still uncontacted, and the bounce rate that caused it). Nothing is
-- re-enabled: restarting a send into a 13% bounce rate is a deliverability and spend decision, and
-- it is the founder's. This only makes the state visible.

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
