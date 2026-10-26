-- V3 REMEDIATION — STAGE 10: INFRASTRUCTURE RELIABILITY
-- =============================================================================================
-- WHAT THE CERTIFICATION SAW: 123 of 2,284 first responses failed, HTTP 502, deterministic per
-- model route rather than per moment, and the 502 body carried a valid upstream chat.completion.
--
-- WHAT THE STAGING LEDGER ACTUALLY SHOWS (all figures measured on pglpqrhvozwepymcuunn before
-- this file was written; the queries are named beside each number so they can be re-run):
--
--   ai_cost_log            3,753 rows, 228 with ok = false, 2026-08-05 .. 2026-08-14.
--   qwen/qwen3.7-plus      152 calls, 152 failures. 100%. It has never once succeeded.
--   anthropic/claude-sonnet-5  575 calls, 76 failures (13.22%).
--   every other route      ~anthropic/claude-haiku-latest 2,099/0 fail, gemini-3.1-flash-lite
--                          431/0, gemini-3.5-flash 386/0. The failure is two routes, not weather.
--
--   On EVERY one of the 228 failed rows: prompt_tokens = 0, output_tokens = 0, cost_aed = 0.
--   The provider generated and billed those tokens. The ledger books them at zero.
--
--   222 of the 228 carry a reason in model_selected_because (the six that do not are from
--   2026-08-10, before ai_gateway started writing it). Of those 222:
--       220  begin '{"id":"gen-...","object":"chat.completion"' — a WELL-FORMED completion body,
--            no "error" key anywhere, no 429, no rate-limit text. The upstream answered.
--         2  read 'The signal has been aborted' — that is OUR AbortController, our own stopwatch,
--            not a provider failure.
--   So the dominant class is NOT provider failure. It is: upstream returned 200 with a valid
--   chat.completion and ai_gateway read no content out of it, then reported 502.
--
--   WHAT I COULD NOT DETERMINE, AND WHY. ai_gateway line 533 does
--   `lastErr = JSON.stringify(j?.error || j).slice(0, 200)`. max(length) of every stored reason
--   is exactly 200. The slice ends before `choices` appears, so finish_reason, message.content
--   and message.reasoning are absent from all 222 rows. Whether the content was empty, was
--   reasoning-only, or sat in a field the gateway does not read is NOT KNOWABLE from the
--   database. That is why `empty_completion` below is named for what was observed and not for a
--   cause, and why fn_classify_llm_failure reports evidence_truncated instead of guessing.
--
-- THE ROUTE THAT PRODUCED IT. model_policy_by_identity, not model_policy:
--       identity 'followup'  primary qwen/qwen3.7-plus  fallback deepseek/deepseek-v4-flash
--       identity 'marketing' primary qwen/qwen3.7-plus  fallback deepseek/deepseek-v4-flash
--   which is exactly the certification's top two agents (followup 44, marketing 32 of 123).
--   deepseek/deepseek-v4-flash does not exist in model_registry. Neither does
--   anthropic/claude-opus-5, qwen/qwen3.7-flash, google/gemini-3.5-flash-lite,
--   google/gemini-3.6-flash, anthropic/claude-sonnet-5:batch. Counted:
--       model_policy                          44 primary refs,   0 dangling
--       model_policy_by_identity.primary     118 refs,          72 dangling
--       model_policy_by_identity.fallback    120 refs,         106 dangling  (88%)
--       model_policy_by_identity.escalation  120 refs,          48 dangling
--   106 of 120 identities have a FALLBACK that is not a registered model. The ladder was a wall.
--
-- AND THE GUARD THAT SHOULD HAVE CAUGHT IT IS GREEN. v_model_policy_offcatalog returns 0 rows
-- today — it joins model_policy to model_registry and never looks at model_policy_by_identity,
-- the table that did the routing. A sibling path that never got the lexicon.
--
-- FIRST-ATTEMPT PRESERVATION — THE HARD REQUIREMENT. ai_cost_log has no request id, no attempt
-- number and no parent call: 2,466 agent_train rows carry 2,465 distinct timestamps across 147
-- distinct (fn, agent, task_class, model) keys. First-attempt success rate is NOT COMPUTABLE
-- from the existing ledger, at all, for any historical row. This file does not pretend otherwise:
-- llm_attempt is an append-only ledger where the retry is a NEW row, and fn_reliability_report
-- reports legacy rows in their own column so the blind spot shrinks visibly instead of being
-- averaged away.
-- =============================================================================================

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. THE TAXONOMY. One row per class. 'unclassified' is a real bucket with a real count, not a
--    silent else-branch — a list with only an allow-list and a deny-list leaves a third answer
--    nobody selects.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.llm_failure_class (
  class_key        text primary key,
  layer            text not null
                     check (layer in ('provider','transport','contract','tool','retrieval',
                                      'database','orchestration','test_runner','unknown')),
  description      text not null,
  -- RETRY ELIGIBILITY. Deterministic, encoded once, read by every caller.
  retryable        boolean not null,
  max_retries      integer not null default 0 check (max_retries between 0 and 5),
  retry_backoff_ms integer not null default 0 check (retry_backoff_ms >= 0),
  -- CIRCUIT BREAKER inputs. A class that is deterministic per route (bad credential, unregistered
  -- model) opens the route on the FIRST occurrence; retrying those is retrying into a wall.
  trips_breaker    boolean not null default true,
  opens_on_first   boolean not null default false,
  operator_note    text
);
alter table public.llm_failure_class enable row level security;
comment on table public.llm_failure_class is
  'Failure taxonomy for model routes. Retry eligibility and breaker behaviour live here, not in edge-function code, so every caller answers the same way.';

