// Phase B deterministic validation of the committed package against the live,
// founder-approved Phase A organization.  Zero inference: no model, no provider.
//
//   node scripts/phase_b/validate_package.mjs            # human summary
//   node scripts/phase_b/validate_package.mjs --json     # machine result
//
// Exit code 0 only when every mandatory invariant in PHASE_B_INVARIANTS.md holds.
import { loadPackage, verifyChecksums, splitList, DECLARED_COUNTS } from './lib/package.mjs';
import {
  makeResolver, NON_ACCOUNTABLE_ACTORS, PACKAGE_ERRATA, isClosureStep,
  OVERLAY_ELIGIBLE_WORKFLOWS, OVERLAY_ELIGIBLE_STEP_TYPES,
} from './lib/identity.mjs';
import { sql } from './lib/db.mjs';

const JSON_OUT = process.argv.includes('--json');
const results = [];
const check = (name, actual, expected, detail) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  results.push({ name, ok, actual, expected, detail: ok ? undefined : detail });
  return ok;
};

// ---------------------------------------------------------------- package bytes
const sums = verifyChecksums();
check('package.checksums', sums.bad.length, 0, sums.bad);
check('package.files_checked', sums.checked, 60);

const pkg = loadPackage();
for (const [k, want] of Object.entries(DECLARED_COUNTS)) check(`count.${k}`, pkg[k].length, want);

// ---------------------------------------------------------------- errata applied
// The package is checksummed and must not be edited in place, so the three defects
// found in it are corrected here on the in-memory copy the deliverables are derived from.
for (const e of PACKAGE_ERRATA) {
  const row = e.file === 'PHASE_B_EXCEPTION_ESCALATION_MATRIX.csv'
      ? pkg.exceptions.find(x => x.exception_id === e.id)
    : e.file === 'PHASE_B_WORKFLOW_REGISTRY.csv'
      ? pkg.workflows.find(x => x.workflow_id === e.id)
    : e.file === 'PHASE_B_WORKFLOW_STEP_REGISTRY.csv'
      ? pkg.steps.find(x => x.step_id === e.id)
    : null;
  if (!row) { results.push({ name: `errata.${e.id}`, ok: false, actual: 'target row not found' }); continue; }
  Object.assign(row, e.correction);
}
check('errata.applied', PACKAGE_ERRATA.length, 3);

// ------------------------------------------------------------------- live org
const liveRoles = await sql(`select role_id, display_name, status, runtime_mode, primary_department_id
                             from public.org_role`);
const liveAliases = await sql(`select alias, role_id from public.org_role_alias`);
const liveDepts = await sql(`select dept_key, name, active, lead_agent from public.org_departments where active`);
const liveOwnership = await sql(`select workflow_id, workflow_name, accountable_role_id,
                                        independent_reviewer, array_to_string(contributors,';') contributors
                                 from public.org_workflow_ownership order by workflow_id`);
const resolve = makeResolver({ liveRoles, liveAliases });

const canonical = liveRoles.filter(r => r.status === 'active' && r.runtime_mode !== 'knowledge_overlay');
const overlays = liveRoles.filter(r => r.status === 'active' && r.runtime_mode === 'knowledge_overlay');
check('phase_a.canonical_roles', canonical.length, 90);
check('phase_a.category_overlays', overlays.length, 86);
check('phase_a.active_departments', liveDepts.length, 10);

const drift = await sql('select * from public.fn_phase_a_baseline_drift()');
check('phase_a.baseline_drift_rows', drift.length, 0, drift);
const viol = await sql('select count(*)::int c from public.fn_phase_a_organization_violations()');
check('phase_a.organization_violations', viol[0].c, 0);

