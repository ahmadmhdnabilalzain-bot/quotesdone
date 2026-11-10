-- Seat: sales_engineer
-- a_quote_carries_the_sales_engineers_review_notes_probe.sql — the pure probe for
-- a_quote_carries_the_sales_engineers_review_notes.sql (10 Nov 2026, founder ledger 1588). No DDL here, so it RAISES
-- its verdict (CHK<<...>>) and everything it touched rolls back. It writes NO row: the shape rule is asked directly,
-- and the CHECK is proved to exist and to call it. It reads no real quote and can reach no person.
--   NODE_USE_ENV_PROXY=1 SUPABASE_ACCESS_TOKEN=proxy-injected node scripts/ci/rehearse_sql.mjs \
--     scripts/sql/a_quote_carries_the_sales_engineers_review_notes.sql scripts/sql/a_quote_carries_the_sales_engineers_review_notes_probe.sql
do $probe$
declare
  v_bad text[] := '{}';
  v_ok jsonb := '[{"code":"scope_missing","severity":"high","line_no":4,"en":"You asked for \"Waterproofing membrane\", and this quote does not price it.","ar":"طلبت \"Waterproofing membrane\"، ولا يتضمن هذا العرض سعرًا له."},
                 {"code":"brand_alternative","severity":"info","line_no":2,"en":"Matches the requested brand: no. Alternative offered: premium German brand.","ar":"مطابق للعلامة التجارية المطلوبة: لا. البديل المعروض: علامة ألمانية فاخرة."}]';
  v_def text;
begin
  if not public.fn_quote_review_notes_are_valid(v_ok) then v_bad := v_bad || 'two well-formed notes refused'::text; end if;
  if not public.fn_quote_review_notes_are_valid(null) then v_bad := v_bad || 'null refused (a quote with no review yet)'::text; end if;
  if not public.fn_quote_review_notes_are_valid('[]'::jsonb) then v_bad := v_bad || 'an empty review refused'::text; end if;
  if public.fn_quote_review_notes_are_valid('{"code":"scope_missing"}'::jsonb) then v_bad := v_bad || 'an object instead of an array accepted'::text; end if;
  if public.fn_quote_review_notes_are_valid('[{"code":"cheapest","severity":"high","en":"This is the cheapest quote you have.","ar":"هذا أرخص عرض لديك."}]'::jsonb) then v_bad := v_bad || 'an unknown code accepted'::text; end if;
  if public.fn_quote_review_notes_are_valid('[{"code":"grade_lower","severity":"urgent","en":"Lower grade than you asked for.","ar":"درجة أدنى مما طلبت."}]'::jsonb) then v_bad := v_bad || 'an unknown severity accepted'::text; end if;
  if public.fn_quote_review_notes_are_valid('[{"code":"grade_lower","severity":"high","en":"Lower grade than you asked for.","ar":"Lower grade"}]'::jsonb) then v_bad := v_bad || 'English in the Arabic field accepted'::text; end if;
  if public.fn_quote_review_notes_are_valid('[{"code":"grade_lower","severity":"high","en":"","ar":"درجة أدنى مما طلبت."}]'::jsonb) then v_bad := v_bad || 'a note with no English accepted'::text; end if;

  select pg_get_constraintdef(c.oid) into v_def from pg_constraint c where c.conname = 'quotes_review_notes_shape' and c.conrelid = 'public.quotes'::regclass;
  if v_def is null or v_def not like '%fn_quote_review_notes_are_valid(review_notes)%' then v_bad := v_bad || ('the CHECK does not call the shape rule: ' || coalesce(v_def, 'missing')); end if;

  if has_function_privilege('anon', 'public.fn_quote_review_notes_are_valid(jsonb)', 'execute') then v_bad := v_bad || 'anon can execute'::text; end if;
  if has_function_privilege('authenticated', 'public.fn_quote_review_notes_are_valid(jsonb)', 'execute') then v_bad := v_bad || 'authenticated can execute'::text; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'fn_quote_review_notes_are_valid'
                  and array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%') then v_bad := v_bad || 'search_path is not pinned'::text; end if;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when cardinality(v_bad) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_bad, '; ') end,
    'constraint', v_def);
end $probe$;
