-- PROMPT CACHING: THE MONEY WAS REAL AND THE METER WAS BROKEN.
--
-- MEASURED on production 11 Aug 2026 (two identical probe calls to
-- anthropic/claude-sonnet-5 through OpenRouter, request ids 207701 / 207702):
--
--   call 1  prompt_tokens 2697  cost $0.010800  prompt_tokens_details = {cached_tokens:0,    cache_write_tokens:2683}
--   call 2  prompt_tokens 2697  cost $0.000605  prompt_tokens_details = {cached_tokens:2683, cache_write_tokens:0}
--
-- An 18x reduction on the prompt for a byte-identical prefix. So caching works.
--
-- ai_gateway ALREADY sent cache_control on the system block. What it never did was READ the
-- result: it looked for usage.cache_read_input_tokens and usage.cached_tokens, and OpenRouter
-- reports neither. The numbers live one level down, in usage.prompt_tokens_details. So cachedIn
-- was 0 on every call ever made, fn_llm_log was told p_cached=false every time, and the company
-- measured "4 cached calls out of 2,141" — which was never a caching failure. It was a meter
-- reading zero because it was pointed at a field that does not exist.
--
-- Two columns and a cost formula, because the meter has to be right before the policy can be.
--
--  * cached_in_tokens     — prompt tokens served FROM the cache at ~10% of the input rate
--  * cache_write_tokens   — prompt tokens written INTO the cache at 1.25x the input rate
--
-- `cached` keeps its old meaning and is NOT widened to cover prompt-cache reads: it means "no
-- model was called at all" (an llm_cache exact/semantic replay, cost 0). A prompt-cache read IS
-- a model call and it DOES cost money. Conflating the two is how a 90%-off prompt would have
-- been booked at zero — fn_llm_log skips costing entirely when p_cached is true.
alter table public.ai_cost_log
  add column if not exists cached_in_tokens   integer not null default 0,
  add column if not exists cache_write_tokens integer not null default 0;

comment on column public.ai_cost_log.cached_in_tokens is
  'Prompt tokens served from the provider prompt cache (usage.prompt_tokens_details.cached_tokens). Billed at the cache-read rate, not the input rate.';
comment on column public.ai_cost_log.cache_write_tokens is
  'Prompt tokens written into the provider prompt cache (usage.prompt_tokens_details.cache_write_tokens). Billed at 1.25x the input rate for the default 5-minute TTL.';

-- Rates. model_registry already carries cache_read_per_mtok_usd; model_rate is what fn_llm_log
-- costs from, and it had no cache columns at all.
alter table public.model_rate
  add column if not exists cache_read_aed_per_mtok  numeric,
  add column if not exists cache_write_aed_per_mtok numeric;

update public.model_rate r
   set cache_read_aed_per_mtok  = coalesce(g.cache_read_per_mtok_usd * 3.6725, r.in_aed_per_mtok * 0.10),
       -- Anthropic charges 1.25x the input rate to write a 5-minute cache block. Derived, not
       -- guessed: the probe above paid $0.0108 for 2,697 tokens = $4.00/Mtok against a $2.00/Mtok
       -- input rate, which is 2.0x — that call used ttl:'1h', which is the 2x tier. The default
       -- (no ttl) block is the 1.25x tier and is what ai_gateway now sends. See the TTL note below.
       cache_write_aed_per_mtok = r.in_aed_per_mtok * 1.25
  from public.model_registry g
 where g.model_id = r.model;

update public.model_rate
   set cache_read_aed_per_mtok  = coalesce(cache_read_aed_per_mtok, in_aed_per_mtok * 0.10),
       cache_write_aed_per_mtok = coalesce(cache_write_aed_per_mtok, in_aed_per_mtok * 1.25)
 where cache_read_aed_per_mtok is null or cache_write_aed_per_mtok is null;

