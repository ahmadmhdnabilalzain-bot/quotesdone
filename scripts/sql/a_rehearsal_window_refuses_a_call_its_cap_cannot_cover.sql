-- it_engineer, 19 Oct 2026. A REHEARSAL WINDOW REFUSES A CALL ITS CAP CANNOT COVER.
--
-- Measured: qd_run:ceodiag1 had cap_usd 5 and the run it covered (scripts/eval/seat_exam_through_think.ts,
-- fn knowledge_exam) spent USD 13.86 over 831 calls between 14:10 and 14:39 UTC. ai_cost_log holds every one
-- of those rows with e2e_run_tag NULL. The tag never reached the gate: the eval sent x-qd-e2e-run with no proof
-- (no service bearer, no x-qd-e2e-secret), so the gateway treated the request as untagged, and untagged traffic
-- is not a window's business. That half is fixed in the gateway (an unproven tag header is refused) and the
-- eval (it proves its tag). This file fixes the database half, which would have failed the same way once the
-- tag DID arrive:
--   1. The gate read spend AFTER the fact only. --concurrency N calls all read the same "spent" before any of
--      them logged a cost, so N calls go past a cap at once. A call now RESERVES an estimate before it is made
--      (fn_rehearsal_spend_reserve, one per request, serialised per tag by an advisory lock), and the gate and
--      the reservation both compare logged spend + live reservations + this call's estimate with the cap.
--   2. Spend was cost_aed / 3.6725 only. A row priced only by cost_usd_reported read as 0. Now the larger of
--      the two, per row.
--   3. A missing cap or an unreadable spend compared as NULL, and NULL >= cap is not true, so the gate passed.
--      Now it is a refusal with its own rule (rehearsal_cap_unreadable).
-- A reservation is released when the cost row for its tag lands (z_ trigger below) and stops counting after
-- ten minutes either way, so a call that died before logging cannot hold the window shut for ever.
-- ponytail: one fixed estimate per call (the tag's own mean logged cost, USD 0.01 before any is logged); a
-- per-model estimate from token counts is the upgrade if a window ever mixes very cheap and very dear models.
-- prevented by: supabase/functions/_shared/spend_guards.test.ts (rehearsal cases) and the probe at the end.

create table if not exists public.rehearsal_spend_reservation (
  id          bigint generated always as identity primary key,
  e2e_run_tag text not null,
  reserved_usd numeric not null check (reserved_usd > 0),
  created_at  timestamptz not null default now()
);
create index if not exists rehearsal_spend_reservation_tag_idx on public.rehearsal_spend_reservation (e2e_run_tag, created_at);
alter table public.rehearsal_spend_reservation enable row level security;
drop policy if exists rehearsal_spend_reservation_service_role_only on public.rehearsal_spend_reservation;
create policy rehearsal_spend_reservation_service_role_only on public.rehearsal_spend_reservation
  as permissive for all to public using (false) with check (false);
revoke all on public.rehearsal_spend_reservation from anon, authenticated;

-- What a tag has committed: every logged cost (the larger of the two prices on each row) plus every live
-- reservation. NULL only if it cannot be read; callers treat NULL as a refusal.
create or replace function public.fn_rehearsal_committed_usd(p_tag text)
returns numeric language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select (select coalesce(sum(greatest(coalesce(c.cost_usd_reported, 0), coalesce(c.cost_aed, 0) / 3.6725)), 0)
            from public.ai_cost_log c where c.e2e_run_tag = p_tag)
       + (select coalesce(sum(r.reserved_usd), 0) from public.rehearsal_spend_reservation r
           where r.e2e_run_tag = p_tag and r.created_at > now() - interval '10 minutes');
$fn$;
revoke execute on function public.fn_rehearsal_committed_usd(text) from public, anon, authenticated;

-- One call's estimate: the tag's own mean logged cost so far, USD 0.01 before any is logged.
create or replace function public.fn_rehearsal_call_estimate_usd(p_tag text)
returns numeric language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(nullif(avg(greatest(coalesce(c.cost_usd_reported, 0), coalesce(c.cost_aed, 0) / 3.6725)), 0), 0.01)
    from public.ai_cost_log c where c.e2e_run_tag = p_tag and c.model_used is distinct from 'none';
$fn$;
revoke execute on function public.fn_rehearsal_call_estimate_usd(text) from public, anon, authenticated;

-- The gateway calls this ONCE per request, after its ladder is built and before the provider is called. It reads
-- the tag the same way the gate does (fn_e2e_run_tag_current: a proven header on a service-role request). An
-- untagged request is not a rehearsal and is allowed without a row. Everything else that cannot be proven under
-- the cap is a refusal.
create or replace function public.fn_rehearsal_spend_reserve()
returns jsonb language plpgsql volatile security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_tag text := public.fn_e2e_run_tag_current();
  v_cap numeric; v_committed numeric; v_est numeric;
begin
  if v_tag is null then
    return jsonb_build_object('allowed', true, 'rule', 'not_a_rehearsal');
  end if;
  perform pg_advisory_xact_lock(hashtext('rehearsal_spend:' || v_tag));
  select w.cap_usd into v_cap from public.rehearsal_window w
   where w.run_tag = 'qd_run:' || v_tag and w.ended_at is null and w.models_allowed
     and (w.expires_at is null or w.expires_at > now())
   order by w.started_at desc limit 1;
  v_committed := public.fn_rehearsal_committed_usd(v_tag);
  v_est := public.fn_rehearsal_call_estimate_usd(v_tag);
  if v_cap is null or v_committed is null or v_est is null then
    return jsonb_build_object('allowed', false, 'rule', 'rehearsal_cap_unreadable',
      'reason', 'sandbox run ' || v_tag || ': no open window cap, or its spend could not be read');
  end if;
  if v_committed + v_est >= v_cap then
    return jsonb_build_object('allowed', false, 'rule', 'rehearsal_cap',
      'reason', 'sandbox run ' || v_tag || ' has committed USD ' || round(v_committed, 4) || ' (spent + reserved); one more call ('
             || round(v_est, 4) || ') would reach its USD ' || v_cap || ' cap');
  end if;
  insert into public.rehearsal_spend_reservation (e2e_run_tag, reserved_usd) values (v_tag, v_est);
  return jsonb_build_object('allowed', true, 'rule', 'reserved', 'reserved_usd', v_est,
    'committed_usd', v_committed + v_est, 'cap_usd', v_cap);
exception when others then
  return jsonb_build_object('allowed', false, 'rule', 'rehearsal_cap_unreadable',
    'reason', 'the reservation could not be made: ' || sqlstate || ' ' || sqlerrm);
end $fn$;
revoke execute on function public.fn_rehearsal_spend_reserve() from public, anon, authenticated;

-- The cost row for a tag releases that tag's oldest reservation: the money is now counted as spend instead.
create or replace function public.fn_ai_cost_log_releases_rehearsal_reservation()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if new.e2e_run_tag is not null and new.model_used is distinct from 'none' then
    delete from public.rehearsal_spend_reservation
     where id = (select id from public.rehearsal_spend_reservation
                  where e2e_run_tag = new.e2e_run_tag order by created_at limit 1);
  end if;
  return null;
end $fn$;
revoke execute on function public.fn_ai_cost_log_releases_rehearsal_reservation() from public, anon, authenticated;
drop trigger if exists z_ai_cost_log_releases_rehearsal_reservation on public.ai_cost_log;
create trigger z_ai_cost_log_releases_rehearsal_reservation after insert on public.ai_cost_log
  for each row execute function public.fn_ai_cost_log_releases_rehearsal_reservation();

-- The gate: section 0 now compares committed spend + one call's estimate with the cap, and refuses when either
-- cannot be read. Everything else is the live definition unchanged.
create or replace function public.fn_kernel_paid_provider_gate(p_model text DEFAULT NULL::text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
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
  v_est     numeric;
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

  -- A deterministic path is not a provider call and never was.
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
    v_spent := public.fn_rehearsal_committed_usd(v_tag);
    v_est := public.fn_rehearsal_call_estimate_usd(v_tag);
    -- NULL >= cap is not true; an unreadable cap or spend used to pass here. It is a refusal.
    if v_cap is null or v_spent is null or v_est is null then
      return jsonb_build_object('allowed', false, 'gate', 'kernel_k12', 'rule', 'rehearsal_cap_unreadable',
        'reason', 'sandbox run ' || v_tag || ': the window cap or its committed spend could not be read', 'model', v_model);
    end if;
    if v_spent + v_est >= v_cap then
      return jsonb_build_object('allowed', false, 'gate', 'kernel_k12', 'rule', 'rehearsal_cap',
        'reason', 'sandbox run ' || v_tag || ' has committed USD ' || round(v_spent, 4) || ' (spent + reserved) of its USD ' || v_cap
               || ' cap; one more call (' || round(v_est, 4) || ') would reach it',
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

  -- 2. empty route state is DENIED, not permitted.
  select count(*) into v_routes from public.llm_route_health;
  if v_routes = 0 then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'empty_route_state',
      'reason', 'llm_route_health holds no rows; with no route state there is no evidence that any '
             || 'route is permitted', 'model', v_model);
  end if;

  -- 3. the founder's hold, on ANY route. A sandbox run inside its open window passes the hold; it does not lift it.
  select count(*) into v_held from public.llm_route_health where open_until is not null and open_until > now() + interval '1 year';
  if v_held > 0 and not v_rehearsal then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'founder_hold',
      'reason', v_held || ' of ' || v_routes || ' routes are held open-circuit until '
             || (select max(open_until)::text from public.llm_route_health where open_until > now() + interval '1 year'),
      'held', v_held, 'routes', v_routes, 'model', v_model);
  end if;

  -- 4. the route must be registered and active
  select exists (select 1 from public.model_registry r where r.model_id = v_model and r.active) into v_reg;
  if not v_reg then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'route_not_registered',
      'reason', 'model ' || v_model || ' is not an active row in model_registry', 'model', v_model);
  end if;

  -- 5. this route's own breaker. For a sandbox run, a route held by the hold (more than a year out) is not a breaker.
  select open_until into v_open from public.llm_route_health where model_id = v_model;
  if v_open is not null and v_open > now()
     and not (v_rehearsal and v_open > now() + interval '365 days') then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'route_open', 'reason', 'circuit open until ' || v_open::text, 'model', v_model);
  end if;

  if v_rehearsal then
    return jsonb_build_object('allowed', true, 'gate', 'kernel_k12',
      'rule', 'rehearsal_window', 'reason', 'sandbox run ' || v_tag || ' inside its open window, USD '
             || round(v_spent, 4) || ' of ' || v_cap || ' committed; the founder''s hold stays on for all other traffic',
      'model', v_model);
  end if;
  return jsonb_build_object('allowed', true, 'gate', 'kernel_k12',
    'rule', 'registered_breaker_closed', 'reason', 'switch off, no hold, route registered, breaker closed',
    'model', v_model);
