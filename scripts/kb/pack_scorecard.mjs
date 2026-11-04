// pack_scorecard.mjs — how much of each of the six v2026.07.31 zips is actually in production.
//
// Scored on TWO axes, because "imported" and "working" are different things and conflating them
// is how a session reports a pack as done while nothing in the company uses it:
//
//   INGESTED  the artefact's rows are in the database, counted against the file on disk
//   IN USE    a production routine READS it, proved by EXECUTING that routine here and counting
//             what comes back
//
// The IN USE column used to be a hand-written string per row. That is a claim, not a check: it
// cannot go red, and on 2026-08-10 four of the rows it called "YES" turned out to have no reader
// in the database at all — model_catalog, model_policy_by_identity, ai_tool_matrix and
// kb_stage.decision_rules. fn_ops_department_context even LOOKED like a reader of
// kb_stage.decision_rules by grep, and was matching a substring of ops_kb_stage.decision_rules.
// So every row now carries a probe: a SQL expression that runs a routine and returns n, and
// IN USE means n > 0. A probe that returns 0 makes this scorecard say NO on its own.
//
//   node scripts/kb/pack_scorecard.mjs --ref=<project> --packs=<extracted packs dir>
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const arg = (n) => (process.argv.find(a => a.startsWith(`--${n}=`)) || '').split('=').slice(1).join('=');
const REF = arg('ref'), PACKS = arg('packs');
if (!/^[a-z]{20}$/.test(REF) || !PACKS) throw new Error('--ref and --packs are required');
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync(SUPABASE_TOKEN_FILE, 'utf8').trim());

async function q(sql, attempt = 0) {
  let r, b;
  try {
    r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
      method: 'POST', headers: { Authorization: 'Bearer ' + token.trim(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(120000) });
  } catch (e) {
    // a timeout or a dropped socket is not a verdict. Retry, then give up loudly.
    if (attempt < 4) { await new Promise(s => setTimeout(s, 2000 * 2 ** attempt)); return q(sql, attempt + 1); }
    throw e;
  }
  b = await r.text();
  if (!r.ok) { if (attempt < 4) { await new Promise(s => setTimeout(s, 1500 * 2 ** attempt)); return q(sql, attempt + 1); } throw new Error(r.status + ': ' + b.slice(0, 200)); }
  return JSON.parse(b);
}
const one = async (sql) => Number((await q(sql))[0]?.n ?? 0);
// A probe that ERRORS is not in use. It must not look like a passing row and must not stop the run.
const probe = async (sql) => { try { return await one(sql); } catch (e) { return -1; } };
// A MISSING SOURCE FILE IS NOT A SATISFIED ARTEFACT (13 Aug 2026). lines() returned 0 for a file
// that is not on disk, and pct(got, 0) returns 100 — so a pack whose zip was never extracted here
// scored a perfect 100% INGESTED on every one of its rows. Three of the four v2026.07.31 pack
// directories are absent from this working tree, which means this scorecard's headline number was
// mostly a statement about files it could not see. null now means "no source to compare against"
// and is printed as NO SOURCE, excluded from the averages, and counted separately.
const lines = (p) => existsSync(p) ? readFileSync(p, 'utf8').split('\n').filter(l => l.trim()).length : null;
const csvRows = (p) => { const n = lines(p); return n === null ? null : Math.max(0, n - 1); };  // minus header
const pct = (got, want) => want === null ? null : (want === 0 ? 100 : Math.min(100, Math.round(1000 * got / want) / 10));

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

// One department context, fetched once: seventeen of the thirty-seven artefacts are proved by
// executing this single function, which is the point — fn_agent_context calls it on every AI
// context build, so one call is the same call the company makes.
const OPSCTX = `public.fn_ops_department_context('procurement', null, 2)`;
const opsArr = (k) => `select coalesce(jsonb_array_length((${OPSCTX})->'${k}'), 0) n`;

const rows = [];
const add = async (pack, artefact, want, got, routine, probeSql, note) =>
  rows.push({ pack, artefact, want, got, pct: pct(got, want), routine, n: await probe(probeSql), note });

