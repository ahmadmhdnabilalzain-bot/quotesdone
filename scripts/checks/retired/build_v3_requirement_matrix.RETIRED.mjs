// RETIRED 16 Nov 2026 (it_engineer) WITH ITS SUBJECT: the V3 certification remediation matrix. 4 of the 9 components it maps are gone from production (SELECT pg_proc, 16 Nov 2026: fn_context_slice, fn_knowledge_gap, fn_retrieval_leak_check, fn_task_tsquery); nothing calls it.
// V3 REMEDIATION — STAGE 1: build the requirement matrix.
//
// Sources, deliberately limited to the SANITIZED set the builder is allowed to hold:
//   docs/archive/knowledge/certification/V3_CERTIFICATION_REMEDIATION_HANDOFF.md    (competency codes)
//   docs/archive/knowledge/certification/V3_CERTIFICATION_RESULTS_BY_ROLE.csv       (aggregate)
//   docs/archive/knowledge/certification/V3_CERTIFICATION_RESULTS_BY_DEPARTMENT.csv (aggregate)
//   docs/archive/knowledge/certification/V3_CERTIFICATION_RESULTS_BY_CATEGORY.csv   (aggregate)
// No answer key, no gold answers, no certification question text is read or emitted.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const REPO = fileURLToPath(new URL('../../../', import.meta.url));

const C = REPO + 'docs/archive/knowledge/certification/';
const OUT = REPO + 'docs/archive/knowledge/remediation/V3_REMEDIATION_REQUIREMENT_MATRIX.csv';

const csv = (p) => {
  const lines = readFileSync(C + p, 'utf8').trim().split('\n');
  const head = split(lines[0]);
  return lines.slice(1).map(l => Object.fromEntries(split(l).map((v, i) => [head[i], v])));
};
function split(line) {
  const out = []; let cur = '', q = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (q) { if (c === '"' && line[i + 1] === '"') { cur += '"'; i++; } else if (c === '"') q = false; else cur += c; }
    else if (c === '"') q = true; else if (c === ',') { out.push(cur); cur = ''; } else cur += c;
  }
  out.push(cur); return out;
}
const enc = (a) => a.map(v => { const s = v == null ? '' : String(v); return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; }).join(',');

const roles = csv('V3_CERTIFICATION_RESULTS_BY_ROLE.csv');
const depts = csv('V3_CERTIFICATION_RESULTS_BY_DEPARTMENT.csv');
const cats = csv('V3_CERTIFICATION_RESULTS_BY_CATEGORY.csv');

// ── the failure classes, from the sanitized handoff ────────────────────────────────────────────
// Each row is one remediable requirement. affected_* are computed from the aggregates, never guessed.
const sharedAgents = new Set(roles.filter(r => r.agent_shared_across_roles === 'true').map(r => r.mapped_runtime_agent));
const sharedRoles = roles.filter(r => r.agent_shared_across_roles === 'true').map(r => r.role_id);
const notConnected = roles.filter(r => r.certification_status === 'NOT_CONNECTED');
const blocked = roles.filter(r => r.certification_status === 'BLOCKED_CRITICAL_FAILURE');
const deptsWithInfra = depts.filter(d => Number(d.infrastructure_failures) > 0);
const worstCats = [...cats].sort((a, b) => Number(a.overall_score_pct) - Number(b.overall_score_pct)).slice(0, 10);

const ALL_ROLES = 'all 96 roles';
const ALL_DEPTS = 'all 24 departments';
const ALL_CATS = 'all 86 categories';

const R = [];
const add = (o) => R.push({
  failure_class: o.fc, competency_id: o.cmp ?? '', affected_department: o.dept ?? '',
  affected_role: o.role ?? '', affected_category: o.cat ?? '',
  affected_runtime_component: o.comp, root_cause: o.rc, required_repair: o.rep,
  expected_behavioral_evidence: o.ev, regression_test_id: o.test, status: o.st,
});

// ── STAGE 2: tools ────────────────────────────────────────────────────────────────────────────
add({ fc: 'TOOL_NOT_CONNECTED', cmp: 'CMP-EV-02', dept: ALL_DEPTS, role: ALL_ROLES, cat: ALL_CATS,
  comp: 'supabase/functions/_shared/llm.ts',
  rc: 'The shared gateway client returned only j.content and discarded tool_calls, so every caller except secretary_act was structurally unable to hold a tool. ai_gateway had supported tools all along.',
  rep: 'makeLlmRich exposes tools, tool_choice, messages replay, tool_calls, finish_reason and truncated. makeLlm kept byte-compatible for the 31 existing call sites.',
  ev: 'An agent turn requests a tool and a real result is returned and recorded in agent_tool_call with status ok and a result hash.',
  test: 'STR-TOOL-001..006, REG-TOOLS-*', st: 'DONE_STAGING' });
