// drawing_bench — the sales engineer's scorecard: every drawing / BOQ format a customer sends, through the
// production readers, counters and redaction, scored against fixtures/bench_truth.json (written by hand BEFORE the
// first run). Founder ledger 31 (read any drawing format), 580 (count properly, remove every contact and project
// detail), 1177 (every attachment is read). 19 Oct 2026, sales_engineer. No model, no network.
//   deno test --no-lock -A --node-modules-dir=auto supabase/functions/drawing_boq/drawing_bench.test.ts
// Three scores per case:
//   format  - the production reader opened the bytes (or routed them to the OCR that reads them);
//   count   - per class, the count equals the hand count (legend samples are not work);
//   leak    - any identifier from the key in anything a supplier receives is a FAIL (BOQ lines, the redacted
//             CAD file's strings, the drawn CAD sheet, PDF text runs left unboxed). A drawing HELD is not a leak.
// The OCR cases (photo, scanned PDF, BOQ image) need tesseract + sharp (read/env/ffi); without them they are
// reported "not run", never green.
// deno-lint-ignore-file no-explicit-any
import { assertEquals } from 'jsr:@std/assert@1';
import { readDocument } from '../_shared/doc_read/index.ts';
import { empty } from '../_shared/doc_read/types.ts';
import { boqFromExtracted } from './boq_from_document.ts';
import { boqFromDrawingSet } from './drawing_set.ts';
import { boqFromSheet } from './boq_from_sheet.ts';
import { cadSupplierBoq } from '../_shared/cad_identity.ts';
import { drawingIdentityTerms, gateDrawingBoq } from '../_shared/drawing_identity_gate.ts';
import { redactBoq, seedTerms, titleBlockBoxes } from '../_shared/anonymise.ts';
import { supplierBoxes } from '../_shared/supplier_copy.ts';
import { textLayerBoxes } from '../_shared/drawing_identity_text.ts';
import { linesFromRuns, pdfPages } from '../_shared/pdf_text_positions.ts';
import { renderCadForSupplier } from '../_shared/cad_render.ts';
import { redactCadFile } from '../_shared/cad_file_redact.ts';
import { inboxBoq } from '../supplier_api/identity_scrub.ts';
import { countSymbols, legendRows } from './symbol_count.ts';
import { deviceTypeOf } from './legend_vocabulary.ts';
import { drawingInput } from './drawing_input.ts';
import { BENCH_CUSTOMER, BENCH_FILE, benchBoqPdf, benchBoqSvg, benchBoqXlsx, benchDxf, benchPdf } from './bench.fixtures.ts';
import { dxfBinaryFrom } from '../_shared/doc_read/cad.fixtures.ts';
import { benchDxfPairs } from './bench.fixtures.ts';
import { amenitiesDxf, archFinishesDxf, hvacDxf, structureDxf } from './bench_trades.fixtures.ts';

const here = new URL('.', import.meta.url);
const path = (u: URL) => decodeURIComponent(u.pathname).replace(/^\/([A-Za-z]:)/, '$1');
const KEY = JSON.parse(await Deno.readTextFile(new URL('fixtures/bench_truth.json', here)));
const PHOTO = new URL('fixtures/harrogate_court_fire_alarm_gf_as_installed.png', here);
const LANG = path(new URL('../../../public/ocr/lang', here));
const seeds = seedTerms({ ...BENCH_CUSTOMER, extra: [BENCH_FILE] });
const low = (s: string) => s.toLowerCase().replace(/\s+/g, ' ');
const leaksIn = (text: string, ids: string[]) => ids.filter((id) => low(text).includes(low(id)));

type Row = { case: string; format: string; counts: string; count_ok: string; leaks: string };
const rows: Row[] = [];
const score = (name: string, read: boolean | string, want: Record<string, number> | null, got: Record<string, number | null>, leaked: string[]) => {
  const keys = want ? Object.keys(want) : [];
  const exact = keys.filter((k) => got[k] === want![k]).length;
  rows.push({ case: name, format: read === true ? 'READ' : read === false ? 'NOT READ' : read,
    counts: keys.map((k) => `${k} ${got[k] ?? '-'}/${want![k]}`).join(', '), count_ok: want ? `${exact}/${keys.length}` : 'n/a', leaks: leaked.length ? 'FAIL: ' + leaked.join('; ') : 'none' });
  return { exact, total: keys.length, leaked };
};

/** create_inquiry's gate then the supplier inbox's gate: what a supplier reads of a BOQ. */
const supplierBoq = (boq: any) => {
  const g = redactBoq(boq, seeds);
  if (g.held) return { held: true, text: '' };
  const inbox = inboxBoq(g.boq, BENCH_CUSTOMER.name, seeds, []) as any;
  return { held: !!inbox.withheld, text: JSON.stringify(inbox.boq ?? '') };
};
const sumBy = (q: { description: string; qty: number | null }[], re: RegExp) => { const m = q.filter((x) => re.test(x.description)); return m.length ? m.reduce((s, x) => s + (x.qty ?? 0), 0) : null; };

