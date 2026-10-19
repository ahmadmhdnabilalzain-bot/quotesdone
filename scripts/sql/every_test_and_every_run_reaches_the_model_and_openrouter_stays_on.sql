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
--   2. Any founder hold on a route is released, and a new one (open_until > now()+1 year) is refused the same way.
--   3. rehearsal_window.models_allowed defaults to TRUE, and every open, unexpired window is set to TRUE.
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE: no spend ceiling or budget cap. rehearsal_window.cap_usd, its CHECK, the
-- gate's 'rehearsal_cap' rule, department budgets and per-key OpenRouter limits are untouched. A route's own breaker
-- (a real failure, open for cooldown_seconds) still opens and closes as before. fn_ai_route's two refusals (no
-- approved model for a class; a class the policy marks deterministic) are routing policy, not a switch, and stay.
-- The code half (ai_gateway and think.ts no longer refuse a fixture with fixture_no_spend) ships in the same PR.

set local app.change_reason = 'founder:1260';

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

-- 2. the founder hold on routes: released, and not re-imposed without him
update public.llm_route_health set open_until = null, opened_reason = 'released by ruling 1260', updated_at = now()
 where public.fn_llm_route_founder_held(open_until);

create or replace function public.fn_llm_route_health_no_new_founder_hold()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if public.fn_llm_route_founder_held(new.open_until)
     and (tg_op = 'INSERT' or not public.fn_llm_route_founder_held(old.open_until))
     and not public.fn_founder_hold_change_allowed() then
    raise exception 'RULING_1260: OpenRouter stays on; route % is held for more than a year only by the founder (set local app.change_reason = ''founder:<ledger id>'').',
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
declare v_model text := (select model_id from public.llm_route_health order by model_id limit 1);
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
    update public.llm_route_health set open_until = now() + interval '100 years' where model_id = v_model;
    insert into _p1260 values ('hold_refused', false);
    raise exception 'ROLLBACK_PROBE';
  exception when others then
    insert into _p1260 values ('hold_refused', sqlerrm like 'RULING_1260%');
  end;
  perform set_config('app.change_reason', 'founder:1260', true);
end $p$;

select case
  when (select bool_and(ok) from _p1260) is not true
    then 'PROBE FAILED: a refusal did not fire: ' || (select string_agg(k || '=' || ok, ',') from _p1260)
  when exists (select 1 from public.app_secrets where key = 'no_paid_ai')
    then 'PROBE FAILED: no_paid_ai row present'
  when exists (select 1 from public.llm_route_health where public.fn_llm_route_founder_held(open_until))
    then 'PROBE FAILED: a route is still founder-held'
  when (select column_default from information_schema.columns where table_schema = 'public'
         and table_name = 'rehearsal_window' and column_name = 'models_allowed') is distinct from 'true'
    then 'PROBE FAILED: models_allowed default is not true'
  when exists (select 1 from public.rehearsal_window where ended_at is null and expires_at > now() and not models_allowed)
    then 'PROBE FAILED: an open window still has models off'
  else 'PROBE OK'
end as verdict;
