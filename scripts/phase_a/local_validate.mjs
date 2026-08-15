// PHASE A — STEP 4: zero-cost local verification. No network, no database, no model call.
//
// Everything here is decidable from the package files and the generated SQL alone, which is the
// point: these are the failures that must never reach a production transaction, and none of them
// needs a database to find.
//
//   node scripts/phase_a/local_validate.mjs <package-dir>
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';

const PKG = process.argv[2];
if (!PKG) { console.error('usage: node scripts/phase_a/local_validate.mjs <package-dir>'); process.exit(2); }

function parseCsv(text) {
  const rows = []; let row = [], f = '', q = false;
  const s = text.replace(/^﻿/, '').replace(/\r\n/g, '\n');
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (q) { if (c === '"') { if (s[i + 1] === '"') { f += '"'; i++; } else q = false; } else f += c; }
    else if (c === '"') q = true;
    else if (c === ',') { row.push(f); f = ''; }
    else if (c === '\n') { row.push(f); rows.push(row); row = []; f = ''; }
    else f += c;
  }
  if (f.length || row.length) { row.push(f); rows.push(row); }
  const h = rows.shift().map(x => x.trim());
  return rows.filter(r => r.some(v => String(v).trim()))
    .map(r => Object.fromEntries(h.map((k, i) => [k, String(r[i] ?? '').trim()])));
}
const csv = (n) => parseCsv(readFileSync(`${PKG}/${n}.csv`, 'utf8'));

let pass = 0, fail = 0;
const check = (name, ok, detail = '') => {
  if (ok) { pass++; console.log(`PASS  ${name}${detail ? '  — ' + detail : ''}`); }
  else { fail++; console.log(`FAIL  ${name}  — ${detail}`); }
};

// ---- 1. every package file parses ---------------------------------------------------------------
const T = {};
for (const n of ['PHASE_A_DEPARTMENT_REGISTRY', 'PHASE_A_CANONICAL_ROLE_REGISTRY', 'PHASE_A_REPORTING_GRAPH',
  'PHASE_A_CATEGORY_OVERLAY_REGISTRY', 'PHASE_A_WORKFLOW_OWNERSHIP', 'CURRENT_TO_FINAL_ROLE_CHANGES',
  'PHASE_A_EXECUTIVE_COMMITTEE']) {
  try { T[n] = csv(n); check(`${n} parses`, T[n].length > 0, `${T[n].length} rows`); }
  catch (e) { check(`${n} parses`, false, e.message); }
}

// ---- 2. the SHA-256 manifest still matches ------------------------------------------------------
{
  const sums = readFileSync(`${PKG}/SHA256SUMS.txt`, 'utf8').split('\n').filter(Boolean);
  let bad = [];
  for (const line of sums) {
    const m = line.trim().match(/^([0-9a-f]{64})\s+\*?(.+)$/);
    if (!m) continue;
    const got = createHash('sha256').update(readFileSync(`${PKG}/${m[2].trim()}`)).digest('hex');
    if (got !== m[1]) bad.push(m[2].trim());
  }
  check('every package file matches SHA256SUMS.txt', bad.length === 0, bad.join(', ') || `${sums.length} files`);
}

// ---- 3. 10 / 90 / 86 reconcile ------------------------------------------------------------------
const depts = T.PHASE_A_DEPARTMENT_REGISTRY, roles = T.PHASE_A_CANONICAL_ROLE_REGISTRY;
const overlays = T.PHASE_A_CATEGORY_OVERLAY_REGISTRY, flows = T.PHASE_A_WORKFLOW_OWNERSHIP;
check('10 active primary departments', depts.filter(d => /true/i.test(d.active)).length === 10,
  `${depts.filter(d => /true/i.test(d.active)).length}`);
check('90 canonical accountable standing roles', roles.length === 90, `${roles.length}`);
check('86 category overlays', overlays.length === 86, `${overlays.length}`);
check('30 organizational workflows', flows.length === 30, `${flows.length}`);
{
  const counts = new Map();
  for (const r of roles) counts.set(r.department_id, (counts.get(r.department_id) || 0) + 1);
  const got = [...counts.values()].sort((a, b) => a - b).join(',');
  check('department role counts are 4,6,7,7,7,9,11,11,11,17', got === '4,6,7,7,7,9,11,11,11,17', got);
  const unknown = [...counts.keys()].filter(k => !depts.some(d => d.department_id === k));
  check('every role names a department that exists', unknown.length === 0, unknown.join(', ') || 'all resolve');
}
check('no overlay is counted among the 90 standing roles',
  overlays.every(o => /^no$/i.test(o.standing_role_counted)),
  overlays.filter(o => !/^no$/i.test(o.standing_role_counted)).map(o => o.overlay_id).join(', ') || '86/86 marked NO');

