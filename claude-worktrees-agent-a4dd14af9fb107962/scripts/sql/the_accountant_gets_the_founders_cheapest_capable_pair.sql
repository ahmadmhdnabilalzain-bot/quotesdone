-- THE ACCOUNTANT GETS THE FOUNDER'S CHEAPEST CAPABLE PAIR. 9 September 2026.
--
-- The founder, 9 Sep 2026, asked for an accountant whose model is "the most affordable and capable
-- model of doing his tasks and responsibilities", then named one: "even gpt luna 5.6 is fine with
-- me as A". So A is openai/gpt-5.6-luna. B is google/gemini-3.1-flash-lite - a DIFFERENT vendor, so
-- one provider outage cannot take both, and a route this estate already runs.
--
-- REGISTRATION ONLY, AND THAT COSTS NOTHING. All 8 rows in llm_route_health are held to 2126-08-15
-- and fn_kernel_paid_provider_gate denies globally on rule 'founder_hold'. Registering a model is a
-- row; calling one is a bill. This is the former, so the routing is correct the day the hold lifts.
--
-- MEASURED, NOT ASSUMED (two free GETs against the OpenRouter catalog, 9 Sep 2026 - /api/v1/models
-- and /api/v1/models/user with app_secrets.openrouter_api_key; 431 catalog models, 428 callable by
-- this account):
--   openai/gpt-5.6-luna   ctx 1,050,000  prompt $0.20/Mtok  completion $1.20/Mtok
--                         input text+image+file, output text, tools yes, structured output yes
--   google/gemini-3.1-flash-lite  already registered since 28 Jul 2026 at $0.25/$1.50 - VERIFIED
--                         below rather than duplicated.
-- Cache read/write prices for luna were NOT measured, so they are left NULL in both tables rather
-- than invented. fn_llm_log already coalesces a null cache rate to in*0.10 and in*1.25, which is
-- exactly the derived convention every 5 Aug row in model_rate used, so a null costs nothing and
-- claims nothing.
--
-- NOT THE BATCH IDS. openai/gpt-5.6-luna:batch and openai/gpt-5.6-luna-pro:batch are both
-- $0.10/$0.60 in the same catalog - half price because batch is asynchronous. An accountant reading
-- a receipt a customer just forwarded is interactive. The exact id below is the interactive one.
--
-- ============================================================================================
-- 1. THE TIER, AND WHAT IT DOES TO THE CHEAPEST-OF-TIER QUERIES
-- ============================================================================================
-- The price ladder in model_registry, measured before this file ran (USD/Mtok in, cheapest first
-- per tier): small flash-lite 0.25 then qwen 0.32 | medium haiku 1.00 then gemini-3.5-flash 1.50 |
-- large sonnet-5 2.00 | xlarge opus-4.8 5.00 then fable-5.1 and gpt-6-astra at 10.00.
--
-- luna is $0.20 in and $1.20 out. That is below EVERY small-tier model on BOTH axes (flash-lite
-- 0.25/1.50, qwen 0.32/1.28). The ladder says small, so small it is - and putting it in medium to
-- dodge the consequence below would be a lie about a price, which is worse than the consequence.
--
-- THE CONSEQUENCE, STATED PLAINLY. Five places pick "the cheapest active+approved model of a tier"
-- rather than a named model. Registering luna at small makes it the answer to the small-tier ones:
--
--   (a) fn_routing_tier_model() maps routing_tier -> registry tier -> cheapest of that tier.
--       'operations_specialist' -> small. Exactly ONE active agent carries that tier: sales_engineer.
--       Its generic-path model therefore moves flash-lite -> luna. This does NOT touch the founder's
--       ruling for that seat: his ruling lives in model_policy.sales_engineer_reasoning
--       (fable-5.1 -> gpt-6-astra), which is untouched below. fn_routing_tier_model only fires when
--       v_generic is true - an UNMAPPED calling function, or a task_class with no policy - and on
--       that path the seat was already getting a cheap small model that nobody ruled on. One cheap
--       small model replaces another, both a fallback nobody designed.
--       accountant is 'analyst_controller' -> medium, and 'ceo' is 'director' -> medium; neither
--       moves, because luna is not the cheapest medium.
--   (b) fn_ai_route's budget DEGRADE branch, for a department over degrade_at_pct: small and medium
--       both degrade to "cheapest small", which becomes luna.
--   (c) fn_ai_route step 9, the silent substitution, for a small-tier policy whose primary is not a
--       registered model. Measured: ZERO active model_policy rows are in that state today (every
--       active primary is either 'none' or one of the eight registered ids), so this changes
--       nothing today and is a statement about tomorrow.
--   (d) The capability-substitution branch orders by tier distance then in_per_mtok_usd, so luna now
--       sorts first inside small. luna does NOT take audio, and that branch filters on the requested
--       capability BEFORE ordering, so an audio task still routes past it to flash-lite or
--       gemini-3.5-flash. A vision-or-tools task at small tier now gets luna.
--   (e) fn_llm_log's could_be_cheaper comparator names the globally cheapest model_rate row and
--       fires at 2x. That reference moves flash-lite 0.9181 -> luna 0.7345 AED/Mtok, so the
--       threshold moves 1.8362 -> 1.4690. No model_rate row sits between those two numbers
--       (qwen 1.1752 is below both; haiku 3.6725 is above both), so the SET of flagged calls does
--       not change - only the model named as the cheaper alternative.
--
-- The two "cheapest medium" consumers - the confidence>=0.95 downgrade and the medium branch of
-- fn_routing_tier_model - keep haiku. Nothing at large or xlarge moves.
--
-- ============================================================================================
-- 2. THE FX CONVENTION - FOUND, NOT INVENTED
-- ============================================================================================
-- Every row already in model_rate names one rate: 3.6725 AED/USD. Verified against the rows rather
-- than assumed: fable-5.1 10.00 USD -> 36.725 AED, opus-4.8 5.00 -> 18.3625, haiku 1.00 -> 3.6725,
-- flash-lite 0.25 -> 0.9181 (0.918125 rounded to 4dp), gemini-3.5-flash 1.50 -> 5.5088. Same rate,
-- rounded to four decimals. luna therefore: 0.20 -> 0.7345 in, 1.20 -> 4.4070 out. Exact at 4dp.
--
-- ============================================================================================
-- 3. THE TASK CLASSES - ONE REUSED, THREE CREATED
-- ============================================================================================
-- The seat's duties, from the founder's brief: read a forwarded receipt into structured fields;
-- classify it against the chart of accounts; prepare a refund recommendation for the CEO; write the
-- weekly report.
--
-- REUSED: finance_analysis. It is the refund recommendation and the seat's analytical work. Reusing
-- it is safe because it is claimed by NOBODY, measured three ways: no fn_task_class row maps any
-- function to it; no file under supabase/functions references it (it appears only in the pack-import
-- SQL that created it and in a scorecard script); and ai_cost_log holds zero rows on it. Its tier
-- stays medium and its max_tokens stays 1400.
--
-- CREATED, because each existing candidate is either claimed by another seat or generic enough that
-- a future caller would silently inherit the accountant's model:
--   accountant_receipt_extraction   - document_extraction is claimed by seven marketplace functions
--       (doc_extract, drawing_boq, drawing_redact, quote_extract, license_extract, extract_text,
--       capability_agent) and repointing it would move all of them. document_extraction_multimodal
--       is unclaimed but its name promises a general capability, so claiming it for one seat is the
--       same silent-inheritance trap in a different table.
--   accountant_expense_classification - category_classification is claimed by category_provision and
--       means marketplace product categories, not a chart of accounts.
--   accountant_weekly_report - executive_report is unclaimed but sits at large/sonnet-5 and is named
--       for the CEO's kind of output; repointing it to a $0.20 model would be a quiet downgrade of
--       whoever writes the first executive report.
-- The naming follows the convention the other three seats already use: ceo_strategic_planning,
-- ceo_approval_decision, customer_portal_assistant, sales_engineer_reasoning.
--
-- max_tokens is non-zero on every row. 17 existing rows carry 0 and `??` does not treat 0 as absent,
-- so maxTok computes to 0 and the call can emit nothing. Not repeated here.
--
-- DELIBERATELY NOT TOUCHED, seat by seat:
--   ceo             - ceo_strategic_planning, ceo_approval_decision (fable-5.1 -> gpt-6-astra)
--   sales_engineer  - sales_engineer_reasoning (fable-5.1 -> gpt-6-astra)
--   customer_support- customer_portal_assistant (fable-5.1 -> gpt-6-astra), and the classes settled
--                     for support the day before: support_ai, visitor_chat, wa_inbound,
--                     customer_communication, inbound_email, resend_inbound, email_triage,
--                     intent_detection
--   shared/marketplace - document_extraction, document_extraction_multimodal, json_extraction,
--                     category_classification, executive_report, quote_comparison, agent_reasoning,
--                     routine_employee_reasoning, and the 'none' deterministic classes the
--                     accountant SHOULD keep hitting: vat_calculation, currency_conversion,
--                     kpi_calculation, money_state_change, duplicate_detection, approval_threshold.
--
-- ============================================================================================
-- 4. THE REWRITE THE SALES ENGINEER WALKED INTO, CHECKED FOR THIS TIER
-- ============================================================================================
-- fn_ai_route rewrites task_class agent_reasoning -> routine_employee_reasoning, but ONLY for
-- `v_rtier = 'operations_specialist'`. Read in the live function body, not a migration: the guard is
-- a single equality and the comment above it says director and analyst_controller stay on purpose.
-- accountant is analyst_controller, so that rewrite CANNOT fire for it.
--
-- The path that CAN silently take the founder's model away from this seat is the other one:
-- fn_routing_tier_model, which for analyst_controller resolves to the cheapest MEDIUM model - haiku
-- today - and overwrites v_pol.model_primary whenever v_generic is true. The accountant edge
-- function makes no model call today and has no fn_task_class row, so any future call it makes with
-- no explicit task_class lands on exactly that path.
-- The row in model_policy_by_identity below closes it: fn_ai_route applies the identity row FIRST
-- and the routing_tier branch is guarded by `v_idp.identity_key is null`, so an identity row for
-- 'accountant' makes the tier default unreachable for this seat. No fn_task_class row is added,
-- because supabase/functions/accountant/index.ts calls no model - mapping it would describe work
-- that does not happen.

