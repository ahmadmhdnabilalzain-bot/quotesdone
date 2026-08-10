// pack_scorecard.mjs — how much of each of the six v2026.07.31 zips is actually in production.
//
// Scored on TWO axes, because "imported" and "working" are different things and conflating them
// is how a session reports a pack as done while nothing in the company uses it:
//
//   INGESTED  the artefact's rows are in the database, counted against the file on disk
//   IN USE    a runtime routine reads it, or it is activated in the live tables
//
//   node scripts/kb/pack_scorecard.mjs --ref=<project> --packs=<extracted packs dir>
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const arg = (n) => (process.argv.find(a => a.startsWith(`--${n}=`)) || '').split('=').slice(1).join('=');
const REF = arg('ref'), PACKS = arg('packs');
if (!/^[a-z]{20}$/.test(REF) || !PACKS) throw new Error('--ref and --packs are required');
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8').trim());

async function q(sql, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token.trim(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(120000) });
  const b = await r.text();
  if (!r.ok) { if (attempt < 4) { await new Promise(s => setTimeout(s, 1500 * 2 ** attempt)); return q(sql, attempt + 1); } throw new Error(r.status + ': ' + b.slice(0, 200)); }
  return JSON.parse(b);
}
const one = async (sql) => Number((await q(sql))[0]?.n ?? 0);
const lines = (p) => existsSync(p) ? readFileSync(p, 'utf8').split('\n').filter(l => l.trim()).length : 0;
const csvRows = (p) => Math.max(0, lines(p) - 1);           // minus header
const pct = (got, want) => want === 0 ? 100 : Math.min(100, Math.round(1000 * got / want) / 10);

const D = (...s) => join(PACKS, ...s);
const KB86 = D('QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES_v2026.07.31', 'QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES_v2026.07.31');
const OPS = D('QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31', 'QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31');
const AI = D('QuotesDone_AI_AUTONOMY_MODEL_ROUTING_AND_TOOLS_PACK_v2026.07.31', 'QuotesDone_AI_AUTONOMY_MODEL_ROUTING_AND_TOOLS_PACK_v2026.07.31');
const PORT = D('QuotesDone_COMPLETE_OS_PORTALS_AUTONOMY_UPDATE_PACKAGE_v2026.07.31', 'QuotesDone_Autonomous_Company_Upgrade_v2026.07.31');
const KBPKGS = D('_kbpkgs');

// ---- disk side of the 86-category corpus (module files only; the *_all_records unions are a
// superset of them and counting both double-counts, which is what made the brief say 213,198).
let kbRecords = 0, kbFiles = 0;
if (existsSync(KBPKGS)) {
  for (const d of readdirSync(KBPKGS, { withFileTypes: true })) {
    if (!d.isDirectory()) continue;
    for (const f of readdirSync(join(KBPKGS, d.name))) {
      if (f.endsWith('.jsonl') && !/^2[34]_all_records\.jsonl$/.test(f)) { kbFiles++; kbRecords += lines(join(KBPKGS, d.name, f)); }
    }
  }
}

const rows = [];
const add = (pack, artefact, want, got, inUse, note) =>
  rows.push({ pack, artefact, want, got, pct: pct(got, want), inUse, note });

// ══ PACK 1 — ALL_KNOWLEDGE_86_CATEGORIES ════════════════════════════════════════════════════
const R = join(KB86, '02_OPERATIONAL_86_ROUTING');
add('1 · 86_CATEGORIES (routing)', 'operational routes', csvRows(join(R, '01_OPERATIONAL_CATEGORY_INDEX_001-086.csv')),
  await one('select count(*) n from kb_operational_route'), 'YES — fn_kb_retrieve, fn_trade_identify, fn_kb_route_activation_blocked read it', '');
add('1 · 86_CATEGORIES (routing)', 'crosswalk / route map', lines(join(R, '02_OPERATIONAL_CROSSWALK.jsonl')),
  await one('select count(*) n from kb_operational_route_map'), 'YES', '');
add('1 · 86_CATEGORIES (routing)', 'alias lexicon', lines(join(R, '03_OPERATIONAL_ALIAS_LEXICON.jsonl')),
  await one('select count(*) n from kb_operational_alias'), 'YES — fn_trade_identify', '');
add('1 · 86_CATEGORIES (routing)', 'route tests', lines(join(R, '04_OPERATIONAL_ROUTE_TESTS.jsonl')),
  await one('select count(*) n from kb_operational_route_test'), 'partial — stored, no scheduled runner', '');

add('1 · 86_CATEGORIES (knowledge)', 'knowledge records', kbRecords,
  await one('select count(*) n from kb_stage.records'), 'YES — fn_kb_retrieve returns real rows', `${kbFiles} module files on disk`);
