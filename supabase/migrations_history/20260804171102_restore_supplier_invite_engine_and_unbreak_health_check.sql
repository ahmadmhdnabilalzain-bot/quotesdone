-- 4 Aug 2026. Three defects found by reading org_tasks#312 - an alarm filed on 29 July into a
-- queue that cannot drain, and unread since.
--
-- 1. enqueue_supplier_invites() has failed on EVERY run since 29 July (7/7), each dying at
--    exactly 2m00s on statement timeout. 32 supplier invitations have been issued in this
--    product's entire life; the last was 28 July 09:00 UTC. invite_enabled is 'true' and the
--    cron is active, so this was a broken engine, not a paused one.
--
--    Cause, measured with EXPLAIN ANALYZE against production: the `activated` and `under` CTEs
--    are each referenced exactly once, so Postgres inlines them into the correlated subquery in
--    `prio` and recomputes them ONCE PER CANDIDATE. 5.618 ms x 19,632 candidates x 2 generated
--    subplans is ~220 s against a 120 s statement_timeout. Deterministic failure, and it cannot
--    self-heal: the candidate set is defined by `invite_status is null`, so nothing sending means
--    nothing shrinking. The aggregate being recomputed 19,632 times returns ZERO rows every time
--    (no lead is `claimed`).
--
--    Fix: `as materialized`. Measured at full scale, same 25 rows out: 2,221 ms. The body is
--    otherwise byte-identical - no selection, ordering, cap or guard behaviour is changed.
--
-- 2. fn_invite_ramp() staged the daily cap on (today - date of first invite ever), i.e. on the
--    calendar, not on volume issued. It therefore walked the cap 10 -> 25 across the same seven
--    days in which zero emails were sent, and would have reached 50 on 6 Aug and 200 on 20 Aug.
--    A zero-send week took its "healthy, warm up" branch because the throttle needs v_sent7 >= 20
--    before it can even consider throttling. Now the ladder advances on invitations actually
--    issued, and a sender that has produced nothing for three days holds at base and raises a
--    founder alert rather than warming up a list it is not sending to.
--
-- 3. run_health_check() - the platform's own 30-minute health monitor - has failed 78 of its
--    last 336 runs. `issues text[] || ('bare literal')` resolves to anyarray||anyarray because
--    the literal is type `unknown`, so Postgres tries to parse the sentence as an array literal
--    and raises "malformed array literal". The three sibling lines survive only by accident:
--    their expressions concatenate an int, which types the result as text. The bare one is the
--    auto-deploy branch - so the monitor crashed precisely when it had something to report, and
--    took every other check in the same run down with it.

