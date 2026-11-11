// scripts/e2e/drawing_reaches_suppliers.mjs — a drawing set, uploaded by a customer, reaches the matched
// suppliers: redacted, taken off, matched, and printed on our template. ON PRODUCTION, with ZZ DEMO only.
// Assigned: sales_engineer (founder instructions 30, 579, 580: drawing reading, the count, the redaction,
// the BOQ PDF suppliers receive).
//
// WHY IT EXISTS. PR #794 proved the reader, the redaction and the PDF in process (drawing_chain.test.ts)
// and said plainly what it had not proved: "routing through the live matcher, and edge CPU at 2600 px".
// This walks the real endpoints in the order the portal and a supplier use them:
//   1. a ZZ DEMO customer and two ZZ DEMO suppliers (HVAC, plumbing), made by scripts/e2e/fixtures.mjs;
//   2. a SYNTHETIC CAD drawing set (8 sheets, 36x24 in, /Rotate 270, text inside Form XObjects, CAD
//      layers, a ZZ DEMO title block with a 555 phone, a bare web host and a street address) - the shape
//      of the two real bid sets, whose copyrighted pages never leave this machine;
//   3. every sheet rasterised the way the portal does (pdf.js, long edge 2600 px, JPEG 0.8);
//   4. customer_api analyze_drawing -> drawing_redact (one sheet per call since 22 Sep) + drawing_boq, live;
//   5. the intake, then customer_api create_inquiry with that drawing -> the live matcher;
//   6. each matched ZZ DEMO supplier's inbox, and the inquiry PDF it downloads (supplier_api inquiry_pdf),
//      read back: our template, every take-off line, no identity from the title block;
//   7. the edge logs: drawing_boq and drawing_redact execution time for this run's requests.
// Then everything the run made is torn down and the teardown is proved.
//
// THE MEASURED RUN (27 Oct 2026, founder ledger 580: "make sure he's doing the count properly ... removes any contact
// details or anything that refers to the project details ... the BOQ PDF he generates and how he ingests it so it can be
// shared as an inquiry with the suppliers"). Until then the run asserted that tags were PRESENT and that the title
// block's strings were absent from the BOQ and the PDF; it never compared a quantity with the truth, the set carried no
// e-mail or mobile, and nobody read the redacted PAGES a supplier is shown. Now:
//   COUNT    every element drawn has a quantity known by construction (TRUTH below); each is scored, exact or not.
//   CONTACTS the set also carries an e-mail and a mobile; every redacted page is OCR'd (tesseract.js, the engine the
//            portal runs) in its title strip and its bottom band, upscaled, and searched for every planted identity
//            string AND for any e-mail address or phone shape. The same OCR runs on the ORIGINAL sheet first: if it
//            cannot read the planted contacts there, a clean redacted page proves nothing, and that is a FAIL. The
//            inquiry row, the supplier inbox and both inquiry PDFs are searched too.
//   OUTPUT   --json <file> writes the numbers: per-item counts, leaks per surface, the inquiry id and RFQ number, the
//            storage path of the BOQ PDF the supplier downloads.
//
//   node scripts/e2e/drawing_reaches_suppliers.mjs            run, report, tear down
//   node scripts/e2e/drawing_reaches_suppliers.mjs --keep     leave the demo standing to look at
//   node scripts/e2e/drawing_reaches_suppliers.mjs --json <file>
//
// NOTHING HERE CAN REACH A REAL PERSON: identities are ZZ DEMO / @example.invalid / +9715000000xx, the
// database's demo guards capture every notice, and a demo account is never matched to a real one.
import { supabaseAccessToken } from '../lib/supabase_token.mjs';
import { rasterise } from './portal_raster.mjs';
import { FALLBACK } from '../../supabase/functions/_shared/doc_template.ts';
import zlib from 'node:zlib';
import { openRun, closeRun, leftovers, makeDemoCustomer, makeDemoSupplier, openTradeForDemo, read, call, waitFor } from './fixtures.mjs';
import { runIntake, keys, BASE } from '../lib/demo_factory.mjs';

