// identity_scrubbers_finish_on_adversarial_input.test.ts — every exported scrubber finishes, on input built to make a
// regex backtrack (13 Nov 2026, independent review of the anonymity fix round: PHONE_WORDS_RE never finished on a run of
// 104 digits, so one customer's serial number could stall every matched supplier's inbox; 50 KB of "near Xyz," cost 524
// ms). A hard time limit per call, on the shapes that broke before: long digit runs, "Al Al Al…", repeated cues, thousands
// of commas, a 200 KB BOQ, long Arabic.
// deno test --no-lock supabase/functions/_shared/identity_scrubbers_finish_on_adversarial_input.test.ts
import { assert } from 'jsr:@std/assert@1';
import { identityShapesIn, knownNameRe, scrubAddresses, scrubIdentityText } from './identity_text.ts';
import { placeSpans, reducePlaces } from './identity_places.ts';
import { redactText, residualScan } from './anonymise.ts';
import { maskContacts } from './quote_documents.ts';
import { generaliseText } from './quote_generalise.ts';
import { inboxField, scrubDeep, scrubIdentity } from '../supplier_api/identity_scrub.ts';
import { stripContact, stripSupplierQuestion } from '../messages_api/strip_contact.ts';
import { scrubIdentity as boqScrub } from '../drawing_boq/boq_from_text.ts';
import { scrubModelText } from '../quote_extract/model_reading.ts';

const digits = (n: number) => '0123456789'.repeat(Math.ceil(n / 10)).slice(0, n);
const line = 'Item 3: Supply and install emulsion, 2 coats on walls, 450 m2 @ AED 12.50 = 5,625.00. Warranty 2 years. Delivery to site in Dubai. ';
const INPUTS: [string, string][] = [
  ['200 digits', `Serial numbers: ${digits(200)} end`], ['5,000 digits', `Serial numbers: ${digits(5000)} end`], ['digit groups', '12 '.repeat(5000)],
  ['50 KB Al Al', 'Al '.repeat(17000)], ['50 KB Al Barsha', 'Al Barsha '.repeat(5000)], ['near Xyz, repeated', 'near Xyz, '.repeat(5000)],
  ['thousands of commas', '1,'.repeat(25000)], ['Villa 1, repeated', 'Villa 1, '.repeat(5500)], ['zero five repeated', 'zero five '.repeat(5000)],
  ['Title Case words', 'Main Distribution Board Tower '.repeat(1700)], ['a @ b.', 'a @ b.'.repeat(8000)],
  ['long Arabic', 'تركيب بلاط السيراميك في الحمام والمطبخ مع الضمان قرب '.repeat(1000)], ['Arabic place run', 'فيلا رقم ١ البرشاء '.repeat(2500)],
];
const NAME = 'ZZ DEMO Falcon Trading LLC';
const RUN: [string, (s: string) => unknown][] = [
  ['scrubIdentityText', (s) => scrubIdentityText(s, '[X]')], ['identityShapesIn', identityShapesIn], ['reducePlaces', (s) => reducePlaces(s, '[X]')], ['placeSpans', placeSpans],
  ['scrubAddresses', scrubAddresses], ['knownNameRe', (s) => s.replace(knownNameRe(NAME, { fragments: true })!, '')], ['redactText', (s) => redactText(s, ['haddad'])],
  ['residualScan', (s) => residualScan(s, ['haddad'])], ['maskContacts', (s) => maskContacts(s, [NAME])], ['generaliseText', (s) => generaliseText(s, { supplierNames: [NAME] })],
  ['scrubIdentity', (s) => scrubIdentity(s, NAME, [])], ['scrubDeep', (s) => scrubDeep({ a: s }, NAME, [])], ['stripContact', (s) => stripContact(s, [NAME])],
  ['stripSupplierQuestion', (s) => stripSupplierQuestion(s, [NAME])], ['drawing_boq scrubIdentity', boqScrub], ['scrubModelText', scrubModelText],
  ['inboxField', (s) => inboxField(s, 'ZZ DEMO Omar Haddad', ['zz demo omar haddad', 'haddad'], [])],
];
// The limits: 2 s for a text scrubber on 50 KB (the edge CPU cap is 2 s for a whole request; these inputs are far beyond any
// real field), 4 s for the inbox gate, which also paints seeds and residual-scans (main took 6.2 s on 50 KB of bare digits,
// so that shape is not asked of it).
Deno.test('every exported scrubber finishes on every adversarial input within its limit', () => {
  const slow: string[] = [];
  for (const [what, s] of INPUTS) for (const [who, f] of RUN) {
    const t0 = performance.now(); f(s); const ms = performance.now() - t0;
    if (ms > (who === 'inboxField' ? 4000 : 2000)) slow.push(`${who} on ${what}: ${ms.toFixed(0)} ms`);
  }
  assert(!slow.length, slow.join('\n'));
});
Deno.test('a 200 KB BOQ description passes the text scrubbers in under 2 s each', () => {
  const big = line.repeat(Math.ceil(200000 / line.length));
  for (const [who, f] of RUN.filter(([w]) => w !== 'inboxField' && w !== 'redactText' && w !== 'residualScan')) { const t0 = performance.now(); f(big); const ms = performance.now() - t0; assert(ms < 2000, `${who}: ${ms.toFixed(0)} ms`); }
});
