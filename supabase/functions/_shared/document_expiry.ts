// document_expiry — read an expiry date OFF a document by code, before any model is asked.
//
// Founder instruction 524 (21 Sep 2026): expiry dates were typed by hand in the supplier portal
// Documents tab while license_extract existed to read them — and license_extract runs through
// ai_gateway, which the OpenRouter hold keeps closed. This is the deterministic first attempt:
//   1. pdfText(bytes): the strings a PDF's content streams draw (Tj / TJ operators), inflating
//      FlateDecode streams with the runtime's DecompressionStream. No dependency.
//   2. expiryFromText(text): a date within 90 characters AFTER an expiry keyword, English or
//      Arabic, or the date in an expiry label's own column of a table. A date with no keyword
//      beside it is NOT an expiry — an issue date, a policy start, a print date all look the same —
//      so nothing is returned and the caller says it could not read the document. NEVER a guess: a
//      wrong expiry either suspends a valid supplier or lets a lapsed one keep trading.
//
// CEILING, measured against scripts/staging/fixtures/licence_pdf.mjs (Helvetica, WinAnsi, plain
// content stream): every field reads. A scanned licence (image-only PDF or a photo) has no text
// stream and returns null — there is no OCR here; the browser-side tesseract (src/components/me/
// ocrClient.ts) is a customer-portal tool and was not moved. A PDF whose fonts use a CID/Identity
// encoding draws two-byte glyph ids, not characters; those come out as noise and, because no
// keyword matches noise, the answer is null rather than wrong. That is the honest direction.
// ponytail: text-stream PDFs only; add pdf.js-in-Deno or server OCR when a measured share of real
// uploads is scanned.

export type ExpiryRead = { expiry: string; source: 'text'; keyword: string; raw: string };

const MONTHS: Record<string, number> = {
  jan: 1, january: 1, feb: 2, february: 2, mar: 3, march: 3, apr: 4, april: 4, may: 5, jun: 6, june: 6,
  jul: 7, july: 7, aug: 8, august: 8, sep: 9, sept: 9, september: 9, oct: 10, october: 10, nov: 11, november: 11, dec: 12, december: 12,
};
const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// Keywords first, then the date; only a date after a keyword counts. Two kinds (28 Oct 2026, review of #1708):
//   EXPIRY keywords name the expiry itself, so the date beside one IS the expiry;
//   PERIOD keywords name a period ("Validity", "Period of Insurance", "صلاحية"), whose first date is often its START.
// An expiry keyword wins over a period keyword wherever each one is printed: "Validity: 15/03/2025 ... Expiry Date:
// 14/03/2028" reads 14/03/2028 (until 28 Oct the first keyword of either kind won and read 15/03/2025). Within a
// kind, the first occurrence that has a date beside it wins. Order inside an alternation does not matter.
const EXPIRY_KEYWORDS = [
  'expiry date', 'expiry', 'expires on', 'expires', 'expiration date', 'expiration', 'date of expiry',
  'valid until', 'valid till', 'valid to', 'valid upto', 'valid up to',
  'تاريخ الانتهاء', 'تاريخ انتهاء', 'الانتهاء', 'ينتهي في', 'ينتهي', 'صالحة حتى', 'صالح حتى', 'سارية حتى', 'ساري حتى',
];
const PERIOD_KEYWORDS = ['validity', 'period of insurance', 'صلاحية'];
// A THIRD KIND, TRIED LAST (1 Nov 2026, sales_engineer; the gap was measured on 28 Oct in the review of #1708). START
// keywords name where a period begins: "Valid From: 15/03/2025 To: 14/03/2028" and "valid between 01/01/2026 and
// 31/12/2026" print no keyword of the other two kinds, and both read null. A start keyword is read only through the
// period it opens, to that period's end; the single date beside one is the start, never the expiry. It is tried last,
// so a document that either other kind reads keeps its reading.
const START_KEYWORDS = ['valid from', 'valid between', 'صالحة من', 'صالح من', 'سارية من', 'ساري من'];
const keywordRe = (ks: string[]) => new RegExp('(' + ks.map(esc).join('|') + ')', 'i');
const EXPIRY_RE = keywordRe(EXPIRY_KEYWORDS);
const PERIOD_RE = keywordRe(PERIOD_KEYWORDS);
const START_RE = keywordRe(START_KEYWORDS);
// A keyword that names an EARLIER document's date is not this document's: a renewal schedule can print "Previous
// Policy Expiry: 31/12/2025" under its own "Period of Insurance: 01/01/2026 to 31/12/2026". The qualifier is looked
// for on the keyword's own line before it, or between the keyword and its date ("Expiry date of previous policy",
// "تاريخ انتهاء الوثيقة السابقة").
const EARLIER_RE = /\b(?:previous|prior|preceding)\b|السابق/i;

