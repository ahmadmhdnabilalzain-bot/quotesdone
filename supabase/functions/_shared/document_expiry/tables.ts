// Tables: a date answers only for its own label (split out of document_expiry.ts, 9 Nov 2026; a pure move).
import { DATE_RE, EXPIRY_KEYWORDS, esc, parseDate, PERIOD_KEYWORDS, START_KEYWORDS } from './dates.ts';

// ── TABLES: A DATE ANSWERS ONLY FOR ITS OWN LABEL ───────────────────────────────────────────────────────────────
// 1 Nov 2026, sales_engineer. Measured on 28 Oct in the independent review of #1708; main read it the same way before
// #1708. A licence or certificate that prints its dates as a header row over a value row draws, in its text layer,
//     Issue Date   Expiry Date
//     15/03/2025   14/03/2028
// and the first date after "Expiry Date" is the ISSUE date. supplier_api (process_docs) and supplier_portal (the
// Documents tab) write leads.license_expiry from this reader without asking the supplier, so a valid licence was
// recorded as expired. A table drawn column by column (the labels stacked, then the dates stacked) read the same way.
// A table is now read the way a person reads one: the date labels of one row, or of a stack of one-label lines, are
// its columns, and the dates right after them (on the same line, else on the lines right under them) are taken in the
// same order, the k-th date for the k-th label. An English label printed beside its Arabic twin is one column. It
// reads only when the counts agree and the expiry is not before an issue or start date of its own row; otherwise
// NOTHING is read, and the model or a person reads the document. Outside a table, a date is still not read for a
// keyword when an issue, start or other date label stands between them (it is that label's date), or when it sits on
// a later line beside another date it is not joined to (a cell of a column whose label is not in this vocabulary).
type Cell = { s: number; e: number; line: number; kind: 'end' | 'start' | 'other' | 'date'; ar: boolean };
// What the date under a label can be: an 'end' label's date may be the expiry; a 'start' label's is never after it;
// an 'other' label's is only counted.
const ISSUE_DATE_LABELS = ['issue date', 'date of issue', 'issued on', 'تاريخ الإصدار'];
const LABEL_KIND = new Map<string, Cell['kind']>([
  ...[...EXPIRY_KEYWORDS, ...PERIOD_KEYWORDS, 'end date'].map((l) => [l, 'end'] as const),
  ...[...START_KEYWORDS, ...ISSUE_DATE_LABELS, 'start date', 'effective date', 'commencement date', 'inception date', 'registration date',
    'date of registration'].map((l) => [l, 'start'] as const),
  ...['renewal date', 'print date', 'date printed', 'printed on'].map((l) => [l, 'other'] as const),
]);
// A label starts a word: 'end date' inside "Amend Date", or 'validity' inside "invalidity", is no label.
const LABEL_G = new RegExp('(?<![A-Za-z])(?:' + [...LABEL_KIND.keys()].sort((a, b) => b.length - a.length).map(esc).join('|') + ')', 'gi');
const DATE_G = new RegExp(DATE_RE.source, 'gi');
type Doc = { t: string; cells: Cell[]; byLine: Map<number, Cell[]>; lines: string[]; starts: number[] };

/** Every date label and every date in the text, in reading order, each with its line. */
function cellsOf(t: string): Doc {
  const cells: Cell[] = [];
  for (const m of t.matchAll(LABEL_G)) {
    const s = m.index ?? 0;
    cells.push({ s, e: s + m[0].length, line: 0, kind: LABEL_KIND.get(m[0].toLowerCase()) ?? 'other', ar: /[؀-ۿ]/.test(m[0]) });
  }
  for (const m of t.matchAll(DATE_G)) { const s = m.index ?? 0; cells.push({ s, e: s + m[0].length, line: 0, kind: 'date', ar: false }); }
  cells.sort((a, b) => a.s - b.s);
  const byLine = new Map<number, Cell[]>();
  let line = 0, p = 0;
  for (const c of cells) {
    for (; p < c.s; p++) if (t.charCodeAt(p) === 10) line++;
    c.line = line;
    let row = byLine.get(line);
    if (!row) byLine.set(line, row = []);
    row.push(c);
  }
  const lines = t.split('\n'), starts: number[] = [];
  for (let n = 0, at = 0; n < lines.length; at += lines[n].length + 1, n++) starts.push(at);
  return { t, cells, byLine, lines, starts };
}