insert into public.llm_failure_class
  (class_key, layer, description, retryable, max_retries, retry_backoff_ms, trips_breaker, opens_on_first, operator_note) values
 ('rate_limited','provider',
  'Provider refused for quota or throughput: HTTP 429, or an error body naming rate limit / quota / capacity.',
  true, 3, 2000, true, false,
  'Retryable but breaker-counted: a route that is 429 for minutes should stop being asked.'),
 ('timeout','transport',
  'No answer inside the deadline. Includes OUR OWN AbortController firing ("The signal has been aborted") and the gateway wall deadline — read latency_ms before calling this a provider fault.',
  true, 1, 500, true, false,
  '2 of 222 measured staging failures were this, both our own abort, not the provider.'),
 ('provider_error','provider',
  'Upstream returned an error OBJECT or a 5xx: the body has an "error" key or the status is 500-599 with no completion payload.',
  true, 2, 1000, true, false,
  'Measured 0 of 222 staging failures. Do not assume a 502 from ai_gateway means this class.'),
 ('empty_completion','contract',
  'Upstream returned a well-formed chat.completion and the gateway read no content and no tool_calls from it. Observed, not diagnosed: the stored evidence is truncated at 200 chars before choices.',
  false, 0, 0, true, false,
  'THE BIGGEST BUCKET: 220 of 222 measured staging failures. Retrying it produced 0 successes; it is deterministic per route.'),
 ('malformed_output','contract',
  'A reply arrived but does not satisfy the output contract: finish_reason = length, or JSON that does not parse.',
  false, 0, 0, false, false,
  'Not retryable — the same prompt and the same token ceiling produce the same truncation. Raise max_tokens in model_policy instead.'),
 ('unauthorised','provider',
  'HTTP 401/403, missing or rejected credential.',
  false, 0, 0, true, true,
  'Opens the route immediately. A bad key does not become a good key on attempt two.'),
 ('route_not_registered','orchestration',
  'The model id the policy asked for is absent from model_registry, or present and not active.',
  false, 0, 0, true, true,
  'Preflight catches this before any provider call. 106 of 120 identity fallbacks are in this state today.'),
 ('tool_failure','tool',
  'The model asked for a tool and the tool call itself failed or returned no result.',
  true, 1, 500, false, false,
  'Distinct from empty_completion: here the completion was fine and the tool underneath was not.'),
 ('retrieval_failure','retrieval',
  'Context assembly failed: embedding, kb_match or context slice errored or returned nothing usable.',
  true, 1, 500, false, false,
  null),
 ('database_failure','database',
  'A Postgres error on the logging or routing path: undefined relation/function, deadlock, connection loss.',
  true, 2, 1000, false, false,
  null),
 ('orchestration_failure','orchestration',
  'The call never reached a provider: no route resolved, policy row missing, ladder empty, budget guard refused.',
  false, 0, 0, false, false,
  null),
 ('test_runner_failure','test_runner',
  'The harness around the call failed — fixture, seeding or assertion plumbing — not the runtime under test.',
  false, 0, 0, false, false,
  'Kept separate so a broken harness can never be reported as an unreliable runtime.'),
 ('unclassified','unknown',
  'No rule matched. MUST TREND TO ZERO. Every row here is a missing rule, and it is counted in fn_reliability_report on purpose.',
  false, 0, 0, false, false,
  'If this bucket grows, add a rule to fn_classify_llm_failure. Never widen an existing rule to swallow it.')
