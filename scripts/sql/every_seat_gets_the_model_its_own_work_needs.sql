-- EVERY SEAT GETS THE MODEL ITS OWN WORK NEEDS.
-- it_engineer, 23 September 2026.
--
-- ═══ THE RULING THIS FILE IMPLEMENTS ════════════════════════════════════════════════════════════
--
-- The founder, 23 Sep 2026, recorded as founder_instruction 841, in his own words:
--
--   "the primary model for the comparison would be Qwen 3.8 max and use GLM 5.3 flash whenever,
--    wherever it's possible as a primary model. And for the CEO, again, Qwen 3.8 max. So this will
--    be plan A for everyone, except the stuff that doesn't require reasoning a lot - GLM 5.3 flash
--    again. We want to cut cost as much as possible. For plan B, for everyone that requires
--    reasoning, it's going to be Opus; and for who doesn't need reasoning then GLM 5.3 flash."
--
-- He REFINED it the same day, recorded as founder_instruction 844, and the refinement moves the line:
--
--   "whenever it's something related to our operation internally, GLM 5.3 Flash can do it, all good.
--    When it comes to customers, Qwen 3.8 Max is fine. So whenever we have document readings,
--    interactions with customers, stuff like that... anything that involves Arabic, keep it Qwen 3.8
--    Max or GPT Sol 5.6, depending which one is cheaper."
--
-- So the line is drawn by AUDIENCE, not by how hard the thinking is. The matrix is two rows:
--
--                                              PLAN A (primary)         PLAN B (fallback/escalate)
--   customer-facing, Arabic-capable, document-
--   reading, or a judgement                    qwen/qwen3.8-max-0902    anthropic/claude-opus-5.5
--   purely internal                            z-ai/glm-5.3-flash       google/gemini-3.8-flash
--   speech_transcription (audio, no choice)    google/gemini-3.1-...    google/gemini-3.5-flash
--
-- THE TIE-BREAK HE ASKED FOR, MEASURED. "Qwen 3.8 Max or GPT Sol 5.6, depending which one is
-- cheaper", read live from the catalogue 23 Sep 2026, USD per Mtok:
--
--   model                   in     out    cache read   ctx        modalities
--   qwen/qwen3.8-max-0902   2.00    6.00       0.25    1,000,000  text image video
--   openai/gpt-5.6-sol      2.00   10.00       0.20    1,050,000  text image file
--
-- IDENTICAL on input; Qwen is 40% CHEAPER ON OUTPUT, which is the axis these classes spend on (short
-- prompt, long answer). So Qwen Max wins on his own rule. The one place sol is cheaper is the cache
-- read, $0.20 against $0.25 — a 20% difference on a line that only applies to a stable system prefix,
-- and it does not come close to covering a 40% gap on every generated token. Recorded here so the
-- choice is auditable rather than asserted; gpt-5.6-sol is NOT registered, because nothing routes to
-- it.
--
-- This SUPERSEDES his ruling of 9 Sep 2026 (anthropic/claude-fable-5.1 + openai/gpt-6-astra on the
-- CEO and Sales Engineer, openai/gpt-5.6-luna on the accountant) and an earlier draft of this same
-- file that put anthropic/claude-opus-5.5 on plan A. Prices read live 23 Sep 2026, USD per Mtok:
--
--   qwen/qwen3.8-max-0902      2.00 /  6.00    plan A: customer / Arabic / document / judgement
--   z-ai/glm-5.3-flash         0.15 /  0.50    plan A: purely internal
--   anthropic/claude-opus-5.5  4.00 / 20.00    plan B on the Qwen row
--   google/gemini-3.8-flash    0.75 /  3.75    plan B on the GLM row; and the degrade target
--   anthropic/claude-fable-5.1 10.00/ 50.00    what the CEO ran on until today
--
-- The CEO's approvals move from $10/$50 to $2/$6 — 8.3x cheaper output — and the whole estate's
-- projected monthly ceiling falls from AED 2,870 (the opus draft) to AED 1,190 (arithmetic in
-- a_ceiling_exists_before_the_door_is_opened.sql). 844's audience split costs AED 20/month more than
-- 841's reasoning split would have, because it moves document reading and every customer-facing
-- surface onto Qwen; that AED 20 is what buys an Arabic-capable model on everything a person reads.
--
-- ═══ PLAN B: WHERE I HAD TO INTERPRET, AND WHAT I CHOSE ════════════════════════════════════════
--
-- Read literally, "for who doesn't need reasoning then GLM 5.3 flash" makes plan B the same model as
-- plan A on the GLM row, and a fallback that IS the primary is not a fallback: fn_ai_route hands the
-- fallback back for p_escalate and for a failed primary, so those rows would have had no second
-- attempt at all.
--
-- His INTENT is unambiguous and it is the cost one — do not pay reasoning prices for internal work. So
-- plan B on the GLM row is google/gemini-3.8-flash at $0.75/$3.75: a different provider (so it does
-- not share GLM's blind spots — this file's own document_extraction rationale makes that argument),
-- still 27x cheaper than opus, and the only model in the fleet carrying both vision and audio. It is
-- also already the degrade target for the Qwen row, so a degraded call and a failed call land in the
-- same place, which is one fewer thing to reason about at 3am.
--
-- PLAN B ON THE QWEN ROW IS opus-5.5 FOR EVERY CLASS ON IT, not just the judgements. A fallback has
-- to be at least as capable in Arabic as the primary it stands in for, or the fallback IS the failure
-- it was meant to prevent: a customer-facing Arabic class that fails over to the internal model has
-- quietly done the thing 844 forbids. opus-5.5 costs nothing while Qwen is healthy — the fallback is
-- reached only on an escalation or a failure.
--
-- THESE TWO ARE THE ONLY PLACES THIS FILE DEPARTS FROM HIS WORDS. Both are flagged in the PR for him
-- to overrule in one word.
--
-- ═══ WHICH SIDE OF THE LINE EACH CLASS IS ON ════════════════════════════════════════════════════
--
-- The list is in qwen_classes below, one place an auditor can read rather than twenty scattered
-- UPDATEs. A class is on the Qwen row if ANY of four things is true — it is read by a customer or a
-- supplier, it can emit Arabic to a person, it reads a document, or it is a judgement:
--
--   read by a person outside the company   visitor_chat, customer_communication, support_ai,
--                                          wa_inbound, supplier_communication, marketing_copy,
--                                          content_drafting, customer_portal_assistant,
--                                          inquiry_qualification_conversation
--   can emit Arabic to a person            translation, translation_general
--   reads a document                       document_extraction, document_extraction_multimodal, ocr,
--                                          vision, drawing_and_boq_analysis, json_extraction,
--                                          json_extraction_text
--   a judgement                            every ceo_* class, chief_of_staff_decision,
--                                          executive_report, quote_comparison, agent_reasoning,
--                                          sales_engineer_reasoning, procurement_reasoning,
--                                          identity_redaction_verify, finance_analysis and the
--                                          accountant's reasoning, knowledge_validation,
--                                          security_incident_analysis, edge_case_escalation,
--                                          contract_analysis, legal_analysis
--
-- PURELY INTERNAL, so GLM: intent_detection, email_triage, inbound_email, resend_inbound (triage),
-- summarization, knowledge_ingestion, engineering_reasoning, reflection_and_learning, and the rest.
--
-- TWO CALLS I HAD TO THINK ABOUT, both stated so they can be overruled in a line:
--
--   engineering_reasoning + reflection_and_learning MOVED TO GLM by 844. An earlier draft of this
--   file had them on the Qwen row, arguing that the IT seat's answers become SQL applied to
--   production. 844 is explicit that internal operation is GLM's, and this work is read by nobody
--   outside the company; its safety net is CI, branch protection and an independent review before
--   every merge, which is a stronger guarantee than a model choice. Moved.
--
--   email_triage / intent_detection STAY ON GLM although the answer contains a customer reply.
--   Measured, not assumed: email_triage/index.ts:16 asks for {category, summary, reply} where the
--   reply is "a short, warm, professional reply ... signed 'The QuotesDone Team'", and the Arabic
--   fixture in scripts/checks/the_triage_answer_fits_its_route.test.mjs is exactly that. By the
--   audience rule that looks like customer-facing Arabic and belongs on Qwen. It stays on GLM because
--   THE DRAFT IS NEVER SENT: index.ts:1 says so, and index.ts:52 files it into agent_actions as a
--   pending 'inbound_review' for a person to read, edit and send. A human gate is what makes the
--   cheap model safe here, and it is the only reason. IF THAT GATE IS EVER REMOVED THIS CLASS MUST
--   MOVE TO THE QWEN ROW, and the check that would notice is the same triage check, because it
--   already asserts over the drafted reply's own fixtures.
--
-- ═══ THE ONE CLASS EXEMPT FROM THE RULING, AND WHY IT IS NOT A CHOICE ═══════════════════════════
--
-- speech_transcription stays on google/gemini-3.1-flash-lite with google/gemini-3.5-flash behind it.
-- Measured in the live catalogue 23 Sep 2026, ONLY the gemini family carries "audio" in
-- input_modalities: glm-5.3-flash and qwen3.8-max-0902 are text+image+video, every anthropic/ and
-- openai/ row is text+image+file. His instruction says "whenever, wherever it's POSSIBLE"; here it is
-- not. A voice note on GLM is rejected by the provider or silently redirected by fn_ai_route's
-- capability branch to a model nobody chose.
--
-- ═══ 1. THE CEO'S DECISIONS WERE GOING TO THE CHEAP TIER ════════════════════════════════════════
--
-- ceo_agent/index.ts:329 passes taskClass 'ceo_judgement'. There was no model_policy row for it, so
-- fn_ai_route fell through `no policy for "ceo_judgement", fell back to general_drafting` — which is
-- ~anthropic/claude-haiku-latest at 900 tokens. The CEO's judgements on refunds and exceptions, the
-- answers fn_ceo_judgement_accept validates against ceo-judgement-v1, were being drafted on the
-- cheapest model in the fleet with a 900-token ceiling. Measured before the change:
--
--   fn_ai_route('ceo_judgement') -> ~anthropic/claude-haiku-latest, 900, medium,
--                                   why: '... fell back to general_drafting'
--
-- I ADD THE CLASS rather than point the caller at ceo_approval_decision. Reasons, in order:
--
--   * ai_cost_log keys on task_class. Collapsing the two makes a plan judgement and a refund
--     approval indistinguishable in the cost log and in the per-seat model A/B the founder has next
--     on his plan. A column that cannot separate two decisions cannot evaluate either.
--   * They are different contracts. ceo_approval_decision answers one approval on the record;
--     ceo_judgement answers fn_ceo_judgement_request's output_schema against measured numbers and
--     code-computed options. Different shapes need different token ceilings, which is the whole
--     reason 900 was wrong.
--   * It is the smaller change: a data row, no function to redeploy. Editing the caller to send a
--     class whose contract it does not match would be a second bug dressed as a fix.
--
-- The caller's own `max: 900` clamps the route too (ai_gateway:326 takes min(body.max, route
-- max_tokens)), so supabase/functions/ceo_agent/index.ts is raised to 2000 in the same PR.
--
-- ═══ 2. THE TOKEN CLAMP ON A JSON CONTRACT ══════════════════════════════════════════════════════
--
-- supplier_catalog_ingest/index.ts:293 asks for max 3000 with response_format 'json', sending a
-- catalogue page as an image. It passes no task_class and had NO fn_task_class row, so it landed on
-- general_drafting: 900. ai_gateway clamps to min(3000, 900) = 900, and a products array truncated
-- at 900 tokens is not JSON, so the function's own parse fell to 'extraction_failed'.
--
-- The fix is a routing row, not a bigger default: document_extraction already means "reading a
-- whole document (scan, drawing, licence, quotation)" and allows 8000, which fits the contract with
-- 2.7x headroom. general_drafting stays at 900 on purpose — it is the "you forgot to map this"
-- path, and a generous default would hide the next unmapped caller instead of truncating visibly.
--
-- EVERY OTHER JSON-RETURNING CALLER WAS AUDITED THE SAME WAY (measured 23 Sep 2026, requested max
-- against the ceiling of the class its fn resolves to):
--
--   caller                          asks   class resolved            ceiling  verdict
--   ceo_agent:329                    900   general_drafting  ->NEW    900     misrouted, fixed above
--   supplier_catalog_ingest:293     3000   general_drafting  ->8000    900     CLAMPED, fixed here
--   inquiry_intake:39               4000   agent_reasoning            8000    fits
--   supplier_onboard:172             900   procurement_reasoning      1500    fits
--   wa_inbound:222                   600   customer_communication      800    fits
--
-- And the non-JSON callers, because a truncated prose answer is also a paid request for nothing:
-- drawing_boq 8000 / document_extraction 8000, quote_compare 10000 / quote_comparison 10000,
-- quote_extract 6000, extract_text 4000, doc_extract 2000, drawing_redact 2000 and license_extract
-- 2000 all against document_extraction 8000; email_triage 700 and resend_inbound 500/400 against
-- intent_detection 800; marketing_social_inbox 300 against marketing_copy 1200. All fit.
-- drawing_redact_verify sends NO max at all, so it takes the route's ceiling — see §4.
-- Held by scripts/checks/no_gateway_caller_is_clamped_below_what_it_asks_for.test.mjs.
--
-- ═══ 3. SEVEN FUNCTIONS OUTSIDE EVERY CEILING — AND WHICH SEVEN THEY REALLY ARE ═════════════════
--
-- The audit listed sales_engineer, supplier_catalog_ingest, accountant, marketing, customer_portal,
-- ceo_agent and it_engineer as missing fn_task_class rows. MEASURED 23 Sep 2026 against the source:
-- of those seven, only ceo_agent and supplier_catalog_ingest make a completion call through
-- ai_gateway. sales_engineer, accountant, marketing, customer_portal and it_engineer contain no
-- call to /functions/v1/ai_gateway, makeLlmRich or makeLlm at all — sales_engineer's only mention
-- is a comment about the free embedding path. A routing row for a call that does not exist is a row
-- that will be wrong by the time the call is written; the check below FAILS the moment any of them
-- starts calling, which is when the row can be right.
--
-- What IS missing, by the same measurement, is a row for marketing_social_inbox (the marketing
-- seat's only gateway caller) and a dept_key on four callers that have a class but no department:
--
--   fn              calls (8-22 Sep)   was          now
--   quote_compare              2,455   (no dept)    marketplace
--   transcribe                     0   (no dept)    marketplace
--   extract_text                   0   (no dept)    marketplace
--   email_triage                   0   (no dept)    customer_experience
--
-- quote_compare is 2,455 of the 3,207 calls in the window — 77% of everything the estate has ever
-- routed — and fn_ai_route's budget branch could not find a budget row for it, so the single
-- largest consumer sat outside every ceiling. That, not the missing table rows, is why the ceiling
-- could never bind. (department_budget's own emptiness is fixed in
-- a_ceiling_exists_before_the_door_is_opened.sql.)
--
-- ═══ 4. THE REDACTION VERIFY PASS IS THE ONE PLACE A MISS LEAKS A SUPPLIER'S IDENTITY ═══════════
--
-- drawing_redact runs FIND (drawing_redact) then VERIFY (drawing_redact_verify) over the redacted
-- page, and publishes only on a clean verify, failing closed on anything else. The verify pass was
-- on general_drafting: haiku at 900 tokens. Session 9 pinned it there deliberately to keep it off
-- google after a 400-token ceiling cut gemini's answer mid-JSON; the diagnosis was wrong (it was
-- the ceiling, measured: 724 output tokens with no max, parsing correctly) but the conclusion — do
-- not route this to redaction_detection — stands, and this file keeps it off google on plan A.
--
-- It now has its own class, identity_redaction_verify, on the REASONING row of the matrix:
-- qwen/qwen3.8-max-0902 primary, anthropic/claude-opus-5.5 on escalate, 2000 tokens (2.7x the 724
-- measured). A miss here sends a consultant's name, a client's name and a phone number from the
-- buyer's drawing to a supplier who has not been revealed. It is the only vision call in the estate
-- where the cheap model is the wrong answer, and it keeps failing closed: the function still treats
-- truncation, an unparseable answer and an exception as NOT clean.
--
-- ═══ 5. WHAT STAYS DETERMINISTIC ════════════════════════════════════════════════════════════════
--
-- All 17 tier='none' rows are untouched. Money, matching, VAT, permissions, approval thresholds,
-- workflow state, scoring and the rest answer from code and keep answering from code.
--
-- SEVENTEEN, NOT TWENTY-THREE (corrected 23 Sep 2026 in review; the first draft of this file, its PR
-- body and its probe all said 23). Measured: `select count(*) from model_policy where tier='none'`
-- = 17, and `... and active` = 17 — every one of them active, none quietly switched off. Of the 73
-- rows in model_policy, 72 are active and 55 of those route to a model. A count is not a finding
-- until you know what you counted, and 23 was not counted from anything.

