// LOAD QuotesDone IT Engineer Knowledge v1 INTO public.it_engineer_knowledge.
//
// Forked from load_accountant_knowledge_pack.mjs, which forked from the sales loader, which
// established the pattern this estate keeps: read the pack's OWN allowlist, validate at the door,
// name every refusal BEFORE any write, and never let an invalid record touch a row that is already
// correct.
//
// WHAT DIFFERS, AND WHY.
//
// 1. THE BANNED SHAPES ARE DIFFERENT, AND THERE ARE SIX. The accountant's rule is "no tax figure
//    you cannot source". The equivalent failure for a monitoring seat is worse, because it is
//    specific, confident and checkable: a fabricated CVE identifier, a claim that some version of
//    some component is vulnerable, an assertion about what patch level this estate is on, a CVSS
//    score, or a GitHub advisory id. This session cannot read a vulnerability feed, so every one of
//    those would be invented. They are scanned for and the run is refused on a hit.
//
//    The scan runs over EVERY record, not over a subset of epistemic statuses. There is no record
//    in this body that legitimately needs to assert a specific advisory, so there is no exemption
//    to argue about later. What IS allowed is the word "CVE" and the concept: a record explaining
//    how to determine whether a published advisory reaches this estate is exactly what the seat
//    needs. The identifier is banned; the noun is not.
//
// 2. THE COMPANY'S OWN LIVE POSTURE IS GENERATED, NOT AUTHORED. Five records are built at load
//    time from live rows -- the scheduler baseline, the SECURITY DEFINER surface, the RLS posture,
//    the knowledge-corpus inventory, and this seat's own model pair with its prices read out of
//    public.model_rate. This is the structural guarantee that the knowledge cannot drift from the
//    estate: there is no hand-typed count of cron jobs, definer routines or USD per million tokens
//    anywhere in the JSONL. Re-running the loader is what refreshes them.
//
// WHAT IS REFUSED AT THE DOOR: any runtime path that is not records/*.jsonl. The evaluation
// questions live in scripts/kb/it_engineer_knowledge_retrieval_eval.mjs, which is executable code
// rather than a data file and can therefore never be reached by a manifest edit. The estate has a
// documented defect where exam answers leaked into the corpus an agent retrieves and 557 rows had
// to be quarantined.
//
//   node scripts/kb/load_it_engineer_knowledge_pack.mjs [--root <dir>] [--apply]
//   node scripts/kb/load_it_engineer_knowledge_pack.mjs --selftest    # prove the guard bites

import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const at = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };
const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = at('--root') || join(HERE, 'it_engineer_knowledge');
const APPLY = process.argv.includes('--apply');
const SELFTEST = process.argv.includes('--selftest');

// THE SIX BANNED SHAPES live in their own side-effect-free module, imported by BOTH this loader
// and the eval. The eval must run the SAME array this loader enforces -- a copy would prove that a
// copy of the guard bites, which is a different claim and would drift the first time one side was
// edited. It cannot import them from HERE, because this file's top level connects to the database
// and runs a load, so borrowing a constant would run a load as a side effect.
import { BANNED_SHAPES, firstBanned } from './it_engineer_banned_shapes.mjs';
export { BANNED_SHAPES, firstBanned };