-- WHY 5 MINUTES AND NOT 1 HOUR. Both work through OpenRouter (the 1h probe returned 200). The
-- choice is arithmetic over the real traffic, measured 11 Aug 2026 over 7 days of agent_brain
-- agent_reasoning calls, 264 of them:
--
--   same-agent repeat within  5 minutes  100 / 264 = 38%
--   same-agent repeat within 55 minutes  108 / 264 = 41%
--   same-agent repeat within 65 minutes  238 / 264 = 90%   <-- the hourly loop, JUST outside 1h
--
--   5-minute TTL: write 1.25x, read 0.10x -> break-even at a 22% hit rate. At 38% the input bill
--                 becomes 0.62*1.25 + 0.38*0.10 = 0.81 of what it was. It pays.
--   1-hour  TTL: write 2.00x, read 0.10x -> break-even at a 53% hit rate. At 41% the input bill
--                 becomes 0.59*2.00 + 0.41*0.10 = 1.22 of what it was. It COSTS 22% MORE.
--
-- The hourly cadence lands at 65 minutes, not 55 — just past a 1-hour window — so the tier that
-- looks made for this workload is the one that loses money on it. 5 minutes it is.
insert into public.decision_policy(key, value, description) values
  ('prompt_cache_enabled', 'true'::jsonb,
   'Mark the stable half of a long system prompt with cache_control so the provider can serve it from cache. Measured 11 Aug 2026: 38% of agent_brain reasoning calls repeat the same agent within the 5-minute window, against a 22% break-even. Set false to stop paying cache-write premiums if that ratio ever falls.')
on conflict (key) do update set value = excluded.value, description = excluded.description;

-- COSTING. Prompt-cache reads and writes are priced at their own rates; the remainder of the
-- prompt is priced at the input rate. Before this, a call that read 20k tokens from cache was
-- billed as if it had paid full price for all 20k.
create or replace function public.fn_llm_log(
  p_fn text, p_dept text, p_agent text, p_task_class text, p_model text, p_because text,
  p_tier text, p_prompt_tokens integer, p_output_tokens integer, p_cached boolean,
  p_cache_key text, p_latency_ms integer, p_ok boolean, p_confidence numeric DEFAULT NULL::numeric,
  p_cached_in integer DEFAULT 0, p_cache_write integer DEFAULT 0)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_cost numeric := 0; v_in numeric; v_out numeric; v_cr numeric; v_cw numeric;
        v_cheaper boolean := false; v_reason text; v_alt text; v_class text;
        v_plain int; v_read int; v_write int;
begin
  -- A call with no task_class is invisible to routing, capping, caching and benchmarking. Derive it
  -- from the caller when the caller did not say, and fall back to the same safe medium default
  -- fn_ai_route uses for an unmapped class rather than leaving it null.
  v_class := coalesce(nullif(trim(coalesce(p_task_class,'')), ''), case
    when p_fn ~* 'agent_brain|dept_plan|exec_agents|reflect|conductor'   then 'agent_reasoning'
    when p_fn ~* 'cos_execute|secretary|chief'                            then 'chief_of_staff_decision'
    when p_fn ~* 'knowledge|kb_|canon_eval|research|exam'                 then 'knowledge_research'
    when p_fn ~* 'extract|parse|ocr'                                      then 'document_extraction'
    when p_fn ~* 'classif|categor|intent|route'                           then 'category_classification'
    when p_fn ~* 'draft|content|blog|marketing|social'                    then 'content_drafting'
    when p_fn ~* 'quote|rfq|supplier|procure'                             then 'procurement_reasoning'
    else 'general_drafting' end);

  v_read  := greatest(coalesce(p_cached_in,0), 0);
  v_write := greatest(coalesce(p_cache_write,0), 0);
  -- The provider reports cached_tokens as a SUBSET of prompt_tokens, and cache_write_tokens the
  -- same way. Never let a bad reading drive the plain remainder negative.
  v_plain := greatest(coalesce(p_prompt_tokens,0) - v_read - v_write, 0);

  if not coalesce(p_cached,false) then
    select in_aed_per_mtok, out_aed_per_mtok, cache_read_aed_per_mtok, cache_write_aed_per_mtok
      into v_in, v_out, v_cr, v_cw
      from model_rate where model = p_model;
    if v_in is not null then
      v_cost := round( v_plain/1000000.0 * v_in
                     + v_read /1000000.0 * coalesce(v_cr, v_in * 0.10)
                     + v_write/1000000.0 * coalesce(v_cw, v_in * 1.25)
                     + coalesce(p_output_tokens,0)/1000000.0 * v_out, 6);
    end if;
  end if;

  select deterministic_alternative into v_alt from model_policy where task_class = v_class;
  if v_alt is not null and v_alt <> '' then
    v_cheaper := true; v_reason := 'A deterministic path exists for this task class: ' || v_alt;
  elsif not coalesce(p_cached,false) and exists (
      select 1 from model_rate used join model_rate alt on alt.model = 'anthropic/claude-sonnet-5'
       where used.model = p_model and alt.in_aed_per_mtok < used.in_aed_per_mtok) then
    v_cheaper := true;
    v_reason := 'claude-sonnet-5 is cheaper than ' || p_model || ' for the same output.';
  end if;

  insert into ai_cost_log (fn, dept_key, agent_key, task_class, model_used, model_selected_because,
    tier, prompt_tokens, output_tokens, cached, cache_hit_key, latency_ms, cost_aed,
    could_be_cheaper, cheaper_reason, ok, confidence, cached_in_tokens, cache_write_tokens)
  values (p_fn, p_dept, p_agent, v_class, p_model, p_because, p_tier,
    coalesce(p_prompt_tokens,0), coalesce(p_output_tokens,0), coalesce(p_cached,false),
    p_cache_key, p_latency_ms, v_cost, v_cheaper, v_reason, coalesce(p_ok,true),
    -- Only a value the caller actually measured, and only if it is a probability. A model that
    -- reports 87 rather than 0.87 is reporting a percentage, so it is normalised; anything outside
    -- 0..100 is not a confidence and is discarded rather than clamped into looking like one.
    case when p_confidence is null then null
         when p_confidence >= 0 and p_confidence <= 1   then p_confidence
         when p_confidence > 1  and p_confidence <= 100 then round(p_confidence / 100.0, 4)
         else null end,
    v_read, v_write);

  return v_cost;
