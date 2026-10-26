import { assertEquals } from 'jsr:@std/assert@1';
import { parseAmount, parseDate, parseStatement, readStatement } from './bank_statement_parse.ts';
import { linesFromRuns, type TextRun } from './pdf_text_positions.ts';

Deno.test('dates are day-first and invalid ones are refused', () => {
  assertEquals(parseDate('03/09/2026'), '2026-09-03');
  assertEquals(parseDate('3-Sep-2026'), '2026-09-03');
  assertEquals(parseDate('2026-09-03'), '2026-09-03');
  assertEquals(parseDate('31/02/2026'), null);
  assertEquals(parseDate('Sep 3'), null);
});

Deno.test('amounts: separators, brackets and signs; junk is refused', () => {
  assertEquals(parseAmount('1,234.50'), 1234.5);
  assertEquals(parseAmount('(200.00)'), -200);
  assertEquals(parseAmount('-12'), -12);
  assertEquals(parseAmount('AED 90.10'), 90.1);
  assertEquals(parseAmount('12.3.4'), null);
  assertEquals(parseAmount(''), null);
});

Deno.test('a CSV with debit and credit columns keeps the sign of each line', () => {
  const csv = [
    'Account Statement,Mashreq', '',
    'Transaction Date,Description,Reference,Debit,Credit,Balance',
    '02/09/2026,STRIPE PAYMENTS UK LTD PAYOUT,PO123,,"1,504.20","10,504.20"',
    '05/09/2026,ACCOUNT MAINTENANCE CHARGE,,200.00,,"10,304.20"',
  ].join('\n');
  assertEquals(parseStatement(csv), [
    { value_date: '2026-09-02', description: 'STRIPE PAYMENTS UK LTD PAYOUT', amount_aed: 1504.2, reference: 'PO123' },
    { value_date: '2026-09-05', description: 'ACCOUNT MAINTENANCE CHARGE', amount_aed: -200, reference: null },
  ]);
});

Deno.test('a CSV with one signed amount column is read as signed', () => {
  const csv = 'Date;Narration;Amount\n01-Sep-2026;STRIPE PAYOUT;300.00\n30-Sep-2026;MONTHLY FEE;-200.00';
  assertEquals(parseStatement(csv).map((l) => l.amount_aed), [300, -200]);
});

Deno.test('a printed statement is read only where CR or DR says the direction', () => {
  const text = ['Mashreq Bank PSC', '02/09/2026 STRIPE PAYOUT 1,504.20 CR 10,504.20',
    '05/09/2026 ACCOUNT MAINTENANCE CHARGE 200.00 DR 10,304.20', '06/09/2026 SOMETHING 99.00 10,205.20'].join('\n');
  assertEquals(parseStatement(text), [
    { value_date: '2026-09-02', description: 'STRIPE PAYOUT', amount_aed: 1504.2, reference: null },
    { value_date: '2026-09-05', description: 'ACCOUNT MAINTENANCE CHARGE', amount_aed: -200, reference: null },
  ]);
});

Deno.test('Arabic-Indic digits, the Arabic decimal mark and separators are read as numbers', () => {
  const csv = 'Date,Description,Debit,Credit\n٠٢/٠٩/٢٠٢٦,STRIPE PAYOUT,,"١٬٥٠٤٫٢٠"\n۰۵/۰۹/۲۰۲۶,MONTHLY FEE,۲۰۰٫۰۰,';
  assertEquals(parseStatement(csv), [
    { value_date: '2026-09-02', description: 'STRIPE PAYOUT', amount_aed: 1504.2, reference: null },
    { value_date: '2026-09-05', description: 'MONTHLY FEE', amount_aed: -200, reference: null },
  ]);
});

Deno.test('thousands separators in the millions, and fils kept exactly with no float drift', () => {
  const csv = 'Date,Description,Amount\n01/09/2026,STRIPE PAYOUT,"1,234,567.89"\n02/09/2026,STRIPE PAYOUT,0.1\n03/09/2026,FEE,-0.07';
  assertEquals(parseStatement(csv).map((l) => l.amount_aed), [1234567.89, 0.1, -0.07]);
  assertEquals(parseAmount('1,23,4.00'), null);        // a malformed grouping is refused, not guessed
  assertEquals(parseAmount('12.345'), null);            // three decimals are not AED fils
});

Deno.test('a debit column and a credit column on the same line: the credit wins only when it is non-zero', () => {
  const csv = 'Date,Description,Debit,Credit\n02/09/2026,REVERSAL,0.00,50.00\n03/09/2026,CHARGE,75.00,0.00';
  assertEquals(parseStatement(csv).map((l) => l.amount_aed), [50, -75]);
});