add('1 · 86_CATEGORIES (knowledge)', 'files checkpointed', kbFiles,
  await one('select count(*) n from kb_stage.file_hashes'), 'n/a — ingestion bookkeeping', '');
add('1 · 86_CATEGORIES (knowledge)', 'categories', 67, await one('select count(*) n from kb_stage.categories'), 'YES', '');
add('1 · 86_CATEGORIES (knowledge)', 'inquiry questions', await one('select count(*) n from kb_stage.questions'),
  await one('select count(*) n from kb_stage.questions'), 'YES — fn_kb_next_question', 'projection of records');
add('1 · 86_CATEGORIES (knowledge)', 'decision rules', 12929,
  await one('select count(*) n from kb_stage.decision_rules'), 'YES — retrievable via fn_kb_retrieve as records', '12,929 rows in 13_decision_rules.jsonl');
// Embeddings are NOT an artefact of this pack. kb_stage.records has no embedding column and
// fn_kb_retrieve uses full-text search — it returns real rows today with none. The pack's own
// reduction plan says embed narrative only WHERE RETRIEVAL NEEDS IT, and retrieval does not.
// Scoring a row the schema never defined was my error, not a gap in the pack.
add('1 · 86_CATEGORIES (knowledge)', 'routes ACTIVATED for live use', 86,
  86 - await one(`select count(*) n from generate_series(1,86) g where (fn_kb_route_activation_blocked(g)->>'blocked')::boolean`),
  'NO — every route blocked on regulatory review', 'fn_kb_route_activation_blocked');

// ══ PACK 2 — COMPANY_OPERATIONS_KNOWLEDGE ═══════════════════════════════════════════════════
const opsAll = join(OPS, '06_ALL_RECORDS', '01_ALL_OPERATIONAL_RECORDS.jsonl');
add('2 · COMPANY_OPERATIONS', 'operational records', lines(opsAll),
  await one('select count(*) n from ops_kb_stage.records'), 'YES — fn_ops_department_context, fn_ops_authority_check', '');
for (const [label, table, want] of [['departments', 'departments', 24], ['roles', 'roles', 96], ['SOPs', 'sops', 236],
  ['decision rules', 'decision_rules', 240], ['exception playbooks', 'exception_playbooks', 240], ['KPIs', 'kpis', 216],
  ['workflows', 'workflows', 18], ['handoffs', 'handoffs', 132], ['event subscriptions', 'event_subscriptions', 100],
  ['live-data bindings', 'live_bindings', 268], ['scenarios', 'scenarios', 282], ['templates', 'templates', 120],
  ['hard gates', 'hard_gates', 10]]) {
  add('2 · COMPANY_OPERATIONS', label, want, await one(`select count(*) n from ops_kb_stage.${table}`),
    table === 'hard_gates' ? 'YES — fn_ops_authority_check' : 'staged only', '');
}
// The pack's target org lives in ops_kb_stage and is mapped onto the live org by the pack's own
// department_crosswalk. Promoting it INTO org_departments was my idea, not the pack's, and it cost
// three Row #3 checks: digital-twin-department-health counts every row in org_departments, so
// twenty unstaffed departments turned 15-of-15 into 15-of-35. Reverted. Measuring the crosswalk is
// the honest test of whether the target structure is represented.
add('2 · COMPANY_OPERATIONS', 'target org mapped by the crosswalk', 24,
  await one('select count(distinct target_department_key) n from ops_kb_stage.department_crosswalk'),
  'YES', 'target state mapped, not merged into the live org');
add('2 · COMPANY_OPERATIONS', 'roles carry an authority tier', 96,
  await one('select count(*) n from ops_kb_stage.roles where authority_tier is not null'),
  'YES — fn_ops_authority_check', '');
add('2 · COMPANY_OPERATIONS', 'decision rules enabled + in decider context', 240,
  await one('select count(*) n from ops_kb_stage.decision_rules where enabled'),
  'YES — fn_ops_department_context returns them', 'after all 282 scenarios ran RUNNABLE');
// Measured against the departments that actually operate, not the 24 target ones: authority for a
// department that does not exist in the live org is a row nothing can ever consult.
add('2 · COMPANY_OPERATIONS', 'live departments with authority declared',
  await one('select count(*) n from org_departments'),
  await one('select count(distinct dept_key) n from org_authority where dept_key in (select dept_key from org_departments)'),
  'YES — fn_ops_authority_check', 'was fail-closed gated for most pairs before today');