// ------------------------------------------------------- workflow registry <-> Phase A
// org_workflow_ownership is INSIDE the frozen Phase A digest, so the package must agree
// with it rather than the other way round.  A disagreement here is a Phase A change
// request, not something Phase B may edit.
const ownById = new Map(liveOwnership.map(o => [o.workflow_id, o]));
const ownershipConflicts = [];
for (const w of pkg.workflows) {
  const live = ownById.get(w.workflow_id);
  if (!live) { ownershipConflicts.push({ workflow_id: w.workflow_id, why: 'absent from org_workflow_ownership' }); continue; }
  const pa = resolve(w.accountable_role_id);
  const pr = resolve(w.independent_reviewer_or_challenge_role);
  const la = resolve(live.accountable_role_id);
  const lr = resolve(live.independent_reviewer);
  if (pa.role_id !== la.role_id) ownershipConflicts.push({
    workflow_id: w.workflow_id, field: 'accountable',
    package: `${w.accountable_role_id} -> ${pa.role_id ?? pa.kind}`,
    phase_a: `${live.accountable_role_id} -> ${la.role_id ?? la.kind}`,
  });
  const prKey = pr.role_id ?? pr.token;
  const lrKey = lr.role_id ?? lr.token;
  if (prKey !== lrKey) ownershipConflicts.push({
    workflow_id: w.workflow_id, field: 'reviewer',
    package: `${w.independent_reviewer_or_challenge_role} -> ${prKey}`,
    phase_a: `${live.independent_reviewer} -> ${lrKey}`,
  });
}
check('phase_a.workflow_ownership_agreement', ownershipConflicts.length, 0, ownershipConflicts);

// ------------------------------------------------------------------ identity/ownership
const unresolved = [], inactive = [], overlayAccountable = [], nonAccountable = [];
const covered = new Set();
const touch = res => { if (res.kind === 'canonical') covered.add(res.role_id); };

const classify = (token, where, opts = {}) => {
  const { accountable = false } = opts;
  const r = resolve(token);
  if (r.kind === 'empty') return r;
  if (r.kind === 'unresolved') unresolved.push({ token, where });
  else if (r.kind === 'inactive') inactive.push({ token, where, status: r.status });
  else if (accountable && r.kind === 'overlay') overlayAccountable.push({ token, where });
  else if (accountable && r.kind === 'dynamic' && NON_ACCOUNTABLE_ACTORS.has(token)
           && !(opts.overlayEligible && token === 'relevant_category_overlay')) {
    nonAccountable.push({ token, where });
  }
  touch(r);
  return r;
};

for (const w of pkg.workflows) {
  classify(w.accountable_role_id, `workflow ${w.workflow_id}.accountable`, { accountable: true });
  classify(w.independent_reviewer_or_challenge_role, `workflow ${w.workflow_id}.reviewer`);
  splitList(w.contributors).forEach(c => classify(c, `workflow ${w.workflow_id}.contributor`));
}
const overlayEligibleSteps = [];
for (const s of pkg.steps) {
  const eligible = OVERLAY_ELIGIBLE_WORKFLOWS.has(s.workflow_id)
    && OVERLAY_ELIGIBLE_STEP_TYPES.has(s.step_type);
  if (s.accountable_role_id === 'relevant_category_overlay') overlayEligibleSteps.push(s.step_id);
  classify(s.accountable_role_id, `step ${s.step_id}.accountable`, { accountable: true, overlayEligible: eligible });
  classify(s.independent_reviewer_role_id, `step ${s.step_id}.reviewer`);
  splitList(s.contributors).forEach(c => classify(c, `step ${s.step_id}.contributor`));
}
// the master spec declares exactly one overlay-accountable step: the technical evaluation
check('identity.overlay_accountable_steps_declared', overlayEligibleSteps, ['W14-S05']);
for (const h of pkg.handoffs) {
  classify(h.sending_role_id, `handoff ${h.handoff_id}.sender`);
  classify(h.receiving_role_id, `handoff ${h.handoff_id}.receiver`);
  classify(h.return_owner_role_id, `handoff ${h.handoff_id}.return_owner`);
}
for (const e of pkg.exceptions) {
  classify(e.detection_owner_role_id, `exception ${e.exception_id}.detection`);
  classify(e.escalation_owner_role_id, `exception ${e.exception_id}.escalation`);
}
for (const o of pkg.objects) classify(o.accountable_role_id, `object ${o.object_id}.accountable`);
for (const e of pkg.events) classify(e.primary_consumer_role_id, `event ${e.event_id}.consumer`);