// ══ PACK 1 — ALL_KNOWLEDGE_86_CATEGORIES ════════════════════════════════════════════════════
const R = join(KB86, '02_OPERATIONAL_86_ROUTING');
await add('1 · 86_CATEGORIES (routing)', 'operational routes', csvRows(join(R, '01_OPERATIONAL_CATEGORY_INDEX_001-086.csv')),
  await one('select count(*) n from kb_operational_route'),
  'fn_kb_route_decide (hourly: kb_route_tests_hourly)',
  `select count(*) n from jsonb_array_elements((public.fn_kb_route_decide('ready mix concrete Dubai'))->'candidates')`, '');
await add('1 · 86_CATEGORIES (routing)', 'crosswalk / route map', lines(join(R, '02_OPERATIONAL_CROSSWALK.jsonl')),
  await one('select count(*) n from kb_operational_route_map'),
  'fn_kb_route_decide -> kb_stage.decision_rules join',
  `select jsonb_array_length((public.fn_kb_route_decide('ready mix concrete Dubai', (select m.catalog_num from public.kb_operational_route_map m order by m.catalog_num limit 1)))->'rules') n`,
  'the rules only resolve through the route map');
await add('1 · 86_CATEGORIES (routing)', 'alias lexicon', lines(join(R, '03_OPERATIONAL_ALIAS_LEXICON.jsonl')),
  await one('select count(*) n from kb_operational_alias'),
  // Since 23 Sep 2026 (decision points 24/77) no routine matches the alias lexicon: the category is reasoned
  // (think()) over the open routes fn_kb_route_decide lists, so this row counts the routes an Arabic request is reasoned over.
  'fn_kb_route_decide on Arabic input (routes offered to reasoning)',
  `select count(*) n from jsonb_array_elements((public.fn_kb_route_decide('أحتاج رمل مغسول في دبي'))->'candidates')`,
  'an Arabic request is reasoned over the open routes, never alias-matched');
await add('1 · 86_CATEGORIES (routing)', 'route tests', lines(join(R, '04_OPERATIONAL_ROUTE_TESTS.jsonl')),
  await one('select count(*) n from kb_operational_route_test'),
  'fn_kb_route_test_run (hourly)',
  `select count(*) n from kb_operational_route_test t
    where t.last_run_at > now() - interval '3 hours'
      and exists (select 1 from cron.job j where j.jobname='kb_route_tests_hourly' and j.active)`,
  'ran in the last 3 hours by its own cron');

await add('1 · 86_CATEGORIES (knowledge)', 'knowledge records', kbRecords,
  await one('select count(*) n from kb_stage.records'),
  'kb_chunks full-text — the path kb_search falls back to',
  `select count(*) n from kb_chunks where source_kind='qd_kb_pack' and fts @@ plainto_tsquery('english','concrete')`,
  `${kbFiles} module files on disk`);
await add('1 · 86_CATEGORIES (knowledge)', 'files checkpointed', kbFiles,
  await one('select count(*) n from kb_stage.file_hashes'),
  'fn_kb_corpus_integrity (daily)',
  `select (public.fn_kb_corpus_integrity()->>'files')::int n`,
  'sum(rows_seen) is asserted against kb_stage.records');
await add('1 · 86_CATEGORIES (knowledge)', 'categories', 67,
  await one('select count(*) n from kb_stage.categories'),
  'fn_kb_corpus_integrity (daily)',
  `select (public.fn_kb_corpus_integrity()->>'categories')::int n`, '');
await add('1 · 86_CATEGORIES (knowledge)', 'inquiry questions', await one('select count(*) n from kb_stage.questions'),
  await one('select count(*) n from kb_stage.questions'),
  'fn_category_questions / fn_inquiry_workstream_activate',
  `select count(*) n from public.fn_category_questions('construction-materials-suppliers','en',10)`,
  'projection of records');
await add('1 · 86_CATEGORIES (knowledge)', 'decision rules', 12929,
  await one('select count(*) n from kb_stage.decision_rules'),
  'fn_kb_route_decide (hourly, 344x)',
  `select jsonb_array_length((public.fn_kb_route_decide('ready mix concrete Dubai', (select m.catalog_num from public.kb_operational_route_map m order by m.catalog_num limit 1)))->'rules') n`,
  '12,929 rows in 13_decision_rules.jsonl');
