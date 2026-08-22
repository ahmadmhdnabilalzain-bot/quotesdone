-- F03 - the catalogue content, and the two kinds of marking
--
-- THE FOUNDER'S RULING, section B: "Every text fixture must be clearly marked:
-- PHASE_D_FIXTURE_DO_NOT_PUBLISH."
--
-- F02 enforced that as a CHECK, and then the first attempt to seed the catalogue met the case the
-- rule cannot cover literally. Three of the values a Phase D fixture has to supply are read by a
-- predicate that compares them against a CLOSED VOCABULARY or a REGISTER, and a marker embedded in
-- them makes them wrong rather than marked:
--
--   GATE-016  lower(assignment_result) in ('delivered','accepted','sent')
--   GATE-010  lower(route_state) = 'confirmed'
--   BR-029    evidence_authority matches a row in public.mep_evidence_weight
--   BR-041    outcome_metric resolves in public.metric_definition
--   BR-039    rollback_ref resolves to an action class carrying a compensating action
--   BR-025/36 terms_hash and artifact_sha256 must be 64 hexadecimal characters
--
-- Writing PHASE_D_FIXTURE_DO_NOT_PUBLISH into any of those does not mark a fixture; it produces a
-- value the predicate correctly rejects, and the test then measures the marker rather than the
-- mechanism. So the constraint gains one exit, and the exit is itself a mechanism rather than a
-- comment: a row may omit the inline marker only if it states, in at least sixty characters, why
-- the value cannot carry one. There is no third option and no default.
--
-- Everything else -- every title, body, rationale, objective, analysis, recommendation, clause
-- selection and free-text reference -- carries the marker inline, and the CHECK still refuses it
-- otherwise.
--
-- WHAT IS NOT IN THIS FILE. terms_version, terms_hash, artifact_sha256, safe_package_ref,
-- provider_event_id, acceptance_ref, quote_id, transaction_id and every other REFERENCE key. Those
-- are not authorable: their correct value is whatever the canonical write produced in this
-- transaction, and they come from public.phase_d_scenario_record through the same one door (F02).

ALTER TABLE public.phase_d_fixture_catalogue
  ADD COLUMN IF NOT EXISTS marker_exemption text;

ALTER TABLE public.phase_d_fixture_catalogue
  DROP CONSTRAINT IF EXISTS phase_d_fixture_catalogue_text_is_marked;

ALTER TABLE public.phase_d_fixture_catalogue
  ADD CONSTRAINT phase_d_fixture_catalogue_text_is_marked
  CHECK (jsonb_typeof(value) <> 'string'
         OR value #>> '{}' like '%PHASE_D_FIXTURE_DO_NOT_PUBLISH%'
         OR length(btrim(coalesce(marker_exemption,''))) >= 60);

COMMENT ON COLUMN public.phase_d_fixture_catalogue.marker_exemption IS
  'WHY THIS TEXT FIXTURE CANNOT CARRY THE INLINE MARKER. Non-null only for a value a predicate '
  'compares against a closed vocabulary, a register or a digest shape, where an embedded marker '
  'would make the value wrong rather than marked. At least sixty characters, and the CHECK is what '
  'requires it (F03).';

-- The checksum covers marker_exemption too: a row that gained an exemption after the fact and did
-- not gain a new checksum is a row edited in the database and not in the committed artefact.
CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_catalogue_checksum()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.checksum := encode(sha256(convert_to(concat_ws(chr(31),
    new.fixture_id, new.fixture_version::text, coalesce(new.workflow_id,''),
    coalesce(new.step_id,''), new.scope, new.field_key, new.value::text, new.value_kind,
    coalesce(new.currency,''), new.expected_schema, new.expected_result,
    new.prohibited_external_use, coalesce(new.marker_exemption,'')), 'UTF8')), 'hex');
  return new;
end
$function$;

-- ================================================================================================
-- THE CATALOGUE
-- ================================================================================================
-- One statement, so a partial catalogue cannot exist. Column order:
--   fixture_id, version, workflow_id, step_id, scope, field_key, value, value_kind, currency,
--   expected_schema, expected_result, prohibited_external_use, marker_exemption
INSERT INTO public.phase_d_fixture_catalogue
 (fixture_id, fixture_version, workflow_id, step_id, scope, field_key, value, value_kind, currency,
  expected_schema, expected_result, prohibited_external_use, marker_exemption)