on conflict (class_key) do update set
  layer = excluded.layer, description = excluded.description, retryable = excluded.retryable,
  max_retries = excluded.max_retries, retry_backoff_ms = excluded.retry_backoff_ms,
  trips_breaker = excluded.trips_breaker, opens_on_first = excluded.opens_on_first,
  operator_note = excluded.operator_note;

-- ---------------------------------------------------------------------------------------------
-- 2. THE CLASSIFIER. Exactly one class out, first rule wins, order is load-bearing.
--    The 502-with-a-valid-body case MUST NOT fall into provider_error, so the provider_error rule
--    demands an actual error object and the completion-shape rule sits below it.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_classify_llm_failure(
  p_err           text,
  p_http_status   integer default null,
  p_finish_reason text    default null,
  p_model         text    default null,
  p_latency_ms    integer default null
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  e text := coalesce(p_err, '');
  k text;
  truncated boolean;
begin
  -- ai_gateway slices lastErr to exactly 200 chars. At 200 the evidence stops before `choices`,
  -- so anything read past that point would be a guess. Say so rather than infer.
  truncated := length(e) >= 200;

  k := case
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
end $$;
revoke all on function public.fn_classify_llm_failure(text,integer,text,text,integer) from public;
grant execute on function public.fn_classify_llm_failure(text,integer,text,text,integer) to service_role;
comment on function public.fn_classify_llm_failure(text,integer,text,text,integer) is
  'Maps one observed failure to exactly one class. Order matters: unauthorised > rate_limited > timeout > route_not_registered > provider_error > empty_completion > malformed_output > ... > unclassified.';

-- ---------------------------------------------------------------------------------------------
-- 3. ROUTE HEALTH + CIRCUIT BREAKER. State per model route, so a route that is failing stops
--    being called instead of being retried into a wall 152 times.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.llm_route_health (
  model_id             text primary key,
  consecutive_failures integer not null default 0 check (consecutive_failures >= 0),
  failure_threshold    integer not null default 5 check (failure_threshold >= 1),
  cooldown_seconds     integer not null default 900 check (cooldown_seconds >= 30),
  open_until           timestamptz,
  opened_reason        text,
  opened_class         text references public.llm_failure_class(class_key),
  last_ok_at           timestamptz,
  last_failure_at      timestamptz,
  total_attempts       bigint not null default 0,
  total_ok             bigint not null default 0,
  updated_at           timestamptz not null default now()
);
alter table public.llm_route_health enable row level security;
comment on table public.llm_route_health is
  'Circuit state per model route. open_until in the future = the route is open and calls fail closed.';

-- PREFLIGHT. Answers before the money is spent. Two gates: the route must be a registered active
-- model, and its breaker must not be open.
create or replace function public.fn_llm_preflight(p_model text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case
    when p_model is null or p_model in ('none','none/deterministic')
      then jsonb_build_object('allowed', true, 'reason', 'deterministic path, no provider call')
    when not exists (select 1 from model_registry r where r.model_id = p_model and r.active)
      then jsonb_build_object('allowed', false, 'class_key', 'route_not_registered',
             'reason', 'model ' || p_model || ' is not an active row in model_registry')
    when exists (select 1 from llm_route_health h
                 where h.model_id = p_model and h.open_until is not null and h.open_until > now())
      then jsonb_build_object('allowed', false, 'class_key', 'route_open',
             'reason', 'circuit open until '
                       || (select h.open_until from llm_route_health h where h.model_id = p_model)
                       || ' after ' || (select h.consecutive_failures from llm_route_health h where h.model_id = p_model)
                       || ' consecutive failures (' || coalesce((select h.opened_class from llm_route_health h where h.model_id = p_model),'?') || ')',
             'open_until', (select h.open_until from llm_route_health h where h.model_id = p_model))
    else jsonb_build_object('allowed', true, 'reason', 'registered, breaker closed')
  end;
$$;
revoke all on function public.fn_llm_preflight(text) from public;
grant execute on function public.fn_llm_preflight(text) to service_role;
comment on function public.fn_llm_preflight(text) is
  'Call BEFORE the provider call. allowed=false means fail closed and pick the next rung, not retry this one.';

-- RETRY ELIGIBILITY, single source of truth. A caller asks; it does not decide.
create or replace function public.fn_llm_retry_allowed(p_class_key text, p_attempt_no integer)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select c.retryable and p_attempt_no <= c.max_retries
       from llm_failure_class c where c.class_key = p_class_key),
    false);   -- unknown class is NOT retryable: an unnamed failure never earns another attempt