begin;

-- ── 1. THE REASONING CLASSES: plan A qwen3.8-max, plan B opus-5.5 ──────────────────────────────
-- One statement, one list. The WHY for the group is the founder's ruling above; the WHY for each
-- individual class goes into its own rationale below, because fn_ai_route returns the rationale in
-- its `why`, so the reason a model was chosen travels with the decision rather than living only here.
create temporary table qwen_classes (task_class text primary key, because text) on commit drop;
insert into qwen_classes values
  -- A JUDGEMENT. He named the CEO and the comparison; the rest are the same shape.
  ('ceo_judgement', 'judgement'), ('ceo_approval_decision', 'judgement'),
  ('ceo_strategic_planning', 'judgement'), ('chief_of_staff_decision', 'judgement'),
  ('executive_report', 'judgement'), ('quote_comparison', 'judgement + customer reads the ranking'),
  ('sales_engineer_reasoning', 'judgement'), ('agent_reasoning', 'judgement'),
  ('procurement_reasoning', 'judgement'), ('identity_redaction_verify', 'judgement'),
  ('finance_analysis', 'judgement + money'), ('accountant_expense_classification', 'judgement + money'),
  ('accountant_weekly_report', 'judgement + money'), ('knowledge_validation', 'judgement'),
  ('security_incident_analysis', 'judgement'), ('edge_case_escalation', 'judgement'),
  ('contract_analysis', 'judgement + legal exposure'), ('legal_analysis', 'judgement + legal exposure'),
  -- READ BY A PERSON OUTSIDE THE COMPANY. "When it comes to customers, Qwen 3.8 Max is fine."
  ('customer_portal_assistant', 'signed-in customer reads it'),
  ('visitor_chat', 'a stranger on the public website reads it'),
  ('customer_communication', 'the customer reads it'), ('support_ai', 'the customer reads it'),
  ('wa_inbound', 'the customer reads it on WhatsApp'),
  ('supplier_communication', 'the supplier reads it'),
  ('inquiry_qualification_conversation', 'the customer reads it, first contact'),
  ('marketing_copy', 'published in the company name'),
  ('content_drafting', 'published in the company name'),
  -- CAN EMIT ARABIC TO A PERSON. "anything that involves Arabic, keep it Qwen 3.8 Max".
  ('translation', 'Arabic the customer receives'), ('translation_general', 'Arabic'),
  -- READS A DOCUMENT. "whenever we have document readings". Verified: qwen3.8-max carries `image`.
  ('document_extraction', 'document reading'), ('document_extraction_multimodal', 'document reading'),
  ('ocr', 'document reading'), ('vision', 'document reading'),
  ('drawing_and_boq_analysis', 'document reading'), ('json_extraction', 'document reading'),
  ('json_extraction_text', 'document reading'),
  ('accountant_receipt_extraction', 'document reading');

