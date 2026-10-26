export const meta = {
  name: 'connectivity-audit',
  description: 'Byte-by-byte audit: every active department bidirectionally connected, every agent actionable, every loop closed',
  phases: [
    { title: 'Audit', detail: 'one agent per active department + cross-cutting dimensions, read-only' },
    { title: 'Verify', detail: 'adversarially confirm each finding is a live gap, not historical/false-positive' },
  ],
};

// Read-only DB recipe every agent uses (management token already on disk).
const RECIPE = `
You audit the QuotesDone autonomous-company database (Supabase project htdblwldjkcgjvmqkbeh). READ ONLY:
run SELECTs only; never write. Query with:

  TOKEN=$(cat C:/Users/Opera/.supabase/access-token)
  curl -s -X POST "https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/database/query" \\
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \\
    -d '{"query":"select ..."}'

CONTEXT — the company is 10 ACTIVE departments: assurance, customer_experience, data_intel, exec,
finance, growth, legal, marketplace, people_ops, product_eng. Everything else in org_departments is
INACTIVE and out of scope.

KEY TABLES/VIEWS:
- org_departments (dept_key, name, active), org_role (roles per dept), org_agents, category_agents.
- org_action_executor (action_class, department, kind edge/rpc, target, active, risk_tier, advisory_safe,
  reversible, notifies_human, required_authority) — HOW an agent ACTS. org_authority (tiers).
- workflow / workflow_step (workflow_key, step_no, action_class, actor) + workflow_run/workflow_step_run.
- phase_c_workflow_binding, phase_c_handoff_binding, phase_c_event_binding, phase_c_event_outbox
  (the runtime wiring). handoff_contract, agent_actions (kind='handoff').
- company_event / company_goals / department_objective / org_objectives (goals cascade).
- Gap views already exist: v_handoff_without_contract, v_workflow_side_effects_without_executor,
  v_handoff_stalled, v_internal_escalation_queue, v_event_backbone, v_ai_agent_health, v_workflow_matrix.

CRITICAL — distinguish a LIVE structural gap from HISTORICAL noise:
- agent_actions handoffs in status done/superseded/cancelled/rejected are TERMINAL history, NOT live gaps.
- A function/agent that "produces no effect" only because it is INFERENCE-BOUND (calls the AI gateway /
  OpenRouter, which is intentionally OFF by founder decision) is NOT a defect — flag it fix_type="inference".
- A real gap is: a LIVE one-way connection (A produces for B but nothing routes B's response back / no
  consumer), a workflow step with no executor and no reason, an active agent that cannot act, an emitted
  event type with no binding, a failure kind with no watcher, an objective that cannot cascade or retire.

Return ONLY verifiable findings, each with a SQL evidence snippet proving it is live. Prefer few high-signal
findings over many speculative ones. If a dimension is fully connected, return an empty findings array.`;

const FINDING_SCHEMA = {
  type: 'object',
  properties: {
    dimension: { type: 'string' },
    summary: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          category: { type: 'string', description: 'one-way-connection | non-actionable-agent | dead-end-step | orphan | unhandled-failure | broken-link | no-cascade | other' },
          subject: { type: 'string', description: 'the exact object: dept/role/workflow.step/event_type/action_class' },
          description: { type: 'string' },
          evidence_sql: { type: 'string', description: 'a SELECT that proves this is a live gap' },
          fix_type: { type: 'string', enum: ['deterministic', 'inference', 'founder'] },
          proposed_fix: { type: 'string' },
        },
        required: ['id', 'severity', 'category', 'subject', 'description', 'evidence_sql', 'fix_type'],
      },
    },
  },
  required: ['dimension', 'findings'],
};

const DEPTS = ['assurance', 'customer_experience', 'data_intel', 'exec', 'finance', 'growth', 'legal', 'marketplace', 'people_ops', 'product_eng'];

