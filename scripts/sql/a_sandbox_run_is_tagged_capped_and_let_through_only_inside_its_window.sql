-- A SANDBOX RUN IS TAGGED, CAPPED, AND LET THROUGH THE HOLD ONLY INSIDE ITS OWN WINDOW.
-- Seat: it_engineer. Ledger 1119 (stage-2 sandbox e2e, scripts/e2e/stage2.mjs); review of PR #1230.
--
-- Measured 6 Oct 2026. ai_cost_log had no run column, the stage-2 spend cap lived only in the script
-- and was checked only between scenarios, and the founder's hold (llm_route_health.open_until = 2126,
-- opened_reason 'HELD BY THE FOUNDER ...') could only be lifted for everybody. Three changes:
--
-- 1. ai_cost_log.e2e_run_tag. trg_ai_cost_log_e2e_run_tag stamps it from app.e2e_run_tag (the aborted
--    duty probes) or the x-qd-e2e-run request header (the harness sends it, and _shared/observe.ts
--    forwards it on every call an edge function makes back to this project). The tag is kept only for
--    an open, unexpired, model-enabled rehearsal_window, so a caller cannot mark rows for the cleanup.
--
-- 2. rehearsal_window gains models_allowed, cap_usd (default USD 4) and expires_at. A CHECK bounds
--    the window at two hours, so a harness that crashes cannot leave one open any longer than that.
--    The harness closes it in a finally block as well (scripts/e2e/stage2.mjs).
--
-- 3. fn_kernel_paid_provider_gate learns one thing: a TAGGED call. It is decided before the hold.
--    - No open, unexpired window for the tag with models_allowed: DENIED (rehearsal_window_closed).
--    - Tagged spend on ai_cost_log for that tag at or over the window's cap_usd: DENIED (rehearsal_cap).
--    - Otherwise it passes the founder's hold (and a route held by it), and NOTHING ELSE:
--      the no_paid_ai switch, empty route state, the registry, and a real breaker still apply.
--    UNTAGGED TRAFFIC TAKES EXACTLY THE PATH IT TOOK BEFORE. The cap is the test's cap only. The founder
--    has ruled there is no cap on production spend (ledger 1134), and none is added here. Lifting the
--    hold for real traffic stays his decision (update llm_route_health set open_until = null).
--
-- The gate body below is the deployed definition (a_paid_model_call_needs_an_approved_provider.sql,
-- read back with pg_get_functiondef on 6 Oct 2026) with the tagged block added. Every other line is
-- unchanged. This file is now the canonical definition, as the last MANIFEST entry for the routine.

alter table public.ai_cost_log add column if not exists e2e_run_tag text;
comment on column public.ai_cost_log.e2e_run_tag is
  'Run tag of the sandbox harness run that caused this model call (scripts/e2e/stage2.mjs). Null for all real traffic. Set by trg_ai_cost_log_e2e_run_tag; the cap and the cleanup read it.';
create index if not exists ai_cost_log_e2e_run_tag_idx on public.ai_cost_log (e2e_run_tag) where e2e_run_tag is not null;

alter table public.rehearsal_window
  add column if not exists models_allowed boolean not null default false,
  add column if not exists cap_usd numeric not null default 4,
  add column if not exists expires_at timestamptz not null default (now() + interval '2 hours');
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'rehearsal_window_at_most_two_hours') then
    alter table public.rehearsal_window add constraint rehearsal_window_at_most_two_hours
      check (expires_at <= started_at + interval '2 hours 1 minute') not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rehearsal_window_cap_is_small') then
    alter table public.rehearsal_window add constraint rehearsal_window_cap_is_small
      check (cap_usd > 0 and cap_usd <= 15) not valid;
  end if;
end $c$;