// The date shapes a UAE licence or certificate prints: 13/03/2027, 13-03-2027, 2027-03-13,
// 13 Mar 2027, 13-MAR-2027, 13 March 2027, March 13, 2027. Two-digit years are not accepted.
// 1 Nov 2026 (sales_engineer; measured 28 Oct): an ORDINAL day too, 1st January 2026, 31st of December 2026, January
// 1st, 2026. An insurance schedule's "From 1st January 2026 to 31st December 2026" read null. And a month is a month's
// own name: any three to nine letters used to count as one, so "17 Ramadan 1449" was a date that parsed to null, and
// the Gregorian expiry printed after it was never reached.
const MONTH_NAME = '(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';
const ORDINAL = '(?:st|nd|rd|th)?';
const DATE_RE = new RegExp('(\\d{4})[-/.](\\d{1,2})[-/.](\\d{1,2})|(\\d{1,2})[-/.](\\d{1,2})[-/.](\\d{4})'
  + '|(\\d{1,2})' + ORDINAL + '(?:[ \\-]of)?[ \\-]' + MONTH_NAME + '[ \\-,]+(\\d{4})'
  + '|\\b' + MONTH_NAME + '[ \\-]+(\\d{1,2})' + ORDINAL + ',?[ \\-]+(\\d{4})', 'i');

// The second date of a period, right after the first: "<date> to <date>", "<date> - <date>", "<date> إلى <date>".
// Between them a schedule may print a time on the first date ("00:00 hrs", "12:00 AM") and a colon after the
// connector ("From: 01/01/2026 To: 31/12/2026", also split over two lines); Arabic joins "و" to the connector
// ("وحتى", "ولغاية") and spells إلى four ways. A hyphen INSIDE one date is never a connector: the first date is
// matched whole before this runs, so "14-03-2028" or "14-Mar-2028" never leaves a "-<date>" behind it.
const TIME_OF_DAY = '(?:\\s*\\d{1,2}[:.]\\d{2}(?:[:.]\\d{2})?\\s*(?:hrs?|hours|[ap]\\.?\\s?m)?\\.?)?';
const RANGE_JOIN = '(?:to|till|until|up\\s*to|upto|through|thru|-|–|—|(?:و\\s*)?(?:إلى|الى|إلي|الي|حتى|لغاية))';
const rangeEnd = (join: string) => new RegExp('^' + TIME_OF_DAY + '\\s*' + join + '\\s*:?\\s*(' + DATE_RE.source + ')', 'i');
const RANGE_END_RE = rangeEnd(RANGE_JOIN);
// "BETWEEN <date> AND <date>" (1 Nov 2026, sales_engineer; measured 28 Oct). "Period of Insurance: between 01/01/2026
// and 31/12/2026" read its START, 01/01/2026, as the expiry: "and" joined nothing, so the first date stood alone.
// "and" (و after بين) joins two dates only where "between" opens them; anywhere else it would join an expiry to
// whatever date follows it. A "between" with one date is a period with no readable end, and reads nothing.
const BETWEEN_LEAD_RE = /(?:\bbetween|بين)\s*:?\s*$/i;
const BETWEEN_END_RE = rangeEnd('(?:' + RANGE_JOIN + '|and|&|و)');

function ymd(y: number, m: number, d: number): string | null {
  if (!(y >= 2000 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31)) return null;
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) return null;   // 31/02 is not a date
  return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

/** Normalise one printed date to YYYY-MM-DD, or null when it is not one. Day-first for numeric forms (UAE). */
export function parseDate(raw: string): string | null {
  const m = DATE_RE.exec(raw);
  if (!m) return null;
  if (m[1]) return ymd(+m[1], +m[2], +m[3]);
  if (m[4]) return ymd(+m[6], +m[5], +m[4]);
  if (m[7]) { const mo = MONTHS[m[8].toLowerCase()]; return mo ? ymd(+m[9], mo, +m[7]) : null; }
  if (m[10]) { const mo = MONTHS[m[10].toLowerCase()]; return mo ? ymd(+m[12], mo, +m[11]) : null; }
  return null;
}

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
type Span = { s: number; e: number };
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
function headerRowRead(d: Doc, K: Cell, heads: Cell[], cols: Cell[][]): { expiry: string; raw: string } | null {
  const { t, lines, byLine, starts } = d;
  const v = nextFilled(d, K.line + 1), vrow = byLine.get(v);
  if (!vrow || vrow.some(isLabel) || severalRows(d, v) || K.kind !== 'end') return null;
  const hc = rowCells(d, K.line), vc = rowCells(d, v);
  let expiry: string | null = null, raw = '';
  const starting: (string | null)[] = [];
  if (hc.length > 1 && hc.length === vc.length) {
    const under = (c: Cell) => vc[hc.findIndex((h) => h.s <= c.s && c.s < h.e)];
    const own = under(K);
    expiry = cellDate(t, own); raw = own ? t.slice(own.s, own.e).trim() : '';
    for (const c of heads) if (c.kind === 'start') starting.push(cellDate(t, under(c)));
  } else {
    const bare = (n: number, spans: Span[]) => {
      let s = lines[n];
      for (const x of [...spans].reverse()) s = s.slice(0, x.s - starts[n]) + s.slice(x.e - starts[n]);
      return /^[\s/|:()\-–—]*$/.test(s);
    };
    if (!bare(K.line, heads) || !bare(v, vrow) || vrow.length !== cols.length) return null;
    const col = cols.findIndex((g) => g.includes(K));
    expiry = parseDate(t.slice(vrow[col].s, vrow[col].e)); raw = t.slice(vrow[col].s, vrow[col].e);
    cols.forEach((g, j) => { if (g[0].kind === 'start') starting.push(parseDate(t.slice(vrow[j].s, vrow[j].e))); });
  }
  // An expiry before an issue or start date of its own row means the columns were not drawn in the order they are
  // read (right-to-left text drawn in visual order, for one), and the date in hand may be the issue date. A range takes
  // its later date because its own words say it is a period; a table's only evidence is its labels, and they disagree.
  if (!expiry || starting.some((x) => (x ?? '') > (expiry as string))) return null;
  return { expiry, raw };
}