VALUES
-- ---- closed-vocabulary and register values (marker exempt, each with its reason) ---------------
('PDF-0001',1,null,null,'CONTEXT_KEY','assignment_result','"accepted"','text',null,
 'one of the three literals GATE-016 accepts: delivered, accepted, sent',
 'GATE-016 passes on the delivery arm and then decides suppression on notify_email',
 'Never send an assignment notification from this value; the effect adapter is mock-only.',
 'GATE-016 compares lower(assignment_result) against the closed set (delivered, accepted, sent). An embedded marker makes the value wrong rather than marked.'),
('PDF-0002',1,null,null,'CONTEXT_KEY','route_state','"confirmed"','text',null,
 'the single literal GATE-010 accepts: confirmed',
 'GATE-010 passes; only a confirmed route carries dispatch authority',
 'Never dispatch to a supplier from this value; no outbound adapter is reachable in Phase D.',
 'GATE-010 compares lower(route_state) against the single literal "confirmed". An embedded marker makes the value wrong rather than marked.'),
('PDF-0003',1,null,null,'CONTEXT_KEY','evidence_authority','"document_extraction"','text',null,
 'a weight_key, evidence_source or source_authority present in public.mep_evidence_weight',
 'BR-029 passes: the authority is ranked, so conflicting evidence can be kept in rank order',
 'This names a ranking row, not a customer document; never publish it as provenance.',
 'BR-029 resolves the value against public.mep_evidence_weight. A marker inside it resolves to no ranked authority, so the rule would fail for the marker rather than for the rank.'),
('PDF-0004',1,null,null,'CONTEXT_KEY','outcome_metric','"reveal_revenue_30d"','text',null,
 'a metric_key present in public.metric_definition and distinct from the activity metric',
 'BR-041 passes: success is declared on a defined outcome metric, not on activity',
 'Never report this metric as a Phase D result; the fixture asserts the key exists, not its value.',
 'BR-041 resolves the value against public.metric_definition. A marker inside it resolves to no defined metric, so the rule would fail for the marker rather than for the definition.'),
('PDF-0005',1,null,null,'CONTEXT_KEY','rollback_ref','"agent_action_work"','text',null,
 'an action_class in public.org_action_executor carrying a compensation_action_class',
 'BR-039 passes: the release names a rollback the estate can actually execute',
 'Naming a compensating action is not permission to run one; no executor is invoked by Phase D.',
 'BR-039 resolves the value against public.org_action_executor.action_class. A marker inside it resolves to no registered action class, so the rule would fail for the marker rather than for the rollback.'),
('PDF-0006',1,null,null,'CONTEXT_KEY','exception_authority_ref','"employee_authority:cpo:recommend"','text',null,
 'employee_authority:<agent_key>:<action_class> resolving to a row in public.employee_authority',
 'BR-043 passes on the delegated arm for an exception that touches no founder-reserved decision',
 'A delegated authority may never clear a founder boundary; BR-043 refuses that arm separately.',
 'BR-043 parses the value as employee_authority:<agent_key>:<action_class> and resolves it. A marker inside it resolves to no granted authority.'),
('PDF-0007',1,null,null,'CONTEXT_KEY','safe_package_approved_by','"compliance_and_privacy_officer"','text',null,
 'an active canonical role id that fn_phase_c_actor_may_own accepts',
 'BR-012 passes on the approver arm; GATE-013 then decides independence against the step owner',
 'This names an internal role, never a person to contact.',
 'BR-012 resolves the value with fn_phase_c_actor_may_own and GATE-013 tests it for independence. A marker inside it resolves to no canonical role.'),
('PDF-0008',1,null,null,'CONTEXT_KEY','notify_email','"PHASE_D_FIXTURE_DO_NOT_PUBLISH@example.invalid"','text',null,
 'an address in the reserved .invalid domain that BR-034 can parse as an email',
 'BR-034 passes: the address is not in public.email_suppressions, so consent is decidable',
 'example.invalid cannot receive mail by RFC 6761; no message may be addressed here or anywhere.',
 null),
('PDF-0009',1,null,null,'CONTEXT_KEY','monetary_state','"reconciled"','text',null,
 'a state BR-033 accepts as known money rather than quarantine',
 'BR-033 passes: the money is in a recognised state and is not reported as success while unknown',
 'A fixture monetary state is never evidence that a payment settled.',
 'BR-033 compares the value against the declared state set for the payment object. An embedded marker makes the value wrong rather than marked.'),

