// A real drawing IMAGE read through the free path, scored field by field against a person's answer key.
// deno test -A supabase/functions/drawing_boq/drawing_image_ocr.test.ts
//
// The fixture is the founder's sample fire alarm layout (fixtures/, outside public/). Every model
// route is held, so a photographed drawing is read only by the customer's browser OCR (tesseract.js
// 7.0.0, LSTM, self-hosted language data in public/ocr/lang). This test runs the SAME library, the
// SAME preparation plan (src/components/me/ocrPlan.ts) and the SAME server-side reader, so no model
// and no network is used and the numbers are what a customer's upload gets.
//
// It reports BEFORE and AFTER per field:
//   before  one OCR pass of the image as it was, read by boqFromExtracted (the path customers had:
//           measured 14 Sep 2026 through the real customer path, BOQ 0/7, OCR 2/20)
//   after   the OCR plan (upscaled, thresholded, tiled, sparse-text, two passes), read by
//           drawing_from_ocr.readDrawing with the lines' page boxes
// and then the raster symbol counter (symbol_count.ts) and its cross-check against the loop.
// It ASSERTS only what must never regress: the path runs, the fields that the reader gets right stay
// right, and no identifying title-block value reaches a supplier-facing BOQ line.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { createWorker } from 'npm:tesseract.js@7.0.0';
import { boqFromExtracted } from './boq_from_document.ts';
import { empty } from '../_shared/doc_read/types.ts';
import { readDrawing, type DrawingRead, type OcrLine } from './drawing_from_ocr.ts';
import { deviceTypeOf } from './legend_vocabulary.ts';
import { countSymbols, crossCheck, legendRows } from './symbol_count.ts';
import { drawingInput } from './drawing_input.ts';
import { OCR_PASSES, binarize, mergeLines, scaleFor, tiles } from '../../../src/components/me/ocrPlan.ts';

const here = new URL('.', import.meta.url);
const path = (u: URL) => decodeURIComponent(u.pathname).replace(/^\/([A-Za-z]:)/, '$1');
const FIXTURE = new URL('fixtures/harrogate_court_fire_alarm_gf_as_installed.png', here);
const KEY = new URL('fixtures/harrogate_court_fire_alarm_gf_as_installed.key.json', here);
const LANG = path(new URL('../../../public/ocr/lang', here));

type Field = { value: unknown; confidence: string };
const norm = (s: string) => String(s ?? '').toLowerCase().replace(/[^a-z0-9/.-]+/g, ' ').replace(/\s+/g, ' ').trim();

/** BEFORE: is every keyed value present somewhere in what the old reader produced? */
export function scoreHaystack(key: Record<string, Field>, haystack: string) {
  const h = ' ' + norm(haystack) + ' ';
  const addrs = new Set([...haystack.matchAll(/L1\s*\/\s*(\d{2})/gi)].map((m) => m[1]));
  const out: Record<string, string> = {};
  for (const [field, f] of Object.entries(key)) {
    if (field.startsWith('_') || f.value === 'not_counted') continue;
    if (field === 'address_count') { out[field] = addrs.size === f.value ? 'RIGHT' : `WRONG (${addrs.size})`; continue; }
    if (field === 'sound_levels_dba') { const v = [...haystack.matchAll(/(\d{2})\s*dBA/gi)].map((m) => Number(m[1])); out[field] = v.length ? `PARTIAL ${Math.min(...v)}-${Math.max(...v)}` : 'WRONG'; continue; }
    const vals = (Array.isArray(f.value) ? f.value : [f.value]).map(String).filter((v) => norm(v).length > 1);
    if (!vals.length) { out[field] = 'n/a'; continue; }
    const hit = vals.filter((v) => h.includes(' ' + norm(v) + ' ')).length;
    out[field] = hit === vals.length ? 'RIGHT' : hit ? `PARTIAL ${hit}/${vals.length}` : 'WRONG';
  }
  return out;
}

