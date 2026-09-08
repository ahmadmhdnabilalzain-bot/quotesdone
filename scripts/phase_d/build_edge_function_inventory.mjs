// EVERY DEPLOYED EDGE FUNCTION, CLASSIFIED FROM MEASUREMENT, NOT FROM A REGEX'S OPINION.
//
//   node scripts/phase_d/build_edge_function_inventory.mjs
//
// WHY THIS EXISTS. A broad static scan reported "117 of 202 Edge Functions write at least one
// trigger-protected table and 97 have no edge source row". Both halves are heuristics: the first
// counts a `.from('x').insert(` that appears anywhere in a file, including in a branch no caller can
// reach and in a string that is never executed; the second compares a slug list against
// public.kernel_trigger_source without asking whether a source row is REQUIRED for that function's
// class. Neither number can be acted on. This file replaces them with a per-function record that
// states, for each of the 202, what was measured and what was not.
//
// WHAT IS MEASURED, PER FUNCTION
//
//   deployed          the Supabase management API's own list: slug, status, verify_jwt, version,
//                     updated_at. The population is what is DEPLOYED, not what is in the repo.
//   repo source       supabase/functions/<slug>/**.ts, concatenated, comments stripped before every
//                     pattern below is applied — so a `.insert(` inside a comment is not a write.
//   writes            .from('<t>').insert/update/upsert/delete(  and  .rpc('<fn>')
//   protected tables  the eight kernel-guarded tables, from public.kernel_write_authority's own
//                     table list plus the tables carrying z10_kernel_write_guard, read live.
//   entry             Deno.serve present; verify_jwt; whether a cron job command names the slug;
//                     whether any file under src/ names the slug; whether another edge function
//                     fetches it; webhook/provider-callback markers.
//   registers         public.phase_c_component (the 202 registered edge components),
//                     public.kernel_trigger_source (edge_function rows),
//                     public.phase_c_source_cutover, public.phase_c_edge_function_writes.
//   runtime           public.os_audit_log for the slug, and the deployment's own updated_at. The
//                     PostgreSQL/edge log stream is NOT read here: Log Explorer holds 24 hours and a
//                     24-hour window cannot answer "has this ever run". That limitation is written
//                     into the file rather than papered over with a zero.
//
// WHAT IS NOT MEASURED, STATED HERE SO IT IS NOT READ AS A ZERO
//
//   * A write performed through a variable table name (`.from(tbl)`) is counted as DYNAMIC and
//     listed for manual review; it is never silently dropped.
//   * A write reached only from a branch no caller can enter is not distinguished from a reachable
//     one by static text alone. Where the runtime evidence says the function has never been invoked,
//     the record says NEVER_OBSERVED rather than claiming the branch is dead.
//   * Comments and string literals are stripped before matching, so dead code that is commented out
//     is not counted as a live source. Dead code that is compiled but unreachable is not detected.
//
// ZERO COST, ZERO EFFECT: reads only. No function is invoked, no provider is called, nothing is
// deployed, and nothing is written to the database by this script.
import { readFileSync, readdirSync, existsSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { outPath, provenance } from './lib/deliverable.mjs';
import { sql } from '../lib/db.mjs';

const PROJECT = 'htdblwldjkcgjvmqkbeh';
const FN_DIR = 'supabase/functions';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

const mgmt = async (path) => {
  for (let i = 0; i < 6; i++) {
    const r = await fetch(`https://api.supabase.com/v1/projects/${PROJECT}${path}`,
      { headers: { authorization: `Bearer ${token}` } });
    if (r.ok) return r.json();
    if (r.status === 429 || r.status >= 500) { await new Promise((s) => setTimeout(s, 1500 * (i + 1))); continue; }
    throw new Error(`management ${path} -> ${r.status}: ${(await r.text()).slice(0, 200)}`);
  }
  throw new Error(`management ${path} kept failing`);
};

// ---- 1. THE POPULATION: WHAT IS DEPLOYED --------------------------------------------------------
const deployed = await mgmt('/functions');
console.log(`deployed edge functions        ${deployed.length}`);

// ---- 2. THE LIVE REGISTERS ----------------------------------------------------------------------
const protectedTables = (await sql(`
  select distinct c.relname as table_name
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_proc p on p.oid = t.tgfoid
   where n.nspname = 'public' and not t.tgisinternal and p.proname = 'fn_kernel_write_guard'
   order by 1`)).map((r) => r.table_name);
console.log(`kernel write-guarded tables    ${protectedTables.length}: ${protectedTables.join(', ')}`);

const components = new Map((await sql(`
  select component_id, entry_method, current_callers, external_entry, schedule_or_trigger,
         mutates_state, current_actor, canonical_system_actor, accountable_role_id, workflow_id,
         step_id, authority_class, trace_policy_id, idempotency_strategy, activation_state,
         classification, gap
    from public.phase_c_component where component_type = 'edge_function'`))
  .map((r) => [String(r.component_id).replace(/^edge:/, ''), r]));

const cronSources = new Map((await sql(`
  select source_key, source_class, workflow_id, connection_state, disposition
    from public.kernel_trigger_source where source_kind = 'cron_job'`))
  .map((r) => [String(r.source_key).replace(/^cron:/, ''), r]));

const sources = new Map((await sql(`
  select source_key, source_ref, source_class, workflow_id, accountable_role_id, connection_state,
         disposition, recorded_active, recorded_creates_work, recorded_routes_through_inbox
    from public.kernel_trigger_source where source_kind = 'edge_function'`))
  .map((r) => [String(r.source_ref || r.source_key).replace(/^edge(_function)?:/, ''), r]));

const cutovers = new Map((await sql(`
  select source_component_id, source_class, current_entry_point, target_kernel_adapter,
         target_workflow, target_step_or_signal, accountable_role, system_actor, trace_policy,
         current_activation, status, idempotency_key
    from public.phase_c_source_cutover`))
  .map((r) => [String(r.source_component_id).replace(/^edge:/, ''), r]));

const recordedWrites = new Map();
for (const r of await sql(`select edge_function, table_name, write_kind, unbounded
                             from public.phase_c_edge_function_writes`)) {
  if (!recordedWrites.has(r.edge_function)) recordedWrites.set(r.edge_function, []);
  recordedWrites.get(r.edge_function).push(`${r.table_name}:${r.write_kind}${r.unbounded ? ':unbounded' : ''}`);
}

const cronCommands = await sql(`select jobid, jobname, command, active from cron.job`);

// WHICH DATABASE ROUTINES REACH AN EDGE FUNCTION, AND THROUGH WHICH TRIGGER. dispatch_inquiry has no
// frontend caller, no cron job and no kernel door in its own source, and on the first pass this
// script called it DERIVED_INTERNAL_MUTATION. It is none of those: public.inquiries carries
// autodispatch_inquiry, whose function net.http_post's /functions/v1/dispatch_inquiry. The
// autonomous source is the TRIGGER, registered as dbtrigger:public.inquiries:autodispatch_inquiry,
// exactly as a cron-driven function's source is the cron job.
const dbCallers = await sql(`
  select p.proname,
         coalesce(string_agg(distinct 'dbtrigger:' || tn.nspname || '.' || tc.relname || ':' || t.tgname, ' '), '') as triggers,
         p.prosrc
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    left join pg_trigger t on t.tgfoid = p.oid and not t.tgisinternal
    left join pg_class tc on tc.oid = t.tgrelid
    left join pg_namespace tn on tn.oid = tc.relnamespace
   where n.nspname = 'public' and p.prosrc like '%/functions/v1/%'
   group by p.proname, p.prosrc`);
const dbTriggerSources = new Map((await sql(`
  select source_key, source_class, workflow_id, connection_state, disposition
    from public.kernel_trigger_source where source_kind = 'database_trigger'`))
  .map((r) => [String(r.source_key), r]));
const auditActors = new Map((await sql(`
  select action, count(*) n, max(at)::text last_at from public.os_audit_log group by 1`))
  .map((r) => [r.action, r]));

// ---- 3. THE REPO SOURCE -------------------------------------------------------------------------
const walk = (d) => readdirSync(d).flatMap((e) => {
  const p = join(d, e);
  return statSync(p).isDirectory() ? walk(p) : [p];
});
// Comments FIRST, then string literals are kept (we need the table names inside them) — but a
// `.from('x').insert(` that lives inside a comment must not count, which is the whole reason this
// runs before any pattern below.
const stripComments = (s) => s.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/(^|[^:])\/\/[^\n]*/g, '$1 ');

