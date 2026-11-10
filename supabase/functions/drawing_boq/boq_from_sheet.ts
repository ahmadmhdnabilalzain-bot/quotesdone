// boq_from_sheet — a customer's OWN bill of quantities (xlsx / xls / csv) read into the same shape
// boqFromPages returns, with no model (14 Sep 2026).
//
// WHY. Founder, 14 Sep 2026: "describe a job / drop a drawing is fine but add attach a BOQ also".
// The composer accepted images, PDF and CAD only, so a BOQ in Excel or CSV — the form a UAE BOQ
// usually travels in — could not be attached at all. A spreadsheet BOQ is already a table of
// quantities; reading it needs no model, so it works under the model hold.
//
// WHAT IT READS. The first sheet (of up to 20) that has a header row within its first 30 rows naming
// a QUANTITY column and a DESCRIPTION or ITEM column, in English, German or Arabic, as one row or two
// (a merged group heading over its sub-columns, e.g. "Quantity" over "Qty | Unit"). Under it, one BOQ
// line per row that says what it is. A row with a description but no quantity and no unit is a section
// heading ("Bill No. 3 – Substructure", "Element 2.1", "Division 09 – Finishes", "KG 300 ..."). Totals,
// carried-forward, collection and blank rows are skipped. Rate / price / amount columns (Rate, Amount,
// EP, GP, السعر, المبلغ) are NEVER read: the brief goes to competing suppliers, and the customer's own
// prices are not theirs to see.
// The wording of headers, headings and totals names the convention in `layout`: 'nrm' (UK/GCC QS
// bills), 'fidic' (UAE/GCC bills with Bill No. and AED), 'masterformat' (CSI division / section codes),
// 'din276' (German GAEB-style exports, whose "1.250,5" decimals are read the German way), else 'generic'.
// The layout is reported, never required: every layout goes through the same reader.
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
import { isQuotation, QUOTATION_NOTE, quotationPartyTerms, scrubTerms } from './quotation_parties.ts';

export const MAX_SHEET_BYTES = 5 * 1024 * 1024;
export const MAX_ROWS = 500;
const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const XLS_MIME = 'application/vnd.ms-excel';

type Cell = string | number | boolean | null | undefined;
type Role = 'ref' | 'desc' | 'qty' | 'unit' | 'price' | 'group' | 'spec';
/** The bill convention the wording points to. Reported, never required. */
export type Layout = 'nrm' | 'fidic' | 'masterformat' | 'din276' | 'generic';

/** A quantity as written: plain numbers, "1,250.5", Arabic-Indic digits. Anything else is null.
 *  deComma: a German (DIN 276 / GAEB) export writes "1.250,5" — '.' groups thousands, ',' is the decimal. */
function num(v: Cell, deComma = false): number | null {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  // ponytail: outside a German-headed bill a comma is read as a thousands separator, so "12,5" reads as
  // 125. UAE BOQs write "1,250.50"; add a per-file locale guess if a real file ever arrives the other way.
  let s = String(v ?? '').trim()
    .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x660))
    .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x6F0))
    .replace(/٫/g, '.').replace(/[٬\s]/g, '');
  s = deComma ? s.replace(/\./g, '').replace(',', '.') : s.replace(/,/g, '');
  if (!/^-?\d+(\.\d+)?$/.test(s)) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

