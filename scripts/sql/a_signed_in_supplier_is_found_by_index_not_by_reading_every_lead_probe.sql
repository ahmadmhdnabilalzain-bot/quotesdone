-- PROBE: A SIGNED-IN SUPPLIER IS FOUND BY INDEX, NOT BY READING EVERY LEAD (10 Nov 2026; seat: it_engineer).
--
-- A pure probe: it reads only (EXPLAIN without ANALYZE, a catalogue lookup) and always ends in raise exception, so
-- nothing it touches survives. Run it after a_signed_in_supplier_is_found_by_index_not_by_reading_every_lead.sql is
-- applied, or after it in the same rolled-back transaction:
--   node scripts/ci/rehearse_sql.mjs scripts/sql/a_signed_in_supplier_is_found_by_index_not_by_reading_every_lead.sql \
--     scripts/sql/a_signed_in_supplier_is_found_by_index_not_by_reading_every_lead_probe.sql
-- It proves the index exists, is valid, is the partial trigram index on claimed_by, and that the planner chooses it
-- for the exact statement PostgREST sends for .ilike('claimed_by', <address>).limit(1). The address is a fixture
-- (example.invalid) and is never written anywhere.
do $probe$
declare
  v_bad text[] := '{}'; v_def text; v_plan text := ''; r record;
begin
  select pg_get_indexdef(i.indexrelid) into v_def
    from pg_index i where i.indexrelid = to_regclass('public.leads_claimed_by_trgm_idx') and i.indisvalid;
  if v_def is null then v_bad := v_bad || 'index missing or invalid'::text;
  elsif v_def !~* 'using gin \(claimed_by (public\.)?gin_trgm_ops\) where \(claimed_by is not null\)' then
    v_bad := v_bad || ('index is not the partial trigram index: ' || v_def);
  end if;

  for r in execute $q$explain select leads.id from public.leads where leads.claimed_by ilike 'zz-demo-probe@example.invalid' limit 1 offset 0$q$ loop
    v_plan := v_plan || r."QUERY PLAN" || ' | ';
  end loop;
  if v_plan !~ 'leads_claimed_by_trgm_idx' then v_bad := v_bad || ('planner did not choose the index: ' || left(v_plan, 300)); end if;
  if v_plan ~ 'Seq Scan on leads' then v_bad := v_bad || 'planner still reads leads sequentially'::text; end if;

  if cardinality(v_bad) = 0 then
    raise exception 'PROBE OK: leads_claimed_by_trgm_idx is valid and chosen (%)', left(v_plan, 200);
  end if;
  raise exception 'PROBE FAILED: %', array_to_string(v_bad, '; ');
end $probe$;