check('identity.unresolved_tokens', unresolved.length, 0, unresolved.slice(0, 40));
check('identity.inactive_owners', inactive.length, 0, inactive);
check('identity.overlay_accountable_steps', overlayAccountable.length, 0, overlayAccountable);
check('identity.placeholder_accountable_steps', nonAccountable.length, 0, nonAccountable);

const uncovered = canonical.map(r => r.role_id).filter(id => !covered.has(id));
check('coverage.roles_unrepresented', uncovered.length, 0, uncovered);
const coveredDepts = new Set(canonical.filter(r => covered.has(r.role_id)).map(r => r.primary_department_id));
const uncoveredDepts = liveDepts.map(d => d.dept_key).filter(k => !coveredDepts.has(k));
check('coverage.departments_unrepresented', uncoveredDepts.length, 0, uncoveredDepts);

// --------------------------------------------------------------- graph and sequence
const dup = (arr, key) => {
  const seen = new Map();
  for (const r of arr) seen.set(r[key], (seen.get(r[key]) ?? 0) + 1);
  return [...seen].filter(([, n]) => n > 1).map(([k]) => k);
};
check('graph.duplicate_workflow_ids', dup(pkg.workflows, 'workflow_id'), []);
check('graph.duplicate_step_ids', dup(pkg.steps, 'step_id'), []);
check('graph.duplicate_event_ids', dup(pkg.events, 'event_id'), []);
check('graph.duplicate_rule_ids', dup(pkg.rules, 'rule_id'), []);
check('graph.duplicate_exception_ids', dup(pkg.exceptions, 'exception_id'), []);
check('graph.duplicate_handoff_ids', dup(pkg.handoffs, 'handoff_id'), []);
check('graph.duplicate_gate_ids', dup(pkg.gates, 'gate_id'), []);
check('graph.duplicate_object_ids', dup(pkg.objects, 'object_id'), []);
check('graph.duplicate_sla_ids', dup(pkg.slas, 'sla_policy_id'), []);

const stepIds = new Set(pkg.steps.map(s => s.step_id));
const wfIds = new Set(pkg.workflows.map(w => w.workflow_id));
// The four terminal targets the package actually uses, enumerated from the committed bytes
// rather than assumed: an unlisted target would be an unreachable step, not a terminal.
const TERMINAL_TARGETS = new Set(['', 'WORKFLOW_COMPLETE', 'WORKFLOW_BLOCKED',
  'WORKFLOW_BLOCKED_OR_ESCALATED', 'CORRECTION_OR_REJECTION_PATH']);
const badTargets = [];
for (const s of pkg.steps) {
  for (const f of ['next_step_if_pass', 'next_step_if_fail']) {
    const v = s[f];
    if (TERMINAL_TARGETS.has(v)) continue;
    if (!stepIds.has(v)) badTargets.push({ step_id: s.step_id, field: f, value: v });
  }
  if (!wfIds.has(s.workflow_id)) badTargets.push({ step_id: s.step_id, field: 'workflow_id', value: s.workflow_id });
}
check('graph.impossible_next_step_references', badTargets.length, 0, badTargets);

// inbound reachability, per workflow, from step_no 1
const orphanSteps = [], deadEnds = [];
for (const w of pkg.workflows) {
  const steps = pkg.steps.filter(s => s.workflow_id === w.workflow_id)
    .sort((a, b) => Number(a.step_no) - Number(b.step_no));
  const inbound = new Set();
  for (const s of steps) for (const f of ['next_step_if_pass', 'next_step_if_fail']) {
    if (stepIds.has(s[f])) inbound.add(s[f]);
  }
  steps.forEach((s, i) => {
    if (i > 0 && !inbound.has(s.step_id)) orphanSteps.push(s.step_id);
    const last = i === steps.length - 1;
    if (!last && !s.next_step_if_pass) deadEnds.push(s.step_id);
  });
  // step numbering is dense and 1-based
  const nos = steps.map(s => Number(s.step_no));
  if (nos.join(',') !== nos.map((_, i) => i + 1).join(',')) {
    results.push({ name: `graph.step_numbering.${w.workflow_id}`, ok: false, actual: nos });
  }
}
check('graph.steps_without_inbound_path', orphanSteps.length, 0, orphanSteps);
check('graph.non_final_steps_without_success_path', deadEnds.length, 0, deadEnds);

