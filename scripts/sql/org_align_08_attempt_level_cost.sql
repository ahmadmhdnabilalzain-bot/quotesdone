-- ORG ALIGNMENT 08 — a retry's cost was real money that nothing recorded.
--
-- MEASURED (staging, 15 Aug 2026, after a 13-scenario capped smoke):
--
--   select count(*), count(cost_aed) from llm_attempt;   -->  666 rows,  0 with a cost
--   select count(*), count(cost_aed) from ai_cost_log;   --> 4336 rows, 4336 with a cost
--
-- The money IS captured — in ai_cost_log, per REQUEST, against agent_key, tier and task_class.
-- AED 119.39 lifetime, AED 2.44 for the smoke run. So "cost is not captured" would have been a
-- false finding, and is not the claim here.
--
-- The claim is narrower and still real: llm_attempt is the per-ATTEMPT ledger, and a request that
-- climbs the fallback ladder makes several attempts. ai_cost_log records ONE row for the request,
-- costed against the model that finally answered. The tokens burned by an attempt that failed, or
-- by an attempt on a model that then fell back, are not attributable to anything. That is exactly
-- the "instrument reporting on the wrong subject" shape: a per-attempt table with cost columns
-- that are null on every row it has ever held.
--
-- fn_record_llm_attempt ALREADY accepts prompt_tokens, output_tokens and cost_aed and already
-- inserts them. Nothing ever passed them: the gateway's recordAttempt() sends nine fields and none
-- of the three is among them. So the fix is (a) pass the tokens from the gateway, which has them
-- in scope at the moment it records a successful attempt, and (b) let this function derive the
-- money from the same pricing source ai_cost_log uses, rather than trusting a caller to convert.

-- The AED peg, named once. fn_llm_log carries the same arithmetic inline; the factor here was
-- derived by MEASURING what fn_llm_log actually produces rather than by reading a constant out of
-- it, so the two are known to agree today:
--
--   fn_llm_log(... 100000 in, 10000 out ...) -> 0.146898 AED
--   fn_model_cost_usd(same model, same tokens) -> 0.040000 USD      ratio 3.672450
--
-- scripts/checks/workflow_ownership_alignment.test.mjs re-derives that ratio, so if either side
-- ever moves the check fails instead of the two ledgers quietly disagreeing.
create or replace function public.fn_usd_to_aed()
returns numeric language sql immutable as $$ select 3.672450::numeric $$;

comment on function public.fn_usd_to_aed() is
  'The AED/USD peg used to price model calls. Measured against fn_llm_log''s own arithmetic on '
  '15 Aug 2026 (0.146898 AED / 0.040000 USD = 3.672450).';