-- ---- booleans -------------------------------------------------------------------------------
('PDF-0010',1,null,null,'CONTEXT_KEY','platform_edited','false','boolean',null,
 'boolean; BR-018 refuses a platform-edited supplier revision',
 'BR-018 passes: the revision is supplier-authored',
 'Never present a fixture revision to a supplier or a customer.',null),
('PDF-0011',1,null,null,'CONTEXT_KEY','holdout_isolated','true','boolean',null,
 'boolean; GATE-023 requires the holdout to be isolated from the answer key',
 'GATE-023 has its evidence present and non-empty',
 'This asserts a property of a fixture evaluation, never of a live model.',null),
('PDF-0012',1,null,null,'CONTEXT_KEY','critical_risk_resolved','true','boolean',null,
 'boolean; GATE-030 requires critical risks resolved before the gate opens',
 'GATE-030 has its evidence present and non-empty',
 'Never quote this as a risk sign-off outside the Phase D transaction.',null),

-- ---- measurement ------------------------------------------------------------------------------
('PDF-0013',1,null,null,'CONTEXT_KEY','denominator','30','number',null,
 'a synthetic positive integer; a denominator of 0 is refused by the handler and by the effect service',
 'BR-040 passes and the MEASUREMENT_RECORD effect is produced over a non-zero denominator',
 'Never publish this ratio as a company measurement.',null),
('PDF-0014',1,null,null,'CONTEXT_KEY','numerator','27','number',null,
 'a synthetic non-negative integer no greater than the denominator',
 'The measurement effect records 27/30 and the handler output validates',
 'Never publish this ratio as a company measurement.',null),
('PDF-0015',1,null,null,'CONTEXT_KEY','formula','"PHASE_D_FIXTURE_DO_NOT_PUBLISH numerator divided by denominator over the stated window"','text',null,
 'free text naming the arithmetic; BR-040 requires it to be present',
 'BR-040 passes: the measurement states its formula rather than implying one',
 'Never publish as a metric definition.',null),
('PDF-0016',1,null,null,'CONTEXT_KEY','window','"PHASE_D_FIXTURE_DO_NOT_PUBLISH 2026-08-01T00:00:00Z..2026-08-21T00:00:00Z"','text',null,
 'free text naming the measurement window; BR-040 requires it to be present',
 'BR-040 passes: the measurement states the window it covers',
 'Never publish as a reporting period.',null),

-- ---- free-text references the generic gates require to be present and non-empty ----------------
('PDF-0017',1,null,null,'CONTEXT_KEY','backend_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH backend-contract/phase-d/v1"','text',null,
 'free text naming the backend contract under review','GATE-022 evidence present and non-empty',
 'Never treat as a released backend contract.',null),
('PDF-0018',1,null,null,'CONTEXT_KEY','frontend_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH frontend-surface/phase-d/v1"','text',null,
 'free text naming the frontend surface under review','GATE-022 evidence present and non-empty',
 'Never treat as a released frontend surface.',null),
('PDF-0019',1,null,null,'CONTEXT_KEY','requirement_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH requirement/phase-d/v1"','text',null,
 'free text naming the requirement under review','GATE-022 evidence present and non-empty',
 'Never treat as an accepted product requirement.',null),
('PDF-0020',1,null,null,'CONTEXT_KEY','test_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH test-evidence/phase-d/v1"','text',null,
 'free text naming the test evidence','GATE-022 and GATE-024 evidence present and non-empty',
 'Never quote as a passing test run.',null),
('PDF-0021',1,null,null,'CONTEXT_KEY','ux_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH ux-specification/phase-d/v1"','text',null,
 'free text naming the UX specification','GATE-022 evidence present and non-empty',
 'Never treat as an approved UX specification.',null),
('PDF-0022',1,null,null,'CONTEXT_KEY','security_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH security-review/phase-d/v1"','text',null,
 'free text naming the security review','GATE-024 evidence present and non-empty',
 'Never quote as a completed security review.',null),
('PDF-0023',1,null,null,'CONTEXT_KEY','operations_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH operations-readiness/phase-d/v1"','text',null,
 'free text naming operational readiness','GATE-024 evidence present and non-empty',
 'Never quote as an operational readiness sign-off.',null),
('PDF-0024',1,null,null,'CONTEXT_KEY','contradiction_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH contradiction-log/phase-d/v1"','text',null,
 'free text naming the contradiction log','GATE-026 evidence present and non-empty',
 'Never publish as a knowledge contradiction finding.',null),
('PDF-0025',1,null,null,'CONTEXT_KEY','freshness_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH freshness-check/phase-d/v1"','text',null,
 'free text naming the freshness check','GATE-026 evidence present and non-empty',
 'Never publish as a knowledge freshness guarantee.',null),