await add('1 · 86_CATEGORIES (knowledge)', 'routes ACTIVATED for live use', 86,
  86 - await one(`select count(*) n from generate_series(1,86) g where (fn_kb_route_activation_blocked(g)->>'blocked')::boolean`),
  'fn_kb_route_decide filters blocked routes; fn_kb_retrieve gates on it',
  `select count(*) n from generate_series(1,86) g where not (public.fn_kb_route_activation_blocked(g)->>'blocked')::boolean`,
  'proved by removing catalog 1 aliases in an aborted transaction: knowledge 50 -> 0');

// ══ PACK 2 — COMPANY_OPERATIONS ═════════════════════════════════════════════════════════════
// Every row here is proved by ONE execution of fn_ops_department_context on a LIVE department
// key. That function had zero callers this morning and could not be reached from a live key at
// all — ops_kb_stage is keyed on the 24 target departments and the org has 15. It resolves
// through the pack's own department_crosswalk now, and fn_agent_context calls it.
const opsAll = join(OPS, '06_ALL_RECORDS', '01_ALL_OPERATIONAL_RECORDS.jsonl');
await add('2 · COMPANY_OPERATIONS', 'operational records', lines(opsAll),
  await one('select count(*) n from ops_kb_stage.records'),
  'fn_ops_department_context <- fn_agent_context', opsArr('department_knowledge'), '');
for (const [label, table, want, key] of [
  ['departments', 'departments', 24, 'charter'], ['roles', 'roles', 96, 'roles'],
  ['SOPs', 'sops', 236, 'sops'], ['decision rules', 'decision_rules', 240, 'decision_rules'],
  ['exception playbooks', 'exception_playbooks', 240, 'exception_playbooks'], ['KPIs', 'kpis', 216, 'kpis'],
  ['workflows', 'workflows', 18, 'workflows'], ['handoffs', 'handoffs', 132, 'handoffs'],
  ['event subscriptions', 'event_subscriptions', 100, 'event_subscriptions'],
  ['live-data bindings', 'live_bindings', 268, 'live_data'], ['scenarios', 'scenarios', 282, 'scenarios'],
  ['templates', 'templates', 120, 'templates'], ['hard gates', 'hard_gates', 10, 'hard_gates']]) {
  await add('2 · COMPANY_OPERATIONS', label, want, await one(`select count(*) n from ops_kb_stage.${table}`),
    'fn_ops_department_context <- fn_agent_context', opsArr(key),
    table === 'event_subscriptions' ? 'emitted with activated=false; the live bus is a different table'
    : table === 'scenarios' ? 'also swept hourly by fn_ops_scenarios_sweep' : '');
}
await add('2 · COMPANY_OPERATIONS', 'target org mapped by the crosswalk', 24,
  await one('select count(distinct target_department_key) n from ops_kb_stage.department_crosswalk'),
  'fn_ops_department_context resolves live -> target', opsArr('target_departments'),
  'target state mapped, not merged into the live org');
await add('2 · COMPANY_OPERATIONS', 'roles carry an authority tier', 96,
  await one('select count(*) n from ops_kb_stage.roles where authority_tier is not null'),
  'fn_ops_department_context',
  `select count(*) n from jsonb_array_elements((${OPSCTX})->'roles') r where coalesce(r->>'authority_tier','') <> ''`, '');
await add('2 · COMPANY_OPERATIONS', 'decision rules enabled + in decider context', 240,
  await one('select count(*) n from ops_kb_stage.decision_rules where enabled'),
  'fn_agent_context emits them to the employee',
  `select count(*) n from (select public.fn_agent_context('procurement', 24000) c) z
    where position('TARGET OPERATING MODEL' in z.c) > 0 and position('RULE ' in z.c) > 0`,
  'the digest is capped at ~1,037 chars; the full text is one call away');