-- The two classes that did not exist at all. Inserted first so the statements below can treat them
-- like any other row.
insert into public.model_policy
  (task_class, tier, model_primary, model_fallback, max_tokens, active, rationale)
values
  ('ceo_judgement', 'large', 'qwen/qwen3.8-max-0902', 'anthropic/claude-opus-5.5', 2000, true,
   'The CEO judging one plan on the record: ceo_agent/index.ts:329 builds the request from '
   || 'fn_ceo_judgement_request and fn_ceo_judgement_accept validates the answer against '
   || 'ceo-judgement-v1. WHY it is plan A qwen3.8-max: the founder named the CEO seat for it '
   || '(instruction 841), and this is the class that decides refunds and exceptions - until 23 Sep '
   || '2026 it had NO policy row at all and fell to general_drafting, ~anthropic/claude-haiku-latest '
   || 'at 900 tokens, which is the cheapest model in the fleet. WHY opus-5.5 on escalate: plan B is '
   || 'DEARER than plan A here, so fn_ai_route''s p_escalate is a real second opinion from a '
   || 'stronger reasoner rather than a retry of the same one. 2000 tokens is the structured answer '
   || 'plus its reasoning; the caller''s own max was raised to match, because ai_gateway takes the '
   || 'lower of the two.'),

  ('identity_redaction_verify', 'large', 'qwen/qwen3.8-max-0902', 'anthropic/claude-opus-5.5', 2000, true,
   'The second pass over a REDACTED drawing page, asked whether any identity is still legible '
   || '(drawing_redact/index.ts:186, fn drawing_redact_verify). WHY the reasoning row of the matrix '
   || 'and not GLM: a false clean here publishes a consultant''s name, a client''s name, a plot '
   || 'number and a phone number from the buyer''s drawing to a supplier who has not been revealed, '
   || 'and no later step can unsend it. The FIND pass may be cheap because a miss there is caught '
   || 'here; a miss here is caught by nobody. WHY not google: measured 13 Aug 2026, routing these '
   || 'calls to redaction_detection on gemini refused two of three correctly-redacted fixtures while '
   || 'naming the planted identifiers as still legible. 2000 tokens against the 724 measured with no '
   || 'ceiling - a ceiling inside the answer''s natural range reads as an unparseable model, which '
   || 'cost a whole session once. Still fails CLOSED: truncated, unparseable and exception all mean '
   || 'not clean.')