begin;

-- 1. model_registry ------------------------------------------------------------------------------
insert into model_registry (
  model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd,
  cache_read_per_mtok_usd, cache_write_per_mtok_usd,
  supports_cache, supports_streaming, supports_vision, supports_audio, supports_tools,
  context_len, approved, active, quality_score, note, updated_at)
values (
  'openai/gpt-5.6-luna', 'openai', 'small', 0.20, 1.20,
  null, null,
  false, true, true, false, true,
  1050000, true, true, null,
  'Founder''s ruling 9 Sep 2026: the accountant seat''s model A - "the most affordable and capable '
  || 'model of doing his tasks and responsibilities", then "even gpt luna 5.6 is fine with me as A". '
  || 'At $0.20/$1.20 it is cheaper than every other small-tier model on BOTH axes, so it becomes the '
  || 'answer to every "cheapest active+approved small" query: fn_routing_tier_model for '
  || 'operations_specialist (sales_engineer''s generic path only - his ruled class '
  || 'sales_engineer_reasoning is untouched), fn_ai_route''s degrade-one-tier branch, step 9''s '
  || 'substitution, and the capability-substitution ordering. ~40x cheaper than the fable-5.1 / '
  || 'gpt-6-astra pair the CEO and Sales Engineer run. NO AUDIO: the capability branch will correctly '
  || 'route an audio task past it. Cache prices were not measured, so they are null rather than '
  || 'guessed. NOT the :batch id at $0.10/$0.60 - batch is asynchronous and this seat is interactive.',
  now())