end $function$;

-- CREATE OR REPLACE on a function whose argument list GREW creates a NEW overload; the 14-argument
-- original still exists and still miscosts. Drop it explicitly so there is one implementation.
drop function if exists public.fn_llm_log(text,text,text,text,text,text,text,integer,integer,boolean,text,integer,boolean,numeric);

-- CREATE OR REPLACE preserves the ACL, but this signature is NEW, so it was granted to PUBLIC on
-- creation. Revoke, then grant only what the estate actually calls it with.
revoke all on function public.fn_llm_log(text,text,text,text,text,text,text,integer,integer,boolean,text,integer,boolean,numeric,integer,integer) from public, anon, authenticated;
grant execute on function public.fn_llm_log(text,text,text,text,text,text,text,integer,integer,boolean,text,integer,boolean,numeric,integer,integer) to service_role;

-- THE LEVEL DISTRIBUTION THE SPEC ASKS FOR, MEASURABLE FOR THE FIRST TIME.
-- open router.txt section 2 sets a target: No AI 20% / Cheap 55% / Medium 20% / Premium 5%.
-- It could not be measured, because a tier='none' refusal returns from fn_ai_route without ever
-- reaching fn_llm_log — Level 0 was the one level that left no trace. ai_gateway now logs
-- refusals with tier 'none' and zero tokens, so the denominator is finally the whole picture.
create or replace view public.v_ai_level_distribution as
with r as (
  select case
           when coalesce(tier,'') = 'none'   then '0 no AI'
           when tier = 'small'               then '1 cheap'
           when tier = 'medium'              then '2 medium'
           when tier = 'large'               then '3 premium'
           when tier = 'xlarge'              then '4 human-level'
           else '? unclassified' end as level,
         cost_aed, prompt_tokens, cached_in_tokens
    from public.ai_cost_log
   where occurred_at >= now() - interval '30 days')
select level,
       count(*)                                                        as calls,
       round(100.0 * count(*) / nullif(sum(count(*)) over (), 0), 1)   as pct_of_calls,
       round(sum(cost_aed)::numeric, 2)                                as cost_aed,
       round(100.0 * sum(cost_aed) / nullif(sum(sum(cost_aed)) over (), 0), 1) as pct_of_cost,
       sum(prompt_tokens)                                              as prompt_tokens,
       sum(cached_in_tokens)                                           as from_cache,
       case level when '0 no AI' then 20 when '1 cheap' then 55
                  when '2 medium' then 20 when '3 premium' then 5 else 0 end as spec_target_pct
  from r group by level order by level;

comment on view public.v_ai_level_distribution is
  'open router.txt section 2: the five AI levels and the 20/55/20/5 target distribution, measured against the last 30 days of ai_cost_log. Level 0 counts deterministic refusals, which only became countable when ai_gateway started logging them.';