const KEEP = process.argv.includes('--keep');
const JSON_OUT = process.argv.includes('--json') ? process.argv[process.argv.indexOf('--json') + 1] : null;
const summary = { ledger: 580, measured_at: new Date().toISOString(), counts: [], leaks: {}, ocr_control: null };
const results = [];
const check = (name, ok, detail = '') => { results.push({ name, ok: !!ok, detail }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' - ' + detail : ''}`); return !!ok; };

// ── the synthetic drawing set ────────────────────────────────────────────────────────────────────────
// Written in DISPLAY coordinates (a = across, b = down, 0..1) and turned into user space by the form's
// /Matrix, exactly as the real CAD exports are. 36 x 24 in sheets shown landscape, stored portrait.
const W = 1728, H = 2592, DW = H, DH = W;
// The planted contact and project details. The e-mail and the mobile joined on 27 Oct 2026 (ledger 580: "removes any
// contact details"): the set carried a phone, a web host and an address, never an address a supplier could write to.
export const IDENTITY = ['ZZ DEMO CONSULTING ENGINEERS', '(555) 010-7400', 'ZZDEMODESIGN.COM', '1039 ZZ MAIN STREET, UNIT G', 'ZZTOWN, CO 80550', 'ZZ DEMO CRIME LAB REMODEL',
  'ZZ.MEP@EXAMPLE.INVALID', 'MOB +971 50 000 0091'];
// What is drawn, known by construction (sheetContent): per sheet 300 air devices tagged A and 60 double-line 26x18 runs
// of 30 segments x 0.013 of the 2592 pt display width at 1/8" = 1'-0"; on sheet 1 alone one each of five tags. A run is
// 30 x 0.013 x 2592 / 72 in x 8 ft/in = 112.32 ft = 34.2351 m; x 60 runs x 8 sheets = 16,432.8 m.
export const TRUTH = [
  { item: 'EF-1', re: /EF-1\b/, qty: 1, unit: 'nos' }, { item: 'EF-2', re: /EF-2\b/, qty: 1, unit: 'nos' },
  { item: 'RTU-1', re: /RTU-1\b/, qty: 1, unit: 'nos' }, { item: 'IRH-1', re: /IRH-1\b/, qty: 1, unit: 'nos' },
  { item: 'WC/L-1', re: /WC\/L-1\b/, qty: 1, unit: 'nos' }, { item: 'Air device type A', re: /Air device type A\b/, qty: 2400, unit: 'nos' },
  { item: 'Duct 26x18', re: /ductwork 26x18/i, qty: +(30 * 0.013 * 2592 / 72 * 8 * 0.3048 * 60 * 8).toFixed(1), unit: 'm', tolPct: 0.5 },
];
// Any e-mail address, and a UAE or North-American phone shape, wherever it appears (not only the planted strings).
const CONTACT_RE = [/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i, /\+?971[\s-]?\d{1,2}[\s-]?\d{3}[\s-]?\d{4}/, /\(\d{3}\)\s?\d{3}-\d{4}/];
function sheetContent(n) {
  const esc = (s) => s.replace(/([()\\])/g, '\\$1');
  const t = (a, b, size, s) => `BT /F1 ${size} Tf 1 0 0 1 ${(a * DW).toFixed(1)} ${((1 - b) * DH).toFixed(1)} Tm (${esc(s)}) Tj ET\n`;
  const L = (a1, b1, a2, b2) => `${(a1 * DW).toFixed(1)} ${((1 - b1) * DH).toFixed(1)} m ${(a2 * DW).toFixed(1)} ${((1 - b2) * DH).toFixed(1)} l S\n`;
  let s = L(0.915, 0.03, 0.915, 0.97);                                                     // title-block border
  s += t(0.30, 0.86, 20, n === 1 ? 'MAIN FLOOR PLAN - MECHANICAL' : `PARTIAL PLAN ${n} - MECHANICAL`) + t(0.30, 0.88, 9, 'SCALE: 1/8" = 1\'-0"');
  // Ducts on their CAD layer: 60 double-line runs of 26x18 (26" = 19.5 pt apart at 1/8"), each cut into
  // 30 segments, so a sheet carries ~3,600 duct segments like the real M1.0 (3,629 measured).
  s += '/OC /L1 BDC q 1.44 w\n';
  for (let r = 0; r < 60; r++) {
    const b = 0.08 + r * 0.012, a0 = 0.05, step = 0.013;
    for (let k = 0; k < 30; k++) { s += L(a0 + k * step, b, a0 + (k + 1) * step, b); s += L(a0 + k * step, b + 19.5 / DH, a0 + (k + 1) * step, b + 19.5 / DH); }
  }
  s += 'Q EMC\n';
  // Annotation: leaders, tags, air devices - ~1,500 text runs a sheet.
  s += '/OC /L2 BDC q 0.3 w\n';
  for (let i = 0; i < 400; i++) s += L(0.05 + (i % 40) * 0.02, 0.1 + Math.floor(i / 40) * 0.07, 0.06 + (i % 40) * 0.02, 0.11 + Math.floor(i / 40) * 0.07);
  s += 'Q EMC\n';
  for (let i = 0; i < 300; i++) {
    const a = 0.05 + (i % 30) * 0.028, b = 0.12 + Math.floor(i / 30) * 0.07;
    s += t(a, b, 9, 'A') + t(a + 0.005, b - 0.003, 9, '8x8') + t(a + 0.005, b + 0.003, 9, '180');   // an air device
    if (i % 10 === 0) s += t(a, b + 0.02, 9, '26x18');
  }
  if (n === 1) s += t(0.40, 0.80, 11, 'EF-1') + t(0.45, 0.80, 11, 'EF-2') + t(0.50, 0.80, 11, 'RTU-1') + t(0.55, 0.80, 11, 'IRH-1') + t(0.60, 0.80, 11, 'WC/L-1');
  s += t(0.10, 0.93, 9, 'LOCATION:') + t(0.15, 0.93, 9, 'ZZTOWN, CO');
  s += t(0.30, 0.93, 9, 'CONTACT:') + t(0.35, 0.93, 9, 'ZZ.MEP@EXAMPLE.INVALID') + t(0.50, 0.93, 9, 'MOB +971 50 000 0091');
  s += 'q /Fm2 Do Q\n';
  const tb = IDENTITY.map((x, i) => t(0.925, 0.10 + i * 0.04, 10, x)).join('') + t(0.93, 0.90, 30, `M1.${n - 1}`) + t(0.925, 0.80, 10, 'MECHANICAL');
  return { plan: s, titleBlock: tb };
}
export function stressSetPdf(pages = 8) {
  const objs = [];
  const add = (s) => { objs.push(s); return objs.length; };
  const stream = (dict, body) => { const z = zlib.deflateSync(Buffer.from(body, 'latin1')); return { dict: `<< ${dict} /Filter /FlateDecode /Length ${z.length} >>`, z }; };
  add('<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [3 0 R 4 0 R] >> >>');                              // 1
  add(null);                                                                                                     // 2 pages (later)
  add('<< /Type /OCG /Name (M-HVAC-DUCT) >>'); add('<< /Type /OCG /Name (M-ANNO) >>');                          // 3, 4
  add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');                                               // 5
  const kids = [];
  for (let n = 1; n <= pages; n++) {
    const { plan, titleBlock } = sheetContent(n);
    const tb = add(stream(`/Type /XObject /Subtype /Form /BBox [0 0 ${DW} ${DH}] /Resources << /Font << /F1 5 0 R >> >>`, titleBlock));
    const fm = add(stream(`/Type /XObject /Subtype /Form /BBox [0 0 ${DW} ${DH}] /Matrix [0 -1 1 0 0 ${H}] /Resources << /Font << /F1 5 0 R >> /XObject << /Fm2 ${tb} 0 R >> /Properties << /L1 3 0 R /L2 4 0 R >> >>`, plan));
    const c = add(stream('', 'q /Fm1 Do Q'));
    kids.push(add(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${W} ${H}] /Rotate 270 /Resources << /XObject << /Fm1 ${fm} 0 R >> >> /Contents ${c} 0 R >>`));
  }
  objs[1] = `<< /Type /Pages /Kids [${kids.map((k) => `${k} 0 R`).join(' ')}] /Count ${kids.length} >>`;
  const parts = [Buffer.from('%PDF-1.5\n', 'latin1')];
  objs.forEach((o, i) => {
    parts.push(Buffer.from(`${i + 1} 0 obj\n`, 'latin1'));
    if (typeof o === 'string') parts.push(Buffer.from(o + '\n', 'latin1'));
    else { parts.push(Buffer.from(o.dict + '\nstream\n', 'latin1'), o.z, Buffer.from('\nendstream\n', 'latin1')); }
    parts.push(Buffer.from('endobj\n', 'latin1'));
  });
  parts.push(Buffer.from('trailer\n<< /Root 1 0 R >>\n%%EOF\n', 'latin1'));
  return Buffer.concat(parts);
}

