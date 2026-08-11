CREATE OR REPLACE FUNCTION public.fn_llm_log(p_fn text, p_dept text, p_agent text, p_task_class text, p_model text, p_because text, p_tier text, p_prompt_tokens integer, p_output_tokens integer, p_cached boolean, p_cache_key text, p_latency_ms integer, p_ok boolean, p_confidence numeric DEFAULT NULL::numeric, p_cached_in integer DEFAULT 0, p_cache_write integer DEFAULT 0)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_cost numeric := 0; v_in numeric; v_out numeric; v_cr numeric; v_cw numeric;
        v_cheaper boolean := false; v_reason text; v_alt text; v_class text;
        v_plain int; v_read int; v_write int;
        -- Added 11 Aug 2026 for the could_be_cheaper rewrite below.
        v_alt_model text; v_alt_rate numeric; v_used_rate numeric;
begin
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
  -- THE WASTE DETECTOR NEVER LOOKED AT THE MODEL DOING THE SPENDING (fixed 11 Aug 2026).
  --
  -- The comparator was hardcoded to claude-sonnet-5 as the CHEAP side of the test:
  --     exists (... alt.model = 'anthropic/claude-sonnet-5'
  --              where used.model = p_model and alt.in_aed_per_mtok < used.in_aed_per_mtok)
  -- so it could only ever fire for a model more expensive than sonnet-5, and by the input-rate
  -- ladder in model_rate that is exactly one model:
  --     flash-lite 0.92 < qwen 1.18 < haiku 3.67 < gemini-flash 5.51 < SONNET-5 7.35 < opus 18.36
  -- That was a reasonable rule when sonnet-5 was the cheap tier. It is not one now.
  --
  -- Measured over the 7 days to 11 Aug: could_be_cheaper fired on 179 calls - 175 of them on
  -- gemini-3.1-flash-lite (the CHEAPEST model in the fleet, 1.1% of spend, flagged by the
  -- deterministic branch above), 4 on opus, and ZERO on claude-sonnet-5 across 622 calls carrying
  -- 84% of all spend. The one field built to find waste was structurally blind to it.
  --
  -- Now it asks the actual question - is there a materially cheaper model than the one used - and
  -- names the cheapest so the reason is actionable rather than a boolean. The 2x threshold is
  -- deliberate: qwen at 1.18 against flash-lite at 0.92 is a 1.3x difference and flagging it would
  -- be noise, while sonnet-5 against flash-lite is 8x and is the finding.
  elsif not coalesce(p_cached,false) then
    select mr.model, mr.in_aed_per_mtok into v_alt_model, v_alt_rate
      from model_rate mr
     where mr.in_aed_per_mtok is not null
     order by mr.in_aed_per_mtok asc
     limit 1;
    select mr.in_aed_per_mtok into v_used_rate from model_rate mr where mr.model = p_model;
    if v_alt_model is not null and v_used_rate is not null
       and v_alt_rate * 2 <= v_used_rate then
      v_cheaper := true;
      v_reason := v_alt_model || ' costs ' || round(v_used_rate / nullif(v_alt_rate,0), 1)
               || 'x less on input than ' || p_model
               || ' (' || v_alt_rate || ' vs ' || v_used_rate || ' AED/Mtok). '
               || 'Whether it is good enough for this task class is a policy decision, not a fact - '
               || 'this flag is the question, not the answer.';
    end if;
  end if;

  insert into ai_cost_log (fn, dept_key, agent_key, task_class, model_used, model_selected_because,
    tier, prompt_tokens, output_tokens, cached, cache_hit_key, latency_ms, cost_aed,
    could_be_cheaper, cheaper_reason, ok, confidence, cached_in_tokens, cache_write_tokens)
  values (p_fn, p_dept, p_agent, v_class, p_model, p_because, p_tier,
    coalesce(p_prompt_tokens,0), coalesce(p_output_tokens,0), coalesce(p_cached,false),
    p_cache_key, p_latency_ms, v_cost, v_cheaper, v_reason, coalesce(p_ok,true),
    case when p_confidence is null then null
         when p_confidence >= 0 and p_confidence <= 1   then p_confidence
         when p_confidence > 1  and p_confidence <= 100 then round(p_confidence / 100.0, 4)
         else null end,
    v_read, v_write);

  return v_cost;
end $function$

