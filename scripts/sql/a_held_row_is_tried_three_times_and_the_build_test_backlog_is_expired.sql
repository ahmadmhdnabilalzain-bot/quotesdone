-- A HELD ROW IS TRIED THREE TIMES, NOT FIVE, AND THE BUILD-TEST BACKLOG IS EXPIRED.
-- Seat: it_engineer. 24 Sep 2026, before the founder opens OpenRouter credit.
--
-- THERE IS NO MONEY CEILING HERE, ON PURPOSE. The founder, 24 Sep 2026 (founder_instruction 987): no caps on LLM
-- spend; idle spend stays at or below USD 1-2 a day because the code is correct, not because a ceiling stops it.
-- An earlier draft of this file added a daily AED limit and per-class call limits (fn_llm_budget_gate); it was
-- never applied and was removed before merge. Idle spend is proved path by path in the PR (IDLE_PROOF).
--
-- MEASURED (OpenRouter inventory, 24 Sep 04:03 UTC, production read-only):
--   * 388 held questions would replay the moment the hold lifts, each retried up to 5 times;
--   * 178 line_specs.assess rows (plus 52 sql.trg_quote_quality, 5 ceo.task_responsibility and 1 document_arabic)
--     were filed by sandbox build and E2E traffic on 23-24 Sep and would be paid for on day one.
--
-- WHAT THIS FILE DOES (correctness, not budget)
--   1. fn_reason_held_due / fn_reason_held_resolve: a row fails after 3 attempts (was 5). This is the loop bound:
--      a question the model cannot answer is not retried forever.
--   2. fn_reason_held_resolve: a replay refused by the founder's hold (reason 'model_hold', nothing was spent)
--      gives its attempt back - waiting while the model is off is not a failure.
--   3. fn_reason_held_due expires a fixture row (ZZ DEMO / @example.invalid, or subject.fixture) before it could be
--      claimed, on every tick, so the next e2e run cannot file a row that is later paid for.
--   4. Expires the build-test rows in the reason queue by exact criteria (below). No real row is touched.
--      A test row is not a question; paying to answer it would be a defect, not a cost.
--
-- Pending: scripts/sql/pending/a_held_row_is_tried_three_times_and_the_build_test_backlog_is_expired.txt
-- Prevented by: scripts/checks/a_held_row_is_tried_three_times_and_no_spend_ceiling_exists.test.mjs

-- From a_held_question_never_expires_it_is_escalated_at_48_hours.sql (canonical), with 5 -> 3.
create or replace function public.fn_reason_held_due(p_limit integer default 3)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_gate jsonb; v jsonb;
begin
  update public.reasoning_held_question set status = 'failed' where status = 'held' and attempts >= 3;
  -- A fixture row is never replayed (a replay would pay for a test question): the estate's fixture convention in the
  -- question or request, or a caller's subject.fixture flag. Same criteria as the one-off expiry at the end of this file.
  update public.reasoning_held_question
     set status = 'expired', result = coalesce(result, '{}'::jsonb) || jsonb_build_object('expired_by', 'fn_reason_held_due', 'why', 'fixture, never paid for')
   where status = 'held'
     and (question ~ 'ZZ DEMO|@example\.invalid' or request::text ~ 'ZZ DEMO|@example\.invalid' or subject->>'fixture' = 'true');
  v_gate := public.fn_kernel_paid_provider_gate('hold-probe/not-a-model');
  if coalesce(v_gate->>'rule', '') in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state') then
    return '[]'::jsonb;
  end if;
  with due as (
    select id from public.reasoning_held_question
     where status = 'held' and attempts < 3
       and (last_attempt_at is null or last_attempt_at < now() - interval '10 minutes')
     order by last_attempt_at nulls first, created_at
     limit greatest(1, least(coalesce(p_limit, 3), 10))
     for update skip locked
  ), claimed as (
    update public.reasoning_held_question h set attempts = h.attempts + 1, last_attempt_at = now()
      from due where h.id = due.id
    returning h.id, h.seat, h.surface, h.request, h.subject
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) into v from claimed;
  return v;
end $fn$;