// --selftest proves the guard bites without touching the database or needing a corpus. Zero
// refusals over a clean corpus cannot distinguish a working guard from a dead one, so the guard is
// exercised against strings that carry each shape, and against clean strings that must survive.
if (SELFTEST) {
  const MUST_REJECT = [
    ['CVE identifier',        'This is fixed by the upstream patch for CVE-2026-31337 released last month.'],
    ['GHSA identifier',       'Advisory GHSA-abcd-1234-wxyz covers the deserialisation path in that library.'],
    ['CVSS score',            'The issue carries a CVSS base score of 9.8 and should be treated as critical.'],
    ['version then verb',     'Postgres 15.4 is vulnerable to the row-security bypass described below.'],
    ['verb then version',     'The runtime is unpatched below 1.42.3 and must be upgraded before launch.'],
    ['patch-level assertion', 'The database is currently running 15.6 so the fix is already present.'],
  ];
  const MUST_PASS = [
    'When an advisory is published for a component this estate uses, determine whether it reaches us by reading the version the platform itself reports, not by trusting a record.',
    'The CVE process exists so that a vulnerability has a stable name; this body holds no specific one, because it cannot verify one.',
    'Account for the fact that fn_kernel_cron_exec swallows failures, so cron.job_run_details.status always reads succeeded.',
    'A file whose declared type and magic bytes disagree is the signal; the file is quarantined and never opened to decide.',
  ];
  let bad = 0;
  console.log('--- SELFTEST: the six banned shapes ---');
  for (const [label, s] of MUST_REJECT) {
    const hit = firstBanned(s);
    console.log((hit ? 'REJECTED  ' : 'MISSED    ') + label.padEnd(24) + ' :: ' + (hit || '(nothing)'));
    if (!hit) bad++;
  }
  console.log('--- SELFTEST: clean strings must survive ---');
  for (const s of MUST_PASS) {
    const hit = firstBanned(s);
    console.log((hit ? 'FALSE POS ' : 'PASSED    ') + (hit || '(nothing)') + '  <- ' + s.slice(0, 70));
    if (hit) bad++;
  }
  console.log(bad === 0
    ? '\nSELFTEST OK: fires on all 6 banned shapes, quiet on all 4 clean strings'
    : '\nSELFTEST FAILED on ' + bad + ' case(s)');
  process.exit(bad === 0 ? 0 : 1);
}

const { sql } = await import('../lib/db.mjs');

const manifest = JSON.parse(readFileSync(join(ROOT, 'manifest.json'), 'utf8'));
const FILES = manifest.runtime_files;
if (!Array.isArray(FILES) || !FILES.length) { console.error('manifest.json has no runtime_files'); process.exit(2); }
console.log('runtime allowlist from the pack itself: ' + FILES.join(', '));

const PACK_ID = manifest.package_id || 'QD-IT-ENGINEER';
const PACK_VERSION = manifest.version || '1.0.0';
const UPDATED_AT = manifest.authored || new Date().toISOString().slice(0, 10);

const REQUIRED = ['record_id', 'record_type', 'domain', 'title', 'content', 'structured_data',
  'source_ids', 'epistemic_status', 'jurisdiction', 'tags'];

// The eight the table's CHECK admits. Validated HERE too, so a bad status is named by record_id in
// a refusal list rather than surfacing as a constraint violation on row 71 of a multi-row insert.
const EPISTEMIC = new Set(['method_engineering', 'diagnostic_lens', 'estate_architecture_measured',
  'failure_signature', 'security_posture_no_version_claim', 'resolve_from_live_system',
  'company_governance_ruling', 'company_record_generated']);

const bodyHash = (r) => createHash('sha256').update(String(r.title) + '\n' + String(r.content), 'utf8').digest('hex');