on conflict (task_class) do update set
  tier = excluded.tier, model_primary = excluded.model_primary,
  model_fallback = excluded.model_fallback, max_tokens = excluded.max_tokens,
  active = excluded.active, rationale = excluded.rationale;

-- Plan A / plan B onto every reasoning class. tier 'large' because that is qwen3.8-max's registry
-- tier and §7b explains why the two must agree.
update public.model_policy set
  tier = 'large',
  model_primary = 'qwen/qwen3.8-max-0902',
  model_fallback = 'anthropic/claude-opus-5.5'
 where active and task_class in (select task_class from qwen_classes);

-- ── 2. EVERYTHING ELSE: plan A GLM 5.3 flash, plan B gemini-3.8-flash ──────────────────────────
-- "use GLM 5.3 flash whenever, wherever it's possible as a primary model... We want to cut cost as
-- much as possible." Reading, classifying, triaging and routine drafting. tier 'small' = GLM's
-- registry tier; a small-tier class degrades within the small band, which is correct for work that
-- is already the cheapest thing the estate does.
--
-- EXCLUSIONS, each for a stated reason and nothing else:
--   speech_transcription  the only audio-capable models are gemini (header)
--   the 17 tier='none'    deterministic, and they must stay that way
--   redaction_detection   has no caller; drawing_redact/index.ts:94 records the measurement that
--                         stopped it being used, and editing a policy nothing reads is noise
update public.model_policy set
  tier = 'small',
  model_primary = 'z-ai/glm-5.3-flash',
  model_fallback = 'google/gemini-3.8-flash'
 where active and tier <> 'none'
   and task_class not in (select task_class from qwen_classes)
   and task_class not in ('speech_transcription', 'redaction_detection');

-- ── 3. THE AUDIO EXEMPTION, WRITTEN DOWN WHERE THE ROUTING IS ──────────────────────────────────
update public.model_policy set
  tier = 'small',
  model_primary = 'google/gemini-3.1-flash-lite',
  model_fallback = 'google/gemini-3.5-flash',
  rationale = 'Verbatim speech to text. THE ONE CLASS EXEMPT FROM founder_instruction 841, and not '
    || 'by choice: measured in the live catalogue 23 Sep 2026, only the gemini family carries '
    || '"audio" in input_modalities. z-ai/glm-5.3-flash and qwen/qwen3.8-max-0902 are '
    || 'text+image+video; every anthropic/ and openai/ row is text+image+file. His words are '
    || '"whenever, wherever it''s POSSIBLE", and here it is not - a voice note on GLM is rejected by '
    || 'the provider, or silently redirected by fn_ai_route''s capability branch to a model nobody '
    || 'chose. gemini-3.1-flash-lite at $0.25/$1.50 is the cheapest audio-capable row; '
    || 'gemini-3.5-flash behind it is also audio-capable, verified the same way.'
 where task_class = 'speech_transcription' and active;

-- ── 4. THE RATIONALES: why THIS model for THIS work, class by class ───────────────────────────
-- The model choice is set above; this sets the reason, which fn_ai_route hands back in `why`. Only
-- the consequential classes get their own paragraph - the rest carry the group rationale at the end.
update public.model_policy set rationale =
  'The CEO deciding one approval on the record - a refund, an exception, a supplier removal. WHY '
  || 'plan A qwen3.8-max (founder, instruction 841, "for the CEO, again, Qwen 3.8 max"): every '
  || 'approval in this company is the CEO''s, refunds included, and nothing reaches the founder, so '
  || 'this row IS the last judgement. It replaces anthropic/claude-fable-5.1 at $10/$50 with '
  || '$2.00/$6.00 - 8.3x cheaper on output, which is the axis a judgement spends on. opus-5.5 on '
  || 'escalate is the dearer second opinion, which is what an escalation should be.'
 where task_class = 'ceo_approval_decision' and active;

update public.model_policy set rationale =
  'Quarterly priorities and capital allocation against the AED 1M by Aug 2027 target. WHY plan A '
  || 'qwen3.8-max: the longest-horizon reasoning the company does, and the one answer that is wrong '
  || 'for a quarter rather than for a call; its 1,000,000 context holds the whole plan, the ledger '
  || 'and the measured KPIs in one request. Runs a handful of times a quarter, so opus-5.5 on '
  || 'escalate costs almost nothing and is worth having.'
 where task_class = 'ceo_strategic_planning' and active;

update public.model_policy set rationale =
  'Cross-department arbitration against company goals - which seat gives way when two are both '
  || 'right. WHY the reasoning row: an arbitration is a judgement with no appeal above it, and the '
  || 'intent_router and founder_directive paths both land here, so a shallow answer mis-routes the '
  || 'founder''s own instruction.'
 where task_class = 'chief_of_staff_decision' and active;

update public.model_policy set rationale =
  'Board-level synthesis for the founder. WHY the reasoning row: this is the report he acts on, and '
  || 'a plausible-sounding wrong synthesis of correct numbers is worse than no report.'
 where task_class = 'executive_report' and active;

update public.model_policy set max_tokens = 10000, rationale =
  'Normalising non-comparable supplier scopes and ranking the customer''s top 3. WHY plan A '
  || 'qwen3.8-max: the founder named this class first - "the primary model for the comparison would '
  || 'be Qwen 3.8 max". It is the revenue event: the customer pays 3% when he reveals the supplier '
  || 'this class ranked first, so the ranking IS the product, and it is 2,455 of the 3,207 calls the '
  || 'estate routed between 8 and 22 Sep 2026 - the most consequential class by volume AND by money, '
  || 'and 92% of the projected bill. 1,000,000 context (the registry said 200,000 until today) '
  || 'matters here because every quotation goes on one request. NOT YET MEASURED on this class: '
  || 'whether qwen refuses to rank quotes that are genuinely non-comparable rather than inventing a '
  || 'common basis. That is the first thing to watch when the hold opens; the PR body names the check.'
 where task_class = 'quote_comparison' and active;

update public.model_policy set rationale =
  'An AI employee reasoning over its own context, memory and live estate - 653 calls in the window, '
  || 'the working turn of every seat. WHY plan A qwen3.8-max: it is reasoning, and at $2.00/$6.00 it '
  || 'costs less than the anthropic/claude-sonnet-5 it replaces ($2.00/$10.00) on the axis that '
  || 'dominates here. WHY opus-5.5 on escalate: fn_ai_route takes the fallback when p_escalate is '
  || 'true, i.e. after an unsatisfactory cheaper attempt, so the escalation is a real second opinion.'
 where task_class = 'agent_reasoning' and active;

update public.model_policy set rationale =
  'The Sales Engineer reasoning over technical scope, supplier capability and what a line item '
  || 'actually requires. WHY the reasoning row: it sits around quote_comparison, which earns the '
  || 'money, and it replaces the anthropic/claude-fable-5.1 / openai/gpt-6-astra pair at $10/$50 '
  || 'with $2.00/$6.00.'
 where task_class = 'sales_engineer_reasoning' and active;

update public.model_policy set rationale =
  'Qualifying an inbound inquiry in conversation - the model interprets and rephrases, code controls '
  || 'the state and the questions. WHY the reasoning row and not GLM: this is the first thing a '
  || 'paying customer reads, and a qualifying question that misreads his trade sends the RFQ to the '
  || 'wrong suppliers, which the exact-trade-match rule then cannot repair.'
 where task_class = 'inquiry_qualification_conversation' and active;

