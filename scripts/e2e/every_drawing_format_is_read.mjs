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
// THE ELEMENT SCORE PER FORMAT (27 Oct 2026, founder ledger 31: "read drawings in every format ... and understand their
// elements"). A file that is READ is not a file that is UNDERSTOOD, and until then this run only asserted that each format
// gave some lines. Now each format carries elements whose count is known, sent the way the portal sends it, through the
// live customer_api with the run's models ON (ruling 1260), and every element is scored exact or not:
//   DXF ascii / binary   the ZZ DEMO power + fire-alarm plan: SD x7, SKT x5 (legend samples not counted)
//   DWG                  LibreDWG's example_2018.dwg against the take-off of the AutoCAD-written DXF of the same drawing
//   PDF vector           the ZZ DEMO plumbing + HVAC sheet: FD-1 x7, WC-1 x5, FCU-1..3
//   PDF scanned          the same sheet as a speckled, turned raster in a scanner's JPEG PDF, no text layer and no browser
//                        OCR sent: the server routes it to the vision model (ruling 1177)
//   image (PNG / JPEG)   the same raster as a picture, through the same path as the scan (ruling 1177)
// --json <file> writes the per-format score.
//
//   node scripts/e2e/every_drawing_format_is_read.mjs [--run-worker] [--keep] [--json <file>]
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { openRun, closeRun, leftovers, makeDemoCustomer, read, write, call } from './fixtures.mjs';
import { dxfBinaryFrom, dxfFixture, dxfFixturePairs } from '../../supabase/functions/_shared/doc_read/cad.fixtures.ts';
import { boqNoteAr } from '../../src/lib/boqNotes.ts';
import { cadRedactionShape } from './cad_redacted_paths.mjs';
import { rasterise } from './portal_raster.mjs';
import { neutralCadName } from '../../supabase/functions/_shared/cad_identity.ts';
import { CFB } from '../../supabase/functions/_shared/vendor/sheetjs-0.20.3/xlsx.mjs';
import { zzDxf, zzDxfBinary, zzPdfSheet, zzScanRgba, zzScanText, CAD_COUNTS, PDF_COUNTS } from '../../supabase/functions/_shared/doc_read/zz_demo_drawings.fixtures.ts';

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
const JSON_OUT = process.argv.includes('--json') ? process.argv[process.argv.indexOf('--json') + 1] : null;
const SCORE = [];
/** Score one format: per element, the summed quantity of the lines that name it against the known count. */
function score(format, r, truth, how) {
  const ls = lines(r);
  const els = Object.entries(truth).map(([el, { re, qty, unit }]) => {
    const ms = ls.filter((l) => re.test(`${l.item || ''} ${l.description || ''}`) && (!unit || String(l.unit || '').toLowerCase() === unit));
    const read = ms.length ? +ms.reduce((a, l) => a + Number(l.qty ?? l.estimate ?? 0), 0).toFixed(2) : null;
    return { element: el, truth: qty, read, exact: read === qty };
  });
  const row = { format, how, http: r.status, read: r.json?.ok === true && ls.length > 0, lines: ls.length, elements: els,
    exact: `${els.filter((e) => e.exact).length}/${els.length}`, models: r.json?.boq?.author_model || r.json?.boq?.method || null };
  SCORE.push(row);
  if (!els.every((e) => e.exact)) console.log(`INFO  ${format} lines: ${JSON.stringify(ls.map((l) => [l.description, l.qty ?? l.estimate, l.unit])).slice(0, 900)} ${r.json?.error || ''} ${(r.json?.boq?.missing_info || []).join(' | ').slice(0, 300)}`);
  check(`elements understood: ${format} ${row.exact}`, els.every((e) => e.exact), els.map((e) => `${e.element} ${e.read ?? '-'}/${e.truth}`).join(', '));
  return row;
}
/** Score elements that are each ONE line: description (case-insensitive), unit and quantity exact; each line used once. */
function scoreLines(format, r, truth, how) {
  const left = [...lines(r)];
  const els = Object.entries(truth).map(([el, { desc, qty, unit }]) => {
    const i = left.findIndex((l) => String(l.description || '').trim().toLowerCase() === desc.toLowerCase() && String(l.unit || '').toLowerCase() === unit && Number(l.qty ?? l.estimate) === qty);
    return { element: el, truth: qty, read: i >= 0 ? Number(left.splice(i, 1)[0].qty ?? qty) : null, exact: i >= 0 };
  });
  const row = { format, how, http: r.status, read: r.json?.ok === true && lines(r).length > 0, lines: lines(r).length, elements: els,
    exact: `${els.filter((e) => e.exact).length}/${els.length}`, models: r.json?.boq?.author_model || r.json?.boq?.method || null };
  SCORE.push(row);
  if (!els.every((e) => e.exact)) console.log(`INFO  ${format} lines: ${JSON.stringify(lines(r).map((l) => [l.description, l.qty ?? l.estimate, l.unit])).slice(0, 900)}`);
  check(`elements understood: ${format} ${row.exact}`, els.every((e) => e.exact), els.map((e) => `${e.element} ${e.read ?? '-'}/${e.truth} (${truth[e.element].desc})`).join(', '));
  return row;
}
// The ZZ DEMO scan with its tags, as scan_takeoff.check.ts draws it: FD-1 x7, WC-1 x5, FCU-1..3.
const SCAN_FD = [[160, 230], [330, 300], [520, 230], [650, 560], [900, 280], [1100, 560], [1420, 280]];
const SCAN_WC = [[160, 600], [420, 600], [1000, 230], [1200, 600], [1500, 560]];
async function zzScanJpeg() {
  const sharp = (await import('sharp')).default;
  const img = zzScanRgba({ rotateDeg: 0.3, noise: 0.001 });
  for (const [x, y] of SCAN_FD) zzScanText(img, x, y, 26, 'FD-1');
  for (const [x, y] of SCAN_WC) zzScanText(img, x, y, 26, 'WC-1');
  ['FCU-1', 'FCU-2', 'FCU-3'].forEach((f, i) => zzScanText(img, 850 + i * 170, 470, 26, f));
  zzScanText(img, 600, 820, 34, 'GROUND FLOOR PLUMBING AND HVAC PLAN');
  return { w: img.w, h: img.h, jpeg: await sharp(Buffer.from(img.rgba.buffer), { raw: { width: img.w, height: img.h, channels: 4 } }).flatten({ background: '#ffffff' }).jpeg({ quality: 85 }).toBuffer() };
}
/** A scanner's PDF: one JPEG painted over the page, no text layer. */
function jpegPdf({ w, h, jpeg }) {
  const cs = `q ${w} 0 0 ${h} 0 0 cm /Im1 Do Q`;
  const head = '%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    + `3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${w} ${h}] /Resources << /XObject << /Im1 4 0 R >> >> /Contents 5 0 R >>\nendobj\n`
    + `4 0 obj\n<< /Type /XObject /Subtype /Image /Width ${w} /Height ${h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpeg.length} >>\nstream\n`;
  const tail = `\nendstream\nendobj\n5 0 obj\n<< /Length ${cs.length} >>\nstream\n${cs}\nendstream\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n`;
  return Buffer.concat([Buffer.from(head, 'latin1'), jpeg, Buffer.from(tail, 'latin1')]);
}