const isLabel = (c: Cell) => c.kind !== 'date';
// A cell that says it holds nothing: "-", "N/A", "n.a.", "Not Applicable", "TBA", "لا يوجد".
const BLANK_CELL_RE = /^[\s\-–—]*$|^\s*(?:n\.?\s*\/?\s*a\.?|nil|none|not applicable|tba|tbc|لا يوجد|غير متوفر|غير متاح)\s*$/i;
type Span = { s: number; e: number };
// A TABLE THAT IS THERE AND DOES NOT READ ENDS THE READING (fifth review of #1733). Returning null there let the reader
// go on to a later keyword, and a table refused for any reason was replaced by whatever expiry the page named next: a
// chamber membership, an insurance policy. 'refused' means: the expiry label heads a column whose date cannot be told,
// so the document's expiry is not read by code at all. null still means "no table here", and the next keyword is tried.
const REFUSED = 'refused' as const;
type TableRead = { expiry: string; raw: string } | null | undefined | typeof REFUSED;
// A cell or line of words before the labels is one more column only when it is worded like a date column's header
// ("Last Inspection"); a title or a company name above a table is not one.
const HIDDEN_HEADER_RE = /\b(?:date|inspection|renewal|renewed|valid|validity|from|to|until|audit|expiry|expires|issued?)\b|تاريخ/i;
// A line split into the cells a text layer draws apart: two or more spaces, a tab or a "|" ends a cell (textFromContent
// joins two cells of one baseline with three spaces). Position in the row, not a count of dates, pairs a value with its
// label: "Issue Date   Expiry Date   Next Inspection" over "-   14/03/2028   01/06/2029" counts two dates for two known
// labels, and pairing them by count read the inspection date as the expiry (review of #1733).
const rowCells = (d: Doc, n: number): Span[] => [...d.lines[n].matchAll(/(?:(?!\s{2}|\t|\|).)+/g)]
  .filter((m) => /\S/.test(m[0])).map((m) => ({ s: d.starts[n] + (m.index ?? 0), e: d.starts[n] + (m.index ?? 0) + m[0].length }));
// The one date a cell holds, or null: a Hijri twin beside it ("14/03/2028 (1449/09/14)") does not read and does not count.
const cellDate = (t: string, c: Span | undefined) => {
  const ds = c ? (t.slice(c.s, c.e).match(DATE_G) ?? []).map(parseDate).filter((x): x is string => !!x) : [];
  return ds.length === 1 ? ds[0] : null;
};
const nextFilled = (d: Doc, n: number) => { while (n < d.lines.length && !/\S/.test(d.lines[n])) n++; return n; };
// A second line of dates under the first: a table of several rows names no one expiry.
const severalRows = (d: Doc, v: number) => { const r = d.byLine.get(nextFilled(d, v + 1)); return !!r && !r.some(isLabel); };

/** A row of labels over the next line of dates: the date in the keyword's own cell. When the cells are not drawn apart
 *  (one space between them), only a line of nothing but labels over a line of nothing but dates reads, by order. */
