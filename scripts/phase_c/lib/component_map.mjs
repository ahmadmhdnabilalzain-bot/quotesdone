// Phase C: assign every measured component to a canonical workflow, a system actor,
// an authority class and a trace policy — deterministically, from what the component IS.
//
// Phase B already assigned a target workflow to 719 of the 1,799 components (cron jobs,
// edge functions, triggers, state tables, frontend routes and runtime workflow
// definitions).  Those assignments are reused verbatim: the instruction was to build on
// the Phase B inventory, not redo it.  What is NEW here is the 1,000 database routines,
// which Phase B never inventoried, and the per-component accountability that Phase B
// recorded as absent.
//
// Nothing below guesses a role.  A component's accountable role is the accountable role
// of the canonical workflow it serves (public.phase_b_workflow.accountable_role_id).  A
// component that serves every workflow equally has SYSTEM scope, and its accountable role
// is the one the Phase C system-actor registry names for its actor — that is the master
// spec's §3.5 rule, not an invention: the system actor executes, the named role owns.

import { CRON_TO_WORKFLOW, EDGE_TO_WORKFLOW, ROUTE_TO_WORKFLOW, RUNTIME_WORKFLOW_TO_CANONICAL }
  from '../../phase_b/lib/crosswalk_map.mjs';

export { CRON_TO_WORKFLOW, EDGE_TO_WORKFLOW, ROUTE_TO_WORKFLOW, RUNTIME_WORKFLOW_TO_CANONICAL };

/**
 * Database routine name prefix/pattern -> canonical workflow.
 * Ordered: the FIRST match wins, so the specific patterns precede the generic ones.
 * Every entry names a workflow the routine's own name states it serves.
 */
