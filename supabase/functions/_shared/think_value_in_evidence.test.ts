// A value is what its evidence says, number for number (review of #1444). No network.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { refuse, valueInEvidence } from './think.ts';

Deno.test('a number in a value must be a WHOLE number of its evidence', () => {
  const no: [string, string][] = [['3', 'Validity: 30 days'], ['2', '25 m2'], ['0.5', '10.5 mm'], ['5', '10.5 mm'], ['30', '300 days'], ['9,000', '9,000.00'], ['000', '9,000.00']];
  for (const [v, e] of no) assertEquals(valueInEvidence(v, e), false, `"${v}" must not pass for "${e}"`);
  const yes: [string, string][] = [['30 days', 'Validity: 30 days'], ['30', 'Validity: 30 days.'], ['2 coats', '2 coats'], ['9,000.00', 'AED 9,000.00 total'],
    ['20.00', '450,m2,20.00,9000.00'], ['9000.00', '450,m2,20.00,9000.00'], ['1,5', '"1,5"'], ['jotun', 'jotun fenomastic'], ['10.5', '10.5 mm'], ['c25', 'grade c25 concrete'], ['2 coats', 'jotun 2 coats, 450 m2']];
  for (const [v, e] of yes) assert(valueInEvidence(v, e), `"${v}" must pass for "${e}"`);
});

Deno.test('refuse(): "3" taken from "Validity: 30 days" is refused; "30 days" is not', () => {
  const decision = { name: 'terms', fields: [{ key: 'validity', question: 'validity' }] };
  const draft = (value: string) => ({ answer: 'x '.repeat(30), reasoning: ['r'], decision: { fields: { validity: { value, evidence: 'Validity: 30 days' } } } });
  const o = { missing: [], sourceIds: new Set<string>(), decision, conversationText: 'Validity: 30 days', requireTrail: false };
  assert(/not in the evidence/.test(String(refuse(draft('3') as never, o))));
  assertEquals(refuse(draft('30 days') as never, o), null);
});