-- The open, unexpired, model-enabled window a tag names, or null. One place, so the trigger and the
-- gate cannot disagree about what "open" means.
create or replace function public.fn_e2e_run_tag_open(p_tag text)
returns boolean language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select p_tag ~ '^[a-z0-9]{4,16}$' and exists (
    select 1 from public.rehearsal_window w
     where w.run_tag = 'qd_run:' || p_tag and w.ended_at is null and w.models_allowed and w.expires_at > now())
$fn$;
revoke execute on function public.fn_e2e_run_tag_open(text) from public, anon, authenticated;

-- The tag the current statement carries, or null. Never throws.
-- THE HEADER COUNTS ONLY FOR A SERVICE-ROLE REQUEST (review of #1230). Eight hex characters are a name,
-- not a credential, so a public (anon or signed-in) caller that sends x-qd-e2e-run straight to PostgREST
-- gets null here, and with it the normal hold. Edge functions reach PostgREST with the service-role
-- key, and only after _shared/e2e_run.ts has checked the request's own proof. app.e2e_run_tag can be
-- set only by a session that already holds SQL access (the aborted duty probes).
create or replace function public.fn_e2e_run_tag_current()
returns text language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  return coalesce(nullif(current_setting('app.e2e_run_tag', true), ''),
                  case when nullif(current_setting('request.jwt.claims', true), '')::json ->> 'role' = 'service_role'
                       then nullif(nullif(current_setting('request.headers', true), '')::json ->> 'x-qd-e2e-run', '') end);
exception when others then
  return null;
end $fn$;
revoke execute on function public.fn_e2e_run_tag_current() from public, anon, authenticated;

create or replace function public.fn_ai_cost_log_e2e_run_tag()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_tag text;
begin
  v_tag := coalesce(new.e2e_run_tag, public.fn_e2e_run_tag_current());
  if v_tag is not null and not coalesce(public.fn_e2e_run_tag_open(v_tag), false) then v_tag := null; end if;
  new.e2e_run_tag := v_tag;
  return new;
exception when others then
  new.e2e_run_tag := null;   -- the cost record is never lost to a malformed header
  return new;
end $fn$;
revoke execute on function public.fn_ai_cost_log_e2e_run_tag() from public, anon, authenticated;

drop trigger if exists trg_ai_cost_log_e2e_run_tag on public.ai_cost_log;
create trigger trg_ai_cost_log_e2e_run_tag before insert on public.ai_cost_log
  for each row execute function public.fn_ai_cost_log_e2e_run_tag();

CREATE OR REPLACE FUNCTION public.fn_kernel_paid_provider_gate(p_model text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_switch  boolean;
  v_routes  bigint;
  v_held    bigint;
  v_model   text := nullif(btrim(coalesce(p_model, '')), '');
  v_reg     boolean;
  v_open    timestamptz;
  v_tag     text;
  v_cap     numeric;
  v_spent   numeric;
  v_rehearsal boolean := false;
begin
  -- An EMPTY STRING is not a deterministic path, it is a caller that did not say. Denied, with its
  -- own rule name, because "I passed you nothing" and "I am not calling a provider" are different
  -- statements and a gate that conflates them has a hole shaped like a typo.
  if p_model is not null and v_model is null then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'model_unspecified',
      'reason', 'an empty model string is not a deterministic path; pass NULL or ''none'' to declare '
             || 'that no provider call is being made', 'model', p_model);
  end if;

  -- A deterministic path is not a provider call and never was. It is named explicitly rather than
  -- reached by falling off the end of the checks.
  if v_model is null or v_model in ('none', 'none/deterministic') then
    return jsonb_build_object('allowed', true, 'gate', 'kernel_k12',
      'rule', 'deterministic_path', 'reason', 'no provider call is being made', 'model', p_model);
  end if;

  -- 0. A SANDBOX RUN'S CALL (ledger 1119). Untagged traffic skips this block entirely.
  v_tag := public.fn_e2e_run_tag_current();
  if v_tag is not null then
    if not coalesce(public.fn_e2e_run_tag_open(v_tag), false) then
      return jsonb_build_object('allowed', false, 'gate', 'kernel_k12', 'rule', 'rehearsal_window_closed',
        'reason', 'the call carries sandbox run tag ' || left(v_tag, 16) || ' but no open, unexpired, model-enabled rehearsal window names it',
        'model', v_model);
    end if;
    select w.cap_usd into v_cap from public.rehearsal_window w
     where w.run_tag = 'qd_run:' || v_tag and w.ended_at is null order by w.started_at desc limit 1;
    select coalesce(sum(cost_aed), 0) / 3.6725 into v_spent from public.ai_cost_log where e2e_run_tag = v_tag;
    if v_spent >= v_cap then
      return jsonb_build_object('allowed', false, 'gate', 'kernel_k12', 'rule', 'rehearsal_cap',
        'reason', 'sandbox run ' || v_tag || ' has spent USD ' || round(v_spent, 4) || ' of its USD ' || v_cap || ' cap',
        'model', v_model);
    end if;
    v_rehearsal := true;
  end if;

  -- 1. the explicit switch
  select exists (select 1 from public.app_secrets
                  where key = 'no_paid_ai' and lower(coalesce(value,'')) in ('1','true','yes','on'))
    into v_switch;
  if v_switch then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'no_paid_ai_switch', 'reason', 'app_secrets.no_paid_ai is set; paid inference is off',
      'model', v_model);
  end if;

  -- 2. empty route state is DENIED, not permitted. An absent hold is not a permission — this is the
  --    "what does it print when its input is absent?" case, answered on purpose.
  select count(*) into v_routes from public.llm_route_health;
  if v_routes = 0 then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'empty_route_state',
      'reason', 'llm_route_health holds no rows; with no route state there is no evidence that any '
             || 'route is permitted', 'model', v_model);
  end if;

  -- 3. the founder's hold, on ANY route. He held the whole estate on 15 Aug 2026; holding one route
  --    and leaving the others open would not be what he asked for. A sandbox run inside its open
  --    window passes the hold; it does not lift it.
  select count(*) into v_held from public.llm_route_health where open_until is not null and open_until > now();
  if v_held > 0 and not v_rehearsal then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'founder_hold',
      'reason', v_held || ' of ' || v_routes || ' routes are held open-circuit until '
             || (select max(open_until)::text from public.llm_route_health where open_until > now()),
      'held', v_held, 'routes', v_routes, 'model', v_model);
  end if;

  -- 4. the route must be registered and active
  select exists (select 1 from public.model_registry r where r.model_id = v_model and r.active) into v_reg;
  if not v_reg then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'route_not_registered',
      'reason', 'model ' || v_model || ' is not an active row in model_registry', 'model', v_model);
  end if;

  -- 5. this route's own breaker. For a sandbox run, a route held by the hold is not a breaker. Measured
  --    6 Oct 2026: every route is held to 2126-08-15, with opened_reason either 'HELD BY THE FOUNDER' or
  --    'held with the rest of the fleet'. A real breaker opens for cooldown_seconds (900). So 'held' is
  --    read from the date (more than a year out), never from the reason text, which has two spellings.
  select open_until into v_open from public.llm_route_health where model_id = v_model;
  if v_open is not null and v_open > now()
     and not (v_rehearsal and v_open > now() + interval '365 days') then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'route_open', 'reason', 'circuit open until ' || v_open::text, 'model', v_model);
  end if;

  if v_rehearsal then
    return jsonb_build_object('allowed', true, 'gate', 'kernel_k12',
      'rule', 'rehearsal_window', 'reason', 'sandbox run ' || v_tag || ' inside its open window, USD '
             || round(v_spent, 4) || ' of ' || v_cap || ' spent; the founder''s hold stays on for all other traffic',
      'model', v_model);
  end if;
  return jsonb_build_object('allowed', true, 'gate', 'kernel_k12',
    'rule', 'registered_breaker_closed', 'reason', 'switch off, no hold, route registered, breaker closed',
    'model', v_model);
