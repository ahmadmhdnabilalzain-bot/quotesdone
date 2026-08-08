-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727085058   name: deliverability_guardrails
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ================================================================
-- Deliverability guardrails, 27 Jul 2026.
-- Context: the domain has sent ~113 emails ever and holds 27 hard bounces,
-- all of them self-inflicted qa.*@quotesdone.com addresses that do not exist.
-- 19,897 leads carry an email; 16,734 of them have no verification signal at all.
-- Raising the invite cap against that list is how a sending domain gets suspended.
-- ================================================================

-- 1. Stop the QA suite bouncing mail at our own domain. These addresses do not exist,
--    and every send to them is a hard bounce recorded against our sending reputation.
insert into public.email_suppressions (email, reason, source)
select distinct lower(l.email), 'blocked: nonexistent qa mailbox pattern', 'guardrail'
from (values ('qa.placeholder@quotesdone.com')) as l(email)
on conflict do nothing;

create table if not exists public.email_block_pattern (
  id      bigserial primary key,
  pattern text not null unique,
  reason  text not null,
  active  boolean not null default true
);

insert into public.email_block_pattern (pattern, reason) values
('^qa[.]', 'QA harness addresses at our own domain that have no mailbox. Every send is a hard bounce against our own reputation. Point the QA suite at a real seed mailbox or a provider simulator address instead.'),
('^(no-?reply|do-?not-?reply|postmaster|abuse|spam|bounce)@', 'Unattended or abuse-handling mailboxes. Sending outreach here produces complaints, not suppliers.'),
('example[.](com|org|net)$', 'Reserved documentation domains. Guaranteed bounce.'),
('[.](test|invalid|localhost|local)$', 'Reserved TLDs. Guaranteed bounce.')
on conflict (pattern) do update set reason = excluded.reason;

create or replace function public.fn_email_sendable(p_email text)
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare v_e text; v_pat record;
begin
  v_e := lower(btrim(coalesce(p_email,'')));
  if v_e = '' then
    return jsonb_build_object('ok', false, 'reason', 'no address');
  end if;
  if v_e !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$' then
    return jsonb_build_object('ok', false, 'reason', 'not a valid address shape');
  end if;
  if exists (select 1 from email_suppressions s where lower(s.email) = v_e) then
    return jsonb_build_object('ok', false, 'reason', 'suppressed');
  end if;
  for v_pat in select pattern, reason from email_block_pattern where active loop
    if v_e ~ v_pat.pattern then
      return jsonb_build_object('ok', false, 'reason', v_pat.reason);
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'reason', 'sendable');
end; $fn$;

revoke execute on function public.fn_email_sendable(text) from anon, authenticated, public;

