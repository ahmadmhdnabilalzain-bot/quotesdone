-- THE NON-CUSTOMER MODEL SPEND STOPS AT A DAILY CEILING (it_engineer, 3 Nov 2026)
--
-- The founder, after topping OpenRouter up: "i cant risk suppliers going to the portal and registering and we lose them.
-- just make sure we dont waste money in a stupid way."
--
-- MEASURED (ai_cost_log and openrouter_day, 7 days to 3 Nov 13:16 UTC): OpenRouter billed USD 141.20, nearly all of it our
-- own tests (wa_inbound conversation_reply 1,450 Sonnet calls, USD 31.87, only 190 of them carrying a run tag; the
-- trade-choice harness 13,762 calls). The internal duties ran on top with no bound: resilience_ping on the CEO's Opus route
-- USD 4.76 for 27 calls, the it_engineer postmortem replays 234 Luna calls.
--
-- WHAT THIS ADDS. public.fn_ai_spend_ceiling(p_class) answers ai_gateway (_shared/spend_ceiling.ts) whether one more call
-- of a class may run today (Asia/Dubai day, the day openrouter_day keeps):
--   'test'     - rows carrying a run tag (ai_cost_log.e2e_run_tag, stamped only for a PROVEN sandbox run);
--   'internal' - rows ai_gateway marked "| spend_class=internal" (an internal duty its caller declared).
-- The ceilings are it_threshold rows, so changing one is a data change: llm_daily_ceiling_test_usd 10 and
-- llm_daily_ceiling_internal_usd 2 (the founder's idle rule of 24 Sep 2026, instruction 986: USD 1-2 a day with no
-- customers). A missing or null row means no ceiling for that class.
--
-- WHAT IT DOES NOT DO. It never counts or refuses a customer's, a supplier's or a visitor's call: those carry neither a
-- run tag nor the internal declaration, and the gateway does not ask this function about them at all. A rehearsal
-- window's own cap is unchanged (fn_kernel_paid_provider_gate, fn_rehearsal_spend_reserve). Spend is summed from the
-- ledger as it stands, so a call in flight is not counted until it is logged: the ceiling can be passed by the calls
-- that were already running when it was reached (ponytail: no reservation; the window reservation exists for tests).
--
--   node scripts/apply_sql.mjs scripts/sql/the_non_customer_model_spend_stops_at_a_daily_ceiling.sql --apply --ddl

insert into public.it_threshold (key, value, unit, basis) values
  ('llm_daily_ceiling_test_usd', 10, 'usd',
   'it_engineer, 3 Nov 2026: tagged test traffic (ai_cost_log.e2e_run_tag) per Asia/Dubai day. Measured 7 days to 3 Nov: USD 141.20 billed, nearly all tests. Past it ai_gateway SKIPS the call (no provider call, run row skipped).'),
  ('llm_daily_ceiling_internal_usd', 2, 'usd',
   'it_engineer, 3 Nov 2026: internal duties (resilience_ping, marketing, knowledge_exam asking an internal-audience question) per Asia/Dubai day. The founder''s idle rule of 24 Sep 2026 (instruction 986): USD 1-2 a day with no customers.')
on conflict (key) do nothing;

create or replace function public.fn_ai_spend_ceiling(p_class text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_ceiling numeric;
  v_spent numeric;
  v_day date := (now() at time zone 'Asia/Dubai')::date;
begin
  if p_class is null or p_class not in ('test', 'internal') then
    -- Not a class this ceiling knows: never refused (the gateway only asks for these two).
    return jsonb_build_object('allowed', true, 'class', p_class, 'why', 'not a counted class');
  end if;
  v_ceiling := public.fn_it_threshold(case p_class when 'test' then 'llm_daily_ceiling_test_usd' else 'llm_daily_ceiling_internal_usd' end);
  if v_ceiling is null then
    return jsonb_build_object('allowed', true, 'class', p_class, 'why', 'no ceiling set');
  end if;
  -- OpenRouter's own charge where it reported one, else our price list (cost_aed at the fixed AED peg).
  select coalesce(sum(coalesce(l.cost_usd_reported, l.cost_aed / 3.6725)), 0) into v_spent
    from public.ai_cost_log l
   where (l.occurred_at at time zone 'Asia/Dubai')::date = v_day
     and l.model_used is distinct from 'none'
     and case p_class when 'test' then l.e2e_run_tag is not null
                      else l.e2e_run_tag is null and l.model_selected_because like '%| spend_class=internal%' end;
  return jsonb_build_object('allowed', v_spent < v_ceiling, 'class', p_class, 'spent_usd', round(v_spent, 4),
                            'ceiling_usd', v_ceiling, 'day', v_day);
end $fn$;

revoke execute on function public.fn_ai_spend_ceiling(text) from public, anon, authenticated;
grant execute on function public.fn_ai_spend_ceiling(text) to service_role;

comment on function public.fn_ai_spend_ceiling(text) is
  'it_engineer, 3 Nov 2026: may one more model call of a non-customer class (test | internal) run today? Asked by ai_gateway only (_shared/spend_ceiling.ts); customer, supplier and visitor calls are never asked about. scripts/sql/the_non_customer_model_spend_stops_at_a_daily_ceiling.sql';

-- PROBE (verdict row; it writes nothing): both ceilings are set, an unknown class is allowed, and the answer has its shape.
select case
  when public.fn_it_threshold('llm_daily_ceiling_test_usd') is null or public.fn_it_threshold('llm_daily_ceiling_internal_usd') is null
    then 'PROBE FAILED: a ceiling row is missing'
  when (public.fn_ai_spend_ceiling('customer') ->> 'allowed')::boolean is not true
    then 'PROBE FAILED: a class that is not counted was refused'
  when public.fn_ai_spend_ceiling('test') ->> 'spent_usd' is null or public.fn_ai_spend_ceiling('internal') ->> 'ceiling_usd' is null
    then 'PROBE FAILED: the answer lacks spent_usd or ceiling_usd'
  else 'PROBE OK' end as verdict;
