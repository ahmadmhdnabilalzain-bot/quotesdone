-- THE ROLE BACKFILL RAN ONCE AND THE DERIVER KEPT WRITING ROWS WITHOUT ONE.
--
-- Earlier today: supplier_capabilities rows carried trades but no roles, and capability_agent's
-- `confirm` refuses any payload missing either - so a supplier could not confirm the scope the
-- company had derived for them. That was fixed by mapping leads.business_role to taxonomy_role and
-- backfilling the 5,220 rows that existed at that moment.
--
-- Backfilling the rows that existed AT THAT MOMENT is the defect. fn_supplier_capability_derive
-- itself was never taught to write roles, and the taxonomy then grew from 25 trades to 40, which
-- made thousands more suppliers derivable. The deriver ran to convergence and produced 10,085
-- further rows, every one of them with an empty roles array and therefore unconfirmable. MEASURED:
--
--   supplier_capabilities   15,305 rows
--   confirmable             5,220        <- exactly the rows the one-off backfill touched
--   confirmed                    0
--
-- A one-shot repair beside a generator that keeps producing the same defect fixes a number, not a
-- mechanism. The generator is fixed here, and the backfill is re-run for what it has already
-- written - which is safe to repeat because it only touches derived, unconfirmed rows that have no
-- roles, so a supplier's own confirmation can never be overwritten.
create or replace function public.fn_supplier_capability_derive(p_limit integer default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_written int := 0; v_skipped_no_trade int := 0; v_candidates int := 0;
begin
  with cand as (
    select l.id,
           public.fn_norm_trades(
             coalesce(l.company_name,'')||' '||coalesce(l.categories,'')||' '||
             coalesce(l.sector,'')||' '||coalesce(l.services,'')||' '||coalesce(l.products,'')) as trades,
           -- ROLES AT INSERT, not by a later sweep. See the header: the sweep is what had to be
           -- repeated, and a row written without a role is a row no supplier can confirm.
           public.fn_lead_role_codes(l.business_role) as roles,
           array_remove(array[nullif(btrim(coalesce(l.emirate,'')),'')]
                        || coalesce(l.service_emirates,'{}'::text[]), null) as emirates,
           (select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
              from unnest(string_to_array(regexp_replace(coalesce(l.products,''), '[;|/]', ',', 'g'), ',')) x
             where length(btrim(x)) between 2 and 80) as products_norm,
           (select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
              from unnest(string_to_array(regexp_replace(coalesce(l.services,''), '[;|/]', ',', 'g'), ',')) x
             where length(btrim(x)) between 2 and 80) as services_norm
      from public.leads l
     where not (coalesce(l.company_name,'') ilike 'ZZ DEMO%' or coalesce(l.email,'') ilike '%@example.invalid')
       and coalesce(l.banned, false) = false
       and not exists (select 1 from public.supplier_capabilities s where s.supplier_id = l.id)
     order by l.id
     limit p_limit
  ), ins as (
    insert into public.supplier_capabilities as sc (
      supplier_id, trades, roles, coverage_emirates, products_norm, services,
      extracted_at, updated_at, extractor_version, review_status, completeness,
      missing_fields, source_docs)
    select c.id, c.trades, c.roles, c.emirates, c.products_norm[1:40], c.services_norm[1:40],
           now(), now(), 'derived_from_directory_v2', 'derived',
           round(( (array_length(c.trades,1) > 0)::int
                 + (array_length(c.emirates,1) > 0)::int
                 + (array_length(c.products_norm,1) > 0)::int
                 + (array_length(c.services_norm,1) > 0)::int )::numeric / 4, 2),
           array_remove(array[
             case when array_length(c.products_norm,1) is null then 'products' end,
             case when array_length(c.emirates,1)      is null then 'coverage_emirates' end,
             'brands','certifications','team_size','min_project_value','max_project_value'
           ], null),
           jsonb_build_object(
             'derived_from','leads directory (company_name, categories, sector, services, products, emirate, business_role)',
             'method','fn_norm_trades over taxonomy_trade aliases + fn_lead_role_codes - deterministic, no model call',
             'confirmed_by_supplier', false,
             'at', now())
    from cand c
    where array_length(c.trades,1) > 0
    returning 1
  )
  select (select count(*) from ins), (select count(*) from cand),
         (select count(*) from cand where array_length(trades,1) is null)
    into v_written, v_candidates, v_skipped_no_trade;

  return jsonb_build_object(
    'candidates', v_candidates,
    'written', v_written,
    'skipped_no_trade', v_skipped_no_trade,
    'total_capability_rows', (select count(*) from public.supplier_capabilities),
    'confirmable', (select count(*) from public.supplier_capabilities
                     where array_length(trades,1) > 0 and array_length(roles,1) > 0),
    'confirmed_rows', (select count(*) from public.supplier_capabilities where confirmed_at is not null),
    'note', 'derived rows are UNCONFIRMED on purpose: fn_match_capability still refuses them until '
            'the supplier confirms their own scope. This gives that conversation something to be about.');
end
$function$;

-- Re-run for everything already written. Idempotent and narrow: derived rows only, unconfirmed
-- only, and only where roles is still empty.
update public.supplier_capabilities sc
   set roles = public.fn_lead_role_codes(l.business_role),
       updated_at = now()
  from public.leads l
 where l.id = sc.supplier_id
   and sc.review_status = 'derived'
   and sc.confirmed_at is null
   and coalesce(array_length(sc.roles,1),0) = 0;