function headerRowRead(d: Doc, K: Cell, heads: Cell[], cols: Cell[][]): TableRead {
  const { t, lines, byLine, starts } = d;
  const v = nextFilled(d, K.line + 1), vrow = byLine.get(v);
  if (!vrow || vrow.some(isLabel) || K.kind !== 'end') return null;
  if (severalRows(d, v)) return REFUSED;
  const hc = rowCells(d, K.line), vc = rowCells(d, v);
  let expiry: string | null = null, raw = '';
  const starting: (string | null)[] = [];
  if (hc.length > 1 && hc.length === vc.length) {
    const under = (c: Cell) => vc[hc.findIndex((h) => h.s <= c.s && c.s < h.e)];
    // Every cell under a date label holds a date or says it is blank ("-", "N/A"). Text there means the cells are
    // misaligned (a value with two spaces in it split in two, "CN  1145872"), and every date may sit one place off.
    // Only the columns a reading leans on are held to it: the expiry's and the issue or start dates'. A note under a
    // column this reader only counts ("TBA" under Renewal Date) says nothing about the alignment of the others.
    const blankOrDate = (c: Span | undefined) => !!c && (BLANK_CELL_RE.test(t.slice(c.s, c.e)) || cellDate(t, c) !== null);
    if (!heads.every((c) => c.kind === 'other' || blankOrDate(under(c)))) return REFUSED;
    const own = under(K);
    expiry = cellDate(t, own); raw = own ? t.slice(own.s, own.e).trim() : '';
    for (const c of heads) if (c.kind === 'start') starting.push(cellDate(t, under(c)));
  } else {
    const bare = (n: number, spans: Span[]) => {
      let s = lines[n];
      for (const x of [...spans].reverse()) s = s.slice(0, x.s - starts[n]) + s.slice(x.e - starts[n]);
      return /^[\s/|:()\-–—]*$/.test(s);
    };
    if (!bare(K.line, heads) || !bare(v, vrow) || vrow.length !== cols.length) return REFUSED;
    const col = cols.findIndex((g) => g.includes(K));
    expiry = parseDate(t.slice(vrow[col].s, vrow[col].e)); raw = t.slice(vrow[col].s, vrow[col].e);
    cols.forEach((g, j) => { if (g[0].kind === 'start') starting.push(parseDate(t.slice(vrow[j].s, vrow[j].e))); });
  }
  // An expiry before an issue or start date of its own row means the columns were not drawn in the order they are
  // read (right-to-left text drawn in visual order, for one), and the date in hand may be the issue date. A range takes
  // its later date because its own words say it is a period; a table's only evidence is its labels, and they disagree.
  if (!expiry || starting.some((x) => (x ?? '') > (expiry as string))) return REFUSED;
  return { expiry, raw };
}

/** The date under the keyword's own label when the keyword is one of a table's date columns; null when it is and the
 *  table does not read; undefined when the keyword is the only date label of its row and of its column. */