/** AFTER: each keyed field against the structured read. */
export function scoreRead(key: Record<string, Field>, r: DrawingRead) {
  const tb = r.title_block; const lp = r.loops.find((l) => l.loop === 'L1');
  const eq = (a: unknown, b: unknown) => (norm(String(a ?? '')) === norm(String(b ?? '')) ? 'RIGHT' : `WRONG (${a ?? '—'})`);
  const list = (got: string[], want: string[]) => { const g = new Set(got.map(norm)); const hit = want.filter((w) => g.has(norm(w))).length; return hit === want.length ? 'RIGHT' : hit ? `PARTIAL ${hit}/${want.length}` : 'WRONG'; };
  const legendTypes = (key.legend_device_types.value as string[]).map((t) => deviceTypeOf(t)!.type);
  const db = r.sound_levels_dba; const dbk = key.sound_levels_dba.value as { min: number; max: number };
  return {
    drawing_type: eq(tb.drawing_type, key.drawing_type.value),
    drawing_title: eq(tb.drawing_title, key.drawing_title.value),
    client: eq(tb.client, key.client.value),
    site: list(tb.site, key.site.value as string[]),
    project: eq(tb.project, key.project.value),
    company: eq(tb.company, key.company.value),
    drawing_ref: eq(tb.drawing_ref, key.drawing_ref.value),
    revision: eq(tb.revision, key.revision.value),
    issue: eq(tb.issue, key.issue.value),
    revision_history: list(tb.revision_history, key.revision_history.value as string[]),
    scale: eq(tb.scale, key.scale.value),
    date: eq(tb.date, key.date.value),
    drawn_by: eq(tb.drawn_by, key.drawn_by.value),
    loop: eq(lp?.loop, key.loop.value),
    address_range: eq(lp ? `L1/01 to L1/${String(lp.highest).padStart(2, '0')}` : null, key.address_range.value),
    address_count: lp && lp.highest === key.address_count.value ? 'RIGHT' : `WRONG (highest ${lp?.highest ?? '—'}, ${lp?.read.length ?? 0} distinct read)`,
    fap_location: eq(r.fap_location, key.fap_location.value),
    legend_device_types: list(r.legend.map((e) => e.type), legendTypes),
    notes: list([r.notes.cable ? `All cable installed using ${r.notes.cable} unless otherwise stated` : '', r.notes.isolators || ''], key.notes.value as string[]),
    sound_levels_dba: db.length ? (Math.min(...db) === dbk.min && Math.max(...db) === dbk.max ? 'RIGHT' : `PARTIAL ${Math.min(...db)}-${Math.max(...db)}`) : 'WRONG',
    rooms: list(r.rooms, key.rooms.value as string[]),
  } as Record<string, string>;
}

// sharp is loaded LAZILY: its module reads process.env on load, and the suite runner
// (scripts/checks/run.mjs) grants no permissions, so a top-level import crashed the whole file
// instead of letting this test report itself ignored (measured 14 Sep 2026: 357 passed, 1 failed).
// deno-lint-ignore no-explicit-any
let sharp: any;
const loadSharp = async () => { if (!sharp) sharp = (await import('npm:sharp')).default; return sharp; };

/** The OCR plan, exactly as the browser runs it, with sharp standing in for the canvas. */
async function ocrPlan(bytes: Uint8Array) {
  await loadSharp();
  const meta = await sharp(bytes).metadata();
  const worker = await createWorker('eng', 1, { langPath: LANG, gzip: true, cacheMethod: 'none' });
  const all: (OcrLine & { pass: number })[] = [];
  try {
    for (let pi = 0; pi < OCR_PASSES.length; pi++) {
      const p = OCR_PASSES[pi]; const s = scaleFor(p, meta.width!, meta.height!);
      const W = Math.round(meta.width! * s), H = Math.round(meta.height! * s);
      const raw = await sharp(bytes).flatten({ background: '#ffffff' }).resize(W, H, { kernel: 'lanczos3' }).removeAlpha().raw().toBuffer();
      const g = binarize(new Uint8Array(raw), 3, W, H);
      // deno-lint-ignore no-explicit-any
      await worker.setParameters({ tessedit_pageseg_mode: p.psm as any, user_defined_dpi: '300' } as any);
      for (const t of tiles(W, H, p.tile)) {
        const png = await sharp(Buffer.from(g), { raw: { width: W, height: H, channels: 1 } }).extract({ left: t.x, top: t.y, width: t.w, height: t.h }).png().toBuffer();
        // deno-lint-ignore no-explicit-any
        const { data } = await worker.recognize(png, {}, { blocks: true } as any) as any;
        for (const b of data.blocks || []) for (const par of b.paragraphs || []) for (const ln of par.lines || []) {
          const bb = ln.bbox; all.push({ text: ln.text, pass: pi, bbox: { x: (t.x + bb.x0) / s, y: (t.y + bb.y0) / s, w: (bb.x1 - bb.x0) / s, h: (bb.y1 - bb.y0) / s } });
        }
      }
    }
  } finally { await worker.terminate(); }
  return { lines: mergeLines(all), width: meta.width!, height: meta.height! };
}