const CROSS = [
  { key: 'action-pipeline', q: 'The ACTION PIPELINE end to end: org_action_executor -> action_execution (queue) -> fn_action_invoke_dispatch/collect -> action_approval -> handoff back to the requester. Find any active executor whose target does not exist or errors; any action_class used in a workflow_step with no active executor and no inference reason; any queued action_execution that no dispatcher consumes; any approval that never routes back. Invoke each active rpc executor in an ABORTED transaction (do $$ begin perform ...; raise exception \'PROBE_OK\'; exception when others then ... end $$;) to confirm it runs.' },
  { key: 'event-and-workflow', q: 'The EVENT BACKBONE and WORKFLOW ENGINE: every phase_c_event_outbox event_type must have a phase_c_event_binding (a subscriber) AND every binding must have an emitter (something that writes that event) — a binding with no emitter or an emitter with no binding is a one-way connection. Every workflow_step must have an owner/actor and either an effect+executor or a next-step (no dead-ends). List workflows whose runtime binding is missing (phase_c_workflow_binding) so they can never run.' },
  { key: 'failure-and-escalation', q: 'FAILURE HANDLING loops: every failure kind (agent_runs error, os_incidents, error_events, escalations, exception_alerts, sla breaches, handoff stalls, dead_letter) must have a WATCHER that detects it AND a HANDLER/owner that acts on it AND a path that closes or escalates it. Find any failure kind with a detector but no handler, or a handler but no detector, or an escalation queue that no one drains. Confirm the re-enabled watcher crons are active and traced.' },
  { key: 'objective-and-agent', q: 'OBJECTIVE CASCADE and AGENT ACTIONABILITY: company_goals -> department_objective -> org_objectives must cascade down with an owner and retire back up (goal_retirement_replan). Find goals that cannot cascade (no measure/owner) or cannot retire. AGENT ACTIONABILITY: for every active department, list roles/agents that have NO way to act (no active org_action_executor and not inference-bound) — a knowledge-only agent that cannot DO anything is the founder\'s explicit concern ("every agent must ACT, not just notify").' },
];

phase('Audit');

const deptResults = await parallel(DEPTS.map((d) => () =>
  agent(
    `${RECIPE}\n\nYOUR DIMENSION: department "${d}". Audit whether department ${d} is a fully-connected member of the company:\n`
    + `1. BIDIRECTIONAL: does ${d} both PRODUCE work for other departments (handoffs/events/effects it emits) AND CONSUME/RESPOND to work from others? A department that only receives or only sends is a one-way connection.\n`
    + `2. ACTIONABLE: do ${d}'s roles/agents have active org_action_executor rows so they can ACT (not just hold knowledge)? List any active role in ${d} that cannot act.\n`
    + `3. LOOPS: are ${d}'s failures watched and handled? Does its work close (workflows reach a terminal state with an owner at each step)?\n`
    + `Return structured findings for department ${d}. Empty array if ${d} is fully connected and actionable.`,
    { label: `audit:${d}`, phase: 'Audit', schema: FINDING_SCHEMA, agentType: 'general-purpose' }
  )
));

const crossResults = await parallel(CROSS.map((c) => () =>
  agent(
    `${RECIPE}\n\nYOUR DIMENSION: ${c.key}. ${c.q}\n\nReturn structured findings. Empty array if this dimension is fully connected.`,
    { label: `audit:${c.key}`, phase: 'Audit', schema: FINDING_SCHEMA, agentType: 'general-purpose' }
  )
));

const all = [...deptResults, ...crossResults].filter(Boolean);
const rawFindings = all.flatMap((r) => (r.findings || []).map((f) => ({ ...f, dimension: r.dimension })));
log(`Audit surfaced ${rawFindings.length} raw findings across ${all.length} dimensions. Verifying each against live state.`);

phase('Verify');

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    is_live_gap: { type: 'boolean', description: 'true only if this is a REAL live structural gap, not historical/terminal/false-positive/inference-expected' },
    verdict_reason: { type: 'string' },
    corrected_fix_type: { type: 'string', enum: ['deterministic', 'inference', 'founder'] },
    corrected_severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
  },
  required: ['is_live_gap', 'verdict_reason'],
};

const verified = await parallel(rawFindings.map((f) => () =>
  agent(
    `${RECIPE}\n\nADVERSARIALLY VERIFY this audit finding. Run its evidence SQL and any additional query needed. Default to is_live_gap=false unless you can PROVE it is a live structural gap (not historical/terminal rows, not a false positive, not an inference-bound function that is simply waiting on the intentionally-off OpenRouter).\n\nFINDING: ${JSON.stringify(f)}`,
    { label: `verify:${f.id || f.subject}`, phase: 'Verify', schema: VERDICT_SCHEMA, agentType: 'general-purpose' }
  ).then((v) => ({ finding: f, verdict: v })).catch(() => null)
));

const confirmed = verified.filter(Boolean).filter((v) => v.verdict?.is_live_gap)
  .map((v) => ({ ...v.finding, severity: v.verdict.corrected_severity || v.finding.severity, fix_type: v.verdict.corrected_fix_type || v.finding.fix_type, verdict_reason: v.verdict.verdict_reason }));

log(`Verified: ${confirmed.length} confirmed live gaps of ${rawFindings.length} raw.`);
return {
  confirmed_count: confirmed.length,
  by_fix_type: {
    deterministic: confirmed.filter((f) => f.fix_type === 'deterministic').length,
    inference: confirmed.filter((f) => f.fix_type === 'inference').length,
    founder: confirmed.filter((f) => f.fix_type === 'founder').length,
  },
  confirmed,
};
