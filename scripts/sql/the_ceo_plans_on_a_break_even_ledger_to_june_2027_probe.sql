-- PROBE for the_ceo_plans_on_a_break_even_ledger_to_june_2027.sql. Seat: ceo. Never applied: it always raises CHK<<...>>
-- and rolls back. It writes plan rows only and asserts that nothing else moved: no notification, no app_secrets value
-- (the invitation cap, every switch), no org_task.
do $probe$
declare l jsonb; r jsonb; r2 jsonb; v_bad text := ''; v_secrets_before text; v_notes_before int; v_tasks_before int; v_arch int;
begin
  select md5(string_agg(key || '=' || coalesce(value, ''), ',' order by key)) into v_secrets_before from public.app_secrets;
  select count(*) into v_notes_before from public.notifications;
  select count(*) into v_tasks_before from public.org_tasks;

  -- the archive holds the 24 Sep plan; the operating plan is the ledger's
  select count(*) into v_arch from public.ceo_year_plan_archive where basis ilike '%ledger 971%';
  if v_arch <> 12 then v_bad := v_bad || ' archive=' || v_arch; end if;
  if exists (select 1 from public.ceo_year_plan where basis not ilike 'break-even ledger%') then v_bad := v_bad || ' plan-not-rebased'; end if;

  -- the ledger: founder 19,000 + measured cost x months + licence; revenue from real reveals only (the one paid reveal is ZZ DEMO)
  l := public.fn_break_even_ledger(timestamptz '2026-11-28 10:00+04');
  if (l->>'revenue_net_aed')::numeric <> 0 then v_bad := v_bad || ' demo-revenue-counted'; end if;
  if abs((l->>'cost_to_cover_aed')::numeric - (19000 + (l->>'monthly_cost_aed')::numeric * (l->>'months_left')::numeric + 1200)) > 0.05 then v_bad := v_bad || ' cost-formula'; end if;
  if (l->>'revenue_months_left')::int <> 6 then v_bad := v_bad || ' revenue-months=' || (l->>'revenue_months_left'); end if;
  if (l#>>'{targets,invitations_target}')::int > (l#>>'{targets,invitations_capacity_to_target_date}')::int then v_bad := v_bad || ' invitations-above-guardrail'; end if;
  if (l#>>'{targets,verified_suppliers_per_open_trade}')::int < 5 then v_bad := v_bad || ' threshold-under-floor'; end if;

  -- the weekly run near the month's end: targets per seat, measured, behind -> a re-plan with its lever
  r := public.fn_ceo_break_even_run(timestamptz '2026-11-28 10:00+04');
  if not coalesce((r->>'weekly')::boolean, false) then v_bad := v_bad || ' weekly-did-not-run'; end if;
  if (select count(*) from public.ceo_seat_month_target where month = date '2026-11-01') < 5 then v_bad := v_bad || ' targets-missing'; end if;
  if exists (select 1 from public.ceo_seat_month_target where month = date '2026-11-01' and checked_at is null) then v_bad := v_bad || ' target-unmeasured'; end if;
  if (select status from public.ceo_seat_month_target where month = date '2026-11-01' and seat = 'sales_engineer' and metric = 'suppliers_verified') <> 'behind' then v_bad := v_bad || ' verified-not-behind'; end if;
  if not exists (select 1 from public.ceo_break_even_replan where month = date '2026-11-01' and lever like 'channels beyond e-mail%') then v_bad := v_bad || ' no-replan-or-wrong-lever'; end if;
  -- a second run the same week re-computes the ledger and does not re-check
  r2 := public.fn_ceo_break_even_run(timestamptz '2026-11-29 10:00+04');
  if coalesce((r2->>'weekly')::boolean, true) then v_bad := v_bad || ' rechecked-within-a-week'; end if;

  -- nothing outside the plan moved
  if (select md5(string_agg(key || '=' || coalesce(value, ''), ',' order by key)) from public.app_secrets) <> v_secrets_before then v_bad := v_bad || ' app_secrets-changed'; end if;
  if (select count(*) from public.notifications) <> v_notes_before then v_bad := v_bad || ' notification-written'; end if;
  if (select count(*) from public.org_tasks) <> v_tasks_before then v_bad := v_bad || ' task-created'; end if;

  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
  raise exception 'CHK<<PROBE OK ledger %; weekly %>>', l, r->'behind';
end $probe$;