on conflict (model_id) do update set
  provider = excluded.provider, tier = excluded.tier,
  in_per_mtok_usd = excluded.in_per_mtok_usd, out_per_mtok_usd = excluded.out_per_mtok_usd,
  cache_read_per_mtok_usd = excluded.cache_read_per_mtok_usd,
  cache_write_per_mtok_usd = excluded.cache_write_per_mtok_usd,
  supports_cache = excluded.supports_cache, supports_streaming = excluded.supports_streaming,
  supports_vision = excluded.supports_vision, supports_audio = excluded.supports_audio,
  supports_tools = excluded.supports_tools, context_len = excluded.context_len,
  approved = excluded.approved, active = excluded.active,
  note = excluded.note, updated_at = now();

-- google/gemini-3.1-flash-lite is ALREADY registered (28 Jul 2026). Verified, not duplicated - this
-- raises rather than silently inserting a second row if the estate ever loses it.
do $$
begin
  if not exists (select 1 from model_registry
                  where model_id = 'google/gemini-3.1-flash-lite' and active and approved) then
    raise exception 'google/gemini-3.1-flash-lite is not an active approved model_registry row; the '
                    'accountant fallback would be unreachable';
  end if;
end $$;

-- 2. model_rate ----------------------------------------------------------------------------------
-- 3.6725 AED/USD, the rate every existing row in this table names.
insert into model_rate (
  model, tier, in_aed_per_mtok, out_aed_per_mtok,
  cache_read_aed_per_mtok, cache_write_aed_per_mtok,
  usd_per_m_prompt, usd_per_m_output, id_verified, source_url, verified_at, note)
