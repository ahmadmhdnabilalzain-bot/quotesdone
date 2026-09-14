-- fire_alarm_and_elv_catalogues_reach_their_checklists — 14 Sep 2026. Assigned: sales_engineer.
--
-- MEASURED. fn_intake_slug_for_catalog maps a catalogue category to the intake checklist that owns
-- it, through public.lead_trade_map. For catalogue 13 (fire-alarm-and-life-safety-suppliers) and
-- catalogue 14 (elv-and-security-systems-suppliers) it returned NULL. So when inquiry_intake's router
-- (fn_kb_route_decide) resolved "Ground floor fire alarm system layout, smoke detectors and call
-- points" to catalogue 13 at confidence 1.000 — which it does — the intake could not turn that into a
-- checklist and fell back to keyword guessing, which filed the founder's fire alarm drawing as
-- flooring.
--
-- WHY NOT A lead_trade_map ROW. The first version of this file inserted ('safety', catalogue 13) and
-- ('security', catalogue 14). lead_trade_map's primary key is trade_key ALONE, and both keys are
-- already taken (safety -> fire-fighting-equipment-suppliers, security -> security-companies), so
-- the insert failed with 23505 and rolled back; nothing was written. A trade key can name only one
-- catalogue there, and the checklists these two catalogues need already have theirs.
--
-- WHAT THIS CHANGES. fn_intake_slug_for_catalog gains an explicit override for exactly those two
-- catalogues — to the checklists that exist in category_specs:
--   fire-alarm-and-life-safety-suppliers -> safety    ("Fire Safety & Fire Fighting")
--   elv-and-security-systems-suppliers   -> security  ("CCTV & Security Systems")
-- — and otherwise answers exactly as before (the original body is below, unchanged). The override
-- only applies when its target slug exists in category_specs, the same eligibility rule the original
-- enforces. search_path now also pins pg_temp. CREATE OR REPLACE keeps the routine's grants.
--
-- WHAT IT DOES NOT CHANGE. lead_trade_map, the router, or any other catalogue's answer. Catalogues 3
-- (cement & concrete) and 26 (cold rooms) also map to nothing; they are not this build's subject.

create or replace function public.fn_intake_slug_for_catalog(p_catalog_slug text)
 returns text
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  -- The reverse of fn_category_knowledge: catalogue slug -> the legacy intake slug that owns the
  -- checklist. It is 1-to-many (flooring-suppliers is reached by carpets, epoxy-flooring, flooring,
  -- marble-granite and tiling), so the choice has to be deterministic or the same customer wording
  -- would land on a different checklist run to run.
  --
  -- Prefer a key the catalogue slug actually BEGINS with - 'flooring' for flooring-suppliers,
  -- 'aluminium' for aluminium-and-glass-suppliers, 'mep' for mep-suppliers-electromechanical.
  -- That picks the base trade over a facet of it. Where none prefixes, the shortest wins, which
  -- also prefers the base ('carpentry' over 'carpentry-joinery', 'fitout' over
  -- 'commercial-retail-fitout'). Only keys that exist in category_specs are eligible, because the
  -- answer has to be something the checklist lookup can actually use.
  --
  -- 14 Sep 2026: two catalogues whose checklist key is already another catalogue's in lead_trade_map
  -- (its primary key is trade_key) are named here; see the header of this file.
  select coalesce(
    (select v.intake
       from (values ('fire-alarm-and-life-safety-suppliers', 'safety'),
                    ('elv-and-security-systems-suppliers',   'security')) as v(slug, intake)
       join (select distinct category from public.category_specs) cs on cs.category = v.intake
      where v.slug = p_catalog_slug),
    (select m.trade_key
       from public.lead_trade_map m
       join (select distinct category from public.category_specs) cs on cs.category = m.trade_key
      where m.catalog_slug = p_catalog_slug
      order by (p_catalog_slug like m.trade_key || '%') desc, length(m.trade_key) asc, m.trade_key asc
      limit 1));
$function$;

do $chk$
declare a text; b text; c text; d text;
begin
  a := public.fn_intake_slug_for_catalog('fire-alarm-and-life-safety-suppliers');
  b := public.fn_intake_slug_for_catalog('elv-and-security-systems-suppliers');
  c := public.fn_intake_slug_for_catalog('flooring-suppliers');            -- unchanged: flooring
  d := public.fn_intake_slug_for_catalog('fire-fighting-equipment-suppliers'); -- unchanged: safety
  if a is distinct from 'safety' or b is distinct from 'security' or c is distinct from 'flooring' or d is distinct from 'safety' then
    raise exception 'mapping wrong: fire-alarm -> %, elv -> %, flooring -> %, fire-fighting -> %', a, b, c, d;
  end if;
  raise notice 'CHK<<fire-alarm -> %, elv -> %, flooring -> %, fire-fighting -> %>>', a, b, c, d;
end $chk$;
