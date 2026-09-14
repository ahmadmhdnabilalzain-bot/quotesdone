-- every_intake_trade_resolves_to_the_capability_vocabulary — 14 Sep 2026. Assigned: sales_engineer.
--
-- MEASURED (production, 14 Sep 2026). Two vocabularies name a trade:
--   * the intake's checklist slugs (category_specs.category; inquiries.category and .trades): 56
--   * the capability matcher's codes (taxonomy_trade.code; supplier_capabilities.trades): 40
-- sales_engineer's `match` passed an inquiry's stored intake slugs STRAIGHT to fn_match_capability,
-- whose gate is `sc.trades && p_trades`. 39 of the 56 slugs are not taxonomy codes (glass vs
-- glazing, fitout vs interior_fitout, carpentry vs joinery, safety vs fire_fighting ...), so every
-- request in those 39 categories matched ZERO suppliers; the router's "no fit" answer is respected,
-- so the keyword fallback was suppressed and the request reached nobody. Measured directly:
-- fn_match_capability(['aluminium']) returned both demo aluminium suppliers; (['glass']) returned
-- none, while the same suppliers' neighbour code 'glazing' is what "glass" means in taxonomy_trade.
-- fn_norm_trades resolves some slugs but maps 13 to nothing and a few by keyword accident.
--
-- WHAT THIS CHANGES.
--   1. public.intake_trade_taxonomy — the explicit slug -> codes mapping, one row per intake slug
--      that is not itself a code. Reviewed by hand, not derived by keyword.
--   2. public.fn_taxonomy_trades_for(text[]) — THE resolver: a slug that is an active taxonomy code
--      passes through; a mapped slug resolves to its codes; anything else resolves to nothing. Only
--      active codes are ever returned. sales_engineer resolves stored trades through it.
--   3. A probe: every category_specs slug resolves to at least one active code, except the named
--      slugs that deliberately have none (general, general-services-other, pest — taxonomy_trade
--      has no pest-control trade; that is a taxonomy gap, stated here, not papered over).
--
-- WHAT IT DOES NOT CHANGE. taxonomy_trade, category_specs, fn_match_capability, or any supplier's
-- registered capability. It also does not create suppliers: on 14 Sep 2026 0 of 22,264 real leads
-- are verified, so a real request reaches nobody until real suppliers finish verification — a
-- registration fact this file cannot and does not change.

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

insert into public.intake_trade_taxonomy (intake_slug, trade_codes, note) values
  ('acrylic',                   '{signage}',                      'acrylic fabrication is sold as signage and displays'),
  ('av-systems',                '{av_it}',                        null),
  ('blinds-curtains',           '{upholstery}',                   null),
  ('carpentry',                 '{joinery}',                      null),
  ('carpentry-joinery',         '{joinery}',                      null),
  ('carpets',                   '{flooring}',                     null),
  ('combined-mep',              '{mep_general}',                  null),
  ('commercial-retail-fitout',  '{interior_fitout}',              null),
  ('custom-furniture',          '{joinery}',                      null),
  ('demolition',                '{civil_works}',                  null),
  ('engineering-and-architectural-consultancies', '{engineering_consultancy}', null),
  ('epoxy-flooring',            '{flooring}',                     null),
  ('facade-cleaning',           '{cleaning}',                     'fn_norm_trades also returned aluminium, by the word facade'),
  ('fitout',                    '{interior_fitout}',              null),
  ('garage-doors',              '{doors}',                        null),
  ('general-building-contracting', '{civil_works}',               null),
  ('generators',                '{power_generators}',             null),
  ('glass',                     '{glazing}',                      null),
  ('insulation',                '{waterproofing}',                'taxonomy_trade has no insulation trade; waterproofing contractors carry it'),
  ('interior-design',           '{interior_fitout}',              null),
  ('it-networking',             '{av_it,it_services}',            null),
  ('job-shop-manufacturing',    '{steel}',                        'fabrication shops are registered under steel'),
  ('kitchens',                  '{joinery}',                      null),
  ('marble-granite',            '{flooring}',                     null),
  ('masonry',                   '{civil_works}',                  null),
  ('mep',                       '{mep_general}',                  null),
  ('movers',                    '{logistics_moving}',             null),
  ('roofing',                   '{waterproofing,civil_works}',    null),
  ('safety',                    '{fire_fighting,safety_equipment}', 'fire alarm, detection and fire fighting (checklist "Fire Safety & Fire Fighting")'),
  ('security',                  '{security_systems}',             null),
  ('smart-home',                '{home_automation}',              null),
  ('structural-steel-fabrication', '{steel}',                     null),
  ('swimming-pools',            '{landscaping}',                  'taxonomy_trade has no pool trade; pool builders register as landscaping'),
  ('tents-and-shade-structures','{steel}',                        null),
  ('tiling',                    '{flooring}',                     null),
  ('water-tank-cleaning',       '{cleaning}',                     null)
on conflict (intake_slug) do update set trade_codes = excluded.trade_codes, note = excluded.note;

create or replace function public.fn_taxonomy_trades_for(p_slugs text[])
returns text[]
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  -- A taxonomy code passes through; an intake slug resolves through intake_trade_taxonomy; anything
  -- else resolves to nothing. Only ACTIVE codes are returned, so a retired code never gates a match.
  select coalesce(array_agg(distinct x.code order by x.code), '{}'::text[])
    from (
      select t.code
        from unnest(coalesce(p_slugs, '{}'::text[])) s
        join public.taxonomy_trade t on t.code = lower(btrim(s))
      union
      select unnest(m.trade_codes)
        from unnest(coalesce(p_slugs, '{}'::text[])) s
        join public.intake_trade_taxonomy m on m.intake_slug = lower(btrim(s))
    ) x
    join public.taxonomy_trade t on t.code = x.code and t.active;
$fn$;

revoke execute on function public.fn_taxonomy_trades_for(text[]) from public, anon, authenticated;

do $chk$
declare
  unresolved text[];
  bad_codes text[];
  a text[]; g text[];
begin
  select array_agg(cs.category order by cs.category) into unresolved
    from (select distinct category from public.category_specs) cs
   where cardinality(public.fn_taxonomy_trades_for(array[cs.category])) = 0
     and cs.category not in ('general', 'general-services-other', 'pest');
  select array_agg(distinct c) into bad_codes
    from public.intake_trade_taxonomy m, unnest(m.trade_codes) c
   where not exists (select 1 from public.taxonomy_trade t where t.code = c and t.active);
  a := public.fn_taxonomy_trades_for(array['aluminium']);
  g := public.fn_taxonomy_trades_for(array['glass']);
  if unresolved is not null or bad_codes is not null or a <> array['aluminium'] or g <> array['glazing'] then
    raise exception 'resolver wrong: unresolved slugs %, unknown codes %, aluminium -> %, glass -> %', unresolved, bad_codes, a, g;
  end if;
  raise notice 'CHK<<every intake slug resolves; aluminium -> %, glass -> %>>', a, g;
end $chk$;
