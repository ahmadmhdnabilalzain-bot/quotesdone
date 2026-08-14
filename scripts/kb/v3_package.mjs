// Parser for the QuotesDone Agent Knowledge V2 + V3 delivery.
// Walks an extracted package tree and yields canonical knowledge records.
// Pure reader: no DB, no network. Used by v3_inventory.mjs and v3_import.mjs.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export const CERT_FILE_RE = /CERTIFICATION_CASES|CERTIFICATION_QUESTIONS|ANSWER_KEY|evaluation_cases\.jsonl$/i;

export function sha256(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

export function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.isFile()) out.push(p);
  }
  return out;
}

// Minimal YAML reader: the package uses a flat/nested subset (block maps, block
// sequences, scalars, folded continuation lines). We do not need full YAML —
// we need the scalar identity fields plus the whole document as text.
export function yamlScalars(text) {
  const out = {};
  const lines = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const m = /^([a-zA-Z_][a-zA-Z0-9_]*):\s*(.*)$/.exec(lines[i]);
    if (!m) continue;
    let v = m[2].trim();
    if (v === '' || v === '|' || v === '>') continue;      // block or nested
    v = v.replace(/^['"]|['"]$/g, '');
    out[m[1]] = v;
  }
  return out;
}

export function readJsonl(file) {
  const txt = fs.readFileSync(file, 'utf8');
  const recs = [];
  const bad = [];
  let n = 0;
  for (const line of txt.split(/\r?\n/)) {
    n++;
    const s = line.trim();
    if (!s) continue;                                       // blank lines are not records
    try { recs.push(JSON.parse(s)); }
    catch (e) { bad.push({ line: n, reason: String(e.message).slice(0, 120) }); }
  }
  return { recs, bad };
}

const SEG = (p) => p.split(/[\\/]/);

// Identify the logical position of a file inside either delivery.
export function classify(absPath, rootDir) {
  const rel = path.relative(rootDir, absPath).replace(/\\/g, '/');
  const segs = SEG(rel);
  const base = segs[segs.length - 1];

  // package = first path segment (the archive folder name)
  const pkg = segs[0] || 'unknown';
  const generation = /_V3_UPGRADE_/.test(rel) ? 'V3' : 'V2';

  let scope_type = null, scope_key = null;
  const iRoles = segs.indexOf('roles');
  const iDepts = segs.indexOf('departments');
  const iCats = segs.indexOf('category_specialists');
  const iCore = segs.indexOf('company_core');

  const iDeptsUpper = segs.indexOf('01_DEPARTMENTS');
  if (iRoles >= 0 && segs[iRoles + 1]) { scope_type = 'role'; scope_key = segs[iRoles + 1]; }
  else if (iDepts >= 0 && segs[iDepts + 1]) { scope_type = 'department'; scope_key = segs[iDepts + 1]; }
  else if (iDeptsUpper >= 0 && segs[iDeptsUpper + 1]) {
    // baseline corpus numbers its department folders: 01_executive_office
    scope_type = 'department'; scope_key = segs[iDeptsUpper + 1].replace(/^\d{2}_/, '');
  }
  else if (iCats >= 0) {
    // .../category_specialists/routes/001_slug/... (V2) or .../category_specialists/001_slug/... (V3).
    // Only NNN_slug directories are categories; `source_corpus` and `routes` are containers.
    const after = segs.slice(iCats + 1).filter((s) => s !== 'routes');
    if (after[0] && /^\d{3}_/.test(after[0])) { scope_type = 'category'; scope_key = after[0]; }
    else { scope_type = 'company'; scope_key = 'category_corpus'; }
  } else if (iCore >= 0) { scope_type = 'company'; scope_key = 'company_core'; }

  if (!scope_type) {
    // master-core / package-level docs
    scope_type = 'company';
    scope_key = 'package_core';
  }

  const isCert = CERT_FILE_RE.test(base);
  return { rel, pkg, generation, scope_type, scope_key, base, isCert };
}

// Map a filename to a knowledge layer + record type.
const LAYER_BY_FILE = [
  [/company_objective|company_core|COMPANY/i, 'company_core'],
  [/competency_map|COMPETENCY_GRAPH/i, 'role_specific'],
  [/decision_playbooks|DECISION_CATALOG|EXPERT_DECISION_CHECKLIST|02_DECISION_PLAYBOOKS/i, 'decision_playbook'],
  [/escalation_matrix|ESCALATION/i, 'authority'],
  [/department_decision_rights|decision_rights/i, 'authority'],
  [/tools_and_permissions|TOOLS_DATA_AND_EVIDENCE/i, 'authority'],
  [/kpi_causal_model|department_kpis|KPI_CAUSAL/i, 'kpi'],
  [/failure_modes|FAILURE_DIAGNOSTIC|FAILURE_MODES/i, 'failure_mode'],
  [/FAILURE_TO_REMEDIATION|remediation/i, 'remediation'],
  [/RECERTIFICATION_AND_DRIFT|readiness|CERTIFICATION_TIERS|SCORING/i, 'policy'],
  [/learning_policy|memory_policy|organizational_learning/i, 'policy'],
  [/sources_and_refresh_policy|SOURCE_REGISTRY|FRESHNESS/i, 'source_reference'],
  [/output_contracts|EVIDENCE_AND_OUTPUT_CONTRACT|quote_comparison_contract/i, 'policy'],
  [/retrieval_policy/i, 'policy'],
  [/rfq_quality_gate|qualification_playbook|FIELD_AND_QUESTION_BANK|QUOTE_READINESS|MINIMUM_SUFFICIENT/i, 'category_specialist'],
  [/casebook|TRAINING_CASES|TRAINING_V3|MANAGEMENT_AND_SYSTEM_CASES|ROUTE_CASEBOOK/i, 'case_training'],
  [/CURRICULUM|role_charter|senior_judgment|EXPERTISE|department_operating_model|SPECIALIST_EXPERTISE/i, 'role_specific'],
  [/manifest|MANIFEST/i, 'source_reference'],
];

export function layerFor(base, scope_type) {
  for (const [re, layer] of LAYER_BY_FILE) if (re.test(base)) {
    if (layer === 'role_specific' && scope_type === 'department') return 'department_shared';
    if (layer === 'role_specific' && scope_type === 'category') return 'category_specialist';
    if (layer === 'role_specific' && scope_type === 'company') return 'company_core';
    return layer;
  }
  return scope_type === 'company' ? 'company_core'
    : scope_type === 'department' ? 'department_shared'
    : scope_type === 'category' ? 'category_specialist'
    : 'role_specific';
}

export const OPS_RECORD_FILE = /^(01_KNOWLEDGE_RECORDS|11_ASSIGNED_COMPANY_OPERATIONS_RECORDS_V2|\d+_COMPANY_RECORDS)\.jsonl$/i;

// The ops corpus records carry their own module/record_type; map those onto the
// V3 layer vocabulary instead of calling every jsonl line a training case.
const OPS_MODULE_LAYER = {
  decision_rules: 'decision_playbook', kpi: 'kpi', governance: 'authority',
  controls: 'authority', source_registry: 'source_reference', principles: 'company_core',
  exception_handling: 'failure_mode', evidence: 'source_reference', memory: 'policy',
  ai_governance: 'policy', data_governance: 'policy', privacy: 'policy', audit: 'policy',
  incident_management: 'failure_mode',
};
export function opsLayer(r) {
  const byModule = OPS_MODULE_LAYER[r.module];
  if (byModule) return byModule;
  if (r.scope_type === 'company') return 'company_core';
  if (r.scope_type === 'agent') return 'role_specific';
  return 'department_shared';
}

const DETERMINISTIC = new Set([
  'authority', 'kpi', 'policy', 'remediation', 'failure_mode', 'source_reference',
]);

// Produce canonical records from one package root.
// Each record: { stable_id, package, package_version, generation, scope_type, scope_key,
//                layer, record_type, title, content, structured_data, source_path,
//                checksum, deterministic, runtime_eligible, is_certification }
export function* records(rootDir, packageVersion = '2026.08.14') {
  const files = walk(rootDir);
  for (const f of files) {
    const c = classify(f, rootDir);
    const ext = path.extname(c.base).toLowerCase();
    if (!['.md', '.yaml', '.yml', '.json', '.jsonl', '.csv'].includes(ext)) continue;
    const layer = layerFor(c.base, c.scope_type);
    const buf = fs.readFileSync(f);
    const fileSum = sha256(buf);

    if (ext === '.jsonl') {
      const { recs, bad } = readJsonl(f);
      for (const r of recs) {
        const id = stableIdOf(r);
        if (!id) { yield { __reject: true, source_path: c.rel, reason: 'jsonl record has no stable id field' }; continue; }
        // The company-operations corpus ships as jsonl too, but those lines are
        // knowledge records with their own scope/module/record_type — not cases.
        const opsNative = OPS_RECORD_FILE.test(c.base) && r.record_type && r.scope_type;
        const rt = opsNative ? String(r.record_type) : caseType(c.base, r, c.scope_type);
        // A jsonl case file is training material regardless of the words in its
        // filename — "…AND_ESCALATION_TRAINING…" is not an authority document.
        const jsonlLayer = c.isCert ? 'certification'
          : opsNative ? opsLayer(r)
          : rt === 'failure_mode_case' ? 'failure_mode'
          : 'case_training';
        yield {
          stable_id: String(id),
          package: c.pkg, package_version: packageVersion, generation: c.generation,
          scope_type: c.scope_type, scope_key: c.scope_key,
          layer: jsonlLayer,
          record_type: rt,
          title: r.title || r.case_family || r.scenario || r.case_type || String(id),
          content: JSON.stringify(r),
          structured_data: r,
          source_path: c.rel, checksum: sha256(Buffer.from(JSON.stringify(r))),
          deterministic: opsNative && DETERMINISTIC.has(opsLayer(r)),
          runtime_eligible: !c.isCert,
          is_certification: c.isCert,
          ops_native: !!opsNative,
        };
      }
      for (const b of bad) yield { __reject: true, source_path: c.rel, reason: `unparseable jsonl line ${b.line}: ${b.reason}` };
      continue;
    }

    // Whole-document records (md / yaml / json / csv)
    const text = buf.toString('utf8');
    let structured = null;
    if (ext === '.json') { try { structured = JSON.parse(text); } catch (e) { yield { __reject: true, source_path: c.rel, reason: 'unparseable json: ' + e.message }; continue; } }
    else if (ext === '.yaml' || ext === '.yml') structured = yamlScalars(text);

    // A whole-document record is identified by where it sits: the same base name
    // (PACKAGE_MANIFEST_V3.json, 00_DEPARTMENT_MASTER.md) recurs at several depths
    // and in every stage archive, so the full relative path is the stable id.
    const stable = `${c.generation}:doc:${c.rel}`;
    yield {
      stable_id: stable,
      package: c.pkg, package_version: packageVersion, generation: c.generation,
      scope_type: c.scope_type, scope_key: c.scope_key,
      layer: c.isCert ? 'certification' : layer,
      record_type: ext.slice(1),
      title: (structured && (structured.title || structured.role_title || structured.name)) || c.base,
      content: text,
      structured_data: structured,
      source_path: c.rel, checksum: fileSum,
      deterministic: DETERMINISTIC.has(layer) && ext !== '.md',
      runtime_eligible: !c.isCert,
      is_certification: c.isCert,
    };
  }
}

// Stable id: the packaged records use several `*_id` key names (case_id,
// evaluation_id, question_id…). Take the declared one; never synthesise from a
// line number, because a re-ordered file would then produce different keys.
const ID_KEYS = ['case_id', 'evaluation_id', 'question_id', 'record_id', 'training_id', 'scenario_id', 'id'];
export function stableIdOf(r) {
  if (!r || typeof r !== 'object') return null;
  for (const k of ID_KEYS) if (r[k]) return r[k];
  const k = Object.keys(r).find((x) => /_id$/.test(x) && r[x]);
  return k ? r[k] : null;
}

function caseType(base, r, scope_type) {
  if (/CERTIFICATION_CASES|CERTIFICATION_QUESTIONS|ANSWER_KEY/i.test(base)) return 'certification_case';
  // Category overlays reuse the words ADVERSARIAL/UNCERTAINTY in their filenames;
  // the scope decides which counted family a case belongs to, not the word.
  if (scope_type === 'category') return /evaluation_cases/i.test(base) ? 'evaluation_case' : 'category_case';
  if (/ADVERSARIAL/i.test(base)) return 'role_adversarial';
  if (/TOOL_USE/i.test(base)) return 'role_tool';
  if (/UNCERTAINTY/i.test(base)) return 'role_uncertainty';
  if (/CROSS_DEPARTMENT/i.test(base)) return 'role_cross_department';
  if (/MANAGEMENT_AND_SYSTEM/i.test(base)) return 'department_management';
  if (/failure_modes/i.test(base)) return 'failure_mode_case';
  if (/evaluation_cases/i.test(base)) return 'evaluation_case';
  if (/casebook|CASEBOOK/i.test(base)) return 'case';
  return r && r.case_type ? String(r.case_type) : 'case';
}
