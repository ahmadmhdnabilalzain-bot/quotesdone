// A certificate's START date is never offered as its EXPIRY (3 Nov 2026, sales_engineer). The 28 Oct document walk found the
// insurance start date offered as the expiry (#1708, live); this replays the rule over a corpus of 120 certificate texts:
// 15 ways a UAE insurance / ISO / dealer certificate or licence prints its period x 8 date styles. Graded by code:
//   WRONG  the expiry read is the start date, the issue date or an earlier document's date: must be 0, always
//   EXACT  the expiry read is the period's end date: measured, and held at the level this file states
// deno test -A --no-lock --node-modules-dir=auto supabase/functions/_shared/certificate_period_expiry.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { expiryFromText } from './document_expiry.ts';

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MONTH = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const p2 = (n: number) => String(n).padStart(2, '0');
// each style prints an ISO date the way a certificate does
export const STYLES: Record<string, (iso: string) => string> = {
  'dd/mm/yyyy': (d) => d.split('-').reverse().join('/'),
  'dd-mm-yyyy': (d) => d.split('-').reverse().join('-'),
  'yyyy-mm-dd': (d) => d,
  'dd.mm.yyyy': (d) => d.split('-').reverse().join('.'),
  'd Mon yyyy': (d) => { const [y, m, dd] = d.split('-').map(Number); return `${dd} ${MON[m - 1]} ${y}`; },
  'Mon d, yyyy': (d) => { const [y, m, dd] = d.split('-').map(Number); return `${MON[m - 1]} ${dd}, ${y}`; },
  'd Month yyyy': (d) => { const [y, m, dd] = d.split('-').map(Number); return `${dd} ${MONTH[m - 1]} ${y}`; },
  'ddMONyyyy': (d) => { const [y, m, dd] = d.split('-').map(Number); return `${p2(dd)}-${MON[m - 1].toUpperCase()}-${y}`; },
};
// A = start, B = end, P = an earlier policy's expiry (a decoy)
export const LAYOUTS: Record<string, (A: string, B: string, P: string) => string> = {
  period_to: (A, B) => `CERTIFICATE OF INSURANCE\nInsured: ZZ DEMO Contracting LLC\nPeriod of Insurance: ${A} to ${B}`,
  period_from_to: (A, B) => `MOTOR AND LIABILITY\nPeriod of Insurance: From ${A} To ${B}`,
  policy_period_dash: (A, B) => `Policy No: ZZ-0001\nPolicy Period: ${A} - ${B}`,
  validity_dash: (A, B) => `TRADE LICENCE\nValidity: ${A} - ${B}`,
  effective_expiry: (A, B) => `Effective Date: ${A}\nExpiry Date: ${B}`,
  inception_expiry: (A, B) => `Inception Date: ${A}\nExpiry Date: ${B}`,
  start_end_one_line: (A, B) => `Start Date: ${A}    End Date: ${B}`,
  valid_from_until: (A, B) => `This certificate is valid from ${A} until ${B}.`,
  valid_from_valid_until: (A, B) => `Valid From: ${A}\nValid Until: ${B}`,
  commencement_expiration: (A, B) => `Commencement Date: ${A}\nExpiration Date: ${B}`,
  header_row: (A, B) => `Issue Date      Expiry Date\n${A}      ${B}`,
  arabic_period: (A, B) => `شهادة تأمين\nمدة التأمين: من ${A} إلى ${B}\nتاريخ الانتهاء: ${B}`,
  issue_expiry: (A, B) => `Date of Issue: ${A}\nDate of Expiry: ${B}`,
  previous_policy_decoy: (A, B, P) => `RENEWAL SCHEDULE\nPrevious Policy Expiry: ${P}\nPeriod of Insurance: ${A} to ${B}`,
  iso_issue_valid_until: (A, B) => `ISO 9001:2015\nCertificate No: ZZ-ISO-7\nDate of Issue: ${A}\nValid until: ${B}`,
};
const A = '2026-01-15', B = '2027-01-14', P = '2026-01-14';

Deno.test('120 certificates: the start, issue or an earlier document\'s date is never read as the expiry', () => {
  const rows: { layout: string; style: string; got: string | null }[] = [];
  for (const [layout, f] of Object.entries(LAYOUTS)) for (const [style, fmt] of Object.entries(STYLES)) {
    rows.push({ layout, style, got: expiryFromText(f(fmt(A), fmt(B), fmt(P)))?.expiry ?? null });
  }
  assertEquals(rows.length, 120);
  const wrong = rows.filter((r) => r.got !== null && r.got !== B);
  assertEquals(wrong, [], 'a date that is not the period end was read as the expiry');
  const exact = rows.filter((r) => r.got === B).length;
  const unread = rows.filter((r) => r.got === null).map((r) => `${r.layout}/${r.style}`);
  console.log(`certificates: ${exact}/120 expiry exact, 0 wrong, ${unread.length} unread${unread.length ? ': ' + unread.join(', ') : ''}`);
  // an unread expiry is asked of the supplier (set_expiry) or the model, never guessed: held at the measured level
  assert(exact >= EXACT_AT_LEAST, `${exact}/120 exact, below the ${EXACT_AT_LEAST} measured on 3 Nov 2026`);
});
const EXACT_AT_LEAST = 120;
