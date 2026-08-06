// IS ANYTHING STILL STAGING-ONLY? — the founder's rule of 6 Aug 2026: "nothing is for staging.
// all for deploy."
//
// verify_phase1 counts tables, views, routines and columns, and a count is exactly the wrong
// instrument here: a routine present on both projects with a DIFFERENT BODY passes every count in
// the repo. So does a view whose definition drifted, a config table whose rows disagree, and an
// Edge Function deployed to staging and forgotten. This compares CONTENT.
//
// Differences that are CORRECT and are reported separately rather than as drift:
//   - a routine whose only difference is the project ref: staging routines must call staging.
//     Isolation is asserted by verify_phase1 and is the opposite of a defect.
//   - cron jobs: staging runs 0 on purpose.
//   - business and telemetry data: leads, agent_runs, ai_cost_log and friends.
//
//   node scripts/verify_prod_parity.mjs
import { mgmtRead, PROD_REF } from './staging/qd_guard.mjs';
import { REF } from './staging/demo_factory.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(46)} ${detail}`);
};
const STAGE_REF = REF;
const bothRefs = new RegExp(`${STAGE_REF}|${PROD_REF}`, 'g');

// ---- routines: compare BEHAVIOUR, not prose ----------------------------------------------------
// Three normalisations, and the third is the one that matters. Comparing raw prosrc reported eight
// routines as drifted; measured, `fn_intake_slug_for_catalog` differed by 894 characters of which
// 894 were a COMMENT — the executable SQL was byte-identical. A comment-blind diff turns "the two
// projects behave differently", which is an incident, into "one of them lost its documentation",
// which is a chore. Both are reported, separately, because they are not the same problem.
const NORM = (col) => `regexp_replace(regexp_replace(regexp_replace(${col},
  '(${STAGE_REF}|${PROD_REF})','__REF__','g'), '--[^\\n]*','','g'), '\\s+',' ','g')`;
const ROUTINES = `select p.oid::regprocedure::text sig,
    md5(p.prosrc) raw,
    md5(regexp_replace(p.prosrc,'(${STAGE_REF}|${PROD_REF})','__REF__','g')) norm,
    md5(${NORM('p.prosrc')}) code
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' order by 1`;
const [sr, pr] = await Promise.all([mgmtRead(STAGE_REF, ROUTINES), mgmtRead(PROD_REF, ROUTINES)]);
const S = new Map(sr.map((r) => [r.sig, r]));
const P = new Map(pr.map((r) => [r.sig, r]));

const onlyStaging = [...S.keys()].filter((k) => !P.has(k));
const onlyProd = [...P.keys()].filter((k) => !S.has(k));
const differ = [...S.keys()].filter((k) => P.has(k) && S.get(k).code !== P.get(k).code);
const commentOnly = [...S.keys()].filter((k) => P.has(k) && S.get(k).norm !== P.get(k).norm && S.get(k).code === P.get(k).code);
const refOnly = [...S.keys()].filter((k) => P.has(k) && S.get(k).raw !== P.get(k).raw && S.get(k).norm === P.get(k).norm);

step('every routine exists on production', onlyStaging.length === 0,
  onlyStaging.length ? `STAGING-ONLY: ${onlyStaging.join(', ')}` : `${S.size} routines, none staging-only`);
step('no routine is production-only', onlyProd.length === 0,
  onlyProd.length ? `PRODUCTION-ONLY: ${onlyProd.join(', ')}` : `${P.size} routines`);
step('routine BEHAVIOUR matches', differ.length === 0,
  differ.length ? `DIFFER: ${differ.slice(0, 12).join(', ')}${differ.length > 12 ? ` +${differ.length - 12}` : ''}` : `${S.size} routines, executable SQL identical`);
step('routine documentation matches', commentOnly.length === 0,
  commentOnly.length ? `comments only, production has lost the reasoning: ${commentOnly.join(', ')}` : 'comments identical too');
console.log(`     note: ${refOnly.length} routine(s) differ ONLY by project ref — correct, staging must call staging`);

// Views get the same treatment for the same reason.

// ---- views -------------------------------------------------------------------------------------
// `AS text` is stripped as well: pg_get_viewdef renders a UNION branch's column alias on one
// project and omits it on the other for the SAME view. v_supplier_coi, v_audit_coverage and
// v_department_health all "differed" by exactly that and are identical definitions.
const VIEWS = `select viewname, md5(regexp_replace(${NORM('definition')}, ' AS text,', ',', 'g')) h
  from pg_views where schemaname='public' order by 1`;