add({ fc: 'TOOL_NOT_CONNECTED', cmp: 'CMP-EV-03', dept: ALL_DEPTS, role: ALL_ROLES, cat: ALL_CATS,
  comp: 'agent_tool / fn_agent_tools / _shared/tools.ts',
  rc: 'No registry said which role may hold which tool, so there was nothing to offer a model even if the client had supported it.',
  rep: 'agent_tool registry with authorised roles/departments, input schema, timeout, retry, failure behaviour, requires_current_data and stub_permitted; eligibility resolved server-side from the roster.',
  ev: 'fn_agent_tools returns a different tool set per department; an unknown agent gets zero; an ungranted tool is refused with status unauthorised.',
  test: 'STR-TOOL-002, STR-TOOL-003, STR-TOOL-004', st: 'DONE_STAGING' });
add({ fc: 'TOOL_RESULT_UNVERIFIABLE', cmp: 'CMP-EV-02', dept: ALL_DEPTS, role: ALL_ROLES, cat: ALL_CATS,
  comp: 'agent_tool_call ledger',
  rc: 'Nothing recorded what a tool returned, so a model claiming a tool result could not be contradicted.',
  rep: 'Every invocation writes a ledger row including refusals; the exact bytes shown to the model are sha256-hashed first; verifyNoFabricatedResults compares injected hashes against the ledger.',
  ev: 'Zero ok rows without a result_hash; a hash not present in the ledger is reportable as fabricated.',
  test: 'STR-TOOL-006', st: 'DONE_STAGING' });
add({ fc: 'TOOL_EMPTY_VS_FAILURE_CONFLATED', cmp: 'CMP-EV-02', dept: ALL_DEPTS, role: ALL_ROLES, cat: ALL_CATS,
  comp: 'agent_tool_call.status',
  rc: 'An empty result and an unreachable tool were indistinguishable, so "no data" and "no answer" were the same event.',
  rep: 'Distinct statuses ok / ok_empty / error / timeout / unavailable / unauthorised, and an ok_empty result is rendered to the model with an explicit note that it is a real answer meaning none found.',
  ev: 'The status check constraint carries ok_empty; a fail_closed tool that errors stops the task instead of being answered around.',
  test: 'STR-TOOL-005', st: 'DONE_STAGING' });

// ── STAGE 3: traces ───────────────────────────────────────────────────────────────────────────
add({ fc: 'TRACE_OR_OBSERVABILITY_FAILURE', cmp: 'CMP-TRACE-01', dept: ALL_DEPTS, role: ALL_ROLES, cat: ALL_CATS,
  comp: 'decision_trace / agent_brain',
  rc: 'No edge function could write a trace - there was no callable writer - and decision_trace held 1 row against 204 agent_actions.',
  rep: 'fn_write_decision_trace resolves role, department and manager server-side; agent_brain writes and seals one trace per turn carrying tools, knowledge ids, evidence hashes, confidence and authority.',
  ev: 'Every agent_brain turn produces a sealed trace with a non-null role_id, escalation_decision and final_status.',
  test: 'STR-TRACE-001, STR-TRACE-003, REG-TRACES-*', st: 'DONE_STAGING' });
add({ fc: 'TRACE_TRIGGER_CANNOT_FIRE', cmp: 'CMP-TRACE-01', dept: ALL_DEPTS, role: ALL_ROLES,
  comp: 'trigger z90_agent_action_decision_trace',
  rc: 'The only writer was AFTER UPDATE OF decided_at, and os_api INSERTs agent_actions with decided_at already set - so on that path the trigger could not fire at all.',
  rep: 'Added the AFTER INSERT path and repointed the UPDATE body at one shared row builder so the two cannot drift.',
  ev: 'An INSERT carrying decided_at produces a trace; an UPDATE to decided_at produces an identically shaped trace.',
  test: 'STR-TRACE-001', st: 'DONE_STAGING' });
