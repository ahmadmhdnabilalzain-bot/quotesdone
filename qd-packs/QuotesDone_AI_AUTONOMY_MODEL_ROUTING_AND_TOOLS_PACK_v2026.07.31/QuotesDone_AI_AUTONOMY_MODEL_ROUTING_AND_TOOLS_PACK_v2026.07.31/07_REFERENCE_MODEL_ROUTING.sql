-- QuotesDone reference migration: AI model and task-routing update
-- DO NOT APPLY BLINDLY. Claude must inspect the live model_registry/model_policy schema,
-- fetch current OpenRouter model metadata, benchmark each task class in staging, and adapt.
-- Prices below reflect OpenRouter pages reviewed on 31 July 2026.

begin;

-- Refresh catalogue. Add supports_* columns only if they exist in the live schema.
insert into public.model_registry
(model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd, supports_cache, context_len, approved, active, note)
values
('qwen/qwen3.7-flash','qwen','small',0.03,0.13,false,1000000,true,true,
 'Canary then primary for high-volume routing/extraction. Verify tool/vision capability from OpenRouter model metadata.'),
('deepseek/deepseek-v4-flash','deepseek','medium',0.09,0.18,true,1050000,true,true,
 'Recommended routine employee reasoning tier. Benchmark tool use and structured output per task.'),
('deepseek/deepseek-v4-flash-0731','deepseek','medium',0.14,0.28,true,1000000,true,false,
 'New 31-Jul revision. Start disabled; enable as 5-10% canary after benchmark.'),
('google/gemini-3.5-flash-lite','google','medium',0.30,2.50,true,1050000,true,true,
 'Focused multimodal document/extraction agent.'),
('google/gemini-3.6-flash','google','large',1.50,7.50,true,1050000,true,true,
 'Complex multimodal and drawing/document reasoning.'),
('anthropic/claude-sonnet-5','anthropic','large',2.00,10.00,true,1000000,true,true,
 'Professional judgment/reviewer tier; not the default for every employee thought.'),
('anthropic/claude-opus-5','anthropic','xlarge',5.00,25.00,true,1000000,true,true,
 'Rare high-impact escalation tier.')
on conflict (model_id) do update set
 provider=excluded.provider, tier=excluded.tier,
 in_per_mtok_usd=excluded.in_per_mtok_usd,
 out_per_mtok_usd=excluded.out_per_mtok_usd,
 context_len=excluded.context_len,
 approved=excluded.approved, active=excluded.active,
 note=excluded.note, updated_at=now();

-- Retire obsolete exact model IDs only after every active policy has been migrated.
update public.model_registry set active=false, note=coalesce(note,'')||' | superseded by Opus 5'
where model_id='anthropic/claude-opus-4.8';

-- Key policy changes. Adapt names to the live table.
update public.model_policy set
 tier='medium', model_primary='deepseek/deepseek-v4-flash',
 model_fallback='anthropic/claude-sonnet-5', max_tokens=1000,
 rationale='Routine employee reasoning uses internal data/rules first and a cost-efficient reasoning model. Sonnet is escalation, not default.'
where task_class='agent_reasoning';

update public.model_policy set
 tier='medium', model_primary='deepseek/deepseek-v4-flash',
 model_fallback='anthropic/claude-sonnet-5', max_tokens=1600
where task_class in ('procurement_reasoning','quote_comparison','knowledge_research');

update public.model_policy set
 tier='small', model_primary='qwen/qwen3.7-flash',
 model_fallback='google/gemini-3.1-flash-lite', max_tokens=500
where task_class in ('rfq_routing','json_extraction','category_classification','intent_detection');

update public.model_policy set
 tier='medium', model_primary='qwen/qwen3.7-plus',
 model_fallback='anthropic/claude-sonnet-5', max_tokens=900
where task_class in ('customer_communication','content_drafting','general_drafting');

update public.model_policy set
 tier='large', model_primary='anthropic/claude-sonnet-5',
 model_fallback='anthropic/claude-opus-5', max_tokens=2400
where task_class in ('chief_of_staff_decision','contract_analysis');

-- Missing-field logic should normally be deterministic after message extraction.
update public.model_policy set
 tier='none', deterministic_alternative='Run imported qualification rules against structured inquiry state',
 max_tokens=0
where task_class='missing_fields_detection';

-- Supplier matching should be deterministic; model only explains trade-offs in a separate task.
update public.model_policy set
 tier='none', deterministic_alternative='Run eligibility filters, capability crosswalk and weighted SQL score',
 max_tokens=0
where task_class='supplier_matching';

commit;

-- Separate implementation requirements:
-- 1. Add a canary percentage and benchmark status to model_registry/model_policy.
-- 2. Store pricing modality (token/second/image) rather than forcing ASR/image pricing into token fields.
-- 3. Pass OpenRouter provider ZDR/data-collection controls for sensitive tasks.
-- 4. Add session_id for multi-turn prompt-cache stickiness.
-- 5. Migrate resend_inbound's direct chat-completion call through ai_gateway.
-- 6. Use provider health endpoints instead of LLM health pings.
-- 7. Execute batch-compatible nightly/weekly work through :batch model variants.