const srcIndex = existsSync('src') ? walk('src').filter((f) => /\.(ts|tsx|js|jsx)$/.test(f))
  .map((f) => ({ f, t: readFileSync(f, 'utf8') })) : [];

// Edge-to-edge callers: which OTHER deployed function's source names this slug's URL.
const fnSources = new Map();
for (const d of (existsSync(FN_DIR) ? readdirSync(FN_DIR) : [])) {
  const dir = join(FN_DIR, d);
  try { if (!statSync(dir).isDirectory()) continue; } catch { continue; }
  const t = walk(dir).filter((f) => /\.(ts|tsx|js|mjs)$/.test(f)).map((f) => readFileSync(f, 'utf8')).join('\n');
  fnSources.set(d, t);
}

const WRITE_RE = /\.from\(\s*['"`]([A-Za-z0-9_]+)['"`]\s*\)([\s\S]{0,400}?)\.(insert|update|upsert|delete)\s*\(/g;
// `.storage.from(bucket)` is the Storage API, not a table. Four of the six functions this pattern
// first reported as dynamic writers — agent_act, compliance_archive, dropbox_backup, vt_scan — were
// only ever calling storage.remove / storage.download / storage.upload, so the negative lookbehind
// is what makes the DYNAMIC column mean "a table this scan could not name".
const DYN_RE = /(?<!\.storage)\.from\(\s*(?!['"`])([A-Za-z0-9_.$\[\]]+)\s*\)([\s\S]{0,200}?)\.(insert|update|upsert|delete)\s*\(/g;

// DECLARED MANUAL REVIEW. A dynamic table name defeats the scan, so each one is read by hand and the
// RESOLVED set is recorded here with the date. An entry is not an exemption: the resolved tables are
// still checked against the kernel-guarded list below, and a function that acquires a dynamic write
// with no entry here is reported as unreviewed.
const MANUAL_REVIEW = {
  kb_embed: {
    reviewed_on: '2026-08-27',
    resolved_tables: ['kb_chunks', 'company_faq'],
    note: 'supabase/functions/kb_embed/index.ts:78 TARGETS is a literal map of exactly two entries and '
        + 'line 84 falls back to kb_chunks for any other value, so `admin.from(tgt.table)` cannot name a '
        + 'third table. The only column written is embedding_gte.',
  },
  os_ops: {
    reviewed_on: '2026-08-27',
    resolved_tables: ['inquiries', 'leads', 'crm_tasks', 'expenses',
                      'board_reports', 'exec_reports', 'finance_reports', 'agent_actions', 'security_events'],
    note: 'supabase/functions/os_ops/index.ts:17 EDITABLE and :24 CONTENT are literal maps; `field_set` '
        + 'refuses any entity or field absent from EDITABLE (line 181) and the content path refuses any '
        + 'key absent from CONTENT, so both dynamic `admin.from(x)` sites are bounded by those nine tables.',
  },
};
const RPC_RE = /\.rpc\(\s*['"`]([A-Za-z0-9_]+)['"`]/g;
const PROVIDERS = [
  ['openrouter', /openrouter\.ai|OPENROUTER/i], ['openai', /api\.openai\.com/i],
  ['stripe', /api\.stripe\.com|Stripe\(/i], ['twilio', /api\.twilio\.com/i],
  ['resend', /api\.resend\.com/i], ['sendgrid', /api\.sendgrid\.com/i],
  ['apify', /api\.apify\.com/i], ['dropbox', /dropboxapi\.com/i],
  ['whatsapp', /graph\.facebook\.com|whatsapp/i],
];

const rows = [];
const counts = {};
const bump = (k) => { counts[k] = (counts[k] || 0) + 1; };

for (const fn of deployed.sort((a, b) => a.slug.localeCompare(b.slug))) {
  const slug = fn.slug;
  const dir = join(FN_DIR, slug);
  const files = existsSync(dir) ? walk(dir).filter((f) => /\.(ts|tsx|js|mjs)$/.test(f)) : [];
  const raw = files.map((f) => readFileSync(f, 'utf8')).join('\n');
  const code = stripComments(raw);

  const writes = new Set(); const dyn = new Set(); const rpcs = new Set();
  for (const m of code.matchAll(WRITE_RE)) writes.add(`${m[1]}.${m[3]}`);
  for (const m of code.matchAll(DYN_RE)) dyn.add(`${m[1]}.${m[3]}`);
  for (const m of code.matchAll(RPC_RE)) rpcs.add(m[1]);
  const protectedHit = [...writes].filter((w) => protectedTables.includes(w.split('.')[0]));
  const providersUsed = PROVIDERS.filter(([, re]) => re.test(code)).map(([n]) => n);

  const cronCallers = cronCommands.filter((c) => String(c.command || '').includes(`/${slug}`)
    || String(c.command || '').includes(`'${slug}'`));
  const frontendCallers = srcIndex.filter((s) => s.t.includes(`functions/v1/${slug}`)
    || s.t.includes(`invoke('${slug}'`) || s.t.includes(`invoke("${slug}"`)).map((s) => s.f);
  const kernelCalls = [...rpcs].filter((r) => /^fn_kernel_|^fn_phase_c_|^fn_phase_d_/.test(r));
  // A PROVIDER CALLBACK IS A SIGNATURE, NOT A verify_jwt FLAG. Nearly every function on this
  // project runs verify_jwt=false and does its own auth, so that flag alone classified 113 of 202
  // as webhooks on the first run of this script -- a classifier that says "webhook" about half the
  // estate is not measuring anything. A real callback presents a provider signature header or is
  // named as a hook.
  const webhookMarker = /stripe-signature|x-hub-signature|X-Twilio-Signature|svix-id|svix-signature|x-signature-ed25519|hub.challenge/i.test(code)
    || /(^|_)(webhook|hook|callback)(_|$)/i.test(slug);
  const comp = components.get(slug) || null;
  const src = sources.get(slug) || null;
  const cut = cutovers.get(slug) || null;
  const audit = auditActors.get(slug) || null;
  const edgeCallers = [...fnSources.entries()]
    .filter(([other, t]) => other !== slug && (t.includes(`functions/v1/${slug}`) || t.includes(`invoke('${slug}'`) || t.includes(`invoke("${slug}"`)))
    .map(([other]) => other);
  const dbRoutineCallers = dbCallers.filter((d) => String(d.prosrc).includes(`/functions/v1/${slug}`));
  const dbTriggerKeys = [...new Set(dbRoutineCallers.flatMap((d) => String(d.triggers || '').split(' ').filter(Boolean)))];
  const dbTriggerRows = dbTriggerKeys.map((k) => dbTriggerSources.get(k)
    || dbTriggerSources.get(k.replace(/^dbtrigger:public./, 'dbtrigger:'))).filter(Boolean);
  const authSurface = /(^|_)(otp|login|auth|session|token|kyc|role_guard|signup|verify)(_|$)/i.test(slug);
  const monitorSurface = /(^|_)(health|uptime|ping|scan|monitor|advisor|drill|resilience|cost_snapshot|money_tests)(_|$)/i.test(slug);

  // ---- CLASSIFICATION. Deterministic, in this order; the FIRST match wins and the rule that
  // matched is recorded so a reader can disagree with a specific sentence rather than a verdict.
  let cls, why;
  if (!files.length) { cls = 'RETIRED'; why = 'deployed but no source directory in the repository'; }
  else if (comp && comp.activation_state === 'inactive') { cls = 'INTENTIONALLY_INACTIVE'; why = `phase_c_component.activation_state=inactive (${comp.classification})`; }
  // THE REGISTER IS EVIDENCE, NOT A GUESS. Where public.kernel_trigger_source already records this
  // function as an external source, its recorded class decides, and the heuristics below never run.
  else if (src && src.source_class === 'webhook_provider_event') { cls = 'PROVIDER_CALLBACK'; why = `kernel_trigger_source ${src.source_key} class webhook_provider_event, ${src.connection_state}, workflow ${src.workflow_id || '(none)'}`; }
  else if (src && src.recorded_creates_work) { cls = 'AUTONOMOUS_NEW_WORK_REQUEST'; why = `kernel_trigger_source ${src.source_key} class ${src.source_class}, recorded_creates_work=true, ${src.connection_state}, workflow ${src.workflow_id || '(none)'}`; }
  else if (src && src.source_class) { cls = 'SYNCHRONOUS_USER_APPLICATION_ENTRY'; why = `kernel_trigger_source ${src.source_key} class ${src.source_class}, recorded_creates_work=false: an external entry that answers rather than creating work`; }
  else if (webhookMarker) { cls = 'PROVIDER_CALLBACK'; why = `a provider-signature header or a hook name is present${providersUsed.length ? ` (${providersUsed.join(', ')})` : ''}; verify_jwt=${fn.verify_jwt}`; }
  else if (kernelCalls.some((k) => /fn_kernel_trigger_submit|fn_kernel_source_emit|fn_kernel_workflow_start/.test(k))) { cls = 'AUTONOMOUS_NEW_WORK_REQUEST'; why = `calls the kernel new-work door: ${kernelCalls.join(', ')}`; }
  else if (kernelCalls.some((k) => /fn_kernel_signal_submit|fn_kernel_step_complete|fn_kernel_handoff|fn_kernel_outbox_emit|fn_phase_c_event_ingress/.test(k))) { cls = 'EXISTING_WORKFLOW_SIGNAL'; why = `signals an existing run: ${kernelCalls.join(', ')}`; }
  else if (frontendCallers.length) { cls = 'SYNCHRONOUS_USER_APPLICATION_ENTRY'; why = `reached from ${frontendCallers.length} file(s) under src/: ${frontendCallers.slice(0,3).join(' ')}`; }
  else if (writes.size === 0 && dyn.size === 0 && rpcs.size === 0) { cls = 'READ_ONLY'; why = 'no table write, no dynamic write and no rpc survive comment-stripping'; }
  else if (authSurface) { cls = 'AUTH_OR_SESSION_SUPPORT'; why = 'authentication/session surface by slug; its writes are its own session and identity tables'; }
  else if (monitorSurface) { cls = 'MONITORING'; why = 'monitoring/health surface by slug'; }
  else if (dbTriggerRows.length) { cls = 'EXISTING_WORKFLOW_SIGNAL'; why = `invoked by database trigger(s) ${dbTriggerKeys.join(' ')} whose source row(s) are registered: ${dbTriggerRows.map((r) => r.source_key + '=' + r.connection_state).join(' ')}`; }
  else if (dbRoutineCallers.length) { cls = 'KERNEL_INTERNAL'; why = `invoked from database routine(s) ${dbRoutineCallers.map((d) => d.proname).slice(0,4).join(' ')} that are not trigger functions`; }
  else if (cronCallers.length) { cls = 'AUTONOMOUS_NEW_WORK_REQUEST'; why = `driven by cron job(s) ${cronCallers.map((c) => c.jobid + (c.active ? '' : '(inactive)')).join(', ')} and reached from no user surface`; }
  else if (protectedHit.length) { cls = 'BLOCKED_DEFECT'; why = `writes kernel-guarded table(s) ${protectedHit.join(', ')} with no user entry, no cron and no kernel door`; }
  else if (edgeCallers.length) { cls = 'KERNEL_INTERNAL'; why = `invoked by another edge function: ${edgeCallers.slice(0,4).join(', ')}`; }
  else { cls = 'DERIVED_INTERNAL_MUTATION'; why = 'writes only its own derived/projection tables; no frontend, cron, edge or kernel caller found'; }
  bump(cls);

  // A kernel_trigger_source row is REQUIRED only for the three classes that create or signal work.
  // WHERE THE AUTONOMOUS SOURCE IS ACTUALLY REGISTERED. A cron-driven edge function is not itself
  // the source of the work -- the CRON JOB is, and public.kernel_trigger_source keys those rows
  // , 206 of them. Demanding an edge-keyed row for a cron-driven function measures the
  // wrong subject: on the first run of this script that reported 36 MISSING, and all 36 had a
  // registered cron source. The register is asked in the shape it is written in.
  const cronSourceRows = cronCallers.map((c) => cronSources.get(String(c.jobid))).filter(Boolean);
  const sourceRequired = ['AUTONOMOUS_NEW_WORK_REQUEST', 'EXISTING_WORKFLOW_SIGNAL'].includes(cls)
    || (cls === 'PROVIDER_CALLBACK' && (kernelCalls.length > 0 || writes.size > 0));
  let sourceStatus;
  if (!sourceRequired) sourceStatus = src ? 'PRESENT_NOT_REQUIRED' : 'NOT_REQUIRED';
  else if (src) sourceStatus = 'PRESENT_AS_EDGE_SOURCE';
  else if (cronSourceRows.length) sourceStatus = 'PRESENT_AS_CRON_SOURCE:' + cronCallers.map((c) => 'cron:' + c.jobid).join('+');
  else if (dbTriggerRows.length) sourceStatus = 'PRESENT_AS_DB_TRIGGER_SOURCE:' + dbTriggerRows.map((r) => r.source_key).join('+');
  else sourceStatus = 'MISSING';
  if (sourceStatus === 'MISSING') bump('SOURCE_ROW_MISSING');
  const review = MANUAL_REVIEW[slug] || null;
  const reviewedTables = review ? review.resolved_tables : [];
  const reviewedGuarded = reviewedTables.filter((t) => protectedTables.includes(t));
  if (dyn.size && !review) bump('DYNAMIC_WRITE_UNREVIEWED');
  if (dyn.size && review) bump('DYNAMIC_WRITE_REVIEWED_BY_HAND');
  if (reviewedGuarded.length) bump('REVIEWED_DYNAMIC_WRITE_HITS_A_GUARDED_TABLE');
  if (protectedHit.length) bump('WRITES_A_KERNEL_GUARDED_TABLE');

  const stateChanging = writes.size > 0 || dyn.size > 0 || kernelCalls.length > 0;
  const unclassified = !cls;
  if (stateChanging && (cls === 'READ_ONLY')) bump('CONTRADICTION_readonly_but_writes');

  rows.push({
    slug,
    deployed_status: fn.status,
    verify_jwt: fn.verify_jwt,
    version: fn.version,
    deployed_updated_at: new Date(fn.updated_at).toISOString(),
    repo_files: files.length,
    classification: cls,
    classification_basis: why,
    state_changing: stateChanging,
    tables_written: [...writes].sort().join(' '),
    kernel_guarded_tables_written: protectedHit.sort().join(' '),
    dynamic_writes_manual_review: [...dyn].sort().join(' '),
    dynamic_write_review: review ? `REVIEWED ${review.reviewed_on}: ${reviewedTables.join(' ')}`
      : (dyn.size ? 'UNREVIEWED' : ''),
    dynamic_write_review_note: review ? review.note : '',
    rpcs_called: [...rpcs].sort().join(' '),
    kernel_doors_called: kernelCalls.sort().join(' '),
    providers_referenced: providersUsed.join(' '),
    cron_callers: cronCallers.map((c) => `${c.jobid}${c.active ? '' : '(inactive)'}`).join(' '),
    frontend_callers: frontendCallers.join(' '),
    edge_function_callers: edgeCallers.join(' '),
    database_callers: dbRoutineCallers.map((d) => d.proname).join(' '),
    database_trigger_sources: dbTriggerKeys.join(' '),
    kernel_trigger_source: sourceStatus,
    cron_source_state: cronSourceRows.map((r) => r.source_key + '=' + r.connection_state + (r.workflow_id ? '/' + r.workflow_id : '')).join(' '),
    source_row_required: sourceRequired,
    registered_component: comp ? comp.classification : '(none)',
    registered_activation: comp ? comp.activation_state : '',
    registered_workflow: comp ? (comp.workflow_id || '') : '',
    registered_step: comp ? (comp.step_id || '') : '',
    registered_role: comp ? (comp.accountable_role_id || '') : '',
    registered_actor: comp ? (comp.canonical_system_actor || '') : '',
    registered_authority: comp ? (comp.authority_class || '') : '',
    registered_trace_policy: comp ? (comp.trace_policy_id || '') : '',
    registered_idempotency: comp ? (comp.idempotency_strategy || '') : '',
    cutover_status: cut ? cut.status : '(no cutover row)',
    cutover_target: cut ? [cut.target_kernel_adapter, cut.target_workflow, cut.target_step_or_signal].filter(Boolean).join('/') : '',
    recorded_writes_register: (recordedWrites.get(slug) || []).sort().join(' '),
    runtime_evidence: audit ? `os_audit_log ${audit.n} row(s), last ${audit.last_at}` : 'NEVER_OBSERVED in os_audit_log',
  });
}

// ---- 4. THE FILE --------------------------------------------------------------------------------
const COLS = Object.keys(rows[0]);
const cell = (v) => { const s = v == null ? '' : String(v); return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
const stateChangingCount = rows.filter((r) => r.state_changing).length;
const unclassifiedCount = rows.filter((r) => !r.classification).length;
const missingSource = rows.filter((r) => r.kernel_trigger_source === 'MISSING');
const guarded = rows.filter((r) => r.kernel_guarded_tables_written);
const dynamic = rows.filter((r) => r.dynamic_writes_manual_review);
const dynUnreviewed = dynamic.filter((r) => r.dynamic_write_review === 'UNREVIEWED');
const noRepoSource = rows.filter((r) => r.repo_files === 0);

const csv = provenance({
  command: 'node scripts/phase_d/build_edge_function_inventory.mjs',
  numerator: rows.length,
  denominator: deployed.length,
  of: 'Edge Functions the Supabase management API reports as deployed on this project',
  attribution: 'classification is the first matching deterministic rule over (repo source with comments stripped; cron.job commands; files under src/; verify_jwt; phase_c_component; kernel_trigger_source); the rule that matched is in classification_basis',
}) + COLS.join(',') + '\n' + rows.map((r) => COLS.map((c) => cell(r[c])).join(',')).join('\n') + '\n';
writeFileSync(outPath('PHASE_D_EDGE_FUNCTION_INVENTORY.csv'), csv);

console.log(`\ninventoried                    ${rows.length} of ${deployed.length}`);
console.log(`state-changing                 ${stateChangingCount}`);
console.log(`unclassified                   ${unclassifiedCount}`);
console.log(`no repo source (RETIRED)       ${noRepoSource.length}${noRepoSource.length ? ': ' + noRepoSource.map((r) => r.slug).join(', ') : ''}`);
console.log(`writes a kernel-guarded table  ${guarded.length}${guarded.length ? ': ' + guarded.map((r) => r.slug).join(', ') : ''}`);
console.log(`dynamic writes, hand-reviewed  ${dynamic.length - dynUnreviewed.length} of ${dynamic.length}${dynamic.length ? ': ' + dynamic.map((r) => r.slug).join(', ') : ''}`);
console.log(`dynamic writes UNREVIEWED      ${dynUnreviewed.length}${dynUnreviewed.length ? ': ' + dynUnreviewed.map((r) => r.slug).join(', ') : ''}`);
console.log(`source row REQUIRED and MISSING ${missingSource.length}${missingSource.length ? ': ' + missingSource.map((r) => r.slug).join(', ') : ''}`);
console.log('\nby classification:');
for (const [k, v] of Object.entries(counts).sort((a, b) => b[1] - a[1])) console.log(`  ${String(v).padStart(4)}  ${k}`);
console.log(`\nwrote ${outPath('PHASE_D_EDGE_FUNCTION_INVENTORY.csv')}`);