export const ROUTINE_PATTERNS = [
  // --- platform plumbing that is not one of the 30 business workflows -----------------
  [/^(pg_|pgrst|uuid_|gtrgm|gin_|gbt_|citext|hmac|crypt|digest|armor|dearmor|encrypt|decrypt|hash_|pgp_|gen_random|gen_salt|set_limit|show_limit|similarity|word_similarity|strict_word|unaccent|lo_|halfvec|sparsevec|vector|ivfflat|hnsw|l2_|inner_product|cosine_|jaccard|hamming|binary_quantize|subvector|avg$|sum$|array_to_|to_tsvector|websearch)/i, 'OUT_OF_SCOPE'],
  [/^fn_(i18n|translate|locale)/i, 'OUT_OF_SCOPE'],
  [/(prune|archive_completed|vacuum|reindex)/i, 'OUT_OF_SCOPE'],

  // --- the canonical Phase C runtime itself -------------------------------------------
  [/^fn_phase_c_/i, 'ALL'],
  [/^fn_founder_command/i, 'ALL'],
  [/^fn_phase_[ab]_/i, 'ALL'],

  // --- W01 founder mandate to company objectives ---------------------------------------
  [/^fn_(founder|ceo|exec_meeting|board|day_conductor|dept_plan|company_selfknow|strategy)/i, 'W01'],
  [/(objective|mandate|goal_decompose)/i, 'W01'],
  // --- W02 target miss and corrective management ---------------------------------------
  [/^fn_(os_|ws_|kpi|indices|improvement|opportunity|evolution|scenario|reflect|self_review|what_if|report_drilldown|simulat)/i, 'W02'],
  [/(kpi|target_miss|corrective|drilldown)/i, 'W02'],
  // --- W03 customer acquisition ---------------------------------------------------------
  [/(^fn_)?(lead|invite|boost|acquisition|founding_rank)/i, 'W03'],
  // --- W04 customer registration and onboarding ----------------------------------------
  [/(customer_onboard|registration|signup|otp|auth_|login|session|magic_link|profile)/i, 'W04'],
  // --- W05/W06 inquiry intake, qualification, routing ----------------------------------
  [/(inquiry|rfq_clarify|rfq_score|rfq_quality|qualif)/i, 'W05'],
  [/(route_inquiry|category_route|intent_router|taxonomy|category_readiness)/i, 'W06'],
  // --- W07 document/BOQ/drawing processing ---------------------------------------------
  [/(document|^fn_doc|_doc_|boq|drawing|cad|extract_text|pdf|xlsx|ocr)/i, 'W07'],
  // --- W08 supplier-safe payload -------------------------------------------------------
  [/(redact|supplier_safe|mask)/i, 'W08'],
  // --- W09/W10 supplier onboarding and verification ------------------------------------
  [/(supplier_onboard|supplier_invite|supplier_registration|supplier_portal|claim)/i, 'W09'],
  [/(capability|licen[cs]e|kyc|verif|trade_licen)/i, 'W10'],
  // --- W11 supplier coverage -----------------------------------------------------------
  [/(supply_gap|coverage|scrape|apify|yello)/i, 'W11'],
  // --- W12 matching and dispatch -------------------------------------------------------
  [/(match|dispatch|redispatch|assignment)/i, 'W12'],
  // --- W13 notification delivery -------------------------------------------------------
  [/(notif|email|sms|whatsapp|^fn_wa_|_wa_|outbox_send|send_|suppress|unsubscribe|optin|inbox)/i, 'W13'],
  // --- W14/W15 quotation, comparison and reveal ----------------------------------------
  [/(quote|quotation)/i, 'W14'],
  [/(reveal|comparison|compare)/i, 'W15'],
  // --- W16 payment, billing, reconciliation --------------------------------------------
  [/(payment|billing|invoice|stripe|subscription|dues|collections|reconcil|gl_sync|ledger|money)/i, 'W16'],
  // --- W17 refund, dispute, fraud ------------------------------------------------------
  [/(refund|dispute|fraud|chargeback|ban_)/i, 'W17'],
  // --- W18 customer support and retention ----------------------------------------------
  [/(support|complaint|ticket|retention|csat|faq)/i, 'W18'],
  // --- W19 supplier retention ----------------------------------------------------------
  [/(supplier_success|supplier_score|supplier_risk|supplier_retention|supplier_health)/i, 'W19'],
  // --- W20 marketing content lifecycle -------------------------------------------------
  [/(marketing|blog|social|seo|content_revise|brand|creative|campaign|postiz|meta_ads|reputation)/i, 'W20'],
  // --- W21 strategic partnership -------------------------------------------------------
  [/(partnership|government_relation|mou)/i, 'W21'],
  // --- W22 product discovery to delivery -----------------------------------------------
  [/(deploy|github|src_|vercel|feature_flag|product_)/i, 'W22'],
  // --- W23 AI/model/prompt change ------------------------------------------------------
  [/(^fn_ai_|_ai_|model|prompt|llm|embed|eval|benchmark|gateway|token|inference)/i, 'W23'],
  // --- W24 release and production approval ---------------------------------------------
  [/(release|qa_|smoke|test_suite|artifact_review|autonomy_audit|approval_trace)/i, 'W24'],
  // --- W25 data reporting and forecasting ----------------------------------------------
  [/(report|snapshot|forecast|analytic|^fn_bi_|metric|dashboard|chart|stats)/i, 'W25'],
  // --- W26 knowledge creation and validation -------------------------------------------
  [/(^fn_kb_|_kb_|knowledge|corpus|memory|graph_|sop|curric|exam|learn)/i, 'W26'],
  // --- W27 financial planning and close ------------------------------------------------
  [/(budget|fpna|cash|close_period|expense|cost_)/i, 'W27'],
  // --- W28 legal, compliance, risk -----------------------------------------------------
  [/(legal|complian|pdpl|privacy|policy|regulat|contract|terms|consent|retention_purge|risk_)/i, 'W28'],
  // --- W29 security incident and reliability -------------------------------------------
  [/(security|incident|health|uptime|resilien|backup|dr_drill|watch|alert|audit_log|breach|secret|rotate)/i, 'W29'],
  // --- W30 agent performance and organization design -----------------------------------
  [/(^fn_agent|_agent_|employee|org_|role_|remediat|reflect|workforce|onboarding|reviewer)/i, 'W30'],

  // --- cross-cutting engine ------------------------------------------------------------
  [/(workflow|^fn_task|_task_|execution|handoff|event_|queue|sla|exception|trace|idempot|control_mode|authority)/i, 'ALL'],
];

export function routineWorkflow(name) {
  for (const [re, wf] of ROUTINE_PATTERNS) if (re.test(name)) return wf;
  return 'ALL';
}