// prerequisite cycles: a forward pass edge that returns to an earlier step and never
// makes progress would be a cycle.  Detect with DFS over pass edges only.
const cycles = [];
for (const w of pkg.workflows) {
  const steps = pkg.steps.filter(s => s.workflow_id === w.workflow_id);
  const nextOf = new Map(steps.map(s => [s.step_id, s.next_step_if_pass]));
  for (const s of steps) {
    const seen = new Set([s.step_id]);
    let cur = nextOf.get(s.step_id);
    while (cur && stepIds.has(cur)) {
      if (seen.has(cur)) { cycles.push({ workflow_id: w.workflow_id, at: cur }); break; }
      seen.add(cur); cur = nextOf.get(cur);
    }
  }
}
check('graph.prerequisite_cycles', cycles.length, 0, cycles);

// ------------------------------------------------------------------ state machines
const wfStates = new Set(pkg.workflowStates.map(s => s.state));
const stStates = new Set(pkg.stepStates.map(s => s.state));
const badWfTrans = pkg.workflowTransitions.filter(t => !wfStates.has(t.from_state) || !wfStates.has(t.to_state));
const badStTrans = pkg.stepTransitions.filter(t => !stStates.has(t.from_state) || !stStates.has(t.to_state));
check('state.workflow_transitions_to_unknown_state', badWfTrans.length, 0, badWfTrans);
check('state.step_transitions_to_unknown_state', badStTrans.length, 0, badStTrans);
check('state.workflow_terminal_states',
  pkg.workflowStates.filter(s => s.terminal.toLowerCase() === 'true').map(s => s.state).sort(),
  ['cancelled', 'completed', 'superseded']);
const badStepStateRefs = pkg.steps.filter(s =>
  (s.success_workflow_state && !wfStates.has(s.success_workflow_state)) ||
  (s.failure_workflow_state && !wfStates.has(s.failure_workflow_state)));
check('state.step_workflow_state_refs', badStepStateRefs.length, 0,
  badStepStateRefs.map(s => ({ step_id: s.step_id, pass: s.success_workflow_state, fail: s.failure_workflow_state })));
// A terminal state may not reopen into live work.  `completed -> superseded` is the one
// declared exception (master spec §10: a completed version may be superseded, never rewritten),
// so the check is that nothing terminal returns to a NON-terminal state.
const terminalWf = new Set(pkg.workflowStates.filter(s => s.terminal.toLowerCase() === 'true').map(s => s.state));
check('state.terminal_state_reopened',
  pkg.workflowTransitions.filter(t => terminalWf.has(t.from_state) && !terminalWf.has(t.to_state))
    .map(t => `${t.from_state}->${t.to_state}`), []);
check('state.terminal_to_terminal_transitions',
  pkg.workflowTransitions.filter(t => terminalWf.has(t.from_state)).map(t => `${t.from_state}->${t.to_state}`),
  ['completed->superseded']);
check('state.profile_assignments', pkg.stateProfiles.length, 30);
check('state.profile_workflow_coverage',
  pkg.stateProfiles.filter(p => !wfIds.has(p.workflow_id)).length, 0);

// ------------------------------------------------------------------------ handoffs
const REQUIRED_HANDOFF_FIELDS = ['sending_role_id', 'receiving_role_id', 'required_packet',
  'receiving_acceptance_criteria', 'rejection_condition', 'return_owner_role_id',
  'closure_condition', 'sla_policy_id'];
const incompleteHandoffs = [];
for (const h of pkg.handoffs) {
  const missing = REQUIRED_HANDOFF_FIELDS.filter(f => !h[f]);
  if (missing.length) incompleteHandoffs.push({ handoff_id: h.handoff_id, missing });
}
check('handoff.incomplete', incompleteHandoffs.length, 0, incompleteHandoffs);

