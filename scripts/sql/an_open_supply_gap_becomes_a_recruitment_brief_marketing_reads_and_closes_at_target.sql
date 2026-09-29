-- Seat: sales_engineer. Reader: marketing.
--
-- GAP (measured 28 Sep 2026, production): 199 supply_gap rows were open (142 open, 50 deciding,
-- 7 recruit), none had ever been closed, and no recruitment brief reached marketing: a gap moved to
-- 'recruit' only changed a status column that nothing on the marketing side reads. marketing has no
-- recruitment tracker of its own (grep marketing/recruit/tracker finds supplier_recruitment_funnel,
-- a 7-row daily funnel, and marketing_prospect, which is customer outreach), so the list below IS
-- the handoff and marketing is its reader.
--
-- WHAT THIS DOES, once a day, called at the end of the existing sales_engineer.supply_gap duty
-- (fn_sales_engineer_supply_gap, redefined below with that one call added):
--   1. every gap already in 'recruit' gets (or refreshes) one row in supply_recruitment_brief: trade,
--      emirate, supply vs target, invited and registered counts from leads, priority, suggested
--      sourcing. Gaps still 'open' are PROMOTED at most p_daily_new (default 10) per Dubai day, best
--      rank first: a waiting customer, then 90-day demand, then the largest uninvited lead pool
--      (marketing can act on it today), then the largest shortfall. 'deciding' and 'deferred' stay
--      with the reasoning that owns that judgement;
--   2. the gap moves to 'recruit' and carries brief_id, the row marketing reads;
--   3. when matchable reaches target the gap and its brief row are closed.
-- WHY THE DAILY CAP (review of #996): without it the first run flipped all ~150 open gaps to
-- 'recruit' in one tick (measured by the aborted probe, 28 Sep 2026), and the marketing funnel then
-- filed one recruitment:pool_empty finding per gap. The funnel is redefined below to file ONE
-- finding per trade group (taxonomy_trade.group_code, 12 groups live) instead.
-- Demo rows: a trade code starting 'zz_demo' counts only demo leads; every other trade counts only
-- real leads, so a ZZ DEMO fixture can never inflate a real brief.

create table if not exists public.supply_recruitment_brief (
  id                   bigserial primary key,
  trade                text not null,
  emirate              text not null,
  matchable            int  not null,
  target               int  not null,
  shortfall            int  not null,
  invited              int  not null default 0,
  registered           int  not null default 0,
  demand_90d           int  not null default 0,
  short_open           int  not null default 0,
  uninvited_pool       int  not null default 0,
  priority             text not null check (priority in ('P1', 'P2', 'P3')),
  suggested_sourcing   text not null,
  status               text not null default 'open' check (status in ('open', 'closed')),
  owner_seat           text not null default 'marketing',
  listed_at            timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  read_by_marketing_at timestamptz,
  closed_at            timestamptz,
  unique (trade, emirate)
);
alter table public.supply_recruitment_brief enable row level security;
drop policy if exists supply_recruitment_brief_service_role_only on public.supply_recruitment_brief;
create policy supply_recruitment_brief_service_role_only on public.supply_recruitment_brief
  as permissive for all to public using (false) with check (false);
revoke all on public.supply_recruitment_brief from anon, authenticated;

alter table public.supply_gap add column if not exists brief_id bigint references public.supply_recruitment_brief(id);

create or replace function public.fn_sales_engineer_supply_gap_to_recruitment_brief(p_daily_new integer default 10)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_listed int; v_moved int; v_closed int; v_budget int;
  v_day_start timestamptz := date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai';
begin
  -- Close first: a gap at target is not recruited for.
  update public.supply_gap set status = 'closed', closed_at = now() where status <> 'closed' and matchable >= target;
  update public.supply_recruitment_brief b set status = 'closed', closed_at = now(), updated_at = now()
    from public.supply_gap g
   where b.status = 'open' and g.trade = b.trade and g.emirate = b.emirate and g.status = 'closed';
  get diagnostics v_closed = row_count;

  -- Today's promotions so far: a second run on the same day spends what is left, never a fresh 10.
  v_budget := greatest(0, coalesce(p_daily_new, 10) - (select count(*) from public.supply_gap
                where decided_by = 'sales_engineer:recruitment_brief' and decided_at >= v_day_start)::int);

  with pick as (
    select g.trade, g.emirate from public.supply_gap g where g.status = 'recruit' and g.matchable < g.target
    union all
    (select g.trade, g.emirate from public.supply_gap g where g.status = 'open' and g.matchable < g.target
      order by (g.short_open > 0) desc, (g.demand_90d > 0) desc, g.uninvited_pool desc, g.target - g.matchable desc, g.trade, g.emirate
      limit v_budget)
  ), gl as (
    select g.*,
           (select count(*) from public.leads l
             where g.trade = any(l.invite_trades) and l.invited_at is not null
               and coalesce(l.is_demo, false) = (g.trade like 'zz_demo%')
               and (g.emirate = 'UAE' or l.emirate = g.emirate))::int as invited,
           (select count(*) from public.leads l
             where g.trade = any(l.invite_trades) and (l.registration_submitted_at is not null or coalesce(l.claimed, false))
               and coalesce(l.is_demo, false) = (g.trade like 'zz_demo%')
               and (g.emirate = 'UAE' or l.emirate = g.emirate))::int as registered
      from public.supply_gap g join pick using (trade, emirate)
  )
  insert into public.supply_recruitment_brief as b (trade, emirate, matchable, target, shortfall, invited, registered,
         demand_90d, short_open, uninvited_pool, priority, suggested_sourcing)
  select trade, emirate, matchable, target, target - matchable, invited, registered, demand_90d, short_open, uninvited_pool,
         case when short_open > 0 then 'P1' when demand_90d > 0 then 'P2' else 'P3' end,
         -- ponytail: 20 invitations per registration is a planning ratio; swap in the measured funnel rate once it has volume.
         case when uninvited_pool >= (target - matchable) * 20 then 'invite from the existing lead pool'
              when uninvited_pool > 0 then 'invite the lead pool, then source new leads (trade directories, chambers of commerce, LinkedIn)'
              else 'source new leads: trade directories, chambers of commerce, LinkedIn, trade exhibitions' end
    from gl
  on conflict (trade, emirate) do update set matchable = excluded.matchable, target = excluded.target, shortfall = excluded.shortfall,
    invited = excluded.invited, registered = excluded.registered, demand_90d = excluded.demand_90d, short_open = excluded.short_open,
    uninvited_pool = excluded.uninvited_pool, priority = excluded.priority, suggested_sourcing = excluded.suggested_sourcing,
    status = 'open', closed_at = null, updated_at = now();
  get diagnostics v_listed = row_count;

  -- Only brief rows this call wrote (updated_at = now(), the transaction start) move a gap, so an
  -- 'open' gap outside today's pick keeps waiting. A promotion is stamped with this routine's name
  -- and time, which is exactly what the budget above counts.
  update public.supply_gap g set status = 'recruit', brief_id = b.id,
         decided_by = case when g.status = 'open' then 'sales_engineer:recruitment_brief'
                           else coalesce(g.decided_by, 'sales_engineer:recruitment_brief') end,
         decided_at = case when g.status = 'open' then now() else coalesce(g.decided_at, now()) end
    from public.supply_recruitment_brief b
   where b.trade = g.trade and b.emirate = g.emirate and b.status = 'open' and b.updated_at = now()
     and g.status in ('open', 'recruit')
     and (g.status <> 'recruit' or g.brief_id is distinct from b.id);
  get diagnostics v_moved = row_count;

  return jsonb_build_object('listed', v_listed, 'moved_to_recruit', v_moved, 'closed', v_closed, 'promotion_budget', v_budget);
end $fn$;
revoke execute on function public.fn_sales_engineer_supply_gap_to_recruitment_brief(integer) from public, anon, authenticated;

-- The daily duty, as live on 28 Sep 2026 (pg_get_functiondef), with ONE change: it ends by calling
-- the brief routine and reports what it did under 'recruitment_brief'.
create or replace function public.fn_sales_engineer_supply_gap(p_reason_limit integer default 10)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_target int := coalesce((select category_open_min_suppliers from public.pricing_config order by id limit 1), 10);
  g record; v_filed int := 0; v_rule int; v_closed int; v_reopened int; v_month text := to_char(now(), 'YYYY-MM');
  v_emirates text[] := array['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'];
  v_brief jsonb;
begin
  with sup as materialized (   -- every matchable supplier with his trades and the emirates he states (none stated = UAE-wide)
    select sc.supplier_id, sc.trades,
           array(select distinct lower(btrim(e)) from unnest(coalesce(sc.coverage_emirates, '{}'::text[]) || coalesce(l.service_emirates, '{}'::text[])) e
                  where nullif(btrim(e), '') is not null) as stated
      from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id
     where sc.confirmed_at is not null
       and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
  ), inq as materialized (
    select i.id, i.emirate, i.trades, i.created_at,
           (i.created_at > now() - interval '30 days' and i.status not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
            and (select count(*) from public.quotes q where q.inquiry_id = i.id) < 3) as short
      from public.inquiries i where i.created_at > now() - interval '90 days'
  ), pool as materialized (
    select t, l.emirate, count(*) as n from public.leads l, unnest(l.invite_trades) t
     where l.invite_status is null and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)
       and coalesce(l.is_demo, false) = false
     group by t, l.emirate
  ), keys as (
    select tt.code as trade, 'UAE'::text as emirate from public.taxonomy_trade tt where tt.active
    union
    select distinct t, i.emirate from inq i, unnest(i.trades) t
     where i.emirate = any(v_emirates) and t in (select code from public.taxonomy_trade where active)
  ), m as (
    select k.trade, k.emirate,
           (select count(*) from sup s where k.trade = any(s.trades)
             and (k.emirate = 'UAE' or cardinality(s.stated) = 0 or lower(k.emirate) = any(s.stated)))::int as matchable,
           (select count(*) from inq i where k.trade = any(i.trades) and (k.emirate = 'UAE' or i.emirate = k.emirate))::int as demand,
           (select count(*) from inq i where i.short and k.trade = any(i.trades) and (k.emirate = 'UAE' or i.emirate = k.emirate))::int as short,
           (select coalesce(sum(p.n), 0) from pool p where p.t = k.trade and (k.emirate = 'UAE' or p.emirate = k.emirate))::int as pool
      from keys k
  )
  insert into public.supply_gap as sg (trade, emirate, matchable, target, demand_90d, short_open, uninvited_pool, measured_at)
  select trade, emirate, matchable, v_target, demand, short, pool, now() from m
  on conflict (trade, emirate) do update set matchable = excluded.matchable, target = excluded.target,
    demand_90d = excluded.demand_90d, short_open = excluded.short_open, uninvited_pool = excluded.uninvited_pool, measured_at = now();

  update public.supply_gap set status = 'closed', closed_at = now() where status <> 'closed' and matchable >= target;
  get diagnostics v_closed = row_count;
  update public.supply_gap set status = 'open', opened_at = now(), closed_at = null, decided_by = null, decided_at = null, held_id = null
   where (status = 'closed' and matchable < target) or (status = 'deferred' and decided_at < now() - interval '30 days');
  get diagnostics v_reopened = row_count;

  -- A decision whose reasoning failed five times goes back to open, so it is filed again (fn_reason_hold reopens it).
  update public.supply_gap sgp set status = 'open'
   where sgp.status = 'deciding' and exists (select 1 from public.reasoning_held_question h where h.id = sgp.held_id and h.status in ('failed', 'expired'));

  -- A CUSTOMER IS ALREADY WAITING: recruited for at once, by rule. No judgement to make, so nothing waits on one.
  update public.supply_gap set status = 'recruit', decided_by = 'rule:customer_waiting', decided_at = now()
   where status in ('open', 'deciding', 'deferred') and (short_open > 0 or demand_90d > 0);
  get diagnostics v_rule = row_count;

  -- NOBODY IS WAITING: recruit now or defer is a judgement, reasoned by the sales engineer (stakes high).
  for g in
    select s.*, tt.label from public.supply_gap s join public.taxonomy_trade tt on tt.code = s.trade
     where s.status = 'open' order by s.uninvited_pool desc, s.matchable, s.trade limit greatest(0, least(coalesce(p_reason_limit, 10), 50))
  loop
    update public.supply_gap set status = 'deciding', held_id = public.fn_seat_duty_reason('sales_engineer', 'sales_engineer.supply_gap',
      'Supplier supply for one trade is below the level at which we open requests to customers. Nobody is waiting on it '
        || 'today. Decide whether marketing should spend recruitment effort on this trade and area now, or defer it for a month.',
      '[{"id":"recruit","meaning":"recruit suppliers for this trade and area now"},{"id":"defer","meaning":"defer for a month; other gaps matter more"}]'::jsonb,
      jsonb_build_object('trade', g.trade, 'trade_label', g.label, 'area', g.emirate, 'matchable_suppliers', g.matchable,
                         'suppliers_needed_to_open', g.target, 'uninvited_leads_in_pool', g.uninvited_pool, 'requests_90d', g.demand_90d),
      jsonb_build_object('trade', g.trade, 'emirate', g.emirate), 'supply_gap:' || g.trade || ':' || g.emirate || ':' || v_month)
     where trade = g.trade and emirate = g.emirate;
    v_filed := v_filed + 1;
  end loop;

  -- THE HANDOFF: every gap still open or recruiting becomes a row in marketing's recruitment brief.
  v_brief := public.fn_sales_engineer_supply_gap_to_recruitment_brief();

  return jsonb_build_object('target', v_target, 'closed', v_closed, 'reopened', v_reopened, 'recruit_by_rule', v_rule,
    'filed_for_reasoning', v_filed, 'recruitment_brief', v_brief,
    'by_status', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from public.supply_gap group by status) x));
