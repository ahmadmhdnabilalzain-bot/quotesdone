-- THE COMPANY RESEARCHED ITS OWN OPERATING CALENDAR AND NOTHING READS IT.
--
-- 13 Aug 2026. public.company_calendar holds 55 hand-researched, sourced and dated rows — UAE
-- public holidays, trade shows, compliance deadlines, seasonality — each carrying an `affects`
-- paragraph, an `action` instruction, an owner department, a source_url and a verified_at. It is
-- read by NO routine, NO view, NO edge function and NO file in src/. Measured by scanning every
-- prosrc and viewdef in public for the table name and grepping the repo: zero hits.
--
-- Row 1 is Mawlid, 25 Aug 2026, and its action reads verbatim:
--
--     "Do not launch campaigns or invite pushes 22-27 Aug."
--
-- Twelve days out, and earlier in this same session the invite ramp's daily cap was raised from 10
-- to 20 on the founder's own crossed-threshold rule. Nothing would have stopped enqueue_supplier_invites
-- pushing twenty cold invitations a day straight through a window the company had already written
-- down as a national shutdown — because the only thing that knew was a table with no reader.
--
-- ── WHAT IS ENCODED, AND WHAT DELIBERATELY IS NOT ──────────────────────────────────────────────
-- The pause fires on days inside [starts_on, ends_on] for kind='public_holiday'. That span is what
-- the calendar states as FACT. The wider guidance — "22-27 Aug", "freeze 1-6 Dec", "hard freeze
-- 8-16 Mar" — lives in the `action` prose, and parsing prose into dates would be inventing data.
-- So the machine acts on the dates it can trust, and the row's own `action` text is carried
-- verbatim into the agent_runs note and the founder's brief, where a human reads it. That split is
-- the point: a narrower automatic pause plus the full human instruction beats a clever parser that
-- is confidently wrong about one date in fifty-five.
--
-- Self-clearing by construction. It does NOT flip app_secrets.invite_enabled — that is the bounce
-- auto-pause's mechanism and it requires a human to re-enable. A holiday must resume on its own.
--
-- Nine public_holiday rows are in scope today, the first on 2026-08-25.
create or replace function public.enqueue_supplier_invites(p_cap integer default null::integer)
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
  v_hol_name text; v_hol_action text; v_hol_end date;
begin
  if coalesce((select value from app_secrets where key='invite_enabled'),'false') <> 'true' then return 0; end if;

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