const [sv, pv] = await Promise.all([mgmtRead(STAGE_REF, VIEWS), mgmtRead(PROD_REF, VIEWS)]);
const SV = new Map(sv.map((r) => [r.viewname, r.h]));
const PV = new Map(pv.map((r) => [r.viewname, r.h]));
const vDiff = [...SV.keys()].filter((k) => !PV.has(k) || PV.get(k) !== SV.get(k));
const vOnlyProd = [...PV.keys()].filter((k) => !SV.has(k));
step('view definitions match', vDiff.length === 0 && vOnlyProd.length === 0,
  vDiff.length || vOnlyProd.length ? `differ/missing: ${[...vDiff, ...vOnlyProd].slice(0, 10).join(', ')}` : `${SV.size} views identical`);

// ---- columns -----------------------------------------------------------------------------------
const COLS = `select md5(string_agg(table_name||'.'||column_name||':'||data_type, E'\\n' order by table_name, column_name)) h,
                     count(*)::int n from information_schema.columns where table_schema='public'`;
const [sc, pc] = await Promise.all([mgmtRead(STAGE_REF, COLS), mgmtRead(PROD_REF, COLS)]);
step('every column matches by name and type', sc[0].h === pc[0].h,
  `staging ${sc[0].n}, production ${pc[0].n}`);

// ---- configuration and reference tables: compare CONTENT ---------------------------------------
// Deliberately excludes business and telemetry tables, which differ by design.
// Hash the WHOLE ROW via to_jsonb rather than a named key column. The first cut named a key per
// table and three of them were wrong (model_registry, catalog_domains, knowledge_module_standard
// have no such column), so the check reported UNREADABLE — a gate that cannot read a table says
// nothing about it, which is worse than a red.
const CONFIG = ['model_policy', 'fn_task_class', 'model_rate', 'model_registry', 'decision_policy',
  'policy_rules', 'edge_expectation', 'org_departments', 'org_agents', 'org_authority',
  'org_action_executor', 'catalog_supplier_categories', 'catalog_domains', 'catalog_category_domain',
  'lead_trade_map', 'knowledge_module_standard', 'os_knowledge_domain', 'operating_system',
  'company_goals', 'employee_kpi'];
const behind = [], ahead = [];
for (const t of CONFIG) {
  const sql = `select count(*)::int n, md5(string_agg(md5(to_jsonb(x)::text), E'\\n' order by md5(to_jsonb(x)::text))) h from public.${t} x`;
  try {
    const [a, b] = await Promise.all([mgmtRead(STAGE_REF, sql), mgmtRead(PROD_REF, sql)]);
    if (a[0].h === b[0].h) continue;
    // Direction is the whole point of this run. Staging AHEAD is undelivered work; staging BEHIND
    // is a rehearsal surface that has not been refreshed, which breaks no promise to anybody.
    (a[0].n > b[0].n ? ahead : behind).push(`${t} (staging ${a[0].n} / production ${b[0].n})`);
  } catch (e) { ahead.push(`${t} UNREADABLE: ${String(e.message || e).slice(0, 60)}`); }
}
step('nothing configuration-shaped is staging-only', ahead.length === 0,
  ahead.length ? `STAGING AHEAD: ${ahead.join(' · ')}` : `${CONFIG.length} tables, staging never ahead`);
console.log(`     note: ${behind.length} table(s) where staging is BEHIND — not undelivered work: ${behind.join(' · ') || 'none'}`);

// ---- the knowledge estate: content, not counts --------------------------------------------------
const KNOW = [
  ['agent_knowledge', `md5(string_agg(agent_key||'|'||coalesce(topic,'')||'|'||md5(coalesce(content,'')), E'\\n' order by id))`],
  ['dept_library', `md5(string_agg(department||'|'||coalesce(title,'')||'|'||md5(coalesce(content,'')), E'\\n' order by id))`],
  ['kb_chunks', `md5(string_agg(id::text||'|'||coalesce(category,'')||'|'||md5(coalesce(content,'')), E'\\n' order by id))`],
  ['ops_knowledge', `md5(string_agg(record_id||'|'||coalesce(dept_key,'')||'|'||md5(content), E'\\n' order by record_id))`],
  ['kb_operational_alias', `md5(string_agg(catalog_num::text||'|'||language||'|'||alias, E'\\n' order by catalog_num, language, alias))`],
];
const kDiff = [];
for (const [t, expr] of KNOW) {
  const sql = `select count(*)::int n, ${expr} h from public.${t}`;
  const [a, b] = await Promise.all([mgmtRead(STAGE_REF, sql), mgmtRead(PROD_REF, sql)]);
  if (a[0].h !== b[0].h) kDiff.push(`${t} (staging ${a[0].n} vs production ${b[0].n})`);
}
step('the knowledge estate is row-for-row identical', kDiff.length === 0,
  kDiff.length ? kDiff.join(' · ') : `${KNOW.length} corpora identical by content hash`);

const bad = checks.filter((c) => !c.ok).length;
console.log(`\nPROD PARITY ${checks.length - bad}/${checks.length} — staging ${STAGE_REF} vs production ${PROD_REF}`);
if (bad) process.exitCode = 1;