Deno.test('two identical lines are two lines: the parser never de-duplicates', () => {
  const csv = 'Date,Description,Amount\n30/09/2026,ACCOUNT MAINTENANCE CHARGE,-200.00\n30/09/2026,ACCOUNT MAINTENANCE CHARGE,-200.00';
  assertEquals(parseStatement(csv).length, 2);
});

Deno.test('dates: every accepted shape, and impossible or ambiguous-looking ones refused', () => {
  assertEquals(parseDate('3.9.2026'), '2026-09-03');
  assertEquals(parseDate('29/02/2028'), '2028-02-29');
  assertEquals(parseDate('29/02/2026'), null);
  assertEquals(parseDate('13/13/2026'), null);
  assertEquals(parseDate('03 September 2026'), '2026-09-03');
});

Deno.test('text with no direction marks reads as nothing, never as a guess', () => {
  assertEquals(parseStatement('02/09/2026 STRIPE PAYOUT 1,504.20 10,504.20'), []);
});

// ── The Mashreq e-statement ──────────────────────────────────────────────────────────────────────
// INVENTED values in the exact layout of the real September 2026 e-statement: three-decimal amounts,
// Debit and Credit both printed on every row, the running balance last, OPENING/CLOSING rows, centred
// wrapped descriptions (2 above + 2 below, 1 + 1, 0 + 0) and "VALUE DATE:" inside the description.
// No account number, name, reference or amount here is real.
const ESTATEMENT = [
  'Mashreqbank PSC is regulated by the Central Bank of the United Arab Emirates.',
  'Current Account Statement',
  'Account No 000111222333 AED',
  'Statement for Period 01/07/2026 to 31/07/2026',
  'Date Transaction Reference no Debit Credit Balance',
  'e - statement',
  'OPENING BALANCE 0.000 0.000 12,345.670',
  'TRANSFER IN',
  '000000000000ZZ000000000000000000000',
  '07/07/2026 000ZZZZ00000000ZZZ 0.000 2,500.000 14,845.670',
  '- ZZ DEMO SENDER - P_2_P -',
  '000000000000Z00000000000000000000',
  '09/07/2026 Monthly Maintenance Fee 000111222333 0ZZREFAED 00001 150.000 0.000 14,695.670',
  '09/07/2026 Value Added Tax - Output 000111222333 0ZZREFAED 00002 7.500 0.000 14,688.170',
  'VALUE DATE: 01-08-2026 Value Added Tax -',
  '31/07/2026 0ZZREFAED 00002 7.500 0.000 14,680.670',
  'Output 000111222333',
  'VALUE DATE: 01-08-2026 Interest',
  '31/07/2026 0ZZCIDAED 00001 0.000 1,234.560 15,915.230',
  '000111222333',
  'CLOSING BALANCE 0.000 0.000 15,915.230',
  'Page 3 of 5',
].join('\n');

Deno.test('the Mashreq e-statement: one line per row, signed, wrapped descriptions joined, value dates read', () => {
  const st = readStatement(ESTATEMENT);
  assertEquals(st.problem, null);
  assertEquals([st.opening_balance_aed, st.closing_balance_aed, st.period_from, st.period_to],
               [12345.67, 15915.23, '2026-07-01', '2026-07-31']);
  assertEquals(st.lines, [
    { value_date: '2026-07-07', description: 'TRANSFER IN 000000000000ZZ000000000000000000000 - ZZ DEMO SENDER - P_2_P - 000000000000Z00000000000000000000 000ZZZZ00000000ZZZ', amount_aed: 2500, reference: null },
    { value_date: '2026-07-09', description: 'Monthly Maintenance Fee 000111222333 0ZZREFAED 00001', amount_aed: -150, reference: null },
    { value_date: '2026-07-09', description: 'Value Added Tax - Output 000111222333 0ZZREFAED 00002', amount_aed: -7.5, reference: null },
    { value_date: '2026-08-01', description: 'Value Added Tax - Output 000111222333 0ZZREFAED 00002', amount_aed: -7.5, reference: null },
    { value_date: '2026-08-01', description: 'Interest 000111222333 0ZZCIDAED 00001', amount_aed: 1234.56, reference: null },
  ]);
  assertEquals(parseStatement(ESTATEMENT).length, 5);
});

Deno.test('the Mashreq e-statement reconciles: opening + sum(lines) = closing, to the fils', () => {
  const st = readStatement(ESTATEMENT);
  const fils = (n: number) => Math.round(n * 100);
  assertEquals(fils(st.opening_balance_aed!) + st.lines.reduce((s, l) => s + fils(l.amount_aed), 0), fils(st.closing_balance_aed!));
});

