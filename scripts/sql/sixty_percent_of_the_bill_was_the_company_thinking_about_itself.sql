-- SIXTY PERCENT OF THE BILL WAS THE COMPANY THINKING ABOUT ITSELF.
--
-- The founder, 12 Aug 2026: "I am literally spending almost 0.3 usd per hour... most internal
-- operations was supposed to be part of the code and not an actual spend on open router."
--
-- HALF THE PREMISE IS WRONG AND HALF IS EXACTLY RIGHT, AND BOTH HALVES ARE MEASURED.
--
-- Wrong half: 0.3 USD/hour was a SESSION - probes and scorer re-runs on 12 Aug - not the company.
-- Right half, and it is worse than the headline: the idle company is not 6 cents an hour either.
-- ai_cost_log, agent_brain + cos_execute on Anthropic models, one row per day:
--
--     1 Aug   3 calls   0.61 AED        6 Aug  54 calls  15.00 AED
--     2 Aug   4 calls   0.91 AED        7 Aug  48 calls  12.62 AED
--     3 Aug   6 calls   1.01 AED        8 Aug  43 calls  11.19 AED
--     4 Aug   0 calls   0.00 AED        9 Aug  47 calls  11.85 AED
--     5 Aug   4 calls   0.41 AED       10 Aug  52 calls  12.51 AED
--                                      11 Aug  61 calls  11.61 AED
--
-- On 6 August the company generated a queue of tasks about ITSELF and the bill went up twelvefold
-- overnight, then held there every day since, on days with and without a session. 385 org_tasks are
-- open right now; 346 of them are action_class='analysis' and 15 more are 'recommend'. Two are
-- 'invite'. Demand on the same date: 0 customers, 0 inquiries, 0 quotes, 0 transactions, 0 approved
-- suppliers. The company is paying claude-sonnet-5 roughly 25,000 input tokens a call, 45 calls a
-- day, to analyse a business that has not yet had a customer.
--
-- WHERE, EXACTLY. 290 of the 316 agent_brain Anthropic calls in the last 7 days - 92% of them,
-- 71.27 of 77.02 AED - fire at minute 50 or 51 of the hour. That is cron job 124,
-- cos_execute_hourly, `50 * * * *`. cos_execute takes MAX_TASKS=2 off the head of the assigned
-- queue every hour, hands each to agent_brain at ~25k input tokens, and fn_task_review then spends
-- more calls having the department head and the Chief of Staff review it. The queue is FIFO by id
-- and it is 346 rows of self-analysis deep, so this runs 24 hours a day and will not reach the
-- bottom of it for a week.
--
-- THE DISCIPLINE ALREADY EXISTS AND WAS NEVER APPLIED TO THIS PATH. model_policy carries 17 task
-- classes at tier='none', each with a written deterministic_alternative - kpi_calculation "SQL over
-- employee_kpi", supplier_scoring "SQL", date_calculation "SQL date functions". The catch-all
-- `agent_reasoning` sits at tier='large' with no deterministic alternative and no gate, and it is
-- 71% of all spend. Nothing decides whether a task is WORTH a large model before one is called.
--
-- WHAT THIS ADDS: one deterministic gate, and it is a gate on the WORK, not on the model.
--
--   * Demand-linked work is NEVER capped. An invite, an inquiry, a quote, an onboarding, a
--     registration chase, a collection - the revenue path runs as often as there is work for it.
--   * Reflection - the company analysing itself - gets a daily ceiling. Default 6 tasks a day
--     against the 48 the hourly loop can currently work.
--
-- It opens by itself. The gate never asks whether demand EXISTS; it asks whether THIS TASK is on
-- the revenue path. The day an inquiry arrives, the tasks it raises are demand-classed and run
-- uncapped without anyone changing a setting. That is deliberate: a gate keyed on "is the company
-- busy yet" is a gate somebody has to remember to open.
--
-- NOT A WEAKENED CHECK. Nothing here makes a failing thing pass. The company will finish fewer
-- self-analysis tasks per day and the org_tasks backlog will drain more slowly, and both of those
-- numbers should be read as what they are: the company was buying them, at 11-15 AED a day, with
-- no customer at the other end. If a scorer counts throughput on that queue it will drop, and that
-- is the true reading, not a regression.
--
-- ESTIMATE, STATED AS AN ESTIMATE: 6 reflection tasks a day at the measured 1.3 model calls per
-- task and 0.24 AED per call is ~1.9 AED/day against the 11.19-15.00 AED/day this path has cost
-- every day since 6 August. The verification is a measurement 24 hours from now, not this comment.

