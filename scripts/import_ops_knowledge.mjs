// THE FOUNDER SHIPPED 3,959 OPERATIONAL RECORDS AND NEITHER PROJECT HAD A TABLE FOR THEM.
//
// `QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31` sits in C:\Users\Opera\qd-packs\ and is a
// SEPARATE corpus from the 86-category supplier knowledge that sessions 10-11 imported — its own
// START_HERE.md says so in its second line. It carries 24 target departments and, measured:
//
//   240 exception_playbook      <- spec file #7's Exception Handling, rated three stars
//   240 decision_rule           <- the Decision Engine
//   268 live_data_binding       <- Layer 3
//   236 standard_operating_procedure · 216 metric_definition · 192 department_scenario
//    96 agent_role · 132 workflow_handoff · 100 event_subscription · 120 operational_template
//    18 cross_department_workflow · 20 operating_principle · 10 hard_gate · 8 audit_requirement
//     6 memory_policy · 5 model_routing_policy · 5 data_classification · 4 incident_priority
//
// The FIRST HR exception playbook is titled "External AI provider unavailable" — the literal first
// scenario the blueprint asks for. This is not content that needs writing; it is content that was
// written, delivered, and never imported.
//
// WHY NOT dept_library. It would have been free — dept_library gained a reader earlier today, so an
// import there would have been instantly reachable. But dept_library has 7 columns and these
// records have 19, and the pack's own instruction 5 is "Preserve every record's
// implementation_status, validation_status, authority tier, sources and review date." Those are not
// decoration: authority_tier is advisory/supervised/gated/autonomous (2,633 supervised, 139 gated)
// and implementation_status is the founder's own audit of his own spec — 1,325 implemented, 1,317
// partial, 1,317 target_state. Flattening that into a title and a body would discard the single
// most useful thing in the corpus.
//
// THE DEPARTMENT MAPPING IS THE PACK'S OWN, NOT MINE. A seventh vocabulary was exactly the trap to
// expect here (the brief lists six for the taxonomy alone), and I was about to invent a crosswalk
// when START_HERE.md pointed at one the founder had already written:
// 04_AGENT_RUNTIME_AND_GOVERNANCE/07_PRODUCTION_TO_TARGET_DEPARTMENT_CROSSWALK.csv. It is
// transcribed below verbatim, inverted from production->target into target->production, with its
// mapping_type preserved so a `split` is visibly different from a `direct`.
//
// TWO MEASURED CORRECTIONS TO IT, and they are corrections to the FOUNDER'S file, so they are
// stated rather than silently applied. The crosswalk lists `hr_people` and `sales_crm` among
// "unmapped_target ... no one-to-one production department is confirmed" and folds sales under
// marketing. Measured 6 Aug 2026, org_departments carries an ACTIVE `hr` (4 agents, lead
// hr_director) and an ACTIVE `sales` (5 agents, lead sales_director). The pack is dated 31 July;
// both departments were added after it was built. Mapping them to their obvious counterparts is
// the correction; leaving them unmapped would strand 284 records against departments that exist.
//
//   node scripts/import_ops_knowledge.mjs pglpqrhvozwepymcuunn            # load staging
//   node scripts/import_ops_knowledge.mjs pglpqrhvozwepymcuunn --dry-run  # map and report only
//
// The pack's instruction 4 says "Import into staging only." That instruction predates production
// becoming a deploy target on 5 Aug, so it is surfaced rather than obeyed blindly — but this script
// refuses production through qd_guard like every other writer in the repo, so loading production is
// a deliberate act somebody has to take, not a default.
import { createReadStream, existsSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { mgmtRead, mgmtWrite, resolveStagingRef } from './lib/qd_guard.mjs';

const PACK = 'C:/Users/Opera/qd-packs/QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31/QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31';
const RECORDS = `${PACK}/06_ALL_RECORDS/01_ALL_OPERATIONAL_RECORDS.jsonl`;

// target department (pack scope_key) -> production org_departments.dept_key
// Inverted from the pack's own crosswalk. `null` means the pack itself records no production
// department; those records still import, with dept_key NULL, and are counted in the report.
export const DEPT_MAP = {
  executive_office: 'exec',                 // direct
  engineering: 'it',                        // split from production `it`
  it_cybersecurity: 'it',                   // split from production `it`
  ai_model_ops: 'it',                       // org_departments.it charter: "Also formally owns AI Mod[el Ops]"
  rfq_intelligence: 'procurement',          // split — marketplace core spans intake/match/quote
  marketplace_operations: 'procurement',    // split
  document_intelligence: 'procurement',     // split
  supplier_success: 'supplier_success',     // direct (note: that org department is INACTIVE today)
  trust_safety: 'supplier_success',         // direct_plus_shared — trust controls stay cross-functional
  customer_success: 'customer_success',     // direct
  payments_revenue: 'finance',              // the crosswalk shares it between customer_success and
                                            // finance; finance is chosen because its own note is
                                            // "Payment operations must reconcile into finance"
  marketing: 'marketing',                   // direct
  sales_crm: 'sales',                       // CORRECTION: crosswalk folds this under marketing and
                                            // says no separate org department is confirmed. One is:
                                            // `sales`, 5 agents, lead sales_director, active.
  finance: 'finance',                       // direct
  legal_compliance: 'legal',                // direct
  hr_people: 'hr',                          // CORRECTION: listed as unmapped_target; `hr` is active
                                            // with 4 agents and lead hr_director.
  data_analytics: 'intelligence',           // crosswalk maps both `analytics` and `intelligence`
                                            // here; `intelligence` is the active one.
  strategy_evolution: 'evolution',          // direct
  knowledge_learning: 'knowledge_eng',      // Knowledge Engineering owns retrieval and embeddings
  supplier_knowledge: 'knowledge',          // production `knowledge` (name: Operations) — the
                                            // crosswalk splits the legacy knowledge function into
                                            // domain knowledge and corporate learning
  admin_operations: 'knowledge',            // production `knowledge` charter is "Process, quality,
                                            // project coordination and document control"
  qa_testing: null,                         // unmapped_target in the crosswalk, and still no
  business_development: null,               // production department exists for any of these three.
  communications: null,                     // Imported with dept_key NULL and reported as such.
};

const REF = resolveStagingRef(process.argv[2]);
const DRY = process.argv.includes('--dry-run');
if (!existsSync(RECORDS)) { console.log(`pack not found at ${RECORDS}`); process.exit(1); }

const q = (v) => (v === null || v === undefined || v === '') ? 'null' : `'${String(v).replace(/'/g, "''")}'`;
const arr = (a) => (Array.isArray(a) && a.length) ? `ARRAY[${a.map(q).join(',')}]::text[]` : `'{}'::text[]`;
const jb = (o) => `'${JSON.stringify(o ?? {}).replace(/'/g, "''")}'::jsonb`;
const dt = (s) => (typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s)) ? `'${s}'::date` : 'null';

