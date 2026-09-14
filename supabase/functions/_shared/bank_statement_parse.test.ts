import { assertEquals } from 'jsr:@std/assert@1';
import { isBankStatement, parseAmount, parseDate, parseStatement } from './bank_statement_parse.ts';

Deno.test('a Mashreq statement is told apart from a receipt', () => {
  assertEquals(isBankStatement('estatements@mashreq.com', 'Your Mashreq account statement for August 2026'), true);
  assertEquals(isBankStatement('management@quotesdone.com', 'Fw: Mashreq statement Aug'), true);
  assertEquals(isBankStatement('invoice+statements@vercel.com', 'Your receipt from Vercel'), false);
  assertEquals(isBankStatement('noreply@mashreq.com', 'Your card was used'), false);
});

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