// The portal rasteriser lives in ./portal_raster.mjs (shared with every_drawing_format_is_read.mjs since 3 Nov 2026).

async function edgeTimes(fn, sinceIso) {
  // function_edge_logs carry execution_time_ms per request (wall time; the runtime does not log CPU).
  // 24 Sep 2026: Supabase removed logs.all (HTTP 410, "Use GET /v1/projects/{ref}/analytics/endpoints/logs").
  // The replacement takes ClickHouse SQL over ONE table, `logs`, filtered by source, with the old nested
  // metadata flattened into log_attributes (keys measured live that day: execution_time_ms,
  // response.status_code, request.pathname). See scripts/checks/edge_requests_show_no_attack_pattern.mjs.
  const { readFileSync } = await import('node:fs');
  const tok = supabaseAccessToken();
  const sql = `select timestamp, toFloat64OrZero(log_attributes['execution_time_ms']) as ms, toInt32OrZero(log_attributes['response.status_code']) as st from logs where source = 'function_edge_logs' and log_attributes['request.pathname'] = '/functions/v1/${fn}' order by timestamp`;
  const r = await fetch(`https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/analytics/endpoints/logs?sql=${encodeURIComponent(sql)}&iso_timestamp_start=${encodeURIComponent(sinceIso)}&iso_timestamp_end=${encodeURIComponent(new Date().toISOString())}`, { headers: { Authorization: 'Bearer ' + tok } });
  const text = await r.text();
  let j; try { j = JSON.parse(text); } catch { j = null; }
  // An unreadable log used to come back as [] and print "no log rows yet" — which is how the 410 went unseen.
  if (!r.ok || !j || j.error || !Array.isArray(j.result)) throw new Error(`function_edge_logs unreadable: HTTP ${r.status} ${text.slice(0, 200)}`);
  return j.result;
}

