// Date shapes and keywords of the expiry reader (split out of document_expiry.ts, 9 Nov 2026; a pure move).
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
  // 3 Nov 2026 (certificate_period_expiry.test.ts, 120 certificates): 'End Date: B' beside 'Start Date: A' read nothing
  'end date',
  'تاريخ الانتهاء', 'تاريخ انتهاء', 'الانتهاء', 'ينتهي في', 'ينتهي', 'صالحة حتى', 'صالح حتى', 'سارية حتى', 'ساري حتى',
];
// 3 Nov 2026 (certificate_period_expiry.test.ts): 'Policy Period: A - B' read nothing (8 of the 120 certificates)
const PERIOD_KEYWORDS = ['validity', 'period of insurance', 'policy period', 'period of cover', 'insurance period', 'صلاحية', 'مدة التأمين'];
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
export { BETWEEN_END_RE, BETWEEN_LEAD_RE, DATE_RE, EARLIER_RE, EXPIRY_KEYWORDS, EXPIRY_RE, PERIOD_KEYWORDS, PERIOD_RE, RANGE_END_RE, RANGE_JOIN, START_KEYWORDS, START_RE, esc, rangeEnd };
