-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727005033   name: llm_cache_and_cost_governor_rpc
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.llm_cache add column if not exists fn text;
create index if not exists llm_cache_expiry_idx on public.llm_cache (expires_at);

create or replace function public.fn_llm_cache_get(p_key text)
returns text language plpgsql security definer set search_path = public as $fn$
declare v text;
begin
  update llm_cache set hits = hits + 1, last_hit_at = now()
  where cache_key = p_key and expires_at > now()
  returning response into v;
  return v;
end; $fn$;

create or replace function public.fn_llm_cache_put(p_key text, p_fn text, p_task_class text, p_model text, p_response text, p_ttl_minutes integer default 1440)
returns void language sql security definer set search_path = public as $fn$
  insert into llm_cache (cache_key, fn, task_class, model_used, response, expires_at)
  values (p_key, p_fn, p_task_class, p_model, p_response, now() + make_interval(mins => greatest(p_ttl_minutes,1)))
  on conflict (cache_key) do update set response = excluded.response, model_used = excluded.model_used,
    expires_at = excluded.expires_at, created_at = now();
$fn$;

create or replace function public.fn_llm_log(
  p_fn text, p_dept text, p_agent text, p_task_class text,
  p_model text, p_because text, p_tier text,
  p_prompt_tokens integer, p_output_tokens integer,
  p_cached boolean, p_cache_key text, p_latency_ms integer, p_ok boolean
) returns numeric
language plpgsql security definer set search_path = public as $fn$
declare v_cost numeric := 0; v_in numeric; v_out numeric; v_cheaper boolean := false; v_reason text; v_alt text;
begin
  if not coalesce(p_cached,false) then
    select in_aed_per_mtok, out_aed_per_mtok into v_in, v_out from model_rate where model = p_model;
    if v_in is not null then
      v_cost := round( coalesce(p_prompt_tokens,0)/1000000.0 * v_in
                     + coalesce(p_output_tokens,0)/1000000.0 * v_out, 6);
    end if;
  end if;

  select deterministic_alternative into v_alt from model_policy where task_class = p_task_class;
  if v_alt is not null and v_alt <> '' then
    v_cheaper := true; v_reason := 'A deterministic path exists for this task class: ' || v_alt;
  elsif not coalesce(p_cached,false) and exists (
      select 1 from model_rate used join model_rate alt on alt.model = 'anthropic/claude-sonnet-5'
      where used.model = p_model and used.out_aed_per_mtok > alt.out_aed_per_mtok) then
    v_cheaper := true; v_reason := 'claude-sonnet-5 is cheaper than ' || p_model || ' for the same output.';
  elsif not coalesce(p_cached,false) and coalesce(p_output_tokens,0) < 200
      and exists (select 1 from model_policy mp where mp.task_class = p_task_class and mp.tier = 'small') then
    v_cheaper := true; v_reason := 'Output under 200 tokens on a small-tier class - a cache entry or a rule may serve this without a model call.';
  end if;

  insert into ai_cost_log (fn, dept_key, agent_key, task_class, model_used, model_selected_because, tier,
                           prompt_tokens, output_tokens, cached, cache_hit_key, latency_ms, cost_aed,
                           could_be_cheaper, cheaper_reason, ok)
  values (p_fn, p_dept, p_agent, p_task_class, p_model, p_because, p_tier,
          p_prompt_tokens, p_output_tokens, coalesce(p_cached,false), p_cache_key, p_latency_ms, v_cost,
          v_cheaper, v_reason, coalesce(p_ok,true));

  if p_dept is not null and v_cost > 0 then
    update department_budget set spent_aed = coalesce(spent_aed,0) + v_cost, updated_at = now()
    where dept_key = p_dept;
  end if;

  return v_cost;
end; $fn$;

revoke execute on function public.fn_llm_log(text,text,text,text,text,text,text,integer,integer,boolean,text,integer,boolean) from anon, authenticated, public;
revoke execute on function public.fn_llm_cache_get(text) from anon, authenticated, public;
revoke execute on function public.fn_llm_cache_put(text,text,text,text,text,integer) from anon, authenticated, public;

alter table public.llm_cache enable row level security;