/** The date under the keyword's own label when the keyword is one of a table's date columns; null when it is and the
 *  table does not read; undefined when the keyword is the only date label of its row and of its column. */
function tableRead(d: Doc, ks: number): { expiry: string; raw: string } | null | undefined {
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
    if (p && ((twins(p, c) && /^[\s/|:()\-–—]*$/.test(gap)) || ([p.kind, c.kind].sort().join() === 'end,other' && /^\s*\/\s*$/.test(gap)))) g.push(c);
    else cols.push([c]);
  }
  if (cols.length < 2) return undefined;
  const last = heads[heads.length - 1], after = cells.slice(cells.indexOf(last) + 1);
  const datesOnLine = after.length > 0 && after[0].line === last.line && !isLabel(after[0]);
  if (mode === 'header' || (mode === 'line' && !datesOnLine)) return headerRowRead(d, K, heads, cols);
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
  if (values.length !== cols.length || K.kind !== 'end') return null;
  const dateIn = (j: number) => parseDate(t.slice(values[j].s, values[j].e));
  const col = cols.findIndex((g) => g.includes(K)), expiry = dateIn(col);
  if (!expiry || cols.some((g, j) => g[0].kind === 'start' && (dateIn(j) ?? '') > expiry)) return null;
  return { expiry, raw: t.slice(values[col].s, values[col].e) };
}

// "Issue/Expiry Date: 15/03/2025 / 14/03/2028" names two dates with one label: the expiry is the later of the two, and
// with one date there is nothing to read (main read the issue date there).
const ISSUE_JOINED_RE = /\b(?:issue|issued|issuance)\s*(?:\/|&|and)\s*$/i;

/** The first occurrence of one kind of keyword that reads a date: in its own column of a table, or within 90
 *  characters after it. A start keyword reads only the end of the period it opens. */
