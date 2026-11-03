// scripts/e2e/document_reading_qualification.mjs — the driver of the supplier document-reading qualification.
// Seat: sales_engineer. 3 Nov 2026. Builds the gold corpus, runs the code stage, and with --model opens this run's own TAGGED
// rehearsal window (models allowed for this tag only, a database-enforced cap: fn_kernel_paid_provider_gate) exactly as
// document_intake_accuracy.mjs does, then runs the model stage through the deployed license_extract and ai_gateway.
//
// INCAPABLE OF REACHING A REAL PERSON: every document is invented ("ZZ DEMO"), the one committed row is a ZZ DEMO subject
// supplier (qd-<tag>-...@example.invalid, no auth user) that carries the spend, torn down by the run; nothing is sent.
//
//   node scripts/e2e/document_reading_qualification.mjs [--model] [--repeats 5] [--cap-usd 5] [--out <dir>] [--corpus <dir>] [--only id,id]
//   needs: deno, and for --model SUPABASE_ACCESS_TOKEN (or `supabase login`) to open the window and read the keys.
import { mkdirSync, existsSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { SANDBOX_OUT } from '../lib/sandbox_out.mjs';

const argv = process.argv.slice(2);
const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };
const MODEL = argv.includes('--model');
const REPEATS = val('--repeats') || '5';
const CAP_USD = Number(val('--cap-usd') || 5);
if (!(CAP_USD > 0 && CAP_USD <= 15)) { console.error('REFUSED: --cap-usd must be in (0, 15]'); process.exit(2); }
const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const OUT = resolve(val('--out') || join(SANDBOX_OUT, 'document_reading_qualification'));
const CORPUS = resolve(val('--corpus') || join(OUT, 'corpus'));
mkdirSync(OUT, { recursive: true });
// sharp is a native module: deno keeps its node_modules in OUT, never in the repository
const deno = (script, args, env = {}) => {
  const r = spawnSync('deno', ['run', '-A', '--unsafe-proto', '--no-lock', '--node-modules-dir=auto', join(REPO, 'scripts', 'e2e', script), ...args],
    { stdio: 'inherit', cwd: OUT, env: { ...process.env, ...env } });
  if (r.status !== 0) throw new Error(`${script} exited ${r.status}`);
};
if (!existsSync(join(CORPUS, 'truth.json'))) deno('document_reading_qualification_corpus.ts', [CORPUS]);
const only = val('--only') ? ['--only', val('--only')] : [];
const label = MODEL ? 'model' : 'code';
if (!MODEL) { deno('document_reading_qualification.ts', [CORPUS, join(OUT, `result_${label}.json`), '--repeats', REPEATS, ...only]); process.exit(0); }

const { newRun, teardown, makeSupplier, keys, REF, q, closeRehearsalWindow, internalCred } = await import('../lib/demo_factory.mjs');
const { mgmtRead, mgmtFixture } = await import('../lib/qd_guard.mjs');
process.env.QD_FIXTURES = '1';
const read = (sql) => mgmtRead(REF, sql), write = (sql, where) => mgmtFixture(REF, sql, where);
const run = newRun({ quiet: true });
console.log(`model stage: run ${run.tag}, hard cap USD ${CAP_USD} (rehearsal_window.cap_usd)`);
await write(`insert into public.rehearsal_window (run_tag, opened_by, note) values (${q('qd_run:' + run.tag)}, 'scripts/e2e/document_reading_qualification.mjs', 'supplier document-reading qualification')`, 'rehearsal window');
let spend = null;
try {
  await write(`update public.rehearsal_window set models_allowed = true, cap_usd = ${CAP_USD}, expires_at = now() + interval '115 minutes'
               where run_tag = ${q('qd_run:' + run.tag)} and ended_at is null`, 'qualification window: models for this tag only');
  const subj = await makeSupplier(run, { trade: 'aluminium', withAuth: false, capability: false, company_name: `ZZ DEMO qualification subject ${run.tag}` });
  const { SERVICE } = await keys();
  const extract = (await read(`select value from public.app_secrets where key='cred_fn_supplier_api'`))[0]?.value || '';
  deno('document_reading_qualification.ts', [CORPUS, join(OUT, `result_${label}.json`), '--repeats', REPEATS, '--model', ...only], {
    SUPABASE_URL: `https://${REF}.supabase.co`, SUPABASE_SERVICE_ROLE_KEY: SERVICE, QD_RUN_TAG: run.tag,
    QD_SUBJECT: JSON.stringify({ supplier_id: Number(subj.leadId), email: subj.email }), QD_E2E_SECRET: await internalCred(), QD_SECRET_EXTRACT: extract });
} finally {
  await write(`update public.rehearsal_window set models_allowed = false where run_tag = ${q('qd_run:' + run.tag)}`, 'qualification window: models off').catch(() => {});
  spend = (await read(`select count(*)::int calls, coalesce(sum(cost_aed), 0)::numeric(12,4) aed from public.ai_cost_log where e2e_run_tag = ${q(run.tag)}`))[0];
  console.log(`spend: ${JSON.stringify(spend)} (server-to-server calls can drop the tag: an upper bound needs the window's own ledger)`);
  const t = await teardown(run);
  console.log(`run ${run.tag} torn down: ${t.summary}`);
  await closeRehearsalWindow(run.tag);
}