// ── reading a page a supplier is shown ───────────────────────────────────────────────────────────────
// tesseract.js with the portal's own language data (public/ocr/lang), sparse-text mode. The title strip (right 10% of
// the sheet as displayed) and the bottom band (last 14%) are cropped and upscaled 3x: at 2600 px a 10 pt label is about
// 10 px tall, below what the engine reads reliably at 1x.
let ocrWorker = null;
async function ocrPage(jpeg) {
  const sharp = (await import('sharp')).default;
  if (!ocrWorker) {
    const { createWorker } = await import('tesseract.js');
    const lang = decodeURIComponent(new URL('../../public/ocr/lang', import.meta.url).pathname).replace(/^\/([A-Za-z]:)/, '$1');
    ocrWorker = await createWorker('eng', 1, { langPath: lang, gzip: true, cacheMethod: 'none' });
    await ocrWorker.setParameters({ tessedit_pageseg_mode: '11' });
  }
  const m = await sharp(jpeg).metadata();
  const crops = [{ left: Math.floor(m.width * 0.90), top: 0, width: m.width - Math.floor(m.width * 0.90), height: m.height },
                 { left: 0, top: Math.floor(m.height * 0.86), width: m.width, height: m.height - Math.floor(m.height * 0.86) }];
  let text = '';
  for (const c of crops) {
    const png = await sharp(jpeg).extract(c).resize({ width: c.width * 3 }).grayscale().png().toBuffer();
    text += (await ocrWorker.recognize(png)).data.text + '\n';
  }
  return text;
}
const squash = (x) => String(x).toUpperCase().replace(/[^A-Z0-9@+]/g, '');
/** The planted strings and every contact shape found in a text. OCR drops spaces and dots, so both sides are squashed. */
// QuotesDone's OWN letterhead (_shared/doc_template.ts: every document we print carries our email and numbers) is not a
// leak: the 3 Nov 2026 run (41598217377) failed both BOQ PDFs on exactly management@quotesdone.com and +971 56 791 8605,
// the template's own footer. Only those exact values are let through; any other contact shape, and every planted
// string, still fails.
const OWN_CONTACT = new Set([FALLBACK.email, FALLBACK.phone, FALLBACK.callPhone].map(squash));
function leaksIn(text) {
  const t = squash(text);
  const planted = IDENTITY.filter((x) => t.includes(squash(x).slice(0, 14)));
  const shapes = CONTACT_RE.flatMap((re) => String(text).match(new RegExp(re.source, 'gi')) || []).filter((s) => !OWN_CONTACT.has(squash(s)));
  return [...new Set([...planted, ...shapes])];
}
async function download(bucket, path) {
  const { SERVICE } = await keys();
  const r = await fetch(`${BASE}/storage/v1/object/${bucket}/${path.split('/').map(encodeURIComponent).join('/')}`, { headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE } });
  if (!r.ok) throw new Error(`download ${bucket}/${path}: HTTP ${r.status}`);
  return Buffer.from(await r.arrayBuffer());
}
/** bucket and object name of a signed storage URL. */
const signedObject = (url) => { const m = /\/object\/sign\/([^/]+)\/([^?]+)/.exec(String(url || '')); return m ? { bucket: m[1], name: decodeURIComponent(m[2]) } : null; };

