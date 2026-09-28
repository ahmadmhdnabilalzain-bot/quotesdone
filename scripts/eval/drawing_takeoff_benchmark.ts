// drawing_takeoff_benchmark — HOW ACCURATE IS THE DRAWING TAKE-OFF? (28 Sep 2026, sales_engineer)
//
// Runs the reader's REAL pure code on the ZZ DEMO drawings in tests/fixtures/drawings/zz_demo/ (written by
// drawing_takeoff_zz_demo_gen.ts) and scores it against ground_truth.json. No model, no network, no database.
//   DXF: readDocument (_shared/doc_read) -> boqFromExtracted, the path drawing_boq/index.ts takes for a file.
//   PDF: pdfPages(layers:false) -> boqFromDrawingSet (else boqFromPages), then the 'lengths' call:
//        mergeLengths(set, lengthsForSet(pdfPages(bytes))) — the two calls drawing_boq/index.ts makes.
// cad_convert is not scored: it is a rasteriser that hands the file to CloudConvert and reads nothing
// (its own header says so); a DWG is read by _shared/doc_read/dwg.ts into this same DXF take-off.
//
// Per item, the quantity read is the SUM of the lines matching it (the take-off writes one line per
// equipment id, so FCU-1 and FCU-2 are two lines of 1): recall = min(read, truth) / truth, precision =
// min(read, truth) / read (a doubled count halves it), quantity error % = |read - truth| / truth.
// Overall: recall = items found / items; precision = lines matching an item / lines with a quantity, so
// every line that matches no item (e.g. the A-WALL linework) is a false positive.
//   deno run -A scripts/eval/drawing_takeoff_benchmark.ts [--json]
// Exits 1 when the score falls below the floor measured on 28 Sep 2026 (THRESHOLDS below).
import { readDocument } from '../../supabase/functions/_shared/doc_read/index.ts';
import { pdfPages } from '../../supabase/functions/_shared/pdf_text_positions.ts';
import { boqFromExtracted } from '../../supabase/functions/drawing_boq/boq_from_document.ts';
import { boqFromDrawingSet, lengthsForSet, mergeLengths } from '../../supabase/functions/drawing_boq/drawing_set.ts';
import { boqFromPages } from '../../supabase/functions/drawing_boq/boq_from_text.ts';

// The measured baseline (28 Sep 2026): 18 of 22 items found, every found quantity exact; 19 of 21 lines
// matched (the 2 misses are the A-WALL linework of the two DXFs). The 4 missed items are the whole
// lighting/power PDF: the PDF take-off knows plumbing and HVAC tags only, so light fittings (LT-1),
// sockets (DS-1), doors (D-1) and detectors (SD) on a PDF are not counted. A regression fails the run;
// raise a floor when the reader improves.
const THRESHOLDS = { recall: 0.818, precision: 0.905, maxMeanQtyErrPct: 0 };

type Item = { id: string; trade: string; match: string; qty: number; unit: 'nos' | 'm' };
type Line = { type?: string; description: string; qty: number | null; unit: string };
const DIR = new URL('../../tests/fixtures/drawings/zz_demo/', import.meta.url);
const truth: Record<string, { format: 'dxf' | 'pdf'; items: Item[] }> = JSON.parse(await Deno.readTextFile(new URL('ground_truth.json', DIR)));

async function takeoff(name: string, format: 'dxf' | 'pdf'): Promise<Line[]> {
  const bytes = await Deno.readFile(new URL(name, DIR));
  if (format === 'dxf') {
    const r = await readDocument(bytes, name, 'image/vnd.dxf');
    if (!r.ok) throw new Error(`${name}: the reader refused it (${JSON.stringify(r)})`);
    return boqFromExtracted(r).boq as Line[];
  }
  const pages = await pdfPages(bytes, undefined, { layers: false });
  const set = boqFromDrawingSet(pages);
  if (!set) return boqFromPages(pages).boq as Line[];
  return mergeLengths({ ...set, missing_info: set.missing_info }, lengthsForSet(await pdfPages(bytes))).boq as Line[];
}

const inM = (l: Line) => l.qty == null ? null : /^(ft|lf|lin\.? ?ft)$/i.test(l.unit) ? l.qty * 0.3048 : l.qty;
const rows: { file: string; item: string; trade: string; truth: number; read: number | null; recall: number; precision: number; errPct: number | null }[] = [];
let tp = 0, predicted = 0, matchedLines = 0;
for (const [file, { format, items }] of Object.entries(truth)) {
  const lines = (await takeoff(file, format)).filter((l) => l.qty != null);
  predicted += lines.length;
  const hit = new Set<Line>();
  for (const it of items) {
    const re = new RegExp(it.match, 'i');
    const ms = lines.filter((l) => re.test(`${l.type || ''} ${l.description}`) && (it.unit === 'nos' ? /^(nos|no|ea|each|nr)$/i.test(l.unit) : inM(l) !== l.qty || /^m$/i.test(l.unit)));
    ms.forEach((l) => hit.add(l));
    const val = (l: Line) => it.unit === 'm' ? inM(l)! : l.qty!;
    const read = ms.length ? +ms.reduce((s, l) => s + val(l), 0).toFixed(2) : null;
    if (read != null) tp++;
    const ok = read == null ? 0 : Math.min(read, it.qty);
    rows.push({ file, item: it.id, trade: it.trade, truth: it.qty, read, recall: +(ok / it.qty).toFixed(3), precision: read ? +(ok / read).toFixed(3) : 0, errPct: read == null ? null : +(Math.abs(read - it.qty) / it.qty * 100).toFixed(1) });
  }
  matchedLines += hit.size;
}
const total = rows.length;
const found = rows.filter((r) => r.errPct != null);
const score = {
  items: total, found: tp,
  recall: +(tp / total).toFixed(3),
  precision: predicted ? +(matchedLines / predicted).toFixed(3) : 0,
  meanQtyErrPct: found.length ? +(found.reduce((s, r) => s + r.errPct!, 0) / found.length).toFixed(1) : 0,
  exactQty: rows.filter((r) => r.errPct === 0).length,
  byFormat: Object.fromEntries(['dxf', 'pdf'].map((f) => { const rs = rows.filter((r) => truth[r.file].format === f); return [f, { items: rs.length, found: rs.filter((r) => r.recall).length }]; })),
};

if (Deno.args.includes('--json')) console.log(JSON.stringify({ score, rows }, null, 2));
else {
  console.table(rows.map((r) => ({ file: r.file, item: r.item, truth: r.truth, read: r.read ?? '-', recall: r.recall, precision: +r.precision.toFixed(2), 'qty err %': r.errPct ?? '-' })));
  console.log(JSON.stringify(score));
}
const fails = [
  score.recall < THRESHOLDS.recall && `recall ${score.recall} < ${THRESHOLDS.recall}`,
  score.precision < THRESHOLDS.precision && `precision ${score.precision} < ${THRESHOLDS.precision}`,
  score.meanQtyErrPct > THRESHOLDS.maxMeanQtyErrPct && `mean qty error ${score.meanQtyErrPct}% > ${THRESHOLDS.maxMeanQtyErrPct}%`,
].filter(Boolean);
if (fails.length) { console.error('BELOW THE MEASURED FLOOR: ' + fails.join('; ')); Deno.exit(1); }