-- ── the demand classifier ───────────────────────────────────────────────────────────────────────
-- IMMUTABLE and pure text so it can be used in an index or a check later without surprise, and so
-- there is exactly ONE list. cos_execute does not carry its own copy; it reads the list back out of
-- fn_cos_work_gate()'s payload, which is why the payload returns it.
create or replace function public.fn_task_is_demand(p_action_class text)
returns boolean
language sql
immutable
as $function$
  select coalesce(p_action_class,'') ~*
    -- the revenue path: someone outside the company is on the other end of it
    '(invite|quote|rfq|inquir|lead|customer|supplier|onboard|registration|approv|kyc|collection|payment|refund|dispute|contract|delivery|fulfil)'
$function$;

comment on function public.fn_task_is_demand(text) is
  'TRUE when an org_task action_class is on the revenue path (someone outside the company is at the '
  'other end). The single source of truth for the cos_execute work gate; see '
  'scripts/sql/sixty_percent_of_the_bill_was_the_company_thinking_about_itself.sql.';

-- ── the daily ceiling ───────────────────────────────────────────────────────────────────────────
-- decision_policy, not a constant in the edge function, so the company can move its own ceiling
-- without a deploy - and so fn_ai_spend_guard has something to turn down when it needs to.
insert into public.decision_policy(key, value, description, updated_at)
values (
  'cos_reflection_tasks_per_day',
  to_jsonb(6),
  'Maximum org_tasks NOT on the revenue path that cos_execute may hand to a large model in one UTC '
  'day. Demand-linked tasks (fn_task_is_demand) are never counted and never capped. Raise this when '
  'reflection is earning its keep; it exists because on 6 Aug 2026 a 346-row self-analysis queue '
  'took the daily AI bill from ~1 AED to 11-15 AED with zero customers, inquiries or quotes.',
  now())
on conflict (key) do update
  set value = excluded.value, description = excluded.description, updated_at = now();

-- ── the gate ────────────────────────────────────────────────────────────────────────────────────
-- SECURITY INVOKER on purpose: cos_execute calls it with the service role, and a gate that reads
-- two tables needs no elevated rights. STABLE, no writes - it decides, it does not record.
--
-- THE COUNTER IS THE TASK, NOT THE MODEL CALL, and that is a deliberate choice. Counting rows in
-- ai_cost_log where fn='agent_brain' would also count the founder's own chats with his employees
-- through the workspace, so his asking the CFO a question would spend the company's reflection
-- budget. Counting org_tasks that cos_execute touched today counts exactly the loop being capped.
--
-- 'executed_by_invoker' is excluded because that mode means an EDGE EXECUTOR did the work, not a
-- model - the 10 knowledge_acquire tasks kb_deepen closed today cost 0.026 AED each and are not
-- what this ceiling is for. Capping them would exhaust the budget on the cheapest path in the
-- company and idle the expensive one by accident.
create or replace function public.fn_cos_work_gate()
returns jsonb
language plpgsql
stable
as $function$
declare
  v_budget int;
  v_used   int;
  v_demand int;
  v_reflect int;
  v_classes jsonb;
