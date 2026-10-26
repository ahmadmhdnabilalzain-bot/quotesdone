// READING A BANK STATEMENT, DETERMINISTICALLY (14 Sep 2026, agent: accountant, duty 1).
//
// The bank is Mashreq; the founder forwards the monthly statement to the expenses mailbox. This reads only
// what it can read WITHOUT GUESSING:
//   * a CSV (or semicolon) export with a header naming a date column and either one signed amount
//     column or separate debit/credit columns;
//   * Mashreq's printed e-statement (parseMashreqEstatement below — built against the real September 2026
//     statement's layout, with its opening and closing balance proving every row);
//   * a text layer whose lines end in an amount marked CR or DR (the common printed-statement shape).
// Anything else returns no lines, and the statement is recorded as UNREADABLE — a finding asking for the
// CSV export — rather than read with a guessed sign. A debit read as a credit would match a payout that
// never arrived.
//
// Pure, so it is tested alone (bank_statement_parse.test.ts).
export type StatementLine = { value_date: string; description: string; amount_aed: number; reference: string | null };

/**
 * Whether a message to the expenses mailbox is a bank statement rather than a receipt.
 * docText (14 Sep 2026): the founder's real Mashreq e-statement arrives as "eStatement_<date>_<n>.pdf",
 * forwarded from his own address — nothing in the sender, the subject or the filename names the bank. The
 * document itself does ("Mashreqbank PSC", "Statement for Period"), so the text the runtime rebuilt from the
 * PDF is the fourth witness.
 */
export function isBankStatement(from: string, subject: string, filenames: string[] = [], docText = ''): boolean {
  const f = String(from || '').toLowerCase();
  const s = String(subject || '').toLowerCase();
  const names = filenames.map((n) => String(n || '').toLowerCase()).join(' ');
  const d = String(docText || '');
  const bank = /mashreq/.test(f) || /mashreq/.test(s) || /mashreq/.test(names) || /mashreq/i.test(d);
  return bank && (/statement/.test(s) || /statement/.test(names) || /estatement|e-statement/.test(f)
                  || /statement (?:for )?period/i.test(d));
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

/** Arabic-Indic (٠-٩) and Eastern Arabic-Indic (۰-۹) digits, the Arabic decimal and thousands marks, to ASCII. */
export function asciiDigits(text: string): string {
  return String(text || '')
    .replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, (c) => String(c.charCodeAt(0) - 0x06F0))
    .replace(/٫/g, '.').replace(/٬/g, ',');
}

// ── THE MASHREQ E-STATEMENT (14 Sep 2026) ────────────────────────────────────────────────────────
// Measured on the founder's real September 2026 e-statement (never copied into the repo): the parser above
// read 0 of its lines, because the printed statement has no CR/DR marks. What it has instead:
//   * a table "Date | Transaction | Reference no | Debit | Credit | Balance", every amount with THREE
//     decimals ("2,500.000") and both Debit and Credit printed on every row ("0.000" in the unused one);
//   * "OPENING BALANCE d c b" above the first row and "CLOSING BALANCE d c b" below the last;
//   * a description that wraps is a vertically CENTRED cell, so its extra lines sit half above the dated
//     line and half below it. Measured: 2 above and 2 below, 1 and 1, 0 and 0 — never lopsided;
//   * "VALUE DATE: DD-MM-YYYY" inside the description when the value date differs from the Date column.
// The sign is not guessed: debit and credit are separate columns. And every row is PROVED before it is
// believed: each row's printed balance must equal the previous balance plus the row, and opening + sum of
// rows must equal the closing balance, to the fils. A statement that does not add up returns NO lines and
// a problem — the caller records it unreadable (an open accountant finding) and books nothing.

export type StatementRead = {
  lines: StatementLine[];
  opening_balance_aed: number | null;
  closing_balance_aed: number | null;   // #659's field name on the bank_statement action
  period_from: string | null;
  period_to: string | null;             // the date the closing balance is printed for (#659's balance_on)
  problem: string | null;               // set when the layout was recognised and the statement does not add up
};

const AMT3 = String.raw`(\d{1,3}(?:,\d{3})*\.\d{3})`;

/** "2,500.000" -> 250000 fils. Mashreq prints AED to three decimals; a non-zero third decimal is not fils. */
function fils3(raw: string): number | null {
  const t = raw.replace(/,/g, '');
  if (!/^\d+\.\d{2}0$/.test(t)) return null;
  return Number(t.replace('.', '').slice(0, -1));
}

