// scripts/e2e/document_intake_accuracy.mjs — the supplier DOCUMENT INTAKE ACCURACY SUITE (ledger 1162).
// Assigned: sales_engineer (supplier verification + matching); it_engineer (the harness).
//
// The founder's gate: "not a single mistake in any trade licence shared by a supplier, nor a company profile or a
// document not read and analysed properly for the cross matching later when customers share inquiries."
//
// One run measures the whole intake on a SYNTHETIC corpus with known truth (document_intake_corpus.mjs):
//   1. CODE    every document through the deployed readers' own modules (document_intake_read.ts): the licence's
//              fields by label, and its / the profile's / the catalogue's trades by exact code or meaning.
//   2. MODEL   (--model deployed|gateway) every licence code could not read completely through the vision model,
//              inside this run's own tagged rehearsal window with models allowed and a database-enforced cap
//              (document_intake_model.ts). Without --model the run measures production as configured today:
//              process_docs's model switch (app_secrets.document_expiry_ai) is off, so a scan gets no model read.
//   3. GATE    the merged reading of each licence written to a ZZ DEMO lead and judged by the REAL
//              public.fn_sales_engineer_verifies_supplier, then
//   4. MATCH   each supplier's proposed trades confirmed and a request in every trade put through the REAL
//              public.fn_match_capability: it must reach exactly the demo suppliers that truly do that trade.
//              Steps 3 and 4 run in ONE transaction that always rolls back (raise with the result): nothing is
//              committed. --gate-sql <file> first replaces routines INSIDE that transaction, so a gate change is
//              measured before it is applied.
//   5. REPORT  per field, per authority, per format, the gate decision and the match, and every failure with its
//              cause, to the founder's Desktop folder (documents\).
//
// INCAPABLE OF REACHING A REAL PERSON: every document is invented ("ZZ DEMO" names, made-up numbers), the only
// committed rows are one ZZ DEMO subject supplier for the model stage (qd-<tag>-…@example.invalid, no auth user),
// torn down by the run; the gate and match rows never commit. No message is sent: notifications queued by triggers
// inside the rolled-back transaction roll back with it.
//
//   node scripts/e2e/document_intake_accuracy.mjs [--model deployed|gateway] [--cap-usd 4] [--gate-sql f.sql ...]
//        [--out <dir>] [--label <name>] [--reuse-code <code.json>] [--reuse-model <model.json>]
import { mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { newRun, teardown, makeSupplier, keys, REF, q, demoMobile, closeRehearsalWindow, internalCred } from '../lib/demo_factory.mjs';
import { mgmtRead, mgmtFixture } from '../lib/qd_guard.mjs';
import { buildCorpus } from './document_intake_corpus.mjs';
import { scoreRun, renderReport } from './document_intake_score.mjs';

const argv = process.argv.slice(2);
const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };
const vals = (f) => argv.flatMap((a, i) => (a === f ? [argv[i + 1]] : []));
const MODEL = val('--model');
if (MODEL && !['deployed', 'gateway'].includes(MODEL)) { console.error('--model deployed|gateway'); process.exit(2); }
const CAP_USD = Number(val('--cap-usd') || 4);
if (!(CAP_USD > 0 && CAP_USD <= 5)) { console.error('REFUSED: --cap-usd must be in (0, 5]'); process.exit(2); }
const LABEL = val('--label') || (MODEL ? `model-${MODEL}` : 'code-only');
const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..');
const OUT = val('--out') || 'C:\\Users\\Opera\\Desktop\\QuotesDone Sandbox Test 2026-10\\documents';
const WORK = join(OUT, `run-${LABEL}`);
mkdirSync(WORK, { recursive: true });
process.env.QD_FIXTURES = '1';
const read = (sql) => mgmtRead(REF, sql);
const write = (sql, where) => mgmtFixture(REF, sql, where);

function deno(script, args, env = {}) {
  const r = spawnSync('deno', ['run', '-A', join(REPO, 'scripts', 'e2e', script), ...args],
    { stdio: 'inherit', env: { ...process.env, ...env }, cwd: REPO });
  if (r.status !== 0) throw new Error(`${script} exited ${r.status}`);
}