end $function$;
revoke execute on function public.fn_sales_engineer_supply_gap(integer) from public, anon, authenticated;

-- MARKETING'S RECRUITMENT FUNNEL: ONE pool_empty FINDING PER TRADE GROUP, NOT ONE PER GAP.
-- As live on 28 Sep 2026 (scripts/sql/marketing_recruits_where_supply_is_short_and_keeps_the_companys_reputation.sql)
-- with the empty-pool finding changed (review of #996):
--   * one finding per taxonomy_trade.group_code (12 active groups), key recruitment:pool_empty:<group>,
--     listing every recruiting gap in that group whose pool is empty, and affected = how many;
--   * blast 'agent_facing', not 'monitor': an empty lead pool stops marketing's work for that trade,
--     it does not blind a detector, and 'monitor' went critical after 6 h by design;
--   * a group finding closes when no recruiting gap in the group has an empty pool; the old per-gap
--     keys (recruitment:pool_empty:<trade>:<emirate>) close on the first run with a note saying why.
create or replace function public.fn_marketing_recruitment_funnel()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_day date := (now() at time zone 'Asia/Dubai')::date; v_rows int; gp record; v_empty int := 0; v_keys text[] := '{}';
begin
  insert into public.supplier_recruitment_funnel as f (trade, emirate, day, pool, invited, clicked, registered, approved, quoting)
  select g.trade, g.emirate, v_day,
         -- l.id is not null: a gap with NO matching lead is a null-extended row whose invite_status is
         -- null, which counted as a pool of 1 and so never fired pool_empty (found by this PR's probe).
         count(*) filter (where l.id is not null and l.invite_status is null and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)),
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

  -- An empty pool is the lead source, not the invitation: marketing's finding, one per trade group.
  for gp in select coalesce(tt.group_code, 'ungrouped') as grp, count(*)::int as n,
                   jsonb_agg(jsonb_build_object('trade', f.trade, 'emirate', f.emirate) order by f.trade, f.emirate) as gaps
              from public.supplier_recruitment_funnel f
              join public.supply_gap s on s.trade = f.trade and s.emirate = f.emirate and s.status = 'recruit'
              left join public.taxonomy_trade tt on tt.code = f.trade
             where f.day = v_day and f.pool = 0
             group by 1 loop
    v_empty := v_empty + gp.n;
    v_keys := v_keys || ('recruitment:pool_empty:' || gp.grp);
    perform public.fn_it_engineer_finding_upsert('recruitment:pool_empty:' || gp.grp,
      'No uninvited lead is left for ' || gp.n || ' recruiting gap(s) in trade group ' || gp.grp,
      'public.supplier_recruitment_funnel', 'agent_facing', gp.n,
      jsonb_build_object('trade_group', gp.grp, 'gap_count', gp.n, 'gaps', gp.gaps, 'owner_seat', 'marketing'), '{}'::text[],
      array['which source can supply leads for these trades while lead scraping is paused'], 'marketing');
  end loop;
  update public.it_engineer_finding fi
     set closed_at = now(),
         close_note = case when fi.issue_key ~ '^recruitment:pool_empty:[^:]+:'
                           then 'superseded: empty pools are now one finding per trade group'
                           else 'no recruiting gap in this trade group has an empty pool' end
   where fi.issue_key like 'recruitment:pool_empty:%' and fi.closed_at is null and not (fi.issue_key = any(v_keys));

  return jsonb_build_object('gaps_recruiting', v_rows, 'empty_pools', v_empty, 'empty_pool_findings', cardinality(v_keys),
    'totals', (select jsonb_build_object('pool', sum(pool), 'invited', sum(invited), 'registered', sum(registered), 'approved', sum(approved), 'quoting', sum(quoting))
                 from public.supplier_recruitment_funnel where day = v_day));
end $fn$;