-- ---------------------------------------------------------------------------------------------
-- 1. the invite enqueuer
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enqueue_supplier_invites(p_cap integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_today date := (now() at time zone 'UTC')::date;
  v_planned int; v_used int; v_remaining int; v_subj text; v_body text; v_count int;
  v_inv_recent int; v_bounced_recent int; v_rate numeric; v_max_rate numeric; v_target int; v_cap int;
  v_pause boolean := false; v_why text;
begin
  if coalesce((select value from app_secrets where key='invite_enabled'),'false') <> 'true' then return 0; end if;

  v_cap := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), 10);
  insert into invite_schedule(day, planned, status) values (v_today, v_cap, 'approved')
    on conflict (day) do update set planned = excluded.planned, status = 'approved';
  v_planned := least(coalesce(p_cap, v_cap), v_cap);
  if v_planned <= 0 then return 0; end if;

  v_max_rate := coalesce((select nullif(value,'')::numeric from app_secrets where key='invite_max_bounce_rate'), 0.08);
  select count(*) into v_inv_recent from leads where invited_at > now() - interval '3 days';
  select count(*) into v_bounced_recent from leads where invite_status='bounced' and invited_at > now() - interval '3 days';
  v_rate := round(v_bounced_recent::numeric / greatest(v_inv_recent,1), 3);

  if v_inv_recent >= 15 and v_rate > v_max_rate then
    v_pause := true;
    v_why := 'bounce rate '||(v_rate*100)||'% over 3 days ('||v_bounced_recent||'/'||v_inv_recent||') exceeds the '||(v_max_rate*100)||'% limit';
  end if;
  if not v_pause and v_bounced_recent >= 5 then
    v_pause := true;
    v_why := v_bounced_recent||' hard bounces in 3 days. Regardless of rate, that is a list-quality problem';
  end if;

  if v_pause then
    update app_secrets set value='false' where key='invite_enabled';
    if not exists (select 1 from founder_alerts where event='invite_paused_bounce' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values('crit','invite_paused_bounce','Supplier invites AUTO-PAUSED: '||v_why||'. Clean the list before resuming.','system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('invite_paused_bounce', coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com'),'admin','email','Supplier invites paused - deliverability risk','Invites were auto-paused: '||v_why||'. Validate the list, then re-enable.','queued');
    end if;
    return 0;
  end if;

  select value into v_subj from app_secrets where key='invite_subject';
  select value into v_body from app_secrets where key='invite_body';
  select count(*) into v_used from notifications where type='supplier_invite' and (created_at at time zone 'UTC')::date = v_today;
  v_remaining := greatest(0, v_planned - v_used);
  if v_remaining <= 0 then return 0; end if;

  -- How many REGISTERED suppliers we want per category before that category stops being prioritised.
  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_category'),
                       (select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 10);

  -- MATERIALIZED, 4 Aug 2026, and it is load-bearing. Both CTEs are referenced exactly once, from
  -- inside the correlated subquery in `prio`. Without this keyword Postgres inlines them there and
  -- re-runs the whole leads x lead_subcategory aggregate once per candidate - 19,632 times, twice
  -- over, ~220 s against a 120 s timeout. Neither depends on the outer row, so computing them once
  -- is semantically identical and 54x faster. Do not remove.
  with activated as materialized (
    -- suppliers who actually came on board, counted per canonical domain
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
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.email_domain, l.email_verified
    from leads l
    where l.email is not null and l.email <> '' and l.invite_status is null
      and coalesce(l.source,'') <> 'self_registered' and coalesce(l.claimed,false) = false
      and (public.fn_email_sendable(l.email)->>'ok')::boolean
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.email_domain,
      -- the lead's own most under-served category; emptiest category first so coverage evens out
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      case when c.email_verified in ('verified','true') then 0 else 1 end as unverified_rank
    from cand c
  ),
  elig as (
    select id, email, company_name from (
      select id, email, company_name, pdomain, unverified_rank,
        case when pdomain='~none' then 1 else 0 end as is_none,
        -- rk cycles: taking rk=1 from every category before any rk=2 is what spreads a run
        row_number() over (partition by pdomain order by unverified_rank, id) as rk,
        row_number() over (partition by coalesce(email_domain, split_part(email,'@',2)) order by unverified_rank, id) as domain_rk
      from prio
    ) r
    where domain_rk <= 5
    -- unclassified leads ('~none') come last: never spend the cap on a lead whose trade we do not know
    order by is_none, rk, unverified_rank, pdomain
    limit v_remaining
  ),
  ins as (
    insert into notifications(type,to_email,to_role,lead_id,subject,body,status,created_at)
    select 'supplier_invite', email, 'supplier', id, v_subj,
           replace(v_body, '{{company}}', coalesce(nullif(btrim(company_name),''), 'there')), 'queued', now()
    from elig returning to_email
  )
  update leads set invite_status='queued', invited_at=now()
  where invite_status is null and lower(email) in (select lower(to_email) from ins);
  get diagnostics v_count = row_count;
  update invite_schedule set sent = sent + v_count where day = v_today;
  return v_count;
end; $function$;

-- ---------------------------------------------------------------------------------------------
-- 2. the ramp
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_invite_ramp()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_base int := 10; v_ceiling int := 200;
  v_sent_total int; v_last_sent timestamptz; v_stage int;
  v_sent7 int; v_bounced7 int; v_rate numeric;
  v_cur int; v_new int; v_note text;
begin
  -- only manage the cap while the campaign is on; if paused, leave it as-is
  if coalesce((select value from app_secrets where key='invite_enabled'),'false') <> 'true' then
    return coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), v_base);
  end if;

  v_cur := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), v_base);

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