// ── CAD ─────────────────────────────────────────────────────────────────────────────────────────────
const CAD_CLASS: Record<string, RegExp> = { door: /^block DOOR/i, window: /^block WIN/i, socket: /^block SKT$/i, wc: /^block WC$/i };
async function cadCase(name: string, bytes: Uint8Array, filename: string) {
  const k = KEY.dxf_realistic;
  const r = await readDocument(bytes, filename);
  if (!r.ok) return score(name, false, k.counts, {}, []);
  const got = Object.fromEntries(Object.entries(CAD_CLASS).map(([c, re]) => [c, sumBy(r.quantities, re)]));
  const leaked: string[] = [];
  const g = gateDrawingBoq(boqFromExtracted(r, '', '', {}), drawingIdentityTerms(r.text, r.dxf_text), true);
  if (g.boq) { const s = supplierBoq(cadSupplierBoq(g.boq, r.dxf_text ?? '')); leaked.push(...leaksIn(s.text, k.identifiers).map((x) => 'BOQ:' + x)); }
  const f = await redactCadFile(bytes, seeds);
  if (f.ok) leaked.push(...leaksIn(f.dxf, k.identifiers).map((x) => 'file:' + x));
  const d = await renderCadForSupplier(bytes, { seeds });
  if (d.ok) leaked.push(...leaksIn(d.drawn_texts.join('\n'), k.identifiers).map((x) => 'sheet:' + x));
  return score(name, true, k.counts, got, [...new Set(leaked)]);
}

// ── every trade (10 Nov 2026, ruling 1586): the engineer's take-off of a CAD drawing, line by line ────────────────
// What a supplier receives (the gate, cad_identity, create_inquiry, the inbox) must carry each line of the key with its
// exact quantity, unit and status; 'read' = everything behind it is on the drawing, 'to_confirm' = an assumption is in it.
const disciplines: string[] = [];
async function tradeCase(name: string, bytes: Uint8Array, k: any) {
  const r = await readDocument(bytes, BENCH_FILE + '.dxf');
  if (!r.ok) return score(name, false, Object.fromEntries(k.lines.map((l: any) => [l[0], l[1]])), {}, []);
  const g = gateDrawingBoq(boqFromExtracted(r, '', '', {}), drawingIdentityTerms(r.text, r.dxf_text), true);
  const out = g.boq ? cadSupplierBoq(g.boq, r.dxf_text ?? '') as any : null;
  const s = out ? supplierBoq(out) : { held: true, text: '' };
  const parsed = s.held ? [] : JSON.parse(s.text || '[]');
  const served: any[] = Array.isArray(parsed) ? parsed : parsed?.boq ?? [];
  const want: Record<string, number> = {}, got: Record<string, number | null> = {};
  for (const [re, qty, unit, status] of k.lines as [string, number, string, string][]) {
    const key = `${re.replace(/^\^|\$$|\\/g, '').slice(0, 38)} [${unit}${status === 'to_confirm' ? ', to confirm' : ''}]`;
    want[key] = qty;
    const l = served.find((x) => new RegExp(re).test(String(x.description)));
    got[key] = l && l.unit === unit && (l.qty_status ?? 'read') === status ? (l.qty ?? l.estimate ?? null) : null;
  }
  if (k.rooms) for (const [room, [area, perim, h]] of Object.entries(k.rooms) as [string, number[]][]) {
    const rm = (out?.rooms ?? []).find((x: any) => x.name === room);
    want[`room ${room} floor/perimeter/height`] = 1;
    got[`room ${room} floor/perimeter/height`] = rm && rm.floor_sqm === area && rm.perimeter_m === perim && rm.height_m === h ? 1 : 0;
  }
  for (const [d, v] of Object.entries(out?.disciplines ?? {}) as [string, any][]) disciplines.push(`${name} | ${d} | exact: ${v.exact.join('; ') || '-'} | assumed: ${v.assumed.join('; ') || 'none'}`);
  return score(name, true, want, got, leaksIn(s.text + JSON.stringify(out ?? ''), KEY.trades.identifiers));
}

