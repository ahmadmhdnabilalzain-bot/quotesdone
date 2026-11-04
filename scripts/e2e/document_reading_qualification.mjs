// scripts/e2e/document_reading_qualification.mjs — the driver of the supplier document-reading qualification.
// Seat: sales_engineer. 3 Nov 2026. Builds a corpus, runs the code stage, and with --model opens this run's own TAGGED
// rehearsal window (models allowed for this tag only, a database-enforced cap: fn_kernel_paid_provider_gate) exactly as
// document_intake_accuracy.mjs does, then runs the model stage through the deployed license_extract and ai_gateway.
//
// Two corpora:
//   synthetic (default)  scripts/e2e/document_reading_qualification_corpus.ts: invented ZZ DEMO documents with known lines and
//                        pages, including the edge cases no real company publishes (corrupt, password-protected, 30 MB)
//   --real               the 56 real UAE company profiles and catalogues of document_reading_qualification_real.json, fetched from
//                        the private evidence bucket with the service role and refused unless the sha256 matches; labelled by
//                        each set's hand-written truth.json. Never written into the repository.
//
// INCAPABLE OF REACHING A REAL PERSON: the one committed row is a ZZ DEMO subject supplier (qd-<tag>-...@example.invalid, no auth
// user) that carries the spend, torn down by the run; no message is sent; a real company's file is read, never contacted.
//
//   node scripts/e2e/document_reading_qualification.mjs [--real] [--model] [--repeats 5] [--parallel 3] [--cap-usd 5] [--out <dir>] [--only id,id]
//   needs: deno; --real and --model need SUPABASE_ACCESS_TOKEN (CI: the repository secret). QD_E2E_RUN_TAGS: the job's tag file.
import { mkdirSync, existsSync, writeFileSync, readFileSync, appendFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { SANDBOX_OUT } from '../lib/sandbox_out.mjs';

const argv = process.argv.slice(2);
const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };
const MODEL = argv.includes('--model'), REAL = argv.includes('--real');
const REPEATS = val('--repeats') || '5', PARALLEL = val('--parallel') || '1';
const CAP_USD = Number(val('--cap-usd') || 5);
if (!(CAP_USD > 0 && CAP_USD <= 5)) { console.error('REFUSED: --cap-usd must be in (0, 5] (coordinator, 3 Nov 2026)'); process.exit(2); }
// THE SYNTHETIC CORPUS NEVER OPENS A MODEL WINDOW (3 Nov 2026, coordinator): its two model-stage windows (cbfb5114, 256e0148) billed the
// real model AED 23.46 of the day's AED 48.22, measured in ai_cost_log. Its model questions are answered on the real corpus; the
// synthetic corpus is measured by code only. Refused before any window, row or call exists.
if (MODEL && !REAL) { console.error('REFUSED: --model runs on the real corpus only (--real); the synthetic corpus is measured by code, with no model'); process.exit(2); }
const HERE = dirname(fileURLToPath(import.meta.url)), REPO = resolve(HERE, '..', '..');
const OUT = resolve(val('--out') || join(SANDBOX_OUT, 'document_reading_qualification'));
const CORPUS = join(OUT, REAL ? 'real' : 'synthetic');
mkdirSync(CORPUS, { recursive: true });
// sharp is a native module: deno keeps its node_modules in OUT, never in the repository
const deno = (script, args, env = {}) => {
  const r = spawnSync('deno', ['run', '-A', '--unsafe-proto', '--no-lock', '--node-modules-dir=auto', join(REPO, 'scripts', 'e2e', script), ...args],
    { stdio: 'inherit', cwd: OUT, env: { ...process.env, ...env } });
  if (r.status !== 0) throw new Error(`${script} exited ${r.status}`);
};