const slaIds = new Set(pkg.slas.map(s => s.sla_policy_id));
check('handoff.unknown_sla_reference',
  pkg.handoffs.filter(h => !slaIds.has(h.sla_policy_id)).map(h => h.handoff_id), []);
const crossDept = pkg.handoffs.filter(h => h.handoff_type === 'cross_department');
check('handoff.cross_department_count', crossDept.length, 47);
check('handoff.cross_department_without_sla', crossDept.filter(h => !h.sla_policy_id).length, 0);
check('handoff.bad_step_reference',
  pkg.handoffs.filter(h => !stepIds.has(h.from_step_id) || !stepIds.has(h.to_step_id))
    .map(h => h.handoff_id), []);

// every owner change between consecutive steps must have a handoff contract
const handoffByEdge = new Set(pkg.handoffs.map(h => `${h.from_step_id}>${h.to_step_id}`));
const missingHandoffs = [];
for (const w of pkg.workflows) {
  const steps = pkg.steps.filter(s => s.workflow_id === w.workflow_id)
    .sort((a, b) => Number(a.step_no) - Number(b.step_no));
  for (const s of steps) {
    const nxt = steps.find(x => x.step_id === s.next_step_if_pass);
    if (!nxt) continue;
    const a = resolve(s.accountable_role_id), b = resolve(nxt.accountable_role_id);
    const aKey = a.role_id ?? a.token, bKey = b.role_id ?? b.token;
    if (aKey !== bKey && !handoffByEdge.has(`${s.step_id}>${nxt.step_id}`)) {
      missingHandoffs.push({ from: s.step_id, to: nxt.step_id, from_owner: aKey, to_owner: bKey });
    }
  }
}
check('handoff.owner_change_without_contract', missingHandoffs.length, 0, missingHandoffs);

// handoff sender/receiver must match the steps they join
const handoffRoleMismatch = [];
const stepById = new Map(pkg.steps.map(s => [s.step_id, s]));
for (const h of pkg.handoffs) {
  const from = stepById.get(h.from_step_id), to = stepById.get(h.to_step_id);
  if (!from || !to) continue;
  if (resolve(from.accountable_role_id).role_id !== resolve(h.sending_role_id).role_id
      && resolve(from.accountable_role_id).token !== resolve(h.sending_role_id).token) {
    handoffRoleMismatch.push({ handoff_id: h.handoff_id, field: 'sender' });
  }
  if (resolve(to.accountable_role_id).role_id !== resolve(h.receiving_role_id).role_id
      && resolve(to.accountable_role_id).token !== resolve(h.receiving_role_id).token) {
    handoffRoleMismatch.push({ handoff_id: h.handoff_id, field: 'receiver' });
  }
}
check('handoff.role_mismatch_with_steps', handoffRoleMismatch.length, 0, handoffRoleMismatch.slice(0, 20));

// --------------------------------------------------------------- review and authority
const collisions = [];
for (const s of pkg.steps) {
  if (!s.independent_reviewer_role_id) continue;
  const c = resolve(s.accountable_role_id), r = resolve(s.independent_reviewer_role_id);
  const ck = c.role_id ?? c.token, rk = r.role_id ?? r.token;
  if (ck === rk) collisions.push({ step_id: s.step_id, identity: ck });
}
check('review.creator_reviewer_collisions', collisions.length, 0, collisions);

const wfCollisions = pkg.workflows.filter(w => {
  const a = resolve(w.accountable_role_id), r = resolve(w.independent_reviewer_or_challenge_role);
  return (a.role_id ?? a.token) === (r.role_id ?? r.token);
}).map(w => w.workflow_id);
check('review.workflow_owner_reviewer_collisions', wfCollisions, []);

// overlays may never hold dispatch / payment / reveal / release authority
const FORBIDDEN_OVERLAY_WORKFLOWS = new Set(['W12', 'W15', 'W16', 'W17', 'W24']);
const overlayAuthority = [];
for (const s of pkg.steps) {
  const r = resolve(s.accountable_role_id);
  const isOverlay = r.kind === 'overlay' || s.accountable_role_id === 'relevant_category_overlay';
  if (isOverlay && FORBIDDEN_OVERLAY_WORKFLOWS.has(s.workflow_id)) {
    overlayAuthority.push({ step_id: s.step_id, workflow_id: s.workflow_id });
  }
  if (isOverlay && s.independent_reviewer_role_id) {
    overlayAuthority.push({ step_id: s.step_id, why: 'overlay as final reviewer' });
  }
}
check('authority.overlay_dispatch_payment_reveal_release', overlayAuthority.length, 0, overlayAuthority);