-- 2. A view that tells the truth about sending health, so the cap decision is evidence-led.
create or replace view public.v_deliverability as
with sent as (
  select count(*) filter (where invited_at is not null)                                as invites_ever,
         count(*) filter (where invited_at > now() - interval '1 day')                 as invites_24h,
         count(*) filter (where invited_at > now() - interval '3 days')                as invites_3d,
         count(*) filter (where invited_at > now() - interval '7 days')                as invites_7d,
         count(*) filter (where invite_status='bounced')                               as bounced_ever,
         count(*) filter (where invite_status='bounced' and invited_at > now() - interval '3 days') as bounced_3d,
         count(*) filter (where invite_status='bounced' and invited_at > now() - interval '7 days') as bounced_7d
  from leads
),
list as (
  select count(*) filter (where coalesce(trim(email),'') <> '')                        as with_email,
         count(*) filter (where email_verified in ('verified','true'))                 as verified,
         count(*) filter (where coalesce(trim(email),'') <> '' and email_verified is null) as unverified,
         count(*) filter (where coalesce(trim(email),'') <> ''
                            and not (email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$')) as malformed
  from leads
)
select
  (select nullif(value,'')::int from app_secrets where key='invite_daily_cap')            as cap_today,
  (select value from app_secrets where key='invite_enabled')                              as invites_enabled,
  s.invites_ever, s.invites_24h, s.invites_3d, s.invites_7d,
  s.bounced_ever, s.bounced_3d, s.bounced_7d,
  case when s.invites_3d > 0 then round(100.0*s.bounced_3d/s.invites_3d,1) end            as bounce_pct_3d,
  case when s.invites_7d > 0 then round(100.0*s.bounced_7d/s.invites_7d,1) end            as bounce_pct_7d,
  (select count(*) from email_suppressions)                                               as suppressed_total,
  (select count(*) from email_suppressions where email ~ '^qa[.]')                        as suppressed_self_inflicted,
  l.with_email, l.verified, l.unverified, l.malformed,
  case
    when (select value from app_secrets where key='invite_enabled') <> 'true' then 'PAUSED'
    when s.invites_3d >= 15 and s.bounced_3d::numeric/greatest(s.invites_3d,1) > 0.08 then 'OVER LIMIT - should be paused'
    when s.invites_7d >= 20 and s.bounced_7d::numeric/greatest(s.invites_7d,1) >= 0.05 then 'ELEVATED - ramp will throttle'
    when s.invites_ever < 50 then 'WARMING - too little history to judge'
    else 'HEALTHY'
  end as state
from sent s, list l;

-- 3. Close the gap where the auto-pause cannot fire during the fragile early ramp.
--    The old rule needed 50 invites in 3 days; at 10/day that is unreachable, so the
--    safety net was off exactly when the domain was most vulnerable.
create or replace function public.enqueue_supplier_invites(p_cap integer DEFAULT NULL::integer)
returns integer
language plpgsql security definer set search_path to 'public'
as $function$
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

  -- Rate rule, now reachable at low volume.
  if v_inv_recent >= 15 and v_rate > v_max_rate then
    v_pause := true;
    v_why := 'bounce rate '||(v_rate*100)||'% over 3 days ('||v_bounced_recent||'/'||v_inv_recent||') exceeds the '||(v_max_rate*100)||'% limit';
  end if;
  -- Absolute rule: a handful of hard bounces is a bad list, whatever the percentage says.
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

  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 5);

  with activated as (
    select code, count(distinct l.id) ct from leads l, lateral unnest(l.invite_trades) code
    where coalesce(l.claimed,false) = true group by code
  ),
  under as (
    select t.code from taxonomy_trade t left join activated a on a.code = t.code
    where t.active and coalesce(a.ct,0) < v_target
  ),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.invite_trades, l.email_domain, l.email_verified
    from leads l
    where l.email is not null and l.email <> '' and l.invite_status is null
      and coalesce(l.source,'') <> 'self_registered' and coalesce(l.claimed,false) = false
      -- every address must pass the sendability check: shape, suppression list, block patterns
      and (public.fn_email_sendable(l.email)->>'ok')::boolean
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.email_domain,
      coalesce((select u.code from under u where u.code = any(c.invite_trades) limit 1), '~none') as ptrade,
      -- a verified address goes first; an unverified one is the risk we are managing
      case when c.email_verified in ('verified','true') then 0 else 1 end as unverified_rank
    from cand c
  ),
  elig as (
    select id, email, company_name from (
      select id, email, company_name, ptrade, unverified_rank,
        case when ptrade='~none' then 1 else 0 end as is_none,
        row_number() over (partition by ptrade order by unverified_rank, id) as rk,
        -- never send more than 5 invites to one recipient domain in a single run:
        -- concentrated volume at one mail host is what trips rate limits and blocklists
        row_number() over (partition by coalesce(email_domain, split_part(email,'@',2)) order by unverified_rank, id) as domain_rk
      from prio
    ) r
    where domain_rk <= 5
    order by unverified_rank, is_none, rk, ptrade
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

revoke execute on function public.enqueue_supplier_invites(integer) from anon, authenticated, public;

alter table public.email_block_pattern enable row level security;