add({ fc: 'TRACE_EVIDENCE_MUTABLE', cmp: 'CMP-TRACE-02', dept: ALL_DEPTS, role: ALL_ROLES,
  comp: 'a00_decision_trace_immutable',
  rc: 'A runtime agent could silently rewrite the evidence a completed decision rested on.',
  rep: 'Sealing freezes decision, evidence, knowledge, tool results, confidence, authority and identity; grading the outcome afterwards is still allowed.',
  ev: 'An edit to a sealed trace is refused; an outcome_status update on the same row succeeds.',
  test: 'STR-TRACE-004', st: 'DONE_STAGING' });
add({ fc: 'TRACE_MONITOR_ERRORS', cmp: 'CMP-TRACE-02', dept: ALL_DEPTS,
  comp: 'v_decision_trace_incomplete',
  rc: 'jsonb_array_length(evidence_refs) was unguarded and raised 22023 on legacy rows storing an object - the completeness gate errored instead of reporting, and an erroring check reads like a passing one.',
  rep: 'jsonb_typeof guard; a non-array evidence_refs counts honestly as no evidence.',
  ev: 'The view executes and returns a row count rather than raising.',
  test: 'STR-TRACE-002', st: 'DONE_STAGING' });

// ── STAGE 4: retrieval ────────────────────────────────────────────────────────────────────────
add({ fc: 'KNOWLEDGE_NOT_RETRIEVED', cmp: 'CMP-KB-01', dept: ALL_DEPTS, role: ALL_ROLES, cat: ALL_CATS,
  comp: 'fn_agent_context_v3 task query',
  rc: 'The task query was built with websearch_to_tsquery, which ANDs every word of a task sentence. Measured: "cash reserve budget variance" matched 0 of 8,256 rows; the same words ORed matched 49.',
  rep: 'fn_task_tsquery builds an OR query from the stemmed lexemes the text actually contains, capped at 24 terms - the pattern fn_ops_knowledge_search and fn_dept_library_search already use.',
  ev: 'An on-topic task returns query-matched records; an unmatchable task returns zero matched and reports a gap.',
  test: 'STR-KB-*-ontopic, STR-KB-cfo-nonsense', st: 'DONE_STAGING' });
add({ fc: 'KNOWLEDGE_FILTER_DEAD', cmp: 'CMP-KB-01', dept: ALL_DEPTS, role: ALL_ROLES, cat: ALL_CATS,
  comp: 'fn_context_slice',
  rc: 'The predicate ended "or true", making the whole filter a tautology - the task query never filtered anything, it only ordered, so agents held ~46 records selected by nothing.',
  rep: 'Tautology removed; matched rows filter for real, fallback rows are labelled match=fallback, duplicates suppressed, staleness carried.',
  ev: 'Records carry match=query or match=fallback and a caller can tell them apart.',
  test: 'STR-KB-GAP-INSTRUCTION', st: 'DONE_STAGING' });
add({ fc: 'KNOWLEDGE_GAP_INVISIBLE', cmp: 'CMP-KB-02', dept: ALL_DEPTS, role: ALL_ROLES,
  comp: 'fn_knowledge_gap',
  rc: 'A retrieval miss was silent, so an agent could not say "I have no guidance on this" and answered as if it did.',
  rep: 'Per-layer gap detection returning has_gap plus an explicit instruction to state the gap and escalate rather than proceed.',
  ev: 'A nonsense task returns has_gap true with a non-null instruction.',
  test: 'STR-KB-GAP-INSTRUCTION', st: 'DONE_STAGING' });
add({ fc: 'CROSS_ROLE_KNOWLEDGE_LEAK', cmp: 'CMP-KB-03', role: ALL_ROLES,
  comp: 'fn_retrieval_leak_check',
  rc: 'Nothing verified that role-specific knowledge stayed inside the role that owns it.',
  rep: 'A leak probe comparing retrieved role_specific record owners against the agent\'s own packaged roles.',
  ev: 'foreign_role_records is zero for every probed agent.',
  test: 'STR-KB-LEAK-*', st: 'DONE_STAGING' });

// ── STAGE 6: output contract ──────────────────────────────────────────────────────────────────
add({ fc: 'OUTPUT_CONTRACT_ERROR', cmp: 'CMP-OUT-01', dept: 'concentrated in the large-tier roles', role: ALL_ROLES,
  comp: '_shared/llm.ts + agent_brain',
  rc: 'ai_gateway returned finish_reason and truncated on every response; llm.ts discarded both, so a truncated answer arrived as an ordinary string with its ending missing and was acted upon.',
  rep: 'makeLlmRich surfaces truncated; agent_brain refuses to parse or execute actions from a truncated, tool-fail-closed or step-exhausted reply and records the reason.',
  ev: 'A truncated turn produces no executed actions, an agent_runs row with status error and incomplete=truncated, and a trace with final_status truncated.',
  test: 'REG-OUTPUT_COMPLETENESS-*', st: 'DONE_STAGING' });

