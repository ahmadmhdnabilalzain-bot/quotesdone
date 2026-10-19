-- EVERY TEST AND EVERY RUN REACHES THE MODEL, AND OPENROUTER STAYS ON
-- it_engineer, 19 Oct 2026. Founder ruling 1260 (public.founder_instruction id 1260, verbatim):
--   "all tests need to be done with AI. from now on open router stays on"
--
-- MEASURED on production 19 Oct 2026, before this file (read-only, scripts/lib/db.mjs):
--   * app_secrets.no_paid_ai              no row (switch off)        read by fn_kernel_paid_provider_gate rule 'no_paid_ai_switch'
--   * llm_route_health founder hold       0 of 20 routes held        read by fn_kernel_paid_provider_gate rule 'founder_hold'
--   * rehearsal_window.models_allowed     column default false       read by fn_e2e_run_tag_open -> gate rule 'rehearsal_window_closed'
--   * 3 open, unexpired windows with models_allowed already true
--   * fn_kernel_paid_provider_gate('~anthropic/claude-haiku-latest') -> allowed, 'registered_breaker_closed'
--
-- WHAT THIS CHANGES
--   1. no_paid_ai is removed and can no longer be switched ON except with a founder:<ledger id> change reason.
--   2. Any hold on a route, of any length (open past its own breaker cooldown), is released, and a new one is
--      refused the same way. A real breaker still opens for its cooldown.
--   Code half (same PR): inside its tagged, open rehearsal window a test call reaches the model and is costed with
--   its run tag; untagged or outside its window it is still refused fixture_no_spend.
--   3. rehearsal_window.models_allowed defaults to TRUE, and every open, unexpired window is set to TRUE.
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE: no spend ceiling or budget cap. rehearsal_window.cap_usd, its CHECK, the
-- gate's 'rehearsal_cap' rule, department budgets and per-key OpenRouter limits are untouched. A route's own breaker
-- (a real failure, open for cooldown_seconds) still opens and closes as before. fn_ai_route's two refusals (no
-- approved model for a class; a class the policy marks deterministic) are routing policy, not a switch, and stay.