('PDF-0026',1,null,null,'CONTEXT_KEY','lineage_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH lineage/phase-d/v1"','text',null,
 'free text naming the data lineage','GATE-025 evidence present and non-empty',
 'Never publish as a data lineage record.',null),
('PDF-0027',1,null,null,'CONTEXT_KEY','metric_definition_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH metric-definition/phase-d/v1"','text',null,
 'free text naming the metric definition under review','GATE-025 evidence present and non-empty',
 'Never publish as a company metric definition.',null),
('PDF-0028',1,null,null,'CONTEXT_KEY','data_verification_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH data-verification/phase-d/v1"','text',null,
 'free text naming the data verification','GATE-029 evidence present and non-empty',
 'Never quote as a data verification result.',null),
('PDF-0029',1,null,null,'CONTEXT_KEY','security_verification_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH security-verification/phase-d/v1"','text',null,
 'free text naming the security verification','GATE-029 evidence present and non-empty',
 'Never quote as a security verification result.',null),
('PDF-0030',1,null,null,'CONTEXT_KEY','service_verification_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH service-verification/phase-d/v1"','text',null,
 'free text naming the service verification','GATE-029 evidence present and non-empty',
 'Never quote as a service verification result.',null),
('PDF-0031',1,null,null,'CONTEXT_KEY','verification_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH verification/phase-d/v1"','text',null,
 'free text naming the verification evidence','GATE-030 evidence present and non-empty',
 'Never quote as a verification result.',null),
('PDF-0032',1,null,null,'CONTEXT_KEY','legal_review_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH legal-review/phase-d/v1"','text',null,
 'free text naming the legal review','GATE-028 evidence present and non-empty',
 'Never present as legal advice or as a completed legal review.',null),
('PDF-0033',1,null,null,'CONTEXT_KEY','control_exception_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH control-exception/phase-d/v1"','text',null,
 'free text naming the control exception','GATE-027 evidence present and non-empty',
 'Never treat as an approved control exception.',null),
('PDF-0034',1,null,null,'CONTEXT_KEY','reconciliation_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH reconciliation/phase-d/v1"','text',null,
 'free text naming the reconciliation','GATE-027 evidence present and non-empty',
 'Never treat as a financial reconciliation.',null),
('PDF-0035',1,null,null,'CONTEXT_KEY','model_eval_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH model-evaluation/phase-d/v1"','text',null,
 'free text naming the model evaluation','GATE-023 evidence present and non-empty',
 'No model was evaluated; paid inference is held for the whole of Phase D.',null),
('PDF-0036',1,null,null,'CONTEXT_KEY','workflow_eval_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH workflow-evaluation/phase-d/v1"','text',null,
 'free text naming the workflow evaluation','GATE-023 evidence present and non-empty',
 'No workflow evaluation was run against a live model.',null),
('PDF-0037',1,null,null,'CONTEXT_KEY','template_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH notification-template/phase-d/v1"','text',null,
 'free text naming the notification template','GATE-016 evidence present and non-empty',
 'No template may be rendered and sent; the external adapter is mock-only.',null),
('PDF-0038',1,null,null,'CONTEXT_KEY','financial_action_key','"PHASE_D_FIXTURE_DO_NOT_PUBLISH refund_decision"','text',null,
 'free text naming the financial action under decision','GATE-020 names the action beside the recorded decision',
 'Naming a financial action is never authority to execute one; every refund needs the founder.',null),
('PDF-0039',1,null,null,'CONTEXT_KEY','artifact_ref','"PHASE_D_FIXTURE_DO_NOT_PUBLISH artifact/phase-d/fixture-artifact-v1"','text',null,
 'free text naming the artifact whose digest BR-036 resolves',
 'BR-036 names the artifact; the digest beside it is what the rule actually resolves',
 'Never publish the fixture artifact or its reference.',null),

-- ---- the content a deterministic handler must not invent ---------------------------------------
('PDF-0040',1,null,null,'CONTEXT_KEY','supplier_payload',
 '{"scope":"PHASE_D_FIXTURE_DO_NOT_PUBLISH — supply and install 12 units to the stated specification","quantities":[{"item":"unit","qty":12}],"customer_identity":"withheld by design"}',
 'object',null,
 'an object carrying scope and quantities and no customer identity token of any kind',
 'BR-011 passes: 0 customer identity matches and 0 identity-shaped tokens in the payload itself',
 'This payload is what a supplier would see; it must never be sent, and it names no customer.',null),
