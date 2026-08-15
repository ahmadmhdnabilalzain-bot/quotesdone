// Deterministic reader for the committed Phase C package.
//
// Same contract as scripts/phase_b/lib/package.mjs: nothing here calls a model, a
// provider or the network.  Every function is pure over the committed bytes under
// docs/phase-c/package/, and the declared row counts are asserted so a truncated or
// re-generated CSV fails loudly instead of silently shrinking a registry.
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
export const PKG = join(REPO, 'docs', 'phase-c', 'package');
export const OUT = join(REPO, 'docs', 'phase-c');

/** RFC4180-ish CSV parser.  Handles quotes, embedded commas and newlines, and a BOM. */
export function parseCSV(text) {
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  const rows = [];
  let cur = [], field = '', inQ = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQ) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else inQ = false;
      } else field += c;
    } else if (c === '"') inQ = true;
    else if (c === ',') { cur.push(field); field = ''; }
    else if (c === '\r') { /* ignore */ }
    else if (c === '\n') { cur.push(field); rows.push(cur); cur = []; field = ''; }
    else field += c;
  }
  if (field !== '' || cur.length) { cur.push(field); rows.push(cur); }
  while (rows.length && rows[rows.length - 1].every(v => v === '')) rows.pop();
  return rows;
}

export function readCSV(file) {
  const rows = parseCSV(readFileSync(file, 'utf8'));
  const hdr = rows[0].map(h => h.trim());
  return rows.slice(1).map(r => Object.fromEntries(hdr.map((h, i) => [h, (r[i] ?? '').trim()])));
}

/** Serialise rows back to RFC4180 CSV using the given header order. */
export function writeCSV(header, rows) {
  const cell = v => {
    const s = v == null ? '' : String(v);
    return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return [header.join(','), ...rows.map(r => header.map(h => cell(r[h])).join(','))].join('\n') + '\n';
}

const csv = name => readCSV(join(PKG, name));

/** Split a `a; b; c` package cell into a trimmed list; empty cell -> []. */
export function splitList(v) {
  return String(v ?? '').split(';').map(s => s.trim()).filter(Boolean);
}

export const sha256 = s => createHash('sha256').update(s).digest('hex');
export const sha256File = p => createHash('sha256').update(readFileSync(p)).digest('hex');

/** Verify every file named in SHA256SUMS.txt.  Returns {ok, checked, bad[]}. */
export function verifyChecksums() {
  const lines = readFileSync(join(PKG, 'SHA256SUMS.txt'), 'utf8').split(/\r?\n/).filter(Boolean);
  const bad = [];
  for (const line of lines) {
    const m = line.match(/^([0-9a-f]{64})\s+(.+)$/);
    if (!m) { bad.push({ file: line, reason: 'unparseable SHA256SUMS line' }); continue; }
    const [, want, rel] = m;
    const p = join(PKG, rel);
    if (!existsSync(p)) { bad.push({ file: rel, reason: 'missing' }); continue; }
    const got = sha256File(p);
    if (got !== want) bad.push({ file: rel, reason: `digest ${got} != ${want}` });
  }
  return { ok: bad.length === 0, checked: lines.length, bad };
}

export function loadPackage() {
  return {
    roles: csv('PHASE_C_ROLE_RUNTIME_BINDING_TEMPLATE.csv'),
    overlays: csv('PHASE_C_CATEGORY_OVERLAY_RUNTIME_BINDING_TEMPLATE.csv'),
    workflows: csv('PHASE_C_WORKFLOW_RUNTIME_BINDING_TEMPLATE.csv'),
    steps: csv('PHASE_C_STEP_RUNTIME_BINDING_TEMPLATE.csv'),
    handoffs: csv('PHASE_C_HANDOFF_RUNTIME_BINDING_TEMPLATE.csv'),
    events: csv('PHASE_C_EVENT_RUNTIME_BINDING_TEMPLATE.csv'),
    gates: csv('PHASE_C_GATE_ENFORCEMENT_BINDING_TEMPLATE.csv'),
    rules: csv('PHASE_C_RULE_ENFORCEMENT_BINDING_TEMPLATE.csv'),
    authority: csv('PHASE_C_AUTHORITY_AND_APPROVAL_MATRIX.csv'),
    intents: csv('PHASE_C_COMMAND_INTENT_REGISTRY.csv'),
    acceptance: csv('PHASE_C_COMMAND_ROUTING_ACCEPTANCE_CASES.csv'),
    commandStates: csv('PHASE_C_COMMAND_STATE_MODEL.csv'),
    commandTransitions: csv('PHASE_C_COMMAND_TRANSITIONS.csv'),
    taskStates: csv('PHASE_C_TASK_STATE_MODEL.csv'),
    taskTransitions: csv('PHASE_C_TASK_TRANSITIONS.csv'),
    systemActors: csv('PHASE_C_SYSTEM_ACTOR_REGISTRY.csv'),
    tracePolicies: csv('PHASE_C_TRACE_REQUIREMENT_POLICY.csv'),
    crosswalkTemplate: csv('PHASE_C_RUNTIME_COMPONENT_CROSSWALK_TEMPLATE.csv'),
    executorTemplate: csv('PHASE_C_EXECUTOR_ACCOUNTABILITY_TEMPLATE.csv'),
  };
}

/** The counts PHASE_C_QA_REPORT.json declares, keyed by loadPackage() field. */
export const DECLARED_COUNTS = {
  roles: 90,
  overlays: 86,
  workflows: 30,
  steps: 257,
  handoffs: 161,
  events: 347,
  gates: 32,
  rules: 54,
  authority: 26,
  intents: 35,
  acceptance: 20,
  commandStates: 13,
  commandTransitions: 24,
  taskStates: 11,
  taskTransitions: 22,
  systemActors: 10,
  tracePolicies: 11,
};

/** Header order for each Phase C deliverable CSV, taken from the package templates. */
export const DELIVERABLE_HEADERS = {
  crosswalk: null,   // filled from the template at run time
  executor: null,
};
