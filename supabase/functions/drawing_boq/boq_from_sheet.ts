// boq_from_sheet — a customer's OWN bill of quantities (xlsx / xls / csv) read into the same shape
// boqFromPages returns, with no model (14 Sep 2026).
//
// WHY. Founder, 14 Sep 2026: "describe a job / drop a drawing is fine but add attach a BOQ also".
// The composer accepted images, PDF and CAD only, so a BOQ in Excel or CSV — the form a UAE BOQ
// usually travels in — could not be attached at all. A spreadsheet BOQ is already a table of
// quantities; reading it needs no model, so it works under the model hold.
//
// WHAT IT READS. The first sheet (of up to 20) that has a header row within its first 30 rows naming
// a QUANTITY column and a DESCRIPTION or ITEM column, in English or Arabic. Under it, one BOQ line per
// row that says what it is. A row with a description but no quantity and no unit is a section heading.
// Totals, carried-forward and blank rows are skipped. Rate / price / amount columns are NEVER read:
// the brief goes to competing suppliers, and the customer's own prices are not theirs to see.
//
// WHAT IT NEVER DOES. Evaluate a formula (SheetJS returns the value the file cached, or nothing),
// run a macro (sanitizeUpload refuses a workbook carrying a VBA project), open an encrypted workbook,
// or expand a zip it has not costed first. Identity (emails, URLs, UAE phones, company names) is
// scrubbed from every cell with the same scrubIdentity the drawing path uses.
//
// SheetJS 0.20.3, VENDORED in _shared/vendor/sheetjs-0.20.3 (fetched 14 Sep 2026 from
// cdn.sheetjs.com/xlsx-0.20.3/package, the vendor's only distribution of 0.20.x). Not npm: the npm
// `xlsx` package stopped at 0.18.5, which carries CVE-2023-30533 (prototype pollution on read) and
// CVE-2024-22363 (ReDoS), and this parser reads files from anonymous customers. Not a CDN URL: Deno 2
// refuses imports from hosts outside its default list without --allow-import, which `deno check`,
// `deno test` and the deploy bundler are all run without. Vendoring is the route SheetJS documents.
// sha256 at vendoring: xlsx.mjs 1a0fb062ee9781b13f6687371b202aaefc53b6ce55b530c027e01f9c087b77db,
// types/index.d.ts 191e4e6aceae3602aa3a1e9a6bc0e98821d6d5fb787e2bc16e250439482bddb6.
// @deno-types="../_shared/vendor/sheetjs-0.20.3/types/index.d.ts"
import * as XLSX from '../_shared/vendor/sheetjs-0.20.3/xlsx.mjs';
import { sanitizeUpload, zipExpansionWithinLimits, SAFE_SHEET } from '../_shared/attachment.ts';
import { scrubIdentity, type BoqItem } from './boq_from_text.ts';

export const MAX_SHEET_BYTES = 5 * 1024 * 1024;
export const MAX_ROWS = 500;
const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const XLS_MIME = 'application/vnd.ms-excel';

type Cell = string | number | boolean | null | undefined;
type Role = 'ref' | 'desc' | 'qty' | 'unit' | 'price';

/** A quantity as written: plain numbers, "1,250.5", Arabic-Indic digits. Anything else is null. */
function num(v: Cell): number | null {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  // ponytail: a comma is read as a thousands separator, so a European "12,5" reads as 125. UAE BOQs
  // write "1,250.50"; add a locale guess if a real file ever arrives the other way.
  const s = String(v ?? '').trim()
    .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x660))
    .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x6F0))
    .replace(/٫/g, '.').replace(/[٬,\s]/g, '');
  if (!/^-?\d+(\.\d+)?$/.test(s)) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