// ---------------------------------------------------------------------------------------------
// READ AND VALIDATE. Every refusal is collected BEFORE anything is written, and one fatal refusal
// aborts the whole run: a partially valid file must not partially overwrite a correct corpus.
// ---------------------------------------------------------------------------------------------
const rows = [], refused = [], seenId = new Map(), seenBody = new Map(), collisions = [];
for (const rel of FILES) {
  const norm = String(rel).replace(/\\/g, '/');
  if (!/^records\/[A-Za-z0-9_.-]+\.jsonl$/.test(norm)) {
    console.error('REFUSED RUNTIME FILE ' + rel + ' :: only records/*.jsonl may be ingested');
    process.exit(2);
  }
  const p = join(ROOT, norm);
  if (!existsSync(p)) { console.error('MISSING ' + p); process.exit(2); }
  let n = 0;
  for (const line of readFileSync(p, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    n++;
    let r;
    try { r = JSON.parse(line); } catch { refused.push([norm + ':' + n, 'unparseable JSON']); continue; }
    const id = r.record_id || (norm + ':' + n);

    const missing = REQUIRED.filter((k) => r[k] === undefined || r[k] === null);
    if (missing.length) { refused.push([id, 'missing required field(s): ' + missing.join(',')]); continue; }
    if (!EPISTEMIC.has(r.epistemic_status)) { refused.push([id, 'epistemic_status not in the eight the table admits: ' + r.epistemic_status]); continue; }
    if (r.authority_effect !== undefined && r.authority_effect !== 'none') { refused.push([id, 'authority_effect=' + r.authority_effect + ' (a record may describe authority, never carry it)']); continue; }
    if (!Array.isArray(r.source_ids) || r.source_ids.length < 1) { refused.push([id, 'source_ids must have at least one entry']); continue; }
    if (typeof r.structured_data !== 'object' || Array.isArray(r.structured_data)) { refused.push([id, 'structured_data is not an object']); continue; }
    if (typeof r.content !== 'string' || r.content.trim().length < 200) { refused.push([id, 'content is empty or under 200 chars']); continue; }
    if (!Array.isArray(r.tags) || !r.tags.length) { refused.push([id, 'tags must have at least one entry -- they carry weight B in the search vector']); continue; }

    // THE BANNED SHAPES, over title and content together. Every record, no exemption.
    const banned = firstBanned(r.title + '\n' + r.content);
    if (banned) { refused.push([id, 'contains ' + banned]); continue; }

    if (seenId.has(r.record_id)) { refused.push([id, 'duplicate record_id, first seen at line ' + seenId.get(r.record_id)]); continue; }
    seenId.set(r.record_id, n);

    const bs = bodyHash(r);
    if (seenBody.has(bs)) collisions.push([r.record_id, seenBody.get(bs), bs]);
    else seenBody.set(bs, r.record_id);

    r.__body_sha256 = bs;
    r.__origin = norm;
    rows.push(r);
  }
}
const authoredCount = rows.length;
console.log('read ' + authoredCount + ' authored record(s) from ' + FILES.length + ' allowlisted file(s)');

// ---------------------------------------------------------------------------------------------
// GENERATE THE ESTATE'S OWN LIVE POSTURE FROM LIVE ROWS. Nothing below is typed by hand anywhere:
// every count, every name and every price is read on this run.
// ---------------------------------------------------------------------------------------------
const gen = [];

// -- 1. THE SCHEDULER BASELINE. The single most misread thing about this estate: 216 cron jobs
// exist and almost none of them run. A seat that reads "216 jobs" and concludes the schedule is
// healthy has measured the wrong subject.
const cronTot = (await sql(`select count(*)::int total, count(*) filter (where active)::int active
                              from cron.job`))[0];
const cronActive = await sql(`select jobid, jobname, schedule from cron.job where active order by jobid`);
const cronRuns = (await sql(`select count(*)::int runs, max(start_time) last_run
                               from cron.job_run_details where start_time > now() - interval '7 days'`))[0];
gen.push({
  record_id: 'QD-ITE-LIVE-SCHEDULER',
  record_type: 'live_posture',
  domain: 'scheduling',
  title: 'The live scheduler baseline: how many cron jobs exist, how many are active, and how many actually ran',
  content: 'Measured on this load run against cron.job and cron.job_run_details. Jobs defined: ' + cronTot.total
    + '. Jobs with active = true: ' + cronTot.active + '. Job runs recorded in the last seven days: ' + cronRuns.runs
    + '; most recent run start_time: ' + (cronRuns.last_run ? String(cronRuns.last_run) : 'none recorded') + '. '
    + (cronTot.active ? 'The active jobs are: ' + cronActive.map((j) => j.jobid + ' ' + j.jobname + ' [' + j.schedule + ']').join('; ') + '. ' : '')
    + 'THREE THINGS FOLLOW AND THEY ARE THE WHOLE REASON THIS RECORD IS GENERATED RATHER THAN WRITTEN. '
    + 'First, the count of DEFINED jobs is not a measure of anything: a defined-and-inactive job is a job that does not run, and reading the larger number as health is an instrument measuring the wrong subject. '
    + 'Second, a run count of zero over a window does not distinguish a dead scheduler from a quiet one, so it must be read together with whether any job was due in that window. '
    + 'Third, this record states the numbers as they were on the load run and nothing more: to know the position NOW, run the same two queries. If the numbers here differ from what you just measured, the live measurement is right and this record is stale, and the fix is to re-run the loader.',
  structured_data: { jobs_defined: cronTot.total, jobs_active: cronTot.active,
                     runs_last_7_days: cronRuns.runs, last_run_start: cronRuns.last_run,
                     active_jobs: cronActive.map((j) => ({ jobid: j.jobid, jobname: j.jobname, schedule: j.schedule })),
                     source: 'cron.job and cron.job_run_details',
                     refresh: 'select count(*) total, count(*) filter (where active) active from cron.job' },
  source_ids: ['live:cron.job', 'live:cron.job_run_details'],
  epistemic_status: 'company_record_generated',
  jurisdiction: 'QuotesDone_estate',
  tags: ['cron', 'scheduler', 'pg_cron', 'jobs', 'baseline', 'monitoring', 'live posture', 'job_run_details'],
});

// -- 2. THE SECURITY DEFINER SURFACE. Every definer routine runs as its owner; one reachable by
// anon is a privilege escalation with a stable URL.
const definer = (await sql(`select count(*)::int total,
    count(*) filter (where has_function_privilege('anon', p.oid, 'execute'))::int anon_exec,
    count(*) filter (where has_function_privilege('authenticated', p.oid, 'execute'))::int authed_exec
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef`))[0];
const publicFns = (await sql(`select count(*)::int total from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public'`))[0];
gen.push({
  record_id: 'QD-ITE-LIVE-DEFINER-SURFACE',
  record_type: 'live_posture',
  domain: 'privilege',
  title: 'The SECURITY DEFINER surface: how many routines run as their owner and who can execute them',
  content: 'Measured on this load run against pg_proc. Routines in schema public: ' + publicFns.total
    + '. Of those, SECURITY DEFINER: ' + definer.total
    + '. Executable by role anon: ' + definer.anon_exec + '. Executable by role authenticated: ' + definer.authed_exec + '. '
    + 'A SECURITY DEFINER routine runs with the privileges of its owner rather than its caller, which is why it is the right tool for a controlled write and the wrong thing to leave reachable. '
    + 'A freshly CREATEd function is granted EXECUTE to PUBLIC by default, so a new definer routine is public until somebody revokes it in the same migration -- and `revoke ... from anon` is a SILENT NO-OP when the grant is actually held through PUBLIC, which is the trap that makes this count worth measuring rather than assuming. '
    + 'CREATE OR REPLACE preserves the existing ACL, so replacing a routine does not re-open it and does not need a second revoke. '
    + 'The estate keeps a CI check named anon_cannot_execute_security_definer for exactly this number; when the count above is non-zero, that check is the thing to run, and the finding is which routine, not how many.',
  structured_data: { public_routines: publicFns.total, security_definer: definer.total,
                     executable_by_anon: definer.anon_exec, executable_by_authenticated: definer.authed_exec,
                     source: 'pg_proc joined to pg_namespace',
                     related_check: 'scripts/checks/anon_cannot_execute_security_definer',
                     trap: 'revoke from anon is a silent no-op when the grant is held through PUBLIC' },
  source_ids: ['live:pg_proc'],
  epistemic_status: 'company_record_generated',
  jurisdiction: 'QuotesDone_estate',
  tags: ['security definer', 'privilege', 'anon', 'grants', 'execute', 'pg_proc', 'live posture', 'escalation'],
});

// -- 3. THE RLS POSTURE. RLS enabled with zero policies denies everyone but the owner and
// service_role. RLS disabled on a granted table is the open door.
const rls = (await sql(`select count(*)::int tables,
    count(*) filter (where c.relrowsecurity)::int rls_on,
    count(*) filter (where c.relrowsecurity and not exists (
      select 1 from pg_policy p where p.polrelid = c.oid))::int rls_on_no_policy
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'`))[0];
const anonGrants = (await sql(`select count(distinct table_name)::int t
  from information_schema.role_table_grants
  where table_schema = 'public' and grantee = 'anon'`))[0];
gen.push({
  record_id: 'QD-ITE-LIVE-RLS-POSTURE',
  record_type: 'live_posture',
  domain: 'data_access',
  title: 'The row-level-security posture: tables, RLS state, and how many are reachable by the anon role',
  content: 'Measured on this load run against pg_class, pg_policy and information_schema.role_table_grants. Ordinary tables in schema public: ' + rls.tables
    + '. With row level security enabled: ' + rls.rls_on
    + '. With RLS enabled and NO policy at all: ' + rls.rls_on_no_policy
    + '. Distinct tables carrying any grant to the anon role: ' + anonGrants.t + '. '
    + 'READ THOSE THREE NUMBERS TOGETHER OR THEY MISLEAD. RLS enabled with zero policies is not a gap: with no policy, RLS denies every role that is not the owner and not a superuser, and service_role bypasses RLS entirely, so that combination is the tightest posture a table can have and it is used deliberately on the knowledge bodies. '
    + 'RLS enabled WITH a permissive policy is where the real questions live, because the policy is the whole access control and it is easy to write one that is true for every row. '
    + 'RLS disabled on a table that carries a grant to anon is an open door with a public URL in front of it, and that is the combination worth alerting on. '
    + 'Belt and braces matters here: a revoke alone can be undone by a later blanket grant on all tables in schema public, which a migration writes without reading the file that revoked; RLS survives that, so tables holding anything sensitive carry both.',
  structured_data: { public_tables: rls.tables, rls_enabled: rls.rls_on,
                     rls_enabled_no_policy: rls.rls_on_no_policy, tables_granted_to_anon: anonGrants.t,
                     source: 'pg_class, pg_policy, information_schema.role_table_grants',
                     alert_on: 'rls disabled AND a grant to anon on the same table' },
  source_ids: ['live:pg_class', 'live:pg_policy', 'live:information_schema.role_table_grants'],
  epistemic_status: 'company_record_generated',
  jurisdiction: 'QuotesDone_estate',
  tags: ['RLS', 'row level security', 'policy', 'anon', 'grants', 'service_role', 'live posture', 'data access'],
});

// -- 4. THE KNOWLEDGE THE SEAT CAN ACTUALLY REACH. Prevents the seat believing it holds knowledge
// it does not, and records that this body extends rather than replaces the existing one.
const opsSec = (await sql(`select count(*)::int n, count(embedding_gte)::int emb,
    count(*) filter (where runtime_eligible)::int rt,
    count(*) filter (where coalesce(supersession_state,'current') = 'current')::int cur
  from public.ops_knowledge where layer = 'it_security_deep'`))[0];
const opsMods = await sql(`select module, count(*)::int n from public.ops_knowledge
                            where layer = 'it_security_deep' group by 1 order by 2 desc, 1`);
const opsAll = (await sql(`select count(*)::int n, count(embedding_gte)::int emb from public.ops_knowledge`))[0];
gen.push({
  record_id: 'QD-ITE-LIVE-CORPUS-INVENTORY',
  record_type: 'live_posture',
  domain: 'knowledge',
  title: 'What this seat can actually retrieve: the two corpora, their sizes and how much of each is embedded',
  content: 'Measured on this load run. fn_it_engineer_assist reads TWO corpora and nothing else. '
    + 'public.it_engineer_knowledge is this seat\'s own body: the diagnostic method, the lenses, the measured architecture and the failure signatures. '
    + 'public.ops_knowledge holds ' + opsAll.n + ' rows of which ' + opsAll.emb + ' are embedded, and inside it the layer it_security_deep holds ' + opsSec.n
    + ' rows (' + opsSec.emb + ' embedded, ' + opsSec.rt + ' runtime-eligible, ' + opsSec.cur + ' current) across these modules: '
    + opsMods.map((m) => m.module + ' ' + m.n).join(', ') + '. '
    + 'THIS BODY EXTENDS THAT LAYER AND SUPERSEDES NONE OF IT. Not one it_security_deep row was rewritten or retired when this pack was built. The division is deliberate: that layer holds the security half -- the OWASP LLM top ten against this codebase, the auth and identity model, the RLS and grant surface, the edge-function attack surface, compliance mapping, threat modelling -- and this body holds the diagnostic half, which is how a fault in this system presents and which instrument to read first. A question that lands in the other half is answered from the other corpus, and the retrieval already searches both, so the seat does not have to know which half it needs before it asks. '
    + 'If a question is answered by NEITHER, the honest response is a refusal: the retrieval returns answered:false with a reason rather than the nearest neighbour, because a nearest neighbour is always found and during an incident it will be acted on.',
  structured_data: { ops_knowledge_rows: opsAll.n, ops_knowledge_embedded: opsAll.emb,
                     it_security_deep_rows: opsSec.n, it_security_deep_embedded: opsSec.emb,
                     it_security_deep_runtime_eligible: opsSec.rt, it_security_deep_current: opsSec.cur,
                     it_security_deep_modules: opsMods.reduce((a, m) => (a[m.module] = m.n, a), {}),
                     relationship: 'extends, supersedes nothing',
                     retrieval: 'public.fn_it_engineer_assist', source: 'public.ops_knowledge' },
  source_ids: ['live:public.ops_knowledge'],
  epistemic_status: 'company_record_generated',
  jurisdiction: 'QuotesDone_estate',
  tags: ['knowledge', 'corpus', 'ops_knowledge', 'it_security_deep', 'retrieval', 'embedding', 'live posture', 'refusal'],
});

// -- 5. THIS SEAT'S OWN MODEL PAIR, WITH THE PRICES READ OUT OF model_rate. The point of generating
// it is that the corpus can never state a price that has drifted from the rate table -- the same
// discipline as the rest of this body, applied to the one set of figures it does hold.
const pol = (await sql(`select * from public.model_policy_by_identity
                         where identity_key = 'it_engineer' and scope = 'current_agent'`))[0];
if (!pol) {
  console.error('public.model_policy_by_identity has no it_engineer/current_agent row -- apply '
    + 'scripts/sql/the_it_engineer_gets_a_knowledge_body_that_never_invents_a_cve.sql first. '
    + 'The model-pair record MUST NOT be invented.');
  process.exit(2);
}
const ladder = await sql(`select r.model, r.tier, r.usd_per_m_prompt, r.usd_per_m_output
                            from public.model_rate r
                            join public.model_registry g on g.model_id = r.model
                           where g.approved and g.active
                           order by r.usd_per_m_output, r.usd_per_m_prompt`);
const priceOf = (m) => { const r = ladder.find((x) => x.model === m); return r ? r.usd_per_m_prompt + '/' + r.usd_per_m_output + ' USD per Mtok (' + r.tier + ')' : 'NOT PRICED IN model_rate'; };
gen.push({
  record_id: 'QD-ITE-LIVE-MODEL-PAIR',
  record_type: 'live_posture',
  domain: 'model_routing',
  title: 'This seat\'s own model pair, and the measured price ladder the choice was made against',
  content: 'Generated on this load run from public.model_policy_by_identity and public.model_rate, so no price in this record can drift from the rate table. '
    + 'Identity key it_engineer, scope ' + pol.scope + '. Primary: ' + pol.primary_model + ' at ' + priceOf(pol.primary_model)
    + '. Fallback: ' + pol.fallback_model + ' at ' + priceOf(pol.fallback_model)
    + '. Escalation: ' + pol.escalation_model + ' at ' + priceOf(pol.escalation_model)
    + '. Max output tokens ' + pol.max_output_tokens + ', reasoning effort ' + pol.reasoning_effort
    + ', deterministic_first ' + pol.deterministic_first + '. '
    + 'The full approved and active ladder, cheapest output first: ' + ladder.map((r) => r.model + ' ' + r.usd_per_m_prompt + '/' + r.usd_per_m_output).join(' | ') + '. '
    + 'TWO OPERATIVE CONSEQUENCES FOR THIS SEAT. First, deterministic_first is Yes and that is not a preference: detection, thresholds, magic-byte checks and the free in-region gte-small embedding run with no model at all, and a seat that reaches for a model to decide whether a number crossed a threshold has wasted money on arithmetic. The model is for the second step -- what the detection MEANS and what to do -- and only then. '
    + 'Second, there is a standing hold on paid provider routes and it is in force: registering a pair is a routing declaration, not a call, and it is what makes the routing correct on the day the hold lifts. Do not attempt a paid call to prove this record, and do not raise the subject of the hold; it is a settled instruction, not an open question. '
    + 'If a model named above is missing from the ladder, that is the finding: an identity pin naming an unregistered model is worse than no pin, because it looks like a decision.',
  structured_data: { identity_key: 'it_engineer', scope: pol.scope,
                     primary: pol.primary_model, fallback: pol.fallback_model, escalation: pol.escalation_model,
                     max_output_tokens: pol.max_output_tokens, reasoning_effort: pol.reasoning_effort,
                     deterministic_first: pol.deterministic_first,
                     ladder: ladder.map((r) => ({ model: r.model, tier: r.tier,
                       usd_per_m_prompt: r.usd_per_m_prompt, usd_per_m_output: r.usd_per_m_output })),
                     source: 'public.model_policy_by_identity and public.model_rate',
                     paid_route_hold: 'in force; registering a pair is not a call' },
  source_ids: ['live:public.model_policy_by_identity', 'live:public.model_rate', 'live:public.model_registry'],
  epistemic_status: 'company_record_generated',
  jurisdiction: 'QuotesDone_estate',
  tags: ['model', 'routing', 'model pair', 'price', 'tier', 'deterministic first', 'live posture', 'identity'],
});

console.log('generating from live rows: ' + gen.length + ' record(s)');

for (const r of gen) {
  // The generated records are held to the SAME banned shapes as the authored ones. A live row that
  // happened to contain a version string must not enter the corpus by the back door.
  const banned = firstBanned(r.title + '\n' + r.content);
  if (banned) { refused.push([r.record_id, 'generated record contains ' + banned]); continue; }
  if (seenId.has(r.record_id)) { refused.push([r.record_id, 'generated record collides with an authored record_id']); continue; }
  seenId.set(r.record_id, -1);
  const bs = bodyHash(r);
  if (seenBody.has(bs)) collisions.push([r.record_id, seenBody.get(bs), bs]);
  else seenBody.set(bs, r.record_id);
  r.__body_sha256 = bs;
  r.__origin = 'generated';
  rows.push(r);
}

// ---------------------------------------------------------------------------------------------
// REPORT WHAT WAS READ, THEN ABORT ON ANY REFUSAL.
// ---------------------------------------------------------------------------------------------
const byType = {}; for (const r of rows) byType[r.record_type] = (byType[r.record_type] || 0) + 1;
const byEpi  = {}; for (const r of rows) byEpi[r.epistemic_status] = (byEpi[r.epistemic_status] || 0) + 1;
console.log('total records: ' + rows.length + ' (' + authoredCount + ' authored + ' + gen.length + ' generated)');
console.log('by record_type:      ' + JSON.stringify(byType));
console.log('by epistemic_status: ' + JSON.stringify(byEpi));
console.log('jurisdictions:       ' + JSON.stringify([...new Set(rows.map((r) => r.jurisdiction))]));

if (collisions.length) {
  console.log('BODY_SHA256 COLLISIONS ' + collisions.length + ' (same title+content under different IDs):');
  for (const [a, b, h] of collisions.slice(0, 20)) console.log('  ' + a + ' == ' + b + '  (' + h.slice(0, 12) + ')');
} else {
  console.log('body_sha256 collisions: 0 (' + seenBody.size + ' distinct bodies across ' + rows.length + ' records)');
}
if (refused.length) {
  console.log('REFUSED ' + refused.length + ':');
  for (const [i, w] of refused) console.log('  ' + i + ' :: ' + w);
  console.error('\nABORTING: ' + refused.length + ' refusal(s). Nothing written; existing rows untouched.');
  process.exit(1);
}
console.log('refused: 0');

if (!APPLY) { console.log('\nDRY RUN -- nothing written.'); process.exit(0); }

// ---------------------------------------------------------------------------------------------
// WRITE. Each chunk is ONE statement: a multi-row insert ... on conflict (record_id) do update, so
// it is atomic in itself and a repeat import updates in place and can produce no duplicate. Said
// plainly rather than claimed: the run is not one transaction, and it does not need to be --
// validation completed BEFORE the first write, and every statement is an idempotent upsert, so a
// run that dies halfway is fixed by running it again rather than by cleaning up after it.
// ---------------------------------------------------------------------------------------------
const lit = (v) => (v === null || v === undefined ? 'null' : "'" + String(v).replace(/'/g, "''") + "'");
const arr = (a) => (Array.isArray(a) && a.length ? 'array[' + a.map(lit).join(',') + ']::text[]' : "'{}'::text[]");

const before = new Map((await sql('select record_id, body_sha256 from public.it_engineer_knowledge'))
  .map((r) => [r.record_id, r.body_sha256]));
let inserted = 0, updated = 0, unchanged = 0;
for (const r of rows) {
  if (!before.has(r.record_id)) inserted++;
  else if (before.get(r.record_id) === r.__body_sha256) unchanged++;
  else updated++;
}

let done = 0;
for (let i = 0; i < rows.length; i += 25) {
  const values = rows.slice(i, i + 25).map((r) => `(${[
    lit(r.record_id), lit(r.record_type), lit(r.domain), lit(r.title), lit(r.content),
    lit(JSON.stringify(r.structured_data)) + '::jsonb', arr(r.source_ids),
    lit(r.epistemic_status), lit(r.jurisdiction), lit(PACK_ID), lit(PACK_VERSION),
    lit(r.__body_sha256), 'true', "'none'", arr(r.tags), lit(UPDATED_AT) + '::timestamptz',
  ].join(', ')})`).join(',\n');
  await sql(`insert into public.it_engineer_knowledge (record_id, record_type, domain, title, content,
      structured_data, source_ids, epistemic_status, jurisdiction, pack_id, pack_version,
      body_sha256, runtime_index_eligible, authority_effect, tags, updated_at)
    values ${values}
    on conflict (record_id) do update set
      record_type = excluded.record_type, domain = excluded.domain, title = excluded.title,
      content = excluded.content, structured_data = excluded.structured_data,
      source_ids = excluded.source_ids, epistemic_status = excluded.epistemic_status,
      jurisdiction = excluded.jurisdiction, pack_version = excluded.pack_version,
      body_sha256 = excluded.body_sha256,
      runtime_index_eligible = excluded.runtime_index_eligible,
      authority_effect = excluded.authority_effect, tags = excluded.tags,
      updated_at = excluded.updated_at, ingested_at = now()`);
  done += Math.min(25, rows.length - i);
  process.stdout.write(done + ' ');
}
console.log('\nknowledge rows written: ' + done);

// A body whose text changed must lose its old vector, or the HNSW index answers with a similarity
// computed against text that no longer exists. Measured and cleared rather than hoped about.
if (updated) {
  const stale = rows.filter((r) => before.has(r.record_id) && before.get(r.record_id) !== r.__body_sha256)
                    .map((r) => lit(r.record_id)).join(',');
  const cleared = await sql(`update public.it_engineer_knowledge set embedding_gte = null
                              where record_id in (${stale}) and embedding_gte is not null
                              returning record_id`);
  console.log('cleared ' + cleared.length + ' now-stale embedding(s); re-run the embedder');
}

console.log('\nSUMMARY  inserted ' + inserted + ' | updated ' + updated + ' | unchanged ' + unchanged
  + ' | refused ' + refused.length + ' | body collisions ' + collisions.length);

const c = await sql(`select
    (select count(*) from public.it_engineer_knowledge) records,
    (select count(*) from public.it_engineer_knowledge where search is not null) with_search,
    (select count(*) from public.it_engineer_knowledge where embedding_gte is not null) with_embedding,
    (select count(distinct record_type) from public.it_engineer_knowledge) types,
    (select count(distinct epistemic_status) from public.it_engineer_knowledge) epistemic_values,
    (select count(*) from public.it_engineer_knowledge where authority_effect <> 'none') carrying_authority,
    (select count(distinct body_sha256) from public.it_engineer_knowledge) distinct_bodies`);
console.log('IN THE DATABASE: ' + JSON.stringify(c[0]));
process.exit(0);