// ---- 4. identity ---------------------------------------------------------------------------------
{
  const ids = roles.map(r => r.canonical_role_id);
  const dupes = ids.filter((v, i) => ids.indexOf(v) !== i);
  check('every role has one canonical id, no duplicates', dupes.length === 0, dupes.join(', ') || `${ids.length} unique`);
  const noPurpose = roles.filter(r => !r.organizational_purpose);
  check('every role states an organizational purpose', noPurpose.length === 0, noPurpose.map(r => r.canonical_role_id).join(', '));
  const noNecessity = roles.filter(r => !r.necessity_status);
  check('every role states a necessity status', noNecessity.length === 0, noNecessity.map(r => r.canonical_role_id).join(', '));
  const noForbidden = roles.filter(r => !r.decisions_forbidden);
  check('every role states forbidden decisions', noForbidden.length === 0, noForbidden.map(r => r.canonical_role_id).join(', '));
  const noOwned = roles.filter(r => !r.decisions_owned && !r.workflows_served);
  check('every role owns at least one decision or workflow', noOwned.length === 0, noOwned.map(r => r.canonical_role_id).join(', '));
}

// ---- 5. reporting graph is acyclic and terminates -------------------------------------------------
{
  const graph = T.PHASE_A_REPORTING_GRAPH;
  const mgr = new Map(graph.map(g => [g.role_id, g.manager_role_id]));
  const ids = new Set(roles.map(r => r.canonical_role_id));
  const selfMgr = graph.filter(g => g.role_id === g.manager_role_id);
  check('no self-management', selfMgr.length === 0, selfMgr.map(g => g.role_id).join(', '));
  const dangling = graph.filter(g => g.manager_role_id && g.manager_role_id !== 'founder' && !ids.has(g.manager_role_id));
  check('every manager is a role that exists', dangling.length === 0,
    dangling.map(g => `${g.role_id}->${g.manager_role_id}`).join(', ') || 'all resolve');
  let cyc = [];
  for (const start of mgr.keys()) {
    const seen = new Set([start]); let cur = mgr.get(start), n = 0;
    while (cur && mgr.has(cur) && n++ < 100) {
      if (seen.has(cur)) { cyc.push(`${start}…${cur}`); break; }
      seen.add(cur); cur = mgr.get(cur);
    }
  }
  check('no reporting cycles', cyc.length === 0, cyc.join(', ') || `${mgr.size} chains terminate`);
  const missing = roles.filter(r => !mgr.has(r.canonical_role_id));
  check('every role appears in the reporting graph', missing.length === 0, missing.map(r => r.canonical_role_id).join(', '));
}

// ---- 6. reviewer independence ---------------------------------------------------------------------
{
  const selfRev = roles.filter(r => r.independent_reviewer_role_id
    && r.independent_reviewer_role_id === r.canonical_role_id);
  check('no role is its own independent reviewer', selfRev.length === 0, selfRev.map(r => r.canonical_role_id).join(', '));
  const ids = new Set(roles.map(r => r.canonical_role_id));
  const bad = roles.filter(r => r.independent_reviewer_role_id && r.independent_reviewer_role_id !== 'founder'
    && !ids.has(r.independent_reviewer_role_id));
  check('every named reviewer is a role that exists', bad.length === 0,
    bad.map(r => `${r.canonical_role_id}->${r.independent_reviewer_role_id}`).join(', ') || 'all resolve');
  // The specific separations the invariants name, checked as department separation rather than as
  // a promise: an evaluator inside the department that builds the thing is not independent.
  const dept = new Map(roles.map(r => [r.canonical_role_id, r.department_id]));
  const pairs = [['model_evaluation_reviewer', 'agent_prompt_engineer', 'model/prompt creation vs evaluation']];
  for (const [a, b, what] of pairs) {
    check(`${what} sit in different departments`, dept.get(a) && dept.get(b) && dept.get(a) !== dept.get(b),
      `${a}=${dept.get(a)} · ${b}=${dept.get(b)}`);
  }
}

