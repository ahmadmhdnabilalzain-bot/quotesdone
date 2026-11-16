// own_request_facts.test.ts — every channel tells the model to answer his own request from the facts, and a sealed quote's own
// words pass the code generaliser. Ids and names are ZZ DEMO shapes.
import { assert, assertEquals, assertMatch, assertNotMatch } from 'jsr:@std/assert@1';
import { customerRecordFacts, generaliseOwnRequestFacts, OWN_REQUEST_RULE, withoutDuplicateRequests } from './own_request_facts.ts';

const PACK = { identity: { kind: 'customer', requests: [{ ref: 14, asked: { budget_as_he_stated_it: 'AED 5,000 excluding VAT' }, quotes: [
  { letter: 'A', price_ex_vat_aed: 4600, revealed: false, warranty_as_stated: '2 years Grohe mixer', lead_time_as_stated: '3 days', validity_as_stated: '30 days' },
  { letter: 'B', price_ex_vat_aed: 4900, revealed: true, supplier: 'ZZ DEMO Revealed Co', warranty_as_stated: '2 years Grohe mixer' },
] }] } };

Deno.test('the rule names every fact the scenarios need and forbids invention, identity and a claimed change', () => {
  for (const k of ['asked', 'changes_he_sent_after', 'comparison', 'budget', 'VAT', 'lead time', 'brand', 'AED', '3.6725', 'reveal', 'cancel']) assert(OWN_REQUEST_RULE.includes(k), k);
  assertMatch(OWN_REQUEST_RULE, /Never ask again/);
  assertMatch(OWN_REQUEST_RULE, /Never state a price, date, count or brand the record does not hold/);
  assertMatch(OWN_REQUEST_RULE, /never a supplier's name, contact or brand/);
  assertMatch(OWN_REQUEST_RULE, /never say it is done/);
});

Deno.test('a sealed quote loses a known brand in its own words; a revealed one and the prices do not change', () => {
  const g = generaliseOwnRequestFacts(PACK);
  const [a, b] = g.identity.requests[0].quotes as Record<string, unknown>[];
  assertNotMatch(String(a.warranty_as_stated), /Grohe/);
  assertEquals(a.lead_time_as_stated, '3 days');
  assertEquals(a.validity_as_stated, '30 days');
  assertEquals(a.price_ex_vat_aed, 4600);
  assertEquals(b.warranty_as_stated, '2 years Grohe mixer');
  assertEquals(g.identity.requests[0].asked.budget_as_he_stated_it, 'AED 5,000 excluding VAT');
  assertEquals(PACK.identity.requests[0].quotes[0].warranty_as_stated, '2 years Grohe mixer', 'the input is not changed');
});

Deno.test('the own record points at the fact pack instead of carrying the same requests twice', () => {
  const mine = { known: true, name: 'ZZ DEMO', inquiries: PACK.identity.requests };
  assertEquals(withoutDuplicateRequests(mine, PACK).inquiries, 'the same requests as FACT PACK identity.requests below');
  assertEquals(withoutDuplicateRequests(mine, null).inquiries, mine.inquiries);
  assertEquals(withoutDuplicateRequests(mine, { identity: { kind: 'unknown' } }).inquiries, mine.inquiries);
});

Deno.test('a sealed supplier\'s question to him passes the generaliser; his answer is his own and kept', () => {
  const g = generaliseOwnRequestFacts({ quotes: [{ letter: 'B', revealed: false, questions_and_answers: [{ supplier_asked: 'Is a Grohe mixer acceptable?', he_answered: 'Yes, Grohe is fine' }] }] });
  const qa = (g.quotes[0] as { questions_and_answers: { supplier_asked: string; he_answered: string }[] }).questions_and_answers[0];
  assertNotMatch(qa.supplier_asked, /Grohe/);
  assertEquals(qa.he_answered, 'Yes, Grohe is fine');
});

// who-knows-what gap 3 (16 Nov 2026): the portal chat reads his account and his case timeline, as the widget does
Deno.test('the portal chat gets his account (without a second copy of his requests) and his case timeline', async () => {
  const f = customerRecordFacts({ known: true, scope: 'customer', account: { email: 'zz-demo@example.invalid' }, inquiries: [{ ref: 14 }] },
    [{ channel: 'whatsapp', kind: 'refund', summary: 'refund REF-1 decided by the CEO' }]);
  assert(f.includes('zz-demo@example.invalid') && f.includes('REF-1') && !f.includes('"ref":14'));
  assertEquals(customerRecordFacts(null, []), '');
  assertEquals(customerRecordFacts({ known: false }, null), '');
  const src = await Deno.readTextFile(new URL('../sales_engineer/actions/portal.ts', import.meta.url));
  assert(/rpc\('fn_wa_context'[\s\S]{0,200}rpc\('fn_contact_timeline'/.test(src) && /customerRecordFacts\(live, events\)/.test(src), 'portal.ts does not read the account and the timeline');
  assert(/\[ownQuote \?[\s\S]{0,300}, record\]/.test(src), 'the portal facts do not carry them');
});