/** The e-statement's text, lines in page order. null when the layout is not this one. */
export function parseMashreqEstatement(text: string): StatementRead | null {
  const rows = String(text || '').split(/\r?\n/).map((l) => l.replace(/\s+/g, ' ').trim()).filter(Boolean);
  const openAt = rows.map((r, i) => /^OPENING BALANCE /i.test(r) ? i : -1).filter((i) => i >= 0);
  if (!openAt.length) return null;
  const closeAt = rows.map((r, i) => /^CLOSING BALANCE /i.test(r) ? i : -1).filter((i) => i >= 0);
  const per = rows.join('\n').match(/Statement (?:for )?Period (\d{2}\/\d{2}\/\d{4}) to (\d{2}\/\d{2}\/\d{4})/i);
  const out: StatementRead = { lines: [], opening_balance_aed: null, closing_balance_aed: null,
    period_from: per ? parseDate(per[1]) : null, period_to: per ? parseDate(per[2]) : null, problem: null };
  const fail = (why: string): StatementRead => ({ ...out, lines: [], problem: why });

  const ccy = [...rows.join('\n').matchAll(/Account No\.? \d+ ([A-Z]{3})\b/g)].map((m) => m[1]).filter((c) => c !== 'AED');
  if (ccy.length) return fail('the statement is for an account in ' + ccy[0] + ', not AED');
  // ponytail: one account section per statement. A consolidated statement with a second account prints a
  // second OPENING/CLOSING pair; read each section on its own account key when a second account exists.
  if (openAt.length !== 1 || closeAt.length !== 1 || closeAt[0] < openAt[0]) {
    return fail('expected one OPENING BALANCE and one CLOSING BALANCE after it; found ' + openAt.length + ' and ' + closeAt.length);
  }
  const bal = (r: string) => { const m = r.match(new RegExp(String.raw`BALANCE ${AMT3} ${AMT3} ${AMT3}$`, 'i')); return m ? fils3(m[3]) : null; };
  const open = bal(rows[openAt[0]]); const close = bal(rows[closeAt[0]]);
  if (open === null || close === null) return fail('the opening or closing balance is not printed as an AED amount');
  out.opening_balance_aed = open / 100; out.closing_balance_aed = close / 100;

  // The dated rows, and the undated lines between them (the wrapped halves of the descriptions).
  const rowRe = new RegExp(String.raw`^(\d{2}\/\d{2}\/\d{4})\s*(.*?)\s*${AMT3} ${AMT3} ${AMT3}$`);
  const dated: { date: string; mid: string; dr: number | null; cr: number | null; bal: number | null }[] = [];
  const gaps: string[][] = [[]];
  for (const r of rows.slice(openAt[0] + 1, closeAt[0])) {
    const m = r.match(rowRe);
    if (!m) { gaps[gaps.length - 1].push(r); continue; }
    const d = parseDate(m[1]);
    if (!d) return fail('a row carries a date that does not exist: ' + m[1]);
    dated.push({ date: d, mid: m[2], dr: fils3(m[3]), cr: fils3(m[4]), bal: fils3(m[5]) });
    gaps.push([]);
  }
  if (!dated.length) return fail('the statement lists no transactions between its opening and closing balance');

  // Centred cells: above(0) = gap(0); below(i) = above(i); above(i+1) = gap(i+1) - below(i); and the last
  // row's below must use up the final gap exactly. If that arithmetic fails (a page break's repeated header
  // falls between two rows), each gap is given to the row after it — the amounts are unaffected.
  const above: number[] = []; let ok = true; let a = gaps[0].length;
  for (let i = 0; i < dated.length; i++) { above.push(a); a = gaps[i + 1].length - a; if (a < 0) { ok = false; break; } }
  if (ok && above[dated.length - 1] !== gaps[dated.length].length) ok = false;

  let prev = open; let sum = 0;
  for (let i = 0; i < dated.length; i++) {
    const r = dated[i];
    if (r.dr === null || r.cr === null || r.bal === null) return fail('row ' + (i + 1) + ' (' + r.date + ') has an amount that is not AED fils');
    if (r.dr > 0 && r.cr > 0) return fail('row ' + (i + 1) + ' (' + r.date + ') carries both a debit and a credit');
    const amt = r.cr - r.dr;
    if (amt === 0) return fail('row ' + (i + 1) + ' (' + r.date + ') moves no money');
    if (prev + amt !== r.bal) return fail('row ' + (i + 1) + ' (' + r.date + '): the previous balance plus this row is not the balance printed on it');
    prev = r.bal; sum += amt;
    const up = ok ? gaps[i].slice(gaps[i].length - above[i]) : gaps[i];
    const down = ok ? gaps[i + 1].slice(0, above[i]) : [];
    let desc = [...up, ...down, r.mid].join(' ');
    let value = r.date;
    const vd = desc.match(/VALUE DATE:\s*(\d{2}-\d{2}-\d{4})\s*/i);
    if (vd) { const v = parseDate(vd[1]); if (v) { value = v; desc = desc.replace(vd[0], ' '); } }
    desc = desc.replace(/\s+/g, ' ').trim();
    if (!desc) return fail('row ' + (i + 1) + ' (' + r.date + ') has no description');
    out.lines.push({ value_date: value, description: desc, amount_aed: amt / 100, reference: null });
  }
  if (prev !== close || open + sum !== close) return fail('opening balance plus the rows is not the closing balance printed');
  return out;
}

/**
 * Whatever the statement is: its lines and, where the layout prints them, its opening and closing balance
 * and its period. Lines are [] when it cannot be read safely; `problem` says why when the layout was
 * recognised and did not add up.
 * Two identical lines are two lines (two AED 200 charges on one day are both real): the parser never
 * de-duplicates. A re-forwarded statement is made harmless by fn_accountant_bank_statement_ingest, which
 * keys each line on its content AND its occurrence number inside the statement.
 */
export function readStatement(text: string): StatementRead {
  const t = asciiDigits(text);
  const bare = (lines: StatementLine[]): StatementRead =>
    ({ lines, opening_balance_aed: null, closing_balance_aed: null, period_from: null, period_to: null, problem: null });
  const csv = parseCsvStatement(t);
  if (csv) return bare(csv);
  return parseMashreqEstatement(t) ?? bare(parseTextStatement(t));
}

export function parseStatement(text: string): StatementLine[] {
  return readStatement(text).lines;
}
