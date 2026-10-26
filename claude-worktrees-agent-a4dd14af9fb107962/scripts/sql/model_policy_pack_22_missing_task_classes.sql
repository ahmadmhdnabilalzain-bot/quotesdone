-- The 22 task classes in QuotesDone_AI_AUTONOMY_MODEL_ROUTING_AND_TOOLS_PACK v2026.07.31
-- (04_MODEL_POLICY_BY_TASK_CLASS.csv) that production's model_policy does not carry.
-- Production has 38 classes and 10 of the pack's 32 by exact name; these are the other 22.
--
-- INSERTED INACTIVE, ON PURPOSE, AND NOT ONE EXISTING ROW IS TOUCHED.
--   * fn_ai_route selects `where task_class = v_class and active`, and on a miss falls back to
--     general_drafting while recording 'no policy for "<class>", fell back to general_drafting'.
--     So an inactive row routes exactly what a missing row routes: nothing changes.
--   * Measured before writing: over 30 days llm_calls carries ONE purpose, `visitor_chat`
--     (56 calls, no policy of its own, served by haiku and sonnet-5 via the fallback). Not one
--     of these 22 class names is requested by anything today, so activating them would change
--     no live path either — but each names a paid model, several of which are not in
--     production's current four-model catalogue, and OpenRouter has ~3 days of balance.
--     Choosing to spend on them is the founder's call, so the rows land as policy and wait.
-- Activate one with:  update model_policy set active = true where task_class = '...';
insert into model_policy
  (task_class, tier, model_primary, model_fallback, max_tokens, rationale,
   deterministic_alternative, active, cache_ttl_min)
