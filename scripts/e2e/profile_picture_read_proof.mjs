// scripts/e2e/profile_picture_read_proof.mjs — A SCANNED OR PHOTOGRAPHED COMPANY PROFILE IS READ AND ITS TRADES ARE PROPOSED.
// Assigned: sales_engineer. 2 Nov 2026, founder ledger 1442 ("Is our agent actually reading the company profile and the trade licence").
//
// WHY A SECOND SCRIPT. The browser walk (supplier_profile_read_walk.mjs) drives the DEPLOYED site, whose supplier_portal only sends
// pictures to the model and holds their trades. The change that reads scanned PDFs the way the licence is read, and proposes what a
// picture states, is in this checkout and not deployed (this branch is not merged or applied). So this runs THIS CHECKOUT's reading
// chain against the real model, in the run's own tagged and capped rehearsal window (the same stage document_intake_model.ts runs
// for the accuracy suite): the file goes to license_extract's profile mode as the portal now sends it (a picture as an image, a PDF with no
// text layer as the file, two attempts), the lines it prints become the document's photo_text, and readDocForTrades (supplier_doc_trades.ts,
// this checkout) chooses the trades with the live trade chooser, each proven by a printed line. Exact trade or none.
//
//   node scripts/e2e/profile_picture_read_proof.mjs [--json f]      (deno on the path; SUPABASE_ACCESS_TOKEN as every harness)
// Exit 1 when a picture's trades differ from the trades its file states, or when a blank page is given a trade. Budget USD 2 (the window's cap).
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { openRun, closeRun, read, REF } from './fixtures.mjs';
import { makeSupplier, keys, internalCred } from '../lib/demo_factory.mjs';
import { profileCorpus } from './profile_read_corpus.mjs';

const argv = process.argv.slice(2);
const JSON_OUT = argv.includes('--json') ? argv[argv.indexOf('--json') + 1] : '';
const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const TMP = mkdtempSync(join(tmpdir(), 'qd-picproof-'));
const dir = join(TMP, 'prof'); mkdirSync(dir, { recursive: true });
const WANT = ['scanned_pdf', 'photo_png', 'arabic_png', 'blank'];
const files = (await profileCorpus(dir)).filter((c) => WANT.includes(c.id));
const NO_TEXT_LAYER = new Set(['scanned_pdf', 'blank']);   // what the code stage reports for a PDF with no text layer
writeFileSync(join(dir, 'truth.json'), JSON.stringify({ docs: files.map((c) => ({ id: c.id, file: c.name, mime: c.mime, kind: 'profile' })) }));
const codePath = join(TMP, 'code.json');
writeFileSync(codePath, JSON.stringify({ docs: files.map((c) => ({ id: c.id, code: {}, trades: { status: NO_TEXT_LAYER.has(c.id) ? 'needs_ocr' : 'read' } })) }));

const run = await openRun({ capUsd: 2, minutes: 40 });
let rows = [], ok = true, spend = null;
try {
  const subj = await makeSupplier(run, { trade: 'aluminium', withAuth: false, capability: false, company_name: `ZZ DEMO picture proof ${run.tag}` });
  const secret = async (k) => (await read(`select value from public.app_secrets where key='${k}'`))[0]?.value || '';
  const { SERVICE } = await keys();
  const outPath = join(TMP, 'out.json');
  const r = spawnSync('deno', ['run', '-A', '--node-modules-dir=none', join(REPO, 'scripts', 'e2e', 'document_intake_model.ts'), dir, codePath, outPath, 'gateway'], {
    stdio: 'inherit', cwd: REPO,
    env: { ...process.env, SUPABASE_URL: `https://${REF}.supabase.co`, SUPABASE_SERVICE_ROLE_KEY: SERVICE, QD_RUN_TAG: run.tag, QD_SUBJECT: JSON.stringify({ supplier_id: Number(subj.leadId), email: subj.email }),
      QD_SECRET: await secret('cred_fn_ai'), QD_E2E_SECRET: await internalCred(), QD_SECRET_EXTRACT: await secret('cred_fn_supplier_api') } });
  if (r.status !== 0) throw new Error(`document_intake_model.ts exited ${r.status}`);
  const out = JSON.parse(readFileSync(outPath, 'utf8')).docs;
  for (const c of files) {
    const m = out.find((d) => d.id === c.id);
    const got = [...(m?.model_trades || [])].sort(), want = [...c.truth.stated].sort();
    const held = m?.vision_held || [];
    const pass = !!m && m.ok === true && JSON.stringify(got) === JSON.stringify(want) && held.length === 0;
    // the blank page: the model is asked and reads nothing printed, so nothing is proposed (a read that returned no lines is still ok)
    rows.push({ id: c.id, label: c.label, want, got, held, model_read: !!m?.ok, lines: m?.profile?.lines ?? [], error: m?.error ?? null, pass });
    console.log(`${pass ? 'PASS' : 'FAIL'} ${c.id.padEnd(12)} file states [${want.join(', ')}] | proposed [${got.join(', ')}] | model read ${m?.ok ? 'yes' : 'NO ' + (m?.error ?? '')} | held ${held.length} | lines ${JSON.stringify((m?.profile?.lines ?? []).slice(0, 4))}`);
    if (!pass) ok = false;
  }
  // known-bad control: the comparison itself fails for a missing trade and for an invented one
  const cmp = (got, want) => JSON.stringify([...got].sort()) === JSON.stringify([...want].sort());
  const control = !cmp(['flooring'], ['elevators', 'flooring']) && !cmp(['elevators', 'flooring', 'hvac'], ['elevators', 'flooring']) && cmp(['flooring', 'elevators'], ['elevators', 'flooring']);
  console.log(`${control ? 'PASS' : 'FAIL'} control: a missing trade and an invented trade both fail the comparison`);
  if (!control) ok = false;
  spend = (await read(`select coalesce(sum(cost_usd_reported),0)::numeric(10,4) usd, count(*)::int calls from public.ai_cost_log where e2e_run_tag = '${run.tag}'`).catch(() => [{ usd: null }]))[0];
  console.log('model spend', JSON.stringify(spend));
  if (spend.usd !== null && Number(spend.usd) > 2) { console.log('FAIL over the USD 2 budget'); ok = false; }
} finally {
  const c = await closeRun(run, {});
  console.log('teardown:', JSON.stringify(c.leftovers || 'kept'));
}
if (JSON_OUT) writeFileSync(JSON_OUT, JSON.stringify({ run_tag: run.tag, spend, rows }, null, 1));
console.log(`${rows.filter((r) => r.pass).length}/${rows.length} files proposed exactly the trades they state`);
process.exit(ok ? 0 : 1);