const norm = (v: Cell) => String(v ?? '').toLowerCase().replace(/[\s._#:()\-\/]+/g, ' ').trim();
// Header vocabularies. NRM 1/2 and FIDIC bills: Ref / Item (No.), Description, Qty, Unit, Rate, Amount
// (£ / AED), Bill No. CSI MasterFormat: Section / Spec Section, UOM. DIN 276 / GAEB exports: Pos. / OZ,
// Kurztext / Langtext / Beschreibung, Menge, Einheit / ME, EP / GP, Kostengruppe / KG. Arabic throughout.
function roleOf(h: string): Role | null {
  if (!h) return null;
  if (h === 'mengeneinheit') return 'unit';                                // contains "menge", is not a quantity
  if (/(qty|quantity|quantities|menge|الكمية|الكميه|كمية)/.test(h)) return 'qty';
  if (/(rate|price|amount|total|cost|value|preis|betrag|سعر|السعر|المبلغ|الإجمالي|الاجمالي|القيمة)/.test(h) || /^(ep|gp|£|aed|dhs)$/.test(h)) return 'price';
  if (/^(unit|units|uom|u o m|u m|unit of meas\w*|einheit|me|eh|الوحدة|الوحده|وحدة)$/.test(h)) return 'unit';
  // A Spec / Specification / Standard column beside the description carries the line's standard
  // ("BS EN 50525", "IEC 61439"); measured 21 Sep 2026 (customer audit, finding 8) it was not read.
  if (/^(spec|specs|specification|specifications|standard|standards|المواصفات|مواصفات|المواصفة)$/.test(h)) return 'spec';
  // A Make / Brand / Model column (10 Nov 2026): a competitor's quotation names the product it priced ("RAK Ceramics",
  // "Knauf"); that is the specification the next supplier must match, so it travels with the line as one.
  if (/^(make|brand|brands|model|make model|make brand|brand make|manufacturer|origin|country of origin|الماركة|العلامة التجارية|الصنع|المنشأ)$/.test(h)) return 'spec';
  if (/(description|particulars|scope|specification|works?$|kurztext|langtext|beschreibung|الوصف|وصف|البيان)/.test(h)) return 'desc';
  if (/^(bill|bill no|bill ref|section|spec section|section no|csi|csi code|division|kostengruppe|kg|kgr|القسم)$/.test(h)) return 'group';
  if (/^(item|items|item no|item ref|ref no|no|s no|sr no|sl no|sn|ref|code|pos|position|oz|البند|رقم البند|رقم|م)$/.test(h)) return 'ref';
  return null;
}
const CURRENCY = /^(aed|dhs|£|\$|€|eur|usd|sar|qar|درهم)$/;

type Header = { first: number; cols: Partial<Record<Role, number>>; specs: number[]; names: string[]; groupKind: 'bill' | 'kg' | 'code' };

// A header is one row, or two when the row under it holds only header words (a merged "Quantity" over
// "Qty | Unit", or "Rate | Amount" over "AED | AED"). Per column the lower cell wins when it names a role.
function findHeader(rows: Cell[][]): Header | null {
  for (let r = 0; r < Math.min(rows.length, 30); r++) {
    const top = (rows[r] || []).map(norm), next = (rows[r + 1] || []).map(norm);
    const cont = next.some(Boolean) && next.every((h) => !h || roleOf(h) || CURRENCY.test(h));
    const width = cont ? Math.max(top.length, next.length) : top.length;
    const cells = Array.from({ length: width }, (_, i) => (cont && roleOf(next[i] || '') ? next[i] : top[i] || ''));
    const cols: Partial<Record<Role, number>> = {};
    cells.forEach((c, i) => { const k = roleOf(c); if (k && cols[k] === undefined) cols[k] = i; });
    if (cols.qty === undefined || (cols.desc === undefined && cols.ref === undefined)) continue;
    // A sheet headed "Item | Qty | Unit" keeps its descriptions in the Item column.
    if (cols.desc === undefined) { cols.desc = cols.ref; delete cols.ref; }
    const g = cols.group === undefined ? '' : cells[cols.group];
    const names = Array.from({ length: width }, (_, i) => `${top[i] || ''} ${cont ? next[i] || '' : ''}`.trim()).filter(Boolean);
    const specs = cells.map((c, i) => (roleOf(c) === 'spec' ? i : -1)).filter((i) => i >= 0);
    return { first: r + (cont ? 2 : 1), cols, specs, names, groupKind: /^bill/.test(g) ? 'bill' : /^(kostengruppe|kg)/.test(g) ? 'kg' : 'code' };
  }
  return null;
}

// Totals and carry rows in every convention: NRM "Page total" / "To collection" / "Collection", FIDIC
// "Total carried forward" / "Carried to Summary", German "Übertrag" / "Summe", Arabic "المجموع المرحل" /
// "مرحل". "Collection" and "Summary" only when they stand alone, so "Collection and disposal of waste" is
// still an item; "مرحل" only as a whole word, so "المرحلة الثانية" (second phase) is still a heading.
const TOTAL = /^(sub ?total|grand total|total\b|page total|carried (forward|over|to)|brought forward|c\/f|b\/f|übertrag|uebertrag|zwischensumme|summe\b|gesamtsumme|المجموع|الإجمالي|الاجمالي|إجمالي|اجمالي)|^(to )?(collection|summary)\s*$|(^|\s)(ال)?مرحل(\s|$)/i;
// A heading written in the Ref / Section column with the description cell empty.
const HEADING = /^(bill|element|division|section|part|kg|kostengruppe|القسم|الباب)\b|^\d{2} ?\d{2} ?\d{2}\b/i;
// A cell a spreadsheet would treat as a formula if this BOQ were ever exported again (CSV injection).
const cellText = (v: Cell, max: number) => scrubIdentity(String(v ?? '').replace(/\s+/g, ' ').trim()).replace(/^[=+@]+/, '').trim().slice(0, max);

// Wording that points to a convention, counted over header names, headings, totals and group labels.
// The most hits wins; none, or a tie, is 'generic'.
const SIGNS: [Layout, RegExp][] = [
  ['din276', /\b(menge|mengeneinheit|kurztext|langtext|beschreibung|einheit|kostengruppe|einheitspreis|gesamtpreis)\b|^(oz|me|ep|gp|pos|kg)$|\bkg \d{3}\b/],
  ['masterformat', /^division \d{1,2}\b|\b\d{2} \d{2} \d{2}\b|\bspec section\b|^uom$|\bmasterformat\b|\bcsi\b/],
  ['fidic', /\bbill no\b|\bitem no\b|carried to summary|total carried forward|\baed\b|\bdhs\b/],
  ['nrm', /^element\b|\bcollection\b|page total|£|^ref$|\bnrm\b/],
];
function layoutOf(texts: string[]): Layout {
  const score = SIGNS.map(([l, re]) => [l, texts.filter((t) => re.test(norm(t))).length] as const).sort((a, b) => b[1] - a[1]);
  return score[0][1] > 0 && score[0][1] > score[1][1] ? score[0][0] : 'generic';
}

/** Rows of cells (cached values, never formulas) -> the BOQ shape drawing_boq returns. */
export function boqFromRows(rows: Cell[][], where: string, hint = '') {
  const h = findHeader(rows);
  const boq: BoqItem[] = [];
  const assumptions = ['Quantities and units are exactly as written in the customer’s BOQ; nothing was re-measured or recalculated.'];
  const missing: string[] = [];
  const seen: string[] = h ? [...h.names] : [];
  let noQty = 0, truncated = false, section = 'BOQ', lastLine = -1;
  if (!h) missing.push('No header row naming a quantity column and a description or item column was found in the first 30 rows.');
  else {
    if (h.cols.price !== undefined) assumptions.push('Rate, price and amount columns were not read, so no prices are passed to suppliers.');
    const deComma = layoutOf(h.names) === 'din276';
    const at = (row: Cell[], k: Role) => (h.cols[k] === undefined ? '' : row[h.cols[k]!]);
    const groupLabel = (g: string) => (h.groupKind === 'kg' && !/^kg/i.test(g) ? `KG ${g}` : h.groupKind === 'bill' && !/^bill/i.test(g) ? `Bill ${g}` : g);
    for (let i = h.first; i < rows.length; i++) {
      if (boq.length >= MAX_ROWS) { truncated = true; break; }
      const row = rows[i] || [];
      const desc = cellText(at(row, 'desc'), 200);
      const ref = cellText(at(row, 'ref'), 20);
      const grp = cellText(at(row, 'group'), 60);
      const qty = num(at(row, 'qty'), deComma);
      const unit = cellText(at(row, 'unit'), 20).toLowerCase();
      if (TOTAL.test(desc) || TOTAL.test(ref) || TOTAL.test(grp)) { seen.push(desc || ref || grp); continue; }
      if (!desc) {                                                          // blank, a bare number, or a heading in the Ref / Section column
        const head = ref || grp;
        if (head && qty == null && !unit && HEADING.test(head)) { section = head.slice(0, 80); seen.push(head); }
        continue;
      }
      if (qty == null && !unit) {                                           // a section heading
        section = (grp && h.groupKind !== 'code' ? `${groupLabel(grp)} ${desc}` : desc).slice(0, 80);
        seen.push(section); continue;
      }
      if (qty == null) noQty++;
      // A Bill No. / Kostengruppe column names the line's section; a MasterFormat section code is its item ref.
      let sec = section, item = ref;
      if (grp && h.groupKind !== 'code') { const l = groupLabel(grp); seen.push(l); if (!section.startsWith(l)) sec = l; }
      else if (grp && !item) { item = grp; seen.push(grp); }
      const specification = [...new Set(h.specs.map((k) => cellText(row[k], 120)).filter(Boolean))].join('; ').slice(0, 200);
      boq.push({ section: sec, item: item || desc.slice(0, 120), description: desc, qty, unit, basis: `${where}, row ${i + 1}`,
                 confidence: qty != null && unit ? 'medium' : 'low', ...(specification ? { specification } : {}) });
      lastLine = i;
    }
    if (!boq.length) missing.push('A header row was found, but no item lines with a description under it.');
    // A COMPETITOR'S QUOTATION (10 Nov 2026, quotation_parties.ts): the letterhead above the table and the terms and
    // signature below it name the parties; those names leave every line, and the inquiry says what it was rebuilt from.
    const around = [...rows.slice(0, h.first), ...rows.slice(lastLine + 1)].map((r) => (r || []).map((c) => String(c ?? '').trim()).filter(Boolean).join('   ')).filter(Boolean);
    // Only a QUOTATION (priced, and titled as one): a customer's own BOQ keeps its words for create_inquiry's gate.
    if (isQuotation(around.join('\n'), h.cols.price !== undefined)) {
      const terms = quotationPartyTerms(around);
      for (const b of boq) { b.description = scrubTerms(b.description, terms); b.item = scrubTerms(b.item, terms); if (b.specification) b.specification = scrubTerms(b.specification, terms); }
      assumptions.push(QUOTATION_NOTE);
    }
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
    layout: layoutOf(seen),
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
    // The sheet is named by its POSITION, never its name: the leak audit (14 Sep 2026) measured a
    // sheet called "Al Mansoori Villa" reaching suppliers in every row's basis.
    const out = boqFromRows(rows, `sheet ${wb.SheetNames.indexOf(name) + 1}`, hint);
    if (out.boq.length) return { ok: true, boq: out };
    firstOut ??= out;
  }
  return firstOut ? { ok: true, boq: firstOut } : { ok: false, error: 'unreadable_workbook', detail: 'the workbook has no sheets' };
}
