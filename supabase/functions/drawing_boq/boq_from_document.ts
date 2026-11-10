// boq_from_document — any document doc_read can open, turned into the customer BOQ shape drawing_boq
// has always returned ({boq, assumptions, missing_info, confidence, ...}).
//
// WHY (14 Sep 2026). Founder: "the sales agent need to be extremely capable of reading all types of
// document." doc_read says what a file contains; this decides what of it becomes a BOQ line a
// supplier sees, and it is the single place the CUSTOMER rules are applied:
//   * a table is read through boqFromRows, which finds the header (NRM / FIDIC / MasterFormat /
//     DIN 276 / Arabic) and NEVER reads a rate, price or amount column;
//   * quantities a format states or measures (DXF, DWG, GAEB, a scaled PDF) are kept as they are;
//   * free text is read line by line through boqFromLines, AFTER every currency amount and "@ rate"
//     is stripped, so a price written in a sentence does not reach a competing supplier either;
//   * every string passes scrubIdentity (emails, URLs, UAE phones, company names).
// Text lines of a document are only read when none of its tables produced a line: a Word BOQ carries
// the same rows as table cells and as text, and reading both would count every item twice.
//
// DRAWINGS (14 Sep 2026). A photographed or scanned DRAWING states almost nothing as "<qty> <unit>",
// so its OCR also goes through drawing_from_ocr.readDrawing (title block, legend, notes, loop
// addresses). Its lines join the BOQ; the title block's client / site / project / company / reference
// / drawn-by values are removed from EVERY string that leaves here, because they identify the
// customer to a competing supplier. A CAD file's block counts (doc_read/cad.ts: "block SD-1 inserted
// 24 times") are mapped to the same device types — that count is exact, and is marked 'read'.
import type { Extracted } from '../_shared/doc_read/types.ts';
import { boqFromLines, scrubIdentity, type BoqItem } from './boq_from_text.ts';
import { boqFromRows, MAX_ROWS } from './boq_from_sheet.ts';
import { readDrawing, type Counts, type OcrLine } from './drawing_from_ocr.ts';
import { deviceTypeOf } from './legend_vocabulary.ts';
import { printedLines } from './symbol_count.ts';
import { validateBoq } from '../_shared/boq_validate.ts';
import { isQuotation, QUOTATION_NOTE, quotationPartyTerms, scrubTerms } from './quotation_parties.ts';
import { measureServices } from './linear_services.ts';
import { neutralCadName } from '../_shared/cad_identity.ts';
import { regionTakeoff, type RoomRow } from './region_takeoff.ts';

export type DrawingInput = { lines?: OcrLine[]; width?: number; counts?: Counts };

/** Remove each identity value (case-insensitive, whole phrase) from a string. */
export function scrubValues(s: string, values: string[]): string {
  let t = String(s || '');
  for (const v of values) { if (v.length < 2) continue; t = t.replace(new RegExp(v.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '\\s+'), 'gi'), ''); }
  return t.replace(/\s{2,}/g, ' ').trim();
}

const CUR = '(?:AED|Dhs?\\.?|د\\.?\\s?إ\\.?|درهم|USD|US\\$|\\$|€|£|EUR|GBP|SAR|ريال)';
const PRICE = new RegExp(`${CUR}\\s*[\\d.,]+|[\\d.,]+\\s*${CUR}|(?:@|\\brate\\b[:\\s]*|\\bunit price\\b[:\\s]*|\\bprice\\b[:\\s]*|\\bamount\\b[:\\s]*|السعر[:\\s]*|المبلغ[:\\s]*)\\s*[\\d.,]+`, 'gi');
/** Remove every currency amount and "@ 85" / "rate 85" figure from a line of customer text. */
export const stripPrices = (s: string) => s.replace(PRICE, ' ').replace(/\s{2,}/g, ' ').trim();

/** OCR lines (one per table CELL in sparse-text mode) back into printed ROWS: each printed line once (its longest
 *  reading), cells on the same baseline joined left to right. 19 Oct 2026 drawing bench: a photographed BOQ read 0 of
 *  4 lines because description, unit and quantity came back as separate lines. */
