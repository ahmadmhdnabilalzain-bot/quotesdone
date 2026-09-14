-- the_drawing_confirm_check_is_the_one_named_exception_to_the_hold — 14 Sep 2026. Assigned: sales_engineer.
--
-- THE RULING. Founder, 14 Sep 2026 (public.founder_instruction id 216, verbatim): "in the case of the
-- boq and drawing, i dont mind using LLM to confirm the result". Scope set with it by the coordinator:
-- ONE vision call per drawing that confirms the CODED BOQ draft (supabase/functions/drawing_boq/
-- confirm.ts); a narrow, NAMED exception to the paid-model hold for that route only, with a hard
-- per-call token cap and a daily spend cap; built behind a flag that defaults OFF; not enabled for
-- customers until the cost is confirmed with the founder.
--
-- WHAT THIS CHANGES.
--   1. public.paid_route_exception — one row per excepted route. The row for 'drawing_boq_confirm'
--      ships with enabled = FALSE. Its authority column names the founder_instruction it rests on.
--   2. public.fn_paid_route_exception(p_route, p_model) — answers {allowed, rule, reason}. Allowed
--      only when the row exists AND is enabled AND the model is the one the row names AND today's
--      spend on that task_class (ai_cost_log, AED) is under the row's daily cap. Anything else,
--      including an error, is DENIED in its own words.
--   3. model_policy row 'drawing_boq_confirm': google/gemini-3.1-flash-lite (the cheapest active,
--      approved vision model in model_registry: $0.25 / $1.50 per million tokens), max_tokens 900.
--
-- WHAT IT DOES NOT CHANGE. fn_kernel_paid_provider_gate is untouched: the hold is still ON for every
-- route, and this route too, until someone sets enabled = true. ai_gateway consults this function
-- ONLY when the kernel gate refused with rule 'founder_hold' AND the caller's task_class names an
-- excepted route. No other route, task class or seat can reach it.

create table if not exists public.paid_route_exception (
  route            text primary key,
  enabled          boolean not null default false,
  model_id         text not null,
  max_tokens_per_call integer not null check (max_tokens_per_call between 1 and 4000),
  daily_cap_aed    numeric(10,2) not null check (daily_cap_aed >= 0),
  authority_instruction_id bigint references public.founder_instruction(id),
  note             text,
  updated_at       timestamptz not null default now()
);
alter table public.paid_route_exception enable row level security;
do $pol$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'paid_route_exception' and policyname = 'paid_route_exception_service_role_only') then
    create policy paid_route_exception_service_role_only on public.paid_route_exception as permissive for all to public using (false) with check (false);
  end if;
end $pol$;
revoke all on public.paid_route_exception from anon, authenticated;

insert into public.paid_route_exception (route, enabled, model_id, max_tokens_per_call, daily_cap_aed, authority_instruction_id, note)
values ('drawing_boq_confirm', false, 'google/gemini-3.1-flash-lite', 900, 5.00, 216,
        'One vision call per drawing confirming the coded BOQ draft. OFF until the founder confirms the cost per drawing. Daily cap AED 5.00 ~ 900 calls at the estimated AED 0.0055 each.')
on conflict (route) do nothing;

insert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active, cache_ttl_min)
values ('drawing_boq_confirm', 'small', 'google/gemini-3.1-flash-lite', null, 900,
        'Founder 14 Sep 2026 (founder_instruction 216): a model may CONFIRM the coded drawing BOQ. Cheapest active approved vision model. Reachable under the hold only through public.paid_route_exception.',
        'drawing_from_ocr + symbol_count: the coded draft stands when this is unavailable', true, 0)
on conflict (task_class) do nothing;

create or replace function public.fn_paid_route_exception(p_route text, p_model text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  r public.paid_route_exception%rowtype;
  v_spent numeric;
begin
  select * into r from public.paid_route_exception where route = p_route;
  if not found then
    return jsonb_build_object('allowed', false, 'rule', 'no_exception', 'reason', 'no paid_route_exception row for ' || coalesce(p_route, 'null'));
  end if;
  if not r.enabled then
    return jsonb_build_object('allowed', false, 'rule', 'exception_disabled', 'reason', 'the exception for ' || p_route || ' exists and is switched off');
  end if;
  if p_model is distinct from r.model_id then
    return jsonb_build_object('allowed', false, 'rule', 'exception_other_model', 'reason', 'the exception names ' || r.model_id || ', not ' || coalesce(p_model, 'null'));
  end if;
  select coalesce(sum(cost_aed), 0) into v_spent from public.ai_cost_log
   where task_class = p_route and occurred_at >= date_trunc('day', now());
  if v_spent >= r.daily_cap_aed then
    return jsonb_build_object('allowed', false, 'rule', 'exception_daily_cap', 'reason', 'spent AED ' || v_spent || ' of the AED ' || r.daily_cap_aed || ' daily cap');
  end if;
  return jsonb_build_object('allowed', true, 'rule', 'named_exception', 'route', p_route, 'model', r.model_id,
    'max_tokens', r.max_tokens_per_call, 'spent_today_aed', v_spent, 'daily_cap_aed', r.daily_cap_aed, 'authority_instruction_id', r.authority_instruction_id);
exception when others then
  return jsonb_build_object('allowed', false, 'rule', 'exception_unreadable', 'reason', sqlstate || ' ' || sqlerrm);
end $fn$;

revoke execute on function public.fn_paid_route_exception(text, text) from public, anon, authenticated;

do $chk$
declare a jsonb; b jsonb; c jsonb;
begin
  a := public.fn_paid_route_exception('drawing_boq_confirm', 'google/gemini-3.1-flash-lite');
  b := public.fn_paid_route_exception('general_drafting', 'google/gemini-3.1-flash-lite');
  c := public.fn_kernel_paid_provider_gate('google/gemini-3.1-flash-lite');
  if (a->>'allowed')::boolean or (b->>'allowed')::boolean then
    raise exception 'an exception answered allowed while shipped OFF: % / %', a, b;
  end if;
  if (c->>'allowed')::boolean then
    raise exception 'the kernel hold is not holding: %', c;
  end if;
  raise notice 'CHK<<confirm route: %, other route: %, kernel: %>>', a->>'rule', b->>'rule', c->>'rule';
end $chk$;
