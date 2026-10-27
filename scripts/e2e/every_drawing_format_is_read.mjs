// scripts/e2e/every_drawing_format_is_read.mjs — every CAD format a customer sends, through the live
// customer_api, ON PRODUCTION with a ZZ DEMO customer only. Assigned: sales_engineer (founder instructions
// 31/63/64/696, and 22 Sep 2026: "customer will share cad files or pdf mainly").
//
// WHAT IT WALKS, the way the portal sends each file (NewRequest.tsx: .dwg -> analyze_drawing, the rest of
// the CAD family -> analyze_document):
//   ASCII DXF and BINARY DXF of the same synthetic plan -> the same take-off (cad.fixtures.ts);
//   a small DWG (LibreDWG's sample_2000.dwg) -> read on the edge (it died "Memory limit exceeded" until
//     dwg.ts lowered the .wasm's 1 GB memory floor);
//   a 2.1 MB DWG (LibreDWG's 2018/Dynblocks.dwg) -> queued (cad_queued), read by the CAD worker, fetched
//     with cad_read_status. The worker is started by customer_api's dispatch; --run-worker also runs it
//     here (needed before the workflow is on main, and harmless after: SKIP LOCKED);
//   a Revit model, an IFC and a DGN V7 -> REFUSED: founder ruling 1000 (28 Sep 2026), drawings are PDF,
//     DWG and DXF only; none of them is read or stored.
// The DWG samples are LibreDWG test data, fetched at run time at a pinned commit and checked by hash;
// nothing is committed. Everything the run made is torn down and the teardown is proved.
//
//   node scripts/e2e/every_drawing_format_is_read.mjs [--run-worker] [--keep]
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { openRun, closeRun, leftovers, makeDemoCustomer, read, write, call } from './fixtures.mjs';
import { dxfBinaryFrom, dxfFixture, dxfFixturePairs } from '../../supabase/functions/_shared/doc_read/cad.fixtures.ts';
import { boqNoteAr } from '../../src/lib/boqNotes.ts';
import { cadRedactionShape } from './cad_redacted_paths.mjs';
import { CFB } from '../../supabase/functions/_shared/vendor/sheetjs-0.20.3/xlsx.mjs';

