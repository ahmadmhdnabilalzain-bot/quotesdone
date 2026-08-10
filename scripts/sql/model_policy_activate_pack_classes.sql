-- Activate the 22 pack task classes, on models production can actually serve.
--
-- Earlier this session they were inserted inactive and parked as "a money decision for the
-- founder". He then removed that category outright: "there's not a single thing that requires my
-- approval except refunds. Nothing else, literally nothing else." So the decision is made here.
--
-- THE SUBSTITUTION, AND WHY. The pack names deepseek/deepseek-v4-flash, qwen/qwen3.7-flash,
-- qwen/qwen3.7-plus, google/gemini-3.5-flash-lite, google/gemini-3.6-flash and
-- anthropic/claude-opus-5. Production's live 38 policies use exactly four models —
-- anthropic/claude-sonnet-5, ~anthropic/claude-haiku-latest, google/gemini-3.5-flash and
-- google/gemini-3.1-flash-lite — so a policy naming any of the others is a policy that fails at
-- call time. Each is mapped to the nearest model production already runs, AT THE SAME TIER, and
-- the pack's original choice is kept verbatim in rationale so it can be restored the day those
-- models are enabled on the account.
--
-- WHAT STAYS INACTIVE AND WHY: marketing_image alone, because production serves no image model at
-- all and the pack's own note is that logos must be composited from assets, never generated.
-- Activating it would promise a capability that does not exist.
--
-- Nothing here touches the 38 live rows. agent_reasoning keeps claude-sonnet-5: replacing the
-- company's reasoning loop with a cheaper tier is a QUALITY change, and routine_employee_reasoning
-- now exists as the cheaper route for callers that want it, which is the pack's own design.
update model_policy set
  model_primary = case model_primary
    when 'deepseek/deepseek-v4-flash'          then 'google/gemini-3.5-flash'
    when 'qwen/qwen3.7-flash'                  then 'google/gemini-3.1-flash-lite'
    when 'qwen/qwen3.7-plus'                   then '~anthropic/claude-haiku-latest'
    when 'google/gemini-3.5-flash-lite'        then 'google/gemini-3.1-flash-lite'
    when 'google/gemini-3.6-flash'             then 'google/gemini-3.5-flash'
    when 'anthropic/claude-opus-5'             then 'anthropic/claude-sonnet-5'
    when 'anthropic/claude-sonnet-5:batch'     then 'anthropic/claude-sonnet-5'
    else model_primary end,
  model_fallback = case model_fallback
    when 'deepseek/deepseek-v4-flash'          then 'google/gemini-3.5-flash'
    when 'qwen/qwen3.7-flash'                  then 'google/gemini-3.1-flash-lite'
    when 'qwen/qwen3.7-plus'                   then '~anthropic/claude-haiku-latest'
    when 'google/gemini-3.5-flash-lite'        then 'google/gemini-3.1-flash-lite'
    when 'google/gemini-3.6-flash'             then 'google/gemini-3.5-flash'
    when 'anthropic/claude-opus-5'             then 'anthropic/claude-sonnet-5'
    when 'anthropic/claude-sonnet-5:batch'     then 'anthropic/claude-sonnet-5'
    else model_fallback end,
  active = true
where task_class in (
  'workflow_state_and_permissions','money_state_change','kpi_measurement','json_extraction_text',
  'document_extraction_multimodal','drawing_and_boq_analysis','redaction_detection',
  'inquiry_qualification_conversation','supplier_communication','marketing_copy','translation_general',
  'knowledge_ingestion','knowledge_validation','routine_employee_reasoning','department_planning',
  'legal_analysis','finance_analysis','security_incident_analysis','engineering_reasoning',
  'reflection_and_learning','executive_report');

-- quote_comparison now HAS a model-free fallback: supabase/functions/quote_compare/deterministic.ts
-- ranks every quote on stated price, completeness, lead time, warranty and payment terms and is
-- served whenever every model attempt fails or the model returns an empty shortlist. Proved on
-- staging against four real quotes with the model forced to fail: HTTP 200, degraded:true,
-- 3 ranked recommendations. This records the fact; it does not create it.
update model_policy
   set deterministic_alternative =
       'fn_quote_score_json completeness + deterministicCompare() in the quote_compare edge '
       'function: ranks every quote on stated price, completeness, lead time, warranty and '
       'payment terms with no model call, and is served automatically when every model attempt '
       'fails or the model returns an empty shortlist.'
 where task_class = 'quote_comparison';