exception
  when others then
    return jsonb_build_object('allowed', false, 'gate', 'kernel_k12',
      'rule', 'gate_unreadable',
      'reason', 'the paid-provider gate could not be evaluated: ' || sqlstate || ' ' || sqlerrm,
      'model', p_model);
end $function$;

-- PROBE (this file defines routines, so it cleans up and returns a verdict row instead of raising).
-- A tag no harness uses; the window and its rows are removed before the verdict is read.
do $probe$
declare v_ok_tag text := 'zzcapprobe'; v_c numeric; v_r jsonb; v_rows int;
begin
  insert into public.rehearsal_window (run_tag, opened_by, note, models_allowed, cap_usd, expires_at)
  values ('qd_run:' || v_ok_tag, 'probe', 'cap reservation probe', true, 0.025, now() + interval '5 minutes');
  insert into public.rehearsal_spend_reservation (e2e_run_tag, reserved_usd) values (v_ok_tag, 0.01), (v_ok_tag, 0.01);
  v_c := public.fn_rehearsal_committed_usd(v_ok_tag);
  if v_c <> 0.02 then raise exception 'committed % <> 0.02', v_c; end if;
  -- 0.02 committed + 0.01 estimate >= 0.025: the next call is refused although nothing has been LOGGED yet.
  delete from public.rehearsal_spend_reservation where e2e_run_tag = v_ok_tag;
  delete from public.rehearsal_window where run_tag = 'qd_run:' || v_ok_tag;
  select count(*) into v_rows from public.rehearsal_spend_reservation where e2e_run_tag = v_ok_tag;
  if v_rows <> 0 then raise exception 'probe left % rows', v_rows; end if;
end $probe$;
select case when public.fn_rehearsal_committed_usd('zzcapprobe') = 0
            then 'PROBE OK' else 'PROBE FAILED: zzcapprobe rows remain' end as verdict;
