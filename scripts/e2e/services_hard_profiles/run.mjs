#!/usr/bin/env node
// THE HARD-PROFILE SET, RUN AGAINST THE SUPPLIER READER (sales_engineer, 12 Nov 2026; founder rulings 1647, 1627, 1628;
// docs/reports/2026-11-12-supplier-service-profiling.md, Parts 2 and 3.11). Twelve invented ZZ DEMO companies (thirteen files:
// H08 also as Word) whose answer keys were written before any reading (answer_keys.json, ANSWER_KEYS.md).
//
//   node scripts/e2e/services_hard_profiles/run.mjs plan [--runs 2] [--only H01]   expected cost and the pass bar (no network)
//   node scripts/e2e/services_hard_profiles/run.mjs read --dir <pdfs>              code reads the files into text (USD 0, no model)
//   node scripts/e2e/services_hard_profiles/run.mjs run --dir <pdfs> --paid --cap-usd 0.15 [--runs 1] [--only H01] [--out <json>] 
//                                                                                the real reader through the deployed ai_gateway
//   node scripts/e2e/services_hard_profiles/score.mjs <out.json>                 the scores against the answer keys
// The PDFs come from make_profiles.mjs --out <pdfs> (generated, never committed).
//
// SPENDS ONLY WITH --paid AND UNDER A CAP, the pattern of scripts/eval/prompt_diet_eval.mjs: `run` refuses without --paid, refuses a cap
// above CAP_USD, opens THIS run's own tagged rehearsal window with models allowed for the tag only and the cap enforced by the database
// (rehearsal_window.cap_usd, fn_kernel_paid_provider_gate), and always closes it. INCAPABLE OF REACHING A REAL PERSON: the one committed
// row is a ZZ DEMO subject supplier (qd-<tag>-...@example.invalid, no auth user) that carries the spend, torn down by the run; the
// reader sends nothing and nothing is uploaded (the files are read from disk). Guard: scripts/checks/the_hard_profile_set_is_capped_and_demo_only.test.mjs.
import { readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const HERE = dirname(fileURLToPath(import.meta.url)), REPO = resolve(HERE, '..', '..', '..');
export const KEYS = JSON.parse(readFileSync(join(HERE, 'answer_keys.json'), 'utf8')).profiles;
// USD per reading of one company, MEASURED 12 Nov 2026 on this set (ai_cost_log by e2e_run_tag); planned at 1.5x the measured mean so a
// set with its slow cases is never under-stated. (The deleted reader @4 measured USD 0.178 for 18 readings, 0.0099 each.)
export const USD_PER_READING = { two_step: 0.015 };
// Reader @5 (the two steps, the only reader since 12 Nov 2026; the one-call chooser of @4 that these numbers were first measured on is deleted):
// the prototype measured USD 0.116 for 13 files = 0.009 a company at medium (report 2.4); planned at 1.5x.
// The cap of one run, and of the whole workstream's paid budget (USD 0.60 for both branches of the build, 12 Nov 2026).
export const CAP_USD = 0.40;
export const PASS_BAR = [
  'specific services evidenced in so many words: found (listed or asked) on >= 90% overall and >= 75% on every profile',
  'wrong or absurd proposals (outside the key\'s must, fair and partner lists): 0',
  'partner services proposed as his own: 0; every partner service the documents name is marked as partner',
  'vague profiles (H02, H03, H05, H12): a question is asked, and at least 3 of its options are in the key',
  '"still reading" or "held" as a final state: 0; a trade with no service and no question: 0',
  'the licence-mismatch profile (H11): the garments trades not proposed, the mismatch asked; nothing evidenced from the licence alone',
  'one reading finishes within 110 s; the same list on both runs for >= 85% of keys per profile',
];
export function plan({ runs = 1, only = null, reader = 'two_step' } = {}) {
  const n = KEYS.filter((k) => !only || only.includes(k.id)).length;
  const usd = Math.round(n * runs * USD_PER_READING[reader] * 1e4) / 1e4;
  return { readings: n * runs, usd, cap: CAP_USD };
}

const argv = process.argv.slice(2);
const opt = (k, d = null) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] ?? d : d; };
const mode = argv[0] ?? 'plan';
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
const ONLY = opt('--only')?.split(',') ?? null, RUNS = Number(opt('--runs', '1')), READER = 'two_step';
const stage = (dir, out, extra, env = {}) => spawnSync('deno', ['run', '-A', '--unsafe-proto', '--no-lock', '--node-modules-dir=none', join(HERE, 'read_profiles.ts'), dir, out,
  ...(ONLY ? ['--only', ONLY.join(',')] : []), ...extra], { stdio: 'inherit', cwd: HERE, env: { ...process.env, DENO_NO_PACKAGE_JSON: '1', ...env } });

