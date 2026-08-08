-- ================================================================================================
-- ROW #6 §12 — mech-resolve-legacy-vocab: the resolver must speak the vocabulary the intake sends.
--
-- ── THE MEASUREMENT THAT ORDERED THIS ───────────────────────────────────────────────────────────
-- Production, 2026-08-09:
--
--   fn_resolve_cat_agent over the 84 catalogue slugs        84 of 84 resolve
--   fn_resolve_cat_agent over the 56 live intake slugs      36 of 56 resolve   <- the gap
--   fn_category_knowledge over the same 56                  51 of 56 answer
--
-- Two routines, one job, two different answers — because only ONE of them knows the bridge exists.
-- fn_category_knowledge already walks `lead_trade_map` and says so in its own header:
--
--     "All 84 spec categories carry their 8 modules under agent_key 'cat:<catalogue-slug>', but the
--      live intake assigns one of 56 LEGACY slugs whose overlap with the catalogue is exactly zero.
--      lead_trade_map is the bridge; this is the first thing that walks it at read time."
--
-- fn_resolve_cat_agent was never updated. It has three hops — exact category_agents slug, exact
-- agent_knowledge key, then a LIKE against the agent's display name — and the third is why it gets
-- 36 rather than 0: 'hvac' happens to be a substring of 'hvac-suppliers'. That is coincidence doing
-- the work of a mapping. 'tiling' does not appear in 'tiling-marble-suppliers' as the LIKE needs it,
-- 'movers' matches nothing at all, and no amount of loosening the LIKE fixes that without also
-- matching things it should not.
--
-- ── WHAT CHANGES: ONE HOP, INSERTED BEFORE THE FUZZY ONE ────────────────────────────────────────
-- The exact-match hops are untouched and still run first, so nothing that resolves today resolves
-- differently. The bridge is consulted BEFORE the name LIKE, because a declared mapping must beat a
-- substring coincidence: where lead_trade_map says 'tiling' -> 'tiling-and-marble-suppliers', that
-- is a decision somebody made, and the LIKE is a guess.
--
-- The hop requires the target to actually HOLD knowledge (`exists ... agent_knowledge`). A bridge
-- row pointing at an empty namespace is not a resolution — it is a resolution-shaped null, and
-- returning one would turn "this category has no agent" into "this category has an agent that
-- returns nothing", which is strictly worse to debug.
--
-- NOT FIXED HERE, AND DELIBERATELY: the trade keys with no lead_trade_map row at all. That is
-- missing DATA — a mapping decision about which catalogue category 'movers' belongs to — and
-- inventing those rows to raise a score is exactly the fabrication the founder's rules forbid.
-- The scorer prints the residual count so the remainder stays visible as a data gap, not a code one.
-- ================================================================================================
create or replace function public.fn_resolve_cat_agent(cat text)
returns text
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare k text; c text := lower(trim(coalesce(cat,'')));
begin
  if c = '' then return null; end if;

  -- Hop 1 and 2, unchanged: the caller already holds a catalogue slug.
  if exists(select 1 from category_agents where slug=c and coalesce(active,true)) then return 'cat:'||c; end if;
  if exists(select 1 from agent_knowledge where agent_key='cat:'||c limit 1) then return 'cat:'||c; end if;

  -- Hop 3, NEW: the declared trade -> catalogue bridge, the same one fn_category_knowledge walks.
  -- Before the name LIKE, because a mapping somebody decided beats a substring that happens to hit.
  select 'cat:'||m.catalog_slug into k
    from lead_trade_map m
   where m.trade_key = c
     and exists (select 1 from agent_knowledge a where a.agent_key = 'cat:'||m.catalog_slug)
   limit 1;
  if k is not null then return k; end if;

  -- Hop 4, unchanged: the display-name fallback, now only reached when nothing declared a mapping.
  select 'cat:'||slug into k from category_agents
    where coalesce(active,true) and (lower(name) like '%'||c||'%' or c like '%'||slug||'%' or lower(name)=c)
    order by length(slug) desc limit 1;
  return k;
end $function$;
