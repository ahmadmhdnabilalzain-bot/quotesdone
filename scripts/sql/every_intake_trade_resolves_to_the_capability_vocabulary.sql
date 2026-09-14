-- every_intake_trade_resolves_to_the_capability_vocabulary — 14 Sep 2026. Assigned: sales_engineer.
--
-- MEASURED (production, 14 Sep 2026). Two vocabularies name a trade:
--   * the intake's checklist slugs (category_specs.category; inquiries.category and .trades): 56
--   * the capability matcher's codes (taxonomy_trade.code; supplier_capabilities.trades): 40
-- sales_engineer's `match` passed an inquiry's stored intake slugs STRAIGHT to fn_match_capability,
-- whose gate is `sc.trades && p_trades`. 39 of the 56 slugs are not taxonomy codes (glass vs
-- glazing, fitout vs interior_fitout, carpentry vs joinery ...), so every request in those 39
-- categories matched ZERO suppliers even when a supplier of that very trade was registered.
-- Measured: fn_match_capability(['aluminium']) returned both demo aluminium suppliers; (['glass'])
-- returned none, though "glass" is listed in taxonomy_trade.aliases of 'glazing'.
--
-- THE FOUNDER'S RULINGS, 14 Sep 2026, verbatim — they decide everything below:
--   "there is nothing called nearest match. either exact match or no match"
--   "and btw our categories are not finalized. if a supplier comes tomorrow and register for
--    packaging services he is welcomed"
--
-- WHAT THIS CHANGES.
--   1. public.fn_trade_code(text) — the ONE normaliser of a trade name: lower case, every run of
--      non-letters/digits becomes '_'. 'Packaging services', 'packaging-services' and
--      'packaging_services' are the same code. supplier_capability.ts (tradeCode) is its TS twin.
--   2. public.intake_trade_taxonomy — intake slug -> the SAME trade under its taxonomy name. A row is
--      admitted only when taxonomy_trade itself names the slug's trade in that code's label or
--      aliases (measured 14 Sep 2026 and quoted in `note`). A neighbouring trade is not the same
--      trade, so it is not a row. Removed on the ruling above (they were nearest, not exact):
--        acrylic -> signage            (signage lists "acrylic letters", not acrylic fabrication)
--        custom-furniture -> joinery   (joinery lists wardrobes and kitchens, not furniture)
--        job-shop-manufacturing -> steel
--        roofing -> waterproofing, civil_works   (neither names roofing)
--        tents-and-shade-structures -> steel
--        safety -> safety_equipment    (that code is PPE; fire safety is fire_fighting, which stays)
--   3. public.fn_taxonomy_trades_for(text[]) — THE resolver. Each name resolves to ITSELF (normalised)
--      plus the taxonomy code(s) of the same trade. Nothing else. So a supplier who registers a trade
--      nobody listed yet ("packaging services") is matched by a request whose category has that same
--      name, and by nothing else. A retired taxonomy code never gates a match.
--   A category with no supplier of its exact trade routes to no one. That is the correct answer:
--   sales_engineer's no-match path tells the customer so. There is no fallback to a neighbour.
--
-- WHAT IT DOES NOT CHANGE. taxonomy_trade, category_specs, fn_match_capability, or any supplier's
-- registered capability. It does not create suppliers: on 14 Sep 2026 0 of 22,264 real leads are
-- verified, so a real request reaches nobody until real suppliers finish verification.

create or replace function public.fn_trade_code(p_name text)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select nullif(btrim(regexp_replace(lower(btrim(coalesce(p_name, ''))), '[^[:alnum:]]+', '_', 'g'), '_'), '');
$fn$;

revoke execute on function public.fn_trade_code(text) from public, anon, authenticated;

create table if not exists public.intake_trade_taxonomy (
  intake_slug text primary key,
  trade_codes text[] not null check (cardinality(trade_codes) > 0),
  note text
);
alter table public.intake_trade_taxonomy enable row level security;
do $pol$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'intake_trade_taxonomy' and policyname = 'intake_trade_taxonomy_service_role_only') then
    create policy intake_trade_taxonomy_service_role_only on public.intake_trade_taxonomy as permissive for all to public using (false) with check (false);
  end if;
end $pol$;
revoke all on public.intake_trade_taxonomy from anon, authenticated;