-- THE FOUNDER'S REASON IS NOT IN THIS FILE (a_sandbox_success_never_lifts_the_model_hold.test.mjs: no file may carry it).
-- The release operator applies it with the founder's ledger id for ruling 1260 set first in the same transaction
-- (see this file's pending note); without it the guarded writes below refuse, so nothing changes.
do $g$ begin
  if coalesce(current_setting('app.change_reason', true), '') !~ '^founder:[0-9]+
-- 1. the explicit switch: off, and it stays off
delete from public.app_secrets where key = 'no_paid_ai';

create or replace function public.fn_app_secrets_no_paid_ai_stays_off()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if new.key = 'no_paid_ai' and lower(coalesce(new.value, '')) in ('1','true','yes','on')
     and not public.fn_founder_hold_change_allowed() then
    raise exception 'RULING_1260: OpenRouter stays on; app_secrets.no_paid_ai is switched on only by the founder (set local app.change_reason = ''founder:<ledger id>'').'
      using errcode = 'P0001';
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_app_secrets_no_paid_ai_stays_off() from public, anon, authenticated;

drop trigger if exists trg_app_secrets_no_paid_ai_stays_off on public.app_secrets;
create trigger trg_app_secrets_no_paid_ai_stays_off before insert or update on public.app_secrets
  for each row execute function public.fn_app_secrets_no_paid_ai_stays_off();

-- 2. any hold on a route, of ANY length, is released, and not re-imposed without him. A HOLD is any open circuit
--    longer than the route's own breaker sets (now() + cooldown_seconds; 900 s on every route measured 6 Oct 2026),
--    plus five minutes of slack; a real breaker stays inside that and keeps working.
create or replace function public.fn_llm_route_is_held(p_open_until timestamptz, p_cooldown_seconds integer)
returns boolean language sql stable
set search_path to 'public', 'pg_temp'
as $fn$ select coalesce(p_open_until > now() + make_interval(secs => greatest(coalesce(p_cooldown_seconds, 0), 0)) + interval '5 minutes', false) $fn$;
revoke execute on function public.fn_llm_route_is_held(timestamptz, integer) from public, anon, authenticated;

update public.llm_route_health set open_until = null, opened_reason = 'released by ruling 1260', updated_at = now()
 where public.fn_llm_route_is_held(open_until, cooldown_seconds);

create or replace function public.fn_llm_route_health_no_new_founder_hold()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if public.fn_llm_route_is_held(new.open_until, new.cooldown_seconds)
     and (tg_op = 'INSERT' or new.open_until is distinct from old.open_until)
     and not public.fn_founder_hold_change_allowed() then
    raise exception 'RULING_1260: OpenRouter stays on; route % is held past its own breaker cooldown only by the founder (set local app.change_reason = ''founder:<ledger id>'').',
      new.model_id using errcode = 'P0001';
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_llm_route_health_no_new_founder_hold() from public, anon, authenticated;

drop trigger if exists trg_llm_route_health_no_new_founder_hold on public.llm_route_health;
create trigger trg_llm_route_health_no_new_founder_hold before insert or update on public.llm_route_health
  for each row execute function public.fn_llm_route_health_no_new_founder_hold();

-- 3. every test window has the model; the cap is not touched
alter table public.rehearsal_window alter column models_allowed set default true;
update public.rehearsal_window set models_allowed = true
 where ended_at is null and expires_at > now() and not models_allowed;

-- PROBE (verdict row; the two refusal attempts run in subtransactions that roll back)
create temp table _p1260 (k text, ok boolean) on commit drop;
do $p$
declare v_model text := (select model_id from public.llm_route_health order by model_id limit 1); v_reason text := current_setting('app.change_reason', true);
begin
  perform set_config('app.change_reason', '', true);
  begin
    insert into public.app_secrets (key, value) values ('no_paid_ai', 'on');
    insert into _p1260 values ('switch_refused', false);
    raise exception 'ROLLBACK_PROBE';
  exception when others then
    insert into _p1260 values ('switch_refused', sqlerrm like 'RULING_1260%');
  end;
  begin
    update public.llm_route_health set open_until = now() + interval '2 hours' where model_id = v_model;
    insert into _p1260 values ('short_hold_refused', false);
    raise exception 'ROLLBACK_PROBE';
  exception when others then
    insert into _p1260 values ('short_hold_refused', sqlerrm like 'RULING_1260%');
  end;
  begin   -- a real breaker (its own cooldown) must still open
    update public.llm_route_health set open_until = now() + make_interval(secs => cooldown_seconds) where model_id = v_model;
    raise exception 'ROLLBACK_PROBE';
  exception when others then
    insert into _p1260 values ('breaker_still_opens', sqlerrm = 'ROLLBACK_PROBE');
  end;
  perform set_config('app.change_reason', v_reason, true);   -- the operator's founder reason, restored after the probe
end $p$;

select case
  when (select bool_and(ok) from _p1260) is not true
    then 'PROBE FAILED: a refusal did not fire: ' || (select string_agg(k || '=' || ok, ',') from _p1260)
  when exists (select 1 from public.app_secrets where key = 'no_paid_ai')
    then 'PROBE FAILED: no_paid_ai row present'
  when exists (select 1 from public.llm_route_health where public.fn_llm_route_is_held(open_until, cooldown_seconds))
    then 'PROBE FAILED: a route is still held'
  when (select column_default from information_schema.columns where table_schema = 'public'
         and table_name = 'rehearsal_window' and column_name = 'models_allowed') is distinct from 'true'
    then 'PROBE FAILED: models_allowed default is not true'
  when exists (select 1 from public.rehearsal_window where ended_at is null and expires_at > now() and not models_allowed)
    then 'PROBE FAILED: an open window still has models off'
  else 'PROBE OK'
end as verdict;
 then
    raise exception 'apply this file with the founder''s change reason for ruling 1260 set first (pending note)';
  end if;
end $g$;

-- 1. the explicit switch: off, and it stays off
delete from public.app_secrets where key = 'no_paid_ai';

create or replace function public.fn_app_secrets_no_paid_ai_stays_off()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if new.key = 'no_paid_ai' and lower(coalesce(new.value, '')) in ('1','true','yes','on')
     and not public.fn_founder_hold_change_allowed() then
    raise exception 'RULING_1260: OpenRouter stays on; app_secrets.no_paid_ai is switched on only by the founder (set local app.change_reason = ''founder:<ledger id>'').'
      using errcode = 'P0001';
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_app_secrets_no_paid_ai_stays_off() from public, anon, authenticated;

drop trigger if exists trg_app_secrets_no_paid_ai_stays_off on public.app_secrets;
create trigger trg_app_secrets_no_paid_ai_stays_off before insert or update on public.app_secrets
  for each row execute function public.fn_app_secrets_no_paid_ai_stays_off();

-- 2. any hold on a route, of ANY length, is released, and not re-imposed without him. A HOLD is any open circuit
--    longer than the route's own breaker sets (now() + cooldown_seconds; 900 s on every route measured 6 Oct 2026),
--    plus five minutes of slack; a real breaker stays inside that and keeps working.
create or replace function public.fn_llm_route_is_held(p_open_until timestamptz, p_cooldown_seconds integer)
returns boolean language sql stable
set search_path to 'public', 'pg_temp'
as $fn$ select coalesce(p_open_until > now() + make_interval(secs => greatest(coalesce(p_cooldown_seconds, 0), 0)) + interval '5 minutes', false) $fn$;
revoke execute on function public.fn_llm_route_is_held(timestamptz, integer) from public, anon, authenticated;

update public.llm_route_health set open_until = null, opened_reason = 'released by ruling 1260', updated_at = now()
 where public.fn_llm_route_is_held(open_until, cooldown_seconds);

create or replace function public.fn_llm_route_health_no_new_founder_hold()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if public.fn_llm_route_is_held(new.open_until, new.cooldown_seconds)
     and (tg_op = 'INSERT' or new.open_until is distinct from old.open_until)
     and not public.fn_founder_hold_change_allowed() then
    raise exception 'RULING_1260: OpenRouter stays on; route % is held past its own breaker cooldown only by the founder (set local app.change_reason = ''founder:<ledger id>'').',
      new.model_id using errcode = 'P0001';
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_llm_route_health_no_new_founder_hold() from public, anon, authenticated;

drop trigger if exists trg_llm_route_health_no_new_founder_hold on public.llm_route_health;
create trigger trg_llm_route_health_no_new_founder_hold before insert or update on public.llm_route_health
  for each row execute function public.fn_llm_route_health_no_new_founder_hold();

-- 3. every test window has the model; the cap is not touched
alter table public.rehearsal_window alter column models_allowed set default true;
update public.rehearsal_window set models_allowed = true
 where ended_at is null and expires_at > now() and not models_allowed;

-- PROBE (verdict row; the two refusal attempts run in subtransactions that roll back)
create temp table _p1260 (k text, ok boolean) on commit drop;
do $p$
declare v_model text := (select model_id from public.llm_route_health order by model_id limit 1); v_reason text := current_setting('app.change_reason', true);
begin
  perform set_config('app.change_reason', '', true);
  begin
    insert into public.app_secrets (key, value) values ('no_paid_ai', 'on');
    insert into _p1260 values ('switch_refused', false);
    raise exception 'ROLLBACK_PROBE';
  exception when others then
    insert into _p1260 values ('switch_refused', sqlerrm like 'RULING_1260%');
  end;
  begin
    update public.llm_route_health set open_until = now() + interval '2 hours' where model_id = v_model;
    insert into _p1260 values ('short_hold_refused', false);
    raise exception 'ROLLBACK_PROBE';
  exception when others then
    insert into _p1260 values ('short_hold_refused', sqlerrm like 'RULING_1260%');
  end;
  begin   -- a real breaker (its own cooldown) must still open
    update public.llm_route_health set open_until = now() + make_interval(secs => cooldown_seconds) where model_id = v_model;
    raise exception 'ROLLBACK_PROBE';
  exception when others then
    insert into _p1260 values ('breaker_still_opens', sqlerrm = 'ROLLBACK_PROBE');
  end;
  perform set_config('app.change_reason', v_reason, true);   -- the operator's founder reason, restored after the probe
end $p$;

select case
  when (select bool_and(ok) from _p1260) is not true
    then 'PROBE FAILED: a refusal did not fire: ' || (select string_agg(k || '=' || ok, ',') from _p1260)
  when exists (select 1 from public.app_secrets where key = 'no_paid_ai')
    then 'PROBE FAILED: no_paid_ai row present'
  when exists (select 1 from public.llm_route_health where public.fn_llm_route_is_held(open_until, cooldown_seconds))
    then 'PROBE FAILED: a route is still held'
  when (select column_default from information_schema.columns where table_schema = 'public'
         and table_name = 'rehearsal_window' and column_name = 'models_allowed') is distinct from 'true'
    then 'PROBE FAILED: models_allowed default is not true'
  when exists (select 1 from public.rehearsal_window where ended_at is null and expires_at > now() and not models_allowed)
    then 'PROBE FAILED: an open window still has models off'
  else 'PROBE OK'
end as verdict;