function tableRead(d: Doc, ks: number): TableRead {
  const { t, cells, byLine, lines } = d;
  const k = cells.findIndex((c) => isLabel(c) && c.s <= ks && ks < c.e);
  if (k < 0) return undefined;
  const K = cells[k], row = byLine.get(K.line) ?? [];
  const twins = (p: Cell, c: Cell) => p.kind === c.kind && p.ar !== c.ar;
  let heads: Cell[], mode: 'line' | 'header' | 'stack';
  if (row.some((c) => !isLabel(c))) {
    // labels and dates on one line: the labels beside the keyword with no date between them. A label that closes the
    // field before it ("Issue Date 15/03/2025 تاريخ الإصدار   Expiry Date 14/03/2028") is that field's twin, not a column.
    let a = k, b = k;
    while (a > 0 && cells[a - 1].line === K.line && isLabel(cells[a - 1])) a--;
    while (b + 1 < cells.length && cells[b + 1].line === K.line && isLabel(cells[b + 1])) b++;
    while (a < k && a >= 2 && cells[a - 1].kind === 'date' && cells[a - 1].line === K.line && twins(cells[a - 2], cells[a])) a++;
    heads = cells.slice(a, b + 1); mode = 'line';
  } else if (row.length > 1) { heads = row; mode = 'header'; }
  else {
    // the keyword alone on its line, as every label is in a table drawn column by column: the stack of such lines
    // (blank lines between them do not end it) is the header
    const alone = (n: number) => { const r = byLine.get(n); return r?.length === 1 && isLabel(r[0]); };
    const blank = (n: number) => n >= 0 && n < lines.length && !/\S/.test(lines[n]);
    let a = K.line, b = K.line;
    for (let n = a - 1; alone(n) || blank(n); n--) if (alone(n)) a = n;
    for (let n = b + 1; alone(n) || blank(n); n++) if (alone(n)) b = n;
    heads = cells.filter((c) => c.line >= a && c.line <= b); mode = 'stack';
  }
  // ONE column: an English label printed beside its Arabic twin, on the same line or the next ("Expiry Date / تاريخ
  // الانتهاء"), with nothing but spaces or separators between them; and an expiry label joined by "/" to a label this
  // reader only counts ("Expiry/Renewal Date", "Date of Expiry / Renewal Date").
  const cols: Cell[][] = [];
  for (const c of heads) {
    const g = cols[cols.length - 1], p = g?.[g.length - 1], gap = p ? t.slice(p.e, c.s) : '';
    if (p && ((twins(p, c) && /^[\s/|:()\-–—]*$/.test(gap)) || ([p.kind, c.kind].sort().join() === 'end,other' && [p, c].some((x) => /^renewal date$/i.test(t.slice(x.s, x.e))) && /^\s*\/\s*$/.test(gap)))) g.push(c);
    else cols.push([c]);
  }
  if (cols.length < 2) return undefined;
  const last = heads[heads.length - 1], after = cells.slice(cells.indexOf(last) + 1);
  const datesOnLine = after.length > 0 && after[0].line === last.line && !isLabel(after[0]);
  if (mode === 'header' || (mode === 'line' && !datesOnLine)) return headerRowRead(d, K, heads, cols);
  // A TABLE PRINTED ON ONE LINE (third review of #1733): its dates are taken by order only when the line, from its
  // first label to its end, holds nothing but known labels, dates and separators. "Issue Date   Expiry Date   Next
  // Inspection   -   14/03/2028   01/06/2029" read the inspection date when an unknown label sat among them.
  if (mode === 'line') {
    const le = t.indexOf('\n', heads[0].s), end = le < 0 ? t.length : le;
    let rest = t.slice(heads[0].s, end);
    for (const c of cells.filter((x) => x.s >= heads[0].s && x.e <= end).reverse()) rest = rest.slice(0, c.s - heads[0].s) + ' ' + rest.slice(c.e - heads[0].s);
    if (!/^[\s/|:()\-–—,]*$/.test(rest)) return REFUSED;
    // ...and no unknown column header stands before its first label (fourth review of #1733: "Last Inspection   Issue
    // Date   Expiry Date   01/06/2024   15/03/2025" can be read with the expiry blank, and then 15/03/2025 is the issue
    // date). A cell of words with no digit there is a header; "Licence No 1145872" or "Printed 01/11/2026" is not.
    const before = t.slice(t.lastIndexOf('\n', heads[0].s - 1) + 1, heads[0].s).split(/\s{2,}|\t|\|/).map((x) => x.trim()).filter(Boolean).pop();
    if (before && HIDDEN_HEADER_RE.test(before) && !/\d/.test(before)) return REFUSED;
  }
  if (mode === 'stack') {
    // the same for a stack: a line of words with no digit right above the stacked labels is one more column header
    let n = heads[0].line - 1;
    while (n >= 0 && !/\S/.test(lines[n])) n--;
    if (n >= 0 && !byLine.get(n) && HIDDEN_HEADER_RE.test(lines[n]) && !/\d/.test(lines[n])) return REFUSED;
  }
  // A table on one line, or drawn column by column: the dates right after the last label on its line; when that line
  // ends, every line of dates right under it (blank lines may come first). A label, or a line with no date, ends them.
  const values: Cell[] = [];
  let i = 0;
  while (i < after.length && after[i].line === last.line && !isLabel(after[i])) values.push(after[i++]);
  if (i === after.length || after[i].line !== last.line) {
    let n = last.line + 1;
    if (!values.length) n = nextFilled(d, n);
    for (; n < lines.length; n++) { const r = byLine.get(n); if (!r || r.some(isLabel)) break; values.push(...r); }
  }
  if (K.kind !== 'end') return null;
  if (values.length !== cols.length) return values.length ? REFUSED : null;
  const dateIn = (j: number) => parseDate(t.slice(values[j].s, values[j].e));
  const col = cols.findIndex((g) => g.includes(K)), expiry = dateIn(col);
  if (!expiry || cols.some((g, j) => g[0].kind === 'start' && (dateIn(j) ?? '') > expiry)) return REFUSED;
  return { expiry, raw: t.slice(values[col].s, values[col].e) };
}
export { DATE_G, ISSUE_DATE_LABELS, REFUSED, cellDate, cellsOf, isLabel, rowCells, severalRows, tableRead };
export type { Cell, Doc };