('PDF-0041',1,null,null,'CONTEXT_KEY','assumptions',
 '["PHASE_D_FIXTURE_DO_NOT_PUBLISH — only the inputs named in this call were used","PHASE_D_FIXTURE_DO_NOT_PUBLISH — no external source was consulted and no paid inference was requested"]',
 'array',null,
 'an array of at least one stated assumption; BR-042 requires the analysis to name them',
 'BR-042 passes: the analysis states its assumptions rather than implying none',
 'Never publish as the assumptions behind a real analysis.',null),
('PDF-0042',1,null,null,'EFFECT_PAYLOAD','kind','"PHASE_D_FIXTURE_DO_NOT_PUBLISH partnership"','text',null,
 'free text; public.opportunity.kind is NOT NULL with no default',
 'the DOMAIN_MUTATION effect for partnership_opportunity writes instead of raising 23502',
 'Never surface as a real partnership opportunity.',null),
('PDF-0043',1,null,null,'EFFECT_PAYLOAD','title','"PHASE_D_FIXTURE_DO_NOT_PUBLISH — Phase D fixture record"','text',null,
 'free text; opportunity.title, os_incidents.title and org_tasks.title are all NOT NULL',
 'the effect writes a titled record instead of raising 23502',
 'Never display this title on any customer, supplier or founder surface.',null),
('PDF-0044',1,null,null,'EFFECT_PAYLOAD','goal','"PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture objective, not a company goal"','text',null,
 'free text; public.company_goals.goal is NOT NULL',
 'the executive-objective effect writes instead of raising 23502',
 'Never report as a company goal; it has no owner and no target.',null),
('PDF-0045',1,null,null,'EFFECT_PAYLOAD','objective','"PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture department objective"','text',null,
 'free text; public.department_objective.objective is NOT NULL',
 'the department-mandate effect writes instead of raising 23502',
 'Never report as a department objective.',null),
('PDF-0046',1,null,null,'EFFECT_PAYLOAD','body',
 '"PHASE_D_FIXTURE_DO_NOT_PUBLISH — fixture content-draft body. This text exists to prove that a deterministic handler receives its content as input rather than generating it. It must never be published, sent, posted or shown to a customer."',
 'text',null,
 'free text; public.content_drafts.body is NOT NULL',
 'the marketing-content effect writes a draft instead of raising 23502',
 'Never publish, post or send. The draft is created inside a transaction that is aborted.',null),
('PDF-0047',1,null,null,'EFFECT_PAYLOAD','analysis',
 '{"note":"PHASE_D_FIXTURE_DO_NOT_PUBLISH — fixture comparison analysis","method":"deterministic reconciliation of the named inputs","paid_inference_used":false}',
 'object',null,
 'an object; public.quote_comparisons.analysis is NOT NULL',
 'the comparison effect writes instead of raising 23502',
 'Never show to a customer as a quote comparison.',null),
('PDF-0048',1,null,null,'EFFECT_PAYLOAD','company_name','"ZZ DEMO — PHASE_D_FIXTURE_DO_NOT_PUBLISH supplier"','text',null,
 'free text; public.leads.company_name is NOT NULL',
 'the lead effect writes instead of raising 23502',
 'Never contact; the row carries no email and no phone by design.',null),
('PDF-0049',1,null,null,'EFFECT_PAYLOAD','quote_amount','1000','number','AED',
 'a declared synthetic amount; public.quotes.quote_amount is NOT NULL and CHECKed > 0',
 'the quotation effect writes a priced quote instead of raising 23502',
 'A synthetic amount. Never invoice, quote, reveal or report it as revenue.',null),
('PDF-0050',1,null,null,'EFFECT_PAYLOAD','refund_amount_fils','10000','number','AED',
 'a declared synthetic amount in fils; the refund case records it and executes nothing',
 'the refund-case effect writes a requested case; GATE-020 still requires the recorded decision',
 'No refund is ever executed by Phase D. Every refund needs the founder, at any amount.',null),
('PDF-0051',1,null,null,'EFFECT_PAYLOAD','reason_code','"other"','text',null,
 'one of the reason codes public.refunds accepts',
 'the refund case is classified rather than raising 23502 on reason_code',
 'Never treat as a real dispute classification.',
 'public.refunds.reason_code is a closed vocabulary; an embedded marker is not one of its values.'),