Deno.test('a Mashreq statement that does not add up yields no lines and says why — nothing is booked', () => {
  const badRow = readStatement(ESTATEMENT.replace('14,688.170', '14,688.270'));
  assertEquals(badRow.lines, []);
  assertEquals(/row 3/.test(badRow.problem || ''), true);
  const badClose = readStatement(ESTATEMENT.replace('CLOSING BALANCE 0.000 0.000 15,915.230', 'CLOSING BALANCE 0.000 0.000 15,915.240'));
  assertEquals(badClose.lines, []);
  assertEquals(/closing balance/.test(badClose.problem || ''), true);
  assertEquals(readStatement(ESTATEMENT.replace('7.500 0.000 14,688.170', '7.505 0.000 14,688.165')).lines, []);   // not fils
  assertEquals(/USD/.test(readStatement(ESTATEMENT.replace('000111222333 AED', '000111222333 USD')).problem || ''), true);
  assertEquals(readStatement(ESTATEMENT.replace('0.000 2,500.000 14,845.670', '2,500.000 2,500.000 14,845.670')).lines, []);
});

Deno.test('a page-break header between two rows breaks only the wrap split, never the amounts', () => {
  const st = readStatement(ESTATEMENT.replace('Output 000111222333\n', 'Output 000111222333\nPage 3 of 5\nDate Transaction Reference no Debit Credit Balance\n'));
  assertEquals(st.problem, null);
  assertEquals(st.lines.map((l) => l.amount_aed), [2500, -150, -7.5, -7.5, 1234.56]);
});

Deno.test('the runtime path: positioned PDF runs rebuilt into rows read the same as the text', () => {
  // Runs as pdf_text_positions returns them: normalised top-left y, one run per table cell line, the
  // wrapped description lines centred on the dated row (the geometry of the real statement).
  const L = 0.0107;
  const runs: TextRun[] = [];
  const at = (y: number, ...cells: [number, string][]) => { for (const [x, text] of cells) runs.push({ text, x, y, w: 0.1, h: 0.01 }); };
  at(0.16, [0.47, 'Account No'], [0.62, '000111222333 AED']);
  at(0.37, [0.08, 'Statement for Period 01/07/2026 to 31/07/2026']);
  at(0.43, [0.17, 'OPENING BALANCE'], [0.69, '0.000'], [0.79, '0.000'], [0.92, '12,345.670']);
  let y = 0.46;
  at(y - 1.5 * L, [0.17, 'TRANSFER IN']); at(y - 0.5 * L, [0.17, '000000000000ZZ000000000000000000000']);
  at(y, [0.086, '07/07/2026'], [0.46, '000ZZZZ00000000ZZZ'], [0.69, '0.000'], [0.77, '2,500.000'], [0.9, '14,845.670']);
  at(y + 0.5 * L, [0.17, '- ZZ DEMO SENDER - P_2_P -']); at(y + 1.5 * L, [0.17, '000000000000Z00000000000000000000']);
  y = 0.49; at(y, [0.086, '09/07/2026'], [0.17, 'Monthly Maintenance Fee  000111222333'], [0.46, '0ZZREFAED 00001'], [0.67, '150.000'], [0.79, '0.000'], [0.91, '14,695.670']);
  y = 0.51; at(y, [0.086, '09/07/2026'], [0.17, 'Value Added Tax - Output  000111222333'], [0.46, '0ZZREFAED 00002'], [0.69, '7.500'], [0.79, '0.000'], [0.91, '14,688.170']);
  y = 0.53; at(y - 0.5 * L, [0.17, 'VALUE DATE: 01-08-2026 Value Added Tax -']); at(y + 0.5 * L, [0.17, 'Output  000111222333']);
  at(y, [0.086, '31/07/2026'], [0.46, '0ZZREFAED 00002'], [0.69, '7.500'], [0.79, '0.000'], [0.91, '14,680.670']);
  y = 0.555; at(y - 0.5 * L, [0.17, 'VALUE DATE: 01-08-2026 Interest']); at(y + 0.5 * L, [0.17, '000111222333']);
  at(y, [0.086, '31/07/2026'], [0.46, '0ZZCIDAED 00001'], [0.69, '0.000'], [0.79, '1,234.560'], [0.91, '15,915.230']);
  at(0.60, [0.17, 'CLOSING BALANCE'], [0.69, '0.000'], [0.79, '0.000'], [0.91, '15,915.230']);
  runs.reverse();   // content-stream order is not reading order
  const fromRuns = readStatement(linesFromRuns([{ width: 595, height: 842, rotate: 0, runs }]));
  assertEquals(fromRuns.problem, null);
  assertEquals(fromRuns.lines, readStatement(ESTATEMENT).lines);
  assertEquals(fromRuns.closing_balance_aed, 15915.23);
});
