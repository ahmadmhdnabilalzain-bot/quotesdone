-- MARKETING PLANS RECRUITMENT FOR EVERY TRADE BELOW TEN SUPPLIERS.
-- Seat: marketing, reading the sales_engineer's supply-gap data. Founder instruction 1013, item 3 (29 Sep 2026):
-- for every category below 10 suppliers (supply_gap) - a targeted recruitment plan (where suppliers of that trade
-- gather, each source with a URL checked by a real lookup), an ENGLISH-only invitation variant tailored to the
-- trade, the category's uninvited leads queued first, and the categories ranked by gap size and customer demand.
-- Organic only; the invitation brakes, daily cap and the founder's go switch all still apply; no LLM in selection.
-- Needs the_sales_engineer_owns_onboarding_performance_and_supply_gaps.sql (public.supply_gap).
--
-- WHAT WAS MEASURED (production, 29 Sep 2026): 217 supply_gap rows below target and not closed (matchable < target,
-- target 10 everywhere): 8 'recruit', the rest 'open'/'deciding'. Only the 'recruit' rows moved a lead up the queue;
-- nothing recorded where a trade's suppliers can be found, and every invitation carried one generic body.
--
-- WHAT THIS ADDS
--   public.marketing_recruitment_source   the places suppliers gather (directory, association, chamber, LinkedIn
--                                         group, trade fair), scoped to all trades, a taxonomy group or one trade,
--                                         each with the URL, the HTTP status and time of the lookup that checked it.
--   public.marketing_gap_recruitment_plan one row per open gap: its rank, the sources, the English invitation variant.
--   fn_marketing_gap_recruitment_plans()  the daily duty marketing.gap_recruitment_plans: rebuilds the plans from
--                                         supply_gap by fixed rules (no model), drops plans whose gap closed, and
--                                         returns the report the seat reads (top of the ranking, sources, pools).
--
-- THE QUEUE IS NOT MARKETING'S (instr 625 stands): the invitation order belongs to the sales engineer. Its routine,
-- fn_supplier_invite_candidates, reads this plan table as an input in
-- the_invitation_queue_reads_marketings_gap_ranking_and_is_always_english.sql (seat sales_engineer). This file
-- produces the ranking, the sources and the English variants only.
--
-- WHAT THIS DOES NOT DO: send anything, buy anything (no paid channel is a source kind), write Arabic copy, or read
-- any lead's words to choose it (trade codes compared by equality, as before).

-- ── 1. where suppliers gather ────────────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_recruitment_source (
  id           bigint generated always as identity primary key,
  scope        text not null,             -- 'all', a taxonomy_trade.group_code, or a taxonomy_trade.code
  kind         text not null check (kind in ('directory', 'association', 'chamber', 'linkedin_group', 'trade_fair')),
  name         text not null,
  url          text not null check (url ~ '^https?://'),
  http_status  integer not null,
  verified     boolean not null,
  checked_at   timestamptz not null,
  evidence     text not null,
  unique (scope, url)
);
alter table public.marketing_recruitment_source enable row level security;
drop policy if exists marketing_recruitment_source_service_role_only on public.marketing_recruitment_source;
create policy marketing_recruitment_source_service_role_only on public.marketing_recruitment_source as permissive for all to public using (false) with check (false);
revoke all on public.marketing_recruitment_source from anon, authenticated;

-- ── 2. the plan per gap ──────────────────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_gap_recruitment_plan (
  trade           text not null,
  emirate         text not null,
  rank            integer not null,
  matchable       integer not null,
  target          integer not null,
  gap             integer not null,
  demand_90d      integer not null,
  uninvited_pool  integer not null,
  gap_status      text not null,
  sources         jsonb not null default '[]'::jsonb,
  invite_subject  text not null,
  invite_body     text not null check (invite_body like '%{{link}}%' and invite_body !~ '[؀-ۿ]' and invite_subject !~ '[؀-ۿ]'),
  built_at        timestamptz not null default now(),
  primary key (trade, emirate),
  foreign key (trade, emirate) references public.supply_gap (trade, emirate) on delete cascade
);
create index if not exists marketing_gap_recruitment_plan_trade_idx on public.marketing_gap_recruitment_plan (trade, rank);
alter table public.marketing_gap_recruitment_plan enable row level security;
drop policy if exists marketing_gap_recruitment_plan_service_role_only on public.marketing_gap_recruitment_plan;
create policy marketing_gap_recruitment_plan_service_role_only on public.marketing_gap_recruitment_plan as permissive for all to public using (false) with check (false);
revoke all on public.marketing_gap_recruitment_plan from anon, authenticated;

create or replace function public.fn_marketing_gap_recruitment_plans()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_body text := (select value from public.app_secrets where key = 'invite_body');
  v_anchor constant text := 'Whatever your trade or product, if it can be quoted from specifications, drawings or photos, it belongs here.';
  v_rows int; v_dropped int;
