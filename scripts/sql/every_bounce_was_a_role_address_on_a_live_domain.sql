-- Every bounce was a role address on a live domain
-- ================================================
--
-- The brief set the order as: prove the registration path, cull the list, then ramp small and halt
-- at the brake — and asked for a number if bounce is still over 8% after the cull. This is that
-- number, and it says the cull does not touch the problem.
--
-- The MX sweep removed 1,566 leads across 1,402 domains that do not accept mail at all. Real value,
-- and every one of them a certain bounce. But of the five invitations that HAVE bounced:
--
--     info@cbce.ae          MX present    scraper said email_verified
--     info@clgme.com        MX present    scraper said email_verified
--     support@oscend.com    MX present    scraper said email_verified
--     info@smecmarine.com   MX present    scraper said email_verified
--     info@uiscllc.com      MX present    scraper said email_verified
--
-- Five of five are ROLE ADDRESSES on domains with live MX, and all five were flagged verified by
-- the scrape. So: the cull prevents none of them, and leads.email_verified is not evidence of
-- deliverability. These are mailbox-level failures, and an MX lookup is a domain-level test.
--
--     role addresses      58 invited   5 bounced   8.6%
--     personal addresses   4 invited   0 bounced   n=4, too small to compare against
--
-- The brief's own reading was "role addresses are a conversion problem, not a bounce problem".
-- On the only evidence there is, they are both — though four personal sends prove nothing about
-- personal addresses, and this file does not claim they do.
--
-- WHAT THIS CHANGES, and what it deliberately does not. It does not delete role addresses: the
-- brief is right that in UAE B2B info@ is often the only published address, and 5,870 of 19,835
-- eligible leads have no other. It DEPRIORITISES them, which is what the brief asked for. The
-- ordering already ranked unverified addresses last; a role address now sorts behind a personal one
-- at the same verification rank, so a run reaches named human beings first and only works down to
-- the shared inboxes when it runs out of them.
--
-- invite_enabled STAYS FALSE. Turning it on is the founder's call: the measured rate is 8.6% on
-- role addresses against an 0.08 brake, no measurement yet predicts the culled list's rate, and the
-- 3-day brake window is currently empty (0 invited in 3 days) so the auto-pause would not catch a
-- bad run until 15 had gone out. The cheap next test is an SMTP RCPT probe, which is free but
-- connects to third-party mail servers and can itself cost sender reputation — a reputation
-- decision, not an engineering one.

create or replace function public.enqueue_supplier_invites(p_cap integer default null)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_site text;
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

  select coalesce(nullif(btrim(value),''), 'https://quotesdone.com') into v_site
    from app_secrets where key='public_site_url';
  select value into v_subj from app_secrets where key='invite_subject';
  select value into v_body from app_secrets where key='invite_body';
  select count(*) into v_used from notifications where type='supplier_invite' and (created_at at time zone 'UTC')::date = v_today;
  v_remaining := greatest(0, v_planned - v_used);
  if v_remaining <= 0 then return 0; end if;

  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_category'),
                       (select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 10);

  -- MATERIALIZED, 4 Aug 2026, and it is load-bearing. Both CTEs are referenced exactly once, from
  -- inside the correlated subquery in `prio`. Without this keyword Postgres inlines them there and
  -- re-runs the whole leads x lead_subcategory aggregate once per candidate - 19,632 times, twice
  -- over, ~220 s against a 120 s timeout. Neither depends on the outer row, so computing them once
  -- is semantically identical and 54x faster. Do not remove.
  with activated as materialized (
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
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified
    from leads l
    where l.email is not null and l.email <> '' and l.invite_status is null
      and coalesce(l.source,'') <> 'self_registered' and coalesce(l.claimed,false) = false
      and (public.fn_email_sendable(l.email)->>'ok')::boolean
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain,
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      case when c.email_verified in ('verified','true') then 0 else 1 end as unverified_rank,
      -- ROLE ADDRESSES LAST (12 Aug 2026). All five bounces to date are role addresses on domains
      -- with live MX, every one flagged email_verified by the scrape, so neither the MX cull nor
      -- that flag protects against them. Not excluded: 5,870 of 19,835 eligible leads publish no
      -- other address and dropping them would drop the supplier. Ranked behind a named human at the
      -- same verification rank, so a run reaches people first and works down to shared inboxes only
      -- when it runs out of them.
      case when split_part(lower(c.email),'@',1) in
             ('info','sales','admin','contact','enquiry','enquiries','inquiry','office','mail',
              'support','hello','marketing','general','accounts','reception','careers','hr')
           then 1 else 0 end as role_rank
    from cand c
  ),
  elig as (
    select id, email, company_name, claim_token from (
      select id, email, company_name, claim_token, pdomain, unverified_rank, role_rank,
        case when pdomain='~none' then 1 else 0 end as is_none,
        row_number() over (partition by pdomain order by unverified_rank, role_rank, id) as rk,
        row_number() over (partition by coalesce(email_domain, split_part(email,'@',2)) order by unverified_rank, role_rank, id) as domain_rk
      from prio
    ) r
    where domain_rk <= 5
    order by is_none, rk, unverified_rank, role_rank, pdomain
    limit v_remaining
  ),
  ins as (
    insert into notifications(type,to_email,to_role,lead_id,subject,body,status,created_at)
    select 'supplier_invite', email, 'supplier', id, v_subj,
           replace(
             replace(v_body, '{{company}}', coalesce(nullif(btrim(company_name),''), 'there')),
             '{{link}}', v_site || '/en/portal?t=' || claim_token::text), 'queued', now()
    from elig returning to_email
  )
  update leads set invite_status='queued', invited_at=now()
  where invite_status is null and lower(email) in (select lower(to_email) from ins);
  get diagnostics v_count = row_count;
  update invite_schedule set sent = sent + v_count where day = v_today;
  return v_count;
end;
$function$;