begin
  select coalesce((value #>> '{}')::int, 6) into v_budget
    from public.decision_policy where key = 'cos_reflection_tasks_per_day';
  v_budget := coalesce(v_budget, 6);

  select count(*) into v_used
    from public.org_tasks k
   where k.last_run_at >= date_trunc('day', (now() at time zone 'utc')) at time zone 'utc'
     and not public.fn_task_is_demand(k.action_class)
     -- NOT `result->>'mode' <> 'executed_by_invoker'`, which is what this said first and it
     -- over-counted by ten on the first run. That mode is written by fn_action_invoke_collect at
     -- COLLECT time, so a task the invoker dispatched at :45 and has not collected yet still reads
     -- mode NULL and was counted as model work. The ten 'Supply gap' knowledge_acquire tasks in
     -- flight this morning are exactly that: kb_deepen at 0.026 AED a call, charged against a
     -- ceiling meant for a 25,000-token one. The invoker ALWAYS leaves an action_execution row and
     -- the cos_execute model path never does, so the row is the reliable discriminator and it is
     -- true from dispatch, not from collection.
     and not exists (
       select 1 from public.action_execution a
        where (a.request->>'org_task_id') = k.id::text
          and a.created_at >= date_trunc('day', (now() at time zone 'utc')) at time zone 'utc');

  select count(*) filter (where not public.fn_task_is_demand(action_class))
    into v_reflect
    from public.org_tasks where status in ('assigned','in_progress');

  -- The concrete classes cos_execute may select on. PostgREST cannot evaluate the regex above, so
  -- the gate resolves it here against the classes that ACTUALLY have open work and hands back a
  -- list. One source of truth, and the edge function carries no copy of the pattern.
  --
  -- AND IT REFUSES ANY CLASS WIRED TO AN UNSAFE EXECUTOR. This gate moves demand work to the FRONT
  -- of cos_execute's queue, and a cost control must never widen a risk. Found on the first run, and
  -- it was not hypothetical: org_tasks 1360 and 1361 - "Start invites: kitchen-and-bathroom-
  -- suppliers", "Start invites: real-estate-agencies" - are action_class='invite', tier='autonomous',
  -- status='assigned', wired to fn_org_exec_invite with risk_tier='high', advisory_safe=false,
  -- reversible=false. They carry the HIGHEST ids in a 385-row FIFO queue, so today they are
  -- unreachable; promoting 'invite' to the head of the queue would have put a high-risk irreversible
  -- supplier mailing first in line, on the exact day the founder wrote "LAST — supplier invites. DO
  -- NOT ENABLE YET" because the bounce rate is at the platform's own 0.08 brake.
  --
  -- A class is eligible only if NO active executor for it is high-risk, irreversible or not
  -- advisory-safe. This is the same triple fn_org_task_execute_sweep already requires before it will
  -- invoke anything; the two paths now agree instead of disagreeing.
  select coalesce(jsonb_agg(distinct k.action_class), '[]'::jsonb) into v_classes
    from public.org_tasks k
   where k.status in ('assigned','in_progress')
     and k.action_class is not null
     and public.fn_task_is_demand(k.action_class)
     and not exists (
       select 1 from public.org_action_executor e
        where e.action_class = k.action_class and e.active
          and (e.risk_tier <> 'low' or not e.advisory_safe or not e.reversible));

  -- demand_open counts ELIGIBLE demand only — the same set cos_execute can actually select. Counting
  -- every demand-classed row here would report "2 revenue-path tasks still run uncapped" for two
  -- invite tasks the gate has just refused to hand over, and gated=false would then describe a run
  -- that in fact calls no model. The number and the decision have to come from one set.
  select count(*) into v_demand
    from public.org_tasks
   where status in ('assigned','in_progress')
     and action_class is not null
     and v_classes ? action_class;

  return jsonb_build_object(
    'demand_classes',         v_classes,
    'reflection_budget',      v_budget,
    'reflection_used_today',  v_used,
    'reflection_allowed',     v_used < v_budget,
    'demand_open',            v_demand,
    'reflection_open',        v_reflect,
    -- nothing at all to do without a model: the ceiling is spent AND no revenue-path task is waiting
    'gated',                  (v_used >= v_budget and v_demand = 0),
    'reason', case
        when v_used < v_budget then
          'reflection ' || v_used || '/' || v_budget || ' today; working normally'
        when v_demand > 0 then
          'reflection ceiling reached (' || v_used || '/' || v_budget || '); ' || v_demand ||
          ' revenue-path task(s) still run uncapped'
        else
          'reflection ceiling reached (' || v_used || '/' || v_budget || ') and no revenue-path task '
          'is waiting, so no model is called this run'
      end
  );
end
$function$;

comment on function public.fn_cos_work_gate() is
  'Deterministic pre-flight for cos_execute. Revenue-path tasks are never capped; self-analysis is '
  'capped at decision_policy.cos_reflection_tasks_per_day. Returns gated=true when the ceiling is '
  'spent and no revenue-path task is waiting, which is the only case where cos_execute calls no '
  'model at all.';

-- Both functions are NEW, so both were granted EXECUTE to PUBLIC on creation. Revoke from PUBLIC
-- (revoking from anon alone is a silent no-op while the grant is held through PUBLIC) and hand it
-- back only to the roles that need it: service_role for the edge function, authenticated so the
-- workspace can show the founder why the loop is idle.
revoke execute on function public.fn_task_is_demand(text) from public;
revoke execute on function public.fn_cos_work_gate() from public;
grant execute on function public.fn_task_is_demand(text) to service_role, authenticated;
grant execute on function public.fn_cos_work_gate() to service_role, authenticated;