function readAfter(d: Doc, keywords: RegExp, kind: 'expiry' | 'period' | 'start'): ExpiryRead | null {
  const { t, cells, byLine } = d;
  let from = 0;
  for (let i = 0; i < 20; i++) {
    const km = keywords.exec(t.slice(from));
    if (!km) return null;
    const ks = from + (km.index ?? 0), at = ks + km[0].length;
    const lineBefore = t.slice(Math.max(0, ks - 40), ks).split('\n').pop() ?? '';
    const table = EARLIER_RE.test(lineBefore) ? null : tableRead(d, ks);
    if (table && kind !== 'start') return { expiry: table.expiry, source: 'text', keyword: km[0], raw: table.raw };
    const window = t.slice(at, at + 90);
    const dm = table === undefined ? DATE_RE.exec(window) : null;
    const lead = dm ? window.slice(0, dm.index) : '';
    if (dm && !EARLIER_RE.test(lead)) {
      // A PERIOD ENDS ON ITS LATER DATE (28 Oct 2026, sales_engineer; document walk on production). An insurance
      // schedule prints "Period of Insurance: From 01/01/2026 To 31/12/2026", and a licence or certificate can print
      // "Validity: 15/03/2025 - 14/03/2028". The first date after the keyword is the START, and it was returned as the
      // expiry: the Documents tab offered "expires 1 Jan 2026 — is that right?" for a policy valid to 31 Dec 2026, and
      // a licence would have had its issue date written as its expiry. When the first date is joined to a second
      // (RANGE_END_RE), the period's end is the expiry, and the end is the LATER of the two: a pair printed backwards
      // ("Expiry Date - Issue Date: 14/03/2028 - 15/03/2025", or right-to-left text drawn in visual order) still reads
      // 14/03/2028. (The first fix took the second date whatever it was, and read 15/03/2025 there.) Where the words
      // themselves say which date opens the period ("Valid From", "between"), an end before its start reads nothing.
      const ds = at + dm.index;
      const between = BETWEEN_LEAD_RE.test(km[0] + lead);
      const first = parseDate(dm[0]);
      const rest = window.slice(dm.index + dm[0].length);
      const tail = (between ? BETWEEN_END_RE : RANGE_END_RE).exec(rest);
      // Not this keyword's date: one that an issue, start or other date label stands in front of ("Expiry Date: see the
      // schedule / Issue Date: 15/03/2025"), unless that label is joined to the keyword by "/" ("Expiry/Renewal Date");
      // or one on a later line beside another date it is not joined to, which is a cell of a column whose label is not
      // in this vocabulary ("Membership Date   Expiry Date" over two dates) and is read only by its position under the
      // keyword. Only dates that read count there: a Hijri twin beside the Gregorian expiry is not a column.
      let joinedTo = at;
      for (const c of cells) if (c.s >= joinedTo && isLabel(c) && c.kind !== 'start' && /^\s*\/\s*$/.test(t.slice(joinedTo, c.s))) joinedTo = c.e;
      const owned = cells.some((c) => (c.kind === 'start' || c.kind === 'other') && c.s >= joinedTo && c.e <= ds);
      const le = t.indexOf('\n', ds), rowText = t.slice(t.lastIndexOf('\n', ds) + 1, le < 0 ? t.length : le);
      const crowded = lead.includes('\n') && !tail && (rowText.match(DATE_G) ?? []).filter((x) => parseDate(x)).length > 1;
      if (!owned && crowded && kind !== 'start') {
        const K = cells.find((c) => isLabel(c) && c.s <= ks && ks < c.e), v = cells.find((c) => c.s === ds)?.line;
        if (K && v !== undefined && !severalRows(d, v)) {
          const hc = rowCells(d, K.line), vc = rowCells(d, v), under = (c: Cell) => vc[hc.findIndex((h) => h.s <= c.s && c.s < h.e)];
          const e = hc.length > 1 && hc.length === vc.length ? cellDate(t, under(K)) : null;
          const starting = (byLine.get(K.line) ?? []).filter((c) => c.kind === 'start').map((c) => cellDate(t, under(c)));
          if (e && !starting.some((x) => (x ?? '') > e)) return { expiry: e, source: 'text', keyword: km[0], raw: e };
        }
      }
      const issueJoined = ISSUE_JOINED_RE.test(t.slice(t.lastIndexOf('\n', ks - 1) + 1, ks));
      if (!owned && !crowded) {
        if (tail) {
          const second = parseDate(tail[1]);
          if (first && second && !((kind === 'start' || between) && second < first)) {
            return { expiry: second > first ? second : first, source: 'text', keyword: km[0], raw: dm[0] + tail[0] };
          }
          // One end does not read as a day-first date (a month-first schedule, "01/12/2026 to 12/31/2026"): the
          // period has no readable end, and its start is certainly not the expiry. Nothing is read beside this keyword.
        } else if (issueJoined) {
          const sm = DATE_RE.exec(rest), second = sm ? parseDate(sm[0]) : null;
          if (first && second) return { expiry: second > first ? second : first, source: 'text', keyword: km[0], raw: dm[0] + rest.slice(0, (sm?.index ?? 0) + (sm?.[0].length ?? 0)) };
        } else if (first && kind !== 'start' && !between) return { expiry: first, source: 'text', keyword: km[0], raw: dm[0] };
      }
    }
    from = at;   // this keyword read nothing ("valid until the expiry date shown above") — try the next
  }
  return null;
}

/** The expiry a document states, or null. A date counts only in the keyword's own column of a table or within 90
 *  characters after the keyword; an expiry keyword wins over a period keyword, and both over a start keyword. */
export function expiryFromText(text: string): ExpiryRead | null {
  const t = String(text || '').replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x0660)); // Arabic-Indic digits
  const d = cellsOf(t);
  return readAfter(d, EXPIRY_RE, 'expiry') ?? readAfter(d, PERIOD_RE, 'period') ?? readAfter(d, START_RE, 'start');
}

// ── PDF text ─────────────────────────────────────────────────────────────────────────────────────
const latin1 = (b: Uint8Array) => { let s = ''; for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode(...b.subarray(i, i + 0x8000)); return s; };

async function inflate(bytes: Uint8Array): Promise<Uint8Array | null> {
  for (const fmt of ['deflate', 'deflate-raw'] as const) {
    try {
      const ds = new DecompressionStream(fmt);
      const out = new Response(new Blob([bytes as BlobPart]).stream().pipeThrough(ds));
      return new Uint8Array(await out.arrayBuffer());
    } catch { /* try the other framing */ }
  }
  return null;
}

function unescapePdf(s: string): string {
  return s.replace(/\\([nrtbf()\\]|[0-7]{1,3})/g, (_, c: string) => {
    if (/^[0-7]+$/.test(c)) return String.fromCharCode(parseInt(c, 8));
    return ({ n: '\n', r: '\r', t: '\t', b: '\b', f: '\f' } as Record<string, string>)[c] ?? c;
  });
}