('PDF-0052',1,null,null,'EFFECT_PAYLOAD','recipient','"PHASE_D_FIXTURE_DO_NOT_PUBLISH@example.invalid"','text',null,
 'an address in the reserved .invalid domain; EXTERNAL_EFFECT_INTENT requires a recipient',
 'the external-effect intent records provider_mode mock against a recipient that cannot receive',
 'example.invalid cannot receive mail by RFC 6761. The adapter is mock-only and sends nothing.',null),
('PDF-0053',1,null,null,'EFFECT_PAYLOAD','consent_basis',
 '"PHASE_D_FIXTURE_DO_NOT_PUBLISH — no consent is claimed; this intent is recorded and never delivered"','text',null,
 'free text stating the consent basis; EXTERNAL_EFFECT_INTENT refuses an intent without one',
 'the intent is recorded with an explicit statement that no consent is asserted',
 'Never send. The basis explicitly disclaims consent.',null),
('PDF-0054',1,null,null,'EFFECT_PAYLOAD','verdict','"approved"','text',null,
 'a verdict public.review_chain accepts',
 'the REVIEW_VERDICT effect records the verdict; BR-002 still decides reviewer independence',
 'Never present as a real internal review outcome.',
 'public.review_chain records a closed verdict vocabulary; an embedded marker is not one of its values.'),
('PDF-0055',1,null,null,'HANDLER_OUTPUT','rationale',
 '"PHASE_D_FIXTURE_DO_NOT_PUBLISH — the verdict follows from the named inputs and the frozen acceptance criteria; no external source and no paid inference were used."','text',null,
 'free text; a review output that names no rationale is an assertion',
 'the REVIEW_HANDLER output validates against its own contract',
 'Never quote as a review rationale.',null),
('PDF-0056',1,null,null,'HANDLER_OUTPUT','recommendation',
 '"PHASE_D_FIXTURE_DO_NOT_PUBLISH — proceed on the fixture scenario only. This is not an executive recommendation and must not be acted on."','text',null,
 'free text; an executive decision step must name what it recommends',
 'the DECISION_HANDLER output validates against its own contract',
 'Never act on. It recommends nothing about the real business.',null),
('PDF-0057',1,null,null,'CONTEXT_KEY','campaign_objective',
 '"PHASE_D_FIXTURE_DO_NOT_PUBLISH — fixture campaign objective; no audience, no budget, no channel"','text',null,
 'free text naming the campaign objective',
 'the marketing workflow has an objective to carry rather than inventing one',
 'Never launch, boost or fund. No channel is reachable from Phase D.',null),
('PDF-0058',1,null,null,'CONTEXT_KEY','contract_clause_selection',
 '"PHASE_D_FIXTURE_DO_NOT_PUBLISH — clause set A, unamended, selected for fixture purposes only"','text',null,
 'free text naming the clause selection',
 'the legal workflow carries an explicit clause selection rather than inventing one',
 'Never present as an executed contract term.',null),
('PDF-0059',1,null,null,'CONTEXT_KEY','market_analysis_result',
 '"PHASE_D_FIXTURE_DO_NOT_PUBLISH — fixture market analysis; no market was researched and no provider was called"','text',null,
 'free text naming the market analysis result',
 'the intelligence workflow carries a stated result rather than inventing one',
 'Never publish as market intelligence. Nothing was researched.',null),
('PDF-0060',1,null,null,'CONTEXT_KEY','category_analysis',
 '"PHASE_D_FIXTURE_DO_NOT_PUBLISH — fixture category analysis; the category set is the frozen one and nothing was scored"','text',null,
 'free text naming the category analysis',
 'the category workflow carries a stated analysis rather than inventing one',
 'Never publish as a category assessment.',null),
('PDF-0061',1,null,null,'CONTEXT_KEY','document_extraction_result',
 '{"method":"deterministic","paid_model_used":false,"fields":{"note":"PHASE_D_FIXTURE_DO_NOT_PUBLISH — fixture extraction, no document was parsed"}}',
 'object',null,
 'an object stating the extraction method and that no paid model was used',
 'the document workflow carries an explicit extraction result rather than inventing one',
 'Never treat as the contents of a customer document.',null),
('PDF-0062',1,null,null,'CONTEXT_KEY','opportunity_kind','"PHASE_D_FIXTURE_DO_NOT_PUBLISH partnership"','text',null,
 'free text; the opportunity workflow needs a kind and must not choose one',
 'the opportunity step carries a stated kind rather than inventing one',
 'Never surface as a real partnership opportunity.',null)
ON CONFLICT (fixture_id) DO NOTHING;