-- ---------------------------------------------------------------------------------------------
-- 3. the health monitor that died whenever it had news
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.run_health_check()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare issues text[] := '{}'; stuck int; failed int; dirty_stuck boolean; inq int; q int; pend int; sms_stuck int; alert_recent boolean;
begin
  select count(*) into stuck from public.notifications
    where coalesce(status,'queued')='queued' and coalesce(channel,'email')<>'sms' and created_at < now()-interval '60 minutes';
  select count(*) into failed from public.notifications where status='failed' and created_at > now()-interval '24 hours';
  select count(*) into sms_stuck from public.notifications where channel='sms' and coalesce(status,'queued')='queued' and created_at < now()-interval '30 minutes';
  select (dirty and coalesce(last_deploy, '2000-01-01') < now()-interval '20 minutes') into dirty_stuck from public.deploy_state where id=1;
  select count(*) into inq from public.inquiries where created_at > now()-interval '24 hours';
  select count(*) into q from public.quotes where created_at > now()-interval '24 hours';
  select count(*) into pend from public.transactions where refund_status='requested';

  -- The ::text casts are the fix, not decoration. `text[] || 'a bare literal'` resolves to
  -- anyarray || anyarray because an unadorned literal is type `unknown`, so Postgres parses the
  -- sentence as an array literal and raises 22P02. Lines that concatenate an int survived only
  -- because that types the expression as text. All four are now explicit.
  if stuck > 0 then issues := issues || ('Email queue stuck: '||stuck||' email(s) queued >1h — the email cron / Resend may be down.')::text; end if;
  if failed > 25 then issues := issues || ('High email failures: '||failed||' failed in 24h — check Resend domain auth.')::text; end if;
  if coalesce(dirty_stuck,false) then issues := issues || ('Auto-deploy stuck: a page change has not deployed in 20+ min — check the Vercel token / cron.')::text; end if;
  -- sms only flagged if a sender is configured (else it is expected to sit)
  if sms_stuck > 0 and exists (select 1 from public.app_secrets where key='twilio_account_sid' and value is not null and value<>'') then
     issues := issues || ('SMS queue stuck: '||sms_stuck||' SMS queued >30min.')::text; end if;

  update public.health_state set last_run=now(), last_status=(case when array_length(issues,1) is null then 'ok' else 'issues' end) where id=1;
  select (last_alert_at > now()-interval '6 hours') into alert_recent from public.health_state where id=1;

  if array_length(issues,1) is not null and not coalesce(alert_recent,false) then
    insert into public.notifications(type,to_email,to_role,subject,body,status)
    select 'health_alert', trim(split_part(value,',',1)), 'admin', 'QuotesDone system health alert',
      'Automated check found issue(s):'||chr(10)||'- '||array_to_string(issues, chr(10)||'- ')||chr(10)||chr(10)||
      'Last 24h: '||inq||' inquiries, '||q||' quotes. Pending refund requests: '||pend||'.'||chr(10)||
      'Open the admin dashboard to investigate.', 'queued'
    from public.app_secrets where key='admin_emails';
    update public.health_state set last_alert_at=now() where id=1;
  end if;

  return json_build_object('ok',true,'status',(case when array_length(issues,1) is null then 'ok' else 'issues' end),'issues',to_jsonb(issues),'stuck_emails',stuck,'failed_24h',failed,'inq_24h',inq,'q_24h',q,'pending_refunds',pend);
end $function$;

-- ---------------------------------------------------------------------------------------------
-- 4. make a failing cron job visible without anyone having to think of looking
-- ---------------------------------------------------------------------------------------------
-- supplier_invites_daily failed 7/7 for a week and the only thing that noticed filed its alarm
-- into org_tasks, which has no approval path and therefore no reader. cron.job_run_details had
-- the answer the whole time. This view is the standing question.
CREATE OR REPLACE VIEW public.v_cron_failing AS
select j.jobname,
       j.schedule,
       j.active,
       count(*) filter (where d.status <> 'succeeded') as failed_runs,
       count(*)                                        as total_runs,
       min(d.start_time) filter (where d.status <> 'succeeded') as first_failure,
       max(d.start_time) filter (where d.status <> 'succeeded') as last_failure,
       max(d.start_time) filter (where d.status =  'succeeded') as last_success,
       left((array_agg(d.return_message order by d.start_time desc)
             filter (where d.status <> 'succeeded'))[1], 300)   as last_error
from cron.job j
join cron.job_run_details d on d.jobid = j.jobid
where d.start_time > now() - interval '7 days'
group by j.jobname, j.schedule, j.active
having count(*) filter (where d.status <> 'succeeded') > 0;

comment on view public.v_cron_failing is
  'Any cron job with at least one non-succeeded run in the last 7 days. Must be empty. Added 4 Aug 2026 after supplier_invites_daily failed 7/7 for a week unnoticed.';

grant select on public.v_cron_failing to service_role;

-- ---------------------------------------------------------------------------------------------
-- 5. re-enter at the volume the domain last proved it could sustain
-- ---------------------------------------------------------------------------------------------
-- The cap says 25 because the old calendar ladder raised it during the outage. 32 invitations have
-- ever been issued. Founder decision, 4 Aug: resume at 10 and let the corrected ramp earn the rest.
update public.app_secrets set value = '10' where key = 'invite_daily_cap';;
