-- fn_kb_route_activation_blocked — two of its three block reasons THROW instead of blocking.
--
-- FOUND BY PROBE, not by reading. The aborted-transaction probe for the new activation gate on
-- fn_kb_retrieve removed catalog 1's Arabic aliases and expected 'blocked'. It got:
--
--   ERROR 22P02 malformed array literal: "no Arabic alias"
--   QUERY: v_reasons := v_reasons || 'no Arabic alias'
--
-- v_reasons is text[]. `text[] || 'literal'` with an untyped literal resolves to the array||array
-- operator, so Postgres parses the reason string as an array literal and raises. The first branch
-- escapes it only because ('regulatory coverage is ' || r.regulatory_coverage_status) is already
-- typed text. The two bare-literal branches — 'no mapped subcategory' and 'no Arabic alias' —
-- have never run, because every one of the 86 routes has a mapped subcategory and an Arabic
-- alias, so the defect sat behind a condition that was always false.
--
-- It matters now: fn_kb_retrieve gates on this function, so a route that lost its Arabic alias
-- would have raised inside every AI context build rather than quietly closing the route.
create or replace function public.fn_kb_route_activation_blocked(p_catalog_num integer)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare r record; v_reasons text[] := '{}';
begin
  select * into r from public.kb_operational_route where catalog_num = p_catalog_num;
  if not found then
    return jsonb_build_object('blocked', true, 'reasons', array['no such route']);
  end if;

  if r.regulatory_coverage_status <> 'confirmed_none'
     and r.regulatory_coverage_status <> 'confirmed_covered' then
    v_reasons := v_reasons || ('regulatory coverage is ' || r.regulatory_coverage_status)::text;
  end if;

  if not exists (select 1 from public.kb_operational_route_map m where m.catalog_num = p_catalog_num) then
    v_reasons := v_reasons || 'no mapped subcategory'::text;
  end if;

  if not exists (select 1 from public.kb_operational_alias a
                  where a.catalog_num = p_catalog_num and a.language = 'ar') then
    v_reasons := v_reasons || 'no Arabic alias'::text;
  end if;

  return jsonb_build_object('blocked', array_length(v_reasons, 1) is not null,
                            'reasons', coalesce(v_reasons, '{}'),
                            'regulatory_coverage_status', r.regulatory_coverage_status,
                            'route', r.catalog_name);
end $function$;

-- GRANTS ARE DELIBERATELY NOT TOUCHED. CREATE OR REPLACE preserves the existing ACL — it is
-- CREATE of a NEW function that grants EXECUTE to PUBLIC — so a revoke here would REMOVE a grant
-- that was already decided rather than undo one I added. The before/after ACL is asserted in the
-- session record instead.