$$;
revoke all on function public.fn_llm_retry_allowed(text,integer) from public;
grant execute on function public.fn_llm_retry_allowed(text,integer) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 4. FIRST-ATTEMPT PRESERVATION. An append-only attempt ledger. A retry is a NEW ROW with a
--    server-assigned attempt_no; it can neither overwrite nor renumber attempt 1. There is no
--    UPDATE path at all, so no future caller can quietly turn a failed first attempt into a
--    success by "recording the final outcome".
-- ---------------------------------------------------------------------------------------------
create table if not exists public.llm_attempt (
  attempt_id     uuid primary key default gen_random_uuid(),
  request_id     uuid        not null,     -- one logical question; retries share it
  attempt_no     integer     not null check (attempt_no >= 1),
  created_at     timestamptz not null default now(),
  fn             text,
  agent_key      text,
  task_class     text,
  model_route    text        not null,     -- the model ACTUALLY attempted, not the ladder head
  tier           text,
  ok             boolean     not null,
  class_key      text references public.llm_failure_class(class_key),
  http_status    integer,
  finish_reason  text,
  err_excerpt    text,
  evidence_truncated boolean not null default false,
  latency_ms     integer,
  prompt_tokens  integer,
  output_tokens  integer,
  cost_aed       numeric,
  breaker_state  text,                     -- 'closed' | 'opened_by_this' | 'preflight_refused'
  constraint llm_attempt_one_row_per_attempt unique (request_id, attempt_no),
  -- a failed attempt must say why; a successful one must not claim a failure class
  constraint llm_attempt_class_matches_ok check ((ok and class_key is null) or (not ok and class_key is not null))
);
create index if not exists llm_attempt_route_idx on public.llm_attempt (model_route, created_at desc);
create index if not exists llm_attempt_agent_idx on public.llm_attempt (agent_key, created_at desc);
create index if not exists llm_attempt_first_idx on public.llm_attempt (created_at desc) where attempt_no = 1;
alter table public.llm_attempt enable row level security;
comment on table public.llm_attempt is
  'Append-only. Retry = new row, same request_id, attempt_no+1. First-attempt success rate is always recoverable because attempt 1 is never rewritten.';
comment on column public.llm_attempt.model_route is
  'The model actually attempted. ai_cost_log records only the ladder HEAD on a total failure, which is why its 152 qwen rows cannot tell you whether the deepseek fallback was even reached.';

-- a00_ prefix: BEFORE triggers fire in name order and this one must win.
create or replace function public.a00_llm_attempt_immutable()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception
    'llm_attempt is append-only (attempted % on attempt_id %). A retry inserts a new row with the next attempt_no; it never rewrites an earlier attempt, because first-attempt success rate must stay computable.',
    tg_op, coalesce(old.attempt_id::text,'?')
    using errcode = 'restrict_violation';
end $$;
drop trigger if exists a00_llm_attempt_immutable on public.llm_attempt;
create trigger a00_llm_attempt_immutable
  before update or delete on public.llm_attempt
  for each row execute function public.a00_llm_attempt_immutable();