// ── 1. corpus + code ───────────────────────────────────────────────────────────────────────────────
const corpusDir = join(WORK, 'corpus');
const docs = await buildCorpus(corpusDir);
console.log(`corpus: ${docs.length} documents in ${corpusDir}`);
const { SERVICE } = await keys();
const SB = { SUPABASE_URL: `https://${REF}.supabase.co`, SUPABASE_SERVICE_ROLE_KEY: SERVICE };
const codePath = join(WORK, 'code.json');
if (val('--reuse-code')) writeFileSync(codePath, readFileSync(val('--reuse-code')));
else deno('document_intake_read.ts', [corpusDir, codePath], SB);
const code = JSON.parse(readFileSync(codePath, 'utf8'));

// ── 2. model, inside this run's own tagged window ────────────────────────────────────────────────────
let model = { via: null, docs: [] }, spend = null, runTag = null;
const modelPath = join(WORK, 'model.json');
if (!MODEL && !val('--reuse-model')) { deno('document_intake_model.ts', [corpusDir, codePath, modelPath, 'none'], SB); model = JSON.parse(readFileSync(modelPath, 'utf8')); }
else if (val('--reuse-model')) { writeFileSync(modelPath, readFileSync(val('--reuse-model'))); model = JSON.parse(readFileSync(modelPath, 'utf8')); }
else if (MODEL) {
  // Estimate first (the founder: quote the spend before running when it can exceed USD 5). Measured price of the
  // route's model is not in the repo, so the estimate is the cap, and the database enforces the cap.
  const asked = code.docs.filter((d) => d.code && docs.find((x) => x.id === d.id)?.kind === 'licence').length;
  console.log(`model stage: at most ${asked} licence reads, hard cap USD ${CAP_USD} (fn_kernel_paid_provider_gate)`);
  const run = newRun({ quiet: true });
  runTag = run.tag;
  await write(`insert into public.rehearsal_window (run_tag, opened_by, note) values (${q('qd_run:' + run.tag)}, 'scripts/e2e/document_intake_accuracy.mjs', 'document intake accuracy suite (ledger 1162)')`, 'rehearsal window');
  try {
    await write(`update public.rehearsal_window set models_allowed = true, cap_usd = ${CAP_USD}, expires_at = now() + interval '2 hours'
                 where run_tag = ${q('qd_run:' + run.tag)} and ended_at is null`, 'accuracy window: models for this tag only');
    const subj = await makeSupplier(run, { trade: 'aluminium', withAuth: false, capability: false, company_name: `ZZ DEMO accuracy subject ${run.tag}` });
    const secret = MODEL === 'deployed'
      ? (await read(`select value from public.app_secrets where key='cred_fn_supplier_api'`))[0]?.value
      : (await read(`select value from public.app_secrets where key='cred_fn_ai'`))[0]?.value;
    deno('document_intake_model.ts', [corpusDir, codePath, modelPath, MODEL],
      { ...SB, QD_RUN_TAG: run.tag, QD_SUBJECT: JSON.stringify({ supplier_id: Number(subj.leadId), email: subj.email }), QD_SECRET: secret, QD_E2E_SECRET: await internalCred(),
        QD_SECRET_EXTRACT: (await read(`select value from public.app_secrets where key='cred_fn_supplier_api'`))[0]?.value || '' });
    model = JSON.parse(readFileSync(modelPath, 'utf8'));
  } finally {
    await write(`update public.rehearsal_window set models_allowed = false where run_tag = ${q('qd_run:' + run.tag)}`, 'accuracy window: models off').catch(() => {});
    spend = (await read(`select count(*)::int calls, coalesce(sum(cost_aed), 0)::numeric(12,4) aed from public.ai_cost_log where e2e_run_tag = ${q(run.tag)}`))[0];
    const t = await teardown(run);
    console.log(`run ${run.tag} torn down: ${t.summary}`);
    await closeRehearsalWindow(run.tag);
  }
}

