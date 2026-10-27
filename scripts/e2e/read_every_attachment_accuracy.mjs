// scripts/e2e/read_every_attachment_accuracy.mjs — measures ruling 1177 ("it should always read") on a ZZ DEMO sample.
// Assigned: sales_engineer + customer_support (reading), it_engineer (harness). Modelled on document_intake_accuracy.mjs.
//
// 1. corpus      read_every_attachment_corpus.mjs: 8 invented ZZ DEMO files, one deliberately degraded.
// 2. code only   every file through the real readers with NO model: what production read before the ruling.
// 3. model       the same, with the vision model, inside THIS run's own tagged rehearsal window (models_allowed,
//                cap_usd <= 4, enforced by fn_kernel_paid_provider_gate) for one ZZ DEMO subject supplier the run
//                creates (qd-<tag>-…@example.invalid, no auth user). Untagged traffic keeps the founder's hold.
// 4. teardown    models off, spend read from ai_cost_log by tag, the subject torn down, the window closed.
// Nothing real is read, written or contacted. Results: <out>/READ_EVERY_ATTACHMENT_RESULTS.{json,md}.
//
//   node scripts/e2e/read_every_attachment_accuracy.mjs [--cap-usd 2] [--no-model] [--out <dir>]
import { SANDBOX_OUT } from '../lib/sandbox_out.mjs';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { newRun, teardown, makeSupplier, keys, REF, q, closeRehearsalWindow, internalCred } from '../lib/demo_factory.mjs';
import { mgmtRead, mgmtFixture } from '../lib/qd_guard.mjs';
import { buildCorpus } from './read_every_attachment_corpus.mjs';

const argv = process.argv.slice(2);
const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };
const CAP_USD = Number(val('--cap-usd') || 2);
if (!(CAP_USD > 0 && CAP_USD <= 4)) { console.error('REFUSED: --cap-usd must be in (0, 4]'); process.exit(2); }
const HERE = dirname(fileURLToPath(import.meta.url)), REPO = resolve(HERE, '..', '..');
const OUT = val('--out') || join(SANDBOX_OUT, 'documents');
const WORK = join(OUT, 'run-read-every-attachment');
mkdirSync(WORK, { recursive: true });
process.env.QD_FIXTURES = '1';
const read = (sql) => mgmtRead(REF, sql);
const write = (sql, where) => mgmtFixture(REF, sql, where);
const deno = (args, env) => {
  const r = spawnSync('deno', ['run', '-A', join(REPO, 'scripts', 'e2e', 'read_every_attachment_read.ts'), ...args], { stdio: 'inherit', env: { ...process.env, ...env }, cwd: REPO });
  if (r.status !== 0) throw new Error(`read_every_attachment_read.ts exited ${r.status}`);
};

const corpus = join(WORK, 'corpus');
const docs = await buildCorpus(corpus);
console.log(`corpus: ${docs.length} ZZ DEMO documents in ${corpus}`);
const { SERVICE } = await keys();
const SB = { SUPABASE_URL: `https://${REF}.supabase.co`, SUPABASE_SERVICE_ROLE_KEY: SERVICE };
deno([corpus, join(WORK, 'code_only.json'), 'none'], SB);