if (isMain && mode === 'plan') {
  const p = plan({ runs: RUNS, only: ONLY, reader: READER });
  console.log(`HARD-PROFILE SET: ${p.readings} readings, expected USD ${p.usd.toFixed(4)} (cap of one run USD ${CAP_USD.toFixed(2)})`);
  console.log('PASS BAR (all of it, on both runs):'); for (const r of PASS_BAR) console.log('  - ' + r);
  process.exit(p.usd <= CAP_USD ? 0 : 1);
}
if (isMain && (mode === 'read' || mode === 'run')) {
  const dir = opt('--dir'); if (!dir) { console.error('--dir <the folder make_profiles.mjs --out wrote>'); process.exit(2); }
  const out = resolve(opt('--out', join(tmpdir(), `services_hard_profiles_${mode}.json`)));
  if (out.startsWith(REPO + '/')) { console.error('REFUSED: a run\'s answers are evidence, not source; write them outside the repository'); process.exit(2); }
  if (mode === 'read') process.exit(stage(dir, out, []).status ?? 1);
  if (!argv.includes('--paid')) { console.error('REFUSED: this spends money on the model provider. Re-run with --paid in the paid round.'); process.exit(2); }
  const cap = Number(opt('--cap-usd'));
  if (!(cap > 0 && cap <= CAP_USD)) { console.error(`REFUSED: --cap-usd must be in (0, ${CAP_USD}]`); process.exit(2); }
  const p = plan({ runs: RUNS, only: ONLY, reader: READER });
  if (p.usd > cap) { console.error(`REFUSED: the plan (USD ${p.usd.toFixed(4)}) is over the cap (USD ${cap})`); process.exit(2); }
  const lib = (f) => import('../../lib/' + f);
  const { newRun, teardown, makeSupplier, keys, REF, q, closeRehearsalWindow, internalCred } = await lib('demo_factory.mjs');
  const { mgmtRead, mgmtFixture } = await lib('qd_guard.mjs');
  process.env.QD_FIXTURES = '1';
  const read = (sql) => mgmtRead(REF, sql), write = (sql, where) => mgmtFixture(REF, sql, where);
  const run = newRun({ quiet: true });
  console.log(`run ${run.tag}: ${p.readings} readings, plan USD ${p.usd.toFixed(4)}, hard cap USD ${cap} (rehearsal_window.cap_usd)`);
  await write(`insert into public.rehearsal_window (run_tag, opened_by, note) values (${q('qd_run:' + run.tag)}, 'sales_engineer services_hard_profiles/run.mjs', ${q('supplier service profiling: hard-profile set')})`, 'rehearsal window');
  let code = 1;
  try {
    await write(`update public.rehearsal_window set models_allowed = true, cap_usd = ${cap}, expires_at = now() + interval '60 minutes'
                 where run_tag = ${q('qd_run:' + run.tag)} and ended_at is null`, 'hard-profile window: models for this tag only');
    const subj = await makeSupplier(run, { trade: 'aluminium', withAuth: false, capability: false, company_name: `ZZ DEMO hard-profile subject ${run.tag}` });
    const { SERVICE } = await keys();
    code = stage(dir, out, ['--model', '--repeats', String(RUNS)], { SUPABASE_URL: `https://${REF}.supabase.co`, SUPABASE_SERVICE_ROLE_KEY: SERVICE, QD_RUN_TAG: run.tag,
      QD_SUBJECT: JSON.stringify({ supplier_id: Number(subj.leadId), email: subj.email }), QD_E2E_SECRET: await internalCred() }).status ?? 1;
  } finally {
    await write(`update public.rehearsal_window set models_allowed = false where run_tag = ${q('qd_run:' + run.tag)}`, 'hard-profile window: models off').catch(() => {});
    const spend = (await read(`select count(*)::int calls, coalesce(sum(cost_aed), 0)::numeric(12,4) aed, round(avg(latency_ms)) avg_ms, max(latency_ms) max_ms from public.ai_cost_log where e2e_run_tag = ${q(run.tag)}`))[0];
    console.log(`SPEND ${run.tag}: ${JSON.stringify(spend)} (USD = AED / 3.6725 = ${(Number(spend.aed) / 3.6725).toFixed(4)})`);
    writeFileSync(out.replace(/\.json$/, '') + '.spend.json', JSON.stringify({ run_tag: run.tag, cap_usd: cap, ...spend, usd: Number(spend.aed) / 3.6725 }, null, 1));
    const t = await teardown(run);
    console.log(`run ${run.tag} torn down: ${t.summary}`);
    await closeRehearsalWindow(run.tag);
  }
  console.log(`answers -> ${out}`);
  process.exit(code);
}
