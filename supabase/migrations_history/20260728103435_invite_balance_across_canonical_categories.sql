-- WHY. enqueue_supplier_invites already round-robins across trades, but it balanced over
-- taxonomy_trade - 25 coarse codes - and read each lead's trades from leads.invite_trades, which was
-- populated for only 9,685 of 20,464 leads. Every one of the other 10,779 fell into the single
-- '~none' bucket, so the round-robin had nothing to rotate over and a run could spend the whole daily
-- cap inside one trade. That is the "a whole day of emailing only fit-out suppliers" failure.
--
-- WHAT CHANGES. Balancing now runs over catalog_domains (67), the canonical taxonomy, using the
-- lead_subcategory classification, which covers 80.1% of leads instead of 47%. Everything protecting
-- deliverability is untouched: the bounce-rate pause, the absolute hard-bounce rule, fn_email_sendable,
-- and the max-5-per-recipient-domain rule all behave exactly as before.

-- Keep invite_trades populated too, so the column stays meaningful for anything else reading it
-- (backup, resend_webhook) and so a human can see a lead's categories without a join.
update leads l
set invite_trades = sub.domains
from (
  select lead_id, array_agg(distinct domain_slug order by domain_slug) as domains
  from lead_subcategory group by lead_id
) sub
where sub.lead_id = l.id
  and (l.invite_trades is distinct from sub.domains);

create or replace function public.enqueue_supplier_invites(p_cap integer default null)
returns integer
language plpgsql
security definer
set search_path to 'public'
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

  with activated as (
    -- suppliers who actually came on board, counted per canonical domain
    select ls.domain_slug, count(distinct l.id) ct
    from leads l join lead_subcategory ls on ls.lead_id = l.id
    where coalesce(l.claimed,false) = true
    group by ls.domain_slug
  ),
  under as (
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

insert into app_secrets (key, value) values ('invite_target_per_category','10')
on conflict (key) do update set value = excluded.value;

select (select count(*) from leads where invite_trades is not null and cardinality(invite_trades)>0) leads_with_categories,
       (select count(distinct d) from leads l, lateral unnest(l.invite_trades) d) distinct_categories_in_play;