-- THE CEO'S MONTHLY REPORT IS A BOARD PACK: SUPPLY BY TRADE AND EMIRATE, EVERY SEAT'S DUTIES, THE RUNWAY AND THE
-- LAUNCH GATE, BESIDE THE PLAN AGAINST ACTUAL IT ALREADY CARRIES.
--
-- Assigned: ceo. 24 Sep 2026. Seat audit GAPS.md, CEO gap 4 (ledger 983; founder instructions 10 — the report
-- "extremely organized more than anybody else" — and 327, the accountant's runway). Approved job description,
-- monthly: "a board-quality company report ... the plan against actuals per seat, supply growth by trade and emirate,
-- cost against budget and the runway reported by the accountant."
--
-- ══ MEASURED, 24 Sep 2026 ═════════════════════════════════════════════════════════════════════════════
--   fn_ceo_month_plan (the_ceo_runs_the_company_on_the_founders_year_one_targets.sql, #923) sends the founder one
--   monthly review: each metric of the path against its target with its owning seat, each seat's directive met or
--   missed, costs against the month's ceiling, improvements opened and closed, next month's targets. It does not
--   carry: supply growth by trade and by emirate, whether each seat's own duties ran, the runway the accountant
--   computes at month close (accountant_month_close.figures -> cash_position -> runway; Aug 2026: 0.3 months on
--   AED 582.96 available against AED 1,788.99 a month), or where the customer-launch gate stands.
--
-- ══ WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════
--   1. fn_ceo_board_pack(month): code only, one jsonb plus the text section, from the owners' own records:
--        supply      verified suppliers added in the month and in total, by emirate (leads.emirate) and by trade
--                    (supplier_capabilities.trades of confirmed suppliers), ZZ DEMO / example.invalid excluded;
--        seats       per seat: duties registered, duties green (ran inside twice their interval), duties failing;
--        runway      the accountant's month-close cash position, quoted as the accountant computed it, or
--                    "not closed yet" — the CEO never recomputes the accountant's number;
--        launch      the latest ceo_launch_gate row (the_ceo_decides_whether_january_holds_on_supply_coverage.sql).
--   2. fn_ceo_month_plan: identical to #923's except the lines marked BOARD PACK — it computes the pack once,
--      stores it under facts.board, and appends its text to the report (the body limit moves from 4,000 to 7,000
--      characters so the pack is not cut).
--
-- NOT CHANGED: what the month closes, which directives it issues, the dedupe, the delivery path (customer_support).
--
-- Pending: scripts/sql/pending/the_ceo_monthly_report_is_a_board_pack.txt. Applies AFTER
-- the_ceo_decides_whether_january_holds_on_supply_coverage.sql (ceo_launch_gate).

create or replace function public.fn_ceo_board_pack(p_month date)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_m date := date_trunc('month', p_month)::date;
  v_from timestamptz := date_trunc('month', p_month)::timestamp at time zone 'Asia/Dubai';
  v_to timestamptz := (date_trunc('month', p_month) + interval '1 month')::timestamp at time zone 'Asia/Dubai';
  v_supply jsonb; v_seats jsonb; v_cash jsonb; v_launch public.ceo_launch_gate; v_text text;
begin
  with real as (
    select l.id, l.emirate, l.approved_at from public.leads l
     where l.approved_at is not null and l.approved_at < v_to
       and not (coalesce(l.is_demo, false) or coalesce(l.company_name, '') ilike 'ZZ DEMO%' or coalesce(l.email, '') ilike '%@example.invalid'))
  select jsonb_build_object(
    'verified_total', (select count(*) from real),
    'verified_added', (select count(*) from real where approved_at >= v_from),
    'by_emirate', (select coalesce(jsonb_agg(jsonb_build_object('emirate', e, 'total', t, 'added', a) order by t desc, e), '[]'::jsonb)
                     from (select coalesce(nullif(btrim(emirate), ''), 'not stated') e, count(*) t, count(*) filter (where approved_at >= v_from) a
                             from real group by 1) x),
    'by_trade', (select coalesce(jsonb_agg(jsonb_build_object('trade', tr, 'total', t, 'added', a) order by t desc, tr), '[]'::jsonb)
                   from (select tr, count(*) t, count(*) filter (where r.approved_at >= v_from) a
                           from real r join public.supplier_capabilities sc on sc.supplier_id = r.id and sc.confirmed_at is not null,
                                unnest(sc.trades) tr group by tr order by count(*) desc, tr limit 15) x))
    into v_supply;

  select coalesce(jsonb_object_agg(owner_seat, jsonb_build_object('duties', n, 'green', g, 'failing', f)), '{}'::jsonb) into v_seats
    from (select d.owner_seat, count(*) n,
                 count(*) filter (where d.last_ok_at >= now() - 2 * d.every - interval '15 minutes') g,
                 count(*) filter (where d.failures > 0) f
            from public.seat_duty d where d.enabled group by d.owner_seat) x;

  select figures -> 'cash_position' into v_cash from public.accountant_month_close where month = v_m;
  select * into v_launch from public.ceo_launch_gate order by week desc limit 1;

  v_text := format(E'BOARD PACK, %s\n\nSupply: %s verified suppliers, %s added this month.', to_char(v_m, 'FMMonth YYYY'),
                   v_supply->>'verified_total', v_supply->>'verified_added')
    || E'\nBy emirate: ' || coalesce((select string_agg(format('%s %s (+%s)', e->>'emirate', e->>'total', e->>'added'), ', ')
                                        from jsonb_array_elements(v_supply->'by_emirate') e), 'none')
    || E'\nBy trade: ' || coalesce((select string_agg(format('%s %s (+%s)', e->>'trade', e->>'total', e->>'added'), ', ')
                                      from jsonb_array_elements(v_supply->'by_trade') e), 'none')
    || E'\n\nSeats (duties green of registered, failing): '
    || coalesce((select string_agg(format('%s %s/%s, %s failing', k, v->>'green', v->>'duties', v->>'failing'), '; ' order by k)
                   from jsonb_each(v_seats) s(k, v)), 'no duties registered')
    || E'\n\nRunway (the accountant''s month close): '
    || case when v_cash is null then 'the accountant has not closed ' || to_char(v_m, 'FMMonth YYYY') || ' yet.'
            when v_cash->'runway'->>'missing' is not null then (v_cash->'runway'->>'missing') || '.'
            else format('%s months: AED %s available against AED %s spent a month.', v_cash->'runway'->>'months',
                        v_cash->'runway'->>'available_aed', v_cash->'runway'->>'monthly_spend_aed') end
    || E'\n\nCustomer launch gate: '
    || case when v_launch.week is null then 'not measured yet.'
            else format('%s of %s trades ready (%s%%), verdict %s%s, week of %s.', v_launch.trades_ready, v_launch.trades_total,
                        v_launch.coverage_pct, v_launch.verdict, coalesce(', decision ' || v_launch.decision, ''), v_launch.week) end;

  return jsonb_build_object('month', v_m, 'supply', v_supply, 'seats', v_seats, 'cash_position', v_cash,
    'launch_gate', case when v_launch.week is null then null else to_jsonb(v_launch) end, 'text', v_text);
end $fn$;
revoke execute on function public.fn_ceo_board_pack(date) from public, anon, authenticated;
grant execute on function public.fn_ceo_board_pack(date) to service_role;

-- ── the month, as #923 wrote it, with the pack in it (lines marked BOARD PACK) ─────────────────────────
create or replace function public.fn_ceo_month_plan(p_at timestamptz default now())
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_m0 date := date_trunc('month', p_at at time zone 'Asia/Dubai')::date; v_pm date := (v_m0 - interval '1 month')::date;
  c_id bigint; d public.ceo_seat_directive; r jsonb; x jsonb; v_status text; v_targets jsonb; v_need numeric; v_act numeric;
  v_miss jsonb; v_hid bigint; n_closed int := 0; n_issued int := 0; v_body text; v_facts jsonb; s text; v_cost numeric; v_ceiling numeric;
  v_board jsonb;   -- BOARD PACK
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';
  if c_id is null then return jsonb_build_object('month', v_m0, 'contract', null); end if;

  -- 1. close last month's directives, met or missed; a missed target becomes an improvement for the seat
  if exists (select 1 from public.target_path where contract_id = c_id and month = v_pm) then
    r := public.fn_ceo_path_month_result(c_id, v_pm);
    for d in select * from public.ceo_seat_directive where month = v_pm and status = 'issued' loop
      select coalesce(jsonb_agg(e), '[]'::jsonb) into x from jsonb_array_elements(r) e where e->>'owner_seat' = d.seat;
      v_status := case when exists (select 1 from jsonb_array_elements(x) e where e->>'result' = 'missed') then 'missed'
                       when exists (select 1 from jsonb_array_elements(x) e where e->>'result' = 'met') then 'met'
                       else 'not_measurable' end;
      update public.ceo_seat_directive set status = v_status, outcome = x, closed_at = now() where month = d.month and seat = d.seat;
      if d.handoff_id is not null and exists (select 1 from public.agent_actions where id = d.handoff_id and status = 'pending') then
        perform set_config('qd.handoff_closer', 'ceo', true);
        perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('verified_by', 'ceo', 'month', v_pm, 'result', v_status, 'outcome', x));
        perform set_config('qd.handoff_closer', '', true);
      end if;
      for v_miss in select e from jsonb_array_elements(x) e where e->>'result' = 'missed' loop
        perform public.fn_ceo_improvement_open('month_miss', v_pm || ':' || d.seat || ':' || (v_miss->>'metric'), d.seat,
          format('%s closed %s at %s against a target of %s. Name the root cause and what changes this month.', v_miss->>'metric', to_char(v_pm, 'Mon YYYY'), v_miss->>'actual', v_miss->>'target'),
          v_miss || jsonb_build_object('month', v_pm));
      end loop;
      n_closed := n_closed + 1;
    end loop;

    -- 2. the founder's monthly report, once per month
    if not exists (select 1 from public.ceo_month_report where month = v_pm) then
      v_board := public.fn_ceo_board_pack(v_pm);   -- BOARD PACK
      select cost_ceiling_aed into v_ceiling from public.ceo_year_plan where month = v_pm;
      v_cost := (select (e->>'actual')::numeric from jsonb_array_elements(r) e where e->>'metric' = 'costs_aed');
      v_facts := jsonb_build_object('month', v_pm, 'metrics', r,
        'directives', (select coalesce(jsonb_object_agg(seat, status), '{}'::jsonb) from public.ceo_seat_directive where month = v_pm),
        'improvements_opened', (select count(*) from public.ceo_improvement where created_at >= v_pm and created_at < v_m0),
        'improvements_closed', (select count(*) from public.ceo_improvement where closed_at >= v_pm and closed_at < v_m0),
        'cost_ceiling_aed', v_ceiling, 'costs_aed', v_cost, 'next_month', (select to_jsonb(y) from public.ceo_year_plan y where y.month = v_m0))
        || jsonb_build_object('board', v_board - 'text');   -- BOARD PACK
      v_body := format(E'Monthly review, %s.\n\nTargets against the plan:\n', to_char(v_pm, 'FMMonth YYYY'))
        || (select string_agg(format('- %s (%s): %s of %s, %s', e->>'metric', e->>'owner_seat', coalesce(e->>'actual', 'not measurable'),
                                     e->>'target', e->>'result'), E'\n' order by e->>'owner_seat') from jsonb_array_elements(r) e)
        || E'\n\nSeats: ' || coalesce((select string_agg(seat || ' ' || status, ', ' order by seat) from public.ceo_seat_directive where month = v_pm), 'no directives were issued')
        || format(E'\nCosts: AED %s against a ceiling of AED %s.', coalesce(round(v_cost)::text, 'not measurable'), v_ceiling)
        || format(E'\nImprovements: %s opened, %s closed.', v_facts->>'improvements_opened', v_facts->>'improvements_closed')
        || coalesce(format(E'\n\nNext month: %s verified suppliers by month end, %s requests, AED %s of reveal fees.',
                           v_facts->'next_month'->>'verified', v_facts->'next_month'->>'requests', v_facts->'next_month'->>'fee_aed'), '')
        || E'\n\n' || coalesce(v_board->>'text', '');   -- BOARD PACK
      v_hid := public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'ceo_month_report', v_pm::text,
        jsonb_build_object('recipient_role', 'founder', 'event', 'CEO monthly review: ' || to_char(v_pm, 'FMMonth YYYY'), 'detail', left(v_body, 7000),
                           'level', 'info', 'kind', 'founder_brief', 'dedupe_key', 'ceo_month:' || v_pm));
      insert into public.ceo_month_report (month, facts, body, handoff_id) values (v_pm, v_facts, v_body, v_hid);
    end if;
  end if;

  -- 3. this month's directive per seat, from the plan table; a cumulative target carries last month's shortfall
  if exists (select 1 from public.target_path where contract_id = c_id and month = v_m0) then
    foreach s in array array['sales_engineer', 'customer_support', 'marketing', 'accountant', 'it_engineer'] loop
      continue when exists (select 1 from public.ceo_seat_directive where month = v_m0 and seat = s);
      continue when not exists (select 1 from public.org_role where role_id = s and status = 'active');
      v_targets := '[]'::jsonb;
      for x in select to_jsonb(p) from public.target_path p where p.contract_id = c_id and p.month = v_m0 and p.owner_seat = s order by p.metric_key loop
        v_need := null;
        if x->>'kind' = 'cumulative' then
          v_act := public.fn_ambition_measure(x->>'metric_key', v_m0::timestamp at time zone 'Asia/Dubai', p_at);
          v_need := greatest(0, (x->>'value')::numeric - coalesce(v_act, 0));
        end if;
        v_targets := v_targets || jsonb_build_object('metric', x->>'metric_key', 'kind', x->>'kind', 'direction', x->>'direction',
                                                     'target', (x->>'value')::numeric, 'still_needed', v_need);
      end loop;
      insert into public.ceo_seat_directive (month, seat, targets, actions)
      values (v_m0, s, v_targets, coalesce((select array_agg(a.action order by a.id) from public.ceo_plan_action a
                                             where a.seat = s and v_m0 between a.from_month and a.to_month), '{}'::text[]));
      v_hid := public.fn_seat_handoff('ceo', s, 'ceo.month_directive', 'ceo_seat_directive', v_m0 || ':' || s,
        jsonb_build_object('month', v_m0, 'targets', v_targets,
                           'actions', (select to_jsonb(actions) from public.ceo_seat_directive where month = v_m0 and seat = s),
                           'due_at', ((v_m0 + interval '1 month')::timestamp at time zone 'Asia/Dubai')));
      update public.ceo_seat_directive set handoff_id = v_hid where month = v_m0 and seat = s;
      n_issued := n_issued + 1;
    end loop;
  end if;
  return jsonb_build_object('month', v_m0, 'closed', n_closed, 'issued', n_issued,
    'reported', (select handoff_id from public.ceo_month_report where month = v_pm));
end $fn$;
revoke execute on function public.fn_ceo_month_plan(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_month_plan(timestamptz) to service_role;
