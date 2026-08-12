-- enqueue_supplier_invites: the absolute bounce trip now scales with the ramp.
--
-- fn_invite_ramp doubles invite_daily_cap while the list behaves - base 10, ceiling 200, staged on
-- lifetime volume. The hard auto-pause beside it was a flat count: five hard bounces in three days,
-- "regardless of rate". At today's cap that is 5/30 = 17% and firing is right. At the ceiling it is
-- 5/600 = 0.8% and firing is wrong - it would switch invite_enabled to false, and supply is the
-- binding constraint on AED 1M with 1 confirmed supplier against 20,470 leads.
--
-- A threshold calibrated for one volume that is never re-read at another is the same defect as a
-- number measuring something other than what its name says: it does not fail, it misfires. The trip
-- is now whichever is larger - five bounces, or invite_max_bounce_rate applied to what was actually
-- sent in the window. Below ~100 sends in three days that is still exactly 5, so nothing about
-- today's behaviour changes; above it the rate test (which needs 15 sends) is stricter and governs.
--
-- Everything else in this definition is byte-identical to what production ran on 12 Aug 2026.
CREATE OR REPLACE FUNCTION public.enqueue_supplier_invites(p_cap integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  -- SCALES WITH THE RAMP (12 Aug 2026). See the header: five was right at a cap of ten and wrong at
  -- two hundred. greatest() ignores nulls, so both arms are non-null by construction.
  if not v_pause and v_bounced_recent >= greatest(5, ceil(v_inv_recent * v_max_rate)::int) then
    v_pause := true;
    v_why := v_bounced_recent||' hard bounces in 3 days against '||v_inv_recent||' sent. Regardless of rate, that is a list-quality problem';
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
