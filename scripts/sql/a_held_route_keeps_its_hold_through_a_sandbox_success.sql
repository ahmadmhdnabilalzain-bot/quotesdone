-- A HELD ROUTE KEEPS ITS HOLD THROUGH A SANDBOX SUCCESS (6 Oct 2026; Assigned: it_engineer).
--
-- MEASURED 6 Oct 2026 20:20 UTC: two successful stage-2 sandbox calls to openai/gpt-6-luna at 20:07 UTC set
-- llm_route_health.open_until to NULL on that route. fn_record_llm_attempt's success branch closed the breaker with
-- no test for the founder's hold (open_until 2126-08-15). A rehearsal is allowed THROUGH a held route by
-- fn_kernel_paid_provider_gate (a_sandbox_run_is_tagged_capped_and_let_through_only_inside_its_window.sql, step 5,
-- "a sandbox run passes the hold; it does not lift it") -- this routine then lifted it. The release operator restored
-- the row by hand (open_until = the fleet's max, opened_reason 'held with the rest of the fleet'), and
-- every_model_class_is_on_the_founders_matrix went green again.
--
-- THE RULE, the same date test the gate uses: an open_until more than 365 days out is the HOLD, not a breaker.
--   success  -> counters reset; a breaker (open_until <= now() + 365 days) is closed, a hold is left exactly as it is;
--   failure  -> counted as before; tripping the breaker never overwrites a hold with a shorter cooldown.
-- Lifting the hold stays the founder's own act (update llm_route_health set open_until = null), never a side effect.
--
-- CREATE OR REPLACE of the canonical body (org_align_08_attempt_level_cost.sql); the signature is unchanged, so the
-- ACL is preserved and no revoke is needed. Everything else in the body is identical.
create or replace function public.fn_record_llm_attempt(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
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
       set consecutive_failures = 0,
           -- the founder's hold (more than a year out) is never closed by a success; a breaker is
           open_until    = case when open_until > now() + interval '365 days' then open_until else null end,
           opened_reason = case when open_until > now() + interval '365 days' then opened_reason else null end,
           opened_class  = case when open_until > now() + interval '365 days' then opened_class else null end,
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
       where model_id = v_model
         and (open_until is null or open_until <= now() + interval '365 days');   -- never shorten a hold
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

-- probe (no DDL rolled back: a verdict row). The behavioural proof is ..._probe.sql (rolls back).
select case when position('interval ''365 days'' then open_until else null' in pg_get_functiondef('public.fn_record_llm_attempt(jsonb)'::regprocedure)) > 0
             and position('never shorten a hold' in pg_get_functiondef('public.fn_record_llm_attempt(jsonb)'::regprocedure)) > 0
            then 'PROBE OK' else 'PROBE FAILED: fn_record_llm_attempt still lifts a hold on success' end as verdict;