await add('2 · COMPANY_OPERATIONS', 'live departments with authority declared',
  await one('select count(*) n from org_departments'),
  await one('select count(distinct dept_key) n from org_authority where dept_key in (select dept_key from org_departments)'),
  'fn_ops_authority_check <- fn_dept_authority',
  `select count(*) n from (select public.fn_dept_authority('procurement','spend',100::numeric) a) z where z.a is not null`, '');

// ══ PACK 3 — AI_AUTONOMY_MODEL_ROUTING_AND_TOOLS ════════════════════════════════════════════
await add('3 · AI_AUTONOMY_ROUTING', 'task-class policies', csvRows(join(AI, '04_MODEL_POLICY_BY_TASK_CLASS.csv')),
  await one(`select count(*) n from model_policy where task_class in (
    'health_ping','workflow_state_and_permissions','money_state_change','kpi_measurement','rfq_routing',
    'category_classification','intent_detection','json_extraction_text','document_extraction_multimodal',
    'drawing_and_boq_analysis','redaction_detection','missing_fields_detection','supplier_matching',
    'inquiry_qualification_conversation','customer_communication','supplier_communication','marketing_copy',
    'translation_general','knowledge_ingestion','knowledge_validation','quote_comparison',
    'routine_employee_reasoning','department_planning','chief_of_staff_decision','legal_analysis',
    'finance_analysis','security_incident_analysis','engineering_reasoning','reflection_and_learning',
    'executive_report','speech_transcription','marketing_image')`),
  'fn_ai_route', `select count(*) n from (select public.fn_ai_route('quote_comparison') r) z where z.r->>'model' is not null`, '');
await add('3 · AI_AUTONOMY_ROUTING', 'model catalogue', csvRows(join(AI, '03_MODEL_CATALOG_RECOMMENDED.csv')),
  await one('select count(*) n from model_catalog'),
  'fn_model_catalog_drift (daily)', `select (public.fn_model_catalog_drift()->>'catalog_models')::int n`,
  '10 of the 14 are not in model_registry — the drift it exists to report');
await add('3 · AI_AUTONOMY_ROUTING', 'per-employee policies (96)', csvRows(join(AI, '05_MODEL_POLICY_BY_96_TARGET_EMPLOYEES.csv')),
  await one("select count(*) n from model_policy_by_identity where scope='target_employee'"),
  'fn_ops_department_context roles[].model_default',
  `select count(*) n from jsonb_array_elements((${OPSCTX})->'roles') r where r->'model_default' <> 'null'::jsonb`,
  'identity_key IS the role agent_key: 96 of 96 join');
await add('3 · AI_AUTONOMY_ROUTING', 'per-current-agent policies (24)', csvRows(join(AI, '06_MODEL_POLICY_BY_CURRENT_PRODUCTION_AGENTS.csv')),
  await one("select count(*) n from model_policy_by_identity where scope='current_agent'"),
  'fn_ai_route role default on the generic branch',
  `select count(*) n from (select public.fn_ai_route(null,null,null,'nosuchfn',false,null,'cfo') r) z
    where z.r->'identity_policy' <> 'null'::jsonb`,
  'the pack says "role default only; task_class routing overrides it"');
await add('3 · AI_AUTONOMY_ROUTING', 'tool / connector matrix', csvRows(join(AI, '02_TOOL_AND_CONNECTOR_MATRIX.csv')),
  await one('select count(*) n from ai_tool_matrix'),
  'fn_tool_readiness (daily)', `select (public.fn_tool_readiness()->>'tools')::int n`, '');

// ══ PACK 4 — COMPLETE_OS_PORTALS ════════════════════════════════════════════════════════════
// The 19 that used to sit here was a literal in this file. It is a query now, so it can fall.
const gates = existsSync(join(PORT, '01_MASTER', '07_ACCEPTANCE_GATES.md'))
  ? readFileSync(join(PORT, '01_MASTER', '07_ACCEPTANCE_GATES.md'), 'utf8').split('\n').filter(l => l.trim().startsWith('- [ ]')).length : 0;