update public.model_policy set rationale =
  'Trade-off reasoning within one category, and the supplier''s mandatory six - name, mobile, email, '
  || 'licence, profile, signed T&C. WHY the reasoning row: this class decides whether a supplier is '
  || 'verified, and one confirmed supplier gates every RFQ, so a wrong answer either admits an '
  || 'unverified company to the marketplace or keeps a real one out. ALSO WHY ITS TIER IS large: at '
  || 'medium it would degrade to the cheapest small row and drop 20x in one step - see §7b.'
 where task_class = 'procurement_reasoning' and active;

update public.model_policy set rationale =
  'The assistant a SIGNED-IN customer or supplier talks to, reasoning over that person''s own '
  || 'quotes, reveals and invoices. WHY the reasoning row: it is the only class that reads real money '
  || 'belonging to the person reading the answer, and it answers about state it can see, so a '
  || 'confident wrong answer about his own reveal is indistinguishable from the truth to him. '
  || 'Distinct from visitor_chat, which knows nothing about anybody and is on GLM.'
 where task_class = 'customer_portal_assistant' and active;

update public.model_policy set max_tokens = 2000, rationale =
  'The accountant''s analysis, including the refund recommendation the CEO then approves. WHY the '
  || 'reasoning row: the books are the one record with an external reader, and AED 6,905.59 of real '
  || 'bookings already sit in them. max_tokens 1400 -> 2000 because a recommendation without its '
  || 'arithmetic is not a recommendation, and this class is read by a person who must be able to '
  || 'check it.'
 where task_class = 'finance_analysis' and active;

update public.model_policy set max_tokens = 600, rationale =
  'Classifying one expense against the chart of accounts. WHY the reasoning row even though the '
  || 'answer is short: the answer is a LEDGER ENTRY. It is cheap to produce and expensive to be '
  || 'wrong about, it is what a VAT position and a P&L are built from, and at $2.00/Mtok in on a '
  || '600-token answer the whole month of expenses costs AED 2.06. max_tokens 400 -> 600 so the '
  || 'account, the reason and the VAT treatment fit together.'
 where task_class = 'accountant_expense_classification' and active;

update public.model_policy set max_tokens = 2000, rationale =
  'The weekly financial report. WHY the reasoning row: it states the company''s position to the '
  || 'founder from the ledger, and a report that reads well and totals wrong is worse than none. '
  || 'Weekly, so the best available model here costs four calls a month.'
 where task_class = 'accountant_weekly_report' and active;

update public.model_policy set rationale =
  'A security incident, an escalated edge case, or an independent review of knowledge before it is '
  || 'trusted. WHY the reasoning row with opus-5.5 on escalate: a reviewer on the cheap model is a '
  || 'green check that means nothing, and a severe incident is exactly the case p_escalate exists for.'
 where task_class in ('security_incident_analysis', 'edge_case_escalation', 'knowledge_validation') and active;update public.model_policy set rationale =
  'The IT seat reasoning about the estate - a finding, a diagnosis, a change. WHY plan A GLM: '
  || 'founder_instruction 844 - "whenever it''s something related to our operation internally, GLM '
  || '5.3 Flash can do it, all good". Nobody outside this company ever reads it. An earlier draft of '
  || 'this file put it on the Qwen row arguing that this seat''s answers become SQL applied to '
  || 'production; that is true and it is not the point, because the guarantee on those answers is CI, '
  || 'branch protection and an independent review before every merge, which is stronger than a model '
  || 'choice. MOVED to GLM by 844.'
 where task_class in ('engineering_reasoning', 'reflection_and_learning') and active;

update public.model_policy set rationale =
  'Legal exposure: reading a contract or a regulatory source for what it actually commits us to. WHY '
  || 'the Qwen row: it is a judgement AND it is document reading, either of which puts it there under '
  || 'founder_instruction 844. A wrong reading costs money no later step recovers, and citations must '
  || 'survive verbatim. No autonomous legal conclusion - the model reads, a person decides.'
 where task_class in ('contract_analysis', 'legal_analysis') and active;

update public.model_policy set rationale =
  'The Arabic quotation and correspondence a UAE customer actually receives. WHY the Qwen row: '
  || 'founder_instruction 844 names it outright - "anything that involves Arabic, keep it Qwen 3.8 Max '
  || 'or GPT Sol 5.6, depending which one is cheaper". Measured live 23 Sep 2026, qwen3.8-max-0902 is '
  || '$2.00/$6.00 against openai/gpt-5.6-sol at $2.00/$10.00: identical input, 40% cheaper output, so '
  || 'Qwen wins on his own rule. NOT YET MEASURED on this estate: formal Gulf Arabic, on either model. '
  || 'The founder chose on price having been told the test was available, and he will judge Arabic on '
  || 'the real test when customers arrive; until then the repository''s Arabic checks are what would '
  || 'catch a regression. translation_general is on the Qwen row too, for the same one reason: it can '
  || 'emit Arabic to a person.'
 where task_class in ('translation', 'translation_general') and active;

update public.model_policy set rationale =
  'Reading a whole document - a scan, a drawing, a trade licence, a quotation, a supplier catalogue '
  || 'page - into structured fields. WHY the Qwen row: founder_instruction 844, "whenever we have '
  || 'document readings". Verified before routing: qwen3.8-max-0902 carries `image` in '
  || 'input_modalities (text+image+video), which is how every document reaches a model here - a '
  || 'base64 data URL in an image_url part, never a `file` part. A document is also the one input that '
  || 'arrives in Arabic without anyone choosing to, which is the other half of why it is not on the '
  || 'internal row. WHY opus-5.5 as fallback: a document GLM or Qwen cannot read must still be read, '
  || 'and the fallback for a class that can meet Arabic must itself handle Arabic. 8000 tokens holds '
  || 'supplier_catalog_ingest''s 3000 JSON products with headroom - it used to land on '
  || 'general_drafting''s 900 and truncate.'
 where task_class in ('document_extraction', 'document_extraction_multimodal', 'ocr', 'vision',
                      'json_extraction', 'json_extraction_text') and active;

update public.model_policy set rationale =
  'Reading a drawing and a bill of quantities together. WHY the Qwen row: document reading (844), over '
  || 'pages that carry Arabic title blocks as often as English ones. A wrong quantity becomes a wrong '
  || 'price on a real quotation, and the design calculations and low-confidence interpretations that '
  || 'are judgement rather than reading escalate to opus-5.5, so the escalation is not decorative.'
 where task_class = 'drawing_and_boq_analysis' and active;

update public.model_policy set rationale =
  'The support seat writing to a customer or a supplier - email, WhatsApp, the portal, the public '
  || 'widget. WHY the Qwen row: founder_instruction 844 - "When it comes to customers, Qwen 3.8 Max is '
  || 'fine... interactions with customers, stuff like that". Every word here is read by somebody '
  || 'outside this company, signed in the company''s name, and in either of two languages. The '
  || 'deterministic FAQ and template levels still answer what code can answer first (18 of 50 '
  || 'site_assistant calls in the 8-22 Sep window, with no model at all), so the model sees only the '
  || 'remainder - that is what makes this affordable, not the model''s price. supplier_communication '
  || 'is here too: a supplier is outside the company even though 844 says "customers", and the first '
  || 'six weeks are supplier registration only, so this is the surface that gets exercised first.'
 where task_class in ('customer_communication', 'support_ai', 'wa_inbound', 'visitor_chat',
                      'supplier_communication') and active;