/** Strings drawn by one content stream, in drawing order; a text-position operator becomes a newline. */
export function textFromContent(content: string): string {
  const out: string[] = [];
  // (...) Tj  |  [ (...) -250 (...) ] TJ  |  <hex> Tj  |  T* / Td / TD / ET → newline
  const re = /\(((?:\\.|[^\\)])*)\)\s*Tj|\[((?:[^\]\\]|\\.)*)\]\s*TJ|<([0-9A-Fa-f\s]+)>\s*Tj|(?:-?[\d.]+\s+){5}(-?[\d.]+)\s+Tm\b|-?[\d.]+\s+(-?[\d.]+)\s+T[dD]\b|(T\*|ET\b)/g;
  // 28 Sep 2026 (sales_engineer): a PDF that places every line with its own `Tm` (the registration walk's
  // licence fixture, and many generators) also read as ONE line, so the line-anchored name label never
  // matched and every such licence was held as licence_name_unread. `Tm` now breaks the line too.
  // 7 Oct 2026 (sales_engineer, accuracy suite, ledger 1162): ...but only when it moves to ANOTHER line. A licence
  // laid out as a two-column table places each label and its value with their own Tm (or their own BT..ET) on
  // the SAME baseline; breaking there put "Legal Name" and its value on different lines, and every table-layout
  // licence of scripts/e2e/document_intake_corpus.mjs (DET, ADGM, SEDD, RAKEZ, JAFZA, DAFZA, IFZA, SHAMS) was
  // held as licence_unreadable with its name printed in plain text. A placement that keeps the baseline
  // (|dy| < 2pt) is now a space, and ET ends the line only if the next placement leaves it.
  // 24 Sep 2026: `T*` then a trailing \b never matched (no word boundary after '*'), so a licence laid out
  // with T* read as ONE line and "Legal Name : X" swallowed the rest of the page. Measured by the
  // readLicenceName test below the fix.
  let m: RegExpExecArray | null;
  let y: number | null = null;   // the baseline being written, from Tm (absolute) and Td (relative)
  let ended = false;             // an ET: the line ends unless the next placement keeps the baseline
  const brk = () => { out.push('\n'); ended = false; };
  const push = (s: string) => { if (ended) brk(); out.push(s); };
  while ((m = re.exec(content))) {
    if (m[4] !== undefined) {                                   // Tm
      const ny = Number(m[4]);
      if (y !== null && Math.abs(ny - y) < 2) { ended = false; out.push(' '); } else brk();
      y = ny; continue;
    }
    if (m[5] !== undefined) {                                   // Td / TD
      const dy = Number(m[5]);
      if (Math.abs(dy) < 2) { ended = false; out.push(' '); } else brk();
      if (y !== null) y += dy; continue;
    }
    if (m[6] === 'ET') { ended = true; continue; }
    if (m[6] !== undefined) { brk(); continue; }                // T*
    if (m[1] !== undefined) push(unescapePdf(m[1]));
    else if (m[2] !== undefined) {
      const parts: string[] = [];
      const inner = /\(((?:\\.|[^\\)])*)\)|<([0-9A-Fa-f\s]+)>|(-?\d+(?:\.\d+)?)/g;
      let p: RegExpExecArray | null;
      while ((p = inner.exec(m[2]))) {
        if (p[1] !== undefined) parts.push(unescapePdf(p[1]));
        else if (p[2] !== undefined) parts.push(hexString(p[2]));
        else if (Number(p[3]) < -200) parts.push(' ');   // a large negative kern is a word gap
      }
      push(parts.join(''));
    }
    else if (m[3] !== undefined) push(hexString(m[3]));
  }
  return out.join(' ').replace(/[ \t]+\n/g, '\n').replace(/\n[ \t]+/g, '\n');
}
const hexString = (h: string) => { const clean = h.replace(/\s+/g, ''); let s = ''; for (let i = 0; i + 1 < clean.length; i += 2) s += String.fromCharCode(parseInt(clean.slice(i, i + 2), 16)); return s; };