const tally = (s: Record<string, string>) => Object.values(s).filter((v) => v === 'RIGHT').length;

const CAN = Deno.permissions.querySync({ name: 'read' }).state === 'granted' && Deno.permissions.querySync({ name: 'env' }).state === 'granted' && Deno.permissions.querySync({ name: 'ffi' }).state === 'granted';
Deno.test({ name: 'drawing image: before/after per field vs the answer key, symbol counter cross-check (no model)', ignore: !CAN, sanitizeResources: false, sanitizeOps: false }, async () => {
  await loadSharp();
  const key = JSON.parse(await Deno.readTextFile(KEY));
  const bytes = await Deno.readFile(FIXTURE);

  // BEFORE — one plain pass, the old reader.
  const w0 = await createWorker('eng', 1, { langPath: LANG, gzip: true, cacheMethod: 'none' });
  let plain = '';
  try { plain = (await w0.recognize(bytes)).data.text; } finally { await w0.terminate(); }
  const before = scoreHaystack(key, JSON.stringify(boqFromExtracted(empty('image'), '', plain)));

  // AFTER — the plan and the drawing reader.
  const t0 = Date.now();
  const { lines, width, height } = await ocrPlan(bytes);
  const ocrMs = Date.now() - t0;
  const { data, info } = await sharp(bytes).flatten({ background: '#ffffff' }).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  const rows = legendRows(lines, width, deviceTypeOf);
  const sym = countSymbols({ w: info.width, h: info.height, px: new Uint8Array(data), channels: 3 }, rows);
  const read0 = readDrawing(lines, {}, width);
  const addr = read0.loops.find((l) => l.loop === 'L1')?.highest ?? null;
  const check = crossCheck(sym.counts, addr);
  const after = scoreRead(key, read0);

  console.log(`\nimage ${width}x${height}; OCR plan ${lines.length} lines in ${(ocrMs / 1000).toFixed(1)} s; symbol counter ${sym.ms} ms`);
  console.table(Object.keys(after).map((f) => ({ field: f, confidence: key[f]?.confidence, before: before[f] ?? 'n/a', after: after[f] })));
  console.log(`RIGHT before ${tally(before)} / after ${tally(after)} of ${Object.keys(after).length}`);
  console.log('symbol counts (estimates):', JSON.stringify(sym.counts));
  console.log('cross-check vs loop addresses:', JSON.stringify(check), check.agrees ? '-> counts may be offered as our count' : '-> totals disagree: per-type counts stay "to be confirmed"');

  // The drawing's BOQ as drawing_boq builds it from what the portal sends (drawingInput redoes the
  // cross-check server-side and writes its result into each count's basis).
  const out = boqFromExtracted(empty('image'), '', '', drawingInput(lines, width, { counts: sym.counts }, ''));
  console.log(`BOQ: ${out.boq.length} lines, category ${out.category}`);
  console.table(out.boq.map((b) => ({ description: b.description, qty: b.qty, estimate: (b as { estimate?: number }).estimate ?? null, unit: b.unit, status: (b as { qty_status?: string }).qty_status ?? '' })));

  // Never regress.
  assert(lines.length > 50, 'OCR plan read almost nothing');
  assertEquals(read0.category, 'safety');
  // The fields measured RIGHT on 14 Sep 2026; any of them turning WRONG is a regression.
  for (const f of ['drawing_type', 'drawing_title', 'client', 'project', 'drawing_ref', 'revision', 'issue', 'date', 'loop', 'legend_device_types']) assertEquals(after[f], 'RIGHT', `${f} regressed: ${after[f]}`);
  assert(tally(after) > tally(before), 'the drawing reader must beat the old path');
  const supplierText = norm(JSON.stringify({ boq: out.boq, keywords: out.keywords, summary: out.summary }));
  for (const id of read0.identity) assert(!supplierText.includes(norm(id)), `identity "${id}" reached the supplier BOQ`);
  // Every device line carries our count as an estimate to confirm — never as a settled quantity.
  for (const b of out.boq as { type?: string; qty: number | null; qty_status?: string }[]) if (b.type && b.type in sym.counts) { assertEquals(b.qty, null); assertEquals(b.qty_status, 'to_confirm'); }
});