begin
  if coalesce(v_body, '') not like '%{{link}}%' then
    raise exception 'app_secrets.invite_body has no {{link}} placeholder: no trade variant is built from it';
  end if;

  delete from public.marketing_gap_recruitment_plan p
   where not exists (select 1 from public.supply_gap g where g.trade = p.trade and g.emirate = p.emirate
                       and g.closed_at is null and g.status <> 'closed' and g.matchable < g.target);
  get diagnostics v_dropped = row_count;

  with gaps as (
    select g.*, coalesce(t.label, g.trade) as label, t.group_code,
           row_number() over (order by (g.target - g.matchable) desc, g.demand_90d desc, g.uninvited_pool desc, g.trade, g.emirate) as rk
      from public.supply_gap g left join public.taxonomy_trade t on t.code = g.trade
     where g.closed_at is null and g.status <> 'closed' and g.matchable < g.target
  ),
  txt as (
    select g.*,
      -- the trade sentence: what was measured, nothing more (demand only where customers asked in 90 days)
      case when g.demand_90d > 0
        then 'Clients have already asked for ' || g.label || ' work' || case when g.emirate <> 'UAE' then ' in ' || g.emirate else '' end
             || ', and fewer than ' || g.target || ' ' || g.label || ' suppliers are registered to quote for it, so a registered '
             || g.label || ' supplier is matched with little competition.'
        else 'We are building the ' || g.label || ' supplier list now: fewer than ' || g.target || ' ' || g.label
             || ' suppliers are registered, so an early ' || g.label || ' supplier is among the first matched when '
             || g.label || ' requests arrive.' end
      || ' ' || case g.group_code
        when 'construction_building'          then 'Requests in your trade usually arrive as a BOQ, drawings or site photos.'
        when 'mep_building_systems'           then 'Requests in your trade usually arrive as a BOQ, drawings, a schedule of equipment or site photos.'
        when 'industrial_manufacturing'       then 'Requests in your trade usually arrive as part numbers, datasheets, drawings or photos of the part.'
        when 'materials_packaging'            then 'Requests in your trade usually arrive as a specification, quantities and a sample photo.'
        when 'energy_environment'             then 'Requests in your trade usually arrive as a site description, capacities and quantities.'
        when 'facilities_property'            then 'Requests in your trade usually arrive as a scope of services, areas and frequency.'
        when 'furniture_hospitality_consumer' then 'Requests in your trade usually arrive as a product list, quantities and reference photos.'
        when 'health_lab_safety'              then 'Requests in your trade usually arrive as a product list with specifications and quantities.'
        when 'marketing_media_events'         then 'Requests in your trade usually arrive as a brief, dates, quantities and reference images.'
        when 'professional_business'          then 'Requests in your trade usually arrive as a scope of work and the deliverables expected.'
        when 'technology_telecom'             then 'Requests in your trade usually arrive as a list of equipment or a scope of work.'
        when 'transport_mobility'             then 'Requests in your trade usually arrive as routes, volumes, vehicle or part details.'
        else 'Requests in your trade arrive as specifications, drawings or photos.' end as trade_line
    from gaps g
  )
  insert into public.marketing_gap_recruitment_plan as p
    (trade, emirate, rank, matchable, target, gap, demand_90d, uninvited_pool, gap_status, sources, invite_subject, invite_body, built_at)
  select x.trade, x.emirate, x.rk, x.matchable, x.target, x.target - x.matchable, x.demand_90d, x.uninvited_pool, x.status,
         coalesce((select jsonb_agg(jsonb_build_object('kind', s.kind, 'name', s.name, 'url', s.url, 'scope', s.scope,
                                                       'http_status', s.http_status, 'verified', s.verified, 'checked_at', s.checked_at)
                                    order by (s.scope = x.trade) desc, (s.scope = x.group_code) desc, s.verified desc, s.kind, s.name)
                     from public.marketing_recruitment_source s
                    where s.scope in ('all', x.trade, coalesce(x.group_code, '-'))), '[]'::jsonb),
         'Invitation: ' || x.label || ' supplier on QuotesDone (free, no commission)',
         -- the approved body, with its "whatever your trade" sentence replaced by this trade's; if that sentence is
         -- ever reworded, the trade sentence goes after the greeting instead, so a variant is never built without it
         case when position(v_anchor in v_body) > 0 then replace(v_body, v_anchor, x.trade_line)
              else regexp_replace(v_body, E'^([^\\n]*\\n\\n)', E'\\1' || replace(x.trade_line, '\', '\\') || E'\n\n') end,
         now()
    from txt x
  on conflict (trade, emirate) do update set rank = excluded.rank, matchable = excluded.matchable, target = excluded.target,
    gap = excluded.gap, demand_90d = excluded.demand_90d, uninvited_pool = excluded.uninvited_pool, gap_status = excluded.gap_status,
    sources = excluded.sources, invite_subject = excluded.invite_subject, invite_body = excluded.invite_body, built_at = excluded.built_at;
  get diagnostics v_rows = row_count;

  -- a planned trade with no checked source is marketing's own finding (where to look is the gap, not the invitation)
  perform public.fn_it_engineer_finding_upsert('recruitment:no_source:' || p.trade,
      'No checked recruitment source is recorded for ' || p.trade, 'public.marketing_recruitment_source', 'monitor', 1,
      jsonb_build_object('trade', p.trade, 'owner_seat', 'marketing'), '{}'::text[],
      array['a directory, association, chamber, LinkedIn group or trade fair where this trade gathers'], 'marketing')
    from (select distinct trade from public.marketing_gap_recruitment_plan
           where not exists (select 1 from jsonb_array_elements(sources) e where (e->>'verified')::boolean)) p;
  update public.it_engineer_finding f set closed_at = now(), close_note = 'a checked source is recorded'
   where f.issue_key like 'recruitment:no_source:%' and f.closed_at is null
     and not exists (select 1 from public.marketing_gap_recruitment_plan p where 'recruitment:no_source:' || p.trade = f.issue_key
                       and not exists (select 1 from jsonb_array_elements(p.sources) e where (e->>'verified')::boolean));

  return public.fn_marketing_gap_recruitment_report() || jsonb_build_object('plans_written', v_rows, 'plans_dropped', v_dropped);
end $fn$;
revoke execute on function public.fn_marketing_gap_recruitment_plans() from public, anon, authenticated;
grant execute on function public.fn_marketing_gap_recruitment_plans() to service_role;

-- what the seat reports: the ranking head, the sources behind it, and how much of the queue the plans hold
create or replace function public.fn_marketing_gap_recruitment_report()
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object(
    'plans', (select count(*) from public.marketing_gap_recruitment_plan),
    'plans_with_checked_source', (select count(*) from public.marketing_gap_recruitment_plan p
                                   where exists (select 1 from jsonb_array_elements(p.sources) e where (e->>'verified')::boolean)),
    'sources', (select count(*) from public.marketing_recruitment_source),
    'sources_verified', (select count(*) from public.marketing_recruitment_source where verified),
    'uninvited_pool_in_plans', (select coalesce(sum(uninvited_pool), 0) from public.marketing_gap_recruitment_plan),
    'top', (select coalesce(jsonb_agg(jsonb_build_object('rank', rank, 'trade', trade, 'emirate', emirate, 'gap', gap,
                                                         'demand_90d', demand_90d, 'uninvited_pool', uninvited_pool, 'gap_status', gap_status,
                                                         'sources', jsonb_array_length(sources)) order by rank), '[]'::jsonb)
              from public.marketing_gap_recruitment_plan where rank <= 20))
$fn$;
revoke execute on function public.fn_marketing_gap_recruitment_report() from public, anon, authenticated;
grant execute on function public.fn_marketing_gap_recruitment_report() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('marketing.gap_recruitment_plans', 'marketing', interval '1 day', 'fn_marketing_gap_recruitment_plans',
   'A recruitment plan per trade below ten suppliers: ranked by gap and customer demand, the checked places its suppliers gather, and an English invitation variant. The sales engineer''s invitation queue reads the ranking (instr 1013, instr 625).',
   'scripts/sql/marketing_plans_recruitment_for_every_trade_below_ten_suppliers.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- ── 3. the sources, as checked on 29 Sep 2026 (each row's http_status and checked_at are that lookup's) ────
insert into public.marketing_recruitment_source (scope, kind, name, url, http_status, verified, checked_at, evidence) values
  ('all', 'chamber', 'Dubai Chamber of Commerce', 'https://www.dubaichambercommerce.com/en/', 200, true, '2026-09-28T20:38:30Z', 'HTTP 200 (redirect from dubaichamber.com), title ''Dubai Chamber of Commerce - Dubai Business Hub'''),
  ('all', 'chamber', 'Abu Dhabi Chamber of Commerce and Industry', 'https://www.abudhabichamber.ae/', 200, true, '2026-09-28T20:38:26Z', 'HTTP 200, title ''غرفة تجارة وصناعة أبوظبي'' (adcci.gov.ae returned 401)'),
  ('all', 'chamber', 'Sharjah Chamber of Commerce and Industry', 'https://sharjah.gov.ae/', 200, true, '2026-09-28T20:38:23Z', 'HTTP 200, Arabic home page title; WebSearch shows ''Sharjah Chamber :: Home'' at this domain'),
  ('all', 'linkedin_group', 'Sharjah Chamber of Commerce and Industry (LinkedIn page)', 'https://www.linkedin.com/company/sharjahchamber', 200, true, '2026-09-28T20:38:25Z', 'HTTP 200, title ''Sharjah Chamber of Commerce & Industry غرفة تجـارة وص...'''),
  ('all', 'chamber', 'Ajman Chamber of Commerce and Industry', 'https://www.ajmanchamber.ae/', 200, true, '2026-09-28T20:37:02Z', 'HTTP 200, title ''غرفة عجمان'''),
  ('all', 'chamber', 'Ras Al Khaimah Chamber of Commerce and Industry', 'https://www.rakchamber.ae/', 200, true, '2026-09-28T20:37:08Z', 'HTTP 200, title ''RAK CHAMBER'''),
  ('all', 'directory', 'Yellow Pages UAE (B2B portal)', 'https://www.yellowpages.ae/', 200, true, '2026-09-28T20:37:11Z', 'HTTP 200, title ''Yellow Pages UAE | B2B Portal | Business Directory In UAE'''),
  ('all', 'directory', 'YellowPages-UAE', 'https://www.yellowpages-uae.com/', 200, true, '2026-09-28T20:38:30Z', 'HTTP 200, title ''YellowPages-UAE, The Online Directory for Businesses and Brands in the...'''),
  ('all', 'association', 'Ministry of Economy and Tourism: Dubai SME (Mohammed Bin Rashid Establishment for SME Development)', 'https://www.moet.gov.ae/en/mohammed-bin-rashid-establishment-for-sme-development-dubai-sme', 200, true, '2026-09-28T20:38:23Z', 'HTTP 200, title ''Mohammed Bin Rashid Establishment for SME Development (Dubai SME) | Mi...'''),
  ('all', 'association', 'Dubai SME', 'https://sme.ae/Default/en', 403, true, '2026-09-28T20:38:22Z', 'HTTP 403 Access Denied to curl; WebSearch lists sme.ae/Default/en as ''Dubai SME'''),
  ('all', 'trade_fair', 'Dubai World Trade Centre events', 'https://www.dwtc.com/en/', 200, true, '2026-09-28T20:37:04Z', 'HTTP 200, title ''Dubai World Trade Centre - Home'''),
  ('all', 'trade_fair', 'ADNEC Centre Abu Dhabi events', 'https://www.adnec.ae/en', 200, true, '2026-09-28T20:37:02Z', 'HTTP 200, title ''ADNEC Centre Abu Dhabi'''),
  ('all', 'trade_fair', 'Expo Centre Sharjah events', 'https://expo-centre.ae/', 200, true, '2026-09-28T20:37:08Z', 'HTTP 200, title ''Expo Centre Sharjah'''),
  ('construction_building', 'trade_fair', 'Big 5 Global', 'https://www.big5global.com/', 200, true, '2026-09-28T20:37:04Z', 'HTTP 200, title ''Big 5 Global | 23 - 26 November 2026, Dubai World Trade Centre'''),
  ('construction_building', 'association', 'UAE Contractors'' Association', 'https://www.uaecontractors.org/', 200, true, '2026-09-28T20:38:25Z', 'HTTP 200, title ''UAE Contractors'''),
  ('construction_building', 'linkedin_group', 'UAE Contractors Association (LinkedIn page)', 'https://www.linkedin.com/company/uae-contractors-association', 200, true, '2026-09-28T20:38:25Z', 'HTTP 200, title ''UAE Contractors Association | LinkedIn'''),
  ('construction_building', 'association', 'Society of Engineers UAE', 'https://www.soeuae.ae/ar/default.aspx', 200, true, '2026-09-28T20:37:10Z', 'HTTP 200 (redirect from soeuae.ae); no title returned'),
  ('construction_building', 'trade_fair', 'Cityscape Global', 'https://cityscapeglobal.com/', 200, true, '2026-09-28T20:37:04Z', 'HTTP 200, title ''Join the Global Real Estate Event | November 16-19, 2026'''),
  ('mep_building_systems', 'association', 'ASHRAE Falcon Chapter UAE', 'https://ashraeuae.org/', 200, true, '2026-09-28T20:38:25Z', 'HTTP 200, title ''Home - ASHRAE Falcon Chapter'''),
  ('mep_building_systems', 'trade_fair', 'HVACR World (with Big 5)', 'https://www.hvacr-world.com/', 200, true, '2026-09-28T20:38:24Z', 'HTTP 200, title ''HVACR World | 23 - 26 November 2026 | DWTC'''),
  ('mep_building_systems', 'trade_fair', 'Intersec Global (fire, security, safety)', 'https://intersecglobal.ae.messefrankfurt.com/dubai/en.html', 200, true, '2026-09-28T20:37:05Z', 'HTTP 200, title ''Intersec Global | The World-Class Security, Safety & Fire Protecti...'''),
  ('mep_building_systems', 'trade_fair', 'Light + Intelligent Building Middle East', 'https://light-middle-east.ae.messefrankfurt.com/dubai/en.html', 200, true, '2026-09-28T20:38:27Z', 'HTTP 200, title ''Light + Intelligent Building Middle East | 12–14 January 2027'''),
  ('mep_building_systems', 'directory', 'MEP Middle East (trade media)', 'https://www.mepmiddleeast.com/', 403, false, '2026-09-28T20:37:08Z', 'HTTP 403 to curl; not confirmed by a second lookup'),
  ('industrial_manufacturing', 'trade_fair', 'Make it in the Emirates', 'https://www.miite.ae/en', 200, true, '2026-09-28T20:38:23Z', 'HTTP 200, title ''Miite - Make it in the Emirates 2026'''),
  ('industrial_manufacturing', 'trade_fair', 'ADIPEC', 'https://www.adipec.com/', 200, true, '2026-09-28T20:37:01Z', 'HTTP 200, title ''ADIPEC Exhibition & Conference | 2 - 5 November 2026'''),
  ('industrial_manufacturing', 'directory', 'Jebel Ali Free Zone (Jafza)', 'https://www.jafza.ae/', 200, true, '2026-09-28T20:38:30Z', 'HTTP 200, title ''Jebel Ali Free Zone (Jafza)'''),
  ('industrial_manufacturing', 'trade_fair', 'WETEX', 'https://www.wetex.ae/en', 403, true, '2026-09-28T20:38:22Z', 'HTTP 403 Access Denied to curl; WebSearch lists ''Wetex | Home'' at wetex.ae/en (DEWA-organised)'),
  ('materials_packaging', 'trade_fair', 'Gulfood Manufacturing', 'https://gulfoodmanufacturing.com/', 200, true, '2026-09-28T20:37:09Z', 'HTTP 200, title ''Gulfood Manufacturing 2026 | Global F&B Manufacturing Exhibition'''),
  ('materials_packaging', 'trade_fair', 'ArabPlast', 'https://www.arabplast.info/', 200, true, '2026-09-28T20:37:03Z', 'HTTP 200, title ''ArabPlast - No. 1 Premium Trade Show in the Middle East...'''),
  ('materials_packaging', 'trade_fair', 'Middle East Coatings Show', 'https://www.middleeastcoatingsshow.com/', 200, true, '2026-09-28T20:37:09Z', 'HTTP 200, title ''Middle East Coatings Show | 28-30 September 2026 | Dubai Exhibition Ce...'''),
  ('energy_environment', 'trade_fair', 'World Future Energy Summit', 'https://www.worldfutureenergysummit.com/', 200, true, '2026-09-28T20:37:10Z', 'HTTP 200, title ''World Future Energy Summit | ADNEC Centre Abu Dhabi'''),
  ('energy_environment', 'association', 'Emirates Solar Industry Association', 'https://emiratessolar.org/', 200, true, '2026-09-28T20:37:06Z', 'HTTP 200, title ''Emirates Solar'''),
  ('energy_environment', 'association', 'Emirates Green Building Council (membership)', 'https://emiratesgbc.org/membership/', 200, true, '2026-09-28T20:38:35Z', 'HTTP 200, title ''Membership – EmiratesGBC'''),
  ('energy_environment', 'association', 'MESIA - MENA Solar Industry Association', 'https://mesia.com/', 200, true, '2026-09-28T20:37:11Z', 'HTTP 200, title ''MESIA | MENA Solar Industry Association'''),
  ('energy_environment', 'trade_fair', 'WETEX', 'https://www.wetex.ae/en', 403, true, '2026-09-28T20:38:22Z', 'HTTP 403 to curl; WebSearch lists ''Wetex | Home'' at this URL and DWTC WETEX 2026 listing'),
  ('energy_environment', 'trade_fair', 'Middle East Energy', 'https://www.middleeast-energy.com/en/home.html', 403, false, '2026-09-28T20:38:23Z', 'HTTP 403 Cloudflare ''Just a moment...''; not confirmed by a second lookup'),
  ('facilities_property', 'association', 'MEFMA - Middle East Facilities Management Association', 'https://mefma.org/', 200, true, '2026-09-28T20:37:09Z', 'HTTP 200, title ''MEFMA - Middle East Facilities Management Association'''),
  ('facilities_property', 'trade_fair', 'Cityscape Global', 'https://cityscapeglobal.com/', 200, true, '2026-09-28T20:37:04Z', 'HTTP 200, title ''Join the Global Real Estate Event | November 16-19, 2026'''),
  ('facilities_property', 'association', 'IFMA - International Facility Management Association', 'https://www.ifma.org/', 200, true, '2026-09-28T20:38:35Z', 'HTTP 200, title ''IFMA - International Facility Management Association'' (global body, not UAE-only)'),
  ('facilities_property', 'directory', 'Clean Middle East magazine', 'https://www.cleanmiddleeast.ae/', 200, true, '2026-09-28T20:38:30Z', 'HTTP 200, title ''Clean Middle East Magazine - Clean Middle East'''),
  ('furniture_hospitality_consumer', 'trade_fair', 'INDEX Dubai', 'https://www.indexexhibition.com/', 200, true, '2026-09-28T20:37:07Z', 'HTTP 200, title ''INDEX | 1 - 3 June 2027 | Dubai World Trade Centre'''),
  ('furniture_hospitality_consumer', 'trade_fair', 'The Hotel Show Dubai', 'https://www.thehotelshow.com/', 200, true, '2026-09-28T20:37:10Z', 'HTTP 200, title ''The Hotel Show | 1 - 3 June 2027 | Dubai World Trade Centre'''),
  ('furniture_hospitality_consumer', 'trade_fair', 'Beautyworld Dubai', 'https://beautyworld-dubai.ae.messefrankfurt.com/dubai/en.html', 200, true, '2026-09-28T20:37:05Z', 'HTTP 200, title ''Beautyworld Dubai | 6 - 8 Oct 2026 | Dubai World Trade Centre'''),
  ('furniture_hospitality_consumer', 'trade_fair', 'GulfHost (hospitality and foodservice equipment)', 'https://www.gulfhost.ae/', 200, true, '2026-09-28T20:38:30Z', 'HTTP 200, title ''Hospitality & Foodservice Equipment Expo | GulfHost 2026'''),
  ('furniture_hospitality_consumer', 'trade_fair', 'Downtown Design', 'https://www.downtowndesign.com/', 200, true, '2026-09-28T20:37:03Z', 'HTTP 200, title ''Downtown Design | The Middle East''s Leading Design Fair'''),
  ('health_lab_safety', 'association', 'Emirates Medical Association', 'https://www.ema.ae/', 200, true, '2026-09-28T20:37:11Z', 'HTTP 200, title ''Emirates Medical Association (EMA)'''),
  ('health_lab_safety', 'trade_fair', 'World Health Expo (WHX) Dubai, formerly Arab Health', 'https://www.worldhealthexpo.com/', 403, false, '2026-09-28T20:37:10Z', 'HTTP 403 Cloudflare ''Just a moment...''; not confirmed by a second lookup'),
  ('health_lab_safety', 'trade_fair', 'WHX Labs Dubai (formerly Medlab Middle East)', 'https://www.worldhealthexpo.com/events/labs/dubai/en/home.html', 403, false, '2026-09-28T20:37:07Z', 'medlabme.com redirects here, final response 403 Cloudflare'),
  ('health_lab_safety', 'trade_fair', 'Intersec Global (safety)', 'https://intersecglobal.ae.messefrankfurt.com/dubai/en.html', 200, true, '2026-09-28T20:37:05Z', 'HTTP 200, title ''Intersec Global | ... Security, Safety & Fire Protection'''),
  ('marketing_media_events', 'association', 'MEPRA - Middle East Public Relations Association', 'https://www.mepra.org/', 200, true, '2026-09-28T20:37:12Z', 'HTTP 200, title ''MEPRA'''),
  ('marketing_media_events', 'trade_fair', 'SGI MENA Expo (Sign & Graphic Imaging)', 'https://www.signmiddleeast.com/', 200, true, '2026-09-28T20:37:10Z', 'HTTP 200, title ''SGI MENA Expo | Sign Print & Beyond'''),
  ('marketing_media_events', 'trade_fair', 'Dubai Lynx', 'https://www.dubailynx.com/', 200, true, '2026-09-28T20:37:06Z', 'HTTP 200, title ''Dubai Lynx 2026 | Celebrating and advancing MENA''s Creative Excel...'''),
  ('marketing_media_events', 'association', 'Emirates Creative Association', 'https://uaeca.ae/', 200, true, '2026-09-28T20:37:12Z', 'HTTP 200, title ''جمعية الإمارات للإبداع – Emirates Creative A...'''),
  ('professional_business', 'association', 'ACCA Middle East', 'https://www.accaglobal.com/middle-east/en.html', 200, true, '2026-09-28T20:38:31Z', 'HTTP 200 (accaglobal.com geo-redirect), title ''Home | ACCA Global'''),
  ('professional_business', 'association', 'ICAEW', 'https://www.icaew.com/', 200, true, '2026-09-28T20:38:32Z', 'HTTP 200, title ''Welcome to ICAEW.com''. The Middle East page paths returned 404'),
  ('professional_business', 'directory', 'ADGM (Abu Dhabi Global Market)', 'https://www.adgm.com/', 200, true, '2026-09-28T20:38:30Z', 'HTTP 200, title ''Abu Dhabi''s International Financial Centre | ADGM'''),
  ('technology_telecom', 'trade_fair', 'GITEX Global', 'https://www.gitex.com/', 200, true, '2026-09-28T20:37:05Z', 'HTTP 200, title ''GITEX GLOBAL | 7-11 DEC 2026 | DUBAI'''),
  ('technology_telecom', 'directory', 'Dubai Internet City', 'https://www.dic.ae/', 200, true, '2026-09-28T20:37:03Z', 'HTTP 200, title ''Dubai''s Leading Innovation & Tech Hub | Dubai Internet City'''),
  ('technology_telecom', 'trade_fair', 'GISEC Global (cybersecurity)', 'https://gisec.ae/', 200, true, '2026-09-28T20:38:27Z', 'HTTP 200, title ''GISEC GLOBAL I 4-6 May 2027 I Dubai'''),
  ('transport_mobility', 'trade_fair', 'Automechanika Dubai', 'https://automechanika-dubai.ae.messefrankfurt.com/dubai/en.html', 200, true, '2026-09-28T20:37:05Z', 'HTTP 200, title ''Automechanika Dubai | 10 – 12 November 2026'''),
  ('transport_mobility', 'trade_fair', 'Dubai Airshow', 'https://www.dubaiairshow.aero/', 200, true, '2026-09-28T20:37:03Z', 'HTTP 200, title ''Dubai Airshow 2027 | Register your interest'''),
  ('transport_mobility', 'association', 'National Association of Freight and Logistics (NAFL)', 'https://www.nafl.ae/', 200, true, '2026-09-28T20:38:24Z', 'HTTP 200, title ''National Association of Freight and Logistics'''),
  ('transport_mobility', 'trade_fair', 'Seatrade Maritime UAE', 'https://www.seatrademaritime-middleeast.com/en/home.html', 403, true, '2026-09-28T20:38:22Z', 'HTTP 403 Cloudflare to curl; WebSearch lists this exact URL as ''Seatrade Maritime UAE | The Event & Conference for Maritime in the Middle East'''),
  ('transport_mobility', 'directory', 'Dubai Maritime City', 'https://www.dmc.ae/', 403, false, '2026-09-28T20:37:03Z', 'HTTP 403 Access Denied; not confirmed by a second lookup'),
  ('painting', 'trade_fair', 'Middle East Coatings Show', 'https://www.middleeastcoatingsshow.com/', 200, true, '2026-09-28T20:37:09Z', 'HTTP 200, title ''Middle East Coatings Show | 28-30 September 2026'''),
  ('gypsum', 'trade_fair', 'Big 5 Global (interiors and finishes)', 'https://www.big5global.com/', 200, true, '2026-09-28T20:37:04Z', 'HTTP 200, title ''Big 5 Global | 23 - 26 November 2026''. General construction show, not gypsum-specific'),
  ('aluminium', 'trade_fair', 'Windows, Doors & Facades Event', 'https://www.windowsdoorsandfacadeevent.com/', 200, true, '2026-09-28T20:37:11Z', 'HTTP 200, title ''Windows, Doors & Facades | 24 - 27 November 2025 | DWTC'' (the page still shows the 2025 dates)'),
  ('glazing', 'trade_fair', 'Windows, Doors & Facades Event', 'https://www.windowsdoorsandfacadeevent.com/', 200, true, '2026-09-28T20:37:11Z', 'HTTP 200, title ''Windows, Doors & Facades ... DWTC'''),
  ('doors', 'trade_fair', 'Windows, Doors & Facades Event', 'https://www.windowsdoorsandfacadeevent.com/', 200, true, '2026-09-28T20:37:11Z', 'HTTP 200, title ''Windows, Doors & Facades ... DWTC'''),
  ('building_materials', 'trade_fair', 'Big 5 Global', 'https://www.big5global.com/', 200, true, '2026-09-28T20:38:30Z', 'HTTP 200 (thebig5.ae redirects here), title ''Big 5 Global'''),
  ('civil_works', 'trade_fair', 'Middle East Concrete (part of Big 5 Global)', 'https://www.big5global.com/', 200, true, '2026-09-28T20:38:32Z', 'middleeastconcrete.com redirects to big5global.com, HTTP 200'),
  ('civil_works', 'association', 'UAE Contractors'' Association', 'https://www.uaecontractors.org/', 200, true, '2026-09-28T20:38:25Z', 'HTTP 200, title ''UAE Contractors'''),
  ('interior_fitout', 'trade_fair', 'INDEX Dubai', 'https://www.indexexhibition.com/', 200, true, '2026-09-28T20:37:07Z', 'HTTP 200, title ''INDEX | 1 - 3 June 2027'''),
  ('interior_fitout', 'trade_fair', 'Downtown Design', 'https://www.downtowndesign.com/', 200, true, '2026-09-28T20:37:03Z', 'HTTP 200, title ''Downtown Design | The Middle East''s Leading Design Fair'''),
  ('flooring', 'trade_fair', 'Big 5 Global (includes Middle East Stone)', 'https://www.big5global.com/', 200, true, '2026-09-28T20:37:04Z', 'HTTP 200. Middle East Stone''s own domains returned 000; WebSearch places it at DWTC alongside Big 5'),
  ('electrical', 'trade_fair', 'Light + Intelligent Building Middle East', 'https://light-middle-east.ae.messefrankfurt.com/dubai/en.html', 200, true, '2026-09-28T20:38:27Z', 'HTTP 200, title ''Light + Intelligent Building Middle East | 12–14 January 2027'''),
  ('electrical', 'trade_fair', 'Middle East Energy', 'https://www.middleeast-energy.com/en/home.html', 403, false, '2026-09-28T20:38:23Z', 'HTTP 403 Cloudflare; not confirmed by a second lookup'),
  ('steel', 'trade_fair', 'Big 5 Global (steel and structures)', 'https://www.big5global.com/', 200, true, '2026-09-28T20:37:04Z', 'HTTP 200. General construction show; no steel-specific UAE source verified'),
  ('upholstery', 'trade_fair', 'INDEX Dubai (furniture and furnishings)', 'https://www.indexexhibition.com/', 200, true, '2026-09-28T20:37:07Z', 'HTTP 200, title ''INDEX | 1 - 3 June 2027'''),
  ('security_systems', 'trade_fair', 'Intersec Global', 'https://intersecglobal.ae.messefrankfurt.com/dubai/en.html', 200, true, '2026-09-28T20:37:05Z', 'HTTP 200, title ''Intersec Global | ... Security, Safety & Fire Protection'''),
  ('security_systems', 'trade_fair', 'GISEC Global', 'https://gisec.ae/', 200, true, '2026-09-28T20:38:27Z', 'HTTP 200, title ''GISEC GLOBAL I 4-6 May 2027 I Dubai'''),
  ('joinery', 'trade_fair', 'Dubai WoodShow', 'https://www.woodshowglobal.com/dubai', 200, true, '2026-09-28T20:37:06Z', 'dubaiwoodshow.com redirects here, HTTP 200, title ''Dubai WoodShow 2027 | Wood Exhibition UAE'''),
  ('landscaping', 'directory', 'Landscape Magazine - Middle East', 'https://www.landscape-me.com/', 200, true, '2026-09-28T20:37:07Z', 'HTTP 200, title ''Landscape Magazine - Middle East'''),
  ('mep_general', 'association', 'ASHRAE Falcon Chapter UAE', 'https://ashraeuae.org/', 200, true, '2026-09-28T20:38:25Z', 'HTTP 200, title ''Home - ASHRAE Falcon Chapter'''),
  ('mep_general', 'trade_fair', 'HVACR World', 'https://www.hvacr-world.com/', 200, true, '2026-09-28T20:38:24Z', 'HTTP 200, title ''HVACR World | 23 - 26 November 2026 | DWTC'''),
  ('cleaning', 'directory', 'Clean Middle East magazine (Middle East Cleaning Technology Week)', 'https://www.cleanmiddleeast.ae/', 200, true, '2026-09-28T20:37:04Z', 'HTTP 200, title ''Clean Middle East Magazine - Clean Middle East'''),
  ('cleaning', 'association', 'MEFMA - Middle East Facilities Management Association', 'https://mefma.org/', 200, true, '2026-09-28T20:37:09Z', 'HTTP 200, title ''MEFMA - Middle East Facilities Management Association''')
on conflict (scope, url) do update set kind = excluded.kind, name = excluded.name, http_status = excluded.http_status,
  verified = excluded.verified, checked_at = excluded.checked_at, evidence = excluded.evidence;

-- ── 4. both tables are in the daily export ──────────────────────────────────────────────────────────────
-- Every marketing table is exported every day (every_marketing_table_is_in_the_daily_export.test.mjs). The two tables
-- above are the seat's records (the verified sources, the ranked plans), so fn_table_export_list is redefined from its
-- canonical body (the_calendar_resend_decisions_are_in_the_daily_export.sql, the last definer in MANIFEST.txt on
-- 29 Sep 2026) with only marketing_recruitment_source and marketing_gap_recruitment_plan added. This file creates both
-- tables above, so neither needs the not-yet-created skip below.
create or replace function public.fn_table_export_list()
returns table(table_name text, subject text, change_log text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select v.t, v.s,
         (select 'table_export_change' from public.table_export_change_tracked x where x.table_name = v.t)
  from (values
    ('customers','customer'), ('customer_preference','customer'), ('customer_calls','customer'), ('projects','customer'),
    ('leads','supplier'), ('lead_category','supplier'), ('lead_subcategory','supplier'), ('supplier_capabilities','supplier'),
    ('supplier_catalog','supplier'), ('supplier_product','supplier'), ('supplier_product_variant','supplier'),
    ('supplier_capability_confirmation','supplier'), ('supplier_collaboration','supplier'), ('supplier_collaboration_event','supplier'),
    ('supplier_negotiation_policy','supplier'), ('supplier_screening_hit','supplier'), ('supplier_lead_intake','supplier'),
    ('doc_reviews','supplier'), ('licence_renewal_ask','supplier'), ('outreach','supplier'), ('company_registration','company'),
    ('inquiries','inquiry'), ('inquiry_intake','inquiry'), ('inquiry_matches','inquiry'), ('inquiry_requirement','inquiry'),
    ('inquiry_cancellations','inquiry'), ('inquiry_supplier_brief','inquiry'), ('inquiry_state_audit','inquiry'),
    ('inquiry_gate','inquiry'), ('inquiry_answer','inquiry'), ('inquiry_answer_document','inquiry'), ('inquiry_answer_scope','inquiry'),
    ('inquiry_workstream','inquiry'), ('inquiry_workstream_group','inquiry'), ('inquiry_workstream_requirement','inquiry'),
    ('inquiry_trade_candidate','inquiry'), ('inquiry_trade_clarification','inquiry'), ('inquiry_scope_disposition','inquiry'),
    ('rfq_archives','inquiry'), ('rfq_clarification','inquiry'),
    ('quotes','quote'), ('quote_items','quote'), ('quote_reviews','quote'), ('quote_review_messages','quote'),
    ('quote_requirements','quote'), ('quote_committed_items','quote'), ('quote_comparisons','quote'), ('quote_spec_hold','quote'),
    ('spec_alternative_offer','quote'), ('po_orders','quote'), ('po_vendors','quote'), ('questions','quote'), ('reviews','quote'),
    ('category_specs','quote rules'), ('category_quote_specs','quote rules'),
    ('transactions','payment'), ('reveal_invoices','payment'), ('supplier_dues','payment'), ('refunds','payment'),
    ('refund_case','payment'), ('refund_incident','payment'), ('refund_ceo_review','payment'), ('refund_ceo_check','payment'),
    ('refund_ladder_evidence','payment'), ('refund_status_transition','payment'), ('stripe_events','payment'),
    ('stripe_payout','payment'), ('stripe_dispute','payment'), ('charge_audit','payment'), ('pricing_config','payment'),
    ('gl_journal','accounting'), ('gl_journal_lines','accounting'), ('gl_expense_map','accounting'), ('expenses','accounting'),
    ('expense_entries','accounting'), ('bank_statement_intake','accounting'), ('bank_statement_line','accounting'),
    ('accountant_month_close','accounting'), ('accountant_issued_document','accounting'),
    ('messages','conversation'), ('chat_threads','conversation'), ('conversation_archive','conversation'),
    ('inbound_messages','conversation'), ('contact_messages','conversation'), ('complaint_tickets','conversation'),
    ('support_case','conversation'), ('support_notification','conversation'), ('support_document_intake','conversation'),
    ('wa_messages','conversation'), ('wa_conversation','conversation'), ('wa_turn','conversation'),
    ('wa_document_intake','conversation'), ('notifications','conversation'), ('agent_chats','conversation'),
    ('legal_reviews','legal'), ('pdpl_requests','legal'), ('pdpl_erase_files','legal'), ('email_suppressions','legal'),
    ('founder_instruction','decision'), ('company_policy_decision','decision'),
    ('kb_chunks','knowledge'), ('dept_library','knowledge'), ('ops_knowledge','knowledge'), ('agent_knowledge','knowledge'),
    ('sales_knowledge','knowledge'), ('ceo_knowledge','knowledge'), ('support_knowledge','knowledge'),
    ('accountant_knowledge','knowledge'), ('it_engineer_knowledge','knowledge'), ('employee_knowledge','knowledge'),
    ('marketing_post','marketing'), ('marketing_connection_check','marketing'), ('marketing_insight_day','marketing'),
    ('marketing_ad_spend_day','marketing'), ('marketing_duty_run','marketing'), ('marketing_report','marketing'),
    ('marketing_article','marketing'), ('marketing_prospect','marketing'), ('marketing_outreach_message','marketing'),
    ('marketing_platform_spec','marketing'), ('marketing_platform_spec_source','marketing'),
    ('marketing_campaign','marketing'), ('marketing_founder_request','marketing'), ('marketing_video_idea','marketing'), ('supplier_campaign_daily_list','supplier'), ('marketing_post_variant','marketing'),
    ('marketing_post_platform','marketing'), ('marketing_post_channel_result','marketing'), ('marketing_calendar_resend_decision','marketing'), ('marketing_post_metric','marketing'), ('marketing_first_touch','marketing'),
    ('marketing_goal','marketing'), ('marketing_scorecard_report','marketing'),
    ('marketing_asset_feature','marketing'), ('marketing_asset_perception','marketing'), ('marketing_asset_review','marketing'),
    ('marketing_insight_note','marketing'), ('marketing_month_plan','marketing'), ('marketing_plan_review_turn','marketing'),
    ('marketing_model_run','marketing'), ('marketing_trend_source','marketing'), ('marketing_trend','marketing'),
    ('marketing_geo_question','marketing'), ('marketing_geo_check','marketing'), ('marketing_review','marketing'), ('market_intel','marketing'), ('competitor','marketing'), ('marketing_knowledge','knowledge'),
    ('marketing_recruitment_source','marketing'), ('marketing_gap_recruitment_plan','marketing'),
    ('table_export_change','backup')
  ) v(t, s)
  -- The sibling PRs' tables may not exist yet when this applies; backup/index.ts fails the whole day on a
  -- missing table, so ONLY those nine are skipped until their own file creates them. Every other table in the
  -- list still fails loudly if it disappears.
  where v.t not in ('marketing_platform_spec','marketing_platform_spec_source','marketing_campaign','marketing_post_variant',
                    'marketing_post_platform','marketing_post_metric','marketing_first_touch','marketing_goal','marketing_scorecard_report')
     or to_regclass('public.' || v.t) is not null
$fn$;

revoke execute on function public.fn_table_export_list() from public, anon, authenticated;