// ── vector PDF ──────────────────────────────────────────────────────────────────────────────────────
async function pdfCase() {
  const k = KEY.pdf_vector, bytes = benchPdf();
  const r = await readDocument(bytes, BENCH_FILE + '.pdf');
  if (!r.ok) return score('PDF vector', false, k.counts, {}, []);
  const pages = await pdfPages(bytes);
  const set = boqFromDrawingSet(pages, '');
  const lines = (set?.boq ?? []) as { description: string; qty: number | null }[];
  // A tag is the same tag with or without its hyphen (the reader writes D1 as "D-1").
  const flat = lines.map((x) => ({ ...x, description: x.description.replace(/([A-Z])-(\d)/g, '$1$2') }));
  const got = Object.fromEntries(Object.keys(k.counts).map((t) => [t, sumBy(flat, new RegExp(`(^|[^A-Z0-9])${t.replace('-', '')}([^A-Z0-9]|$)`))]));
  const leaked: string[] = [];
  const g = set ? gateDrawingBoq(set, drawingIdentityTerms(linesFromRuns(pages)), false) : { boq: null };
  if (g.boq) { const s = supplierBoq(g.boq); leaked.push(...leaksIn(s.text, k.identifiers).map((x) => 'BOQ:' + x)); }
  // The page a supplier sees: every identifying text run must sit inside a box drawing_redact paints.
  const tb = titleBlockBoxes(await pdfPages(bytes, undefined, { layers: false }), seeds);
  const boxes = supplierBoxes(tb, null, pages.length);
  if (boxes) {
    const all = [...boxes[0], ...textLayerBoxes(pages, 0).boxes];
    const inside = (b: any, r: any) => r.x >= b.x - 1e-6 && r.y >= b.y - 1e-6 && r.x + r.w <= b.x + b.w + 1e-6 && r.y + r.h <= b.y + b.h + 1e-6;
    for (const run of pages[0].runs) if (leaksIn(run.text, k.identifiers).length && !all.some((b) => inside(b, run))) leaked.push('page:' + run.text);
  }
  return score('PDF vector' + (boxes ? '' : ' (page HELD)'), true, k.counts, got, [...new Set(leaked)]);
}

// ── BOQ xlsx / pdf ──────────────────────────────────────────────────────────────────────────────────
function boqScore(name: string, read: boolean, lines: { description: string; qty: number | null; estimate?: number | null }[], supplierText: string) {
  const k = KEY.boq_xlsx;
  const got = Object.fromEntries(Object.keys(k.lines).map((d) => { const l = lines.find((x) => low(x.description).includes(low(d))); return [d, l ? (l.qty ?? l.estimate ?? null) : null]; }));
  return score(name, read, k.lines, got, leaksIn(supplierText, k.identifiers));
}

// ── OCR cases ───────────────────────────────────────────────────────────────────────────────────────
const CAN_OCR = ['read', 'env', 'ffi'].every((n) => Deno.permissions.querySync({ name: n as any }).state === 'granted');
async function imageCase(name: string, bytes: Uint8Array) {
  const k = KEY.image_real;
  const { loadSharp, ocrPlan } = await import('./ocr_plan_offline.ts');
  const sharp = await loadSharp();
  const { lines, width, bytes: level } = await ocrPlan(bytes, LANG);
  const { data, info } = await sharp(level).flatten({ background: '#ffffff' }).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  const sym = countSymbols({ w: info.width, h: info.height, px: new Uint8Array(data), channels: 3 }, legendRows(lines, width, deviceTypeOf));
  const out = boqFromExtracted(empty('image'), '', '', drawingInput(lines, width, { counts: sym.counts }, ''));
  const s = supplierBoq(out);
  return score(name, lines.length > 50, k.counts, sym.counts, leaksIn(s.text, k.identifiers));
}

