// expiryFromText: the expiry a document's text states (split out of document_expiry.ts, 9 Nov 2026; a pure move).
import { BETWEEN_END_RE, BETWEEN_LEAD_RE, DATE_RE, EARLIER_RE, EXPIRY_RE, type ExpiryRead, parseDate, PERIOD_RE, RANGE_END_RE, RANGE_JOIN, rangeEnd, START_RE } from './dates.ts';
import { type Cell, cellDate, cellsOf, DATE_G, type Doc, isLabel, REFUSED, rowCells, severalRows, tableRead } from './tables.ts';

// "Issue/Expiry Date: 15/03/2025 / 14/03/2028" names two dates with one label: the expiry is the later of the two, and
// with one date there is nothing to read (main read the issue date there).
const ISSUE_JOINED_RE = /(?<![\w-])(?:issue|issued|issuance)\s*(?:\/|&|and)\s*$/i;
// ...and only a second date joined straight to the first counts (review of #1733: "Issue/Expiry Date: 15/03/2025
// Next Inspection: 01/06/2029" read the inspection date when any later date in the window was taken).
const ISSUE_PAIR_RE = rangeEnd('(?:' + RANGE_JOIN + '|\\/|&|and)');

/** The first occurrence of one kind of keyword that reads a date: in its own column of a table, or within 90
 *  characters after it. A start keyword reads only the end of the period it opens. */
function readAfter(d: Doc, keywords: RegExp, kind: 'expiry' | 'period' | 'start'): ExpiryRead | null | typeof REFUSED {
  const { t, cells, byLine } = d;
  let from = 0;
  for (let i = 0; i < 20; i++) {
    const km = keywords.exec(t.slice(from));
    if (!km) return null;
    const ks = from + (km.index ?? 0), at = ks + km[0].length;
    const lineBefore = t.slice(Math.max(0, ks - 40), ks).split('\n').pop() ?? '';
    const table = EARLIER_RE.test(lineBefore) ? null : tableRead(d, ks);
    if (table === REFUSED) { if (kind !== 'start') return REFUSED; }
    else if (table && kind !== 'start') return { expiry: table.expiry, source: 'text', keyword: km[0], raw: table.raw };
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
      for (const c of cells) if (c.s >= joinedTo && (c.kind === 'end' || /^renewal date$/i.test(t.slice(c.s, c.e))) && /^\s*\/\s*$/.test(t.slice(joinedTo, c.s))) joinedTo = c.e;
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
          const pair = ISSUE_PAIR_RE.exec(rest), second = pair ? parseDate(pair[1]) : null;
          if (first && second) return { expiry: second > first ? second : first, source: 'text', keyword: km[0], raw: dm[0] + pair![0] };
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
  for (const [re, kind] of [[EXPIRY_RE, 'expiry'], [PERIOD_RE, 'period'], [START_RE, 'start']] as const) {
    const r = readAfter(d, re, kind);
    if (r === REFUSED) return null;
    if (r) return r;
  }
  return null;
}