values
  ('workflow_state_and_permissions','none','none','none',0,
   'Pack: SQL, policies and queues only. Escalation: none.','SQL, policies and queues only',false,0),
  ('money_state_change','none','none','none',0,
   'Pack: Stripe/webhook/ledger code only; model may explain but never post money. Escalation: none.',
   'Stripe/webhook/ledger code only',false,0),
  ('kpi_measurement','none','none','deepseek/deepseek-v4-flash',600,
   'Pack: SQL computes; model diagnoses variance only. Escalation: anthropic/claude-sonnet-5. Batch preferred.',
   'SQL computes the KPI',false,0),
  ('json_extraction_text','small','qwen/qwen3.7-flash','google/gemini-3.1-flash-lite',500,
   'Pack: use response_format/json_schema. Escalation: deepseek/deepseek-v4-flash.',
   'Schema/parser first',false,0),
  ('document_extraction_multimodal','medium','google/gemini-3.5-flash-lite','google/gemini-3.6-flash',1800,
   'Pack: extract once, store structured fields and source coordinates. Escalation: anthropic/claude-sonnet-5. Batch preferred.',
   'File parser/OCR first',false,0),
  ('drawing_and_boq_analysis','medium','google/gemini-3.6-flash','anthropic/claude-sonnet-5',3000,
   'Pack: escalate design calculations and low-confidence interpretations. Escalation: anthropic/claude-opus-5. Batch preferred.',
   'Geometry/parser first',false,0),
  ('redaction_detection','medium','google/gemini-3.5-flash-lite','google/gemini-3.6-flash',1200,
   'Pack: must include independent post-redaction verification and fail closed. Escalation: anthropic/claude-sonnet-5.',
   'Deterministic patterns first',false,0),
  ('inquiry_qualification_conversation','medium','qwen/qwen3.7-plus','deepseek/deepseek-v4-flash',700,
   'Pack: model interprets/rephrases; code controls state and questions. Escalation: anthropic/claude-sonnet-5.',
   'Rules select the next question',false,0),
  ('supplier_communication','medium','qwen/qwen3.7-plus','deepseek/deepseek-v4-flash',700,
   'Pack: use funnel/context fields; keep opt-out and contact-policy gates. Escalation: anthropic/claude-sonnet-5.',
   'Templates first',false,0),
  ('marketing_copy','medium','qwen/qwen3.7-plus','deepseek/deepseek-v4-flash',1200,
   'Pack: Sonnet only for final high-visibility brand/legal review. Escalation: anthropic/claude-sonnet-5. Batch preferred.',
   'Content plan first',false,0),
  ('translation_general','small','qwen/qwen3.7-flash','qwen/qwen3.7-plus',1200,
   'Pack: legal terms use Sonnet and approved bilingual source text. Escalation: anthropic/claude-sonnet-5. Batch preferred.',
   'Translation memory first',false,0),
  ('knowledge_ingestion','medium','google/gemini-3.5-flash-lite','deepseek/deepseek-v4-flash',2200,
   'Pack: expensive research happens offline once, not in live inquiries. Escalation: anthropic/claude-sonnet-5. Batch preferred.',
   'Parser/chunker first',false,0),
  ('knowledge_validation','medium','deepseek/deepseek-v4-flash','anthropic/claude-sonnet-5:batch',1800,
   'Pack: independent reviewer model; never auto-approve regulated knowledge. Escalation: anthropic/claude-opus-5. Batch preferred.',
   'Rules/source check first',false,0),
  ('routine_employee_reasoning','medium','deepseek/deepseek-v4-flash','anthropic/claude-sonnet-5',1000,
   'Pack: replaces the current blanket large-tier agent_reasoning. agent_reasoning is LIVE on anthropic/claude-sonnet-5 and agent_brain is ~93% of OpenRouter spend; switching the company reasoning loop to a cheaper tier is a quality-and-cost decision, so this row exists and does not take over.',
   'Live metrics/rules first',false,0),
  ('department_planning','medium','deepseek/deepseek-v4-flash','anthropic/claude-sonnet-5',1600,
   'Pack: Sonnet for quarterly plans or material underperformance, not every daily plan. Escalation: anthropic/claude-opus-5. Batch preferred.',
   'KPI/root-cause data first',false,0),
  ('legal_analysis','large','anthropic/claude-sonnet-5','anthropic/claude-opus-5',2600,
   'Pack: no autonomous legal conclusion; preserve citations and lawyer escalation. Batch preferred.',
   'Exact official source retrieval first',false,0),
  ('finance_analysis','medium','deepseek/deepseek-v4-flash','anthropic/claude-sonnet-5',1400,
   'Pack: no model-generated accounting entries without deterministic validation. Escalation: anthropic/claude-opus-5. Batch preferred.',
   'SQL/ledger first',false,0),
  ('security_incident_analysis','large','anthropic/claude-sonnet-5','deepseek/deepseek-v4-flash',2200,
   'Pack: severe incidents route to Opus plus founder/human escalation. Escalation: anthropic/claude-opus-5.',
   'Detectors/runbook first',false,0),
  ('engineering_reasoning','medium','deepseek/deepseek-v4-flash','anthropic/claude-sonnet-5',2200,
   'Pack: production changes still require CI and branch protections. Escalation: anthropic/claude-opus-5. Batch preferred.',
   'Tests/logs/static analysis first',false,0),
  ('reflection_and_learning','medium','deepseek/deepseek-v4-flash','anthropic/claude-sonnet-5:batch',1200,
   'Pack: run daily/weekly in batch; avoid a model reflection after every tiny task. Escalation: anthropic/claude-opus-5.',
   'Outcome ledger first',false,0),
  ('executive_report','large','anthropic/claude-sonnet-5:batch','anthropic/claude-sonnet-5',2500,
   'Pack: Opus only for board-level strategic synthesis. Escalation: anthropic/claude-opus-5. Batch preferred.',
   'Metrics and event trace first',false,0),
  ('marketing_image','small','google/gemini-3.1-flash-lite-image','none',0,
   'Pack: exact logos should be composited from assets, never generated by the model. Batch preferred.',
   'Brand template/compositor first',false,0)
on conflict (task_class) do nothing;