const run = await openRun();
let exitCode = 1;
let custId = null;
try {
  const cust = await makeDemoCustomer(run, { label: 'Formats' });
  custId = cust.customerId;
  check('a ZZ DEMO customer with a complete account', !!cust.customerId, cust.email);
  const doc = (buf, file_name) => call('customer_api', cust.jwt, { action: 'analyze_document', file_b64: buf.toString('base64'), mime: '', file_name, hint: 'ZZ DEMO fit-out' }, 150000);
  const drawing = (buf, name, images = [], mime = '') => call('customer_api', cust.jwt, { action: 'analyze_drawing', images, original_b64: buf.toString('base64'), mime, drawing_file_name: name, hint: 'ZZ DEMO fit-out' }, 280000);
  // THE PORTAL'S OWN DOOR (3 Nov 2026). NewRequest.tsx sends a PDF and a photo to analyze_drawing (only DOC_RE files go to
  // analyze_document, and a PDF or an image is not one): a PDF with its pages rasterised (pdfRaster.ts), a photo as JPEG
  // pages (ocrClient toJpegPages, a PNG included). Until today the element score sent them to analyze_document, a door
  // the portal never uses for them, and read 0/3 there every night (27 Oct report: "the drawing-set reader does not run
  // on this path"). No browser OCR is sent with a photo or a scan: what the server reads is what is scored.
  const asPdfDrawing = async (pdf, name) => drawing(pdf, name, (await rasterise(pdf)).map(({ mime, data }) => ({ mime, data })), 'application/pdf');
  const asPhoto = (jpeg, name) => drawing(jpeg, name, [{ mime: 'image/jpeg', data: jpeg.toString('base64') }], 'image/jpeg');

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

  // ── THE ELEMENT SCORE PER FORMAT ─────────────────────────────────────────────────────────────────────
  const tag = (t) => new RegExp(`(^|[^A-Z0-9])${t.replace('-', '-?')}([^0-9]|$)`, 'i');
  const cadTruth = { SD: { re: /\bblock SD\b|smoke detector/i, qty: CAD_COUNTS.SD }, SKT: { re: /\bblock SKT\b|socket/i, qty: CAD_COUNTS.SKT } };
  const pdfTruth = { 'FD-1': { re: tag('FD-1'), qty: PDF_COUNTS['FD-1'] }, 'WC-1': { re: tag('WC-1'), qty: PDF_COUNTS['WC-1'] }, FCU: { re: /FCU-?\d/i, qty: PDF_COUNTS.FCU } };
  score('DXF ascii', await doc(Buffer.from(zzDxf()), 'ZZ DEMO E-101.dxf'), cadTruth, 'analyze_document');
  score('DXF binary', await doc(Buffer.from(zzDxfBinary()), 'ZZ DEMO E-101 binary.dxf'), cadTruth, 'analyze_document');
  // DWG: the truth is the AutoCAD DXF of the same drawing (dwg_samples.check.ts pins it): blocks 8 + 2, layer lengths.
  const ex18 = await drawing(await sample('example_2018.dwg', '7bc7721224003062'), 'ZZ DEMO example_2018.dwg');
  // 3 Nov 2026: the customer's take-off carries every CAD name through neutralCadName (cad_identity.ts: a layer or block
  // name keeps only CAD vocabulary, because a name can identify the job), so 'CIRKLO_PUNKTOJ' and 'bloko' both read
  // 'block unnamed' and 'Tavolo 3' reads 'layer 3'. The old score looked for the raw names and read 0/5 while all five
  // quantities were exact (27 Oct report). Each element is now ONE line: the anonymised name the product must print, its
  // unit and its exact quantity, each line used once. A raw name on the line fails it, and so does a wrong quantity.
  const cadLine = (kind, name, qty, unit) => ({ desc: kind === 'block' ? `block ${neutralCadName(name)}` : `${kind} on layer ${neutralCadName(name)}`, qty, unit });
  scoreLines('DWG (AutoCAD 2018)', ex18, { 'block CIRKLO_PUNKTOJ': cadLine('block', 'CIRKLO_PUNKTOJ', 8, 'nos'), 'block bloko': cadLine('block', 'bloko', 2, 'nos'),
    'Tavolo 3 sqm': cadLine('closed outlines', 'Tavolo 3', 129.36, 'sqm'), 'Tavolo 3 m': cadLine('linework', 'Tavolo 3', 80.56, 'm'), 'Tavolo 2 m': cadLine('linework', 'Tavolo 2', 12.64, 'm') }, 'analyze_drawing');
  score('PDF vector', await asPdfDrawing(Buffer.from(zzPdfSheet()), 'ZZ DEMO P-101.pdf'), pdfTruth, 'analyze_drawing, pages rasterised as the portal does');
  const scan = await zzScanJpeg();
  const sc = await asPdfDrawing(jpegPdf(scan), 'ZZ DEMO P-101 scan.pdf');
  score('PDF scanned (no text layer, model reads it)', sc, pdfTruth, 'analyze_drawing, pages rasterised as the portal does, no ocr_text');
  // A photo or a picture of the sheet: no extension refusal applies to images (drawing_format.ts refuses BIM formats),
  // so it is read like the scan (ruling 1177) and scored the same way; a refusal is recorded as what it is.
  for (const [buf, name] of [[scan.jpeg, 'ZZ DEMO P-101 photo.jpg'], [await (await import('sharp')).default(scan.jpeg).png().toBuffer(), 'ZZ DEMO P-101.png']]) {
    const x = await asPhoto(name.endsWith('.png') ? await (await import('sharp')).default(buf).jpeg({ quality: 92 }).toBuffer() : buf, name);
    const fmt = `image ${name.split('.').pop().toUpperCase()}`;
    if (x.json?.ok === true) score(fmt, x, pdfTruth, 'analyze_drawing as JPEG pages (the portal converts a PNG too), no ocr_text');
    else { SCORE.push({ format: fmt, how: 'analyze_document', http: x.status, read: false, error: x.json?.error || null, elements: [], exact: `refused: ${x.json?.error || x.status}` });
      check(`${fmt} is read`, false, `HTTP ${x.status} ${x.json?.error || ''} ${x.json?.detail || ''}`); }
  }
  console.table(SCORE.map((r) => ({ format: r.format, read: r.read, lines: r.lines ?? '-', exact: r.exact, elements: (r.elements || []).map((e) => `${e.element} ${e.read ?? '-'}/${e.truth}`).join(', ') })));

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
  if (JSON_OUT) { const { writeFileSync } = await import('node:fs'); writeFileSync(JSON_OUT, JSON.stringify({ ledger: 31, measured_at: new Date().toISOString(), score: SCORE, checks: `${results.filter((x) => x.ok).length}/${results.length}`, failed: results.filter((x) => !x.ok) }, null, 1)); }
  process.exit(exitCode);
}