// ---- 7. workflow ownership -------------------------------------------------------------------------
{
  const ids = new Set(roles.map(r => r.canonical_role_id));
  const unowned = flows.filter(f => !f.accountable_role_id);
  check('no unowned workflow', unowned.length === 0, unowned.map(f => f.workflow_id).join(', '));
  const multi = flows.filter(f => /[;,]/.test(f.accountable_role_id));
  check('no multiply-owned workflow', multi.length === 0, multi.map(f => f.workflow_id).join(', '));
  const ghost = flows.filter(f => !ids.has(f.accountable_role_id));
  check('every workflow owner is a canonical role', ghost.length === 0,
    ghost.map(f => `${f.workflow_id}->${f.accountable_role_id}`).join(', ') || `${flows.length} owners resolve`);
  const ownerIsReviewer = flows.filter(f => f.independent_reviewer_or_challenge_role === f.accountable_role_id);
  check('no workflow owner reviews their own workflow', ownerIsReviewer.length === 0,
    ownerIsReviewer.map(f => f.workflow_id).join(', '));
  const contribOwner = flows.filter(f => String(f.contributors || '').split(/\s*;\s*/).includes(f.accountable_role_id));
  check('a contributor is never also the accountable owner', contribOwner.length === 0,
    contribOwner.map(f => f.workflow_id).join(', '));
  const wid = flows.map(f => f.workflow_id);
  check('workflow ids are unique', new Set(wid).size === wid.length, `${new Set(wid).size}/${wid.length}`);
}

// ---- 8. overlays are on-demand and cannot decide -----------------------------------------------------
{
  const notOnDemand = overlays.filter(o => o.status !== 'ON_DEMAND_OVERLAY');
  check('all 86 overlays are ON_DEMAND_OVERLAY', notOnDemand.length === 0, notOnDemand.map(o => o.overlay_id).join(', '));
  const missingGov = overlays.filter(o => !o.operational_department_id || !o.invocation_role_id || !o.knowledge_owner_role_id);
  check('every overlay declares an owner, an invocation role and a knowledge path',
    missingGov.length === 0, missingGov.map(o => o.overlay_id).join(', '));
  const canDecide = overlays.filter(o => !/dispatch/i.test(o.cannot_decide) || !/supplier approval/i.test(o.cannot_decide));
  check('no overlay may dispatch or approve suppliers', canDecide.length === 0, canDecide.map(o => o.overlay_id).join(', '));
  const slugs = overlays.map(o => o.canonical_slug);
  check('overlay slugs are unique', new Set(slugs).size === slugs.length, `${new Set(slugs).size}/${slugs.length}`);
}

// ---- 9. the generated SQL ------------------------------------------------------------------------------
{
  const fwd = 'supabase/migrations/20260815050000_phase_a_organization_closure.sql';
  const back = 'scripts/sql/phase_a_rollback.sql';
  check('forward migration exists', existsSync(fwd), fwd);
  check('rollback exists', existsSync(back), back);
  const f = readFileSync(fwd, 'utf8'), b = readFileSync(back, 'utf8');
  check('forward migration asserts preconditions', /PRECONDITION:/.test(f));
  check('forward migration asserts postconditions', /POST:/.test(f));
  check('forward migration deletes no org_role row', !/delete\s+from\s+public\.org_role\b/i.test(f),
    'retirement is by status, so history survives');
  check('rollback restores every created object',
    /delete from public\.org_role where role_id='corporate_performance_director'/.test(b)
    && /delete from public\.org_role where role_id='strategic_partnerships_government_relations_manager'/.test(b)
    && /delete from public\.org_role where role_id='product_ux_designer'/.test(b)
    && /drop table if exists public\.org_workflow_ownership/.test(b));
  check('rollback proves the pre-change shape', /ROLLBACK: roles per department/.test(b));
  // The exclusions, checked against the text rather than trusted.
  const forbidden = [
    [/\bcron\.(schedule|alter_job|unschedule)/i, 'cron scheduling'],
    [/net\.http_(post|get)/i, 'an outbound HTTP call'],
    [/openrouter/i, 'OpenRouter'],
    [/\bllm_route_health\b/i, 'the provider hold'],
    [/insert\s+into\s+public\.(customers|inquiries|quotes|leads|suppliers)\b/i, 'synthetic marketplace data'],
    [/\bagent_tool\b|\bknowledge_scopes\s*=\s*array/i, 'tool or knowledge activation'],
  ];
  for (const [re, what] of forbidden) {
    check(`forward migration contains no ${what}`, !re.test(f), re.test(f) ? 'FOUND — Phase A forbids it' : '');
  }
}

console.log(`\n${pass} passed, ${fail} failed`);
console.log('paid inference requests: 0 · OpenRouter requests: 0 · cost: USD 0.00 (this file opens no socket)');
process.exit(fail ? 1 : 0);