values (
  'openai/gpt-5.6-luna', 'small', 0.7345, 4.4070,
  null, null,
  0.20, 1.20, true, 'https://openrouter.ai/api/v1/models', date '2026-09-09',
  'Converted at 3.6725 AED/USD, the same rate every other row in this table names. USD prices read '
  || 'from the OpenRouter catalog on 9 Sep 2026 and ALLOWED for this account. Cheapest input rate in '
  || 'the fleet, which moves fn_llm_log''s could_be_cheaper reference from flash-lite 0.9181 to '
  || '0.7345 and its 2x threshold from 1.8362 to 1.4690; no model_rate row sits between those, so '
  || 'the set of flagged calls is unchanged and only the named alternative moves. Cache rates were '
  || 'not measured and are null; fn_llm_log coalesces a null to in*0.10 and in*1.25, which is the '
  || 'same derived convention the 5 Aug rows used.')
on conflict (model) do update set
  tier = excluded.tier,
  in_aed_per_mtok = excluded.in_aed_per_mtok, out_aed_per_mtok = excluded.out_aed_per_mtok,
  cache_read_aed_per_mtok = excluded.cache_read_aed_per_mtok,
  cache_write_aed_per_mtok = excluded.cache_write_aed_per_mtok,
  usd_per_m_prompt = excluded.usd_per_m_prompt, usd_per_m_output = excluded.usd_per_m_output,
  id_verified = excluded.id_verified, source_url = excluded.source_url,
  verified_at = excluded.verified_at, note = excluded.note;

-- 3. model_policy --------------------------------------------------------------------------------
insert into model_policy (task_class, tier, model_primary, model_fallback, max_tokens, cache_ttl_min,
                          active, rationale)
