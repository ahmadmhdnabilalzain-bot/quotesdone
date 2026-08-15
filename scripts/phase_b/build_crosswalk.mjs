// Build docs/phase-b/PHASE_B_CURRENT_TO_TARGET_WORKFLOW_CROSSWALK.csv.
//
// Classification is driven by MEASURED evidence, never by "the object exists":
//   * a cron job that has never run is not a connected path;
//   * an edge function with no caller in repo, database or cron is not a connected path
//     unless it serves an external surface (a browser page, a provider webhook, an OAuth
//     callback), which is read from its own source;
//   * a runtime workflow definition with zero workflow_run rows has never executed.
//
// Every row carries the command that produced its verdict so the verdict can be re-measured.
import { writeFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { REPO, loadPackage } from './lib/package.mjs';
import {
  CRON_TO_WORKFLOW, RUNTIME_WORKFLOW_TO_CANONICAL, EDGE_TO_WORKFLOW, ROUTE_TO_WORKFLOW,
} from './lib/crosswalk_map.mjs';

const OUT = join(REPO, 'docs', 'phase-b', 'PHASE_B_CURRENT_TO_TARGET_WORKFLOW_CROSSWALK.csv');
// PowerShell's `>` redirect writes a UTF-8 BOM, which JSON.parse rejects.
const j = f => JSON.parse(readFileSync(join(REPO, 'docs', 'phase-b', f), 'utf8').replace(/^﻿/, ''));
const inv = j('_inventory.json');
const callers = j('_edge_callers.json');
const entry = j('_entry_points.json');
const pkg = loadPackage();

const HEADER = ['current_artifact_type', 'current_artifact_name', 'repository_or_database_location',
  'current_trigger_or_caller', 'current_owner_or_actor', 'current_states_or_outcomes',
  'target_workflow_id', 'target_step_id', 'target_classification', 'duplicate_or_conflicting_path',
  'historical_compatibility_required', 'phase_c_wiring_action', 'evidence_command',
  'evidence_result', 'notes'];

const rows = [];
const add = o => rows.push(HEADER.map(h => o[h] ?? ''));

// ------------------------------------------------------------------ runtime workflows
const stepsBy = Object.fromEntries(inv.db.workflow_tables.workflow_step.map(s => [s.workflow_key, s]));
const runsBy = Object.fromEntries(inv.db.workflow_tables.workflow_run.map(s => [s.workflow_key, s]));
const empBy = Object.fromEntries(inv.db.workflow_tables.employee_workflow.map(s => [s.workflow_key, s]));

for (const w of inv.db.workflow_tables.workflow) {
  const st = stepsBy[w.workflow_key] ?? {}, rn = runsBy[w.workflow_key] ?? {}, em = empBy[w.workflow_key] ?? {};
  const targets = RUNTIME_WORKFLOW_TO_CANONICAL[w.workflow_key] ?? ['OUT_OF_SCOPE'];
  const ranEver = Number(rn.runs ?? 0) > 0;
  const spansMany = targets.length > 1;
  const cls = !ranEver ? 'PHASE_C_WIRING_GAP'
    : spansMany ? 'CANONICAL_PARTIAL'
    : 'CANONICAL_PARTIAL';
  add({
    current_artifact_type: 'runtime_workflow_definition',
    current_artifact_name: w.workflow_key,
    repository_or_database_location: 'public.workflow + public.workflow_step',
    current_trigger_or_caller: w.trigger_event || 'workflow_start_due / workflow_dispatch_10min',
    current_owner_or_actor: `workflow_step.actor_role x${st.actors ?? 0}`,
    current_states_or_outcomes: `${st.steps ?? 0} steps, ${st.gated ?? 0} gated, ${rn.runs ?? 0} runs, last ${rn.last_run ?? 'never'}`,
    target_workflow_id: targets.join(';'),
    target_step_id: '',
    target_classification: cls,
    duplicate_or_conflicting_path: spansMany
      ? `spans ${targets.length} canonical workflows in one definition` : '',
    historical_compatibility_required: 'yes',
    phase_c_wiring_action: !ranEver
      ? 'connect a real trigger, or retire the definition; it has never executed'
      : spansMany
        ? 'split into the canonical workflows it spans and give each its own accountable owner'
        : 'align step ownership to the canonical step registry',
    evidence_command: `select count(*) from public.workflow_run where workflow_key = '${w.workflow_key}'`,
    evidence_result: `${rn.runs ?? 0} runs; ${em.rows ?? 0} employee_workflow rows; ${em.owners ?? 0} owners`,
    notes: !ranEver ? 'defined, gated and owned, but has never executed once' : '',
  });
}

// -------------------------------------------------------------------------- cron jobs
for (const c of inv.cron) {
  const target = CRON_TO_WORKFLOW[c.jobname] ?? 'UNMAPPED';
  const ranEver = Number(c.runs ?? 0) > 0;
  // A job that ran 21,563 times and was switched off on a stated date is DEACTIVATED, not dead.
  // Only "never ran at all" is evidence of an unproven path.
  const cls = target === 'OUT_OF_SCOPE' ? 'OUT_OF_SCOPE'
    : target === 'UNMAPPED' ? 'UNOWNED'
    : !ranEver ? 'PHASE_C_WIRING_GAP'
    : c.last_status && c.last_status !== 'succeeded' ? 'CONFLICTING_PATH'
    : 'CANONICAL_PARTIAL';
  add({
    current_artifact_type: 'cron_job',
    current_artifact_name: c.jobname,
    repository_or_database_location: `cron.job jobid=${c.jobid}`,
    current_trigger_or_caller: `schedule ${c.schedule}`,
    current_owner_or_actor: 'pg_cron (no accountable role attached)',
    current_states_or_outcomes: `active=${c.active}, runs=${c.runs ?? 0}, last=${c.last_start ?? 'never'} ${c.last_status ?? ''}`.trim(),
    target_workflow_id: target === 'UNMAPPED' ? '' : target,
    target_step_id: '',
    target_classification: cls,
    duplicate_or_conflicting_path: cls === 'CONFLICTING_PATH' ? `last run ${c.last_status}` : '',
    historical_compatibility_required: 'yes',
    phase_c_wiring_action: cls === 'PHASE_C_WIRING_GAP'
      ? 'scheduled but never executed; prove it fires before relying on it'
      : cls === 'CONFLICTING_PATH' ? 'failing job; fix before it can carry a canonical step'
      : cls === 'UNOWNED' ? 'assign to a canonical workflow and accountable role'
      : !c.active ? 'deactivated job with prior successful runs; decide reactivation in Phase C'
      : 'attach to the canonical step it advances and record its accountable role',
    evidence_command: `select count(*), max(start_time) from cron.job_run_details where jobid = ${c.jobid}`,
    evidence_result: `${c.runs ?? 0} runs; last ${c.last_start ?? 'never'}; status ${c.last_status ?? 'n/a'}`,
    notes: !ranEver && c.active ? 'active schedule that has produced no run row'
      : !c.active ? `DEACTIVATED; ${c.runs} prior runs, last ${String(c.last_start ?? '').slice(0, 10)}` : '',
  });
}

// --------------------------------------------------------------------- edge functions
const callerBy = Object.fromEntries(callers.functions.map(f => [f.slug, f]));
const entryBy = Object.fromEntries(entry.functions.map(f => [f.slug, f]));
const EXTERNAL = new Set(['provider_webhook', 'oauth_callback', 'public_html_page']);

for (const f of callers.functions) {
  const e = entryBy[f.slug] ?? {};
  const target = EDGE_TO_WORKFLOW[f.slug] ?? 'UNMAPPED';
  const internal = f.callers > 0;
  const external = EXTERNAL.has(e.surface);
  const who = [
    f.frontend.length ? `frontend:${f.frontend.length}` : null,
    f.edge.length ? `edge:${f.edge.length}` : null,
    f.db.length ? `db:${f.db.join('|').slice(0, 60)}` : null,
    f.cron.length ? `cron:${f.cron.join('|')}` : null,
  ].filter(Boolean).join(' ');

  const cls = target === 'OUT_OF_SCOPE' ? 'OUT_OF_SCOPE'
    : target === 'UNMAPPED' ? (internal || external ? 'UNOWNED' : 'DEAD_CODE')
    : internal ? 'CANONICAL_PARTIAL'
    : external ? 'CANONICAL_PARTIAL'
    : 'PHASE_C_WIRING_GAP';
  add({
    current_artifact_type: 'edge_function',
    current_artifact_name: f.slug,
    repository_or_database_location: `supabase/functions/${f.slug}/index.ts`,
    current_trigger_or_caller: who || (external ? `external:${e.surface}` : 'NONE FOUND'),
    current_owner_or_actor: 'service role (no accountable role attached)',
    current_states_or_outcomes: `entry_surface=${e.surface ?? '?'}`,
    target_workflow_id: target === 'UNMAPPED' ? '' : target,
    target_step_id: '',
    target_classification: cls,
    duplicate_or_conflicting_path: '',
    historical_compatibility_required: 'yes',
    phase_c_wiring_action: cls === 'PHASE_C_WIRING_GAP'
      ? 'no caller in repo, database or cron and no external entry surface; wire it or retire it'
      : cls === 'DEAD_CODE' ? 'no caller and no canonical workflow; retire'
      : cls === 'UNOWNED' ? 'runs under the service role; bind to a canonical accountable role'
      : 'bind the invocation to the canonical step and its accountable role',
    evidence_command: 'node scripts/phase_b/edge_callers.mjs',
    evidence_result: `${f.callers} internal callers; surface ${e.surface ?? '?'}`,
    notes: e.uses_llm ? 'imports the LLM client; must stay held while Phase B runs' : '',
  });
}

// -------------------------------------------------------------------------- frontend
for (const p of inv.frontend) {
  const target = ROUTE_TO_WORKFLOW[p.route] ?? 'UNMAPPED';
  add({
    current_artifact_type: 'frontend_route',
    current_artifact_name: p.route,
    repository_or_database_location: p.path,
    current_trigger_or_caller: 'browser navigation',
    current_owner_or_actor: 'end user (customer / supplier / founder)',
    current_states_or_outcomes: 'rendered page',
    target_workflow_id: target === 'UNMAPPED' ? '' : target,
    target_step_id: '',
    target_classification: target === 'OUT_OF_SCOPE' ? 'OUT_OF_SCOPE'
      : target === 'UNMAPPED' ? 'UNOWNED' : 'CANONICAL_PARTIAL',
    duplicate_or_conflicting_path: '',
    historical_compatibility_required: 'yes',
    phase_c_wiring_action: 'bind the page action to the canonical start event or step it triggers',
    evidence_command: 'ls src/app/**/page.tsx',
    evidence_result: 'route present in the built app',
    notes: '',
  });
}

// --------------------------------------------------------------------------- triggers
for (const t of inv.db.triggers) {
  const enabled = t.tgenabled === 'O' || t.tgenabled === 'A';
  add({
    current_artifact_type: 'database_trigger',
    current_artifact_name: `${t.table_name}.${t.tgname}`,
    repository_or_database_location: `public.${t.table_name} -> ${t.function_name}()`,
    current_trigger_or_caller: [t.on_insert && 'INSERT', t.on_update && 'UPDATE', t.on_delete && 'DELETE']
      .filter(Boolean).join('/') + (t.is_before ? ' BEFORE' : ' AFTER'),
    current_owner_or_actor: 'database (no accountable role attached)',
    current_states_or_outcomes: `enabled=${t.tgenabled}`,
    target_workflow_id: 'ALL',
    target_step_id: '',
    target_classification: enabled ? 'CANONICAL_KEEP' : 'DEAD_CODE',
    duplicate_or_conflicting_path: '',
    historical_compatibility_required: 'yes',
    phase_c_wiring_action: enabled
      ? 'structural guard; keep, and record which canonical gate it enforces'
      : 'disabled trigger; remove or re-enable deliberately',
    evidence_command: `select tgenabled from pg_trigger where tgname = '${t.tgname}'`,
    evidence_result: `tgenabled=${t.tgenabled}`,
    notes: '',
  });
}

// --------------------------------------------------------------- workflow/state tables
for (const t of inv.db.state_tables) {
  add({
    current_artifact_type: 'state_table',
    current_artifact_name: t.table_name,
    repository_or_database_location: `public.${t.table_name}`,
    current_trigger_or_caller: 'written by edge functions, cron jobs and database routines',
    current_owner_or_actor: 'varies',
    current_states_or_outcomes: `state columns: ${t.state_columns}; rows=${t.rows}`,
    target_workflow_id: 'ALL',
    target_step_id: '',
    target_classification: Number(t.rows) === 0 ? 'PHASE_C_WIRING_GAP' : 'CANONICAL_PARTIAL',
    duplicate_or_conflicting_path: '',
    historical_compatibility_required: 'yes',
    phase_c_wiring_action: Number(t.rows) === 0
      ? 'state table that has never received a row; prove a writer exists before relying on it'
      : 'map its state column onto the canonical workflow or step state model',
    evidence_command: `select count(*) from public.${t.table_name}`,
    evidence_result: `${t.rows} rows`,
    notes: '',
  });
}

// ------------------------------------------------------------ canonical coverage gaps
const covered = new Set();
for (const r of rows) {
  const t = r[HEADER.indexOf('target_workflow_id')];
  for (const w of String(t).split(';')) if (/^W\d\d$/.test(w)) covered.add(w);
}
for (const w of pkg.workflows) {
  if (covered.has(w.workflow_id)) continue;
  add({
    current_artifact_type: 'none',
    current_artifact_name: `(no current path) ${w.workflow_id} ${w.workflow_name}`,
    repository_or_database_location: '',
    current_trigger_or_caller: 'NONE',
    current_owner_or_actor: 'NONE',
    current_states_or_outcomes: 'no current implementation found',
    target_workflow_id: w.workflow_id,
    target_step_id: '',
    target_classification: 'PHASE_C_WIRING_GAP',
    duplicate_or_conflicting_path: '',
    historical_compatibility_required: 'no',
    phase_c_wiring_action: 'build the runtime path; the canonical workflow has no current implementation',
    evidence_command: 'node scripts/phase_b/build_crosswalk.mjs',
    evidence_result: 'no cron job, edge function, runtime workflow or route maps to this workflow',
    notes: 'canonical workflow with zero current coverage',
  });
}

const esc = v => /[",\n]/.test(String(v)) ? `"${String(v).replace(/"/g, '""')}"` : String(v);
writeFileSync(OUT, [HEADER, ...rows].map(r => r.map(esc).join(',')).join('\n') + '\n', 'utf8');

const tally = {};
for (const r of rows) {
  const c = r[HEADER.indexOf('target_classification')];
  tally[c] = (tally[c] ?? 0) + 1;
}
console.log(`wrote ${rows.length} rows -> ${OUT.slice(REPO.length + 1)}`);
console.log(JSON.stringify(tally, null, 1));
