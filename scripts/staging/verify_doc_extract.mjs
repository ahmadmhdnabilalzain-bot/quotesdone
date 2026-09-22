// verify_doc_extract.mjs — run the document queue that has never run.
//
// doc_extract is a queue drainer over public.documents, pulled by the `doc_process` cron. Staging
// has 0 crons by design, so it had NEVER executed there: 24 documents rows, every one
// status='pending', and 0 agent_runs for the agent. "Wired but never executed" is not the same as
// "works" - §5 of the brief is a list of subsystems that passed a green suite while doing nothing.
//
// The fixture costs ONE model call. A real object goes into drawing-files, an inquiry is created
// carrying its path, and `trg_reg_inquiry_doc` registers the documents row through the real
// trigger - so the queue entry arrives the way a customer's upload would, with no model call at
// all. Only the extraction itself is billed.
//
// It also measures the output against doc_extract's `max:2000` ceiling. Four separate defects in
// sessions 7-8 were a token cap sitting inside the output's natural range, failing about one run in
// three and reading exactly like model flakiness.
//
//     node scripts/staging/verify_doc_extract.mjs
import { mgmtRead } from '../lib/qd_guard.mjs';
import { REF, withRun, makeCustomer, makeInquiry, uploadObject, call, q } from '../lib/demo_factory.mjs';
import { readFileSync } from 'node:fs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(46)} ${detail}`);
};

await withRun(async (run) => {
  const cred = (await mgmtRead(REF,
    "select value from public.app_secrets where key='cred_cron_documents'"))[0]?.value;
  step('a credential scopes doc_extract', !!cred,
    cred ? 'cred_cron_documents (context cron.documents)' : 'no credential in staging scopes doc_extract');
  if (!cred) return;

  // A real drawing, in the real bucket, registered by the real trigger.
  const png = readFileSync(new URL('./fixtures/drawing_windows.png', import.meta.url));
  const path = `drawings/demo-${run.tag}/west_elevation_windows.png`;
  await uploadObject('drawing-files', path, png, 'image/png');

  const cust = await makeCustomer(run, { mode: 'sql' });
  const inq = await makeInquiry(run, {
    customer: cust, trade: 'aluminium',
    drawing_file_path: path, drawing_file_name: 'west_elevation_windows.png',
  });

  const doc = (await mgmtRead(REF,
    `select id, bucket, path, kind, status, attempts from public.documents
      where ref_table='inquiries' and ref_id=${q(inq.id)}`))[0];
  step('the upload registers a queue entry through the real trigger',
    !!doc && doc.kind === 'drawing' && doc.status === 'pending' && doc.bucket === 'drawing-files',
    doc ? `documents #${doc.id} ${doc.bucket}/${doc.path} kind=${doc.kind} status=${doc.status}`
        : 'trg_reg_inquiry_doc registered nothing');
  if (!doc) return;

  const before = Number((await mgmtRead(REF,
    "select count(*)::int n from public.agent_runs where agent='doc_extract'"))[0].n);

  const r = await call('doc_extract', null, { __secret: cred, document_id: doc.id }, 180000);
  step('doc_extract accepts the job', r.status === 200 && r.json?.error === undefined,
    `HTTP ${r.status} ${r.text}`);

  const after = (await mgmtRead(REF, `
    select status, attempts, error,
           length(coalesce(extracted::text,'')) extracted_len,
           coalesce(extracted->>'text','') txt,
           coalesce(jsonb_array_length(extracted->'specifications'),0) specs,
           coalesce(jsonb_array_length(extracted->'quantities'),0) quantities,
           indexed
      from public.documents where id=${doc.id}`))[0] || {};
  step('the document is marked done, not left pending',
    after.status === 'done' && !after.error,
    `status=${after.status} attempts=${after.attempts} error=${after.error ?? 'none'}`);

  // ok:true with an empty payload is the failure mode this whole suite exists to catch:
  // quote_extract returned a fully-formed but entirely empty proposal for exactly this reason.
  step('the extraction carries real content, not an empty shell',
    Number(after.extracted_len) > 80 && String(after.txt).trim().length > 40,
    `extracted ${after.extracted_len} chars, text ${String(after.txt).trim().length} chars, ` +
    `${after.specs} specification(s), ${after.quantities} quantity(ies)`);

  const runs = Number((await mgmtRead(REF,
    "select count(*)::int n from public.agent_runs where agent='doc_extract'"))[0].n);
  step('the run is recorded in agent_runs', runs > before,
    `agent_runs for doc_extract ${before} -> ${runs}`);

  // The ceiling. doc_extract asks ai_gateway for max:2000; ai_gateway also reports finish_reason and
  // truncated, and logs TRUNCATED: with the ceiling and task class when it trips.
  const cost = (await mgmtRead(REF, `
    select model_used, prompt_tokens, output_tokens, cost_aed, task_class, ok
      from public.ai_cost_log where fn='doc_extract' order by occurred_at desc limit 1`))[0];
  // The ceiling is now whatever the task class says, because doc_extract no longer passes its own
  // `max` - ai_gateway computes min(body.max ?? policy, policy), so a caller-supplied max could
  // only ever lower it. Read the live policy rather than hard-coding a number that will rot.
  const CEILING = Number((await mgmtRead(REF,
    "select max_tokens from public.model_policy where task_class='document_extraction'"))[0]?.max_tokens ?? 0);
  const out = Number(cost?.output_tokens ?? 0);
  step(`output sits clear of the ${CEILING}-token task-class ceiling`,
    !!cost && out > 0 && CEILING > 0 && out < CEILING * 0.8,
    cost ? `${cost.model_used} ${cost.prompt_tokens}+${out} tokens ` +
           `(${Math.round(100 * out / CEILING)}% of ${CEILING}), cost ${cost.cost_aed} AED. ` +
           'The old caller-side max:2000 sat BELOW this natural output and returned extraction_null'
         : 'no ai_cost_log row for doc_extract');
});

const pass = checks.filter((c) => c.ok).length;
console.log(`\nDOC EXTRACT ${pass}/${checks.length} on ${REF}`);
process.exitCode = pass === checks.length ? 0 : 1;
