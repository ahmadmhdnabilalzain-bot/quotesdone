// Phase B identity resolution.
//
// The package addresses roles by descriptive name; the founder-approved Phase A
// organization stores them under its own keys.  `payments_billing_manager` and
// `payments_and_billing_manager` are the same employee.  Every mapping below was
// confirmed one-to-one against the live 90 canonical roles on 15 Aug 2026.
//
// These are ALIASES, not organization changes.  org_role_alias carries no Phase A
// frozen digest and no z90_phase_a_freeze trigger, so teaching the estate a second
// name for an existing role leaves fn_phase_a_baseline_drift() at zero rows.
// Nothing here creates, renames, merges, moves or retires a role.

/** package token -> live canonical role_id (org_role.role_id, status='active'). */
export const PACKAGE_ROLE_ALIASES = {
  account_manager: 'account_management',
  accounts_payable_specialist: 'accounts_payable',
  agent_prompt_engineer: 'prompt_engineer',
  ai_quality_assurance_reviewer: 'ai_quality_reviewer',
  billing_reconciliation_specialist: 'billing_operations',
  boq_specification_analyst: 'boq_analyst',
  brand_creative_manager: 'brand_and_creative',
  business_development_manager: 'business_development',
  category_knowledge_curator: 'category_curator',
  chief_product_technology_officer: 'cto',
  collections_revenue_assurance_specialist: 'collections_and_revenue_assurance',
  compliance_privacy_officer: 'compliance_and_privacy_officer',
  construction_civil_domain_specialist: 'spec_construction',
  content_strategy_copy_specialist: 'content_strategy_and_copy',
  coo: 'chief_operating_officer',
  crm_revenue_operations_manager: 'crm_and_revenue_operations',
  culture_performance_manager: 'culture_and_performance_manager',
  customer_onboarding_specialist: 'customer_onboarding',
  customer_retention_specialist: 'customer_retention',
  customer_support_specialist: 'customer_support',
  drawing_cad_analyst: 'drawing_analyst',
  fp_a_analyst: 'fpna_analyst',
  fraud_reviewer: 'fraud_analyst',
  industrial_energy_domain_specialist: 'spec_industrial',
  inquiry_quality_scoring_analyst: 'inquiry_quality_analyst',
  interior_fitout_domain_specialist: 'spec_fitout',
  it_operations_site_reliability_engineer: 'it_operations_engineer',
  learning_development_manager: 'learning_and_development_manager',
  lifecycle_channel_operations_specialist: 'lifecycle_channel_operations',
  mep_domain_specialist: 'spec_mep',
  model_evaluation_reviewer: 'model_evaluator',
  organisation_design_lead: 'organization_designer',
  payments_billing_manager: 'payments_and_billing_manager',
  product_optimisation_engineer: 'product_optimization_engineer',
  project_coordinator_pmo: 'project_coordinator',
  qa_release_management_director: 'quality_and_release_director',
  quote_evaluation_specialist: 'quote_evaluation',
  rfq_success_specialist: 'rfq_success',
  risk_governance_manager: 'risk_and_governance_manager',
  social_media_community_manager: 'social_media_and_community',
  supplier_coverage_liquidity_specialist: 'supplier_coverage',
  supplier_retention_specialist: 'supplier_retention',
  supplier_verification_reviewer: 'supplier_verification',
  taxonomy_governance_manager: 'taxonomy_manager',
  trust_safety_manager: 'trust_and_safety_manager',
  visual_design_specialist: 'visual_design',
};

/**
 * Dynamic actors: tokens that are deliberately NOT a standing role.  Each resolves
 * at runtime; none may hold accountability for a required step on its own.
 * The five `*_slot` entries are the ALL-scope structural objects in the business
 * object registry, whose "accountable role" is whichever owner the run produced.
 */
export const DYNAMIC_ACTORS = {
  // declared in PHASE_B_DYNAMIC_ACTOR_PLACEHOLDER_REGISTRY.csv
  founder: 'external_decision_boundary',
  relevant_category_overlay: 'single_or_set_overlay',
  relevant_domain_specialist: 'single_dynamic_role',
  department_heads: 'dynamic_role_set',
  affected_department_head: 'single_dynamic_role',
  relevant_business_owner: 'single_dynamic_role',
  business_owner: 'single_dynamic_role',
  relevant_manager: 'single_dynamic_role',
  current_step_owner: 'runtime_placeholder',
  workflow_engine: 'system_actor',
  // prose spellings of the same placeholders, used in the contributors columns that
  // Phase A froze verbatim in org_workflow_ownership.  Mapped, not invented.
  'category overlay': 'single_or_set_overlay',
  'category overlays': 'single_or_set_overlay',
  'broad domain specialist': 'single_dynamic_role',
  'broad domain specialists': 'single_dynamic_role',
  'department heads': 'dynamic_role_set',
  relevant_department_head: 'single_dynamic_role',
  // structural slots on the five ALL-scope business objects
  workflow_accountable_owner: 'structural_slot',
  step_accountable_owner: 'structural_slot',
  sending_role: 'structural_slot',
  independent_reviewer: 'structural_slot',
  exception_owner: 'structural_slot',
};

/** Placeholders that may never hold accountability for a required workflow step. */
export const NON_ACCOUNTABLE_ACTORS = new Set([
  'relevant_category_overlay', 'relevant_domain_specialist', 'department_heads',
  'affected_department_head', 'relevant_business_owner', 'business_owner',
  'relevant_manager', 'current_step_owner', 'workflow_engine',
  'category overlay', 'category overlays', 'broad domain specialist',
  'broad domain specialists', 'department heads', 'relevant_department_head',
  'workflow_accountable_owner', 'step_accountable_owner', 'sending_role',
  'independent_reviewer', 'exception_owner',
]);