-- THE WRITE PATH. Classifies, assigns attempt_no server-side, and moves the breaker in the same
-- transaction so health can never drift from the ledger it is derived from.
create or replace function public.fn_record_llm_attempt(p jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
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

  insert into llm_attempt (request_id, attempt_no, fn, agent_key, task_class, model_route, tier,
                           ok, class_key, http_status, finish_reason, err_excerpt,
                           evidence_truncated, latency_ms, prompt_tokens, output_tokens, cost_aed,
                           breaker_state)
  values (v_req, v_no, p->>'fn', p->>'agent_key', p->>'task_class', v_model, p->>'tier',
          v_ok, v_key, nullif(p->>'http_status','')::integer, p->>'finish_reason',
          left(coalesce(p->>'err_excerpt',''), 4000),
          coalesce((v_cls->>'evidence_truncated')::boolean, false),
          nullif(p->>'latency_ms','')::integer, nullif(p->>'prompt_tokens','')::integer,
          nullif(p->>'output_tokens','')::integer, nullif(p->>'cost_aed','')::numeric,
          v_state)
  returning attempt_id into v_id;

  return jsonb_build_object(
    'attempt_id', v_id, 'request_id', v_req, 'attempt_no', v_no,
    'class_key', v_key, 'breaker', v_state,
    'retry_allowed', case when v_ok then false
                          when v_state = 'opened_by_this' then false   -- fail closed, do not retry into a wall
                          else fn_llm_retry_allowed(v_key, v_no) end,
    'retry_backoff_ms', coalesce((v_cls->>'retry_backoff_ms')::integer, 0),
    'evidence_truncated', coalesce((v_cls->>'evidence_truncated')::boolean, false));
end $$;
revoke all on function public.fn_record_llm_attempt(jsonb) from public;
grant execute on function public.fn_record_llm_attempt(jsonb) to service_role;
comment on function public.fn_record_llm_attempt(jsonb) is
  'Records one attempt, classifies the failure, moves the breaker and returns whether a retry is eligible. attempt_no is server-assigned so a retry can never masquerade as the first attempt.';

-- ---------------------------------------------------------------------------------------------
-- 5. THE REPORT. Per model route AND per agent, grouped BY CLASS. Never in aggregate: a
--    662-ok/50-failed roll-up is exactly what hid a route here that had never succeeded once.
--
--    Legacy honesty: ai_cost_log rows carry no attempt number, so they are counted in their own
--    column and NEVER counted as first attempts. first_attempt_pct is NULL, not 100, when there
--    is nothing to measure — least()/greatest() ignore nulls and are not used anywhere here.
-- ---------------------------------------------------------------------------------------------
-- ROUTINE REMOVED 7 September 2026. public.fn_reliability_report was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke all on function public.fn_reliability_report(integer) from public;
grant execute on function public.fn_reliability_report(integer) to service_role;
comment on function public.fn_reliability_report(integer) is
  'Per model route and per agent: attempts, first_attempt_ok, eventual_ok, failures grouped by class. legacy_attempts_no_attempt_no counts ai_cost_log rows that predate the attempt ledger and therefore cannot contribute a first-attempt figure - that column shrinking to zero is the migration finishing.';

-- ---------------------------------------------------------------------------------------------
-- 6. MONITORS. Absence checks, so these regressions are visible without anyone running a report.
-- ---------------------------------------------------------------------------------------------

-- 6a. The group-per-class monitor: a route with traffic and zero successes. Today this is
--     qwen/qwen3.7-plus at 152/0 - invisible in any aggregate that mixes it with haiku's 2,099/0-fail.
create or replace view public.v_llm_route_never_succeeded as
  select model_used as model_route,
         count(*) as calls, count(*) filter (where ok) as ok_calls,
         min(occurred_at) as first_seen, max(occurred_at) as last_seen,
         (select h.open_until from llm_route_health h where h.model_id = c.model_used) as open_until
    from ai_cost_log c
   where model_used is not null and model_used <> 'none'
   group by model_used
  having count(*) filter (where ok) = 0 and count(*) > 0;
comment on view public.v_llm_route_never_succeeded is
  'A route that has been called and has never once answered. Aggregate success rate cannot show this.';

-- 6b. THE GUARD THAT WAS POINTED AT THE WRONG TABLE. v_model_policy_offcatalog checks
--     model_policy against model_registry and returns 0 rows. The routing that produced the
--     certification 502s lives in model_policy_by_identity, which it never reads.
create or replace view public.v_llm_identity_route_offcatalog as
  select i.identity_key, s.slot, s.model_id,
         (select count(*) from ai_cost_log l where l.model_used = s.model_id) as ledger_rows
    from model_policy_by_identity i
    cross join lateral (values ('primary', i.primary_model),
                               ('fallback', i.fallback_model),
                               ('escalation', i.escalation_model)) as s(slot, model_id)
   where s.model_id is not null
     and s.model_id not in ('none','none/deterministic')
     and not exists (select 1 from model_registry r where r.model_id = s.model_id and r.active);
comment on view public.v_llm_identity_route_offcatalog is
  'Identity routes naming a model that is not an active model_registry row. Measured 2026-08-14 before this file: 72 primary, 106 fallback, 48 escalation - and v_model_policy_offcatalog reported 0 because it only reads model_policy.';

-- 6c. The unclassified bucket, which must trend to zero.
create or replace view public.v_llm_unclassified_failures as
  select date_trunc('day', created_at)::date as day, model_route,
         count(*) as unclassified
    from llm_attempt
   where not ok and class_key = 'unclassified'
   group by 1, 2;
comment on view public.v_llm_unclassified_failures is
  'Every row here is a missing rule in fn_classify_llm_failure. Add a rule; never widen an existing one to absorb it.';

commit;