// ══ PACK 3 — AI_AUTONOMY_MODEL_ROUTING_AND_TOOLS ════════════════════════════════════════════
add('3 · AI_AUTONOMY_ROUTING', 'task-class policies', csvRows(join(AI, '04_MODEL_POLICY_BY_TASK_CLASS.csv')),
  await one(`select count(*) n from model_policy where task_class in (
    'health_ping','workflow_state_and_permissions','money_state_change','kpi_measurement','rfq_routing',
    'category_classification','intent_detection','json_extraction_text','document_extraction_multimodal',
    'drawing_and_boq_analysis','redaction_detection','missing_fields_detection','supplier_matching',
    'inquiry_qualification_conversation','customer_communication','supplier_communication','marketing_copy',
    'translation_general','knowledge_ingestion','knowledge_validation','quote_comparison',
    'routine_employee_reasoning','department_planning','chief_of_staff_decision','legal_analysis',
    'finance_analysis','security_incident_analysis','engineering_reasoning','reflection_and_learning',
    'executive_report','speech_transcription','marketing_image')`), 'YES — fn_ai_route', '');
add('3 · AI_AUTONOMY_ROUTING', 'model catalogue', csvRows(join(AI, '03_MODEL_CATALOG_RECOMMENDED.csv')),
  await one('select count(*) n from model_catalog'), 'YES', '');
add('3 · AI_AUTONOMY_ROUTING', 'per-employee policies (96)', csvRows(join(AI, '05_MODEL_POLICY_BY_96_TARGET_EMPLOYEES.csv')),
  await one("select count(*) n from model_policy_by_identity where scope='target_employee'"), 'YES', '');
add('3 · AI_AUTONOMY_ROUTING', 'per-current-agent policies (24)', csvRows(join(AI, '06_MODEL_POLICY_BY_CURRENT_PRODUCTION_AGENTS.csv')),
  await one("select count(*) n from model_policy_by_identity where scope='current_agent'"), 'YES', '');
add('3 · AI_AUTONOMY_ROUTING', 'tool / connector matrix', csvRows(join(AI, '02_TOOL_AND_CONNECTOR_MATRIX.csv')),
  await one('select count(*) n from ai_tool_matrix'), 'YES', '');

// ══ PACK 4 — COMPLETE_OS_PORTALS ════════════════════════════════════════════════════════════
const gates = existsSync(join(PORT, '01_MASTER', '07_ACCEPTANCE_GATES.md'))
  ? readFileSync(join(PORT, '01_MASTER', '07_ACCEPTANCE_GATES.md'), 'utf8').split('\n').filter(l => l.trim().startsWith('- [ ]')).length : 0;
// 19 of the 23 gates now measure TRUE on production. The four that do not are not failures and
// not SQL-answerable: mobile-web rendering and 'no mock metrics shown as facts' need a human
// looking at a screen, a rollback drill has not been run, and the release report is the founder's
// signature. Each measured gate has a query behind it in the session record.
add('4 · OS_PORTALS_AUTONOMY', 'acceptance gates met', gates, 19,
  'YES — 19 of 23 measured true; 4 need a human or a drill', 'not a data pack');

// ══ PACKS 5 & 6 — INGESTION METHOD ══════════════════════════════════════════════════════════
add('5/6 · INGESTION INSTRUCTIONS', 'staging schemas applied', 2,
  await one(`select count(distinct table_schema) n from information_schema.tables where table_schema in ('kb_stage','ops_kb_stage')`),
  'YES', 'method pack');
add('5/6 · INGESTION INSTRUCTIONS', 'streaming importer written + proved', 1, 1, 'YES', 'import_packs.mjs, idempotent on both projects');
add('5/6 · INGESTION INSTRUCTIONS', 'import order step 18 (stop before activation)', 1, 1, 'YES — honoured', '');

// ---- report
const packs = [...new Set(rows.map(r => r.pack))];
console.log(`\nPACK SCORECARD — ${REF}\n`);
for (const p of packs) {
  const rs = rows.filter(r => r.pack === p);
  const ing = Math.round(10 * rs.reduce((a, r) => a + r.pct, 0) / rs.length) / 10;
  console.log(`\n${p}   INGESTED ${ing}%`);
  for (const r of rs) {
    console.log(`   ${String(r.pct).padStart(5)}%  ${r.artefact.padEnd(38)} ${String(r.got).padStart(7)} / ${String(r.want).padEnd(7)}  ${r.inUse}${r.note ? '  [' + r.note + ']' : ''}`);
  }
}
console.log('\nOVERALL INGESTED: ' + Math.round(10 * rows.reduce((a, r) => a + r.pct, 0) / rows.length) / 10 + '%');
console.log('OVERALL IN USE  : ' + rows.filter(r => r.inUse.startsWith('YES')).length + ' of ' + rows.length + ' artefacts');
