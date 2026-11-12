-- PROBE (pure, no DDL, aborted transaction) for a_partner_service_is_matched_knowingly.sql.
-- Seat: sales_engineer. 12 Nov 2026, founder rulings 1647 / 1628 and 24 Sep 2026 (any number of suppliers may quote).
-- Run AFTER the file, or with it, rolled back:
--   node scripts/ci/rehearse_sql.mjs scripts/sql/a_partner_service_is_matched_knowingly.sql scripts/sql/a_partner_service_is_matched_knowingly_probe.sql
-- It always ends in raise exception 'CHK<<json>>', so every row it writes rolls back; session_replication_role = replica
-- stops every trigger for this transaction only.
--
-- ITS SUBJECTS CANNOT REACH A PERSON: the matchable demo suppliers at @example.invalid that scripts/lib/demo_factory.mjs
-- built ('ZZ DEMO ...' or 'QD Demo ...'), up to 4, at least 2 (production held 3, then 2, on 12 Nov 2026; the
-- 3 own-team + 1 partner-only case is also asserted offline in supabase/functions/_shared/partner_match.test.ts); their capability rows
-- are rewritten here and roll back. No inquiry is created, nothing is matched into inquiry_matches. Every other capability
-- and every lead are counted before and after and must not move.
--
-- The first n-1 build pools with their own team. The last offers pool construction THROUGH A PARTNER and is given the
-- request's product, so his score is the HIGHEST (40 points of product match):
--   1. all n are matched (nobody is held back), and the partner-only one is LAST; his partner_hits is the key and his
--      why says so; the own-team ones carry no partner hit
--   2. with p_limit n-1 the partner-only one is the one left out (he ranks last, he is not refused)
--   3. a key in services_partner that is not in services is not confirmed: he is matched for nothing
--   4. mixed (maintenance himself, construction through the partner) is NOT partner-only: ordered by score, first
--   5. a request naming no service is untouched: no partner_hits, ordered by score as before (he is first)
do $probe$
declare
  f text := ''; v_sup bigint[]; v_own bigint[]; v_p bigint; n int; v_ids bigint[]; v_row record;
  v_caps_before int; v_caps_after int; v_leads_before int; v_leads_after int;
  k text := 'swimming_pools.pool_construction'; m text := 'swimming_pools.pool_maintenance';
