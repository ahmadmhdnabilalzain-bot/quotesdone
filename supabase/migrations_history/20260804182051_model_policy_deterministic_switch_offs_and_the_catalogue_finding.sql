-- 4 Aug 2026. What could and could not be taken from 07_REFERENCE_MODEL_ROUTING.sql.
--
-- THE PACK CANNOT BE APPLIED AS WRITTEN. Its header says "fetch current OpenRouter model metadata
-- and adapt". Doing that, against https://openrouter.ai/api/v1/models today, 6 of the 12 model IDs
-- it names DO NOT EXIST:
--
--   NOT FOUND : qwen/qwen3.7-flash · deepseek/deepseek-v4-flash · deepseek/deepseek-v4-flash-0731
--               google/gemini-3.5-flash-lite · google/gemini-3.6-flash · anthropic/claude-opus-5
--   EXISTS    : qwen/qwen3.7-plus · google/gemini-3.5-flash · google/gemini-3.1-flash-lite
--               anthropic/claude-sonnet-5 · anthropic/claude-opus-4.8 · anthropic/claude-haiku-latest
--
-- Applying it verbatim would have pointed 11 of its 16 policy edits at models that 404 - including
-- agent_reasoning, quote_comparison, every classification task and every drafting task - and would
-- have broken the pack's own acceptance gate, "0 active policy rows reference unavailable model
-- IDs". Its instruction to retire anthropic/claude-opus-4.8 is also NOT executed: its replacement,
-- opus-5, does not exist, so retiring 4.8 would leave no xlarge tier at all.
--
-- THE BIGGER FINDING, and the reason the rest of the pack would have changed nothing anyway.
-- ai_gateway's own header records it: "_shared/llm.ts only consults [the policies] when a caller
-- passes taskClass and no caller did." That is still true. Exactly four files in the repository
-- mention task_class - ai_gateway, _shared/llm.ts and two others - and llm.ts passes
-- `task_class: def.taskClass ?? null`, so the value is null unless a caller sets it. Measured:
-- 54 of the 56 rows in llm_calls used anthropic/claude-sonnet-5.
--
--   The 31 rows in model_policy are not the binding constraint. Callers not declaring what they
--   are doing is. Rewriting the policy table changes nothing until task_class is threaded through
--   the call sites, and that is a code change across many functions, not a migration.
--
-- WHAT IS APPLIED: the two edits that are correct regardless of catalogue or caller, because they
-- remove a model from the loop rather than choosing a different one. Both take effect the moment
-- task_class starts flowing, and neither can break anything before then.

update public.model_policy set
  tier = 'none',
  model_primary = 'none',
  model_fallback = null,
  max_tokens = 0,
  deterministic_alternative = 'Run the imported qualification rules against structured inquiry state. kb_stage.decision_rules now holds 12,929 rules across all 67 categories, and as of today kb_stage.records carries all 10,392 decision_rule records including the seven core construction trades.',
  rationale = 'Missing-field detection is deterministic after extraction: the question set and its activation conditions are in the corpus. A model here spends money to re-derive a lookup.'
where task_class = 'missing_fields_detection';

update public.model_policy set
  tier = 'none',
  model_primary = 'none',
  model_fallback = null,
  max_tokens = 0,
  deterministic_alternative = 'Run eligibility filters, the capability crosswalk and a weighted SQL score. A model may explain the trade-offs afterwards as a separate, cheaper task - it must not decide the match.',
  rationale = 'Supplier matching decides who receives a customer''s RFQ. That is an auditable, reproducible decision and must not vary with model temperature. supplier_scoring was already tier=none; this makes the pair consistent.'
where task_class = 'supplier_matching';

-- ------------------------------------------------------------------ make the gate measurable
-- The pack requires "every call logs model, task, agent, tokens, latency, cost, cache and outcome"
-- and "0 active policy rows reference unavailable model IDs". Both are now queries.
create or replace view public.v_model_policy_offcatalog as
select p.task_class, p.tier, p.model_primary, p.model_fallback,
       (r1.model_id is null) as primary_not_in_registry,
       (p.model_fallback is not null and r2.model_id is null) as fallback_not_in_registry
from public.model_policy p
left join public.model_registry r1 on r1.model_id = p.model_primary and r1.active
left join public.model_registry r2 on r2.model_id = p.model_fallback and r2.active
where coalesce(p.active, true)
  and p.model_primary is not null and p.model_primary <> 'none'
  and (r1.model_id is null or (p.model_fallback is not null and r2.model_id is null));
comment on view public.v_model_policy_offcatalog is
  'Acceptance gate "0 active policy rows reference unavailable model IDs", as a query. Target: zero rows. NOTE this checks against model_registry, not against OpenRouter - keeping the registry honest is a separate job.';

create or replace view public.v_llm_calls_without_task_class as
select date_trunc('day', created_at) as day,
       count(*)                                        as calls,
       count(*) filter (where purpose is null)         as no_purpose,
       count(distinct model_used)                      as distinct_models
from public.llm_calls
group by 1 order by 1 desc;
comment on view public.v_llm_calls_without_task_class is
  'Cost-routing reality check. llm_calls has no task_class column at all, so the routing policy cannot be attributed per call. Until it does, every AI-cost acceptance gate in the 31 July pack is unverifiable in both directions. Added 4 Aug 2026.';

grant select on public.v_model_policy_offcatalog, public.v_llm_calls_without_task_class to service_role;;
