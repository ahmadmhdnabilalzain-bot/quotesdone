-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260723215926   name: supplier_invites_autonomous
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #51: make supplier invites fully autonomous per founder directive — no manual daily approval,
-- a safe hard daily cap (new domain), trade round-robin toward 5/trade, all safety rails kept.
update public.app_secrets set value='10' where key='invite_daily_cap';

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
begin
  if coalesce((select value from app_secrets where key='invite_enabled'),'false') <> 'true' then
    return 0;
  end if;

  -- AUTONOMOUS: no manual per-day approval. A safe hard daily cap governs volume; today's
  -- invite_schedule row is auto-approved for tracking. p_cap can only LOWER the cap (canary), never raise it.
  v_cap := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), 10);
  insert into invite_schedule(day, planned, status) values (v_today, v_cap, 'approved')
    on conflict (day) do update set planned = excluded.planned, status = 'approved';
  v_planned := least(coalesce(p_cap, v_cap), v_cap);
  if v_planned <= 0 then return 0; end if;

  -- deliverability circuit-breaker: auto-pause if recent invites bounce above the safety limit
  v_max_rate := coalesce((select nullif(value,'')::numeric from app_secrets where key='invite_max_bounce_rate'), 0.08);
  select count(*) into v_inv_recent from leads where invited_at > now() - interval '3 days';
  select count(*) into v_bounced_recent from leads where invite_status='bounced' and invited_at > now() - interval '3 days';
  if v_inv_recent >= 50 and (v_bounced_recent::numeric / greatest(v_inv_recent,1)) > v_max_rate then
    v_rate := round(v_bounced_recent::numeric / greatest(v_inv_recent,1), 3);
    update app_secrets set value='false' where key='invite_enabled';
    if not exists (select 1 from founder_alerts where event='invite_paused_bounce' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values('crit','invite_paused_bounce','Supplier invites AUTO-PAUSED: bounce rate '||(v_rate*100)||'% over 3 days ('||v_bounced_recent||'/'||v_inv_recent||') exceeds the '||(v_max_rate*100)||'% limit. Clean the list before resuming.','system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('invite_paused_bounce', coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com'),'admin','email','Supplier invites paused — high bounce rate','Invites were auto-paused: '||(v_rate*100)||'% bounced in the last 3 days. Clean/validate the list, then re-enable in the OS.','queued');
    end if;
    return 0;
  end if;

  select value into v_subj from app_secrets where key='invite_subject';
  select value into v_body from app_secrets where key='invite_body';
  select count(*) into v_used from notifications where type='supplier_invite' and (created_at at time zone 'UTC')::date = v_today;
  v_remaining := greatest(0, v_planned - v_used);
  if v_remaining <= 0 then return 0; end if;

  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 5);

  with activated as (
    select code, count(distinct l.id) ct
    from leads l, lateral unnest(l.invite_trades) code
    where coalesce(l.claimed,false) = true
    group by code
  ),
  under as (
    select t.code from taxonomy_trade t left join activated a on a.code = t.code
    where t.active and coalesce(a.ct,0) < v_target
  ),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.invite_trades
    from leads l
    where l.email is not null and l.email <> '' and l.invite_status is null
      and coalesce(l.source,'') <> 'self_registered' and coalesce(l.claimed,false) = false
      and lower(l.email) not in (select lower(email) from email_suppressions)
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name,
      coalesce((select u.code from under u where u.code = any(c.invite_trades) limit 1), '~none') as ptrade
    from cand c
  ),
  elig as (
    select id, email, company_name
    from (
      select id, email, company_name,
        case when ptrade='~none' then 1 else 0 end as is_none,
        row_number() over (partition by ptrade order by id) as rk
      from prio
    ) r
    order by is_none, rk, ptrade
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

-- Conversion tracking: per-trade invite funnel (invited -> sent -> registered)
create or replace view public.v_invite_funnel as
select coalesce(tt.label, u.code) as trade, u.code as trade_code,
  count(distinct l.id) as invited,
  count(distinct l.id) filter (where l.invite_status = 'sent') as delivered,
  count(distinct l.id) filter (where l.invite_status = 'bounced') as bounced,
  count(distinct l.id) filter (where coalesce(l.claimed,false)=true or l.registration_status is not null) as registered
from public.leads l,
  lateral unnest(case when cardinality(l.invite_trades)=0 then array['(unclassified)'] else l.invite_trades end) as u(code)
left join public.taxonomy_trade tt on tt.code = u.code
where l.invite_status is not null
group by 1,2;

-- Founder chase list: invited >7 days ago, still no registration (WhatsApp / call / visit)
create or replace view public.v_invite_nonresponders as
select l.id, l.company_name, l.email, coalesce(l.phone_e164, l.phone) as phone,
  l.invite_trades, l.invited_at,
  (now()::date - l.invited_at::date) as days_since_invite
from public.leads l
where l.invite_status in ('sent','queued')
  and coalesce(l.claimed,false) = false
  and l.invited_at is not null
  and l.invited_at < now() - interval '7 days'
order by l.invited_at;

revoke all on public.v_invite_funnel from anon, authenticated;
revoke all on public.v_invite_nonresponders from anon, authenticated;
