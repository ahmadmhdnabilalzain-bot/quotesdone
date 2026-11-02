-- PROBE: the portal turn has its task class (#1640 review, 27 Oct 2026). Pure probe, no DDL, no write of its own: run AFTER
-- the_portal_turn_has_its_task_class.sql in the SAME query through node scripts/qsql.mjs, so the row is rolled back with it;
-- it always ends in raise exception CHK<<...>>. Run alone, it reads the live table (the "before": no row, unmapped).
-- PROBE OK only if fn_task_class maps fn 'sales_engineer' to customer_portal_assistant AND fn_ai_route, asked for that fn
-- with NO task_class (the floor case), routes to customer_portal_assistant rather than the general_drafting default.
do $probe$
declare
  v_row text; v_route jsonb; v_cls text;
begin
  select task_class into v_row from public.fn_task_class where fn = 'sales_engineer' and active;
  v_route := public.fn_ai_route(null, null, null, 'sales_engineer', false, null, null);
  v_cls := coalesce(v_route->>'task_class', '');
  if v_row is distinct from 'customer_portal_assistant' or v_cls <> 'customer_portal_assistant' then
    raise exception 'CHK<<PROBE FAILED: fn_task_class row=% route task_class=% route=%>>', coalesce(v_row, 'none'), v_cls, left(v_route::text, 300);
  end if;
  raise exception 'CHK<<PROBE OK: sales_engineer -> customer_portal_assistant (row and route) | %>>', left(v_route::text, 300);
end $probe$;