// ── the real corpus, from the evidence bucket ────────────────────────────────────────────────────────
async function realCorpus() {
  const { keys, REF } = await import('../lib/demo_factory.mjs');
  const { createClient } = await import('@supabase/supabase-js');
  const { SERVICE } = await keys();
  const sb = createClient(`https://${REF}.supabase.co`, SERVICE, { auth: { persistSession: false } });
  const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const man = JSON.parse(readFileSync(join(HERE, 'document_reading_qualification_real.json'), 'utf8')).items;
  const truths = {};
  const items = [];
  for (const m of man) {
    const t = (truths[m.set] ??= Object.fromEntries(JSON.parse(readFileSync(join(HERE, m.set, 'truth.json'), 'utf8')).docs.map((d) => [d.id, d])))[m.id];
    const path = join(CORPUS, m.file);
    if (!existsSync(path)) {
      const { data, error } = await sb.storage.from('evidence').download(m.evidence_key);
      if (error || !data) throw new Error(`${m.id}: the evidence object could not be fetched: ${error?.message ?? 'no data'}`);
      writeFileSync(path, Buffer.from(await data.arrayBuffer()));
    }
    const bytes = readFileSync(path);
    const sha = createHash('sha256').update(bytes).digest('hex');
    if (sha !== m.sha256) throw new Error(`${m.id}: sha256 ${sha} is not the recorded ${m.sha256}: refused`);
    let pages = 1;
    if (/pdf/i.test(m.mime)) { try { pages = (await pdfjs.getDocument({ data: new Uint8Array(bytes), isEvalSupported: false, disableFontFace: true }).promise).numPages; } catch { pages = 0; } }
    const scan = /image|no_text|png|scan/i.test(m.format), arabic = /arabic|bilingual/i.test(m.format);
    const cls = scan ? 'real_scan' : arabic ? 'real_arabic_bilingual' : m.kind === 'catalogue' ? 'real_catalogue' : pages >= 100 ? 'real_long_100p_plus' : pages >= 20 ? 'real_mid_20_99p' : 'real_short_under_20p';
    items.push({ id: `${m.id}_${pages}p`, file: m.file, mime: m.mime, kind: m.kind === 'catalogue' ? 'catalogue' : 'profile', cls, pages, text_layer: !scan,
      registered_name: t.registered_name, trades: t.truth.trades.map((code) => ({ code, line: '', page: 0 })), allowed: t.truth.trades_also ?? [], forbidden: [], strict: true,
      ...(scan ? { expect: 'needs_model' } : {}), note: `${m.set}/${m.id} ${m.format}` });
    console.log(`${m.id}: ${(bytes.length / 1048576).toFixed(1)} MB, ${pages} pages, sha256 verified, ${cls}`);
  }
  writeFileSync(join(CORPUS, 'truth.json'), JSON.stringify({ builder: 'scripts/e2e/document_reading_qualification_real.json (real profiles, evidence bucket)', items }, null, 1));
}
if (!existsSync(join(CORPUS, 'truth.json'))) { if (REAL) await realCorpus(); else deno('document_reading_qualification_corpus.ts', [CORPUS]); }
const only = val('--only') ? ['--only', val('--only')] : [];
const label = `${REAL ? 'real' : 'synthetic'}_${MODEL ? 'model' : 'code'}`;
const result = join(OUT, `result_${label}.json`);
const runArgs = [CORPUS, result, '--repeats', REPEATS, '--parallel', PARALLEL, ...only];
if (!MODEL) { deno('document_reading_qualification.ts', runArgs); process.exit(0); }

// ── the model stage, inside this run's own tagged window ─────────────────────────────────────────────
const { newRun, teardown, makeSupplier, keys, REF, q, closeRehearsalWindow, internalCred } = await import('../lib/demo_factory.mjs');
const { mgmtRead, mgmtFixture } = await import('../lib/qd_guard.mjs');
process.env.QD_FIXTURES = '1';
const read = (sql) => mgmtRead(REF, sql), write = (sql, where) => mgmtFixture(REF, sql, where);
const run = newRun({ quiet: true });
// the job's always() step tears down and closes every tag in this file, even when this process is killed (close_job_windows.mjs)
if (process.env.QD_E2E_RUN_TAGS) appendFileSync(process.env.QD_E2E_RUN_TAGS, run.tag + '\n');
console.log(`model stage (${label}): run ${run.tag}, hard cap USD ${CAP_USD} (rehearsal_window.cap_usd)`);
await write(`insert into public.rehearsal_window (run_tag, opened_by, note) values (${q('qd_run:' + run.tag)}, 'scripts/e2e/document_reading_qualification.mjs', ${q('supplier document-reading qualification ' + label)})`, 'rehearsal window');
try {
  await write(`update public.rehearsal_window set models_allowed = true, cap_usd = ${CAP_USD}, expires_at = now() + interval '115 minutes'
               where run_tag = ${q('qd_run:' + run.tag)} and ended_at is null`, 'qualification window: models for this tag only');
  const subj = await makeSupplier(run, { trade: 'aluminium', withAuth: false, capability: false, company_name: `ZZ DEMO qualification subject ${run.tag}` });
  const { SERVICE } = await keys();
  const extract = (await read(`select value from public.app_secrets where key='cred_fn_supplier_api'`))[0]?.value || '';
  deno('document_reading_qualification.ts', [...runArgs, '--model'], {
    SUPABASE_URL: `https://${REF}.supabase.co`, SUPABASE_SERVICE_ROLE_KEY: SERVICE, QD_RUN_TAG: run.tag,
    QD_SUBJECT: JSON.stringify({ supplier_id: Number(subj.leadId), email: subj.email }), QD_E2E_SECRET: await internalCred(), QD_SECRET_EXTRACT: extract });
} finally {
  await write(`update public.rehearsal_window set models_allowed = false where run_tag = ${q('qd_run:' + run.tag)}`, 'qualification window: models off').catch(() => {});
  const spend = (await read(`select count(*)::int calls, coalesce(sum(cost_aed), 0)::numeric(12,4) aed from public.ai_cost_log where e2e_run_tag = ${q(run.tag)}`))[0];
  console.log(`SPEND ${label}: ${JSON.stringify(spend)} (AED; USD = AED / 3.6725)`);
  writeFileSync(join(OUT, `spend_${label}.json`), JSON.stringify({ run_tag: run.tag, cap_usd: CAP_USD, ...spend }, null, 1));
  const t = await teardown(run);
  console.log(`run ${run.tag} torn down: ${t.summary}`);
  await closeRehearsalWindow(run.tag);
}
