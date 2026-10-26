-- ---------------------------------------------------------------------------
-- THE UNLOCK: classify by CALLING FUNCTION, not by call site.
--
-- The reason model_policy has never executed is that _shared/llm.ts only consults
-- fn_select_model when a caller passes taskClass, and none of the ~68 LLM-calling
-- functions does. Editing 68 call sites two days before launch is not sane.
--
-- _shared/llm.ts already derives the calling function name (guessFn()). So the map
-- below lets the SERVER classify by that name. One client change activates policy
-- routing for the entire company, and any function can still override by passing an
-- explicit taskClass.
-- ---------------------------------------------------------------------------

create table if not exists fn_task_class (
  fn          text primary key,
  task_class  text not null,
  note        text,
  active      boolean not null default true,
  updated_at  timestamptz not null default now()
);
alter table fn_task_class enable row level security;
revoke all on fn_task_class from public, anon, authenticated;

-- Three classes the existing 26 did not cover.
insert into model_policy (task_class, tier, model_primary, model_fallback, max_tokens, rationale, active) values
 ('agent_reasoning','large','anthropic/claude-sonnet-5','anthropic/claude-opus-4.8',1700,
  'An AI employee reasoning over its own context, memory and live numbers to decide and act.',true),
 ('general_drafting','medium','~anthropic/claude-haiku-latest','anthropic/claude-sonnet-5',900,
  'Safe default for anything unmapped. Medium tier so an unclassified caller degrades gracefully rather than silently getting the cheapest or the dearest model.',true),
 ('health_ping','small','google/gemini-3.1-flash-lite','qwen/qwen3.7-plus',32,
  'Liveness probe against a provider. Needs a token or two, never reasoning.',true)
on conflict (task_class) do update set tier=excluded.tier, model_primary=excluded.model_primary,
  model_fallback=excluded.model_fallback, max_tokens=excluded.max_tokens, rationale=excluded.rationale, active=true;

-- Point the existing classes at the new cheap tier. Before this every class named
-- Sonnet or Opus because nothing cheaper was approved to exist.
update model_policy set model_primary='google/gemini-3.1-flash-lite', model_fallback='qwen/qwen3.7-plus'
 where tier='small' and active;
update model_policy set model_primary='~anthropic/claude-haiku-latest', model_fallback='anthropic/claude-sonnet-5'
 where tier='medium' and active and task_class <> 'customer_communication';
-- Customers hear this one. Keep a cache-capable model but do not drop below Haiku.
update model_policy set model_primary='~anthropic/claude-haiku-latest', model_fallback='anthropic/claude-sonnet-5'
 where task_class='customer_communication';
update model_policy set model_primary='anthropic/claude-sonnet-5', model_fallback='anthropic/claude-opus-4.8'
 where tier='large' and active;