create or replace function public.fn_record_llm_attempt(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_req      uuid    := coalesce(nullif(p->>'request_id','')::uuid, gen_random_uuid());
  v_model    text    := nullif(p->>'model_route','');
  v_ok       boolean := coalesce((p->>'ok')::boolean, false);
  v_no       integer;
  v_cls      jsonb;
  v_key      text;
  v_trips    boolean;
  v_first    boolean;
  v_thresh   integer;
  v_cool     integer;
  v_conseq   integer;
  v_state    text := 'closed';
  v_id       uuid;
  v_in       integer := nullif(p->>'prompt_tokens','')::integer;
  v_out      integer := nullif(p->>'output_tokens','')::integer;
  v_cached   integer := coalesce(nullif(p->>'cached_in_tokens','')::integer, 0);
  v_cost     numeric := nullif(p->>'cost_aed','')::numeric;
begin
  if v_model is null then
    raise exception 'fn_record_llm_attempt requires model_route: the route is what the breaker keys on';
  end if;

  if not v_ok then
    v_cls := fn_classify_llm_failure(p->>'err_excerpt',
                                     nullif(p->>'http_status','')::integer,
                                     p->>'finish_reason', v_model,
                                     nullif(p->>'latency_ms','')::integer);
    v_key := v_cls->>'class_key';
  end if;

  -- attempt_no is assigned HERE, never accepted from the caller. A caller cannot claim to be
  -- attempt 1 twice, and cannot renumber an earlier attempt out of the way.
  select coalesce(max(attempt_no), 0) + 1 into v_no from llm_attempt where request_id = v_req;

  insert into llm_route_health (model_id) values (v_model) on conflict (model_id) do nothing;
  select failure_threshold, cooldown_seconds into v_thresh, v_cool
    from llm_route_health where model_id = v_model;

  if v_ok then
    update llm_route_health
       set consecutive_failures = 0, open_until = null, opened_reason = null, opened_class = null,
           last_ok_at = now(), total_attempts = total_attempts + 1, total_ok = total_ok + 1,
           updated_at = now()
     where model_id = v_model;
  else
    select trips_breaker, opens_on_first into v_trips, v_first
      from llm_failure_class where class_key = v_key;
    update llm_route_health
       set consecutive_failures = case when coalesce(v_trips,false)
                                       then consecutive_failures + 1 else consecutive_failures end,
           last_failure_at = now(), total_attempts = total_attempts + 1, updated_at = now()
     where model_id = v_model
     returning consecutive_failures into v_conseq;

    if coalesce(v_trips,false) and (coalesce(v_first,false) or v_conseq >= v_thresh) then
      update llm_route_health
         set open_until = now() + make_interval(secs => v_cool),
             opened_reason = case when coalesce(v_first,false)
                             then 'opened on first occurrence of ' || v_key
                             else v_conseq || ' consecutive failures, threshold ' || v_thresh end,
             opened_class = v_key
       where model_id = v_model;
      v_state := 'opened_by_this';
    end if;
  end if;

  -- DERIVE THE MONEY HERE, from the same pricing source ai_cost_log uses, rather than trusting a
  -- caller to convert. A caller that computes its own AED is a second pricing implementation, and
  -- two of those drift. An explicit cost_aed in the payload still wins, so a provider that reports
  -- its own charge can be recorded verbatim.
  --
  -- Deliberately only when tokens are present: a failed attempt that produced no usage block has
  -- no measurable cost, and inventing 0 there would make "this retry was free" indistinguishable
  -- from "nobody recorded what this retry cost".
  if v_cost is null and (v_in is not null or v_out is not null) then
    begin
      v_cost := public.fn_model_cost_usd(v_model, coalesce(v_in,0), coalesce(v_out,0), v_cached)
                * public.fn_usd_to_aed();
    exception when others then v_cost := null;   -- pricing is reporting, never a gate
    end;
  end if;

  insert into llm_attempt (request_id, attempt_no, fn, agent_key, task_class, model_route, tier,
                           ok, class_key, http_status, finish_reason, err_excerpt,
                           evidence_truncated, latency_ms, prompt_tokens, output_tokens, cost_aed,
                           breaker_state)
  values (v_req, v_no, p->>'fn', p->>'agent_key', p->>'task_class', v_model, p->>'tier',
          v_ok, v_key, nullif(p->>'http_status','')::integer, p->>'finish_reason',
          left(coalesce(p->>'err_excerpt',''), 4000),
          coalesce((v_cls->>'evidence_truncated')::boolean, false),
          nullif(p->>'latency_ms','')::integer, v_in, v_out, v_cost,
          v_state)
  returning attempt_id into v_id;

  return jsonb_build_object(
    'attempt_id', v_id, 'request_id', v_req, 'attempt_no', v_no,
    'class_key', v_key, 'breaker', v_state,
    'cost_aed', v_cost,
    'retry_allowed', case when v_ok then false
                          when v_state = 'opened_by_this' then false   -- fail closed, do not retry into a wall
                          else fn_llm_retry_allowed(v_key, v_no) end,
    'retry_backoff_ms', coalesce((v_cls->>'retry_backoff_ms')::integer, 0),
    'evidence_truncated', coalesce((v_cls->>'evidence_truncated')::boolean, false));
end $function$;
