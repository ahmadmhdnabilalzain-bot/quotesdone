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
//   a Revit model (an OLE2 compound file built here with a BasicFileInfo and a preview PNG) -> version,
//     preview and the IFC ask, with Arabic for every sentence;
//   a DGN V7 header and a DGN V8 (OLE2 with Bentley's storages) -> recognised, with the export ask.
// The DWG samples are LibreDWG test data, fetched at run time at a pinned commit and checked by hash;
// nothing is committed. Everything the run made is torn down and the teardown is proved.
//
//   node scripts/e2e/every_drawing_format_is_read.mjs [--run-worker] [--keep]
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { openRun, closeRun, leftovers, makeDemoCustomer, read, write, call } from './fixtures.mjs';
import { dxfBinaryFrom, dxfFixture, dxfFixturePairs } from '../../supabase/functions/_shared/doc_read/cad.fixtures.ts';
import { boqNoteAr } from '../../src/lib/boqNotes.ts';
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
function png(w, h) {
  const chunk = (t, d) => { const c = Buffer.alloc(12 + d.length); c.writeUInt32BE(d.length, 0); c.write(t, 4, 'latin1'); d.copy(c, 8); return c; };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', Buffer.alloc(0)), chunk('IEND', Buffer.alloc(0))]);
}
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
  check('a small DWG is read on the edge (not 546)', small.json?.ok && small.json?.note === 'cad_read_not_pictured' && small.json?.drawing_held === true && lines(small).length > 0, `HTTP ${small.status}, note ${small.json?.note}, held ${small.json?.drawing_held}, ${lines(small).length} lines`);

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
    for (let i = 0; i < 60 && !(st?.json?.status === 'done' || st?.json?.status === 'failed'); i++) {
      if (i) await new Promise((r) => setTimeout(r, 10000));
      st = await call('customer_api', cust.jwt, { action: 'cad_read_status', job_id: job });
    }
    const n = st?.json?.boq?.boq?.length || 0;
    check('the CAD worker read it and the customer receives the take-off', st?.json?.status === 'done' && n > 0, `status ${st?.json?.status} after ${Math.round((Date.now() - t0) / 1000)} s, ${n} lines`);
    const other = await call('customer_api', null, { action: 'cad_read_status', job_id: job });
    check('nobody else can read the job', other.status === 401 || other.status === 403 || other.status === 404 || other.json?.ok !== true, `HTTP ${other.status}`);
  }

  // Revit: what is certain, and the IFC ask.
  const rvt = ole({ BasicFileInfo: Buffer.concat([Buffer.from([7]), u16('Worksharing: Not enabled\r\nUsername: zz.demo\r\nFormat: 2024\r\nBuild: 20240111_1515(x64)\r\nLast Save Path: C:\\ZZ DEMO\\Villa.rvt\r\n')]),
    'RevitPreview4.0': Buffer.concat([Buffer.alloc(300, 0x19), png(128, 96)]), ProjectInformation: Buffer.alloc(8) });
  const r = await doc(rvt, 'ZZ DEMO villa.rvt');
  const rn = r.json?.boq?.missing_info || [];
  check('a Revit model is read for its version and preview, and asked for IFC', r.json?.ok && r.json?.needs === 'bim_conversion' && rn.some((n) => n === 'This Revit file was saved in Revit 2024.') && rn.some((n) => /128 x 96 pixel preview/.test(n)) && rn.some((n) => /File > Export > IFC/.test(n)), `HTTP ${r.status} ${r.json?.error || ''} ${rn.join(' | ').slice(0, 200)}`);
  check('no path or user name from the Revit file reaches the customer or a supplier', !/zz\.demo|Villa\.rvt|Save Path/i.test(JSON.stringify(r.json?.boq || {})));
  check('every Revit sentence has its Arabic', rn.length > 0 && allArabic(rn));
  check('the Revit original is stored (held, like every CAD original)', !!r.json?.drawing_file_path, String(r.json?.drawing_file_path || 'not stored'));

  // DGN V7 and V8: recognised, asked for an export.
  const v7 = Buffer.alloc(2048); v7.set([0x08, 0x09, 0xfe, 0x02]);
  const g7 = await doc(v7, 'ZZ DEMO site.dgn');
  const v8 = ole({ 'Dgn~H': Buffer.alloc(64), 'Dgn~S': Buffer.alloc(64) });
  const g8 = await doc(v8, 'ZZ DEMO site v8.dgn');
  const gn = (x) => x.json?.boq?.missing_info || [];
  check('a DGN V7 is recognised and asked for DWG / DXF / PDF', g7.json?.needs === 'cad_conversion' && gn(g7)[0] === 'This is a MicroStation DGN V7 (2D) file.' && allArabic(gn(g7)), `HTTP ${g7.status} ${gn(g7).join(' | ').slice(0, 160)}`);
  check('a DGN V8 is recognised (not read as a spreadsheet) and asked the same', g8.json?.needs === 'cad_conversion' && gn(g8)[0] === 'This is a MicroStation DGN V8 file.' && allArabic(gn(g8)), `HTTP ${g8.status} ${g8.json?.error || ''} ${gn(g8).join(' | ').slice(0, 160)}`);

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