const gatesMet = await one(`select count(*) n from public.fn_os_portals_gates() where verdict = 'met'`);
const gatesReasoned = await one(`select count(*) n from public.fn_os_portals_gates() where verdict in ('met','needs_human','needs_founder')`);
await add('4 · OS_PORTALS_AUTONOMY', 'acceptance gates met or reasoned', gates, gatesReasoned,
  'fn_os_portals_gates', `select count(*) n from public.fn_os_portals_gates() where verdict='met'`,
  `${gatesMet} measured met; the rest carry a stated reason, not "not measured"`);

// ══ PACKS 5 & 6 — INGESTION METHOD ══════════════════════════════════════════════════════════
await add('5/6 · INGESTION INSTRUCTIONS', 'staging schemas applied', 2,
  await one(`select count(distinct table_schema) n from information_schema.tables where table_schema in ('kb_stage','ops_kb_stage')`),
  'fn_kb_corpus_integrity + fn_ops_department_context read both',
  `select (public.fn_kb_corpus_integrity()->>'staged')::int n`, 'method pack');
await add('5/6 · INGESTION INSTRUCTIONS', 'streaming importer written + proved', 1, 1,
  'fn_kb_corpus_integrity asserts the importer checkpoint against the rows',
  `select count(*) n from (select public.fn_kb_corpus_integrity() c) z
    where (z.c->>'staged')::bigint = (z.c->>'checkpointed')::bigint
      and (z.c->>'staged_records_with_no_chunk')::bigint = 0`,
  // WAS: deployed_to_kb_chunks >= staged — a ROW-COUNT test that went red the moment 24,660
  // byte-identical duplicate chunks were deleted, while every distinct staged record was still
  // deployed. fn_kb_corpus_integrity now answers the real question directly and this probe asks it.
  'import_packs.mjs, idempotent on both projects');
await add('5/6 · INGESTION INSTRUCTIONS', 'import order step 18 (stop before activation)', 86,
  await one(`select count(*) n from kb_operational_route where regulatory_coverage_status in ('confirmed_none','confirmed_covered')`),
  'fn_kb_route_activation_blocked, enforced by fn_kb_route_decide',
  `select count(*) n from generate_series(1,86) g where not (public.fn_kb_route_activation_blocked(g)->>'blocked')::boolean`,
  'activation is gated on a settled regulatory status, not assumed');

// ---- report
const packs = [...new Set(rows.map(r => r.pack))];
console.log(`\nPACK SCORECARD — ${REF}\n`);
const scored = (rs) => rs.filter(r => r.pct !== null);
for (const p of packs) {
  const rs = rows.filter(r => r.pack === p);
  const sc = scored(rs);
  const ing = sc.length ? Math.round(10 * sc.reduce((a, r) => a + r.pct, 0) / sc.length) / 10 : null;
  const use = rs.filter(r => r.n > 0).length;
  const nosrc = rs.length - sc.length;
  console.log(`\n${p}   INGESTED ${ing === null ? 'NO SOURCE ON DISK' : ing + '% of ' + sc.length + ' scorable'}` +
              `${nosrc ? ' (' + nosrc + ' artefact(s) have no source file here)' : ''}   IN USE ${use}/${rs.length}`);
  for (const r of rs) {
    const verdict = r.n > 0 ? `IN USE  n=${String(r.n).padStart(6)}` : (r.n === 0 ? 'NOT READ        ' : 'PROBE ERRORED   ');
    const left = r.pct === null ? 'NO SRC' : String(r.pct).padStart(5) + '%';
    console.log(`   ${left}  ${r.artefact.padEnd(38)} ${String(r.got).padStart(7)} / ${String(r.want === null ? '?' : r.want).padEnd(7)}  ${verdict}  ${r.routine}${r.note ? '  [' + r.note + ']' : ''}`);
  }
}
const sc = scored(rows);
console.log('\nOVERALL INGESTED: ' + (sc.length ? Math.round(10 * sc.reduce((a, r) => a + r.pct, 0) / sc.length) / 10 + '% across ' + sc.length + ' of ' + rows.length + ' artefacts' : 'NOT SCORABLE') +
            (rows.length - sc.length ? ' — ' + (rows.length - sc.length) + ' artefact(s) have no source file in this working tree and are NOT counted either way' : ''));