let spend = null, runTag = null;
if (!argv.includes('--no-model')) {
  console.log(`model stage: at most ${docs.length * 2 + 4} vision calls, hard cap USD ${CAP_USD} (fn_kernel_paid_provider_gate)`);
  const run = newRun({ quiet: true });
  runTag = run.tag;
  await write(`insert into public.rehearsal_window (run_tag, opened_by, note) values (${q('qd_run:' + run.tag)}, 'scripts/e2e/read_every_attachment_accuracy.mjs', 'every attachment is read (ruling 1177)')`, 'rehearsal window');
  try {
    await write(`update public.rehearsal_window set models_allowed = true, cap_usd = ${CAP_USD}, expires_at = now() + interval '1 hour'
                 where run_tag = ${q('qd_run:' + run.tag)} and ended_at is null`, 'read-every-attachment window: models for this tag only');
    const subj = await makeSupplier(run, { trade: 'aluminium', withAuth: false, capability: false, company_name: `ZZ DEMO read-every-attachment ${run.tag}` });
    if (!/@example\.invalid$/.test(String(subj.email))) throw new Error('REFUSED: the subject is not a fixture address');
    const secret = (await read(`select value from public.app_secrets where key='cred_fn_ai'`))[0]?.value;
    deno([corpus, join(WORK, 'model.json'), 'model'], { ...SB, QD_RUN_TAG: run.tag, QD_SUBJECT: JSON.stringify({ supplier_id: Number(subj.leadId), email: subj.email }),
      QD_SECRET: secret, QD_E2E_SECRET: await internalCred() });
  } finally {
    await write(`update public.rehearsal_window set models_allowed = false where run_tag = ${q('qd_run:' + run.tag)}`, 'models off').catch(() => {});
    spend = (await read(`select count(*)::int calls, coalesce(sum(cost_aed), 0)::numeric(12,4) aed from public.ai_cost_log where e2e_run_tag = ${q(run.tag)}`))[0];
    const t = await teardown(run);
    console.log(`run ${run.tag} torn down: ${t.summary}`);
    await closeRehearsalWindow(run.tag);
  }
}

const code = JSON.parse(readFileSync(join(WORK, 'code_only.json'), 'utf8'));
let model = null; try { model = JSON.parse(readFileSync(join(WORK, 'model.json'), 'utf8')); } catch { /* --no-model */ }
const rows = (model || code).docs;
const held = rows.filter((d) => d.status !== 'read');
const heldUndegraded = held.filter((d) => !d.degraded);
const wrong = rows.filter((d) => d.status === 'read' && !d.words_ok);
const quotes = rows.filter((d) => 'quote_total' in d);
const result = { ruling: 1177, measured_at: new Date().toISOString(), project: REF, run_tag: runTag, cap_usd: CAP_USD, spend,
  code_only: { read: code.docs.filter((d) => d.status === 'read').length, of: code.docs.length },
  with_model: model ? { read: rows.filter((d) => d.status === 'read').length, of: rows.length, held: held.map((d) => d.id),
    held_not_degraded: heldUndegraded.map((d) => d.id), read_but_words_missing: wrong.map((d) => d.id),
    quote_totals_ok: quotes.filter((d) => d.quote_total_ok).length + '/' + quotes.length, model_calls: model.model_calls } : null,
  target_met: !!model && heldUndegraded.length === 0 && wrong.length === 0 && held.every((d) => d.degraded),
  docs: rows.map((d) => ({ ...d, code_only_status: code.docs.find((c) => c.id === d.id)?.status })) };
writeFileSync(join(OUT, 'READ_EVERY_ATTACHMENT_RESULTS.json'), JSON.stringify(result, null, 1));
const md = ['# Every attachment is read — measured result (ruling 1177)', '',
  `Measured ${result.measured_at} on project ${REF}, rehearsal run \`${runTag || '-'}\`, cap USD ${CAP_USD}. Spend: ${spend ? `${spend.calls} logged call(s), AED ${spend.aed}` : 'none'}.`,
  `Code only (before the ruling): ${result.code_only.read}/${result.code_only.of} read. With the model: ${model ? `${result.with_model.read}/${result.with_model.of} read` : 'not run'}.`,
  `Target (0 held except the deliberately degraded file, every read file carries its words): **${result.target_met ? 'MET' : 'NOT MET'}**.`, '',
  '| file | path | code only | with model | by | attempts | words | quote total |', '|---|---|---|---|---|---|---|---|',
  ...result.docs.map((d) => `| ${d.id}${d.degraded ? ' (degraded on purpose)' : ''} | ${d.path} | ${d.code_only_status} | ${d.status} | ${d.by ?? '-'} | ${d.model_attempts} | ${d.found.length}/${d.must.length} | ${'quote_total' in d ? `${d.quote_total ?? 'none'}${d.quote_total_ok ? ' ✓' : ''}` : ''} |`)];
writeFileSync(join(OUT, 'READ_EVERY_ATTACHMENT_RESULTS.md'), md.join('\n') + '\n');
console.log(md.slice(0, 4).join('\n'));
process.exit(result.target_met || argv.includes('--no-model') ? 0 : 1);