/**
 * Corrections to the committed package.  The package is checksummed and must not be
 * edited in place, so a defect found in it is recorded here with its evidence and
 * applied when the deliverable registry is derived.
 */
export const PACKAGE_ERRATA = [
  {
    file: 'PHASE_B_EXCEPTION_ESCALATION_MATRIX.csv',
    id: 'EX-006',
    defect: 'row is short one cell: escalation_owner_role_id is absent, so required_response '
      + 'and closure_condition are each shifted one column left and the last column is empty.',
    evidence: 'EX-006 escalation_owner_role_id reads "Block activation/verification and correct '
      + 'displayed/recorded version." — a sentence, where every other one of the 50 rows holds a role id.',
    correction: {
      escalation_owner_role_id: 'general_counsel',
      required_response: 'Block activation/verification and correct displayed/recorded version.',
      closure_condition: 'Exact displayed and accepted version/hash reconcile.',
    },
    rationale: 'Detection owner is compliance_and_privacy_officer, so escalation cannot return to the '
      + 'same identity without a creator/reviewer collision. Terms text is founder-reserved (FDR-002) '
      + 'and the founder boundary mapping assigns "General Counsel blocks until approval" (FDR-007); '
      + 'general_counsel owns W28 legal/compliance verdicts and is independent of the detector.',
  },
  {
    file: 'PHASE_B_WORKFLOW_REGISTRY.csv',
    id: 'W13',
    defect: 'primary_object is "notification_delivery", which is not an object_id in '
      + 'PHASE_B_BUSINESS_OBJECT_REGISTRY.csv. The other 29 workflows all name a registered object.',
    evidence: 'The object registry holds exactly two objects governed by W13: "notification" and '
      + '"notification_attempt". There is no "notification_delivery" row.',
    correction: { primary_object: 'notification' },
    rationale: '"notification" is the canonical record W13 produces and reaches a delivered/failed/'
      + 'suppressed state on; "notification_attempt" is the per-try child, not the primary object.',
  },
  {
    file: 'PHASE_B_WORKFLOW_STEP_REGISTRY.csv',
    id: 'W22-S07',
    defect: 'W22 is the only workflow of the 30 with no step_type="closure", so GATE-008 '
      + '(closure completeness) had no step to attach to in the product delivery workflow.',
    evidence: 'For the other 29 workflows, step_type="closure" and next_step_if_pass='
      + '"WORKFLOW_COMPLETE" select the identical step, and no closure-typed step is ever non-final. '
      + 'W22-S07 "Release go/no-go" is final and points at WORKFLOW_COMPLETE.',
    correction: { is_closure_step: true },
    rationale: 'The closure anchor is derived as (step_type = closure OR next_step_if_pass = '
      + 'WORKFLOW_COMPLETE), proven equivalent on the other 29 workflows. This attaches GATE-008 to '
      + 'W22 rather than leaving it unenforced, keeps the declared 257-step count, and invents no work: '
      + 'the step, its owner and its output are unchanged.',
  },
];

/**
 * A step is the workflow's closure anchor when it carries step_type="closure" OR it is the
 * step that reaches WORKFLOW_COMPLETE.  Proven equivalent for 29 of 30 workflows; see the
 * W22-S07 erratum for the thirtieth.
 */
export const isClosureStep = s =>
  s.step_type === 'closure' || s.next_step_if_pass === 'WORKFLOW_COMPLETE';

/**
 * The single declared exception to "an overlay may never be accountable": the technical
 * evaluation step.  Overlays may contribute to W05, W06, W07, W10 and W14 (master spec §12),
 * and may hold accountability only for an analysis step inside that scope.
 */
export const OVERLAY_ELIGIBLE_WORKFLOWS = new Set(['W05', 'W06', 'W07', 'W10', 'W14']);
export const OVERLAY_ELIGIBLE_STEP_TYPES = new Set(['analysis']);

/** Resolve a package token. -> {kind, role_id?, actor_type?} */
export function makeResolver({ liveRoles, liveAliases }) {
  const byId = new Map(liveRoles.map(r => [r.role_id, r]));
  const byAlias = new Map();
  for (const a of liveAliases) if (!byAlias.has(a.alias)) byAlias.set(a.alias, a.role_id);

  return function resolve(token) {
    const t = String(token ?? '').trim();
    if (!t) return { kind: 'empty' };
    if (DYNAMIC_ACTORS[t]) return { kind: 'dynamic', actor_type: DYNAMIC_ACTORS[t], token: t };
    let id = null;
    if (byId.has(t)) id = t;
    else if (PACKAGE_ROLE_ALIASES[t]) id = PACKAGE_ROLE_ALIASES[t];
    else if (byAlias.has(t)) id = byAlias.get(t);
    if (!id) return { kind: 'unresolved', token: t };
    const r = byId.get(id);
    if (!r) return { kind: 'unresolved', token: t, note: `alias -> missing role ${id}` };
    if (r.status !== 'active') return { kind: 'inactive', token: t, role_id: id, status: r.status };
    if (r.runtime_mode === 'knowledge_overlay') return { kind: 'overlay', token: t, role_id: id };
    return { kind: 'canonical', token: t, role_id: id, department_id: r.primary_department_id };
  };
}