// ── the run ──────────────────────────────────────────────────────────────────────────────────────────
// --pdf <file>: write the synthetic set and stop (to read it locally before a production run).
if (process.argv.includes('--pdf')) {
  const { writeFileSync } = await import('node:fs');
  writeFileSync(process.argv[process.argv.indexOf('--pdf') + 1], stressSetPdf(8));
  process.exit(0);
}
const started = new Date(Date.now() - 5000).toISOString();
const run = await openRun();
let exitCode = 1;
try {
  const [hvac, plumb] = [await makeDemoSupplier(run, { trade: 'hvac', label: 'HVAC' }), await makeDemoSupplier(run, { trade: 'plumbing', label: 'PLUMB' })];
  check('two ZZ DEMO suppliers approved with the mandatory six', hvac.row?.approval_status === 'approved' && plumb.row?.approval_status === 'approved', `${hvac.leadId}, ${plumb.leadId}`);
  // The request is posted in HVAC: the trade must be open for a demo customer first (fixtures.mjs openTradeForDemo; run 077cbbfc: 409).
  const opened = await openTradeForDemo(run, 'hvac', 1);
  check('HVAC is open for the demo customer at the trade-opening floor', opened.counted >= opened.floor, `${opened.counted} counted, floor ${opened.floor}, ${opened.bench.length} bench supplier(s) outside Dubai`);
  const cust = await makeDemoCustomer(run, { label: 'Drawing' });
  check('a ZZ DEMO customer with a complete account', !!cust.customerId, cust.email);

  const pdf = stressSetPdf(8);
  const images = await rasterise(pdf);
  check('8 sheets rasterised as the portal does (long edge 2600 px, JPEG 0.8)', images.length === 8 && images.every((i) => Math.max(i.w, i.h) === 2600), `${images.length} x ${images[0]?.w}x${images[0]?.h}, pdf ${Math.round(pdf.length / 1024)} KB`);
  // THE CONTROL: the same OCR must find the planted contacts on the ORIGINAL sheet, or a clean redacted page proves nothing.
  const control = leaksIn(await ocrPage(Buffer.from(images[0].data, 'base64')));
  const wantRead = ['ZZ.MEP@EXAMPLE.INVALID', 'MOB +971 50 000 0091', 'ZZ DEMO CONSULTING ENGINEERS'];
  summary.ocr_control = { found_on_original: control, required: wantRead };
  check('the OCR reads the planted e-mail, mobile and consultant on the ORIGINAL sheet (the control)', wantRead.every((w) => control.includes(w)), control.join(' | '));

  const t0 = Date.now();
  const an = await call('customer_api', cust.jwt, { action: 'analyze_drawing', images: images.map(({ mime, data }) => ({ mime, data })), original_b64: pdf.toString('base64'), mime: 'application/pdf', drawing_file_name: 'ZZ DEMO mechanical set.pdf', hint: 'HVAC ductwork and equipment, Dubai' }, 280000);
  const secs = ((Date.now() - t0) / 1000).toFixed(1);
  const res = an.json || {};
  check('analyze_drawing answered', an.status === 200 && res.ok === true, `HTTP ${an.status} in ${secs}s ${res.error || ''} ${res.detail || ''}`);
  const boq = res?.boq?.boq || [];
  const has = (re) => boq.some((l) => re.test(`${l.item || ''} ${l.description || ''}`));
  check('the take-off read the sheet: tags, air devices, duct sizes', has(/EF-1/) && has(/RTU-1/) && has(/Air device type A/) && has(/26x18/), `${boq.length} lines, method ${res?.boq?.method || '-'}`);
  // THE COUNT, item by item against the construction.
  for (const t of TRUTH) {
    const ms = boq.filter((l) => t.re.test(`${l.item || ''} ${l.description || ''}`) && String(l.unit || '').toLowerCase() === t.unit);
    const got = ms.length ? +ms.reduce((a, l) => a + Number(l.qty ?? l.estimate ?? 0), 0).toFixed(1) : null;
    const errPct = got == null ? null : +(Math.abs(got - t.qty) / t.qty * 100).toFixed(3);
    const ok = got != null && errPct <= (t.tolPct ?? 0);
    summary.counts.push({ item: t.item, truth: t.qty, read: got, unit: t.unit, err_pct: errPct, ok });
    check(`count: ${t.item} = ${t.qty} ${t.unit}`, ok, `read ${got ?? '-'}${errPct == null ? '' : `, error ${errPct}%`}`);
  }
  summary.lines = boq.length;
  summary.counts_exact = `${summary.counts.filter((c) => c.ok).length}/${summary.counts.length}`;
  summary.leaks.boq_lines = [...new Set(boq.flatMap((l) => leaksIn(JSON.stringify(l))))];
  check('no planted contact or project detail in any BOQ line', !summary.leaks.boq_lines.length, summary.leaks.boq_lines.join(' | '));
  check('no identity from the title block in any line', !boq.some((l) => IDENTITY.some((x) => JSON.stringify(l).toUpperCase().includes(x.toUpperCase().slice(0, 12)))));
  check('every sheet redacted and verified', res.redaction_complete === true && res.redaction_pages_out === 8, `in ${res.redaction_pages_in} out ${res.redaction_pages_out} lost ${res.redaction_pages_lost} held ${res.drawing_held}`);
  check('the redacted pages are shareable', res.drawing_held !== true && (res.drawing_redacted_paths || []).length === 8, `${(res.drawing_redacted_paths || []).length} paths`);
  // Every redacted page, read the way a person reads it.
  summary.redacted_paths = res.drawing_redacted_paths || [];
  summary.original_path = res.drawing_file_path || null;
  summary.leaks.redacted_pages = [];
  for (const p of summary.redacted_paths) {
    const found = leaksIn(await ocrPage(await download('drawing-files', p)));
    if (found.length) summary.leaks.redacted_pages.push({ page: p, found });
  }
  check('no contact or project detail on any redacted page (OCR)', summary.redacted_paths.length > 0 && !summary.leaks.redacted_pages.length, `${summary.redacted_paths.length} pages read; ${JSON.stringify(summary.leaks.redacted_pages).slice(0, 400)}`);

  // One sheet alone, the same 8-sheet original: what a single drawing_redact call costs at 2600 px. This is
  // the unit customer_api now sends (REDACT_BATCH = 1); measured here so the edge, not a laptop, says it fits.
  const one = await call('customer_api', cust.jwt, { action: 'analyze_drawing', images: images.slice(0, 1).map(({ mime, data }) => ({ mime, data })), original_b64: pdf.toString('base64'), mime: 'application/pdf', drawing_file_name: 'ZZ DEMO mechanical set p1.pdf', hint: 'HVAC' }, 280000);
  check('one 2600 px sheet per drawing_redact call survives the edge', one.json?.redaction_pages_out === 1, `in ${one.json?.redaction_pages_in} out ${one.json?.redaction_pages_out} lost ${one.json?.redaction_pages_lost}`);

  // The intake the portal runs, carrying the drawing's BOQ, then the request itself.
  const answers = [
    // The budget comes FIRST and in words: until the parseBudget fix in this PR is deployed, the intake took the
    // first number anywhere in the text (a duct size, 26x18 -> 'AED 26'), below every supplier's minimum job.
    'Budget around AED 150,000. HVAC only: supply and install ductwork, rooftop units and exhaust fans in an existing office building in Dubai, as per the attached drawings.',
    'Quantities are in the attached drawing take-off: 26x18 supply duct, air devices type A, EF-1, EF-2, RTU-1, IRH-1.',
    'Scope: supply and install, including testing, balancing and commissioning. No ceiling or partition works.',
    'Materials: galvanised steel ductwork to SMACNA, standard commercial grade. Warranty: 12 months minimum.',
    'Needed by 30 November 2026. Ground floor, direct vehicle access.',
  ];
  // The intake asks what it still needs; each open question gets a plain answer in its own words.
  const reply = (m) => /warranty/i.test(m) ? '12 months warranty at least.'
    : /by when|date|deliver/i.test(m) ? 'Needed by 30 November 2026.'
    : /ceiling/i.test(m) ? 'No ceiling works - existing ceiling stays.'
    : /partition/i.test(m) ? 'No partitions - existing walls stay.'
    : /air conditioning|split|ducted|cassette/i.test(m) ? 'A central ducted system: rooftop units with ductwork and diffusers, as drawn.'
    : /used for|how big|size of|area/i.test(m) ? 'Offices and storage, about 1,200 square metres.'
    : /install/i.test(m) ? 'Supply and installation.'
    : /material|spec/i.test(m) ? 'Galvanised steel ductwork, standard commercial grade.'
    : 'Standard commercial specification.';
  let intake = await runIntake({ ...cust, jwt: cust.jwt, email: cust.email }, answers, answers.length);
  for (let turn = 0; turn < 6 && intake.status !== 'ready' && intake.intakeId; turn++) {
    const text = intake.missing.map(reply).join(' ');
    const r = await call('inquiry_intake', cust.jwt, { intake_id: intake.intakeId, text, email: cust.email, drawing_boq: res.boq });
    intake = { ...intake, status: r.json?.status ?? intake.status, missing: Array.isArray(r.json?.missing) ? r.json.missing.map(String) : [], turns: intake.turns + 1 };
  }
  check('the intake reached ready', intake.status === 'ready', `${intake.status} after ${intake.turns} turns, missing ${intake.missing.join(', ')}`);
  // The request carries the full set when every sheet was shared; on a deployment that still sends four
  // sheets per redaction call (held above), it carries the one sheet that did clear, so the chain after
  // redaction - matching, the inbox, the PDF - is still walked on production.
  const shared = (res.drawing_redacted_paths || []).length === 8 ? res : { ...(one.json || {}), boq: res.boq };
  console.log(`INFO  the request carries ${(shared.drawing_redacted_paths || []).length} redacted sheet(s)`);
  const drawing = { drawing_file_path: shared.drawing_file_path, drawing_file_name: shared.drawing_file_name, drawing_redacted_paths: shared.drawing_redacted_paths, boq: res.boq, brief_source: 'drawing' };
  const ci = await call('customer_api', cust.jwt, { action: 'create_inquiry', intake_id: intake.intakeId, category: 'hvac', emirate: 'Dubai', trades: ['hvac'], scope_type: 'single', summary: 'ZZ DEMO HVAC ductwork and equipment per drawings', raw_input: answers.join('\n'), spec: {}, drawing }, 120000);
  const iid = ci.json?.id ?? ci.json?.inquiry_id ?? null;
  check('create_inquiry posted the request', !!iid, `HTTP ${ci.status} ${ci.text}`);
  if (iid) run.ids.inquiries.add(iid);
  console.log(`INFO  create_inquiry: matches ${ci.json?.matches}, routing ${JSON.stringify(ci.json?.routing || ci.json?.coverage || null).slice(0, 900)}`);

  if (iid) {
    const row = (await read(`select rfq_no, status, drawing_redacted_paths, jsonb_array_length(coalesce(boq->'boq','[]'::jsonb)) n from public.inquiries where id = '${iid}'`))[0] || {};
    summary.inquiry_id = iid; summary.rfq_no = row.rfq_no ?? null;
    const [inqText] = await read(`select coalesce(boq::text,'') || ' ' || coalesce(summary,'') t from public.inquiries where id = '${iid}'`);
    summary.leaks.inquiry_row = leaksIn(inqText?.t || '');
    check('no planted contact or project detail in the inquiry row (BOQ and summary)', !summary.leaks.inquiry_row.length, summary.leaks.inquiry_row.join(' | '));
    check('the inquiry carries the take-off and the redacted pages', Number(row.n) === boq.length && (row.drawing_redacted_paths || []).length === (shared.drawing_redacted_paths || []).length && (row.drawing_redacted_paths || []).length > 0, `rfq ${row.rfq_no}, ${row.n} lines, ${(row.drawing_redacted_paths || []).length} pages, status ${row.status}`);
    const matched = await waitFor(async () => { const m = await read(`select m.supplier_id, l.company_name, l.is_demo from public.inquiry_matches m join public.leads l on l.id = m.supplier_id where m.inquiry_id = '${iid}'`); return m.some((x) => String(x.supplier_id) === String(hvac.leadId)) ? m : null; }, { timeoutMs: 90000, everyMs: 15000 }).catch((e) => { console.log(`INFO  match poll stopped: ${e?.status || e}`); return null; });
    check('the live matcher matched the ZZ DEMO HVAC supplier', !!matched, JSON.stringify((matched || []).map((m) => `${m.company_name}${m.is_demo ? ' (demo)' : ''}`)));
    check('no real supplier was matched to a demo request', !!matched && matched.every((m) => m.is_demo === true));

    // What the supplier sees and downloads.
    const inbox = await call('supplier_api', hvac.jwt, { action: 'inbox', inquiry_id: iid });
    const item = (inbox.json?.inquiries || [])[0];
    check('the HVAC supplier sees the request in the inbox', !!item, `HTTP ${inbox.status}, drawing pages ${item?.drawing_pages ?? item?.drawing_redacted_paths?.length ?? '-'}`);
    summary.leaks.supplier_inbox = leaksIn(JSON.stringify(item || {}));
    check('no planted contact or project detail in what the supplier inbox returns', !!item && !summary.leaks.supplier_inbox.length, summary.leaks.supplier_inbox.join(' | '));
    const pdfR = await call('supplier_api', hvac.jwt, { action: 'inquiry_pdf', inquiry_id: iid, lang: 'en' }, 120000);
    const url = pdfR.json?.url;
    check('the supplier downloads the inquiry PDF', !!url, `HTTP ${pdfR.status} ${pdfR.text}`);
    if (url) {
      const bytes = Buffer.from(await (await fetch(url)).arrayBuffer());
      const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
      const doc = await pdfjs.getDocument({ data: new Uint8Array(bytes), verbosity: 0 }).promise;
      let text = '';
      for (let p = 1; p <= doc.numPages; p++) text += (await (await doc.getPage(p)).getTextContent()).items.map((x) => x.str).join(' ') + '\n';
      check('the PDF is our template: QuotesDone, the RFQ number, the BOQ table', /QuotesDone/i.test(text) && text.includes(String(row.rfq_no || '~')) && /26x18/.test(text) && /EF-1/.test(text), `${doc.numPages} page(s), ${bytes.length} bytes`);
      check('no identity from the title block in the PDF', !IDENTITY.some((x) => text.toUpperCase().includes(x.toUpperCase())));
      summary.boq_pdf = { ...signedObject(url), pages: doc.numPages, bytes: bytes.length };
      summary.leaks.inquiry_pdf_en = leaksIn(text);
      check('no contact detail of any shape in the English BOQ PDF', !summary.leaks.inquiry_pdf_en.length, summary.leaks.inquiry_pdf_en.join(' | '));
      // Every counted item is on the PDF with its quantity (2,400 may print with a separator).
      const nos = TRUTH.filter((t) => t.unit === 'nos'), flat = text.replace(/(\d),(\d)/g, '$1$2');
      const onPdf = nos.filter((t) => t.re.test(text) && new RegExp(`(^|\\D)${t.qty}(\\D|$)`).test(flat));
      summary.boq_pdf.items_with_qty = `${onPdf.length}/${nos.length}`;
      check('every counted item is on the BOQ PDF with its quantity', onPdf.length === nos.length, summary.boq_pdf.items_with_qty);
      const ar = await call('supplier_api', hvac.jwt, { action: 'inquiry_pdf', inquiry_id: iid, lang: 'ar' }, 120000);
      check('the Arabic inquiry PDF is produced too', !!ar.json?.url, `HTTP ${ar.status}`);
      if (ar.json?.url) {
        const ab = Buffer.from(await (await fetch(ar.json.url)).arrayBuffer());
        const d2 = await pdfjs.getDocument({ data: new Uint8Array(ab), verbosity: 0 }).promise;
        let t2 = ''; for (let p = 1; p <= d2.numPages; p++) t2 += (await (await d2.getPage(p)).getTextContent()).items.map((x) => x.str).join(' ') + '\n';
        summary.boq_pdf_ar = { ...signedObject(ar.json.url), pages: d2.numPages, bytes: ab.length };
        summary.leaks.inquiry_pdf_ar = leaksIn(t2);
        check('no contact detail of any shape in the Arabic BOQ PDF', !summary.leaks.inquiry_pdf_ar.length, summary.leaks.inquiry_pdf_ar.join(' | '));
      }
    }
  }

  // Edge timings for this run's drawing calls (logs land within ~a minute).
  await new Promise((r) => setTimeout(r, 45000));
  for (const fn of ['drawing_boq', 'drawing_redact', 'customer_api']) {
    // Timings are information, not a check: an unreadable log is printed as such, never as "no rows".
    try {
      const rows = await edgeTimes(fn, started);
      console.log(`TIME  ${fn}: ${rows.map((r) => `${r.st}/${r.ms}ms`).join('  ') || 'no log rows yet'}`);
    } catch (e) { console.log(`TIME  ${fn}: ${e.message}`); }
  }
  exitCode = results.every((r) => r.ok) ? 0 : 1;
} catch (e) {
  check('the run completed', false, String(e?.stack || e).slice(0, 600));
} finally {
  // The management API throttles (429) a teardown that follows a long run; one wait and a second pass.
  try { await closeRun(run, { keep: KEEP }); } catch (e) { console.log(`teardown throttled (${e?.status || e}); retrying in 60 s`); await new Promise((r) => setTimeout(r, 60000)); await closeRun(run, { keep: KEEP }); }
  if (!KEEP) { const left = await leftovers(run); check('teardown left nothing behind', left.total === 0, JSON.stringify(left)); if (left.total) exitCode = 1; summary.teardown = left; }
  // The drawing files are named by the customer, not the run tag, so the run's own objects are also counted by name.
  if (!KEEP) {
    const objs = [...(summary.redacted_paths || []).map((n) => ({ bucket: 'drawing-files', name: n })), summary.original_path && { bucket: 'drawing-files', name: summary.original_path }, summary.boq_pdf, summary.boq_pdf_ar].filter((o) => o?.name);
    const lit = (x) => `'${String(x).replace(/'/g, "''")}'`;
    const n = objs.length ? (await read(`select count(*)::int n from storage.objects where (bucket_id, name) in (${objs.map((o) => `(${lit(o.bucket)}, ${lit(o.name)})`).join(',')})`))[0].n : 0;
    summary.storage_left_of_named = `${n}/${objs.length}`;
    check('none of the run\'s drawing files or BOQ PDFs is left in storage', n === 0, `${n} of ${objs.length} named objects remain`);
    if (n) exitCode = 1;
  }
  if (ocrWorker) await ocrWorker.terminate();
  summary.checks = `${results.filter((r) => r.ok).length}/${results.length}`;
  summary.failed = results.filter((r) => !r.ok).map((r) => `${r.name}: ${r.detail}`);
  if (JSON_OUT) { const { writeFileSync } = await import('node:fs'); writeFileSync(JSON_OUT, JSON.stringify(summary, null, 1)); }
  console.log(`\n${results.filter((r) => r.ok).length}/${results.length} checks passed`);
  process.exit(exitCode);
}
