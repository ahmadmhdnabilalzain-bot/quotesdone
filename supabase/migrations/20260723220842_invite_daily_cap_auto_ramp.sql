-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260723220842   name: invite_daily_cap_auto_ramp
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #51: safe automatic warm-up of the supplier-invite daily cap. Grows the cap on a time-based
-- warmup schedule but ONLY while deliverability is clean; halves it on a bounce wobble (5-8%);
-- the enqueue hard-breaker still fully pauses at 8%. Floor 10, ceiling 200, max 2x growth/day.
create or replace function public.fn_invite_ramp() returns integer
 language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_base int := 10; v_ceiling int := 200;
  v_start date; v_days int; v_stage int;
  v_sent7 int; v_bounced7 int; v_rate numeric;
  v_cur int; v_new int; v_note text;
begin
  -- only manage the cap while the campaign is on; if paused, leave it as-is
  if coalesce((select value from app_secrets where key='invite_enabled'),'false') <> 'true' then
    return coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), v_base);
  end if;

  v_cur := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), v_base);
  select min(invited_at)::date into v_start from leads where invited_at is not null;

  if v_start is null then
    v_new := v_base;                              -- nothing sent yet
  else
    v_days := (now() at time zone 'UTC')::date - v_start;
    v_stage := case when v_days < 7 then 10 when v_days < 14 then 25
                    when v_days < 21 then 50 when v_days < 28 then 100 else v_ceiling end;
    select count(*) into v_sent7    from leads where invited_at > now() - interval '7 days';
    select count(*) into v_bounced7 from leads where invite_status='bounced' and invited_at > now() - interval '7 days';
    v_rate := v_bounced7::numeric / greatest(v_sent7,1);

    if v_sent7 >= 20 and v_rate >= 0.05 then
      v_new := greatest(v_base, floor(v_cur * 0.5)::int);   -- deliverability wobble: throttle down
      v_note := 'throttle: 7d bounce '||round(v_rate*100,1)||'% ('||v_bounced7||'/'||v_sent7||') >= 5%; cap '||v_cur||'->'||v_new;
    else
      v_new := least(v_stage, v_cur * 2);                   -- healthy: warm up, at most 2x/day, capped by the day-stage
      v_note := 'healthy: day '||v_days||', stage '||v_stage||', 7d bounce '||round(v_rate*100,1)||'% ('||v_bounced7||'/'||greatest(v_sent7,0)||'); cap '||v_cur||'->'||v_new;
    end if;
  end if;

  v_new := greatest(v_base, least(v_new, v_ceiling));
  if v_new <> v_cur then
    update app_secrets set value = v_new::text where key='invite_daily_cap';
    insert into agent_runs(agent,status,counts,note,finished_at)
      values('invite_ramp','ok',jsonb_build_object('old_cap',v_cur,'new_cap',v_new),coalesce(v_note,''),now());
    if v_new < v_cur then
      insert into founder_alerts(level,event,detail,channel)
        values('warn','invite_cap_throttled','Supplier-invite cap reduced '||v_cur||'->'||v_new||' — '||coalesce(v_note,'')||'. Hard auto-pause still triggers at 8%.','system');
    end if;
  end if;
  return v_new;
end; $function$;

-- run daily at 08:45 UTC, before the 09:00 invite send, so the day's cap is set first
select cron.schedule('invite_ramp_daily','45 8 * * *','select public.fn_invite_ramp();');

-- run once now to confirm it behaves (day ~0, tiny sample -> should hold cap at 10)
select public.fn_invite_ramp() as computed_cap_today;