insert into fn_task_class (fn, task_class, note) values
 -- ---- SMALL: classification, extraction, routing. 8x cheaper input than today. ----
 ('route_inquiry','rfq_routing','Routes an RFQ to a domain specialist. Selection, not reasoning.'),
 ('quote_extract','json_extraction','Pulls a known shape out of a supplier quotation.'),
 ('license_extract','json_extraction','Trade licence fields.'),
 ('inquiry_parse','json_extraction','Structured parse of an inbound inquiry.'),
 ('profile_ai','json_extraction','Supplier profile fields.'),
 ('finance_doc','json_extraction','Invoice and receipt fields.'),
 ('enrich_capability','json_extraction','Supplier capability summary from known fields.'),
 ('canon_eval','json_extraction','Grades a canon answer against a rubric.'),
 ('knowledge_exam','json_extraction','Marks exam answers to a fixed schema.'),
 ('category_provision','category_classification','Picks one of 86 known categories.'),
 ('category_reqs','missing_fields_detection','Compares against the category required-field list.'),
 ('inquiry_intake','missing_fields_detection','Finds what the customer has not told us yet.'),
 ('capability_agent','supplier_matching','Ranks ties after SQL has done the matching.'),
 ('supplier_review','supplier_matching','Reviews a supplier against capability evidence.'),
 ('prompt_gate','intent_detection','Short guard classification.'),
 ('email_triage','intent_detection','Classifies an inbound email. Short, high volume, no reasoning depth.'),
 ('resend_inbound','intent_detection','Classifies inbound mail webhooks.'),
 ('doc_extract','ocr_cleanup','Tidies extracted document text.'),
 ('extract_text','ocr_cleanup','Text tidying.'),
 ('transcribe','ocr_cleanup','Transcript cleanup.'),
 ('drawing_redact','ocr_cleanup','Identifies regions to redact.'),
 ('ai_health','health_ping','Provider liveness only.'),

 -- ---- MEDIUM: drafting, summarising, anything a customer reads. ----
 ('site_assistant','customer_communication','Public website chat. Tone matters, errors are customer-visible.'),
 ('wa_inbound','customer_communication','WhatsApp replies.'),
 ('support_ai','customer_communication','Retired 410 stub; mapped for completeness.'),
 ('messages_api','customer_communication','In-app messaging.'),
 ('secretary_act','customer_communication','Drafts on behalf of the company.'),
 ('copilot','customer_communication','Founder-facing assistant.'),
 ('marketing_draft','content_drafting','Brand-voice writing.'),
 ('blog_weekly','content_drafting','Long-form brand writing.'),
 ('seo_gen','content_drafting','Page copy.'),
 ('content_revise','content_drafting','Revision pass.'),
 ('translate_html','content_drafting','Translation.'),
 ('translate_page','content_drafting','Translation.'),
 ('doc_render','content_drafting','Document assembly.'),
 ('os_pages','content_drafting','OS page copy.'),
 ('prompt_improve','content_drafting','Rewrites prompts.'),
 ('agent_autogen','content_drafting','Writes new agent definitions.'),
 ('ea_meeting_summary','content_drafting','Meeting summary.'),
 ('archive_rfq','content_drafting','Summarises an RFQ before archiving.'),
 ('cost_snapshot','content_drafting','Narrates the cost snapshot.'),
 ('gen_category_knowledge','knowledge_research','Builds category knowledge. Cacheable and repeated across 86 fixed categories.'),
 ('gen_category_personas','knowledge_research','Category personas.'),
 ('kb_deepen','knowledge_research','Deepens category knowledge.'),
 ('kb_fill_gap','knowledge_research','Fills an identified knowledge gap.'),
 ('kb_research_test','knowledge_research','Research harness.'),
 ('learn_gaps','knowledge_research','Reviews intake checklists.'),
 ('quote_compare','quote_comparison','Normalises non-comparable scopes.'),
 ('quote_review','quote_comparison','Reviews a quotation.'),
 ('inquiry_ai','procurement_reasoning','Trade-off reasoning inside one category.'),
 ('drawing_boq','procurement_reasoning','Bill of quantities from a drawing.'),
 ('project_consultant','procurement_reasoning','Scoping advice.'),
 ('analytics_recommend','procurement_reasoning','Recommendations from analytics.'),
 ('boost_recommend','procurement_reasoning','Boost recommendations.'),

 -- ---- LARGE: genuine reasoning, planning, arbitration, legal exposure. ----
 ('agent_brain','agent_reasoning','An AI employee thinking. The single biggest cost line in the company.'),
 ('cos_execute','agent_reasoning','Chief of Staff carrying out a task.'),
 ('agent_act','agent_reasoning','Agent action execution.'),
 ('agents','agent_reasoning','Agent runtime.'),
 ('exec_agents','agent_reasoning','Executive advisory agents.'),
 ('reflect','agent_reasoning','Reflection over outcomes.'),
 ('dept_learn','agent_reasoning','Department lesson extraction.'),
 ('dept_plan','chief_of_staff_decision','A department head planning its own next moves against company goals.'),
 ('intent_router','chief_of_staff_decision','Decomposes a founder objective across departments.'),
 ('orchestrate','chief_of_staff_decision','Cross-department orchestration.'),
 ('legal_review','contract_analysis','Legal exposure justifies the cost.')
on conflict (fn) do update set task_class=excluded.task_class, note=excluded.note, active=true, updated_at=now();

comment on table fn_task_class is
  'Maps an edge function name to a model_policy task_class so routing works without editing call sites. _shared/llm.ts derives the function name already; the server does the classification. An explicit taskClass from the caller always wins over this map.';