const norm = (v: Cell) => String(v ?? '').toLowerCase().replace(/[\s._#:()\-\/]+/g, ' ').trim();
function roleOf(h: string): Role | null {
  if (!h) return null;
  if (/(qty|quantity|quantities|الكمية|الكميه|كمية)/.test(h)) return 'qty';
  if (/(rate|price|amount|total|cost|value|سعر|السعر|المبلغ|الإجمالي|الاجمالي|القيمة)/.test(h)) return 'price';
  if (/^(unit|units|uom|u o m|unit of measure|الوحدة|الوحده|وحدة)$/.test(h)) return 'unit';
  if (/(description|particulars|scope|specification|works?$|الوصف|وصف|البيان)/.test(h)) return 'desc';
  if (/^(item|items|item no|item ref|no|s no|sr no|sl no|sn|ref|code|البند|رقم البند|رقم|م)$/.test(h)) return 'ref';
  return null;
}

function findHeader(rows: Cell[][]): { row: number; cols: Partial<Record<Role, number>> } | null {
  for (let r = 0; r < Math.min(rows.length, 30); r++) {
    const cols: Partial<Record<Role, number>> = {};
    (rows[r] || []).forEach((c, i) => { const k = roleOf(norm(c)); if (k && cols[k] === undefined) cols[k] = i; });
    if (cols.qty === undefined || (cols.desc === undefined && cols.ref === undefined)) continue;
    // A sheet headed "Item | Qty | Unit" keeps its descriptions in the Item column.
    if (cols.desc === undefined) { cols.desc = cols.ref; delete cols.ref; }
    return { row: r, cols };
  }
  return null;
}

const TOTAL = /^(sub ?total|grand total|total|carried (forward|over)|brought forward|c\/f|b\/f|المجموع|الإجمالي|الاجمالي|إجمالي|اجمالي)/i;
// A cell a spreadsheet would treat as a formula if this BOQ were ever exported again (CSV injection).
const cellText = (v: Cell, max: number) => scrubIdentity(String(v ?? '').replace(/\s+/g, ' ').trim()).replace(/^[=+@]+/, '').trim().slice(0, max);

/** Rows of cells (cached values, never formulas) -> the BOQ shape drawing_boq returns. */
export function boqFromRows(rows: Cell[][], where: string, hint = '') {
  const h = findHeader(rows);
  const boq: BoqItem[] = [];
  const assumptions = ['Quantities and units are exactly as written in the customer’s BOQ; nothing was re-measured or recalculated.'];
  const missing: string[] = [];
  let noQty = 0, truncated = false, section = 'BOQ';
  if (!h) missing.push('No header row naming a quantity column and a description or item column was found in the first 30 rows.');
  else {
    if (h.cols.price !== undefined) assumptions.push('Rate, price and amount columns were not read, so no prices are passed to suppliers.');
    const at = (row: Cell[], k: Role) => (h.cols[k] === undefined ? '' : row[h.cols[k]!]);
    for (let i = h.row + 1; i < rows.length; i++) {
      if (boq.length >= MAX_ROWS) { truncated = true; break; }
      const row = rows[i] || [];
      const desc = cellText(at(row, 'desc'), 200);
      const ref = cellText(at(row, 'ref'), 20);
      const qty = num(at(row, 'qty'));
      const unit = cellText(at(row, 'unit'), 20).toLowerCase();
      if (TOTAL.test(desc) || TOTAL.test(ref)) continue;
      if (!desc) continue;                                                 // blank, or a number that says nothing
      if (qty == null && !unit) { section = desc.slice(0, 80); continue; } // a section heading
      if (qty == null) noQty++;
      boq.push({ section, item: ref || desc.slice(0, 120), description: desc, qty, unit, basis: `${where}, row ${i + 1}`,
                 confidence: qty != null && unit ? 'medium' : 'low' });
    }
    if (!boq.length) missing.push('A header row was found, but no item lines with a description under it.');
  }
  if (noQty) missing.push(`${noQty} line(s) have no quantity written.`);
  if (truncated) missing.push(`Only the first ${MAX_ROWS} lines were read; the rest of the file was not.`);
  return {
    drawing_type: '', category: '', summary: scrubIdentity(hint).slice(0, 200), scale_detected: '',
    total_area_sqm: null as number | null, area_tags_sqm: [] as number[],
    boq, keywords: [] as string[], assumptions, missing_info: missing,
    // 'medium', not 'high': the quantities are the customer's own, only our reading of the columns can be wrong.
    confidence: (boq.length && !noQty ? 'medium' : 'low') as 'low' | 'medium',
    method: 'spreadsheet', source: where, rows_read: boq.length,
  };
}

/** A small RFC 4180 reader: quoted cells, doubled quotes, comma / semicolon / tab chosen from line 1. */
export function parseCsv(text: string): string[][] {
  const t = text.replace(/^﻿/, '');
  const first = t.split(/\r?\n/, 1)[0] || '';
  const delim = ([',', ';', '\t'] as const).map((d) => [d, first.split(d).length] as const).sort((a, b) => b[1] - a[1])[0][0];
  const rows: string[][] = [];
  let row: string[] = [], cell = '', q = false;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (q) { if (c === '"') { if (t[i + 1] === '"') { cell += '"'; i++; } else q = false; } else cell += c; continue; }
    if (c === '"') q = true;
    else if (c === delim) { row.push(cell); cell = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && t[i + 1] === '\n') i++;
      row.push(cell); rows.push(row); row = []; cell = '';
      if (rows.length > MAX_ROWS + 60) return rows;                      // enough for the cap plus a header block
    } else cell += c;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  return rows;
}

function hasUtf16(b: Uint8Array, s: string): boolean {
  const n = new Uint8Array(s.length * 2); for (let i = 0; i < s.length; i++) n[i * 2] = s.charCodeAt(i);
  outer: for (let i = 0; i + n.length <= b.length; i++) { for (let j = 0; j < n.length; j++) if (b[i + j] !== n[j]) continue outer; return true; }
  return false;
}

export type SheetOutcome = { ok: true; boq: ReturnType<typeof boqFromRows> } | { ok: false; error: string; detail: string };
const ENCRYPTED: SheetOutcome = { ok: false, error: 'encrypted', detail: 'the workbook is password-protected' };

/** base64 or bytes from the customer -> a BOQ, or a refusal with a reason. Type is decided by the BYTES. */
export function boqFromSheet(input: Uint8Array | string, declaredMime: string, filename: string, hint = ''): SheetOutcome {
  const s = sanitizeUpload({ input, declaredMime, filename, allow: SAFE_SHEET, maxBytes: MAX_SHEET_BYTES });
  if (!s.ok) return { ok: false, error: s.error, detail: s.detail };
  if (s.mime === 'text/csv') return { ok: true, boq: boqFromRows(parseCsv(new TextDecoder().decode(s.bytes)), 'CSV', hint) };
  // An encrypted .xlsx is an OLE2 container holding an EncryptionInfo stream, so it sniffs as .xls.
  if (s.mime === XLS_MIME && hasUtf16(s.bytes, 'EncryptionInfo')) return ENCRYPTED;
  if (s.mime === XLSX_MIME) {
    const z = zipExpansionWithinLimits(s.bytes, { maxEntries: 256, maxTotalBytes: 32 * 1024 * 1024, maxRatio: 120 });
    if (!z.ok) return { ok: false, error: z.error, detail: z.detail };
  }
  let wb: XLSX.WorkBook;
  try {
    wb = XLSX.read(s.bytes, { type: 'array', cellFormula: false, cellHTML: false, cellNF: false, cellStyles: false, bookVBA: false, sheetRows: MAX_ROWS + 60 });
  } catch (e) {
    const m = String((e as Error)?.message || e);
    return /password|encrypt/i.test(m) ? ENCRYPTED : { ok: false, error: 'unreadable_workbook', detail: m.slice(0, 160) };
  }
  let firstOut: ReturnType<typeof boqFromRows> | null = null;
  for (const name of wb.SheetNames.slice(0, 20)) {
    const rows = XLSX.utils.sheet_to_json<Cell[]>(wb.Sheets[name], { header: 1, raw: true, defval: '', blankrows: true });
    const out = boqFromRows(rows, `sheet "${cellText(name, 40)}"`, hint);
    if (out.boq.length) return { ok: true, boq: out };
    firstOut ??= out;
  }
  return firstOut ? { ok: true, boq: firstOut } : { ok: false, error: 'unreadable_workbook', detail: 'the workbook has no sheets' };
}