begin
  set local session_replication_role = replica;
  select count(*) into v_leads_before from public.leads;
  select array_agg(l.id order by l.id) into v_sup from (
    select l.id from public.leads l
     where l.company_name ~* '^\s*(zz|qd)\s*demo' and l.email like '%@example.invalid'
       and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
     order by l.id limit 4) l;
  n := coalesce(cardinality(v_sup), 0);
  if n < 2 then raise exception 'CHK<<{"verdict":"PROBE FAILED: fewer than two matchable demo suppliers at @example.invalid"}>>'; end if;
  v_own := v_sup[1:n - 1]; v_p := v_sup[n];
  select count(*) into v_caps_before from public.supplier_capabilities where not (supplier_id = any(v_sup));
  delete from public.supplier_availability where supplier_id = any(v_sup);
  insert into public.supplier_capabilities (supplier_id, trades, roles, services, confirmed_at, confirmed_version)
  select s, '{}', array['contractor'], '{}', now(), 1 from unnest(v_sup) s
  on conflict (supplier_id) do update set trades = '{}', roles = array['contractor'], services = '{}', services_removed = '{}',
    excluded_trades = '{}', coverage_emirates = '{}', min_project_value = null, max_project_value = null, confirmed_at = now();
  update public.supplier_capabilities sc set trades = array['swimming_pools'], products_norm = '{}', services_partner = '{}',
         services = array[k], authority_approvals = coalesce((select jsonb_object_agg(a, true) from public.taxonomy_trade t,
           unnest(t.authority_required) a where t.code = 'swimming_pools'), '{}'::jsonb)
   where sc.supplier_id = any(v_sup);
  update public.supplier_capabilities set services_partner = array[k], products_norm = array['pool pump'] where supplier_id = v_p;

  -- 1. all matched, the partner-only one last although he scores highest
  v_ids := array(select x.supplier_id from public.fn_match_capability(array['swimming_pools'], 'executes', array['pool pump'],
                   p_limit := 100000, p_services := array[k]) x where x.supplier_id = any(v_sup));
  if cardinality(v_ids) <> n then f := f || 'not all ' || n || ' suppliers were matched: ' || coalesce(v_ids::text, 'none') || '; ';
  elsif v_ids[n] <> v_p then f := f || 'the partner-only supplier is not last: ' || v_ids::text || '; '; end if;
  select x.* into v_row from public.fn_match_capability(array['swimming_pools'], 'executes', array['pool pump'],
           p_limit := 100000, p_services := array[k]) x where x.supplier_id = v_p;
  if v_row.partner_hits is distinct from array[k] or position('through a partner: ' || k in coalesce(v_row.why, '')) = 0 then
    f := f || 'the partner hit or why is wrong: ' || coalesce(v_row.partner_hits::text, 'null') || ' / ' || coalesce(v_row.why, 'null') || '; ';
  end if;
  if v_row.score <= (select max(x.score) from public.fn_match_capability(array['swimming_pools'], 'executes', array['pool pump'],
           p_limit := 100000, p_services := array[k]) x where x.supplier_id = any(v_own)) then
    f := f || 'the probe did not make the partner-only supplier outscore the own team, so the order proves nothing; ';
  end if;
  if exists (select 1 from public.fn_match_capability(array['swimming_pools'], 'executes', p_limit := 100000, p_services := array[k]) x
              where x.supplier_id = any(v_own) and cardinality(x.partner_hits) > 0) then f := f || 'an own-team supplier carries a partner hit; '; end if;

  -- 2. a limit one short leaves out the partner-only one (ranked last, not refused)
  if v_p = any(array(select x.supplier_id from public.fn_match_capability(array['swimming_pools'], 'executes', array['pool pump'],
           p_limit := n - 1, p_services := array[k]) x)) and (select count(*) from public.fn_match_capability(array['swimming_pools'], 'executes', array['pool pump'],
           p_limit := 100000, p_services := array[k]) x) = n then
    f := f || 'with the limit one short the partner-only supplier displaced the own team; ';
  end if;

  -- 3. an unconfirmed partner key matches nothing
  update public.supplier_capabilities set services = '{}' where supplier_id = v_p;
  if exists (select 1 from public.fn_match_capability(array['swimming_pools'], 'executes', p_limit := 100000, p_services := array[k]) x
              where x.supplier_id = v_p) then f := f || 'a partner key that is not a confirmed service matched; '; end if;

  -- 4. mixed: maintenance himself, construction through the partner: not partner-only, ordered by score (first)
  update public.supplier_capabilities set services = array[k, m] where supplier_id = any(v_sup);
  v_ids := array(select x.supplier_id from public.fn_match_capability(array['swimming_pools'], 'executes', array['pool pump'],
                   p_limit := 100000, p_services := array[k, m]) x where x.supplier_id = any(v_sup));
  if v_ids[1] is distinct from v_p then f := f || 'a supplier doing part himself was ordered as partner-only: ' || coalesce(v_ids::text, 'none') || '; '; end if;
  if (select x.partner_hits from public.fn_match_capability(array['swimming_pools'], 'executes', p_limit := 100000,
        p_services := array[k, m]) x where x.supplier_id = v_p) is distinct from array[k] then f := f || 'the mixed supplier''s partner hits are wrong; '; end if;

  -- 5. no service named: untouched (he is first on score, no partner hits)
  update public.supplier_capabilities set services = array[k] where supplier_id = any(v_sup);
  v_ids := array(select x.supplier_id from public.fn_match_capability(array['swimming_pools'], 'executes', array['pool pump'], p_limit := 100000) x
                  where x.supplier_id = any(v_sup));
  if v_ids[1] is distinct from v_p or cardinality(v_ids) <> n then f := f || 'a request naming no service was reordered: ' || coalesce(v_ids::text, 'none') || '; '; end if;
  if exists (select 1 from public.fn_match_capability(array['swimming_pools'], 'executes', p_limit := 100000) x where cardinality(x.partner_hits) > 0) then
    f := f || 'a request naming no service reported a partner hit; ';
  end if;

  select count(*) into v_caps_after from public.supplier_capabilities where not (supplier_id = any(v_sup));
  select count(*) into v_leads_after from public.leads;
  if v_caps_after <> v_caps_before or v_leads_after <> v_leads_before then f := f || 'real rows moved; '; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when f = '' then 'PROBE OK' else 'PROBE FAILED: ' || f end,
    'suppliers', n, 'own_team', n - 1, 'partner_only_rank', n);
end $probe$;
