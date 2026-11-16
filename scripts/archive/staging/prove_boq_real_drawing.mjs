// prove_boq_real_drawing.mjs — drive customer_api analyze_drawing with a REAL construction drawing.
//
// WHY. The BoQ path had only synthetic fixtures. boq_fixture_check grades drawing_boq against
// answers a human wrote, which proves the grader, not the pipeline: nothing had ever taken a
// drawing produced by an actual consultant, rasterised it the way the portal rasterises it, and
// pushed it through analyze_drawing -> drawing_boq + drawing_redact together.
//
// The page images must be produced the way CustomerPortal.fileToImages() produces them, because
// that is what the endpoint receives in production: pdf.js, viewport scale 1.8, first 6 pages only,
// JPEG quality 0.8, base64 without the data: prefix. Any rasteriser will do as long as those four
// numbers hold. Feed the result in as a JSON file:
//
//   [{ "mime": "image/jpeg", "data": "<base64>" }, ...]
//
//   node scripts/archive/staging/prove_boq_real_drawing.mjs <pages.json> [original.pdf] [hint]
//
// Refuses production through qd_guard; the customer is a tagged demo row and is torn down.
import { readFileSync } from 'node:fs';
import { withRun, makeCustomer, call, REF, q } from '../../lib/demo_factory.mjs';
import { mgmtRead } from '../../lib/qd_guard.mjs';

const pagesFile = process.argv[2];
const pdfFile = process.argv[3] || null;
const HINT = process.argv[4] || 'HVAC ductwork and mechanical equipment replacement, Dubai';
if (!pagesFile) { console.error('usage: node scripts/archive/staging/prove_boq_real_drawing.mjs <pages.json> [original.pdf] [hint]'); process.exit(2); }

const images = JSON.parse(readFileSync(pagesFile, 'utf8'));
if (!Array.isArray(images) || !images.length) { console.error('pages.json is not a non-empty array'); process.exit(2); }
const originalB64 = pdfFile ? readFileSync(pdfFile).toString('base64') : null;
const bytes = images.reduce((a, i) => a + (i.data || '').length, 0);
console.log(`drawing: ${images.length} page image(s), ${Math.round(bytes / 1024)} KB of base64` +
  (originalB64 ? `, original ${Math.round(originalB64.length / 1024)} KB` : ', no original attached'));

let failures = 0;
const check = (name, ok, detail) => { if (!ok) failures++; console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`); };

await withRun(async (run) => {
  const cust = await makeCustomer(run, { full_name: 'ZZ DEMO — BoQ drawing proof' });
  console.log(`customer ${cust.email} on ${REF}`);

  const t0 = Date.now();
  const raw = await call('customer_api', cust.jwt, {
    action: 'analyze_drawing',
    images,
    original_b64: originalB64,
    mime: 'application/pdf',
    drawing_file_name: 'ZZ DEMO - mechanical drawing set.pdf',
    hint: HINT,
  }, 240000);
  const secs = ((Date.now() - t0) / 1000).toFixed(1);
  const res = raw.json || {};
  console.log(`analyze_drawing HTTP ${raw.status} in ${secs}s: ${(raw.json ? JSON.stringify(raw.json) : raw.text).slice(0, 400)}`);
  check('analyze_drawing answered 200', raw.status === 200, `HTTP ${raw.status}`);

  const boq = res?.boq?.boq;
  check('analyze_drawing returned a BoQ array', Array.isArray(boq), Array.isArray(boq) ? `${boq.length} line item(s)` : `got ${JSON.stringify(res?.boq)?.slice(0, 160)}`);
  check('BoQ has at least one line item', Array.isArray(boq) && boq.length >= 1);
  check('BoQ classified the drawing', !!(res?.boq?.category || res?.boq?.drawing_type), `category=${res?.boq?.category || '-'} type=${res?.boq?.drawing_type || '-'}`);
  if (Array.isArray(boq)) for (const it of boq.slice(0, 12)) console.log(`   • ${JSON.stringify(it).slice(0, 200)}`);

  if (originalB64) check('the original file was stored', !!res?.drawing_file_path, String(res?.drawing_file_path || 'null'));
  const red = res?.drawing_redacted_paths || [];
  check('redacted pages were produced', Array.isArray(red) && red.length >= 1, `${red.length} page(s)`);

  // The endpoint's own claim is not the proof: read the ledger back. Redaction is batched, so a
  // single upload produces one row PER BATCH and the assertions have to aggregate — reading only
  // the newest row reports the last batch as if it were the whole drawing.
  const runs = await mgmtRead(REF,
    `select coalesce(sum(pages_in),0)::int as pin, coalesce(sum(pages_out),0)::int as pout,
            coalesce(sum(coalesce(array_length(output_paths,1),0)),0)::int as outs, count(*)::int as n
       from public.drawing_redaction_runs
      where customer_id = ${q(cust.customerId)} and status <> 'original_stored'`);
  const r0 = runs[0];
  check('drawing_redaction_runs recorded the run', !!r0 && r0.n > 0, JSON.stringify(r0 || null));
  check('every page sent was accounted for', !!r0 && Number(r0.pin) === images.length, r0 ? `${r0.pin} of ${images.length}` : '');
  check('the ledger names exactly the pages the caller was given', !!r0 && Number(r0.outs) === red.length, r0 ? `${r0.outs} vs ${red.length}` : '');
  // Not a pass/fail: how much of a real drawing survives the adversarial verifier is the number
  // that decides whether a customer can share a drawing at all.
  console.log(`INFO  redaction yield on a real drawing: ${r0 ? r0.pout : 0}/${images.length} page(s) cleared the verifier`);
});

console.log(failures ? `\nFAILURES: ${failures}` : '\nALL CHECKS PASSED');
process.exit(failures ? 1 : 0);