const rows = [];
const byScope = new Map(), byType = new Map(), unmapped = new Map();
const bump = (m, k) => m.set(k, (m.get(k) || 0) + 1);

const rl = createInterface({ input: createReadStream(RECORDS, 'utf8'), crlfDelay: Infinity });
for await (const line of rl) {
  if (!line.trim()) continue;
  const r = JSON.parse(line);
  // A department-scoped record names its department in scope_key. An `agent` or `workflow` record
  // names it in structured_data.department_key instead — 96 of 96 agent records and 100 of 340
  // workflow records carry one. Resolving only scope_key left 884 of 3,959 records reachable by
  // nothing, which is this project's signature defect reproduced inside its own fix.
  const packKey = r.scope_type === 'department'
    ? r.scope_key
    : (r.structured_data && r.structured_data.department_key) || null;
  const dept = packKey ? (DEPT_MAP[packKey] ?? null) : null;
  if (packKey && dept === null) bump(unmapped, packKey);
  bump(byScope, r.scope_type);
  bump(byType, r.record_type);
  rows.push(`(${[
    q(r.record_id), q(r.scope_type), q(r.scope_key), q(dept), q(r.module), q(r.record_type),
    q(r.title), q(r.content), jb(r.structured_data), arr(r.source_ids),
    q(r.implementation_status), q(r.validation_status), q(r.authority_tier), q(r.risk_level),
    q(r.version), dt(r.effective_date), dt(r.review_after), arr(r.keywords),
    arr(r.dependencies), jb(r.escalation_rule),
  ].join(',')})`);
}