exception
  -- The gate itself failing is the most dangerous case, because it is the one a try/catch upstream
  -- used to swallow. It answers DENIED, in its own voice, rather than throwing into a caller that
  -- might interpret an exception as "carry on".
  when others then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'gate_unreadable',
      'reason', 'the paid-provider gate could not be evaluated: ' || sqlstate || ' ' || sqlerrm,
      'model', p_model);
end $function$;

-- PROBE (cleans up after itself, returns a verdict row; the file defines routines, so it never raises).
-- Untagged: the answer is exactly what it was. Tagged with no window: denied. Tagged with an open
-- window: past the hold. Over the cap: denied. Nothing is left behind.
do $p$ declare a jsonb; b jsonb; c jsonb; d jsonb; e jsonb; g jsonb; v_bad text := ''; begin
  a := public.fn_kernel_paid_provider_gate('anthropic/claude-opus-5.5');
  perform set_config('app.e2e_run_tag', 'zzprobe0001', true);
  b := public.fn_kernel_paid_provider_gate('anthropic/claude-opus-5.5');
  insert into public.rehearsal_window (run_tag, opened_by, note, models_allowed, cap_usd)
    values ('qd_run:zzprobe0001', 'probe', 'gate probe', true, 4);
  c := public.fn_kernel_paid_provider_gate('anthropic/claude-opus-5.5');
  -- the same open window, named only by a request HEADER: a public caller gets the hold, the service role does not
  perform set_config('app.e2e_run_tag', '', true);
  perform set_config('request.headers', '{"x-qd-e2e-run": "zzprobe0001"}', true);
  perform set_config('request.jwt.claims', '{"role": "anon"}', true);
  e := public.fn_kernel_paid_provider_gate('anthropic/claude-opus-5.5');
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  g := public.fn_kernel_paid_provider_gate('anthropic/claude-opus-5.5');
  perform set_config('request.headers', '', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('app.e2e_run_tag', 'zzprobe0001', true);
  update public.rehearsal_window set cap_usd = 0.000001 where run_tag = 'qd_run:zzprobe0001';
  insert into public.ai_cost_log (fn, task_class, model_used, prompt_tokens, output_tokens, cost_aed, ok, e2e_run_tag)
    values ('gate_probe', 'health_ping', 'openai/gpt-6-luna', 1, 1, 0.01, true, 'zzprobe0001');
  d := public.fn_kernel_paid_provider_gate('anthropic/claude-opus-5.5');
  delete from public.ai_cost_log where e2e_run_tag = 'zzprobe0001';
  delete from public.rehearsal_window where run_tag = 'qd_run:zzprobe0001';
  perform set_config('app.e2e_run_tag', '', true);
  if b->>'rule' <> 'rehearsal_window_closed' then v_bad := v_bad || ' no-window=' || (b->>'rule'); end if;
  if (c->>'allowed')::boolean is not true and (a->>'rule') = 'founder_hold' then v_bad := v_bad || ' open-window=' || (c->>'rule'); end if;
  if d->>'rule' <> 'rehearsal_cap' then v_bad := v_bad || ' over-cap=' || (d->>'rule'); end if;
  if e->>'rule' = 'rehearsal_window' then v_bad := v_bad || ' public-header-was-let-through'; end if;
  if g->>'rule' <> c->>'rule' then v_bad := v_bad || ' service-header=' || (g->>'rule'); end if;
  if a->>'rule' = 'rehearsal_window' then v_bad := v_bad || ' untagged-was-let-through'; end if;
  create temp table if not exists _gate_probe(verdict text) on commit drop;
  insert into _gate_probe values (case when v_bad = '' then 'PROBE OK: untagged=' || (a->>'rule') || ' no-window=' || (b->>'rule') || ' open-window=' || (c->>'rule') || ' over-cap=' || (d->>'rule') || ' public-header=' || (e->>'rule') || ' service-header=' || (g->>'rule') else 'PROBE FAILED:' || v_bad end);
end $p$;
select verdict from _gate_probe;