/** Component type -> the Phase C system actor that executes it. */
export const TYPE_TO_SYSTEM_ACTOR = {
  cron_job: 'system.scheduler',
  edge_function: 'system.webhook_receiver',      // refined per-slug below
  database_function: 'system.workflow_engine',
  database_trigger: 'system.workflow_engine',
  state_table: 'system.workflow_engine',
  frontend_route: 'system.command_router',
  runtime_workflow_definition: 'system.workflow_engine',
  event_subscription: 'system.event_dispatcher',
};

/** Refine the executing actor for an edge function from what it actually does. */
export function edgeSystemActor(e) {
  if (/(webhook|inbound|callback|oauth)/i.test(e.slug)) return 'system.webhook_receiver';
  if (/(send_|email|sms|whatsapp|wa_|notif|outbox)/i.test(e.slug)) return 'system.notification_dispatcher';
  if (/(health|uptime|ping|resilien|edge_health)/i.test(e.slug)) return 'system.health_monitor';
  if (/(ai_gateway|agent_brain|extract_text|transcribe|apify|yello|postiz|meta_|stripe|dropbox|github|vercel)/i.test(e.slug))
    return 'system.provider_adapter';
  if (/(os_api|secretary|copilot|command)/i.test(e.slug)) return 'system.command_router';
  if (/(workflow|action_worker|orchestrate|dispatch)/i.test(e.slug)) return 'system.workflow_engine';
  return 'system.task_engine';
}

/** Component type -> trace policy id. */
export const TYPE_TO_TRACE_POLICY = {
  cron_job: 'TRACE-SYSTEM-EXECUTION',
  edge_function: 'TRACE-SYSTEM-EXECUTION',
  database_function: 'TRACE-ROLE-ACTION',
  database_trigger: 'TRACE-SYSTEM-EXECUTION',
  state_table: 'TRACE-WORKFLOW',
  frontend_route: 'TRACE-ROLE-ACTION',
  runtime_workflow_definition: 'TRACE-WORKFLOW',
  event_subscription: 'TRACE-SYSTEM-EXECUTION',
};

/**
 * Workflow -> the authority action class that governs a state-changing component
 * serving it.  Taken from PHASE_C_AUTHORITY_AND_APPROVAL_MATRIX.csv; every workflow
 * not listed falls to routine_operational_decision, which the matrix defines as
 * "any ordinary department decision inside policy/authority".
 */
export const WORKFLOW_TO_ACTION_CLASS = {
  W08: 'supplier_safe_approval',
  W10: 'supplier_approval',
  W05: 'inquiry_quote_ready',
  W12: 'supplier_dispatch',
  W14: 'quotation_publish',
  W15: 'customer_identity_reveal',
  W16: 'company_payment_within_budget',
  W17: 'refund_execution',
  W19: 'supplier_suspension',
  W20: 'marketing_publish',
  W22: 'production_release',
  W23: 'model_prompt_change',
  W24: 'production_release',
  W26: 'knowledge_publish',
  W27: 'company_payment_within_budget',
  W28: 'legal_contract_within_template',
  W29: 'security_secret_rotation',
};
export const actionClassFor = wf => WORKFLOW_TO_ACTION_CLASS[wf] || 'routine_operational_decision';

/**
 * Idempotency strategy by component type.  A cron job's natural scope is its schedule
 * tick; an edge function's is its request/business key; a trigger's is the row it fires on.
 */
export const TYPE_TO_IDEMPOTENCY = {
  cron_job: 'schedule_tick:jobname:scheduled_at',
  edge_function: 'request:slug:business_key',
  database_function: 'transaction:routine:argument_hash',
  database_trigger: 'row:table:primary_key:operation',
  state_table: 'row:primary_key',
  frontend_route: 'client_request:route:idempotency_key',
  runtime_workflow_definition: 'workflow_run:workflow_key:business_object_id',
  event_subscription: 'event:event_id:consumer',
};

export const TYPE_TO_RETRY = {
  cron_job: 'next_scheduled_tick',
  edge_function: 'caller_retry_with_same_key',
  database_function: 'caller_retry_in_new_transaction',
  database_trigger: 'statement_retry_only',
  state_table: 'not_applicable',
  frontend_route: 'user_retry_with_same_key',
  runtime_workflow_definition: 'workflow_retry_preserving_first_attempt',
  event_subscription: 'outbox_retry_with_backoff',
};
