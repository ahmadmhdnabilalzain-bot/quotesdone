-- A SANDBOX SUCCESS NEVER LIFTS THE MODEL HOLD.
-- Seat: it_engineer. Founder, 7 Oct 2026: "Stop a sandbox success lifting the model hold." The hold
-- (every llm_route_health row open_until 2126-08-15, read by fn_kernel_paid_provider_gate rule
-- founder_hold; app_secrets.no_paid_ai is the second, currently unset, switch) stays on until HE lifts it.
--
-- MEASURED 7 Oct 2026 (pg_proc prosrc, production): exactly one routine body writes llm_route_health,
-- fn_record_llm_attempt, which ai_gateway calls after every provider attempt. Two of its lines lifted
-- the hold for one route, for everybody, whatever caused the attempt:
--   - ok = true  -> set open_until = null, opened_reason = null   (a success "closed the breaker")
--   - a breaker-tripping failure -> set open_until = now() + cooldown (15 minutes replaced 2126)
-- Under the hold no attempt reaches a provider, so neither line has fired. The stage-2 sandbox
-- (#1230, rehearsal_window) lets TAGGED calls past the hold inside their window, so the first tagged
-- success would have un-held its route for real traffic. That is the bug this file closes.
--
-- What changes:
-- 1. fn_llm_route_founder_held(open_until): one definition of "held by the founder" -- open_until more
--    than a year out, the same reading fn_kernel_paid_provider_gate step 5 uses (the reason text has
--    two spellings; the date has one). A real breaker opens for cooldown_seconds (900).
-- 2. fn_record_llm_attempt: a success resets the counters and closes a REAL breaker; it leaves a
--    founder-held route's open_until, opened_reason and opened_class exactly as they were. A tripping
--    failure never overwrites a founder hold. Every other line is the deployed body, read back with
--    pg_get_functiondef on 7 Oct 2026.
-- 3. THE GUARD. trg_llm_route_health_founder_hold refuses, on any path, clearing or shortening a
--    founder-held open_until, or deleting such a row; trg_app_secrets_no_paid_ai_founder_switch refuses
--    turning no_paid_ai from on to off (or deleting it while on). Allowed only when the transaction
--    first says so:
--        set local app.change_reason = 'founder:<founder_instruction id>';   -- his release
--        set local app.change_reason = 'probe:<check name>';                 -- an aborted probe
--    The check scripts/checks/a_sandbox_success_never_lifts_the_model_hold.test.mjs asserts that a
--    'founder:' reason appears in no routine, script or workflow, and that every 'probe:' use sits in
--    a probe that raises CHK<<>> (rolls back). Setting the hold (lengthening it) is never refused.
--
-- NOT changed: the gate. A tagged call inside an open window still PASSES the hold (block 0 of
-- fn_kernel_paid_provider_gate); untagged traffic still meets it. A sandbox success may RECORD (ai_cost_log,
-- llm_attempt, the rehearsal_window row); it never changes llm_route_health's hold columns.

create or replace function public.fn_llm_route_founder_held(p_open_until timestamptz)
returns boolean language sql stable
set search_path to 'public', 'pg_temp'
as $fn$ select coalesce(p_open_until > now() + interval '1 year', false) $fn$;
revoke execute on function public.fn_llm_route_founder_held(timestamptz) from public, anon, authenticated;

create or replace function public.fn_founder_hold_change_allowed()
returns boolean language sql stable
set search_path to 'public', 'pg_temp'
as $fn$ select coalesce(current_setting('app.change_reason', true), '') ~ '^(founder:[0-9]+|probe:[a-z0-9_]+)' $fn$;
revoke execute on function public.fn_founder_hold_change_allowed() from public, anon, authenticated;

create or replace function public.fn_llm_route_health_founder_hold_guard()
returns trigger language plpgsql
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if public.fn_llm_route_founder_held(old.open_until)
     and (tg_op = 'DELETE' or new.open_until is null or new.open_until < old.open_until)
     and not public.fn_founder_hold_change_allowed() then
    raise exception 'FOUNDER_HOLD: route % is held by the founder until %; only he lifts it. Release with set local app.change_reason = ''founder:<ledger id>'' in the same transaction.',
      old.model_id, old.open_until using errcode = 'P0001';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $fn$;
revoke execute on function public.fn_llm_route_health_founder_hold_guard() from public, anon, authenticated;

drop trigger if exists trg_llm_route_health_founder_hold on public.llm_route_health;
create trigger trg_llm_route_health_founder_hold before update or delete on public.llm_route_health
  for each row execute function public.fn_llm_route_health_founder_hold_guard();

create or replace function public.fn_app_secrets_no_paid_ai_guard()
returns trigger language plpgsql
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if old.key = 'no_paid_ai' and lower(coalesce(old.value, '')) in ('1','true','yes','on')
     and (tg_op = 'DELETE' or new.key <> 'no_paid_ai' or lower(coalesce(new.value, '')) not in ('1','true','yes','on'))
     and not public.fn_founder_hold_change_allowed() then
    raise exception 'FOUNDER_HOLD: app_secrets.no_paid_ai is on; only the founder turns it off (set local app.change_reason = ''founder:<ledger id>'').'
      using errcode = 'P0001';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $fn$;
revoke execute on function public.fn_app_secrets_no_paid_ai_guard() from public, anon, authenticated;

drop trigger if exists trg_app_secrets_no_paid_ai_founder_switch on public.app_secrets;
create trigger trg_app_secrets_no_paid_ai_founder_switch before update or delete on public.app_secrets
  for each row execute function public.fn_app_secrets_no_paid_ai_guard();

CREATE OR REPLACE FUNCTION public.fn_record_llm_attempt(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
       -- A SUCCESS CLOSES A BREAKER, NEVER THE FOUNDER'S HOLD (7 Oct 2026). A sandbox call passes the hold
       -- inside its window; its success used to null open_until here and lift the hold for everyone.
       set consecutive_failures = 0,
           open_until    = case when public.fn_llm_route_founder_held(open_until) then open_until end,
           opened_reason = case when public.fn_llm_route_founder_held(open_until) then opened_reason end,
           opened_class  = case when public.fn_llm_route_founder_held(open_until) then opened_class end,
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
         and not public.fn_llm_route_founder_held(open_until);   -- a 15-minute breaker never replaces a 2126 hold
      if found then v_state := 'opened_by_this'; end if;
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