update public.model_policy set rationale =
  'Sorting one inbound message into what it is and who it is from, and drafting a reply for a person '
  || 'to send. WHY plan A GLM even though the answer contains customer-facing text, including Arabic: '
  || 'THE DRAFT IS NEVER SENT BY THE MACHINE. Measured - email_triage/index.ts:1 says "Never sends", '
  || 'and index.ts:52 files the draft into agent_actions as a pending inbound_review for a person to '
  || 'read, edit and send. A human gate is what makes the cheap model safe here and it is the only '
  || 'reason; IF THAT GATE IS EVER REMOVED THIS CLASS MUST MOVE TO THE QWEN ROW. 844 puts triage on '
  || 'the internal side and this is triage. max_tokens is NOT reduced: email_triage asks for 700 and '
  || '300 cut its Arabic replies in half (founder instruction 705).'
 where task_class in ('intent_detection', 'email_triage', 'inbound_email', 'resend_inbound') and active;

update public.model_policy set rationale =
  'Reading a supplier catalogue or a knowledge source for MEANING, offline, once - not transcribing '
  || 'it, which is document_extraction on the Qwen row. WHY plan A GLM: 844 puts internal ingestion '
  || 'here, its 1,310,720 context takes a whole catalogue in one request at $0.15/Mtok, and this runs '
  || 'in batch rather than in front of a person, so nothing it produces is read by a customer without '
  || 'passing through a class that is on the Qwen row.'
 where task_class = 'knowledge_ingestion' and active;

update public.model_policy set rationale =
  'Public posts, social replies and brand copy. WHY the Qwen row: it is published under the company''s '
  || 'own name on surfaces the founder does not review first, to a UAE audience reading in two '
  || 'languages - "when it comes to customers, Qwen 3.8 Max is fine" (844). The deterministic '
  || 'brand_rule_check (tier none) still gates it, so the model writes and code checks; that gate is '
  || 'load-bearing rather than a formality, and it is why this is safe to automate at all.'
 where task_class in ('marketing_copy', 'content_drafting') and active;

update public.model_policy set rationale =
  'Reading a forwarded receipt - image or PDF - into fields. WHY the Qwen row: document reading (844). '
  || 'It is worth being precise that this step TRANSCRIBES and does not decide: the judgement about '
  || 'what the receipt MEANS is accountant_expense_classification, which is on the same model for a '
  || 'different reason (a ledger entry is a judgement about money). Both being on Qwen does not make '
  || 'them one class - ai_cost_log keys on task_class, so a misread stays distinguishable from a '
  || 'misjudgement, which is the whole reason they are separate rows.'
 where task_class = 'accountant_receipt_extraction' and active;

-- The group rationale for every remaining routed class, so no row is left claiming a model it no
-- longer runs. It names the ruling and the date, which is what an auditor needs from a row nobody
-- wrote a paragraph for. The guard is `%instruction 841%` — every paragraph above either says that
-- or says "WHY plan A"/"WHY the reasoning row", so this touches only the rows nobody wrote one for.
update public.model_policy set rationale =
  'Routed by founder_instruction 841 (23 Sep 2026): plan A z-ai/glm-5.3-flash at $0.15/$0.50, plan B '
  || 'google/gemini-3.8-flash. "use GLM 5.3 flash whenever, wherever it''s possible as a primary '
  || 'model... We want to cut cost as much as possible." This class reads, classifies or drafts '
  || 'routinely: its answer is checkable by code or corrected by the next step, so the cheapest '
  || 'capable model is the right one. Previous rationale, written for the model this class ran on '
  || 'before that ruling: ' || coalesce(rationale, '(none)')
 where active and tier <> 'none'
   and model_primary = 'z-ai/glm-5.3-flash'
   and coalesce(rationale, '') not like '%instruction 841%'
   and coalesce(rationale, '') not like '%WHY plan A%';

-- ── 5. fn_task_class: the rows the callers need, and the departments the ceiling is found by ───
-- `as ftc` is not decoration: scripts/apply_sql.mjs treats `public.fn_<name>(` as a ROUTINE CALL and
-- refuses the file for calling a routine the database does not have. fn_task_class is a TABLE whose
-- name happens to start with fn_, so the alias keeps the column list off the table name.
insert into public.fn_task_class as ftc (fn, task_class, dept_key, active, note)
values
  ('ceo_agent', 'ceo_judgement', 'exec', true,
   'ceo_agent/index.ts:329 passes taskClass ceo_judgement explicitly, so this row is not what '
   || 'chooses its model - but fn_ai_route finds the BUDGET by fn_task_class.dept_key when the '
   || 'caller sends no p_dept_key, and ceo_agent sends none. Without this row the CEO''s judgements '
   || 'were outside every ceiling as well as on the wrong model.'),
  ('supplier_catalog_ingest', 'document_extraction', 'marketplace', true,
   'Reads a supplier catalogue page as an image into a JSON products array '
   || '(supplier_catalog_ingest/index.ts:293, response_format json, max 3000). Had no row, so it '
   || 'fell to general_drafting and ai_gateway clamped 3000 to 900, truncating the JSON and '
   || 'recording extraction_failed. document_extraction allows 8000.'),
  ('marketing_social_inbox', 'marketing_copy', 'marketing', true,
   'The marketing seat''s only gateway caller - drafting a public social reply.')
on conflict (fn) do update set
  task_class = excluded.task_class, dept_key = excluded.dept_key,
  active = excluded.active, note = excluded.note, updated_at = now();

-- drawing_redact_verify moves off general_drafting onto its own class (see §4 in the header).
update public.fn_task_class set
  task_class = 'identity_redaction_verify', dept_key = 'marketplace', updated_at = now(),
  note = 'The VERIFY pass over a redacted drawing page. Pinned to general_drafting by session 9 to '
    || 'keep it off google after a token ceiling cut gemini''s answer mid-JSON; that kept it off '
    || 'google and also put the estate''s only identity-leak check on haiku at 900 tokens. It now '
    || 'has its own class on the reasoning row of founder_instruction 841''s matrix, with 2000 tokens.'
 where fn = 'drawing_redact_verify';

-- Four callers that had a class but no department, so fn_ai_route's budget branch could not find a
-- ceiling for them. quote_compare alone is 2,455 of the 3,207 calls logged 8-22 Sep 2026.
update public.fn_task_class set dept_key = 'marketplace', updated_at = now()
 where fn in ('quote_compare', 'extract_text', 'transcribe') and dept_key is null;
update public.fn_task_class set dept_key = 'customer_experience', updated_at = now()
 where fn = 'email_triage' and dept_key is null;