console.log(`parsed ${rows.length} record(s) from the pack`);
console.log(`scope_type: ${[...byScope].map(([k, v]) => `${k} ${v}`).join(' · ')}`);
console.log(`department records with no production department: ${[...unmapped].map(([k, v]) => `${k} ${v}`).join(' · ') || '(none)'}`);
if (DRY) { console.log('--dry-run: nothing written'); process.exit(0); }

const COLS = `record_id,scope_type,scope_key,dept_key,module,record_type,title,content,structured_data,
  source_ids,implementation_status,validation_status,authority_tier,risk_level,version,
  effective_date,review_after,keywords,dependencies,escalation_rule`;

// Batched, and `on conflict (record_id) do update` so a re-run is a refresh rather than a
// duplicate — the pack ships a stable record_id and 0 of 3,959 collide.
const BATCH = 250;
let done = 0;
for (let i = 0; i < rows.length; i += BATCH) {
  const chunk = rows.slice(i, i + BATCH);
  await mgmtWrite(REF, `insert into public.ops_knowledge (${COLS}) values\n${chunk.join(',\n')}
    on conflict (record_id) do update set
      dept_key=excluded.dept_key, title=excluded.title, content=excluded.content,
      structured_data=excluded.structured_data, implementation_status=excluded.implementation_status,
      validation_status=excluded.validation_status, authority_tier=excluded.authority_tier,
      risk_level=excluded.risk_level, review_after=excluded.review_after;`, 'ops_knowledge import');
  done += chunk.length;
  if (done % 1000 === 0 || done === rows.length) console.log(`  ${done}/${rows.length}`);
}

const m = (await mgmtRead(REF, `select
  (select count(*)::int from public.ops_knowledge) total,
  (select count(*)::int from public.ops_knowledge where dept_key is not null) mapped,
  (select count(distinct dept_key)::int from public.ops_knowledge where dept_key is not null) depts,
  (select count(*)::int from public.ops_knowledge where record_type='exception_playbook') playbooks,
  (select count(*)::int from public.ops_knowledge where record_type='decision_rule') rules,
  (select count(*)::int from public.ops_knowledge where implementation_status='implemented') implemented`))[0];

console.log(`\nops_knowledge on ${REF}: ${m.total} rows, ${m.mapped} mapped to ${m.depts} production department(s)`);
console.log(`  ${m.playbooks} exception playbooks · ${m.rules} decision rules · ${m.implemented} marked implemented by the founder`);

// The department that had NOTHING is the measurement that matters: hr, intelligence and
// knowledge_eng each held 0 agent_knowledge and 0 dept_library rows before this.
const cover = await mgmtRead(REF, `select d.dept_key,
    (select count(*) from public.ops_knowledge o where o.dept_key=d.dept_key) ops,
    (select count(*) from public.dept_library l where l.department=d.dept_key) lib
  from public.org_departments d where d.active order by 2, 1`);
console.log('\nper active department  ops_knowledge / dept_library');
for (const c of cover) console.log(`  ${String(c.dept_key).padEnd(18)} ${String(c.ops).padStart(4)} / ${c.lib}`);
const empty = cover.filter((c) => Number(c.ops) === 0 && Number(c.lib) === 0).map((c) => c.dept_key);
console.log(empty.length ? `\nSTILL EMPTY: ${empty.join(', ')}` : '\nevery active department now has knowledge');
