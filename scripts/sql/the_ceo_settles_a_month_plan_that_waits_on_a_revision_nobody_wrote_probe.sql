-- PROBE for the_ceo_settles_a_month_plan_that_waits_on_a_revision_nobody_wrote.sql. Seat: ceo. Never applied: it always
-- raises CHK<<...>> and rolls back. It settles the two real stuck plans inside the rolled-back transaction.
do $probe$
declare r jsonb; v_bad text := ''; v_notes int; nov text; dec text; v_dec_ideas int; v_customer int;
begin
  select count(*) into v_notes from public.notifications;
  r := public.fn_ceo_settles_stuck_month_plans(timestamptz '2026-11-11 10:00+04');
  select status into nov from public.marketing_month_plan where month = date '2026-11-01';
  select status, jsonb_array_length(plan->'ideas'), (select count(*) from jsonb_array_elements(plan->'ideas') e where e->>'audience' = 'customer')
    into dec, v_dec_ideas, v_customer from public.marketing_month_plan where month = date '2026-12-01';
  if nov <> 'rejected' then v_bad := v_bad || ' nov=' || nov; end if;
  if dec <> 'ceo_approved' then v_bad := v_bad || ' dec=' || dec; end if;
  if v_customer <> 0 then v_bad := v_bad || ' customer-ideas-left=' || v_customer; end if;
  if (select count(*) from public.ceo_decision_round where source_table = 'ceo_month_plan_settle') <> 2 then v_bad := v_bad || ' ledger-rows'; end if;
  if (select count(*) from public.notifications) <> v_notes then v_bad := v_bad || ' mailed'; end if;
  -- idempotent: a second run settles nothing more
  if jsonb_array_length(public.fn_ceo_settles_stuck_month_plans(timestamptz '2026-11-11 11:00+04')->'settled') <> 0 then v_bad := v_bad || ' settled-twice'; end if;
  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
  raise exception 'CHK<<PROBE OK November withdrawn, December approved with % ideas (0 customer-only), 2 ledger rows, no mail: %>>', v_dec_ideas, r;
end $probe$;
