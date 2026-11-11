// What the reader recorded off a trade licence is what the registration form shows (customer_support, 10 Nov 2026,
// supplier registration certification). Fails on main: process_docs answered a code-read licence with its expiry alone, and the
// form's licence number and authority fields stayed empty.
import { assertEquals } from 'jsr:@std/assert@1';
import { licenceShownBack } from './licence_shown_back.ts';

const CODE_ONLY_ANSWER = { expiry: '2027-05-03', source: 'text', keyword: 'expiry date', read_by: 'code', licence_name: 'ZZ DEMO Ghaf Joinery and Carpentry LLC' };
const ROW = { trade_license_no: 'CN-ZZ482137', license_authority: 'Abu Dhabi Department of Economic Development', licence_legal_name: 'ZZ DEMO Ghaf Joinery and Carpentry LLC', license_expiry: '2027-05-03', emirate: 'Abu Dhabi' };

Deno.test('a licence code read whole: the answer carries the number and the authority the form shows', () => {
  const out = licenceShownBack(CODE_ONLY_ANSWER, ROW, true)!;
  assertEquals(out.license_number, 'CN-ZZ482137');
  assertEquals(out.authority, 'Abu Dhabi Department of Economic Development');
  assertEquals(out.legal_name, 'ZZ DEMO Ghaf Joinery and Carpentry LLC');
  assertEquals(out.read_by, 'code');
});

Deno.test('the row wins over a model answer that disagrees (the row keeps code\'s number)', () => {
  const out = licenceShownBack({ license_number: 'CN-ZZ482131', authority: 'ADDED' }, ROW, true)!;
  assertEquals(out.license_number, 'CN-ZZ482137');
});

Deno.test('nothing read and nothing recorded stays nothing; no licence in the call leaves the answer alone', () => {
  assertEquals(licenceShownBack(undefined, {}, true), undefined);
  assertEquals(licenceShownBack(undefined, ROW, false), undefined);
  assertEquals(licenceShownBack(undefined, { trade_license_no: 'ZZ-1' }, true), { license_number: 'ZZ-1' });
});

Deno.test('process_docs answers with what the row holds, before a clashing number is set aside', async () => {
  const src = await Deno.readTextFile(new URL('../actions/documents.ts', import.meta.url));
  const shown = src.indexOf('licenceShownBack(');
  const aside = src.indexOf('if (licenceSetAside) {');
  if (shown < 0) throw new Error('process_docs never applies licenceShownBack: the form shows empty licence fields');
  if (!(aside > shown)) throw new Error('licenceShownBack must run before the set-aside removes a clashing number');
});