values
  ('accountant_receipt_extraction', 'small', 'openai/gpt-5.6-luna', 'google/gemini-3.1-flash-lite',
   1200, 0, true,
   'The accountant reads a forwarded receipt - image or PDF - into structured fields. Both models '
   || 'take text+image+file and carry ~1M context, so a long multi-page attachment fits without '
   || 'chunking. NEW rather than a reuse of document_extraction, which seven marketplace functions '
   || 'already own, or of document_extraction_multimodal, whose generic name would hand the '
   || 'accountant''s model to whoever calls it next. 1200 output tokens is a receipt''s worth of '
   || 'fields, not a document.'),
  ('accountant_expense_classification', 'small', 'openai/gpt-5.6-luna', 'google/gemini-3.1-flash-lite',
   400, 0, true,
   'Classifying one expense against the chart of accounts: short input, one account code and a '
   || 'confidence out. NEW rather than a reuse of category_classification, which category_provision '
   || 'owns and which means marketplace product categories, not accounting codes.'),
  ('accountant_weekly_report', 'medium', 'openai/gpt-5.6-luna', 'google/gemini-3.1-flash-lite',
   2000, 0, true,
   'The weekly financial report. Medium tier because the report is consequential enough that a '
   || 'missing-model substitution should land on haiku rather than on the cheapest thing in the '
   || 'fleet, while the primary stays the founder''s choice. NEW rather than a reuse of '
   || 'executive_report, which sits at large/sonnet-5 and is named for the CEO''s output - '
   || 'repointing it would quietly downgrade the first executive report anyone writes.')
on conflict (task_class) do update set
  tier = excluded.tier, model_primary = excluded.model_primary,
  model_fallback = excluded.model_fallback, max_tokens = excluded.max_tokens,
  cache_ttl_min = excluded.cache_ttl_min, active = excluded.active,
  rationale = excluded.rationale;

-- REUSED. finance_analysis carries the refund recommendation the accountant prepares for the CEO,
-- and the seat's analytical work generally. Claimed by nobody: no fn_task_class row, no reference in
-- supabase/functions, zero ai_cost_log rows. Tier and max_tokens unchanged.
update model_policy
   set model_primary  = 'openai/gpt-5.6-luna',
       model_fallback = 'google/gemini-3.1-flash-lite',
       rationale      = 'The accountant''s analysis, including the refund recommendation he prepares '
         || 'for the CEO - the CEO decides, the accountant recommends. Moved to the founder''s '
         || 'accountant pair on 9 Sep 2026 rather than creating a fourth accountant_* class, because '
         || 'this class is exactly this seat''s domain and was claimed by nobody: no fn_task_class '
         || 'row mapped a function to it, no edge function referenced it, and ai_cost_log held zero '
         || 'rows on it. Tier stays medium and max_tokens stays 1400.',
       active = true
 where task_class = 'finance_analysis';

-- 4. model_policy_by_identity --------------------------------------------------------------------
-- Closes the one path that could take the founder's model away from this seat: fn_routing_tier_model
-- resolves analyst_controller -> cheapest medium -> haiku whenever v_generic is true. fn_ai_route
-- applies this row first and guards that branch with `v_idp.identity_key is null`, so this makes the
-- tier default unreachable for 'accountant'.
insert into model_policy_by_identity (
  identity_key, scope, department, title, deterministic_first,
  primary_model, fallback_model, escalation_model, max_output_tokens,
  reasoning_effort, manager, authority_tier, note)
values (
  'accountant', 'current_agent', 'finance', 'Accountant', 'Yes',
  'openai/gpt-5.6-luna', 'google/gemini-3.1-flash-lite', null, 1400,
  '', '', '',
  'Founder''s ruling 9 Sep 2026. Role default for the generic path only - task_class routing '
  || 'overrides it, which is the same precedence every other row in this table states. It exists to '
  || 'stop fn_routing_tier_model resolving analyst_controller to the cheapest medium model (haiku) '
  || 'on an unmapped call and quietly replacing the founder''s choice. deterministic_first stays Yes: '
  || 'ledger posting, VAT and currency conversion are model_policy tier ''none'' and must stay there.')
on conflict (identity_key, scope) do update set
  department = excluded.department, title = excluded.title,
  deterministic_first = excluded.deterministic_first,
  primary_model = excluded.primary_model, fallback_model = excluded.fallback_model,
  escalation_model = excluded.escalation_model, max_output_tokens = excluded.max_output_tokens,
  note = excluded.note;

commit;
