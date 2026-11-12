-- PROBE (pure, no DDL, aborted transaction) for a_partner_service_is_matched_knowingly.sql.
-- Seat: sales_engineer. 12 Nov 2026, founder rulings 1647 / 1628; analysis services/REPORT.md 3.7.
-- Run AFTER the file, or with it, rolled back:
--   node scripts/ci/rehearse_sql.mjs scripts/sql/a_partner_service_is_matched_knowingly.sql scripts/sql/a_partner_service_is_matched_knowingly_probe.sql
-- It always ends in raise exception 'CHK<<json>>', so every row it writes rolls back; session_replication_role = replica
-- stops every trigger for this transaction only.
--
-- ITS SUBJECTS CANNOT REACH A PERSON: two matchable demo suppliers at @example.invalid that scripts/lib/demo_factory.mjs
-- built ('ZZ DEMO ...' or 'QD Demo ...'), the same two the own-words probe uses; their capability rows are rewritten here and
-- roll back. No inquiry is created, nothing is matched into inquiry_matches. Every other capability and every lead are
-- counted before and after and must not move.
--
-- A builds pools with his own team. B offers pool construction THROUGH A PARTNER and is given the request's product, so
-- his score is HIGHER than A's (40 points of product match): the order must still put A first.
--   1. both are matched for "pool construction"; A first; B's partner_hits is that key and his why says so; A's is empty
--   2. with p_limit 1 only A is returned
--   3. a key in services_partner that is not in services is not confirmed: B is matched for nothing
--   4. B mixed (pool maintenance himself, construction through the partner) is NOT partner-only: ordered by score, first
--   5. a request naming no service is untouched: no partner_hits, ordered by score as before (B first)
do $probe$
declare
  f text := ''; v_a bigint; v_b bigint; v_ids bigint[]; v_row record; v_first bigint;
  v_caps_before int; v_caps_after int; v_leads_before int; v_leads_after int;
  k text := 'swimming_pools.pool_construction'; m text := 'swimming_pools.pool_maintenance';
