-- THE CEO SETTLES A MONTH PLAN THAT WAITS ON A REVISION NOBODY WROTE.
--
-- Assigned: ceo (the decision), with marketing (whose plan it is). 10 Nov 2026. Founder ledger 1609 ("no decision goes to
-- the founder"), 1059 (a rejection never ends the cycle; the CEO gives reasons), 1614 (trade by trade). Proposal P11 of
-- docs/reports/2026-11-10-seat-qualification-audit.md.
--
-- == MEASURED, 10 Nov 2026, production read-only ====================================================================
--   * marketing_month_plan 2026-11-01 and 2026-12-01 are both 'ceo_reviewing'. The CEO (model, held questions 21507 and
--     35241, both 'applied') REJECTED them: November twice (12 Oct, "the 12 ideas submitted are word for word the round-1
--     plan"), December once (31 Oct, "it breaks the binding constraint ... October to December 2026 is supply only").
--     The revision is marketing's model call (fn_seat_revises_for_the_ceo); it never came, so the plans wait on nobody.
--   * Each idea carries a structured audience: December's 12 are customer 6, both 3, supplier 3.
--
-- == WHAT THIS ADDS ================================================================================================
--   fn_ceo_settles_stuck_month_plans(at), daily (ceo.month_plan_settle): a plan the CEO rejected more than 3 days ago with
--   no revision since is settled BY THE CEO, in code, with reasons on the decision ledger (fn_ceo_decide):
--     * a month already more than 7 days under way is WITHDRAWN (status 'rejected'): its ideas are late for their dates;
--     * otherwise the CEO applies its own rejection: while no trade is open to customers (trade_customer_opening), the
--       customer-only ideas leave the plan (supply first; ledger 1614 opens customers trade by trade). With 4 or more
--       ideas left it is APPROVED ('ceo_approved'), and the normal path takes it to the founder's one monthly approval
--       (ledger 1059 kept); with fewer it is withdrawn and marketing drafts the next month fresh.
--   It reads the idea's own audience field, never its words (instruction 890).
-- NOT CHANGED: the model review of a NEW plan (fn_marketing_month_plan_to_ceo), social_send_enabled and every switch.
-- prevented by: scripts/checks/the_ceo_settles_a_month_plan_that_waits_on_a_revision_nobody_wrote.test.mjs
-- Pending: scripts/sql/pending/the_ceo_settles_a_month_plan_that_waits_on_a_revision_nobody_wrote.txt

create or replace function public.fn_ceo_settles_stuck_month_plans(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare p public.marketing_month_plan; v_key text; v_last public.ceo_decision_round; v_day date := (p_at at time zone 'Asia/Dubai')::date;
  v_open int := 0; v_kept jsonb; v_dropped int; v_cyc jsonb; v_reasons text; v_out jsonb := '[]'::jsonb;
begin
  if to_regclass('public.trade_customer_opening') is not null then
    execute 'select count(*) from public.trade_customer_opening where is_open' into v_open;
  end if;
  for p in select * from public.marketing_month_plan where status = 'ceo_reviewing' and plan is not null order by month loop
    v_key := 'marketing_month_plan:' || p.month;
    select * into v_last from public.ceo_decision_round r where r.item_key = v_key order by r.decided_at desc limit 1;
    -- only a plan the CEO already rejected, whose revision has not come in 3 days
    continue when v_last.id is null or v_last.decision <> 'rejected' or v_last.decided_at > p_at - interval '3 days'
                  or p.updated_at > v_last.decided_at + interval '1 minute';
    if p.month + 7 <= v_day then
      v_reasons := format('Withdrawn by the CEO: the %s plan is %s days into its month and its revision never came, so its video dates have passed. Marketing carries what still fits into the next month''s plan.',
                          to_char(p.month, 'FMMonth YYYY'), v_day - p.month);
      v_cyc := public.fn_ceo_decide('marketing_month_plan', v_key, 'marketing', 'withdrawn', v_reasons,
                 jsonb_build_object('month', p.month, 'ideas', p.plan->'ideas'), 'ceo_month_plan_settle', v_key || ':' || v_day);
      update public.marketing_month_plan set status = 'rejected', updated_at = now(),
             verdict = coalesce(verdict, '{}'::jsonb) || jsonb_build_object('ceo', jsonb_build_object('decision', 'withdrawn', 'reasons', v_reasons, 'by', 'code', 'cycle', v_cyc))
       where month = p.month;
      v_out := v_out || jsonb_build_object('month', p.month, 'decision', 'withdrawn');
      continue;
    end if;
    select coalesce(jsonb_agg(e order by (e->>'n')::int), '[]'::jsonb), count(*) filter (where false)
      into v_kept, v_dropped from jsonb_array_elements(p.plan->'ideas') e
     where v_open > 0 or coalesce(e->>'audience', 'both') <> 'customer';
    v_dropped := jsonb_array_length(p.plan->'ideas') - jsonb_array_length(v_kept);
    if jsonb_array_length(v_kept) >= 4 then
      v_reasons := format('Approved by the CEO after its own rejection was applied: %s customer-only idea(s) removed because no trade is open to customers yet (ledger 1614, supply first); %s supplier and shared ideas remain on UAE working days. It now goes to the founder''s one monthly approval.',
                          v_dropped, jsonb_array_length(v_kept));
      v_cyc := public.fn_ceo_decide('marketing_month_plan', v_key, 'marketing', 'approved', v_reasons,
                 jsonb_build_object('month', p.month, 'ideas', v_kept), 'ceo_month_plan_settle', v_key || ':' || v_day);
      update public.marketing_month_plan set status = 'ceo_approved', updated_at = now(),
             plan = plan || jsonb_build_object('ideas', v_kept, 'revisions', coalesce(plan->'revisions', '[]'::jsonb)
                      || jsonb_build_array(jsonb_build_object('by', 'ceo', 'at', p_at, 'dropped_customer_only', v_dropped, 'why', 'no trade open to customers'))),
             verdict = coalesce(verdict, '{}'::jsonb) || jsonb_build_object('ceo', jsonb_build_object('decision', 'approved', 'reasons', v_reasons, 'by', 'code', 'cycle', v_cyc))
       where month = p.month;
      v_out := v_out || jsonb_build_object('month', p.month, 'decision', 'approved', 'ideas', jsonb_array_length(v_kept), 'dropped', v_dropped);
    else
      v_reasons := format('Withdrawn by the CEO: only %s idea(s) remain once the customer-only ones leave (no trade is open to customers yet), too few for a month. Marketing drafts the next month fresh.', jsonb_array_length(v_kept));
      v_cyc := public.fn_ceo_decide('marketing_month_plan', v_key, 'marketing', 'withdrawn', v_reasons,
                 jsonb_build_object('month', p.month, 'ideas', p.plan->'ideas'), 'ceo_month_plan_settle', v_key || ':' || v_day);
      update public.marketing_month_plan set status = 'rejected', updated_at = now(),
             verdict = coalesce(verdict, '{}'::jsonb) || jsonb_build_object('ceo', jsonb_build_object('decision', 'withdrawn', 'reasons', v_reasons, 'by', 'code', 'cycle', v_cyc))
       where month = p.month;
      v_out := v_out || jsonb_build_object('month', p.month, 'decision', 'withdrawn');
    end if;
  end loop;
  return jsonb_build_object('settled', v_out, 'trades_open', v_open);
end $fn$;
revoke execute on function public.fn_ceo_settles_stuck_month_plans(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_settles_stuck_month_plans(timestamptz) to service_role;
create or replace function public.fn_ceo_settles_stuck_month_plans_now()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$ select public.fn_ceo_settles_stuck_month_plans(now()) $fn$;
revoke execute on function public.fn_ceo_settles_stuck_month_plans_now() from public, anon, authenticated;
grant execute on function public.fn_ceo_settles_stuck_month_plans_now() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.month_plan_settle', 'ceo', interval '1 day', 'fn_ceo_settles_stuck_month_plans_now',
   'Every day, a marketing month plan the CEO rejected more than 3 days ago with no revision is settled by the CEO in code, with reasons: withdrawn when its month is under way, else approved once the CEO''s own rejection is applied (customer-only ideas out while no trade is open).',
   'scripts/sql/the_ceo_settles_a_month_plan_that_waits_on_a_revision_nobody_wrote.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