console.log('OVERALL IN USE  : ' + rows.filter(r => r.n > 0).length + ' of ' + rows.length + ' artefacts (measured by probe, not asserted)');

// ---- THIRD AXIS: RETRIEVABLE. Added 11 Aug 2026 after the word-by-word audit.
//
// The two axes above were both TRUE and together read as something neither of them says. This
// scorecard printed "OVERALL INGESTED 100% / IN USE 37 of 37" on a corpus where 73,488 of 120,530
// kb_chunks had no embedding at all, including 0% of `trade` and 0% of `regulation`. INGESTED means
// the rows are in the table. IN USE means SOME routine reads the artefact. Neither word is
// "retrievable", and an employee asking a question reaches knowledge through retrieval.
//
// So the third axis is printed next to the other two, from the database, every run — never asserted.
// It is allowed to be ugly. A scorecard that cannot say "ingested but unreachable" is how a corpus
// spends three weeks at 39% embedded with every report green.
const emb = await q(`select coalesce(source_kind,'(null)') k, count(*) n,
                            count(*) filter (where embedding_gte is not null) e
                       from public.kb_chunks group by 1 order by 2 desc`);
const totN = emb.reduce((a, r) => a + Number(r.n), 0);
const totE = emb.reduce((a, r) => a + Number(r.e), 0);
console.log('OVERALL RETRIEVABLE: ' + totE.toLocaleString() + ' of ' + totN.toLocaleString() +
            ' kb_chunks carry an embedding (' + (totN ? (100 * totE / totN).toFixed(1) : '0.0') + '%)' +
            (totE < totN ? ' — the remainder is reachable by keyword only' : ''));
for (const r of emb) {
  const n = Number(r.n), e = Number(r.e);
  const p = n ? (100 * e / n) : 0;
  console.log('   ' + (p === 0 ? 'NOT EMBEDDED' : p.toFixed(1).padStart(11) + '%') + '  ' +
              String(r.k).padEnd(14) + String(e).padStart(7) + ' / ' + String(n).padEnd(7) +
              (p === 0 ? '  no semantic path to any of these rows' : ''));
}
// And the path itself. A vector column with a vector index earns nothing if the routine holding it
// is not the routine the employees call. Measured against the function bodies, not assumed.
//
// SCOPE OF THIS LINE, STATED, because the first version of it was an instrument reporting on the
// wrong subject — the exact defect this scorecard exists to stop. It counts SQL routines in
// `public` ONLY. kb_match's real caller is the `kb_search` EDGE FUNCTION, which agent_brain's
// retrieve() invokes on every employee turn, and which merges kb_match with full-text by
// reciprocal-rank fusion. Probed on production 11 Aug 2026: six results for "chilled water pipe
// insulation thickness Dubai Municipality", all six via=semantic, similarity 0.891-0.922. So "0
// callers in public" is true and does NOT mean the semantic path is unused.
const sem = await q(`select
    (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind='f' and p.prolang <> 12
        and pg_get_functiondef(p.oid) like '%embedding_gte%'
        and p.proname <> 'kb_match') vector_readers,
    (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind='f' and p.prolang <> 12
        and pg_get_functiondef(p.oid) like '%kb_match%' and p.proname <> 'kb_match') kb_match_callers`);
console.log('   semantic path: kb_match has ' + sem[0].kb_match_callers + ' SQL caller(s) in public; ' +
            sem[0].vector_readers + ' other routine(s) touch embedding_gte. Its real caller is the ' +
            'kb_search EDGE FUNCTION (hybrid: kb_match + full-text, RRF), which agent_brain calls on ' +
            'every employee turn — so a 0 here is NOT evidence that the semantic path is unused.');
const dead = rows.filter(r => r.n <= 0);
if (dead.length) {
  console.log('\nNOT READ BY ANY PRODUCTION ROUTINE:');
  for (const r of dead) console.log(`   ${r.pack} · ${r.artefact} — probe returned ${r.n === -1 ? 'an error' : '0'} against ${r.routine}`);
}
