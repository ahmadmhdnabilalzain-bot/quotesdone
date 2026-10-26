-- GITHUB AND SUPABASE DISAGREED ABOUT TWO ROUTINES. THE DATABASE WAS RIGHT BOTH TIMES.
--
-- Founder instruction, 15 Aug 2026: "supabase and github has to be identical 100%. anything that
-- doesnt match need to be rectified now before we start 3 phases i need."
--
-- scripts/checks/sql_files_match_live.test.mjs reported 2 routines drifted against a baseline of 0.
-- Both were checked for DIRECTION before anything was applied, because reconciling the wrong way
-- is how a fix becomes a regression.
--
-- 1. fn_classify_llm_failure — REAL DRIFT, and the live side is the one worth keeping.
--    Live carries a branch the repo has never had:
--
--      when p_http_status = 402
--        or e ~* '(requires more credits|insufficient[_ ]credit|can only afford|quota exceeded|payment required)'
--        then 'insufficient_credit'
--
--    It was applied straight to the database on 14 Aug and never written back. That is the rule
--    which stops the company RETRYING INTO AN OUT-OF-CREDIT WALL — measured the same day: 164 of
--    604 staging attempts failed on credit, and without this class each one is retried. Applying
--    the old file would have deleted it and made the billing problem worse, on the same day the
--    founder asked why his credit was draining.
--
-- 2. fn_category_specialist_scorecard — NOT DRIFT AT ALL. Live is byte-identical to
--    org_reorg_08_findings.sql. Two files define this routine and both landed in the same commit;
--    the check ranks files by their first LINE in `git log --name-only`, so 05 was listed first,
--    was called "the newest file", and the routine was compared against a definition it was never
--    meant to match. The database was right and the instrument was wrong — the exact defect this
--    check exists to catch, pointed at itself.
--
--    Ranking per COMMIT instead of per LINE was tried and made things worse, not better: it fixed
--    this false positive and created two new ones (fn_delete_proposer,
--    zzz_fn_notifications_demo_guard), because within one commit there is no reliable way to infer
--    apply order from a filename. Reverted. The real answer is one routine, one file — and this
--    file provides it by being the newest definition of both.
--
-- WHY A NEW FILE AND NOT AN EDIT. scripts/sql is APPEND-ONLY, as its own check documents: a file
-- is the record of a change that was applied, and is never edited afterwards. Editing
-- v3_repair_10_infra_reliability.sql to add the missing branch was the first attempt here and was
-- reverted for exactly that reason. Same precedent as the_files_were_stale_not_the_database.sql.
--
-- Both definitions below are captured VERBATIM from pg_get_functiondef on production, so applying
-- this file is a no-op against live and simply makes the newest file the true one.

-- ROUTINE REMOVED 7 September 2026. public.fn_category_specialist_scorecard was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


CREATE OR REPLACE FUNCTION public.fn_classify_llm_failure(p_err text, p_http_status integer DEFAULT NULL::integer, p_finish_reason text DEFAULT NULL::text, p_model text DEFAULT NULL::text, p_latency_ms integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  e text := coalesce(p_err, '');
  k text;
  truncated boolean;
begin
  -- ai_gateway slices lastErr to exactly 200 chars. At 200 the evidence stops before `choices`,
  -- so anything read past that point would be a guess. Say so rather than infer.
  truncated := length(e) >= 200;

  k := case
    -- BILLING FIRST (added 14 Aug 2026). Stable across every OpenRouter model, and not
    -- retryable: retrying an out-of-credit request cannot succeed and burns the wall budget.
    when p_http_status = 402
      or e ~* '(requires more credits|insufficient[_ ]credit|can only afford|quota exceeded|payment required)'
      then 'insufficient_credit'
    -- credentials first: deterministic, and must never be retried
    when p_http_status in (401, 403)
      or e ~* '(unauthor|forbidden|invalid api key|no auth credentials|api[_ ]?key missing)'
      then 'unauthorised'
    when p_http_status = 429
      or e ~* '(rate[ _-]?limit|too many requests|quota exceeded|insufficient (credits|quota)|capacity)'
      then 'rate_limited'
    -- our own stopwatch reads as a model failure unless it is named
    when e ~* '(signal has been aborted|aborterror|the operation was aborted|timed? ?out|etimedout|deadline|gateway_deadline)'
      then 'timeout'
    when e ~* '(not a valid model|model not found|no endpoints found|unknown model|no allowed providers)'
      then 'route_not_registered'
    when p_model is not null
      and not exists (select 1 from model_registry r where r.model_id = p_model and r.active)
      then 'route_not_registered'
    -- a REAL provider error object, or a 5xx with no payload
    when e ~ '"error"\s*:' or e ~* '^\s*\{"error"'
      or (p_http_status between 500 and 599 and e !~ '"object"\s*:\s*"chat\.completion"')
      then 'provider_error'
    -- the shape the certification actually hit
    when e ~ '"object"\s*:\s*"chat\.completion"' or e ~ '^\s*\{"id"\s*:\s*"gen-'
      then 'empty_completion'
    when lower(coalesce(p_finish_reason,'')) = 'length'
      or e ~* '(unexpected end of json|unparseable|invalid json|json parse|content_filter)'
      then 'malformed_output'
    when e ~* '(tool[_ ]call|tool result|tool failed|function call failed)'
      then 'tool_failure'
    when e ~* '(embedding|kb_match|retriev|context slice|no chunks)'
      then 'retrieval_failure'
    when e ~* '(pgrst|sqlstate|does not exist|deadlock detected|connection (reset|refused|closed)|relation .* does not exist)'
      then 'database_failure'
    when e ~* '(route_failed|no route|no model policy|budget|spend guard|ladder empty)'
      then 'orchestration_failure'
    when e ~* '(harness|fixture|test runner|seed(ing)? failed)'
      then 'test_runner_failure'
    else 'unclassified'
  end;

  return jsonb_build_object(
    'class_key', k,
    'retryable', (select retryable from llm_failure_class where class_key = k),
    'max_retries', (select max_retries from llm_failure_class where class_key = k),
    'retry_backoff_ms', (select retry_backoff_ms from llm_failure_class where class_key = k),
    'trips_breaker', (select trips_breaker from llm_failure_class where class_key = k),
    'opens_on_first', (select opens_on_first from llm_failure_class where class_key = k),
    -- honesty flag: the caller learns the evidence was cut off, so 'empty_completion' is never
    -- mistaken for a diagnosed root cause
    'evidence_truncated', truncated,
    'latency_ms', p_latency_ms
  );
end $function$;