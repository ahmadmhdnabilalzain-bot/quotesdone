// Gate C0 — verify the committed Phase C package against its own checksums and counts,
// and measure every role/overlay/workflow/department token it addresses against the live
// frozen Phase A + Phase B organization.
//
//   node scripts/phase_c/validate_package.mjs
//
// Nothing here writes.  It exists so a claim about the package is a measurement rather
// than a reading of the README that ships inside it.
import { loadPackage, verifyChecksums, DECLARED_COUNTS, splitList } from './lib/package.mjs';
import { sql } from './lib/db.mjs';

const fail = [];
const note = (ok, what, detail) => {
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}${detail ? '  — ' + detail : ''}`);
  if (!ok) fail.push(what);
};

// ---------------------------------------------------------------- checksums + counts
const ck = verifyChecksums();
note(ck.ok, `checksums ${ck.checked}/${ck.checked}`, ck.bad.map(b => `${b.file}: ${b.reason}`).join('; '));

const pkg = loadPackage();
for (const [k, want] of Object.entries(DECLARED_COUNTS)) {
  note(pkg[k].length === want, `count ${k}`, `${pkg[k].length} (declared ${want})`);
}

// ---------------------------------------------------------------- live organization
const live = {
  roles: await sql(`select role_id, display_name, primary_department_id, status, runtime_mode
                    from public.org_role order by role_id`),
  aliases: await sql(`select alias, role_id, kind from public.org_role_alias order by alias`),
  depts: await sql(`select dept_key, name, active from public.org_departments order by dept_key`),
  deptAliases: await sql(`select packaged_department, dept_key from public.org_department_alias`),
  workflows: await sql(`select workflow_id, workflow_name, accountable_role_id from public.phase_b_workflow order by workflow_id`),
  steps: await sql(`select step_id, workflow_id, accountable_role_id from public.phase_b_workflow_step order by step_id`),
  handoffs: await sql(`select handoff_id, sending_role_id, receiving_role_id from public.phase_b_handoff order by handoff_id`),
  events: await sql(`select event_id from public.phase_b_event order by event_id`),
  gates: await sql(`select gate_id from public.phase_b_gate order by gate_id`),
  rules: await sql(`select rule_id from public.phase_b_business_rule order by rule_id`),
};

const activeRoles = new Set(live.roles.filter(r => r.status === 'active' && r.runtime_mode !== 'knowledge_overlay').map(r => r.role_id));
const activeOverlays = new Set(live.roles.filter(r => r.status === 'active' && r.runtime_mode === 'knowledge_overlay').map(r => r.role_id));
const aliasTo = new Map(live.aliases.map(a => [a.alias, a.role_id]));
const deptKeys = new Set(live.depts.filter(d => d.active).map(d => d.dept_key));
const deptAliasTo = new Map(live.deptAliases.map(a => [a.packaged_department, a.dept_key]));

note(activeRoles.size === 90, 'live canonical roles', String(activeRoles.size));
note(activeOverlays.size === 86, 'live category overlays', String(activeOverlays.size));
note(deptKeys.size === 10, 'live active departments', String(deptKeys.size));

const resolveRole = t => activeRoles.has(t) ? t : (aliasTo.has(t) && activeRoles.has(aliasTo.get(t)) ? aliasTo.get(t) : null);
const resolveOverlay = t => activeOverlays.has(t) ? t : (aliasTo.has(t) && activeOverlays.has(aliasTo.get(t)) ? aliasTo.get(t) : null);
const resolveDept = t => deptKeys.has(t) ? t : (deptAliasTo.has(t) && deptKeys.has(deptAliasTo.get(t)) ? deptAliasTo.get(t) : null);

// ---------------------------------------------------------------- token reconciliation
// Every column in the package that names a role, an overlay or a department, with the
// column it came from, so an unresolved token is reported with its exact provenance.
const roleTokens = new Map();     // token -> Set(source)
const deptTokens = new Map();
const overlayTokens = new Map();
const add = (map, tok, src) => {
  tok = String(tok ?? '').trim();
  if (!tok) return;
  if (!map.has(tok)) map.set(tok, new Set());
  map.get(tok).add(src);
};

for (const r of pkg.roles) { add(roleTokens, r.role_id, 'role_binding.role_id'); add(deptTokens, r.department_id, 'role_binding.department_id'); }
for (const o of pkg.overlays) { add(overlayTokens, o.overlay_id, 'overlay_binding.overlay_id'); }
for (const w of pkg.workflows) { add(roleTokens, w.accountable_role_id, 'workflow_binding.accountable_role_id'); }
for (const s of pkg.steps) { add(roleTokens, s.accountable_role_id, 'step_binding.accountable_role_id'); }
for (const h of pkg.handoffs) { add(roleTokens, h.sending_role_id, 'handoff.sending'); add(roleTokens, h.receiving_role_id, 'handoff.receiving'); }
for (const e of pkg.events) { add(roleTokens, e.accountable_role_id, 'event.accountable'); add(roleTokens, e.primary_consumer_role_id, 'event.consumer'); }
for (const g of pkg.gates) { add(roleTokens, g.accountable_role_id, 'gate.accountable'); }
for (const r of pkg.rules) { add(roleTokens, r.accountable_role_id, 'rule.accountable'); }
for (const a of pkg.authority) {
  add(roleTokens, a.accountable_role_id, 'authority.accountable');
  for (const c of splitList(a.review_or_contributors)) add(roleTokens, c, 'authority.review_or_contributors');
}
for (const i of pkg.intents) {
  add(roleTokens, i.default_accountable_role_id, 'intent.default_accountable');
  add(roleTokens, i.command_owner_role_id, 'intent.command_owner');
}
for (const s of pkg.systemActors) { add(roleTokens, s.accountable_role_id, 'system_actor.accountable'); add(deptTokens, s.department_id, 'system_actor.department'); }
for (const c of pkg.acceptance) {
  add(roleTokens, c.expected_primary_role, 'acceptance.primary');
  for (const r of splitList(c.expected_child_roles)) add(roleTokens, r, 'acceptance.child');
}

const unresolvedRoles = [...roleTokens].filter(([t]) => t !== 'founder' && !resolveRole(t) && !resolveOverlay(t));
const unresolvedDepts = [...deptTokens].filter(([t]) => !resolveDept(t));
const unresolvedOverlays = [...overlayTokens].filter(([t]) => !resolveOverlay(t));

console.log(`\nrole tokens addressed: ${roleTokens.size}  resolved: ${roleTokens.size - unresolvedRoles.length}  unresolved: ${unresolvedRoles.length}`);
for (const [t, srcs] of unresolvedRoles) console.log(`  UNRESOLVED role   ${t}   [${[...srcs].join(', ')}]`);
console.log(`department tokens: ${deptTokens.size}  unresolved: ${unresolvedDepts.length}`);
for (const [t, srcs] of unresolvedDepts) console.log(`  UNRESOLVED dept   ${t}   [${[...srcs].join(', ')}]`);
console.log(`overlay tokens: ${overlayTokens.size}  unresolved: ${unresolvedOverlays.length}`);
for (const [t] of unresolvedOverlays.slice(0, 20)) console.log(`  UNRESOLVED overlay ${t}`);

// ---------------------------------------------------------------- key-space reconciliation
const liveWf = new Set(live.workflows.map(w => w.workflow_id));
const liveStep = new Set(live.steps.map(s => s.step_id));
const liveHandoff = new Set(live.handoffs.map(h => h.handoff_id));
const liveEvent = new Set(live.events.map(e => e.event_id));
const liveGate = new Set(live.gates.map(g => g.gate_id));
const liveRule = new Set(live.rules.map(r => r.rule_id));

const missing = (pkgRows, key, liveSet) => pkgRows.map(r => r[key]).filter(k => !liveSet.has(k));
note(missing(pkg.workflows, 'workflow_id', liveWf).length === 0, 'package workflow ids exist in phase_b_workflow', missing(pkg.workflows, 'workflow_id', liveWf).join(','));
note(missing(pkg.steps, 'step_id', liveStep).length === 0, 'package step ids exist in phase_b_workflow_step', missing(pkg.steps, 'step_id', liveStep).slice(0, 10).join(','));
note(missing(pkg.handoffs, 'handoff_id', liveHandoff).length === 0, 'package handoff ids exist', missing(pkg.handoffs, 'handoff_id', liveHandoff).slice(0, 10).join(','));
note(missing(pkg.events, 'event_id', liveEvent).length === 0, 'package event ids exist', missing(pkg.events, 'event_id', liveEvent).slice(0, 10).join(','));
note(missing(pkg.gates, 'gate_id', liveGate).length === 0, 'package gate ids exist', missing(pkg.gates, 'gate_id', liveGate).slice(0, 10).join(','));
note(missing(pkg.rules, 'rule_id', liveRule).length === 0, 'package rule ids exist', missing(pkg.rules, 'rule_id', liveRule).slice(0, 10).join(','));

console.log(`\n${fail.length === 0 ? 'PACKAGE VALIDATED' : 'PACKAGE VALIDATION FAILED: ' + fail.join('; ')}`);
process.exit(fail.length === 0 && unresolvedDepts.length === 0 ? 0 : 1);
