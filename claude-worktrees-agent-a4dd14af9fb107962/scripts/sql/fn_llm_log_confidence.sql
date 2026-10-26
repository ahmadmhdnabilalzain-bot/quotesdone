-- THE QUALITY AXIS WAS NEVER RECORDABLE. ai_cost_log has a `confidence` column; every one of the
-- 1,614 model calls in the last 30 days carries latency_ms and cost_aed, and NOT ONE carries a
-- confidence -- because fn_llm_log has thirteen parameters and none of them is quality, so the
-- INSERT could not set the column whatever the caller knew.
--
-- And the caller did know. _shared/llm.ts already sends `confidence` to the gateway, ai_gateway
-- already forwards it to the router at p_confidence, and on the level-0 path the gateway formats a
-- genuinely measured retrieval confidence into the p_because TEXT -- "Answered with no model: faq
-- (confidence 0.82)" -- because there was no numeric slot to put it in. A measured value stringified
-- into a prose column is the same defect as an addressee with no employee: the thing exists, it is
-- correct, and it is addressed to somewhere nothing reads.
--
-- This adds the slot. It does NOT invent a quality score: p_confidence is null unless the caller
-- measured one, so a model with no self-reported confidence keeps a null and s25-quality-latency-cost
-- stays red for that model. That is the honest state, and it is why the parameter defaults to null
-- rather than to a number.
--
-- The 13-argument signature is DROPPED rather than left beside the new one. A 14-argument version
-- whose last parameter defaults would make every existing 13-named-argument call ambiguous (42725,
-- "function is not unique"), so keeping both would break the only caller there is. ai_gateway is
-- that caller -- the single other match in the schema is a COMMENT inside fn_os_portals_gates.

drop function if exists public.fn_llm_log(text, text, text, text, text, text, text, integer, integer, boolean, text, integer, boolean);

create or replace function public.fn_llm_log(
  p_fn text, p_dept text, p_agent text, p_task_class text, p_model text, p_because text,
  p_tier text, p_prompt_tokens integer, p_output_tokens integer, p_cached boolean,
  p_cache_key text, p_latency_ms integer, p_ok boolean, p_confidence numeric default null)
returns numeric
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_cost numeric := 0; v_in numeric; v_out numeric; v_cheaper boolean := false;
        v_reason text; v_alt text; v_class text;
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

  if not coalesce(p_cached,false) then
    select in_aed_per_mtok, out_aed_per_mtok into v_in, v_out from model_rate where model = p_model;
    if v_in is not null then
      v_cost := round( coalesce(p_prompt_tokens,0)/1000000.0 * v_in
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
    could_be_cheaper, cheaper_reason, ok, confidence)
  values (p_fn, p_dept, p_agent, v_class, p_model, p_because, p_tier,
    coalesce(p_prompt_tokens,0), coalesce(p_output_tokens,0), coalesce(p_cached,false),
    p_cache_key, p_latency_ms, v_cost, v_cheaper, v_reason, coalesce(p_ok,true),
    -- Only a value the caller actually measured, and only if it is a probability. A model that
    -- reports 87 rather than 0.87 is reporting a percentage, so it is normalised; anything outside
    -- 0..100 is not a confidence and is discarded rather than clamped into looking like one.
    case when p_confidence is null then null
         when p_confidence >= 0 and p_confidence <= 1   then p_confidence
         when p_confidence > 1  and p_confidence <= 100 then round(p_confidence / 100.0, 4)
         else null end);

  return v_cost;
end $function$;

revoke execute on function public.fn_llm_log(text, text, text, text, text, text, text, integer, integer, boolean, text, integer, boolean, numeric) from public, anon, authenticated;
grant execute on function public.fn_llm_log(text, text, text, text, text, text, text, integer, integer, boolean, text, integer, boolean, numeric) to service_role;
