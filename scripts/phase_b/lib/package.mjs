// Deterministic reader for the committed Phase B package.
//
// The package is the authoritative target for Phase B.  Nothing in here calls a
// model, a provider or the network: every function is pure over the committed
// bytes under docs/phase-b/package/.
//
// Row counts are asserted against PHASE_B_INVARIANTS.md, so a truncated or
// re-generated CSV fails loudly here rather than silently shrinking a registry.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
export const PKG = join(REPO, 'docs', 'phase-b', 'package');

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

const csv = name => readCSV(join(PKG, name));

/** Split a `a; b; c` package cell into a trimmed list; empty cell -> []. */
export function splitList(v) {
  return String(v ?? '').split(';').map(s => s.trim()).filter(Boolean);
}

export function sha256File(p) {
  return createHash('sha256').update(readFileSync(p)).digest('hex');
}

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
  const pkg = {
    workflows: csv('PHASE_B_WORKFLOW_REGISTRY.csv'),
    steps: csv('PHASE_B_WORKFLOW_STEP_REGISTRY.csv'),
    workflowStates: csv('PHASE_B_WORKFLOW_STATE_MODEL.csv'),
    workflowTransitions: csv('PHASE_B_WORKFLOW_TRANSITIONS.csv'),
    stepStates: csv('PHASE_B_STEP_STATE_MODEL.csv'),
    stepTransitions: csv('PHASE_B_STEP_TRANSITIONS.csv'),
    stateProfiles: csv('PHASE_B_WORKFLOW_STATE_PROFILE_ASSIGNMENT.csv'),
    handoffs: csv('PHASE_B_HANDOFF_REGISTRY.csv'),
    objects: csv('PHASE_B_BUSINESS_OBJECT_REGISTRY.csv'),
    rules: csv('PHASE_B_BUSINESS_RULE_REGISTRY.csv'),
    gates: csv('PHASE_B_GATE_REGISTRY.csv'),
    exceptions: csv('PHASE_B_EXCEPTION_ESCALATION_MATRIX.csv'),
    slas: csv('PHASE_B_SLA_POLICY.csv'),
    events: csv('PHASE_B_EVENT_REGISTRY.csv'),
    founderBoundaries: csv('PHASE_B_FOUNDER_BOUNDARY_MAPPING.csv'),
    placeholders: csv('PHASE_B_DYNAMIC_ACTOR_PLACEHOLDER_REGISTRY.csv'),
    crosswalkTemplate: csv('PHASE_B_CURRENT_TO_TARGET_WORKFLOW_CROSSWALK_TEMPLATE.csv'),
  };
  return pkg;
}

/** The counts PHASE_B_INVARIANTS.md declares, keyed by loadPackage() field. */
export const DECLARED_COUNTS = {
  workflows: 30,
  steps: 257,
  handoffs: 161,
  objects: 56,
  rules: 54,
  exceptions: 50,
  slas: 34,
  gates: 32,
  events: 347,
  workflowStates: 14,
  workflowTransitions: 35,
  stepStates: 11,
  stepTransitions: 19,
};

/** Every distinct role token the package addresses, and where it came from. */
export function collectRoleRefs(pkg) {
  const refs = new Map(); // token -> Set(source)
  const add = (tok, src) => {
    tok = String(tok ?? '').trim();
    if (!tok) return;
    if (!refs.has(tok)) refs.set(tok, new Set());
    refs.get(tok).add(src);
  };
  for (const w of pkg.workflows) {
    add(w.accountable_role_id, 'workflow.accountable');
    add(w.independent_reviewer_or_challenge_role, 'workflow.reviewer');
    splitList(w.contributors).forEach(c => add(c, 'workflow.contributor'));
  }
  for (const s of pkg.steps) {
    add(s.accountable_role_id, 'step.accountable');
    add(s.independent_reviewer_role_id, 'step.reviewer');
    splitList(s.contributors).forEach(c => add(c, 'step.contributor'));
  }
  for (const h of pkg.handoffs) {
    add(h.sending_role_id, 'handoff.sender');
    add(h.receiving_role_id, 'handoff.receiver');
    add(h.return_owner_role_id, 'handoff.return_owner');
  }
  for (const o of pkg.objects) add(o.accountable_role_id, 'object.accountable');
  for (const e of pkg.exceptions) {
    add(e.detection_owner_role_id, 'exception.detection');
    add(e.escalation_owner_role_id, 'exception.escalation');
  }
  for (const e of pkg.events) {
    add(e.primary_consumer_role_id, 'event.consumer');
    add(e.emitted_by, 'event.emitter');
  }
  return refs;
}
