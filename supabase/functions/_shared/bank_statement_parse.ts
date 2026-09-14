// READING A BANK STATEMENT, DETERMINISTICALLY (14 Sep 2026, agent: accountant, duty 1).
//
// The bank is Mashreq; the founder forwards the monthly statement to the expenses mailbox. No sample
// statement exists in the estate yet, so this reads only what it can read WITHOUT GUESSING:
//   * a CSV (or semicolon) export with a header naming a date column and either one signed amount
//     column or separate debit/credit columns;
//   * a text layer whose lines end in an amount marked CR or DR (the common printed-statement shape).
// Anything else returns no lines, and the statement is recorded as UNREADABLE — a finding asking for the
// CSV export — rather than read with a guessed sign. A debit read as a credit would match a payout that
// never arrived.
//
// Pure, so it is tested alone (bank_statement_parse.test.ts).
export type StatementLine = { value_date: string; description: string; amount_aed: number; reference: string | null };

/** Whether a message to the expenses mailbox is a bank statement rather than a receipt. */
export function isBankStatement(from: string, subject: string, filenames: string[] = []): boolean {
  const f = String(from || '').toLowerCase();
  const s = String(subject || '').toLowerCase();
  const names = filenames.map((n) => String(n || '').toLowerCase()).join(' ');
  const bank = /mashreq/.test(f) || /mashreq/.test(s) || /mashreq/.test(names);
  return bank && (/statement/.test(s) || /statement/.test(names) || /estatement|e-statement/.test(f));
}

const MONTHS: Record<string, string> = { jan: '01', feb: '02', mar: '03', apr: '04', may: '05', jun: '06',
  jul: '07', aug: '08', sep: '09', oct: '10', nov: '11', dec: '12' };

/** DD/MM/YYYY, DD-MM-YYYY, DD-Mon-YYYY, DD Mon YYYY or YYYY-MM-DD, to YYYY-MM-DD. UAE statements are day-first. */
export function parseDate(raw: string): string | null {
  const t = String(raw || '').trim();
  let m = t.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  m = t.match(/^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{4})$/);
  if (m) return valid(m[3], m[2].padStart(2, '0'), m[1].padStart(2, '0'));
  m = t.match(/^(\d{1,2})[\s-]([A-Za-z]{3})[A-Za-z]*[\s-](\d{4})$/);
  if (m && MONTHS[m[2].toLowerCase()]) return valid(m[3], MONTHS[m[2].toLowerCase()], m[1].padStart(2, '0'));
  return null;
}
function valid(y: string, mo: string, d: string): string | null {
  const iso = `${y}-${mo}-${d}`;
  const dt = new Date(iso + 'T00:00:00Z');
  return !isNaN(dt.getTime()) && dt.toISOString().slice(0, 10) === iso ? iso : null;
}

/** "1,234.50" -> 1234.5; "(12.00)" -> -12; "" -> null. */
export function parseAmount(raw: string): number | null {
  let t = String(raw ?? '').trim().replace(/AED/i, '').replace(/\s/g, '');
  if (!t) return null;
  let neg = false;
  if (/^\(.*\)$/.test(t)) { neg = true; t = t.slice(1, -1); }
  if (t.startsWith('-')) { neg = !neg; t = t.slice(1); }
  if (!/^\d{1,3}(,\d{3})*(\.\d{1,2})?$|^\d+(\.\d{1,2})?$/.test(t)) return null;
  const n = Number(t.replace(/,/g, ''));
  return Number.isFinite(n) ? (neg ? -n : n) : null;
}

function splitCsv(line: string, sep: string): string[] {
  const out: string[] = []; let cur = ''; let q = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"') { if (q && line[i + 1] === '"') { cur += '"'; i++; } else q = !q; }
    else if (c === sep && !q) { out.push(cur); cur = ''; }
    else cur += c;
  }
  out.push(cur);
  return out.map((x) => x.trim());
}

/** A CSV export. Returns null when the header is not one it can read, so the caller can try text. */
export function parseCsvStatement(text: string): StatementLine[] | null {
  const rows = String(text || '').split(/\r?\n/).filter((l) => l.trim());
  for (let h = 0; h < Math.min(rows.length, 15); h++) {
    const sep = (rows[h].match(/;/g) || []).length > (rows[h].match(/,/g) || []).length ? ';' : ',';
    const head = splitCsv(rows[h], sep).map((x) => x.toLowerCase());
    const di = head.findIndex((x) => /^(value date|transaction date|date|posting date)$/.test(x));
    const de = head.findIndex((x) => /description|narration|details|particulars/.test(x));
    const am = head.findIndex((x) => /^amount( \(aed\))?$/.test(x));
    const dr = head.findIndex((x) => /^(debit|withdrawals?|debit amount)$/.test(x));
    const cr = head.findIndex((x) => /^(credit|deposits?|credit amount)$/.test(x));
    const rf = head.findIndex((x) => /reference|ref\.?|cheque/.test(x));
    if (di < 0 || de < 0 || (am < 0 && (dr < 0 || cr < 0))) continue;
    const out: StatementLine[] = [];
    for (const r of rows.slice(h + 1)) {
      const c = splitCsv(r, sep);
      const d = parseDate(c[di] || '');
      if (!d) continue;
      let amt: number | null;
      if (am >= 0) amt = parseAmount(c[am] || '');
      else {
        const dv = parseAmount(c[dr] || ''); const cv = parseAmount(c[cr] || '');
        amt = cv ? Math.abs(cv) : dv ? -Math.abs(dv) : null;
      }
      const desc = String(c[de] || '').trim();
      if (amt === null || amt === 0 || !desc) continue;
      out.push({ value_date: d, description: desc, amount_aed: Math.round(amt * 100) / 100, reference: rf >= 0 ? (c[rf] || null) : null });
    }
    return out;
  }
  return null;
}

/** A printed statement's text layer: only lines whose amount carries CR or DR are read. */
export function parseTextStatement(text: string): StatementLine[] {
  const out: StatementLine[] = [];
  for (const raw of String(text || '').split(/\r?\n/)) {
    const line = raw.replace(/\s+/g, ' ').trim();
    const m = line.match(/^(\d{1,2}[\/.-](?:\d{1,2}|[A-Za-z]{3})[\/.-]\d{4})\s+(.+?)\s+([\d,]+\.\d{2})\s?(CR|DR)\b/i);
    if (!m) continue;
    const d = parseDate(m[1]); const a = parseAmount(m[3]);
    if (!d || a === null || a === 0) continue;
    out.push({ value_date: d, description: m[2].trim(), amount_aed: m[4].toUpperCase() === 'CR' ? a : -a, reference: null });
  }
  return out;
}

/** Whatever the statement is, the lines it can be read into — or [] when it cannot be read safely. */
export function parseStatement(text: string): StatementLine[] {
  return parseCsvStatement(text) ?? parseTextStatement(text);
}