/** All text the PDF's content streams draw, or null when the bytes are not a PDF / draw no text. */
// ONE READ OF A PDF PER UPLOAD, AND A NATIVE DECODE (28 Oct 2026, sales_engineer; production size measurement).
// A scanner-style licence of 14.50 MB and one of 19.33 MB ended supplier_portal save_documents and supplier_api
// process_docs at the edge's CPU cap (HTTP 546); 9.66 MB passed. Measured locally on the 19.33 MB file: the whole-file
// latin1() above (String.fromCharCode over 32 KB slices) took 810 ms of the 1,044 ms pdfText spent, and each upload ran
// pdfText three times (readExpiry, readLicenceName, readLicenceFields on the same bytes). The whole-file view is now
// decoded natively (TextDecoder 'latin1', which the WHATWG Encoding standard maps to windows-1252: one character per
// byte, so every offset still indexes `bytes`, and only ASCII - the dictionaries and `stream`/`endstream` - is read
// from it); a content stream's own text still goes through latin1(), unchanged. And the text is kept per bytes object,
// so the three readers share one pass.
const TEXT_OF = new WeakMap<Uint8Array, Promise<string | null>>();
export function pdfText(bytes: Uint8Array): Promise<string | null> {
  let p = TEXT_OF.get(bytes);
  if (!p) { p = readPdfText(bytes); TEXT_OF.set(bytes, p); }
  return p;
}
async function readPdfText(bytes: Uint8Array): Promise<string | null> {
  const raw = new TextDecoder('latin1').decode(bytes);
  if (!raw.startsWith('%PDF')) return null;
  const chunks: string[] = [];
  const re = /(<<[\s\S]*?>>)\s*stream\r?\n/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(raw))) {
    const start = m.index + m[0].length;
    const end = raw.indexOf('endstream', start);
    if (end < 0) break;
    const dict = m[1];
    // The EOL before `endstream` is not stream data; DecompressionStream refuses bytes after the
    // deflate trailer ("junk after end"), so it is trimmed before inflating.
    let bodyEnd = end;
    while (bodyEnd > start && (bytes[bodyEnd - 1] === 0x0a || bytes[bodyEnd - 1] === 0x0d)) bodyEnd--;
    let body = bytes.subarray(start, bodyEnd);
    // AN IMAGE IS NEVER INFLATED TO LOOK FOR TEXT (28 Oct 2026, sales_engineer; supplier-journey audit, run fceb5876).
    // A 686 kB scan saved from a browser (one 2483x3265 RGB image and its soft mask, both FlateDecode) ended
    // supplier_portal save_documents at the edge's CPU cap (HTTP 546, "CPU Time exceeded", 08:40:31Z), and the platform's
    // own error sentence reached the supplier. Each read inflated 32 MB of pixels and copied them into a string to look
    // for text operators an image cannot hold: 4.3 s for the three readers of one upload, measured locally. An image
    // XObject (and its /SMask, also an image) is skipped before it is inflated; the page's content streams are read as before.
    // Only the stream's OWN dictionary is asked, here and by the two filter tests below (review of #1726, 28 Oct 2026). The match above starts at the first `<<`
    // after the previous stream, so `dict` can begin in an earlier object; a text stream that followed any object naming
    // `/Subtype /Image` (or an image whose `stream` keyword ends in a lone CR, so its match ran on into the next stream)
    // was skipped and its licence text lost. What follows the span's last `N G obj` header is this stream's dictionary.
    const heads = [...dict.matchAll(/\d+\s+\d+\s+obj\b/g)];
    const own = heads.length ? dict.slice(heads[heads.length - 1].index) : dict;
    if (/\/Subtype\s*\/Image\b/.test(own)) { re.lastIndex = end; continue; }
    if (/\/FlateDecode/.test(own)) { const inf = await inflate(body); if (!inf) { re.lastIndex = end; continue; } body = inf; }
    else if (/\/Filter/.test(own)) { re.lastIndex = end; continue; }   // LZW / DCT (an image) — not text
    const content = latin1(body);
    if (/\bTj\b|\bTJ\b/.test(content)) chunks.push(textFromContent(content));
    re.lastIndex = end;
  }
  const text = chunks.join('\n').trim();
  return text ? text : null;
}

// THE NAME A LICENCE PRINTS (24 Sep 2026, sales_engineer). The review compares it with the registered
// company name (fn_supplier_licence_name_mismatch). Read the same way as the expiry: a value on the SAME
// line as a name label, nothing inferred. Legal name is preferred over trade name, which a UAE licence
// may print without the legal form. No label = null ("not read"), never a guess.
// 7 Oct 2026 (accuracy suite): an Ajman sole establishment prints "Establishment Name"; with no label for it the
// reader fell through to "Trade Name" and recorded the trade name as the licence's name.
const LEGAL_NAME_LABELS = ['legal name', 'company name', 'name of company', 'name of the company', 'establishment name', 'name of establishment',
  'الاسم القانوني', 'اسم الشركة', 'اسم المؤسسة'];
const TRADE_NAME_LABELS = ['trade name', 'trading name', 'الاسم التجاري'];
export const NAME_LABELS = [...LEGAL_NAME_LABELS, ...TRADE_NAME_LABELS];
export function licenceNameFromText(text: string): string | null {
  for (const label of NAME_LABELS) {
    const re = new RegExp('^[ \\t]*' + label + '[ \\t]*[:：\\-]?[ \\t]*(.+)$', 'im');
    const v = re.exec(String(text || ''))?.[1]?.trim().slice(0, 200);
    if (v && /\p{L}{2}/u.test(v)) return v;
  }
  return null;
}
/** The licence's printed company name from a text-layer PDF, or null. Images return null (no OCR). */
export async function readLicenceName(bytes: Uint8Array, mime: string): Promise<string | null> {
  if (!/pdf/i.test(mime)) return null;
  const text = await pdfText(bytes);
  return text ? licenceNameFromText(text) : null;
}