// Every founder-reserved decision must be reachable only through a founder gate.  A boundary
// is satisfied when at least one workflow in its scope carries a founder-gated step — not when
// every scoped workflow does: several boundaries are constraints ("departments operate within
// approved policy"), not approval events, and demanding a gate step for those would be a check
// that measures something other than what it names.
const founderGateSteps = pkg.steps.filter(s => s.founder_gate && s.founder_gate.toLowerCase() !== 'none');
const wfWithFounderGate = new Set(founderGateSteps.map(s => s.workflow_id));
const uncoveredBoundaries = pkg.founderBoundaries
  .filter(b => !splitList(b.workflow_scope).some(w => wfWithFounderGate.has(w)))
  .map(b => `${b.boundary_id}:${b.workflow_scope}`);
check('authority.founder_boundaries_without_any_gate', uncoveredBoundaries, []);
check('authority.founder_boundaries', pkg.founderBoundaries.length, 10);
check('authority.founder_gated_steps', founderGateSteps.length > 0, true);
// A founder gate may only be discharged by the founder, never by an operational role.
check('authority.founder_gate_owned_by_operational_role',
  founderGateSteps.filter(s => /founder (approv|decid|sign)/i.test(s.required_action)
    && resolve(s.accountable_role_id).kind === 'canonical'
    && !/escalat|prepar|submit|packag|recommend|propos|request/i.test(s.required_action))
    .map(s => s.step_id), []);

// onboarding cannot approve its own supplier; payment executor cannot reconcile itself
const w09Owner = resolve(pkg.workflows.find(w => w.workflow_id === 'W09').accountable_role_id).role_id;
const w10Steps = pkg.steps.filter(s => s.workflow_id === 'W10');
check('authority.onboarding_approving_own_supplier',
  w10Steps.filter(s => s.step_type === 'decision' || s.step_type === 'review')
    .filter(s => resolve(s.accountable_role_id).role_id === w09Owner).map(s => s.step_id), []);

// Payment executor / reconciler separation.
//
// Classify by what a step PRODUCES, not by whether its prose mentions "executor": the reconcile
// step's own action reads "…independently of the payment executor", and a keyword match on that
// sentence classified the reconciler AS the executor. Absence of a word is not its presence.
const w16 = pkg.steps.filter(s => s.workflow_id === 'W16');
const MONEY_OUTPUT = /payment request|provider event|transaction state|charge|payout|refund record/i;
const executors = new Set(w16
  .filter(s => ['intake', 'execution', 'decision'].includes(s.step_type) && MONEY_OUTPUT.test(s.required_output))
  .map(s => resolve(s.accountable_role_id).role_id));
const reconcilers = w16.filter(s => s.step_type === 'review');
check('authority.payment_executors_identified', executors.size > 0, true);
check('authority.payment_reconcilers_identified', reconcilers.length > 0, true);
check('authority.payment_executor_reconciles_own_action',
  reconcilers.filter(s => executors.has(resolve(s.accountable_role_id).role_id)).map(s => s.step_id), []);

// ------------------------------------------------------------- workflow completeness
const REQUIRED_WF_FIELDS = ['workflow_name', 'purpose', 'primary_object', 'accountable_role_id',
  'start_event', 'required_end_state', 'founder_boundary', 'criticality', 'profile'];
const incompleteWf = pkg.workflows.map(w => ({ id: w.workflow_id, missing: REQUIRED_WF_FIELDS.filter(f => !w[f]) }))
  .filter(x => x.missing.length);
check('completeness.workflows', incompleteWf.length, 0, incompleteWf);

