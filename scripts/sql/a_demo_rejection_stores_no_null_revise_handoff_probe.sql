-- PROBE: pure, run AFTER its .sql in the SAME query; ends in raise exception CHK<<...>> so nothing survives.
-- PROBE OK only if fn_ceo_decide carries array_remove on the revise handoff, and array_remove drops a null but keeps a real id.
do $p$ begin
  raise exception 'CHK<<%>>', case when pg_get_functiondef('public.fn_ceo_decide'::regproc) ~ 'array_remove\(array\[v_h\], null\)'
                                    and array_remove(array[null::bigint], null) = '{}'::bigint[]
                                    and array_remove(array[7::bigint], null) = '{7}'::bigint[] then 'PROBE OK' else 'PROBE FAILED' end;
end $p$;
