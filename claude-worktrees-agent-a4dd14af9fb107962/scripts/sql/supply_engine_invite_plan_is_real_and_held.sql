-- THE INVITE PLAN IS REAL, AND THE SEND IS HELD (3 Sep 2026).
--
-- What the scorer found (s26-recommend-onboarding): 0 invitations sent in 7 days against 0 planned,
-- newest invite_schedule row 15 Aug, cron last ok "never". Two causes, both here:
--
--   1. enqueue_supplier_invites returned before planning anything whenever invite_enabled was not
--      'true', so a held campaign left no invite_schedule row at all — "0 planned" was not a plan of
--      zero, it was the absence of a plan. Now the day's batch is planned FIRST, from the ramp's cap
--      and the pool that can actually be written to (a never-invited lead with an email that is not
--      self-registered or claimed), and only then does the gate decide whether it is sent. A held day
--      is a row with status 'pending' and the reason in `note`; an open day is 'approved'.
--      invite_schedule.planned stays what the scorer says it is — an intention — and `sent` is only
--      ever moved by a queued invitation.
--
--   2. The cron (supplier_invites_daily, job 2) was stood down on 16 Aug. It is re-enabled through
--      the kernel in supply_engine_crons_run_through_the_kernel.sql. Measured before this file:
--      app_secrets.invite_enabled was 'true' and invite_daily_cap 50 — so re-enabling the cron alone
--      would have queued 50 real invitations at 09:00 UTC and email_cron would have sent them two
--      minutes later. The founder alone gives the go for real invites, so this file closes the gate:
--      invite_enabled := 'false'. His go is `update app_secrets set value = 'true' where key =
--      'invite_enabled'` (or approving an invite_campaign_week action in the OS, which
--      fn_invite_week_activate turns into the same write); the next 09:00 tick then sends the
--      planned batch and every 'pending' schedule day from today on flips to 'approved'.
--
-- The candidate ordering, the bounce brake, the per-domain cap and the role-address ranking are
-- unchanged from the 12 Aug version; only the order of plan and gate moved.
--
--   node scripts/apply_sql.mjs scripts/sql/supply_engine_invite_plan_is_real_and_held.sql --apply --ddl

update public.app_secrets set value = 'false' where key = 'invite_enabled' and value = 'true';

create or replace function public.enqueue_supplier_invites(p_cap integer DEFAULT NULL::integer)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare v_site text;
  v_today date := (now() at time zone 'UTC')::date;
  v_planned int; v_used int; v_remaining int; v_subj text; v_body text; v_count int;
  v_inv_recent int; v_bounced_recent int; v_rate numeric; v_max_rate numeric; v_target int; v_cap int;
  v_pause boolean := false; v_why text; v_go boolean; v_pool int;
  v_hol_name text; v_hol_action text; v_hol_end date;
begin
  -- THE CALENDAR THE COMPANY KEEPS ABOUT ITSELF. Checked before anything is planned or written, so
  -- a frozen day leaves no invite_schedule row claiming it planned sends it never made.
  select c.event_name, c.action, c.ends_on into v_hol_name, v_hol_action, v_hol_end
    from public.company_calendar c
   where c.kind = 'public_holiday'
     and v_today between c.starts_on and coalesce(c.ends_on, c.starts_on)
   order by c.starts_on limit 1;
  if v_hol_name is not null then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'calendar_paused', true, 'resumes_on', coalesce(v_hol_end, v_today) + 1),
            'Invites held: company_calendar has "' || v_hol_name || '" covering today. Its recorded action: '
            || coalesce(v_hol_action, '(none recorded)'), now(), now());
    return 0;
  end if;

  -- THE PLAN, before the gate. The batch is the ramp's cap bounded by the pool that can be written
  -- to today; the row says whether the day is open or held and why.
  v_go  := coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') = 'true';
  v_cap := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), 10);
  select count(*) into v_pool from leads l
   where l.email is not null and l.email <> '' and l.invite_status is null
     and coalesce(l.source,'') <> 'self_registered' and coalesce(l.claimed,false) = false
     and coalesce(l.banned,false) = false;
  v_planned := least(coalesce(p_cap, v_cap), v_cap, v_pool);
  insert into invite_schedule(day, planned, status, note)
  values (v_today, greatest(v_planned, 0),
          case when v_go then 'approved' else 'pending' end,
          'batch of ' || greatest(v_planned, 0) || ' from a pool of ' || v_pool || ' never-invited lead(s) with an email, cap ' || v_cap
          || case when v_go then '; sending open' else '; HELD — real invitations wait for the founder''s go (app_secrets.invite_enabled)' end)
    on conflict (day) do update
      set planned = excluded.planned, status = excluded.status, note = excluded.note;

  if not v_go then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'planned', greatest(v_planned, 0), 'pool', v_pool, 'cap', v_cap, 'held', true),
            'Invites planned and HELD: ' || greatest(v_planned, 0) || ' of a pool of ' || v_pool
            || ' would be queued at cap ' || v_cap || '; invite_enabled is false, so nothing was written to the outbox.', now(), now());
    return 0;
  end if;
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
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; auto-paused: ' || v_why where day = v_today;
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
  insert into agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('supplier_invites', 'ok',
          jsonb_build_object('queued', v_count, 'planned', v_planned, 'pool', v_pool, 'cap', v_cap, 'held', false),
          'Invites: ' || v_count || ' queued of ' || v_planned || ' planned (pool ' || v_pool || ', cap ' || v_cap || ').', now(), now());
  return v_count;
end;
$function$;