export function rowsOf(lines: OcrLine[]): string {
  const rows: OcrLine[][] = [];
  for (const l of printedLines(lines).sort((a, b) => a.bbox.y - b.bbox.y)) {
    const cy = l.bbox.y + l.bbox.h / 2;
    const row = rows.find((r) => Math.abs(r[0].bbox.y + r[0].bbox.h / 2 - cy) < Math.max(4, r[0].bbox.h * 0.6));
    if (row) row.push(l); else rows.push([l]);
  }
  return rows.map((r) => r.sort((a, b) => a.bbox.x - b.bbox.x).map((l) => l.text.trim()).join(' ')).join('\n');
}

export function boqFromExtracted(ex: Extracted, hint = '', ocrText = '', drawing: DrawingInput = {}) {
  const boq: (BoqItem & { type?: string; qty_status?: string; estimate?: number | null; section_ar?: string; description_ar?: string })[] = [];
  const rooms: RoomRow[] = [];
  const disciplines: Record<string, { exact: string[]; assumed: string[] }> = {};
  const missing: string[] = [];
  const assumptions = new Set<string>(['Every line is exactly as written in the customer’s document; nothing was re-measured, and no price was read.']);
  const kinds: string[] = [];
  const layouts = new Set<string>();

  const fromText = (text: string, where: string, confidence?: 'low') => {
    const lines = text.split('\n').map(stripPrices).filter((t) => t.length > 2).map((t) => ({ page: 1, text: t }));
    for (const b of boqFromLines(lines)) {
      // OCR TEXT IS NEVER "READY" (21 Sep 2026, founder instruction 580). Measured on a real 8-sheet
      // mechanical set: the portal's whole-page OCR at ~72 dpi produced 4 lines of noise ("Ere Mill || + |
      // I 0 99 5" = 2 m), each with a qty and no qty_status, so NewRequest marked the brief ready with
      // invented quantities. A line read from OCR carries its number as OUR estimate to confirm.
      boq.push({ ...b, section: where, basis: b.basis.replace(/^printed on page \d+/, `written in ${where}`).replace(/^schedule row on page \d+/, `row in ${where}`), ...(confidence ? { confidence, qty_status: 'to_confirm', estimate: b.qty } : {}) });
    }
  };

  const visit = (e: Extracted, where: string) => {
    kinds.push(e.kind);
    let tableItems = 0, priced = false;
    const fromTables: BoqItem[] = [];
    e.tables.forEach((t, i) => {
      const r = boqFromRows(t, `${where}, table ${i + 1}`);
      if (!r.boq.length) return;
      tableItems += r.boq.length;
      fromTables.push(...r.boq);
      priced ||= r.assumptions.some((a) => /^Rate, price and amount columns were not read/.test(a));
      r.assumptions.forEach((a) => assumptions.add(a));
      if ((r as { layout?: string }).layout) layouts.add(String((r as { layout?: string }).layout));
    });
    // A COMPETITOR'S QUOTATION printed as a PDF (10 Nov 2026): its table rows came back as tables (doc_read/word_tables),
    // and the letterhead, the To / Attn / Project block, the terms and the signature are the text lines around them.
    if (fromTables.length && e.text && isQuotation(e.text, priced)) {
      const cells = e.tables.flat(2).map((c) => String(c ?? '').trim()).filter((c) => c.length >= 6);
      const around = e.text.split('\n').filter((l) => !cells.some((c) => l.includes(c.slice(0, 40))));
      const terms = quotationPartyTerms(around);
      if (terms.length) for (const b of fromTables) { b.description = scrubTerms(b.description, terms); b.item = scrubTerms(b.item, terms); if (b.specification) b.specification = scrubTerms(b.specification, terms); }
      assumptions.add(QUOTATION_NOTE);
    }
    boq.push(...fromTables);
    // THE ENGINEER'S TAKE-OFF OF A CAD FILE (10 Nov 2026; founder 10 Nov and ruling 1586): rooms, finishes, walls,
    // ceilings, skirting, door / window schedules and every other trade's regions (region_takeoff.ts), and duct, pipe,
    // tray, conduit, steel and other runs by size (linear_services.ts). A layer or block they measured is not listed
    // again as raw linework or a bare block count.
    const usedLayers = new Set<string>(), usedBlocks = new Set<string>();
    let engineered = false;
    if (e.cad) {
      const rt = regionTakeoff(e.cad), sv = measureServices(e.cad);
      engineered = rt.lines.length + sv.lines.length > 0;
      for (const l of [...rt.lines, ...sv.lines]) boq.push({ ...l, section: scrubIdentity(l.section), item: scrubIdentity(l.item).slice(0, 120), description: scrubIdentity(l.description).slice(0, 200), basis: scrubIdentity(l.basis).slice(0, 300) });
      rooms.push(...rt.rooms.map((r) => ({ ...r, name: scrubIdentity(r.name).slice(0, 60) })));
      for (const [k, v] of Object.entries(rt.disciplines)) disciplines[k] = { exact: [...new Set(v.exact)], assumed: [...new Set(v.assumed)] };
      for (const [d, secs] of [['mep services', ['Ductwork', 'Pipework', 'Cable containment', 'Conduits']], ['structure', ['Structural steel']], ['linear items', ['Linear items']]] as const) {
        const ls = sv.lines.filter((l) => (secs as readonly string[]).includes(l.section)); if (!ls.length) continue;
        const kinds = [...new Set(ls.map((l) => l.section.toLowerCase()))];
        disciplines[d] = { exact: [`${kinds.join(', ')}: length${d === 'structure' ? ', and weight where the section states its mass' : ''} for every run whose printed size is in reach`],
          assumed: ls.filter((l) => l.qty_status === 'to_confirm').map((l) => `${l.description}: size not labelled`) };
      }
      rt.layers.forEach((l) => usedLayers.add(l)); sv.layers.forEach((l) => usedLayers.add(l)); rt.blocks.forEach((b) => usedBlocks.add(b));
      [...rt.assumptions, ...sv.assumptions].forEach((a) => assumptions.add(a));
      missing.push(...rt.missing, ...sv.missing);
      if (e.cad.capped) missing.push(CAD_CAPPED_NOTE);
    }
    let unnamedBlocks = 0;
    for (const q of e.quantities) {
      if (q.section.startsWith('layer ') && usedLayers.has(q.section.slice(6))) continue;
      if (q.section === 'Blocks' && usedBlocks.has(q.description.replace(/^block\s+/i, ''))) continue;
      const d = scrubIdentity(q.description).slice(0, 200);
      if (!d) continue;
      // A CAD block whose name is a device ("SMOKE_DET", "MCP", "FAP") becomes that device's line,
      // counted exactly by the file itself.
      const dev = q.section === 'Blocks' ? deviceTypeOf(d.replace(/^block\s+/i, '').replace(/[_-]+/g, ' ')) : null;
      // The block's own name is shown only as CAD vocabulary (cad_identity.neutralCadName): this line's section is the
      // trade's, so the supplier inbox's neutraliseCadLines (which renames CAD-section lines) does not see it.
      const size = dev ? /(?<![\d.])(\d{3,4}(?:\s*[xX]\s*\d{3,4})?)(?![\d.])/.exec(d.replace(/^block\s+/i, ''))?.[1] : undefined;
      if (dev) { boq.push({ section: dev.section ?? 'Devices (CAD blocks)', type: dev.type, item: size ? `${dev.en} ${size}` : dev.en, description: size ? `${dev.en} ${size}` : dev.en, description_ar: size ? `${dev.ar} ${size}` : dev.ar, qty: q.qty, unit: dev.unit, basis: `block ${neutralCadName(d.replace(/^block\s+/i, ''))} inserted ${q.qty} times (counted from the CAD file)`, confidence: 'medium', qty_status: 'read' }); continue; }
      if (q.section === 'Blocks') unnamedBlocks++;
      boq.push({ section: scrubIdentity(q.section).slice(0, 80) || where, item: d.slice(0, 120), description: d, qty: q.qty, unit: q.unit, basis: scrubIdentity(q.basis).slice(0, 200), confidence: q.confidence });
    }
    if (unnamedBlocks) missing.push(UNNAMED_BLOCKS_NOTE(unnamedBlocks));
    if (!tableItems && e.text) {
      const before = boq.length;
      fromText(e.text, where);
      // A CAD file's door / window schedule is already a line per mark (region_takeoff.ts): a schedule row read again
      // from the text ("D1 SINGLE LEAF DOOR 900x2100 5") is not a second line.
      if (engineered) {
        const marks = new Set(boq.filter((b) => /^opening:/.test(b.type ?? '')).map((b) => b.type!.slice(8)));
        for (let k = boq.length - 1; k >= before; k--) if (marks.has(String(boq[k].item).split(/\s+/)[0].toUpperCase().replace(/[-.]/g, ''))) boq.splice(k, 1);
      }
    }
    for (const n of e.notes) missing.push(scrubIdentity(n));
    for (const c of e.children) visit(c.doc, `${where} › ${scrubIdentity(c.name).slice(0, 60) || 'attachment'}`);
  };
  visit(ex, ex.kind.toUpperCase());

  // THE DRAWING READ. From the OCR lines with boxes when the portal sent them, else from the text.
  const ocrLines = Array.isArray(drawing.lines) && drawing.lines.length ? drawing.lines : null;
  const dr = ocrLines || ocrText ? readDrawing(ocrLines || ocrText, drawing.counts || {}, drawing.width || 0) : null;
  const isDrawing = !!dr && (dr.legend.length > 0 || dr.loops.some((l) => (l.highest || 0) > 0));
  const identity = dr ? dr.identity : [];
  if (dr && isDrawing) {
    for (const b of dr.boq) boq.push({ section: b.section || 'Drawing', item: b.item || b.description, description: b.description, qty: b.qty, unit: b.unit, basis: b.basis || '', confidence: 'low', type: b.type, qty_status: b.qty_status, estimate: b.estimate ?? null });
    for (const m of dr.missing_info) missing.push(m);
    assumptions.add('The drawing was read by OCR in the customer’s browser and by rules on our side; quantities we could not read are shown to the customer as our count to confirm, or marked for the supplier to verify.');
  } else if (ocrLines || ocrText) {
    fromText(ocrLines ? rowsOf(ocrLines) : ocrText, 'OCR of the photo', 'low');
    assumptions.add('The photo was read by OCR in the customer’s browser; OCR can misread digits, so every quantity is marked low confidence.');
  }

  // One line per (description, qty, unit): a zip holding the same sheet twice should not double it.
  const seen = new Set<string>();
  const uniq = boq.filter((b) => { const k = `${b.description.toLowerCase()}|${b.qty}|${b.unit}`; if (seen.has(k)) return false; seen.add(k); return true; })
    // The drawing's own names never leave: every string a supplier could read is scrubbed of them.
    .map((b) => identity.length ? { ...b, item: scrubValues(b.item, identity), description: scrubValues(b.description, identity), basis: scrubValues(b.basis, identity), section: scrubValues(b.section, identity) } : b);
  const lines = uniq.slice(0, MAX_ROWS);
  if (uniq.length > MAX_ROWS) missing.push(`Only the first ${MAX_ROWS} lines were kept.`);
  if (!lines.length) missing.push('No line stating a quantity was found in the document.');
  // The set is checked as a surveyor would (boq_validate.ts). A null qty is already an open line the
  // customer is asked about (boq_open_lines), and a unit we cannot convert is our limit, not the customer's
  // doubt; only the remaining findings become missing_info sentences.
  const validation = validateBoq(lines);
  for (const f of validation) if (f.check === 'bad_qty' || f.check === 'conflict') missing.push(f.say);
  const withQty = lines.filter((b) => b.qty != null).length;
  const tb = dr && isDrawing ? dr.title_block : null;
  return {
    // Drawing type, scale and title describe what is drawn, not who it is for; they may be shown.
    drawing_type: tb?.drawing_type || '', category: isDrawing ? dr!.category : '',
    summary: scrubValues(scrubIdentity(hint), identity).slice(0, 200), scale_detected: tb?.scale || '',
    total_area_sqm: null as number | null, area_tags_sqm: [] as number[],
    boq: lines, ...(rooms.length ? { rooms } : {}), ...(Object.keys(disciplines).length ? { disciplines } : {}), keywords: isDrawing ? [...new Set(dr!.legend.map((e) => e.en.toLowerCase()))].slice(0, 12) : [] as string[],
    assumptions: [...assumptions], missing_info: [...new Set(missing.map((m) => scrubValues(m, identity)))],
    confidence: (lines.length && withQty === lines.length && lines.every((b) => b.confidence === 'medium') ? 'medium' : 'low') as 'low' | 'medium',
    method: 'document', validation: validation.map((f) => ({ check: f.check, lines: f.lines })), kinds, layout: [...layouts].join(',') || null, rows_read: lines.length,
    // The identity values themselves are deliberately NOT returned: this object is posted back by the
    // portal and stored on the RFQ, so carrying them "for redaction" would carry them to suppliers.
  };
}

export const CAD_CAPPED_NOTE = 'The drawing is larger than one reading measures; the rooms and runs above are from the part that was read.';
export const UNNAMED_BLOCKS_NOTE = (n: number) => `${n} block type(s) on the drawing are not in our drawing vocabulary; each is listed by its block name with its exact count, and what it is must be confirmed before suppliers price it.`;
