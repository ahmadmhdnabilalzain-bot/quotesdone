// A value is what its evidence says, number for number (review of #1444 and #1445). No network.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { refuse, valueInEvidence } from './think.ts';

const AR30 = String.fromCharCode(0x663, 0x660);           // "30" in Arabic-Indic digits
const AR3 = String.fromCharCode(0x663);
const AR_DAY = String.fromCharCode(0x64A, 0x648, 0x645);   // "day" (Arabic)
const AR9000 = String.fromCharCode(0x669, 0x66C, 0x660, 0x660, 0x660);   // 9,000 with the Arabic thousands separator

Deno.test('a number in a value must be a WHOLE number of its evidence', () => {
  const no: [string, string][] = [
    ['3', 'Validity: 30 days'], ['2', '25 m2'], ['0.5', '10.5 mm'], ['5', '10.5 mm'], ['30', '300 days'],
    ['9,000', '9,000.00'], ['000', '9,000.00'],
    ['2', 'internal walls 450 m2'],                // the "2" of a unit written apart is not a quantity
    [AR3, AR30 + ' ' + AR_DAY],                    // \p{Nd}: an Arabic 3 does not pass for an Arabic 30
  ];
  for (const [v, e] of no) assertEquals(valueInEvidence(v, e), false, `"${v}" must not pass for "${e}"`);
});

Deno.test('a bare value matches a number with its unit or currency glued on', () => {
  const yes: [string, string][] = [
    ['9,000', 'aed9,000 total'], ['450', '450m2 internal walls'], ['10', '10mm board'], ['30', 'validity 30days'],
    ['30 days', 'Validity: 30 days'], ['30', 'Validity: 30 days.'], ['9,000.00', 'AED 9,000.00 total'],
    ['20.00', '450,m2,20.00,9000.00'], ['9000.00', '450,m2,20.00,9000.00'], ['1,5', '"1,5"'], ['10.5', '10.5 mm'],
    [AR30 + ' ' + AR_DAY, 'صلاحية ' + AR30 + ' ' + AR_DAY], [AR9000, 'المجموع ' + AR9000],
  ];
  for (const [v, e] of yes) assert(valueInEvidence(v, e), `"${v}" must pass for "${e}"`);
});

Deno.test('code-like tokens: C25, L1, m2 as a name match only themselves', () => {
  assert(valueInEvidence('c25', 'grade c25 concrete'));
  assert(valueInEvidence('l1', 'see l1 on the drawing'));
  assertEquals(valueInEvidence('25', 'grade c25 concrete'), false, 'the 25 of C25 is not a quantity of 25');
  assertEquals(valueInEvidence('1', 'see l1 on the drawing'), false);
});

// One case per kind of numeric field the think() decision schemas read today (reasoned_matching TERM_FIELDS, reasoned_suppliers
// QUOTE_TERMS, line_specs attrs, reasoned_books vendor): none of these legitimate values may be refused.
Deno.test('every numeric field type in use keeps its legitimate values', () => {
  const ok: [string, string, string][] = [
    ['lead_time / delivery (duration)', '3 weeks', 'lead time: 3 weeks from approval'],
    ['delivery (date)', '15/11/2026', 'delivery by 15/11/2026'],
    ['validity (days glued)', '30', 'valid for 30days'],
    ['warranty_period', '2 years', 'warranty: 2 years materials and workmanship'],
    ['thickness_mm (glued unit)', '18', '18mm mr mdf carcass'],
    ['glass_thickness', '6mm', '6mm clear tempered glass'],
    ['dimensions', '1200x600', 'porcelain tiles 1200x600mm'],
    ['coats (count)', '2 coats', 'jotun fenomastic 2 coats, 450 m2'],
    ['percentage', '50%', 'payment: 50% advance, 50% on completion'],
    ['money (currency glued)', '11,160.00', 'total aed11,160.00 excluding vat'],
    ['vendor (name with digits)', 'zz demo trading 2000 llc', 'invoice from zz demo trading 2000 llc'],
  ];
  for (const [kind, v, e] of ok) assert(valueInEvidence(v, e), `${kind}: "${v}" was refused for "${e}"`);
});

Deno.test('refuse(): "3" taken from "Validity: 30 days" is refused; "30 days" is not', () => {
  const decision = { name: 'terms', fields: [{ key: 'validity', question: 'validity' }] };
  const draft = (value: string) => ({ answer: 'x '.repeat(30), reasoning: ['r'], decision: { fields: { validity: { value, evidence: 'Validity: 30 days' } } } });
  const o = { missing: [], sourceIds: new Set<string>(), decision, conversationText: 'Validity: 30 days', requireTrail: false };
  assert(/not in the evidence/.test(String(refuse(draft('3') as never, o))));
  assertEquals(refuse(draft('30 days') as never, o), null);
});