-- ── 6. THE GUARD: an active policy cannot name a model the catalogue or the breaker does not hold
-- This is the recurrence guard for the defect this PR fixes. fn_ai_route SUBSTITUTES silently for
-- an unregistered model (it writes a WARNING into `why` that nobody reads), and before today
-- fn_llm_preflight ALLOWED an unmeasured one. Both holes were opened the same way: a model was
-- added to model_policy and the two tables behind it were not updated in the same breath. A
-- trigger is the only thing that makes those three writes one action.
--
-- IT COVERS model_policy ONLY. model_policy_by_identity names six models that are in neither table,
-- on fn_ai_route's role-default branch; that branch fires only for a caller unmapped in
-- fn_task_class, and after this PR all 19 gateway callers are mapped. It is being fixed separately.
create or replace function public.trg_model_policy_names_a_known_route()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_m text;
begin
  if not coalesce(new.active, false) then return new; end if;
  for v_m in
    select m from unnest(array[new.model_primary, new.model_fallback]) m
     where m is not null and m not in ('none', 'none/deterministic')
  loop
    if not exists (select 1 from model_registry r where r.model_id = v_m and r.active) then
      raise exception 'model_policy.% names "%" which is not an active model_registry row. '
        'fn_ai_route would substitute a different model silently. Add the registry row (prices read '
        'live from the provider catalogue) in the same file.', new.task_class, v_m
        using errcode = '23514';
    end if;
    if not exists (select 1 from llm_route_health h where h.model_id = v_m) then
      raise exception 'model_policy.% names "%" which has no llm_route_health row, so no circuit '
        'breaker covers it and fn_llm_preflight must refuse it. Add the breaker row - carrying the '
        'same open_until as the rest of the fleet - in the same file.', new.task_class, v_m
        using errcode = '23514';
    end if;
  end loop;
  -- A FALLBACK THAT IS THE PRIMARY IS NOT A FALLBACK (added 23 Sep 2026 in review, after the first
  -- draft set knowledge_ingestion's fallback to a model that a later blanket rewrite turned into its
  -- own primary). fn_ai_route hands model_fallback back for p_escalate and for a failed primary, so
  -- an equal pair silently removes the second attempt.
  if new.model_fallback is not null and new.model_fallback = new.model_primary
     and new.model_primary not in ('none', 'none/deterministic') then
    raise exception 'model_policy.% names "%" as BOTH primary and fallback. fn_ai_route returns the '
      'fallback for an escalation and for a failed primary, so this row has no second attempt at '
      'all.', new.task_class, new.model_primary
      using errcode = '23514';
  end if;
  return new;
end $fn$;

revoke execute on function public.trg_model_policy_names_a_known_route() from public, anon, authenticated;

drop trigger if exists trg_model_policy_names_a_known_route on public.model_policy;
create trigger trg_model_policy_names_a_known_route
  before insert or update on public.model_policy
  for each row execute function public.trg_model_policy_names_a_known_route();

-- ── 7b. THE TIER MUST AGREE WITH ITS OWN MODEL, OR DEGRADING IS A CLIFF ───────────────────────
-- Added 23 Sep 2026 in review, and it is the root cause of a class of defect rather than four
-- instances of it.
--
-- model_policy.tier is not a label. fn_ai_route reads it three times, and every one of them picks a
-- DIFFERENT MODEL from it rather than from the primary:
--
--   * the budget degrade branch:  xlarge -> large, large -> medium, anything else -> small, then
--                                 "cheapest active approved model in that tier"
--   * the substitution branch:    a policy model missing from the registry is replaced by the
--                                 cheapest approved model of the POLICY's tier
--   * the capability branch:      fn_ai_route_tier_rank(v_tier) orders the substitute search, so a
--                                 vision or audio substitution lands near the declared tier
--
-- So a row declaring `medium` while naming a `large` model degrades TWO bands in one step. Measured:
-- procurement_reasoning was medium with a large model, and medium degrades to small, whose cheapest
-- approved row is openai/gpt-6-luna at $0.10/$0.50 — a TWENTY-FOLD drop in one step, on the class
-- that decides whether a supplier is verified against the mandatory six. One confirmed supplier
-- gates every RFQ, so that cliff admits an unverified company or keeps a real one out, at 80% of a
-- budget nobody is watching.
--
-- Under this file's matrix the bands are chosen so every degrade is ONE step:
--
--   reasoning classes   tier large  (qwen3.8-max $2.00/$6.00)
--                         -> degrade to cheapest medium = google/gemini-3.8-flash $0.75/$3.75, 2.67x
--   everything else     tier small  (glm-5.3-flash $0.15/$0.50)
--                         -> degrade within small = openai/gpt-6-luna $0.10/$0.50, 1.5x
--
-- Neither is a cliff, and the cheap row barely degrades at all, which is right: work that already
-- costs a fraction of a fils has nothing to give back.
--
-- SEVEN ROWS WERE ALREADY MISMATCHED BEFORE THIS PR (measured 23 Sep 2026): accountant_weekly_report,
-- finance_analysis, document_extraction_multimodal, knowledge_ingestion and redaction_detection
-- declared medium while naming a small model; summarization declared small while naming a medium one;
-- translation declared medium while naming a large one. §1 and §2 fix all but redaction_detection by
-- setting both together. This statement closes whatever is left, including rows this file never
-- named — because fixing the instances and leaving the mechanism means writing this comment again in
-- a month.
--
-- WHY IT IS SAFE ON A ROW THIS FILE DID NOT OTHERWISE TOUCH: the tier does not choose the model on
-- the normal path. v_model comes from model_primary; v_tier is only reported and used by the three
-- fallback branches above. Aligning it cannot change which model a healthy call uses, only which
-- model a DEGRADED or SUBSTITUTED call uses, and in every case it makes that choice nearer the
-- intent. redaction_detection's models and max_tokens stay exactly as they are (§2) — only its tier
-- label moves, and it has no caller.
update public.model_policy p set tier = r.tier
  from public.model_registry r
 where r.model_id = p.model_primary
   and p.active and p.tier <> 'none' and p.tier <> r.tier;

-- ── THE PROBE: the routing every seat now gets, printed by fn_ai_route itself ──────────────────
-- Read-only (fn_ai_route is STABLE) and it cannot reach a person.
--
-- ONE RESULT SET, VERDICT FIRST (corrected 23 Sep 2026 in review). The first draft printed the ROUTE
-- listing as its own select followed by the verdict as a second one — and scripts/apply_sql.mjs
-- returns only the LAST result set, so the evidence this file exists to produce could never have been
-- read. The verdict has to come first so the applier's PROBE FAILED scan (it exits 3) still sees it,
-- and the routes follow in the same set. A verdict row, never `raise notice` (the management API
-- discards NOTICE) and never `raise exception` (it would roll back the DDL above).
create temporary table probe_routes (seat text, task_class text, chosen text, fallback text,
                                     max_tokens int, tier text, use_llm boolean) on commit drop;