-- This file owns every row of the table, so it reloads it whole: a mapping removed here is removed
-- from production on the next apply, not left behind by an upsert.
delete from public.intake_trade_taxonomy;
insert into public.intake_trade_taxonomy (intake_slug, trade_codes, note) values
  ('av-systems',                '{av_it}',                        'av_it aliases: audio visual'),
  ('blinds-curtains',           '{upholstery}',                   'upholstery = "Upholstery & soft furnishing"; aliases: curtains, blinds'),
  ('carpentry',                 '{joinery}',                      'joinery = "Joinery & carpentry"'),
  ('carpentry-joinery',         '{joinery}',                      'joinery = "Joinery & carpentry"'),
  ('carpets',                   '{flooring}',                     'flooring aliases: carpet'),
  ('combined-mep',              '{mep_general}',                  'mep_general = "MEP (combined)"'),
  ('commercial-retail-fitout',  '{interior_fitout}',              'interior_fitout aliases: fitout'),
  ('demolition',                '{civil_works}',                  'civil_works aliases: demolition'),
  ('engineering-and-architectural-consultancies', '{engineering_consultancy}', 'engineering_consultancy = "Engineering Consultancy & Architecture"'),
  ('epoxy-flooring',            '{flooring}',                     'flooring aliases: epoxy floor'),
  ('facade-cleaning',           '{cleaning}',                     'cleaning aliases: cleaning'),
  ('fitout',                    '{interior_fitout}',              'interior_fitout aliases: fitout'),
  ('garage-doors',              '{doors}',                        'doors aliases: door, shutter'),
  ('general-building-contracting', '{civil_works}',               'civil_works aliases: general contracting, building contractor'),
  ('generators',                '{power_generators}',             'power_generators aliases: generators'),
  ('glass',                     '{glazing}',                      'glazing = "Glass & glazing"'),
  ('insulation',                '{waterproofing}',                'waterproofing = "Waterproofing & insulation"'),
  ('interior-design',           '{interior_fitout}',              'interior_fitout aliases: interior design'),
  ('it-networking',             '{av_it,it_services}',            'it_services = "IT & Network Services"; av_it aliases: networking'),
  ('kitchens',                  '{joinery}',                      'joinery aliases: kitchens'),
  ('marble-granite',            '{flooring}',                     'flooring aliases: marble'),
  ('masonry',                   '{civil_works}',                  'civil_works aliases: masonry'),
  ('mep',                       '{mep_general}',                  'mep_general aliases: mep'),
  ('movers',                    '{logistics_moving}',             'logistics_moving aliases: movers and packers'),
  ('safety',                    '{fire_fighting}',                'checklist "Fire Safety & Fire Fighting"; fire_fighting aliases: fire alarm, life safety'),
  ('security',                  '{security_systems}',             'security_systems = "Security systems"'),
  ('smart-home',                '{home_automation}',              'home_automation aliases: smart home'),
  ('structural-steel-fabrication', '{steel}',                     'steel aliases: structural steel, metal fabrication'),
  ('swimming-pools',            '{landscaping}',                  'landscaping = "Landscaping & pools"; aliases: swimming pool'),
  ('tiling',                    '{flooring}',                     'flooring aliases: tiling'),
  ('water-tank-cleaning',       '{cleaning}',                     'cleaning aliases: cleaning');

create or replace function public.fn_taxonomy_trades_for(p_slugs text[])
returns text[]
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  -- Each name resolves to itself (normalised) and to the taxonomy code(s) of the same trade. Never to a
  -- neighbour. A retired taxonomy code is dropped, so it never gates a match.
  select coalesce(array_agg(distinct x.code order by x.code), '{}'::text[])
    from (
      select public.fn_trade_code(s) as code
        from unnest(coalesce(p_slugs, '{}'::text[])) s
      union
      select unnest(m.trade_codes)
        from unnest(coalesce(p_slugs, '{}'::text[])) s
        join public.intake_trade_taxonomy m on public.fn_trade_code(m.intake_slug) = public.fn_trade_code(s)
    ) x
   where x.code is not null
     and not exists (select 1 from public.taxonomy_trade t where t.code = x.code and not t.active);
$fn$;

revoke execute on function public.fn_taxonomy_trades_for(text[]) from public, anon, authenticated;

-- Probe. This file defines routines, so a pass ends in `raise notice`; a failure raises and rolls the
-- whole file back, which is what a wrong resolver deserves.
do $chk$
declare
  bad_codes text[];
  r jsonb;
begin
  select array_agg(distinct c) into bad_codes
    from public.intake_trade_taxonomy m, unnest(m.trade_codes) c
   where not exists (select 1 from public.taxonomy_trade t where t.code = c and t.active);
  r := jsonb_build_object(
    'aluminium', public.fn_taxonomy_trades_for(array['aluminium']),
    'glass',     public.fn_taxonomy_trades_for(array['glass']),
    'safety',    public.fn_taxonomy_trades_for(array['safety']),
    'roofing',   public.fn_taxonomy_trades_for(array['roofing']),
    'acrylic',   public.fn_taxonomy_trades_for(array['acrylic']),
    'new_cat',   public.fn_taxonomy_trades_for(array['packaging-services']),
    'new_reg',   public.fn_taxonomy_trades_for(array['Packaging Services']),
    'new_ar',    public.fn_taxonomy_trades_for(array[' خدمات التغليف ']));
  if bad_codes is not null
     or r->'aluminium' <> '["aluminium"]'::jsonb
     or r->'glass'     <> '["glass", "glazing"]'::jsonb
     or r->'safety'    <> '["fire_fighting", "safety"]'::jsonb
     or r->'roofing'   <> '["roofing"]'::jsonb
     or r->'acrylic'   <> '["acrylic"]'::jsonb
     or r->'new_cat'   <> '["packaging_services"]'::jsonb
     or r->'new_reg'   <> '["packaging_services"]'::jsonb
     or r->'new_ar'    <> '["خدمات_التغليف"]'::jsonb then
    raise exception 'resolver wrong: unknown codes %, results %', bad_codes, r;
  end if;
  raise notice 'CHK<<exact-only resolver: %>>', r;
end $chk$;