-- From a_reasoned_answer_is_applied_by_its_own_surface.sql (canonical, byte-equal to production), with 5 -> 3
-- and the attempt given back when the replay was refused by a gate (reason 'model_hold': nothing was spent).
create or replace function public.fn_reason_held_resolve(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_effect jsonb := null; v_fn text;
begin
  select * into r from public.reasoning_held_question where id = p_id for update;
  if not found then raise exception 'no held question %', p_id using errcode = 'P0002'; end if;
  if coalesce(p_result->>'status', '') <> 'answered' then
    if coalesce(p_result->>'reason', '') = 'model_hold' then
      update public.reasoning_held_question
         set result = p_result, status = 'held', attempts = greatest(attempts - 1, 0)
       where id = p_id;
      return jsonb_build_object('id', p_id, 'status', 'still_held', 'attempt_returned', true);
    end if;
    update public.reasoning_held_question
       set result = p_result, status = case when attempts >= 3 then 'failed' else 'held' end
     where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'still_held');
  end if;
  update public.reasoning_held_question set result = p_result, status = 'reasoned', reasoned_at = now() where id = p_id;
  if r.surface = 'ceo.command_intent' and (r.subject->>'command_id') is not null then
    v_effect := public.fn_ceo_command_interpret((r.subject->>'command_id')::bigint, p_result->'decision'->>'choice',
                  left(coalesce(p_result->>'answer', ''), 1000));
  elsif r.surface = 'inquiry_intake.trade' and (r.subject->>'intake_id') is not null then
    update public.inquiry_intake i
       set category = p_result->'decision'->>'choice', status = 'needs_info', updated_at = now(),
           brief = coalesce(i.brief, '{}'::jsonb) || jsonb_build_object('category_by', 'reasoning', 'held_id', p_id)
     where i.id::text = r.subject->>'intake_id' and i.status = 'held'
       and exists (select 1 from public.category_specs cs where cs.category = p_result->'decision'->>'choice');
    v_effect := jsonb_build_object('intake_id', r.subject->>'intake_id', 'category', p_result->'decision'->>'choice', 'reopened', found);
  else
    v_fn := 'fn_reason_apply_' || replace(r.surface, '.', '__');
    if length(v_fn) <= 63 and to_regprocedure(format('public.%I(bigint,jsonb)', v_fn)) is not null then
      execute format('select public.%I($1, $2)', v_fn) into v_effect using p_id, p_result;
      v_effect := coalesce(v_effect, jsonb_build_object('applied_by', v_fn));
    end if;
  end if;
  if v_effect is not null then
    update public.reasoning_held_question set status = 'applied', applied_at = now() where id = p_id;
  end if;
  return jsonb_build_object('id', p_id, 'status', case when v_effect is null then 'reasoned' else 'applied' end, 'effect', v_effect);
end $fn$;

-- THE BUILD-TEST ROWS ARE EXPIRED, BY EXACT CRITERIA, NEVER BY GUESS (measured 24 Sep 2026: 236 rows).
--   A. the question or the request carries the fixture convention (ZZ DEMO / @example.invalid): 168 line_specs.assess,
--      52 sql.trg_quote_quality, 5 ceo.task_responsibility, 1 sales_engineer.document_arabic;
--   B. the other 10 line_specs.assess rows: the question is, whitespace aside, one of the two gypsum fixture
--      quotations of scripts/e2e/journey_audit_buttons.mjs, the subject is a supplier_api review key
--      ('review:<inquiry>:<lead>'), and the inquiry it names no longer exists (the harness removed it).
--   A row about a live inquiry or quote is never matched: both arms need a fixture marker, and B needs the
--   inquiry to be gone. The sales_engineer.document_arabic row without a marker is NOT expired.
update public.reasoning_held_question h
   set status = 'expired',
       result = coalesce(h.result, '{}'::jsonb) || jsonb_build_object('expired_by',
         'a_held_row_is_tried_three_times_and_the_build_test_backlog_is_expired.sql',
         'why', 'sandbox build / E2E fixture traffic, not a real question; never paid for')
 where h.status = 'held'
   and (
        h.question ~ 'ZZ DEMO|@example\.invalid' or h.request::text ~ 'ZZ DEMO|@example\.invalid'
     or (h.surface = 'line_specs.assess'
         and h.subject->>'quote_id' ~ '^review:[0-9a-f-]{36}:'
         and regexp_replace(h.question, '\s+', ' ', 'g') in (
           'LINE 1: Gypsum board partition 100mm metal stud, both faces LINE 2: Suspended false ceiling 600x600 mineral fibre LINE 3: Gypsum bulkhead 300mm drop, painted finish',
           'LINE 1: Gypsum board partition 12.5mm board 100mm metal stud both faces LINE 2: Suspended false ceiling 600x600 mineral fibre tiles LINE 3: Gypsum bulkhead standard gypsum board 300mm drop painted finish')
         and not exists (select 1 from public.inquiries i
                          where i.id::text = substring(h.subject->>'quote_id' from '^review:([0-9a-f-]{36}):')))
   );

-- Verdict row (DDL in this file, so no raise): the retry bound is 3, and no fixture row is left held.
select case
  when position('attempts < 3' in pg_get_functiondef('public.fn_reason_held_due(integer)'::regprocedure)) = 0
    then 'PROBE FAILED: fn_reason_held_due does not bound a row at 3 attempts'
  when exists (select 1 from public.reasoning_held_question where status = 'held'
                and (question ~ 'ZZ DEMO|@example\.invalid' or request::text ~ 'ZZ DEMO|@example\.invalid'))
    then 'PROBE FAILED: a fixture row is still held'
  else 'PROBE OK' end as verdict;
