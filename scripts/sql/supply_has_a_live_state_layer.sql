-- SUPPLY HAS A LIVE-STATE LAYER (6 Sep 2026). Knowledge audit docs/knowledge_audit/supply.md finding S-2.
--
-- MEASURED: org_departments.supply.health_fn was NULL, so "# LAYER 3 - LIVE OPERATIONAL STATE" was
-- absent from all six Supply contexts (bd, onboarding, partnerships_mgr, supplier_coverage,
-- supplier_retention, supplier_verification). A Supply agent could not see the lead pool, the invite
-- funnel, approvals, licence expiries or category depth from its own context - the numbers its charter
-- is about. fn_ws_suppliers() exists but returns ~35,000 chars of supplier ROWS; the head's LAYER 3 slot
-- is ~1,500 chars, so pointing at it would have carried two supplier rows and no funnel.
--
-- fn_ws_supply() is the funnel in one bounded object: pool by lifecycle stage, invites in the last
-- 7 days, approval/verification counts, matching blocks, licences expiring in 30 days, and category
-- depth (compliant / thin / none, plus the six thinnest catalogue routes). Read live on every call,
-- one pass over leads (~22k rows) and v_category_coverage; measured 0.3 s.
--
--   node scripts/apply_sql.mjs scripts/sql/supply_has_a_live_state_layer.sql --apply --ddl

begin;

create or replace function public.fn_ws_supply()
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  select jsonb_build_object(
    'read_at', now(),
    'lead_pool', (select jsonb_build_object(
        'total', count(*),
        'not_contacted', count(*) filter (where lifecycle_stage = 'not_contacted'),
        'invited', count(*) filter (where invite_status = 'sent'),
        'no_response', count(*) filter (where lifecycle_stage = 'no_response'),
        'undeliverable', count(*) filter (where lifecycle_stage = 'undeliverable'),
        'registered', count(*) filter (where lifecycle_stage = 'registered'),
        'claimed', count(*) filter (where coalesce(claimed, false)),
        'approved', count(*) filter (where approval_status = 'approved'),
        'pending_review', count(*) filter (where approval_status = 'pending_review'),
        'verified', count(*) filter (where coalesce(verified, false)),
        'matching_blocked', count(*) filter (where coalesce(matching_blocked, false)),
        'banned', count(*) filter (where coalesce(banned, false)),
        'wa_optin', count(*) filter (where coalesce(wa_optin, false)))
      from public.leads),
    'invites_last_7d', (select count(*) from public.leads where invited_at > now() - interval '7 days'),
    'registrations_last_30d', (select count(*) from public.leads where registration_submitted_at > now() - interval '30 days'),
    'licences_expiring_30d', (select count(*) from public.leads
                               where approval_status = 'approved'
                                 and license_expiry between current_date and current_date + 30),
    'category_depth', (select jsonb_build_object(
        'routes', count(*),
        'compliant', count(*) filter (where coverage = 'COMPLIANT'),
        'thin_under_5_suppliers', count(*) filter (where coalesce(supplier_supply, 0) between 1 and 4),
        'no_supply', count(*) filter (where coalesce(supplier_supply, 0) = 0))
      from public.v_category_coverage),
    'thinnest_routes', (select coalesce(jsonb_agg(jsonb_build_object('route', t.catalog_slug, 'suppliers', t.supplier_supply)
                                                  order by t.supplier_supply nulls first, t.catalog_slug), '[]'::jsonb)
                          from (select catalog_slug, supplier_supply from public.v_category_coverage
                                 order by supplier_supply nulls first, catalog_slug limit 6) t),
    'blocked_for_non_response', (select coalesce(jsonb_agg(jsonb_build_object('lead', l.id, 'name', left(l.company_name, 50), 'reason', left(l.matching_block_reason, 80))
                                                           order by l.id), '[]'::jsonb)
                                   from (select id, company_name, matching_block_reason from public.leads
                                          where coalesce(matching_blocked, false) order by id limit 5) l));
$function$;

revoke execute on function public.fn_ws_supply() from public, anon, authenticated;
grant execute on function public.fn_ws_supply() to service_role;

update public.org_departments set health_fn = 'fn_ws_supply' where dept_key = 'supply' and health_fn is distinct from 'fn_ws_supply';

-- PROOF, in-file and read-only: every active Supply employee now carries LAYER 3 inside the 19,500
-- characters the capped path keeps.
do $proof$
declare r record; p int; n int := 0;
begin
  for r in select agent_key from public.org_agents where active and department = 'supply' order by 1 loop
    p := position('# LAYER 3 - LIVE OPERATIONAL STATE' in public.fn_agent_context(r.agent_key, 22000));
    if p = 0 or p > 19500 then raise exception 'supply agent % has LAYER 3 at position % (expected 1..19500)', r.agent_key, p; end if;
    n := n + 1;
  end loop;
  if n < 6 then raise exception 'expected 6 active supply agents, found %', n; end if;
end $proof$;

commit;
