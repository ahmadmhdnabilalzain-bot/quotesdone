-- THE RECRUITMENT FUNNEL COUNTS WHAT WAS SENT AND NAMES THE STAGE THAT LOST THEM.
-- Seat: marketing (analytics and attribution). 28 Sep 2026, seat audit gap (marketing.md P2, priority 4):
-- "Recruitment funnel: pool 2,802, invited 54, registered 0" and "marketing_first_touch = 0. CAC/ROI null".
--
-- WHAT WAS MEASURED (production, 28 Sep 2026, read-only)
--   * seat_duty marketing.recruitment_funnel last_result: pool 2,802, invited 54, registered 0, 7 gaps. It reports
--     totals and nothing reasons over them.
--   * leads.invited_at is set on 171 leads (162 'sent', 10 'bounced'; July to 23 Aug, plus 1 ZZ DEMO today).
--     notifications holds 0 rows of type 'supplier_invite' (the outbox starts 7 Sep; the 16 'supplier_invite_seed'
--     rows are test-path sends to mail-tester and the founder, lead_id null). So no invitation counted as "invited"
--     has a delivery record: the invited column is a status, not a send. Since 7 Sep enqueue_supplier_invites holds
--     every batch (supplier_outreach_golive = false, invite_enabled = false; 28 Sep: planned 50, queued 0).
--     WhatsApp invitations: 0.
--   * The invitation link is <site>/<lang>/portal?t=<claim_token>: no UTM. The browser's first-touch capture
--     (src/lib/firstTouch.ts) keeps only a link with utm_source, so a supplier who came from an invitation could
--     never be attributed. marketing_first_touch = 0 rows. Posts are already tagged (70 of 70 cta_url carry
--     utm_source/utm_content), so only invitations lacked a ref.
--
-- WHAT CHANGES
--   1. fn_supplier_invite_link: the invitation link carries utm_source=invite&utm_medium=email&
--      utm_campaign=supplier_invite&utm_content=lead-<id>. fn_supplier_invite_candidates (copied from the canonical
--      the_daily_supplier_list_goes_only_before_a_sending_day_and_a_company_is_invited_once.sql, one line changed)
--      builds its {{link}} through it. The portal link and claim token are unchanged, so a07 still passes.
--   2. fn_marketing_first_touch_record (copied from each_post_is_measured_and_names_the_suppliers_it_brought.sql):
--      when the browser kept no tagged visit but the lead opened its own claim link (leads.invite_clicked_at, set by
--      claim_lookup), the first touch is the invitation. Idempotent: first touch wins (on conflict do nothing).
--   3. fn_marketing_funnel_largest_drop + fn_marketing_funnel_diagnosis: plain SQL. Stages per channel and trade:
--      invited (status) -> sent (outbox row status 'sent') -> delivered (provider_status 'delivered') -> clicked
--      (invite_clicked_at) -> started (claimed) -> registered (registration_submitted_at). Names the stage pair with
--      the largest drop and a rule-based cause and fix. When a channel has >= N invited (app_secrets
--      recruitment_diagnosis_min_invites, default 20) and 0 registered, it is filed to the CEO as a ceo_improvement
--      ('funnel_stage_drop', one per channel, cause and month), which assigns it to marketing.
--   4. fn_marketing_recruitment_funnel (copied from marketing_recruits_where_supply_is_short_and_keeps_the_companys_
--      reputation.sql): its result carries the diagnosis, and it files it.
--   5. ceo_improvement_source_kind_check gains 'funnel_stage_drop' (list copied from
--      the_ceo_turns_the_binding_constraint_into_an_improvement_every_week.sql).
--
-- WHAT THIS DOES NOT DO: it sends nothing and opens no go (the invitation and its release are sales_engineer's and
-- customer_support's, instr 625); it calls no model (the proposed fix is a rule per cause; no narrative is written,
-- so the model hold is not touched); it does not score social posts (fn_marketing_scorecard already attributes
-- registrations to posts through the same first-touch table); CAC stays null because spend is 0 (organic only).

