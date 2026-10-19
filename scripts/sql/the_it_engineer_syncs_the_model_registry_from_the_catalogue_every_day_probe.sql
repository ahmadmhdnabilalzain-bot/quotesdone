-- PROBE for the_it_engineer_syncs_the_model_registry_from_the_catalogue_every_day.sql (it_engineer, 18 Oct 2026).
-- NEVER APPLIED: it ends in raise exception, so the whole request rolls back - the ZZ DEMO registry rows, the ledger
-- rows and everything else. Send it through scripts/lib/safe_replay.mjs (replaySql), after the main file while that
-- file is pending. The verdict is in the exception text: 'PROBE OK :: ...' or 'PROBE FAILED :: ...'.
--
-- Asserts: the sync records a price move, a context move on a matrix model and an absent model; it changes NO
-- registry or model_rate value; a row closes as 'resolved' once the registry agrees with the catalogue (as a
-- reviewed correction would make it); a second identical run opens nothing new.
do $probe$
declare
  v_cat jsonb; v_only text[] := array['zz-demo/price-move','zz-demo/matrix','zz-demo/gone'];
  r1 jsonb; r2 jsonb; r3 jsonb; v_before text; v_after text; v_rate_before text; v_rate_after text;
  v_open int; v_resolved int;
begin
  insert into public.model_registry (model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd, context_len, approved, active, note)
  values ('zz-demo/price-move', 'zz-demo', 'small', 1.00, 2.00, 100000, false, true, 'ZZ DEMO probe row, rolled back'),
         ('zz-demo/matrix',     'zz-demo', 'small', 1.00, 2.00, 100000, false, true, 'ZZ DEMO probe row, rolled back'),
         ('zz-demo/gone',       'zz-demo', 'small', 1.00, 2.00, 100000, false, true, 'ZZ DEMO probe row, rolled back');

  select jsonb_agg(x) into v_cat from (
    select jsonb_build_object('id', 'zz-demo/price-move', 'context_length', 100000, 'pricing', jsonb_build_object('prompt', '0.000005', 'completion', '0.000002')) x
    union all select jsonb_build_object('id', 'zz-demo/matrix', 'context_length', 101000, 'pricing', jsonb_build_object('prompt', '0.000001', 'completion', '0.000002'))
    union all select jsonb_build_object('id', 'zz-demo/filler-' || g, 'context_length', 1, 'pricing', jsonb_build_object('prompt', '0', 'completion', '0'))
      from generate_series(1, 50) g) s;

  select string_agg(model_id || ':' || in_per_mtok_usd || '/' || out_per_mtok_usd || '/' || context_len, ',' order by model_id)
    into v_before from public.model_registry;
  select md5(coalesce(string_agg(t::text, ',' order by t::text), '')) into v_rate_before from public.model_rate t;

  r1 := public.fn_model_catalogue_sync(v_cat, v_only, array['zz-demo/matrix']);
  r2 := public.fn_model_catalogue_sync(v_cat, v_only, array['zz-demo/matrix']);

  select string_agg(model_id || ':' || in_per_mtok_usd || '/' || out_per_mtok_usd || '/' || context_len, ',' order by model_id)
    into v_after from public.model_registry;
  select md5(coalesce(string_agg(t::text, ',' order by t::text), '')) into v_rate_after from public.model_rate t;

  -- a reviewed correction brings the registry to the catalogue's price: the next run resolves that row
  update public.model_registry set in_per_mtok_usd = 5.00 where model_id = 'zz-demo/price-move';
  r3 := public.fn_model_catalogue_sync(v_cat, v_only, array['zz-demo/matrix']);
  select count(*) filter (where closed_at is null), count(*) filter (where outcome = 'resolved')
    into v_open, v_resolved from public.model_catalogue_change where model_id like 'zz-demo/%';

  if (r1->>'open')::int = 3 and (r1->>'new')::int = 3
     and (r2->>'open')::int = 3 and (r2->>'new')::int = 0
     and v_before = v_after and v_rate_before = v_rate_after
     and (r3->>'resolved')::int = 1 and v_open = 2 and v_resolved = 1
     and exists (select 1 from public.model_catalogue_change where model_id = 'zz-demo/matrix' and field = 'ctx' and matrix and closed_at is null)
     and exists (select 1 from public.model_catalogue_change where model_id = 'zz-demo/gone' and field = 'absent' and closed_at is null)
  then
    raise exception 'PROBE OK :: price move, matrix context move and absent model recorded; no registry or model_rate value changed; a corrected row resolved; a repeat run opened nothing';
  end if;
  raise exception 'PROBE FAILED :: %', jsonb_build_object('r1', r1 - 'items', 'r2', r2 - 'items', 'r3', r3 - 'items',
    'registry_unchanged', v_before = v_after, 'model_rate_unchanged', v_rate_before = v_rate_after,
    'open', v_open, 'resolved', v_resolved)::text;
end $probe$;