// EVERY FIELD A LICENCE PRINTS, READ BY CODE (7 Oct 2026, sales_engineer; founder gate ledger 1162: "not a single
// mistake in any trade licence"). Measured before this on the 50-licence synthetic corpus of
// scripts/e2e/document_intake_accuracy.mjs: code read the name and the expiry only, so the licence number, the
// issuing authority, the legal form, the issue date, the emirate and the activities of a text licence were read by
// nothing at all (process_docs's model switch is off), and trades were proposed from the company's NAME line
// ("Horizon Floor LLC" -> floor cleaners) instead of its licensed activities. Same rule as the name: a value is
// taken only from the same line as its label; no label, no value. Labels are each authority's own vocabulary.
export type LicenceFields = {
  licence_no: string | null; legal_name_en: string | null; trade_name: string | null; legal_form: string | null;
  authority: string | null; emirate: string | null; issue_date: string | null; expiry_date: string | null; activities: string[] | null;
  legal_name_ar: string | null;
};
const LABELS: Record<'licence_no' | 'legal_form' | 'authority' | 'emirate' | 'issue_date' | 'activities', string[]> = {
  licence_no: ['trade licence number', 'trade license number', 'trade licence no', 'trade license no', 'commercial licence no', 'commercial license no',
    'licence number', 'license number', 'licence no', 'license no', 'registered number', 'registration number', 'registration no', 'رقم الرخصة'],
  legal_form: ['legal form', 'legal type', 'legal status', 'company type', 'الشكل القانوني'],
  authority: ['issuing authority', 'licensing authority', 'issued by', 'جهة الإصدار'],
  emirate: ['emirate', 'الإمارة'],
  issue_date: ISSUE_DATE_LABELS,
  activities: ['business activities', 'licensed activities', 'activities', 'activity', 'الأنشطة', 'النشاط'],
};
/** The value on the same line as the first label that has one. A label is a whole word: "Licence No" never reads "Licence Number". */
function labelled(text: string, labels: string[]): string | null {
  for (const label of labels) {
    const re = new RegExp('^[ \\t]*' + esc(label) + '(?![\\p{L}])\\.?[ \\t]*[:：\\-]?[ \\t]*(.+)$', 'imu');
    const v = re.exec(text)?.[1]?.trim().slice(0, 300);
    if (v && /[\p{L}\p{N}]/u.test(v)) return v;
  }
  return null;
}
const EMIRATES = ['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'];
const EMIRATE_AR: Record<string, string> = { 'دبي': 'Dubai', 'أبوظبي': 'Abu Dhabi', 'ابوظبي': 'Abu Dhabi', 'الشارقة': 'Sharjah', 'عجمان': 'Ajman', 'أم القيوين': 'Umm Al Quwain', 'رأس الخيمة': 'Ras Al Khaimah', 'الفجيرة': 'Fujairah' };
export function emirateOf(s: string | null | undefined): string | null {
  const t = String(s ?? '');
  for (const e of EMIRATES) if (new RegExp('\\b' + e + '\\b', 'i').test(t)) return e;
  for (const [ar, e] of Object.entries(EMIRATE_AR)) if (t.includes(ar)) return e;
  return null;
}
// Where a licence prints no emirate (most free zones), the issuing authority decides it: each of these is in one emirate.
const AUTHORITY_EMIRATE: [RegExp, string][] = [
  [/abu dhabi global market|\badgm\b/i, 'Abu Dhabi'], [/ras al khaimah|\brakez\b/i, 'Ras Al Khaimah'], [/sharjah|\bshams\b|\bsaif\b|hamriyah/i, 'Sharjah'],
  [/jebel ali|\bjafza\b|multi commodities|\bdmcc\b|airport free ?zone|\bdafza\b|silicon oasis|\bdso\b|international free zone|\bifza\b|meydan|international financial centre|\bdifc\b|economy and tourism|dubai/i, 'Dubai'],
  [/abu dhabi/i, 'Abu Dhabi'], [/ajman/i, 'Ajman'], [/umm al quwain/i, 'Umm Al Quwain'], [/fujairah/i, 'Fujairah'],
];
export function emirateOfAuthority(a: string | null | undefined): string | null {
  for (const [re, e] of AUTHORITY_EMIRATE) if (re.test(String(a ?? ''))) return e;
  return null;
}
export function licenceFieldsFromText(text: string): LicenceFields {
  const t = String(text || '');
  const noRaw = labelled(t, LABELS.licence_no);
  const licence_no = noRaw ? (/[A-Z0-9][A-Z0-9\-/.]*\d[A-Z0-9\-/.]*/i.exec(noRaw)?.[0].replace(/[.\-/]+$/, '') ?? null) : null;
  const legal = labelled(t, LEGAL_NAME_LABELS);
  const authority = labelled(t, LABELS.authority);
  const emirateRaw = labelled(t, LABELS.emirate);
  const issueRaw = labelled(t, LABELS.issue_date);
  const acts = labelled(t, LABELS.activities);
  const name = legal && /\p{L}{2}/u.test(legal) ? legal : null;
  return {
    licence_no, legal_name_en: name && !/[؀-ۿ]/.test(name) ? name : null,
    legal_name_ar: name && /[؀-ۿ]/.test(name) ? name : null,
    trade_name: labelled(t, TRADE_NAME_LABELS), legal_form: labelled(t, LABELS.legal_form), authority,
    emirate: emirateOf(emirateRaw) ?? emirateOfAuthority(authority),
    issue_date: issueRaw ? parseDate(issueRaw) : null, expiry_date: expiryFromText(t)?.expiry ?? null,
    activities: acts ? acts.split(/[,،;؛]/).map((a) => a.trim()).filter((a) => a.length >= 3) : null,
  };
}
const NO_FIELDS: LicenceFields = { licence_no: null, legal_name_en: null, legal_name_ar: null, trade_name: null, legal_form: null, authority: null, emirate: null, issue_date: null, expiry_date: null, activities: null };
/** A licence file's fields by code; an image or a PDF with no text layer reads as all null ("not read"). */
export async function readLicenceFields(bytes: Uint8Array, mime: string): Promise<LicenceFields> {
  if (!/pdf/i.test(mime)) return { ...NO_FIELDS };
  const text = await pdfText(bytes);
  return text ? licenceFieldsFromText(text) : { ...NO_FIELDS };
}
/** The model is asked whenever code left one of the three fields the gate stands on unread. */
export const licenceNeedsModel = (c: Partial<LicenceFields> | null | undefined) => !c?.legal_name_en || !c?.licence_no || !c?.expiry_date;