-- ── 1. the invitation link carries its ref ──────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_invite_link(p_site text, p_lang text, p_token uuid, p_lead_id bigint)
returns text
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(nullif(btrim(p_site), ''), 'https://quotesdone.com') || '/' || case when p_lang = 'ar' then 'ar' else 'en' end
         || '/portal?t=' || p_token::text
         || '&utm_source=invite&utm_medium=email&utm_campaign=supplier_invite&utm_content=lead-' || p_lead_id::text
$fn$;
revoke execute on function public.fn_supplier_invite_link(text, text, uuid, bigint) from public, anon, authenticated;

create or replace function public.fn_supplier_invite_candidates(p_limit integer)
returns table (lead_id bigint, to_email text, company_name text, lang text, subject text, body text)
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_site text; v_target int;
  v_subj text; v_body text; v_subj_ar text; v_body_ar text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  select value into v_subj    from app_secrets where key = 'invite_subject';
  select value into v_body    from app_secrets where key = 'invite_body';
  select value into v_subj_ar from app_secrets where key = 'invite_subject_ar';
  select value into v_body_ar from app_secrets where key = 'invite_body_ar';
  -- A template without the link placeholder is the 62-invitations-with-no-way-in failure. Refuse.
  if coalesce(v_body, '') not like '%{{link}}%' then
    raise exception 'app_secrets.invite_body has no {{link}} placeholder: an invitation with no way in is refused';
  end if;
  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_category'),
                       (select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 10);

  -- MATERIALIZED, 4 Aug 2026, and it is load-bearing (see enqueue_supplier_invites' history): both
  -- CTEs are read from a correlated subquery and would otherwise be recomputed per candidate.
  return query
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
  -- ONE COMPANY, ONE INVITATION (24 Sep 2026, marketing). A company is its email domain, unless the domain is
  -- a shared mailbox provider (gmail, emirates.net.ae ...: measured as a domain carrying 3+ different company
  -- names), where it is the address itself; and, independently, its normalised company name.
  shared as materialized (
    select split_part(lower(btrim(l.email)), '@', 2) as dom from leads l where coalesce(btrim(l.email), '') <> ''
    group by 1 having count(distinct lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g'))) >= 3
  ),
  keyed as materialized (
    select l.id,
           case when s.dom is null then split_part(lower(btrim(l.email)), '@', 2) else lower(btrim(l.email)) end as dkey,
           nullif(lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g')), '') as nkey,
           (l.invite_status is not null or l.invited_at is not null or coalesce(l.claimed, false)) as touched
    from leads l left join shared s on s.dom = split_part(lower(btrim(l.email)), '@', 2)
    where coalesce(btrim(l.email), '') <> ''
  ),
  touched_d as materialized (select distinct dkey from keyed where touched),
  touched_n as materialized (select distinct nkey from keyed where touched and nkey is not null),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified,
           l.invite_trades, l.emirate, k.dkey, k.nkey,
           -- Arabic only where the lead's own locale says so AND the Arabic copy exists; otherwise
           -- English, which is also what a04 assumes for an unregistered recipient.
           case when (lower(coalesce(l.locale, '')) like 'ar%' or coalesce(l.company_name, '') ~ '[؀-ۿ]') and coalesce(v_body_ar, '') like '%{{link}}%'   -- the language from the name too (#916, the_supplier_invitation_reads_the_language_from_the_name_and_skips_a_suppressed_address.sql)
                     and coalesce(v_subj_ar, '') <> '' then 'ar' else 'en' end as lang
    from leads l join keyed k on k.id = l.id
    where public.fn_supplier_invite_eligible(l)
      -- a company already invited (bounced, unsubscribed or registered included) is not invited again at another address
      and not exists (select 1 from touched_d t where t.dkey = k.dkey)
      and (k.nkey is null or not exists (select 1 from touched_n t where t.nkey = k.nkey))
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain, c.lang, c.dkey, c.nkey,
      -- 23 Sep 2026 (marketing.recruitment_funnel): a lead in a trade the sales engineer marked for recruitment
      -- (public.supply_gap, status 'recruit') goes first. Trade codes compared for equality; no word is read.
      case when exists (select 1 from public.supply_gap g where g.status = 'recruit' and g.trade = any(coalesce(c.invite_trades, '{}'::text[]))
                          and (g.emirate = 'UAE' or g.emirate = c.emirate)) then 0 else 1 end as target_rank,
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      case when c.email_verified in ('verified','true') then 0 else 1 end as unverified_rank,
      case when split_part(lower(c.email),'@',1) in
             ('info','sales','admin','contact','enquiry','enquiries','inquiry','office','mail',
              'support','hello','marketing','general','accounts','reception','careers','hr')
           then 1 else 0 end as role_rank
    from cand c
  ),
  elig as (
    select r.id, r.email, r.company_name, r.claim_token, r.lang from (
      select p.*,
        case when p.pdomain='~none' then 1 else 0 end as is_none,
        row_number() over (partition by p.pdomain order by p.unverified_rank, p.role_rank, p.id) as rk,
        row_number() over (partition by coalesce(p.email_domain, split_part(p.email,'@',2)) order by p.unverified_rank, p.role_rank, p.id) as domain_rk,
        -- the best contact per company: a verified, named mailbox before info@/sales@ (a role address goes only
        -- when it is the company's only one). ponytail: a lead that wins one key and loses the other waits a day.
        row_number() over (partition by p.dkey order by p.unverified_rank, p.role_rank, p.id) as company_rk,
        row_number() over (partition by coalesce(p.nkey, p.email) order by p.unverified_rank, p.role_rank, p.id) as name_rk
      from prio p
    ) r
    where r.domain_rk <= 5 and r.company_rk = 1 and r.name_rk = 1
    order by r.target_rank, r.is_none, r.rk, r.unverified_rank, r.role_rank, r.pdomain
    limit greatest(coalesce(p_limit, 0), 0)
  )
  select e.id, btrim(e.email), e.company_name, e.lang,
         case when e.lang = 'ar' then v_subj_ar else v_subj end,
         replace(
           replace(case when e.lang = 'ar'
                        then case when coalesce(btrim(e.company_name), '') = ''
                                  then replace(v_body_ar, 'السادة/ {{company}} المحترمين،', 'السادة الكرام،')
                                  else v_body_ar end
                        else v_body end,
                   '{{company}}', coalesce(nullif(btrim(e.company_name),''), case when e.lang = 'ar' then 'الكرام' else 'there' end)),
           '{{link}}', public.fn_supplier_invite_link(v_site, e.lang, e.claim_token, e.id))   -- the ref (this file)
  from elig e;
end
$fn$;
revoke execute on function public.fn_supplier_invite_candidates(integer) from public, anon, authenticated;

-- ── 2. first touch at registration, the invitation when the browser kept none ───────────────────────
create or replace function public.fn_marketing_first_touch_record(p_lead_id bigint, p_touch jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_ok constant text := '^[A-Za-z0-9._-]{1,100}$';
  v_src text; v_med text; v_cmp text; v_cnt text; v_path text; v_at timestamptz; v_post bigint; v_id bigint;
begin
  if p_lead_id is null then
    return jsonb_build_object('ok', true, 'recorded', false, 'reason', 'no lead');
  end if;
  if p_touch is null or jsonb_typeof(p_touch) <> 'object' then p_touch := '{}'::jsonb; end if;
  v_src := nullif(btrim(p_touch->>'utm_source'), '');     if v_src !~ v_ok then v_src := null; end if;
  v_med := nullif(btrim(p_touch->>'utm_medium'), '');     if v_med !~ v_ok then v_med := null; end if;
  v_cmp := nullif(btrim(p_touch->>'utm_campaign'), '');   if v_cmp !~ v_ok then v_cmp := null; end if;
  v_cnt := nullif(btrim(p_touch->>'utm_content'), '');    if v_cnt !~ v_ok then v_cnt := null; end if;
  v_path := nullif(btrim(p_touch->>'landing_path'), '');  if v_path !~ '^/\S{0,200}$' then v_path := null; end if;
  -- THE INVITATION IS A TOUCH EVEN WHEN THE BROWSER KEPT NONE (28 Sep 2026, this file): private mode or a link
  -- opened before the ref existed leaves no tagged visit, but claim_lookup stamps invite_clicked_at when the
  -- lead's own claim link is opened. That is evidence of the invitation, not a status column.
  if v_src is null then
    select 'invite', 'email', 'supplier_invite', 'lead-' || l.id, '/portal', l.invite_clicked_at
      into v_src, v_med, v_cmp, v_cnt, v_path, v_at
      from public.leads l where l.id = p_lead_id and l.invite_clicked_at is not null;
    if v_src is null then
      return jsonb_build_object('ok', true, 'recorded', false, 'reason', 'no valid utm_source and no opened invitation');
    end if;
    p_touch := jsonb_build_object('first_seen_at', v_at);
  end if;
  begin
    v_at := (p_touch->>'first_seen_at')::timestamptz;
    if v_at < now() - interval '400 days' or v_at > now() + interval '1 hour' then v_at := null; end if;
  exception when others then v_at := null;
  end;
  if v_med = 'social' and v_cnt is not null then
    select id into v_post from public.marketing_post where ingest_key = lower(v_cnt);
  end if;
  insert into public.marketing_first_touch (lead_id, utm_source, utm_medium, utm_campaign, utm_content, landing_path, first_seen_at, post_id)
  values (p_lead_id, lower(v_src), v_med, v_cmp, v_cnt, v_path, v_at, v_post)
  on conflict (lead_id) do nothing
  returning id into v_id;
  return jsonb_build_object('ok', true, 'recorded', v_id is not null, 'post_id', v_post);
end
$fn$;
revoke execute on function public.fn_marketing_first_touch_record(bigint, jsonb) from public, anon, authenticated;

-- ── 3. the stage that lost them ──────────────────────────────────────────────────────────────────────────
-- p_stages: {"invited":n,"sent":n,"delivered":n,"clicked":n,"started":n,"registered":n}. The pair with the largest
-- drop (the earliest on a tie) and the rule for it. A rule, not a judgement: each cause is what that pair means.
create or replace function public.fn_marketing_funnel_largest_drop(p_stages jsonb)
returns jsonb
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce((
    select jsonb_build_object('from', s.a, 'to', s.b, 'lost', s.lost, 'cause', s.cause, 'proposed_fix', s.fix)
      from (select a, b, coalesce((p_stages->>a)::int, 0) - coalesce((p_stages->>b)::int, 0) as lost, cause, fix, ord
              from (values
                (1, 'invited', 'sent', 'not_actually_sent',
                 'Leads are marked invited but the outbox holds no sent invitation for them. Count only outbox sends; the batch is released by enqueue_supplier_invites once supplier_outreach_golive and invite_enabled are true.'),
                (2, 'sent', 'delivered', 'bounced_or_undelivered',
                 'Invitations left the outbox but were not delivered. Clean the list (role and dead domains) and check the sending domain before the next batch.'),
                (3, 'delivered', 'clicked', 'no_clicks',
                 'Invitations were delivered but nobody opened the link. Test the subject line, the first sentence and the sender name per trade.'),
                (4, 'clicked', 'started', 'clicks_but_no_start',
                 'Suppliers opened the link but did not claim their company. Walk the portal claim step from the invitation link and shorten it.'),
                (5, 'started', 'registered', 'started_not_finished',
                 'Suppliers claimed but did not submit the registration. Find the form step they stop at and follow up through customer_support.')
              ) v(ord, a, b, cause, fix)) s
     where s.lost > 0
     order by s.lost desc, s.ord
     limit 1),
    jsonb_build_object('from', null, 'to', null, 'lost', 0, 'cause', 'no_drop', 'proposed_fix', null))
$fn$;
revoke execute on function public.fn_marketing_funnel_largest_drop(jsonb) from public, anon, authenticated;

-- Per channel and per (channel, trade). The population is every lead with invited_at (the status); each later stage
-- is measured on its own record. Demo leads only when asked (the probe). p_file: a channel with >= N invited and
-- 0 registered is filed to the CEO as an improvement for marketing, once per channel, cause and month.
create or replace function public.fn_marketing_funnel_diagnosis(p_include_demo boolean default false, p_file boolean default false)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_min int := coalesce((select nullif(btrim(value), '')::int from public.app_secrets where key = 'recruitment_diagnosis_min_invites'), 20);
  v_month text := to_char((now() at time zone 'Asia/Dubai')::date, 'YYYY-MM');
  v_channels jsonb; v_trades jsonb; c record; v_filed jsonb := '[]'::jsonb; v_imp bigint;
begin
  with f as (
    select l.id, coalesce(n.channel, 'email') as channel,
           coalesce(nullif(l.invite_trades, '{}'::text[]), array['unknown']) as trades,
           coalesce(n.sent, false)::int as sent, coalesce(n.delivered, false)::int as delivered,
           (l.invite_clicked_at is not null)::int as clicked, coalesce(l.claimed, false)::int as started,
           (l.registration_submitted_at is not null)::int as registered
      from public.leads l
      left join lateral (
        select max(x.channel) as channel, bool_or(x.status = 'sent') as sent,
               bool_or(x.status = 'sent' and x.provider_status = 'delivered') as delivered
          from public.notifications x where x.lead_id = l.id and x.type = 'supplier_invite') n on true
     where l.invited_at is not null and (p_include_demo or not coalesce(l.is_demo, false))
  ), per_channel as (
    select channel, jsonb_build_object('invited', count(*), 'sent', sum(sent), 'delivered', sum(delivered),
           'clicked', sum(clicked), 'started', sum(started), 'registered', sum(registered)) st
      from f group by channel
  ), per_trade as (
    select f.channel, t.trade, jsonb_build_object('invited', count(*), 'sent', sum(f.sent), 'delivered', sum(f.delivered),
           'clicked', sum(f.clicked), 'started', sum(f.started), 'registered', sum(f.registered)) st
      from f cross join lateral unnest(f.trades) t(trade) group by f.channel, t.trade
  )
  select (select coalesce(jsonb_agg(jsonb_build_object('channel', channel, 'stages', st,
                   'drop', public.fn_marketing_funnel_largest_drop(st)) order by channel), '[]'::jsonb) from per_channel),
         (select coalesce(jsonb_agg(jsonb_build_object('channel', channel, 'trade', trade, 'stages', st,
                   'drop', public.fn_marketing_funnel_largest_drop(st)) order by channel, trade), '[]'::jsonb) from per_trade)
    into v_channels, v_trades;

  if p_file then
    for c in select e from jsonb_array_elements(v_channels) e
              where (e->'stages'->>'invited')::int >= v_min and (e->'stages'->>'registered')::int = 0 loop
      v_imp := public.fn_ceo_improvement_open('funnel_stage_drop',
        (c.e->>'channel') || ':' || (c.e->'drop'->>'cause') || ':' || v_month, 'marketing',
        format('Recruitment by %s: %s invited, 0 registered. The largest drop is %s -> %s (%s lost): %s. %s',
               c.e->>'channel', c.e->'stages'->>'invited', c.e->'drop'->>'from', c.e->'drop'->>'to', c.e->'drop'->>'lost',
               c.e->'drop'->>'cause', c.e->'drop'->>'proposed_fix'),
        jsonb_build_object('stages', c.e->'stages', 'drop', c.e->'drop', 'min_invites', v_min,
                           'source', 'fn_marketing_funnel_diagnosis'));
      v_filed := v_filed || jsonb_build_object('channel', c.e->>'channel', 'improvement_id', v_imp);
    end loop;
  end if;

  return jsonb_build_object('min_invites', v_min, 'channels', v_channels, 'by_trade', v_trades, 'filed', v_filed);
end $fn$;
revoke execute on function public.fn_marketing_funnel_diagnosis(boolean, boolean) from public, anon, authenticated;

-- ── 4. the CEO's improvement kinds gain the funnel ───────────────────────────────────────────────────────
alter table public.ceo_improvement drop constraint if exists ceo_improvement_source_kind_check;
alter table public.ceo_improvement add constraint ceo_improvement_source_kind_check
  check (source_kind in ('recurring_miss', 'month_miss', 'lesson', 'recurring_finding', 'binding_constraint',
                         'marketing_plan_late', 'seat_audit',
                         -- marketing's recruitment funnel with 0 registrations (this file)
                         'funnel_stage_drop'));

-- ── 5. the daily duty carries and files the diagnosis ────────────────────────────────────────────────────

create or replace function public.fn_marketing_recruitment_funnel()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_day date := (now() at time zone 'Asia/Dubai')::date; v_rows int; gp record; v_empty int := 0;
begin
  insert into public.supplier_recruitment_funnel as f (trade, emirate, day, pool, invited, clicked, registered, approved, quoting)
  select g.trade, g.emirate, v_day,
         count(*) filter (where l.invite_status is null and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)),
         count(*) filter (where l.invited_at is not null),
         count(*) filter (where l.invite_clicked_at is not null),
         count(*) filter (where l.registration_submitted_at is not null or coalesce(l.claimed, false)),
         count(*) filter (where l.approval_status = 'approved'),
         count(*) filter (where exists (select 1 from public.quotes q where q.supplier_id = l.id))
    from public.supply_gap g
    left join public.leads l on g.trade = any(coalesce(l.invite_trades, '{}'::text[]))
                            and (g.emirate = 'UAE' or l.emirate = g.emirate) and coalesce(l.is_demo, false) = false
   where g.status = 'recruit'
   group by g.trade, g.emirate
  on conflict (trade, emirate, day) do update set pool = excluded.pool, invited = excluded.invited, clicked = excluded.clicked,
    registered = excluded.registered, approved = excluded.approved, quoting = excluded.quoting;
  get diagnostics v_rows = row_count;

  -- An empty pool is the lead source, not the invitation: marketing's finding, one per gap, closed when it refills.
  for gp in select f.trade, f.emirate, f.pool from public.supplier_recruitment_funnel f
            join public.supply_gap s on s.trade = f.trade and s.emirate = f.emirate and s.status = 'recruit'
           where f.day = v_day loop
    if gp.pool = 0 then
      v_empty := v_empty + 1;
      perform public.fn_it_engineer_finding_upsert('recruitment:pool_empty:' || gp.trade || ':' || gp.emirate,
        'No uninvited lead is left to recruit for ' || gp.trade || ' (' || gp.emirate || ')',
        'public.supplier_recruitment_funnel', 'monitor', 1,
        jsonb_build_object('trade', gp.trade, 'emirate', gp.emirate, 'owner_seat', 'marketing'), '{}'::text[],
        array['which source can supply leads for this trade while lead scraping is paused'], 'marketing');
    else
      update public.it_engineer_finding set closed_at = now(), close_note = 'the pool has leads again'
       where issue_key = 'recruitment:pool_empty:' || gp.trade || ':' || gp.emirate and closed_at is null;
    end if;
  end loop;
  update public.it_engineer_finding fi set closed_at = now(), close_note = 'the gap is no longer being recruited for'
   where fi.issue_key like 'recruitment:pool_empty:%' and fi.closed_at is null
     and not exists (select 1 from public.supply_gap s where s.status = 'recruit' and 'recruitment:pool_empty:' || s.trade || ':' || s.emirate = fi.issue_key);

  return jsonb_build_object('gaps_recruiting', v_rows, 'empty_pools', v_empty,
    'totals', (select jsonb_build_object('pool', sum(pool), 'invited', sum(invited), 'registered', sum(registered), 'approved', sum(approved), 'quoting', sum(quoting))
                 from public.supplier_recruitment_funnel where day = v_day),
    -- which stage lost them, filed to the CEO when a channel has N invited and 0 registered (this file)
    'diagnosis', public.fn_marketing_funnel_diagnosis(false, true));
end $fn$;
revoke execute on function public.fn_marketing_recruitment_funnel() from public, anon, authenticated;
grant execute on function public.fn_marketing_recruitment_funnel() to service_role;