// ── 3 + 4. gate and match, one transaction that always rolls back ──────────────────────────────────────
const MERGE = await import('./document_intake_score.mjs');
const merged = MERGE.mergedReads(docs, code, model);
const gateSql = vals('--gate-sql').map((f) => readFileSync(resolve(REPO, f), 'utf8'));
const tag = (runTag || 'acc' + Date.now().toString(36).slice(-6)).toLowerCase();
const roles = ['contractor', 'installer', 'supplier'];
const arr = (a) => `array[${a.map(q).join(',')}]::text[]`;
let body = '';
const supplierDocs = docs.filter((d) => ['licence', 'profile', 'catalogue'].includes(d.kind));
supplierDocs.forEach((d, i) => {
  const m = merged[d.id];
  const lic = d.kind === 'licence' ? (d.file ? `licenses/zzdemo-accuracy-${tag}/${d.id}` : null) : `licenses/zzdemo-accuracy-${tag}/${d.id}-licence`;
  const prof = `profiles/zzdemo-accuracy-${tag}/${d.id}`;
  // A profile or catalogue supplier holds a valid licence read in full: only its trades are under test.
  const name = d.registered_name, licName = d.kind === 'licence' ? m.legal_name_en : name;
  const expiry = d.kind === 'licence' ? m.expiry_date : '2028-12-31', no = d.kind === 'licence' ? m.licence_no : `ZZACC-${i}`;
  body += `
  ${lic ? `insert into storage.objects (bucket_id, name) values ('supplier-docs', ${q(lic)});` : ''}
  insert into storage.objects (bucket_id, name) values ('supplier-docs', ${q(prof)});
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (${d.start_approved ? "'approved', true" : 'null, false'}, ${q(name)}, ${q(`qd-${tag}-acc${i}@example.invalid`)}, ${q(demoMobile())}, true, true, now(), ${q(`terms/zzdemo-accuracy-${tag}/${d.id}.pdf`)},
          ${lic ? q(lic) : 'null'}, ${q(prof)}, ${licName ? q(licName) : 'null'}, ${expiry ? q(expiry) + '::date' : 'null'}, ${no ? q('ZZACC-' + tag + '-' + no) : 'null'},
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', ${q('qd_run:' + tag)}]::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  ${m.trades.length ? `insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, ${arr(m.trades)}, ${arr(roles)}, '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(${arr(m.trades)})), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);` : ''}
  res := res || jsonb_build_object('id', ${q(d.id)}, 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));`;
});
const allTrades = [...new Set(supplierDocs.flatMap((d) => d.truth.trades || []).concat(Object.values(merged).flatMap((m) => m.trades)))].sort();
const sql = `do $probe$
declare lid bigint; v jsonb; ids bigint[] := '{}'; res jsonb := '[]'; mt jsonb := '{}';
begin
  ${gateSql.map((s) => `execute ${q(s)};`).join('\n  ')}
  ${body}
  ${allTrades.map((t) => `mt := mt || jsonb_build_object(${q(t)}, (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array[${q(t)}], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));`).join('\n  ')}
  raise exception 'CHK<<%>>', jsonb_build_object('gate', res, 'match', mt)::text;
end $probe$;`;
writeFileSync(join(WORK, 'probe.sql'), sql);
let probe;
try { await write(sql, 'document intake accuracy probe (always rolls back)'); throw new Error('the probe did not raise: refusing to trust a committed probe'); }
catch (e) {
  let msg = String(e.message || e); try { msg = JSON.parse(e.body).message; } catch { /* not a JSON body */ }
  const m = /CHK<<([\s\S]*)>>/.exec(msg);
  if (!m) { writeFileSync(join(WORK, 'probe_error.txt'), String(e.body || e.message || e)); throw e; }
  probe = JSON.parse(m[1]);
}
// Nothing may have survived: the tag's leads, capabilities and storage rows are counted after the rollback.
const left = (await read(`select (select count(*) from public.leads where tags @> array[${q('qd_run:' + tag)}]::text[])::int leads,
  (select count(*) from storage.objects where name like ${q('%zzdemo-accuracy-' + tag + '%')})::int objects`))[0];

// ── 5. score + report ──────────────────────────────────────────────────────────────────────────────
const result = scoreRun({ docs, code, model, merged, probe, label: LABEL, spend, gateSql: vals('--gate-sql'), left, runTag: tag });
writeFileSync(join(WORK, 'result.json'), JSON.stringify(result, null, 1));
writeFileSync(join(OUT, `ACCURACY_${LABEL}.md`), renderReport(result));
console.log(renderReport(result).split('\n').slice(0, 40).join('\n'));
console.log(`\nreport: ${join(OUT, `ACCURACY_${LABEL}.md`)}`);
if (left.leads || left.objects) { console.error(`LEFTOVERS after rollback: ${JSON.stringify(left)}`); process.exit(1); }
