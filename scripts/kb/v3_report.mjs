// Generates the V3 implementation evidence documents from live measurement.
// Every number in docs/knowledge/*.md comes from here, so a stale report is a re-run away.
//
//   node scripts/kb/v3_report.mjs
import fs from 'node:fs';
import path from 'node:path';
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';

// staging (pglpqrhvozwepymcuunn) was a second target until its Supabase project was deleted on
// 15 Aug 2026; the same six measurements now run against production alone.
const REFS = { production: PROD_REF };

const STATS = `select
  (select count(*) from ops_knowledge) ops_total,
  (select count(*) from ops_knowledge where generation is not null) ops_from_package,
  (select count(*) from ops_knowledge where generation='V3') ops_v3,
  (select count(*) from ops_knowledge where generation='V2') ops_v2,
  (select count(*) from ops_knowledge where runtime_eligible and supersession_state='current') ops_retrievable,
  (select count(*) from ops_knowledge where deterministic) ops_deterministic,
  (select count(distinct layer) from ops_knowledge where layer is not null) ops_layers,
  (select count(distinct role_key) from ops_knowledge where role_key is not null) roles_with_knowledge,
  (select count(distinct category_key) from ops_knowledge where category_key is not null) cats_with_knowledge,
  (select count(*) from agent_training_case) training_total,
  (select count(*) from agent_training_case where generation='V3') training_v3,
  (select count(*) from agent_training_case where generation='V2') training_v2,
  (select count(*) from org_role_identity) identity_rows,
  (select count(distinct packaged_role_id) from org_role_identity) packaged_roles,
  (select count(distinct agent_key) from org_role_identity) agents_with_identity,
  (select count(*) from org_agents where active) agents_active,
  (select count(*) from org_department_alias) dept_alias,
  (select count(*) from org_category_identity) category_identity,
  (select count(*) from category_route_map) route_map,
  (select count(*) from knowledge_ingestion_run) runs,
  (select count(*) from ops_knowledge where layer='certification') cert_in_runtime,
  (select count(*) from cert.certification_question) cert_questions,
  (select count(*) from cert.certification_answer_key) cert_answers,
  (select count(*) from cert.certification_result) cert_results,
  (select count(*) from artifact_review) artifact_reviews,
  (select count(*) from agent_context_retrieval) retrievals,
  (select count(*) from decision_trace) traces`;

const LAYERS = `select layer, count(*) n, count(*) filter (where deterministic) det
  from ops_knowledge where layer is not null group by 1 order by 2 desc`;
const FAMILIES = `select generation, case_family, count(*) n from agent_training_case group by 1,2 order by 1,3 desc`;
const MAPPING = `select mapping_type, count(*) n, count(distinct packaged_role_id) roles
  from org_role_identity group by 1 order by 2 desc`;
const READINESS = `select readiness, count(*) n from org_role_identity group by 1 order by 2 desc`;
const RUNS = `select package_version, generation, status, counts->>'inserted' inserted,
  counts->>'updated' updated, counts->>'unchanged' unchanged, counts->>'rejected' rejected,
  counts->>'errors' errors, finished_at
  from knowledge_ingestion_run order by started_at`;

const out = {};
for (const [name, ref] of Object.entries(REFS)) {
  out[name] = {
    stats: (await mgmtRead(ref, STATS))[0],
    layers: await mgmtRead(ref, LAYERS),
    families: await mgmtRead(ref, FAMILIES),
    mapping: await mgmtRead(ref, MAPPING),
    readiness: await mgmtRead(ref, READINESS),
    runs: await mgmtRead(ref, RUNS),
  };
}

const dir = path.join(process.cwd(), 'docs', 'knowledge');
fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(path.join(dir, 'V3_MEASUREMENTS.json'), JSON.stringify(out, null, 2));
console.log(JSON.stringify({
  production: out.production.stats,
  mapping: out.production.mapping, readiness: out.production.readiness,
  layers: out.production.layers, families_v3: out.production.families.filter((f) => f.generation === 'V3'),
}, null, 2));