Deno.test({ name: 'drawing bench: format coverage, count accuracy, redaction completeness vs the hand key', sanitizeResources: false, sanitizeOps: false }, async () => {
  const res = [
    await cadCase('DXF ascii (dynamic doors, MINSERT, nested)', benchDxf(), BENCH_FILE + '.dxf'),
    await cadCase('DXF binary (same drawing)', dxfBinaryFrom(benchDxfPairs()), BENCH_FILE + '.dxf'),
    await pdfCase(),
    await tradeCase('DXF architectural finishes plan', archFinishesDxf(), KEY.trades.architectural_finishes),
    await tradeCase('DXF HVAC duct layout', hvacDxf(), KEY.trades.hvac_duct_layout),
    await tradeCase('DXF lifts, pool, landscape', amenitiesDxf(), KEY.trades.lift_pool_landscape),
    await tradeCase('DXF structural steel, scaffolding', structureDxf(), KEY.trades.structure_scaffolding),
  ];
  // BOQ as a spreadsheet: boqFromSheet -> create_inquiry gate -> inbox.
  const xs = boqFromSheet(benchBoqXlsx(), '', BENCH_FILE + '.xlsx');
  res.push(boqScore('BOQ xlsx', xs.ok, xs.ok ? xs.boq.boq as any : [], xs.ok ? supplierBoq(xs.boq).text : ''));
  // BOQ as a PDF: readDocument -> boqFromExtracted.
  const bp = await readDocument(benchBoqPdf(), BENCH_FILE + '.pdf');
  const bpo = bp.ok ? boqFromExtracted(bp, '', '', {}) : null;
  res.push(boqScore('BOQ pdf', bp.ok, (bpo?.boq ?? []) as any, bpo ? supplierBoq(bpo).text : ''));
  if (CAN_OCR) {
    const { loadSharp } = await import('./ocr_plan_offline.ts');
    const sharp = await loadSharp();
    const photo = await Deno.readFile(PHOTO);
    res.push(await imageCase('image PNG (real sample sheet)', photo));
    // A phone photo of the printed sheet: a little rotation, blur and JPEG loss.
    const phone = new Uint8Array(await sharp(photo).rotate(1.5, { background: '#ffffff' }).blur(0.6).jpeg({ quality: 60 }).toBuffer());
    res.push(await imageCase('photo JPG (rotated, blurred, q60)', phone));
    // A scanned PDF has no text layer: the server routes it to OCR, the browser rasterises each page (pdfRaster)
    // and the same OCR plan reads it; the rasterised page is the scan itself.
    const scan = new Uint8Array(await sharp(photo).flatten({ background: '#ffffff' }).jpeg({ quality: 85 }).toBuffer());
    const meta = await sharp(scan).metadata();
    const pdf = new TextEncoder().encode('%PDF-1.4\n');
    const body = [`1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n`, `2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n`,
      `3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${meta.width} ${meta.height}] /Resources << /XObject << /Im1 4 0 R >> >> /Contents 5 0 R >>\nendobj\n`];
    const head = `4 0 obj\n<< /Type /XObject /Subtype /Image /Width ${meta.width} /Height ${meta.height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${scan.length} >>\nstream\n`;
    const cs = `q ${meta.width} 0 0 ${meta.height} 0 0 cm /Im1 Do Q`;
    const tail = `\nendstream\nendobj\n5 0 obj\n<< /Length ${cs.length} >>\nstream\n${cs}\nendstream\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n`;
    const scanPdf = new Uint8Array([...pdf, ...new TextEncoder().encode(body.join('') + head), ...scan, ...new TextEncoder().encode(tail)]);
    const sr = await readDocument(scanPdf, 'scan.pdf');
    const routed = sr.ok && (sr as any).needs === 'ocr';
    const sc = await imageCase('PDF scanned (routed to OCR)', scan);
    rows[rows.length - 1].format = routed ? 'READ (OCR)' : 'NOT READ';
    res.push(sc);
    // A BOQ photographed: the customer's browser OCR text -> boqFromExtracted as OCR text.
    const png = new Uint8Array(await sharp(new TextEncoder().encode(benchBoqSvg())).png().toBuffer());
    // As the portal posts it: the OCR text and the OCR lines with their boxes.
    const { lines, width } = await (await import('./ocr_plan_offline.ts')).ocrPlan(png, LANG);
    const ocrText = lines.map((l: any) => l.text).join('\n');
    const bi = boqFromExtracted(empty('image'), '', ocrText, drawingInput(lines, width, {}, ocrText));
    res.push(boqScore('BOQ image (OCR)', lines.length > 3, bi.boq as any, supplierBoq(bi).text));
  } else rows.push({ case: 'image / photo / scanned PDF / BOQ image', format: 'NOT RUN (needs read, env, ffi)', counts: '', count_ok: '', leaks: '' });

  console.table(rows);
  console.log('PER DISCIPLINE, exact vs assumed:\n  ' + disciplines.join('\n  '));
  const tot = res.reduce((a, r) => ({ e: a.e + r.exact, t: a.t + r.total, l: a.l + r.leaked.length }), { e: 0, t: 0, l: 0 });
  const read = rows.filter((r) => /^READ/.test(r.format)).length;
  console.log(`SCORE format ${read}/${rows.length} read; count ${tot.e}/${tot.t} classes exact; redaction ${tot.l} leaked identifier(s)`);
  if (Deno.permissions.querySync({ name: 'env' }).state === 'granted' && Deno.env.get('BENCH_REPORT_ONLY')) return;
  // Targets: every format read, zero leaks; every count exact where the file states it (CAD, vector PDF, BOQs).
  // The raster counts (photo, scan) are estimates the customer confirms; they are reported, and must not regress.
  assertEquals(read, rows.filter((r) => !/^NOT RUN/.test(r.format)).length, 'a format was not read');
  assertEquals(tot.l, 0, 'an identifier reached a supplier');
  for (const r of res.slice(0, 9)) assertEquals(r.exact, r.total, 'a count the file states was not counted exactly');
});