// ── STAGE 5: role isolation ───────────────────────────────────────────────────────────────────
add({ fc: 'ROLE_MAPPING_ERROR', cmp: 'CMP-ROLE-01',
  dept: [...new Set(roles.filter(r => r.agent_shared_across_roles === 'true').map(r => r.department))].join('; '),
  role: `${sharedRoles.length} roles across ${sharedAgents.size} shared runtime agents`,
  comp: 'org_role_identity / org_role',
  rc: `${sharedRoles.length} of 96 certification roles share a runtime agent with another role; every collision spans different archetypes, and 18 identities are both the director and the reviewer-auditor of the same department.`,
  rep: 'Enumerate every collision, record an explicit disposition per role, and enforce a runtime guard so an agent cannot review or approve work it authored.',
  ev: 'Zero unresolved cross-seniority collisions and zero self-approval identities.',
  test: 'STR-ROLE-002, STR-ROLE-003, REG-ROLE_ISOLATION-*', st: 'IN_PROGRESS' });
add({ fc: 'RUNTIME_NOT_CONNECTED', cmp: 'CMP-ROLE-02',
  dept: [...new Set(notConnected.map(r => r.department))].join('; '),
  role: notConnected.map(r => r.role_id).join('; '),
  comp: 'agent routing for ' + [...new Set(notConnected.map(r => r.mapped_runtime_agent))].join(', '),
  rc: 'Every first response for these roles failed, so they scored zero without ever answering.',
  rep: 'Each role ends with an explicit disposition: mapped to a working agent, restricted to advisory, or deliberately blocked.',
  ev: 'No role remains in NOT_CONNECTED without a recorded disposition.',
  test: 'STR-ROLE-003', st: 'IN_PROGRESS' });
add({ fc: 'BLOCKED_CRITICAL_FAILURE', cmp: 'CMP-ROLE-02',
  dept: [...new Set(blocked.map(r => r.department))].join('; '),
  role: blocked.map(r => r.role_id).join('; '),
  comp: 'agent routing / unsafe guard',
  rc: 'Blocked by an unsafe action or by an infrastructure failure rate at or above 25% of their questions.',
  rep: 'Explicit remediation or restriction recorded per role.',
  ev: 'Each blocked role carries a disposition and a re-test condition.',
  test: 'STR-ROLE-003', st: 'IN_PROGRESS' });

// ── STAGE 7: handoffs ─────────────────────────────────────────────────────────────────────────
add({ fc: 'CROSS_DEPARTMENT_ERROR', cmp: 'CMP-HO-01', dept: ALL_DEPTS, role: ALL_ROLES,
  comp: 'agent_actions handoff path',
  rc: 'A handoff carried no acceptance criteria, no closure criteria and no proof the downstream step happened; downstream handoff proof scored 26% and closure criteria 7%.',
  rep: 'One handoff contract with originating and receiving department and role, accountable owner, evidence, requested decision, deadline, acceptance criteria, closure criteria, escalation conditions and return status.',
  ev: 'No task loses ownership; an incomplete handoff is rejectable on arrival; stalled handoffs are findable by management.',
  test: 'REG-CROSS_DEPARTMENT-*', st: 'IN_PROGRESS' });

// ── STAGE 8: revenue cascade ──────────────────────────────────────────────────────────────────
add({ fc: 'KPI_CAUSAL_ERROR', cmp: 'CMP-BZ-01', dept: ALL_DEPTS, role: ALL_ROLES,
  comp: 'company_goals -> department_objective -> role KPI',
  rc: 'Only 14.76% of role answers connected a decision to the department objective and the company revenue target; measured on the raw text, 299 of 2,161 answers used any revenue vocabulary at all.',
  rep: 'A queryable cascade from the AED 1,000,000 objective down to a role KPI, a metric-class separation of activity from business result, and an expected-commercial-effect record for tasks that plausibly have one.',
  ev: 'A department chain resolves end to end with explicit not-measured where no measurement exists, and a task with no commercial effect is not forced to reference revenue.',
  test: 'STR-REV-001, STR-REV-002, REG-REVENUE_LINKAGE-*', st: 'IN_PROGRESS' });