begin
  set local session_replication_role = replica;
  select count(*) into v_leads_before from public.leads;
  select array_agg(l.id order by l.id) into v_ids from (
    select l.id from public.leads l
     where l.company_name ~* '^\s*(zz|qd)\s*demo' and l.email like '%@example.invalid'
       and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
     order by l.id limit 2) l;
  if coalesce(cardinality(v_ids), 0) < 2 then
    raise exception 'CHK<<{"verdict":"PROBE FAILED: fewer than two matchable demo suppliers at @example.invalid"}>>';
  end if;
  v_a := v_ids[1]; v_b := v_ids[2];
  select count(*) into v_caps_before from public.supplier_capabilities where supplier_id not in (v_a, v_b);
  delete from public.supplier_availability where supplier_id in (v_a, v_b);
  insert into public.supplier_capabilities (supplier_id, trades, roles, services, confirmed_at, confirmed_version)
  values (v_a, '{}', array['contractor'], '{}', now(), 1), (v_b, '{}', array['contractor'], '{}', now(), 1)
  on conflict (supplier_id) do update set trades = '{}', roles = array['contractor'], services = '{}', services_removed = '{}',
    excluded_trades = '{}', coverage_emirates = '{}', min_project_value = null, max_project_value = null, confirmed_at = now();
  update public.supplier_capabilities sc set trades = array['swimming_pools'], products_norm = '{}', services_partner = '{}',
         services = array[k], authority_approvals = coalesce((select jsonb_object_agg(a, true) from public.taxonomy_trade t,
           unnest(t.authority_required) a where t.code = 'swimming_pools'), '{}'::jsonb)
   where sc.supplier_id in (v_a, v_b);
  update public.supplier_capabilities set services_partner = array[k], products_norm = array['pool pump'] where supplier_id = v_b;

  -- 1. both matched, own team first although B scores higher
  v_ids := array(select x.supplier_id from public.fn_match_capability(array['swimming_pools'], 'executes', array['pool pump'],
                   p_limit := 100000, p_services := array[k]) x where x.supplier_id in (v_a, v_b));
  if v_ids is distinct from array[v_a, v_b] then f := f || 'own team first: expected A then B, got ' || coalesce(v_ids::text, 'none') || '; '; end if;
  select x.* into v_row from public.fn_match_capability(array['swimming_pools'], 'executes', array['pool pump'],
           p_limit := 100000, p_services := array[k]) x where x.supplier_id = v_b;
  if v_row.partner_hits is distinct from array[k] or position('through a partner: ' || k in coalesce(v_row.why, '')) = 0 then
    f := f || 'B''s partner hit or why is wrong: ' || coalesce(v_row.partner_hits::text, 'null') || ' / ' || coalesce(v_row.why, 'null') || '; ';
  end if;
  if v_row.score <= (select x.score from public.fn_match_capability(array['swimming_pools'], 'executes', array['pool pump'],
           p_limit := 100000, p_services := array[k]) x where x.supplier_id = v_a) then
    f := f || 'the probe did not make B outscore A, so the order proves nothing; ';
  end if;
  if (select cardinality(x.partner_hits) from public.fn_match_capability(array['swimming_pools'], 'executes', p_limit := 100000,
        p_services := array[k]) x where x.supplier_id = v_a) <> 0 then f := f || 'A (own team) carries a partner hit; '; end if;

  -- 2. the limit drops the partner-only supplier first
  select x.supplier_id into v_first from public.fn_match_capability(array['swimming_pools'], 'executes', array['pool pump'],
           p_limit := 1, p_services := array[k]) x;
  if v_first is distinct from v_a then f := f || 'with p_limit 1 the partner-only supplier displaced the own team; '; end if;

  -- 3. an unconfirmed partner key matches nothing
  update public.supplier_capabilities set services = '{}' where supplier_id = v_b;
  if exists (select 1 from public.fn_match_capability(array['swimming_pools'], 'executes', p_limit := 100000, p_services := array[k]) x
              where x.supplier_id = v_b) then f := f || 'a partner key that is not a confirmed service matched; '; end if;

  -- 4. mixed: maintenance himself, construction through the partner: not partner-only, ordered by score (first)
  update public.supplier_capabilities set services = array[k, m], services_partner = array[k] where supplier_id = v_b;
  update public.supplier_capabilities set services = array[k, m] where supplier_id = v_a;
  v_ids := array(select x.supplier_id from public.fn_match_capability(array['swimming_pools'], 'executes', array['pool pump'],
                   p_limit := 100000, p_services := array[k, m]) x where x.supplier_id in (v_a, v_b));
  if v_ids is distinct from array[v_b, v_a] then f := f || 'a supplier doing part himself was ordered as partner-only: ' || coalesce(v_ids::text, 'none') || '; '; end if;
  if (select x.partner_hits from public.fn_match_capability(array['swimming_pools'], 'executes', p_limit := 100000,
        p_services := array[k, m]) x where x.supplier_id = v_b) is distinct from array[k] then f := f || 'the mixed supplier''s partner hits are wrong; '; end if;

  -- 5. no service named: untouched (B first on score, no partner hits)
  update public.supplier_capabilities set services = array[k], services_partner = array[k] where supplier_id = v_b;
  update public.supplier_capabilities set services = array[k] where supplier_id = v_a;
  v_ids := array(select x.supplier_id from public.fn_match_capability(array['swimming_pools'], 'executes', array['pool pump'], p_limit := 100000) x
                  where x.supplier_id in (v_a, v_b));
  if v_ids is distinct from array[v_b, v_a] then f := f || 'a request naming no service was reordered: ' || coalesce(v_ids::text, 'none') || '; '; end if;
  if exists (select 1 from public.fn_match_capability(array['swimming_pools'], 'executes', p_limit := 100000) x where cardinality(x.partner_hits) > 0) then
    f := f || 'a request naming no service reported a partner hit; ';
  end if;

  select count(*) into v_caps_after from public.supplier_capabilities where supplier_id not in (v_a, v_b);
  select count(*) into v_leads_after from public.leads;
  if v_caps_after <> v_caps_before or v_leads_after <> v_leads_before then f := f || 'real rows moved; '; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when f = '' then 'PROBE OK' else 'PROBE FAILED: ' || f end);
end $probe$;
