// ROW #3 s38 — the operating manual documents a quarter of the company and calls itself complete.
//
// ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
//   s38-manual-self-documenting  MISSING  1 of 4 documented categories; missing: policies,
//                                         decision rules, departments
//
//   undocumented, counted directly against v_operating_manual and os_runbooks:
//     workflow            0 of 14
//     governance_policy  16 of 16
//     decision_policy    27 of 27
//     org_departments     3 of 13
//
// ── THE CAUSE IS THE VIEW, NOT THE CONTENT ──────────────────────────────────────────────────────
// Nothing is missing from the company. governance_policy holds sixteen written policies with their
// rule, their enforcement and the department that owns them; decision_policy holds twenty-seven
// decision rules with a description and a live value; org_departments holds thirteen departments
// with a charter and a north star. v_operating_manual unions four sources — operating_system,
// workflow, priority_hierarchy and cron_registry — and opens none of those three.
//
// So this is the row's own defect in its purest form: written down, and read by nothing. The fix
// is three UNION ALL branches over tables that are already populated. No text is authored here; a
// policy's summary is the rule as it is stored, a department's summary is its charter as it is
// stored. Nothing is invented, because inventing manual entries to satisfy a manual check would be
// the exact fraud the check exists to catch.
//
// `key` and `title` coincide for a governance policy because the table names it once —
// governance_policy.policy IS "No fabricated facts", and giving it a second, prettier name here
// would be this file writing documentation rather than exposing it.
//
// ── THE OTHER LEG WAS ALREADY GREEN ─────────────────────────────────────────────────────────────
// The check also asks that the manual REACH a surface. fn_ws_company_os already carries the 81
// runbooks into the browser payload — verified before this was written — so this change is the
// whole remaining distance.
//
// The view is read from the live database and appended to, with its existing text untouched, so
// the four branches that already work stay byte-identical. CREATE OR REPLACE VIEW cannot rename or
// reorder columns; adding UNION ALL branches leaves the column list alone, which is why the change
// takes this shape rather than editing the select list.
import { readFileSync, writeFileSync } from 'node:fs';
import { mgmtRead } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';

const OUT = 'scripts/sql/manual_documents_policies_rules_departments.sql';
const one = async (sql) => { const r = await mgmtRead(STAGE, sql); return r[0] ? Object.values(r[0])[0] : null; };

const viewDef = await one(`select pg_get_viewdef('public.v_operating_manual'::regclass, true)`);
if (!viewDef) { console.error('v_operating_manual not found'); process.exit(1); }
if (/governance_policy/.test(viewDef)) { console.error('REFUSING: v_operating_manual already opens governance_policy.'); process.exit(1); }

// The manual currently ends on cron_registry. If it does not, it has been extended since this was
// written and appending blindly would produce a view whose shape nobody has looked at.
const body = viewDef.replace(/;\s*$/, '').trimEnd();
if (!/FROM cron_registry$/i.test(body)) {
  console.error('REFUSING: v_operating_manual no longer ends on cron_registry. Re-read it first.');
  process.exit(1);
}

const SQL = `create or replace view public.v_operating_manual as
${body}
UNION ALL
 -- SIXTEEN WRITTEN POLICIES THE MANUAL NEVER OPENED. The rule, the enforcement and the owning
 -- department are stored on the row; this exposes them, it does not compose them.
 SELECT 'governance_policy'::text AS section,
    gp.policy AS key,
    gp.policy AS title,
    gp.rule AS summary,
    jsonb_build_object('domain', gp.domain, 'enforced_by', gp.enforced_by,
                       'enforcement', gp.enforcement, 'owner_dept', gp.owner_dept) AS detail
   FROM governance_policy gp
UNION ALL
 -- TWENTY-SEVEN DECISION RULES, each with the live value it is currently set to. The title is the
 -- key made readable; the meaning is the description exactly as the row carries it.
 SELECT 'decision_rule'::text AS section,
    dp.key AS key,
    initcap(replace(dp.key, '_', ' ')) AS title,
    dp.description AS summary,
    jsonb_build_object('value', dp.value, 'updated_at', dp.updated_at) AS detail
   FROM decision_policy dp
UNION ALL
 -- THIRTEEN ACTIVE DEPARTMENTS. Ten were reachable only because their key happened to appear in
 -- some other entry's title; three appeared nowhere at all.
 SELECT 'department'::text AS section,
    d.dept_key AS key,
    d.name AS title,
    d.charter AS summary,
    jsonb_build_object('north_star', d.north_star, 'lead_agent', d.lead_agent,
                       'brain_agent', d.brain_agent, 'health_fn', d.health_fn) AS detail
   FROM org_departments d
  WHERE COALESCE(d.active, true);`;

const selfLines = readFileSync(new URL(import.meta.url).pathname.replace(/^\//, ''), 'utf8').split('\n');
const end = selfLines.findIndex((l) => !l.startsWith('//'));
const HEADER = selfLines.slice(0, end < 0 ? selfLines.length : end)
  .map((l) => l.replace(/^\/\/ ?/, '-- ').replace(/^\/\//, '--')).join('\n');

writeFileSync(OUT, `${HEADER}\n\n${SQL}\n`);
console.log(`wrote ${OUT}`);
console.log(`  v_operating_manual + governance_policy, decision_policy, org_departments`);