insert into probe_routes
select s.seat, s.tc,
       r ->> 'model', r ->> 'fallback', (r ->> 'max_tokens')::int, r ->> 'tier',
       (r ->> 'use_llm')::boolean
  from (values
    ('1_ceo', 'ceo_judgement'), ('1_ceo', 'ceo_approval_decision'), ('1_ceo', 'ceo_strategic_planning'),
    ('1_ceo', 'chief_of_staff_decision'), ('1_ceo', 'executive_report'),
    ('2_sales_engineer', 'quote_comparison'), ('2_sales_engineer', 'agent_reasoning'),
    ('2_sales_engineer', 'sales_engineer_reasoning'), ('2_sales_engineer', 'document_extraction'),
    ('2_sales_engineer', 'drawing_and_boq_analysis'), ('2_sales_engineer', 'redaction_detection'),
    ('2_sales_engineer', 'identity_redaction_verify'), ('2_sales_engineer', 'procurement_reasoning'),
    ('2_sales_engineer', 'knowledge_ingestion'), ('2_sales_engineer', 'json_extraction'),
    ('2_sales_engineer', 'speech_transcription'),
    ('3_customer_support', 'customer_portal_assistant'), ('3_customer_support', 'visitor_chat'),
    ('3_customer_support', 'customer_communication'), ('3_customer_support', 'wa_inbound'),
    ('3_customer_support', 'intent_detection'), ('3_customer_support', 'email_triage'),
    ('3_customer_support', 'translation'),
    ('4_accountant', 'finance_analysis'), ('4_accountant', 'accountant_expense_classification'),
    ('4_accountant', 'accountant_receipt_extraction'), ('4_accountant', 'accountant_weekly_report'),
    ('4_accountant', 'money_state_change'),
    ('5_marketing', 'marketing_copy'), ('5_marketing', 'content_drafting'),
    ('6_it_engineer', 'engineering_reasoning'), ('6_it_engineer', 'security_incident_analysis'),
    ('6_it_engineer', 'knowledge_validation'),
    ('7_deterministic', 'vat_calculation'), ('7_deterministic', 'supplier_matching'),
    ('7_deterministic', 'workflow_state_and_permissions')
  ) s(seat, tc)
  cross join lateral (select public.fn_ai_route(s.tc, null, null, null, false, null, null) r) x;

with bad as (
  select count(*) n from probe_routes
   where use_llm and (chosen is null
     or not exists (select 1 from public.model_registry r where r.model_id = chosen and r.active)
     or not exists (select 1 from public.llm_route_health h where h.model_id = chosen))
),
det as (select count(*) n from probe_routes where seat = '7_deterministic' and use_llm),
ruling as (
  -- founder_instruction 841: every reasoning class on qwen3.8-max, everything else on GLM, and
  -- speech_transcription on gemini because nothing else can hear.
  select count(*) n from probe_routes p
   where p.use_llm
     and case
           when p.task_class in (select task_class from qwen_classes)
             then p.chosen <> 'qwen/qwen3.8-max-0902'
           when p.task_class = 'speech_transcription'
             then p.chosen not like 'google/gemini-%'
           when p.task_class = 'redaction_detection' then false   -- deliberately untouched, §2
           else p.chosen <> 'z-ai/glm-5.3-flash'
         end
),
selfsame as (
  select count(*) n from public.model_policy
   where active and model_fallback is not null and model_fallback = model_primary
     and model_primary not in ('none', 'none/deterministic')
),
mismatch as (
  select count(*) n from public.model_policy p join public.model_registry r on r.model_id = p.model_primary
   where p.active and p.tier <> 'none' and p.tier <> r.tier
),
gaps as (
  select count(*) n from (
    select model_primary m from public.model_policy where active and model_primary <> 'none'
    union select model_fallback from public.model_policy where active and coalesce(model_fallback,'none') <> 'none'
  ) z where not exists (select 1 from public.llm_route_health h where h.model_id = z.m)
    or not exists (select 1 from public.model_registry r where r.model_id = z.m and r.active)
),
clamp as (
  select count(*) n from probe_routes
   where (task_class = 'document_extraction' and coalesce(max_tokens,0) < 3000)
      or (task_class = 'ceo_judgement' and coalesce(max_tokens,0) < 2000)
      or (task_class = 'identity_redaction_verify' and coalesce(max_tokens,0) < 2000)
      or (task_class = 'quote_comparison' and coalesce(max_tokens,0) < 10000)
),
none_rows as (select count(*) n from public.model_policy where active and tier = 'none'),
-- A TYPO IN qwen_classes WOULD BE SILENT. A misspelled class matches no policy row, so the real
-- class stays on the GLM row and the estate quietly routes a customer-facing surface to the internal
-- model — the exact thing 844 forbids, produced by a missing letter. Measured before the change: of
-- the 37 entries in that list, exactly two matched no active policy row, and those two are the ones
-- this file CREATES (ceo_judgement, identity_redaction_verify). After the inserts above the answer
-- must be zero.
listed_but_missing as (
  select count(*) n from qwen_classes q
   where not exists (select 1 from public.model_policy p
                      where p.task_class = q.task_class and p.active)),
-- And the split itself, so the verdict reports what it actually did rather than that it finished.
split_qwen as (
  select count(*) n from public.model_policy p
   where p.active and p.tier <> 'none' and p.model_primary = 'qwen/qwen3.8-max-0902'),
split_glm as (
  select count(*) n from public.model_policy p
   where p.active and p.tier <> 'none' and p.model_primary = 'z-ai/glm-5.3-flash'),
verdict as (
  select case
    when (select n from det)      > 0 then 'PROBE FAILED: ' || (select n from det)::text || ' tier=none class(es) now want a model'
    when (select n from none_rows) <> 17 then 'PROBE FAILED: ' || (select n from none_rows)::text || ' active tier=none rows, expected the 17 measured before the change'
    when (select n from bad)      > 0 then 'PROBE FAILED: ' || (select n from bad)::text || ' route(s) chose a model that is not a registered, measured route'
    when (select n from ruling)   > 0 then 'PROBE FAILED: ' || (select n from ruling)::text || ' class(es) do not match founder_instruction 844''s audience split'
    when (select n from selfsame) > 0 then 'PROBE FAILED: ' || (select n from selfsame)::text || ' active row(s) name the same model as primary AND fallback'
    when (select n from mismatch) > 0 then 'PROBE FAILED: ' || (select n from mismatch)::text || ' active row(s) declare a tier their own primary model does not have'
    when (select n from gaps)     > 0 then 'PROBE FAILED: ' || (select n from gaps)::text || ' active-policy model(s) are missing from model_registry or llm_route_health'
    when (select n from clamp)    > 0 then 'PROBE FAILED: ' || (select n from clamp)::text || ' class(es) still allow less than their caller asks for'
    when (select n from listed_but_missing) > 0
      then 'PROBE FAILED: ' || (select n from listed_but_missing)::text || ' entr(ies) in qwen_classes '
           || 'match no active model_policy row - a typo there silently leaves the real class on the '
           || 'internal model: ' || (select string_agg(q.task_class, ', ') from qwen_classes q
                where not exists (select 1 from public.model_policy p
                                   where p.task_class = q.task_class and p.active))
    else 'PROBE OK: founder_instruction 844''s audience split is live - '
         || (select n from split_qwen)::text || ' classes on qwen/qwen3.8-max-0902 (customer-facing, '
         || 'Arabic-capable, document-reading or a judgement), '
         || (select n from split_glm)::text || ' on z-ai/glm-5.3-flash (purely internal), '
         || 'speech_transcription on gemini because only gemini hears, and '
         || (select n from none_rows)::text || ' tier=none rows untouched. '
         || (select count(*) from probe_routes where use_llm)::text || ' sampled routes all resolve '
         || 'to a registered, measured model; ' || (select count(*) from probe_routes where not use_llm)::text
         || ' still deterministic; 0 tier mismatches, 0 self-fallbacks, 0 unmatched class names.'
    end as line
)
select 0 as ord, (select line from verdict) as line
union all
select 1, '  ' || seat || ' / ' || rpad(task_class, 34) || ' -> ' || rpad(coalesce(chosen, '(deterministic)'), 24)
          || ' fb ' || rpad(coalesce(fallback, '-'), 24) || ' max ' || lpad(coalesce(max_tokens, 0)::text, 5)
          || '  tier ' || coalesce(tier, '-')
  from probe_routes
 order by ord, line;

commit;
