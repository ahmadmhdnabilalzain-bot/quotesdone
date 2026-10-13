-- PROBE: THE DEMO PURGE REFUSES TO REACH A REAL ROW (founder ruling 1199; it_engineer).
--
-- A pure probe: it always raises CHK<<...>>, so every row it writes is rolled back. Nothing it creates can reach a
-- person: the supplier is a ZZ DEMO fixture on a reserved address, the inquiry has no customer and no contact.
--
-- 1. A demo supplier (ZZ DEMO, @example.invalid) and an inquiry that is NOT demo but hired it: the only path by
--    which the FK walk could reach a real row. fn_demo_purge(false) must refuse with DEMO PURGE REFUSED (QD198).
-- 2. Without that inquiry, the same plan must succeed and report the demo supplier among the leads it removes.
-- 3. The real inquiry is still there after the refused plan.
do $probe$
declare v_lead bigint; v_inq uuid; v_refused boolean := false; v_msg text; v_plan jsonb; v_ok boolean;
begin
  insert into public.leads (company_name, email, source)
  values ('ZZ DEMO — purge guard probe 1199', 'qd-probe1199-sup@example.invalid', 'demo_factory') returning id into v_lead;
  insert into public.inquiries (category, status, summary, hired_supplier_id)
  values ('aluminium', 'draft', 'probe 1199: a real-shaped inquiry that hired a demo supplier', v_lead) returning id into v_inq;

  begin
    perform public.fn_demo_purge(false);
  exception when sqlstate 'QD198' then v_refused := true; v_msg := sqlerrm;
  end;

  v_ok := exists (select 1 from public.inquiries where id = v_inq);
  delete from public.inquiries where id = v_inq;
  v_plan := public.fn_demo_purge(false);

  if v_refused and v_ok and (v_plan->>'mode') = 'plan' and coalesce((v_plan->'demo_ids'->>'leads')::int, 0) >= 1 then
    raise exception 'CHK<<PROBE OK: refused a purge reaching a real inquiry (%); the same plan without it removes % demo lead(s)>>',
      left(v_msg, 120), v_plan->'demo_ids'->>'leads';
  end if;
  raise exception 'CHK<<PROBE FAILED: refused=% real_inquiry_kept=% plan=%>>', v_refused, v_ok, left(coalesce(v_plan::text, ''), 300);
end $probe$;