/**
 * CODE FIRST, THE MODEL ONLY WHERE CODE COULD NOT READ (founder: "code first, LLM only where code can't"). One rule,
 * used by supplier_api.process_docs and by the accuracy suite, so what is measured is what runs. A field code read
 * is never overwritten by the model. The model's name counts only when it is confident (licenceNameFromModel).
 * `source` says, per field, who read it.
 */
// deno-lint-ignore no-explicit-any
export function mergeLicenceReads(code: Partial<LicenceFields> | null | undefined, model: any): { merged: LicenceFields; source: Record<string, 'code' | 'model'> } {
  const c = { ...NO_FIELDS, ...(code || {}) };
  const m = model || {};
  const conf = m.confidence !== 'low';
  const fromModel: Partial<LicenceFields> = {
    licence_no: String(m.license_number ?? '').trim() || null,
    legal_name_en: conf ? (licenceNameFromModel(m) && !/[؀-ۿ]/.test(String(m.legal_name)) ? licenceNameFromModel(m) : null) : null,
    legal_name_ar: conf ? (String(m.legal_name_ar ?? '').trim() || null) : null,
    trade_name: String(m.trade_name ?? '').trim() || null, legal_form: String(m.legal_form ?? '').trim() || null,
    authority: String(m.license_authority ?? '').trim() || null, emirate: emirateOf(m.emirate) ?? emirateOfAuthority(m.license_authority),
    issue_date: m.issue_date || null, expiry_date: m.expiry_date || null,
    activities: Array.isArray(m.activities) && m.activities.length ? m.activities.map((a: unknown) => String(a).trim()).filter(Boolean) : null,
  };
  const merged = { ...NO_FIELDS }; const source: Record<string, 'code' | 'model'> = {};
  for (const k of Object.keys(NO_FIELDS) as (keyof LicenceFields)[]) {
    const cv = c[k], mv = fromModel[k];
    const has = (v: unknown) => v != null && v !== '' && !(Array.isArray(v) && !v.length);
    // deno-lint-ignore no-explicit-any
    if (has(cv)) { (merged as any)[k] = cv; source[k] = 'code'; } else if (has(mv)) { (merged as any)[k] = mv; source[k] = 'model'; }
  }
  return { merged, source };
}

// A SCANNED LICENCE STILL YIELDS ITS NAME (24 Sep 2026, sales_engineer). Code reads only a text layer, so a
// scan or a photo reaches the name through license_extract (vision, model_policy.document_extraction). These
// two are the whole rule, shared by every upload path (supplier_api, resend_inbound, wa_inbound):
/** The name the model read, or null. A 'low' confidence read (an unreadable scan, or a truncated reply) is not a name. */
export function licenceNameFromModel(doc: { legal_name?: unknown; confidence?: unknown } | null | undefined): string | null {
  if (!doc || doc.confidence === 'low') return null;
  const v = String(doc.legal_name ?? '').trim().slice(0, 200);
  return /\p{L}{2}/u.test(v) ? v : null;
}
export function toB64(u8: Uint8Array): string {
  let bin = ''; for (let i = 0; i < u8.length; i += 0x8000) bin += String.fromCharCode(...u8.subarray(i, i + 0x8000));
  return btoa(bin);
}
/** What license_extract is sent: the images or file the request carried; otherwise, when code could not read a
 *  name, the STORED licence (a scan uploaded earlier, or by path). null = nothing to send. */
export function licenceModelPayload(lic: { images?: unknown[]; file_b64?: string; mime?: string; filename?: string },
    stored: { bytes: Uint8Array; mime: string } | null, codeName: string | null) {
  const images = Array.isArray(lic.images) ? lic.images : [];
  if (images.length || lic.file_b64) return { images, file_b64: lic.file_b64, mime: lic.mime, filename: lic.filename };
  if (codeName || !stored?.bytes?.length) return null;
  return /^image\//i.test(stored.mime)
    ? { images: [{ b64: toB64(stored.bytes), mime: stored.mime }], file_b64: undefined, mime: stored.mime, filename: lic.filename }
    : { images: [], file_b64: toB64(stored.bytes), mime: stored.mime || 'application/pdf', filename: lic.filename || 'licence.pdf' };
}

/** The one call the upload paths make: bytes in, a read expiry or null out. Images return null (no OCR here). */
export async function readExpiry(bytes: Uint8Array, mime: string): Promise<ExpiryRead | null> {
  if (!/pdf/i.test(mime)) return null;
  const text = await pdfText(bytes);
  return text ? expiryFromText(text) : null;
}