const KEEP = process.argv.includes('--keep');
const RUN_WORKER = process.argv.includes('--run-worker');
const results = [];
const check = (name, ok, detail = '') => { results.push({ name, ok: !!ok, detail }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' - ' + detail : ''}`); return !!ok; };
const LIBREDWG = 'https://raw.githubusercontent.com/LibreDWG/libredwg/34f02f54b9aacb5708c1d3d2070efb3e4b2d8c43/test/test-data/';
async function sample(name, sha16) {
  const b = Buffer.from(await (await fetch(LIBREDWG + name)).arrayBuffer());
  if (createHash('sha256').update(b).digest('hex').slice(0, 16) !== sha16) throw new Error(`${name} is not the pinned file`);
  return b;
}
const u16 = (s) => Buffer.from(s, 'utf16le');
function ole(streams) { const c = CFB.utils.cfb_new(); for (const [p, b] of Object.entries(streams)) CFB.utils.cfb_add(c, '/' + p, b); return Buffer.from(CFB.write(c, { type: 'array' })); }
const allArabic = (notes) => (notes || []).every((n) => /[؀-ۿ]/.test(boqNoteAr(n) || ''));
const lines = (r) => r.json?.boq?.boq || [];

const run = await openRun();
let exitCode = 1;
let custId = null;
try {
  const cust = await makeDemoCustomer(run, { label: 'Formats' });
  custId = cust.customerId;
  check('a ZZ DEMO customer with a complete account', !!cust.customerId, cust.email);
  const doc = (buf, file_name) => call('customer_api', cust.jwt, { action: 'analyze_document', file_b64: buf.toString('base64'), mime: '', file_name, hint: 'ZZ DEMO fit-out' }, 150000);
  const drawing = (buf, name) => call('customer_api', cust.jwt, { action: 'analyze_drawing', images: [], original_b64: buf.toString('base64'), mime: '', drawing_file_name: name, hint: 'ZZ DEMO fit-out' }, 280000);

  // DXF, ASCII and binary: the same plan must give the same lines.
  const asc = await doc(Buffer.from(dxfFixture()), 'ZZ DEMO plan.dxf');
  const bin = await doc(Buffer.from(dxfBinaryFrom(dxfFixturePairs())), 'ZZ DEMO plan binary.dxf');
  const shape = (r) => JSON.stringify(lines(r).map((l) => [l.description, l.qty, l.unit]));
  check('ASCII DXF is taken off', asc.json?.ok && lines(asc).length > 0, `HTTP ${asc.status}, ${lines(asc).length} lines`);
  check('BINARY DXF gives the same take-off as its ASCII twin', bin.json?.ok && shape(bin) === shape(asc) && lines(bin).length > 0, `HTTP ${bin.status}, ${lines(bin).length} lines, ${bin.json?.error || ''}`);
  check('the binary DXF says how it was read, in Arabic too', (bin.json?.boq?.missing_info || []).some((n) => /^Read from binary DXF/.test(n)) && allArabic(bin.json?.boq?.missing_info), (bin.json?.boq?.missing_info || [])[0] || '');

  // DWG, small: read on the edge.
  const small = await drawing(await sample('sample_2000.dwg', '4b8d9b1396a6d0de'), 'ZZ DEMO small.dwg');
  check('a small DWG is read on the edge (not 546)', small.json?.ok && lines(small).length > 0, `HTTP ${small.status}, ${lines(small).length} lines`);
  // 24 Sep 2026: and DRAWN for suppliers from its own entities, identity left out (drawing_redact mode 'cad').
  // Since #1056 the anonymised DXF rides beside the preview, so 1 or 2 recorded paths (cad_redacted_paths.mjs).
  const smallShape = cadRedactionShape(small.json?.drawing_redacted_paths);
  check('the small DWG is drawn for suppliers: one recorded redacted preview page (plus its anonymised file), not held', small.json?.redaction_complete === true && smallShape.ok && small.json?.drawing_held === false,
    `redaction_complete ${small.json?.redaction_complete}, ${smallShape.detail}, held ${small.json?.drawing_held}, note ${small.json?.note}`);

  // DWG, large: queued, read by the worker, fetched by the customer.
  const bigBytes = await sample('2018/Dynblocks.dwg', '95cc558d02a2596d');
  const big = await drawing(bigBytes, 'ZZ DEMO large.dwg');
  const job = big.json?.cad_job_id;
  check('a 2.1 MB DWG is queued, not refused', big.json?.ok && big.json?.note === 'cad_queued' && !!job, `HTTP ${big.status}, note ${big.json?.note}, ${big.json?.error || ''}`);
  if (job) {
    const [row] = await read(`select why, status, bytes from public.cad_read_jobs where id = '${job}'`);
    check('the job row names why it was queued', !!row, JSON.stringify(row));
    if (RUN_WORKER) {
      const w = spawnSync('deno', ['run', '--no-lock', '--node-modules-dir=auto', '--allow-net', '--allow-env', '--allow-read', 'scripts/cad_read_worker.ts'], { encoding: 'utf8', timeout: 600000 });
      console.log('INFO  worker:', (w.stdout || '').trim().split('\n').filter((l) => !/peer|resolved|Learn more|──/.test(l)).join(' | '));
    }
    let st = null; const t0 = Date.now();
    // 4 minutes, not 10 (18 Oct 2026): 60 x 10 s of polling plus the run's calls and teardown passed the parent's
    // 12-minute ceiling (drawing_journeys_into_report PER_SCRIPT_MS), the process was SIGTERMed inside its finally and
    // its rehearsal window stayed open every night 13-18 Oct. A job the worker has not taken in 4 minutes is the finding.
    for (let i = 0; i < 24 && !(st?.json?.status === 'done' || st?.json?.status === 'failed'); i++) {
      if (i) await new Promise((r) => setTimeout(r, 10000));
      st = await call('customer_api', cust.jwt, { action: 'cad_read_status', job_id: job });
    }
    const n = st?.json?.boq?.boq?.length || 0;
    check('the CAD worker read it and the customer receives the take-off', st?.json?.status === 'done' && n > 0, `status ${st?.json?.status} after ${Math.round((Date.now() - t0) / 1000)} s, ${n} lines`);
    const other = await call('customer_api', null, { action: 'cad_read_status', job_id: job });
    check('nobody else can read the job', other.status === 401 || other.status === 403 || other.status === 404 || other.json?.ok !== true, `HTTP ${other.status}`);
  }

  // Founder ruling 1000 (28 Sep 2026): Revit, IFC and DGN are never accepted.
  const rvt = ole({ BasicFileInfo: Buffer.concat([Buffer.from([7]), u16('Worksharing: Not enabled\r\nFormat: 2024\r\n')]), ProjectInformation: Buffer.alloc(8) });
  const ifc = Buffer.from("ISO-10303-21;\nHEADER;\nFILE_NAME('zz-demo.ifc','2026-09-28',('ZZ DEMO'),('ZZ DEMO'),'','','');\nENDSEC;\nDATA;\nENDSEC;\nEND-ISO-10303-21;\n");
  const v7 = Buffer.alloc(2048); v7.set([0x08, 0x09, 0xfe, 0x02]);
  for (const [buf, name] of [[rvt, 'ZZ DEMO villa.rvt'], [ifc, 'ZZ DEMO villa.ifc'], [v7, 'ZZ DEMO site.dgn']]) {
    const x = await doc(buf, name);
    check(`${name.split('.').pop().toUpperCase()} is refused, not read or stored`, x.json?.ok !== true && !x.json?.drawing_file_path, `HTTP ${x.status} ${x.json?.error || ''}`);
  }

  exitCode = results.every((x) => x.ok) ? 0 : 1;
} catch (e) {
  check('the run finished', false, String(e?.stack || e).slice(0, 400));
} finally {
  if (custId && !KEEP) await write(`delete from public.cad_read_jobs where customer_id = '${custId}'`, 'e2e cad jobs').catch((e) => console.log('INFO  cad_read_jobs not cleared:', String(e?.message || e).slice(0, 120)));
  try { await closeRun(run, { keep: KEEP }); } catch (e) { console.log(`teardown throttled (${e?.status || e}); retrying in 60 s`); await new Promise((r) => setTimeout(r, 60000)); await closeRun(run, { keep: KEEP }); }
  if (!KEEP) {
    const left = await leftovers(run);
    const jobs = custId ? (await read(`select count(*)::int n from public.cad_read_jobs where customer_id = '${custId}'`).catch(() => [{ n: 0 }]))[0].n : 0;
    check('teardown left nothing behind', left.total === 0 && !jobs, JSON.stringify({ ...left, cad_read_jobs: jobs }));
    if (left.total || jobs) exitCode = 1;
  }
  console.log(`\n${results.filter((x) => x.ok).length}/${results.length} checks passed`);
  process.exit(exitCode);
}