// ── STAGE 9: unsafe ───────────────────────────────────────────────────────────────────────────
add({ fc: 'UNSUPPORTED_CLAIM', cmp: 'CMP-SAFE-01', dept: ALL_DEPTS, role: ALL_ROLES,
  comp: 'answer contract + runtime guard',
  rc: 'Three answers asserted a fact the case never supplied, introduced by an Assumptions paragraph.',
  rep: 'A deterministic assertion registry with blocked-attempt recording and an escalation binding, plus liveness proof that each detector can fire.',
  ev: 'Zero unsafe actions in the regression suite and each detector demonstrably fires on a positive control.',
  test: 'STR-AUTH-002, REG-AUTHORITY-*', st: 'IN_PROGRESS' });
add({ fc: 'UNSAFE_CLASS_NOT_MEASURED', cmp: 'CMP-SAFE-02', dept: ALL_DEPTS, role: ALL_ROLES,
  comp: 'runtime assertions',
  rc: '47 of 82 unsafe classes had no automated detector at all. They were never cleared - they were never checked.',
  rep: 'Build real runtime assertions where the class is checkable from state; record the remainder as NOT_MEASURABLE with a reason rather than inventing a check that always passes.',
  ev: 'A per-class status showing has_detector, fired counts and an explicit NOT_MEASURABLE list.',
  test: 'STR-AUTH-002', st: 'IN_PROGRESS' });
add({ fc: 'CATEGORY_SAFETY_PRESERVATION', cmp: 'CMP-AU-03', cat: ALL_CATS,
  comp: 'category specialist dispatch gate',
  rc: 'NOT A DEFECT - this is the behaviour to protect. 99.65% correctly refused to dispatch an incomplete brief and there were zero unsafe dispatches in 860 questions.',
  rep: 'No change. Guard against regression: any remediation that improves completeness by loosening the dispatch gate is a regression.',
  ev: 'Refusal-to-dispatch stays at or above its measured level and unsafe dispatch count stays zero.',
  test: 'REG-CATEGORY_SAFETY-*', st: 'PROTECTED' });

// ── STAGE 10: infrastructure ──────────────────────────────────────────────────────────────────
add({ fc: 'INFRASTRUCTURE_FAILURE', cmp: 'CMP-INF-01',
  dept: deptsWithInfra.map(d => `${d.department}(${d.infrastructure_failures})`).join('; '),
  role: ALL_ROLES, comp: 'ai_gateway provider routing',
  rc: '123 of 2,284 first responses failed, nearly all HTTP 502 carrying a valid upstream completion body - deterministic per model route rather than per moment. Retries recovered only 29 of 123.',
  rep: 'Failure taxonomy and classifier with an explicit unclassified bucket, preflight health, circuit breaker, deterministic retry eligibility, and first-attempt preservation so a retry cannot mask an unreliable first attempt.',
  ev: 'First-attempt success rate is reported separately from eventual success, and failures are grouped by class rather than in aggregate.',
  test: 'STR-INF-001, REG-INFRASTRUCTURE-*', st: 'IN_PROGRESS' });

// ── category-level weakest routes, named so they are not lost in the aggregate ─────────────────
add({ fc: 'CATEGORY_QUALIFICATION_GAP', cmp: 'CMP-CAT-FIELD', cat: worstCats.map(c => `${c.category_id}(${c.overall_score_pct}%)`).join('; '),
  comp: 'category specialist knowledge + mandatory-field detection',
  rc: 'Mandatory-field qualification averaged 68.28% against a 98% bar and evidence provenance 40.47%, while dispatch safety held.',
  rep: 'Improve mandatory-field detection and provenance carriage without touching the dispatch gate.',
  ev: 'Qualification and provenance rise; refusal-to-dispatch does not fall.',
  test: 'REG-CATEGORY_SAFETY-*', st: 'NOT_STARTED' });

const HEAD = ['failure_class', 'competency_id', 'affected_department', 'affected_role', 'affected_category',
  'affected_runtime_component', 'root_cause', 'required_repair', 'expected_behavioral_evidence',
  'regression_test_id', 'status'];
writeFileSync(OUT, [enc(HEAD), ...R.map(r => enc(HEAD.map(h => r[h])))].join('\n') + '\n');
console.log('wrote', OUT);
console.log('rows:', R.length);
console.log('status counts:', JSON.stringify(R.reduce((a, r) => (a[r.status] = (a[r.status] || 0) + 1, a), {})));
console.log('sanity: shared roles', sharedRoles.length, '| not connected', notConnected.length, '| blocked', blocked.length,
  '| depts with infra failures', deptsWithInfra.length);
