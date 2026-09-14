-- fire_alarm_and_elv_catalogues_reach_their_checklists — 14 Sep 2026. Assigned: sales_engineer.
--
-- MEASURED. fn_intake_slug_for_catalog maps a catalogue category to the intake checklist that owns
-- it, through public.lead_trade_map. For catalogue 13 (fire-alarm-and-life-safety-suppliers) and
-- catalogue 14 (elv-and-security-systems-suppliers) it returned NULL: lead_trade_map had rows for
-- fire-fighting-equipment-suppliers (safety, fire_fighting) and for elv-and-security-systems-suppliers
-- only under 'security_systems', which is not a category_specs key. So when inquiry_intake's router
-- (fn_kb_route_decide) resolved "Ground floor fire alarm system layout, smoke detectors and call
-- points" to catalogue 13 at confidence 1.000 — which it does — the intake could not turn that into
-- a checklist, and the request fell back to keyword guessing, which filed it as flooring.
--
-- WHAT THIS CHANGES. Two mapping rows, to checklists that exist in category_specs:
--   fire-alarm-and-life-safety-suppliers -> safety    ("Fire Safety & Fire Fighting")
--   elv-and-security-systems-suppliers   -> security  ("CCTV & Security Systems")
-- Idempotent: inserted only where the (trade_key, catalog_slug) pair is absent.
--
-- WHAT IT DOES NOT CHANGE. fn_intake_slug_for_catalog itself, the router, or any other mapping.
-- Catalogues 3 (cement & concrete) and 26 (cold rooms) also map to nothing; they are not this build's
-- subject and are left as they are.

insert into public.lead_trade_map (trade_key, catalog_slug, confidence, note)
select v.trade_key, v.catalog_slug, 'high', v.note
  from (values
    ('safety',   'fire-alarm-and-life-safety-suppliers', 'fire alarm, detection and life safety share the Fire Safety & Fire Fighting checklist (14 Sep 2026)'),
    ('security', 'elv-and-security-systems-suppliers',   'ELV and security systems reach the CCTV & Security Systems checklist (14 Sep 2026)')
  ) as v(trade_key, catalog_slug, note)
 where not exists (select 1 from public.lead_trade_map m where m.trade_key = v.trade_key and m.catalog_slug = v.catalog_slug);

do $chk$
declare a text; b text;
begin
  a := public.fn_intake_slug_for_catalog('fire-alarm-and-life-safety-suppliers');
  b := public.fn_intake_slug_for_catalog('elv-and-security-systems-suppliers');
  if a is distinct from 'safety' or b is distinct from 'security' then
    raise exception 'mapping did not take: fire-alarm -> %, elv -> %', a, b;
  end if;
  raise notice 'CHK<<fire-alarm -> %, elv -> %>>', a, b;
end $chk$;