const REQUIRED_STEP_FIELDS = ['step_name', 'step_type', 'accountable_role_id', 'entry_condition',
  'required_inputs', 'required_action', 'required_output', 'acceptance_criteria',
  'closure_criteria', 'failure_or_block_state', 'idempotency_scope'];
const incompleteSteps = pkg.steps.map(s => ({ id: s.step_id, missing: REQUIRED_STEP_FIELDS.filter(f => !s[f]) }))
  .filter(x => x.missing.length);
check('completeness.steps', incompleteSteps.length, 0, incompleteSteps);

const objIds = new Set(pkg.objects.map(o => o.object_id));
check('completeness.workflow_primary_object_known',
  pkg.workflows.filter(w => !objIds.has(w.primary_object)).map(w => `${w.workflow_id}:${w.primary_object}`), []);

const wfWithException = new Set(pkg.exceptions.flatMap(e => e.workflow_scope.split(/[;\/]/).map(s => s.trim())));
check('completeness.workflows_without_exception_path',
  pkg.workflows.filter(w => !wfWithException.has(w.workflow_id) && !wfWithException.has('ALL')).map(w => w.workflow_id), []);

const wfWithSteps = new Set(pkg.steps.map(s => s.workflow_id));
check('completeness.workflows_without_steps', pkg.workflows.filter(w => !wfWithSteps.has(w.workflow_id)).map(w => w.workflow_id), []);

const wfWithClosure = new Set(pkg.steps.filter(isClosureStep).map(s => s.workflow_id));
check('completeness.workflows_without_closure_step',
  pkg.workflows.filter(w => !wfWithClosure.has(w.workflow_id)).map(w => w.workflow_id), []);
// the derived closure anchor must select exactly one step per workflow, and it must be the last
const closureAnomalies = [];
for (const w of pkg.workflows) {
  const steps = pkg.steps.filter(s => s.workflow_id === w.workflow_id)
    .sort((a, b) => Number(a.step_no) - Number(b.step_no));
  const anchors = steps.filter(isClosureStep);
  if (anchors.length !== 1) closureAnomalies.push({ workflow_id: w.workflow_id, anchors: anchors.map(a => a.step_id) });
  else if (anchors[0].step_id !== steps[steps.length - 1].step_id) {
    closureAnomalies.push({ workflow_id: w.workflow_id, why: 'closure anchor is not the final step' });
  }
}
check('completeness.closure_anchor_unique_and_final', closureAnomalies.length, 0, closureAnomalies);

// ------------------------------------------------------------------------ events
check('events.unknown_workflow',
  pkg.events.filter(e => e.workflow_id !== 'ALL' && !wfIds.has(e.workflow_id)).map(e => e.event_id).slice(0, 20), []);
check('events.without_dedupe_key', pkg.events.filter(e => !e.dedupe_key).length, 0);
check('events.without_payload_contract', pkg.events.filter(e => !e.payload_contract).length, 0);

// -------------------------------------------------------------------- rules/gates
check('rules.without_scope', pkg.rules.filter(r => !r.workflow_scope).length, 0);
check('gates.without_evidence', pkg.gates.filter(g => !g.required_evidence).length, 0);
check('gates.without_fail_result', pkg.gates.filter(g => !g.fail_result).length, 0);
check('sla.without_breach_action', pkg.slas.filter(s => !s.breach_action).length, 0);
check('exceptions.without_closure', pkg.exceptions.filter(e => !e.closure_condition).length, 0);
check('exceptions.without_escalation_owner', pkg.exceptions.filter(e => !e.escalation_owner_role_id).length, 0);

// ------------------------------------------------------------------------- report
const failed = results.filter(r => !r.ok);
if (JSON_OUT) {
  console.log(JSON.stringify({ ok: failed.length === 0, total: results.length, failed: failed.length, results }, null, 2));
} else {
  for (const r of results) {
    console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name.padEnd(52)} ${JSON.stringify(r.actual)}`);
    if (!r.ok && r.detail !== undefined) console.log(`      detail: ${JSON.stringify(r.detail).slice(0, 1400)}`);
  }
  console.log(`\n${results.length - failed.length}/${results.length} invariants passed`);
}
process.exit(failed.length === 0 ? 0 : 1);
