// Prevented-by test for the supplier journey audit of 28 Oct 2026 (docs/reports/supplier_journey_audit_28_oct/sales_agent):
// three model replies to an invited, unregistered supplier went out with no registration link. The bodies below are those
// replies verbatim (greeting and sign-off removed, as composeMailReply adds them), from cases c2, c5 and c8.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { ADD_CONTACT_FACT, claimLinkOf, customerFacts, NEXT_STEP_PORTAL, NEXT_STEP_REGISTER, PORTAL_LEAD, PORTAL_URL, registeredSupplierFacts, SUPPLIER_SIGN_IN_FACT, supplierFacts, supplierTermsFact, unregisteredSupplierFacts, withClaimLink, withoutWriteToUs } from './account_facts.ts';

const LINK = 'https://quotesdone.com/portal?t=0f6c1e1e-aaaa-4bbb-8ccc-123456789abc';
const FACTS = unregisteredSupplierFacts('ZZ DEMO Audit Co', LINK);
const onOwnLine = (t: string) => t.split('\n').some((l) => l.trim() === LINK);

const C2 = 'Registration is free permanently for the first 1,000 suppliers. From the 1,001st registration, the annual subscription is AED 1,000. There is no commission on work you win. As your company has not registered yet, I can’t confirm which registration tier will apply; it depends on whether your registration is among the first 1,000.';
const C5 = 'Supplier registration is free permanently for the first 1,000 businesses. To complete registration, you’ll need your company’s licensed legal name, a valid UAE trade licence, a company profile listing your trades and emirates, a verified mobile number and email address, and a signed Supplier Agreement. We check the licence number, issuing authority and expiry date.';
const C8 = 'The only mandatory document to upload is your valid UAE trade licence. To complete registration, we also need your licensed business name, an OTP-verified mobile number, a verified email address, a company profile listing the trades and emirates you cover, and your signed acceptance of the Supplier Agreement. We check the licence number, issuing authority and expiry date. VAT certificates, insurance and ISO certificates are optional and do not hold up registration.';

Deno.test('the facts name the link the reply must carry', () => {
  assertEquals(claimLinkOf(FACTS), LINK);
  assertEquals(claimLinkOf(unregisteredSupplierFacts('', 'https://quotesdone.com/portal')), 'https://quotesdone.com/portal');
});
for (const [name, body] of [['c2 (cost, reasoned)', C2], ['c5 (Arabic, direct)', C5], ['c8 (documents, reasoned)', C8]]) {
  Deno.test(`audit case ${name}: the reply that dropped the link now carries it on its own line`, () => {
    assert(!onOwnLine(body), 'known-bad control: the audited reply had no link');
    const out = withClaimLink(body, FACTS);
    assert(onOwnLine(out));
    assert(out.startsWith(body), 'the model text is kept as written');
  });
}
Deno.test('a reply that already has the link on its own line is not changed (c9 shape, and wrapped forms)', () => {
  for (const line of [LINK, `<${LINK}>`, `  ${LINK}.`]) {
    const body = 'Open your company\'s own registration link:\n' + line + '\n\nChoose "Create account".';
    assertEquals(withClaimLink(body, FACTS), body);
  }
});
Deno.test('a link buried in a sentence still gets its own line', () => {
  const out = withClaimLink(`Register at ${LINK} today.`, FACTS);
  assert(onOwnLine(out));
});
Deno.test('no invited-supplier facts: the reply is untouched', () => {
  for (const f of ['', SUPPLIER_SIGN_IN_FACT, supplierFacts('ZZ DEMO Co', []), customerFacts([])]) assertEquals(withClaimLink(C2, f), C2);
});
Deno.test('every reply path in email_triage passes the model text through withClaimLink', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const calls = src.match(/composeMailReply\(\{[^}]*\}\)/g) || [];
  assert(calls.length >= 2, 'both the person path and the reasoned/direct path compose a reply');
  for (const c of calls) assert(/answer:\s*withWhatsappTail\(withClaimLink\(body,\s*facts\),\s*waTail\)/.test(c), 'unwrapped reply path: ' + c);
  // 16 Nov 2026 (marketing, ledger 1184/1373): every path also carries the WhatsApp line (the offer, or his confirmation code)
});

// ── 17 Nov 2026 (sales_engineer): Shine Carpets Washing L.L.C. (inbound_messages 2214, "interested, send contact details and an
// overview"). The reply that went (notification 149799), greeting and sign-off removed, before code added the link block:
const SHINE = 'QuotesDone is a UAE B2B quotation marketplace. Buyers describe what they need, and the platform matches requests with suppliers who can do that trade. Suppliers can submit anonymised quotations; buyers compare them and pay a 3% reveal fee to unlock the supplier they choose. The service is designed to provide relevant requests, and QuotesDone charges suppliers no commission on work won.\n\nYou can contact us at management@quotesdone.com or call +971 56 791 8605. WhatsApp is +1 218 316 6814 for messages only. Our hours are Monday to Friday, 9am to 6pm UAE time, excluding UAE public holidays.\n\nPlease add supplier@quotesdone.com to your contacts, or write to that address first.';
Deno.test('Shine Carpets: the reply to an interested prospect ends with one next step and his own link, never "write to that address"', () => {
  const out = withClaimLink(SHINE, FACTS);
  assert(onOwnLine(out), 'his own registration link on its own line');
  assert(out.includes(NEXT_STEP_REGISTER), 'one clear next step before the link');
  assert(out.indexOf(NEXT_STEP_REGISTER) < out.indexOf(LINK));
  assert(!/write to that address/i.test(out), out);
  assert(out.includes('Please add supplier@quotesdone.com to your contacts.'), 'the contacts request is kept');
  assert(!/write to that address/i.test(ADD_CONTACT_FACT) && /never ask them to write to/i.test(ADD_CONTACT_FACT));
});
Deno.test('a sentence sending them to the address they wrote to is removed; other contact lines stay', () => {
  const body = 'Thank you for your interest.\nYou can reach Ahmad at supplier@quotesdone.com. You can also call us.\nE-mail us at supplier@quotesdone.com for anything else.';
  const out = withoutWriteToUs(body);
  assert(!/supplier@quotesdone\.com/.test(out), out);
  assert(out.includes('You can also call us.') && out.startsWith('Thank you for your interest.'));
  assertEquals(withoutWriteToUs(C2), C2);
});
Deno.test('a registered supplier gets his portal link instead of a registration link', () => {
  const facts = registeredSupplierFacts('ZZ DEMO Co', null);
  assert(facts.includes(PORTAL_LEAD + PORTAL_URL));
  assertEquals(claimLinkOf(facts), null);
  const out = withClaimLink('Your documents are complete.', facts);
  assert(out.endsWith(NEXT_STEP_PORTAL + '\n' + PORTAL_URL) && !out.includes('?t='), out);
  assertEquals(withClaimLink('Open ' + PORTAL_URL + ' and choose Services.', facts), 'Open ' + PORTAL_URL + ' and choose Services.');
});
Deno.test('the prospect asking for plans is answered from the live terms (pricing_config as measured 18 Nov 2026)', () => {
  const t = supplierTermsFact({ supplier_free_count: 1000, supplier_reg_fee: 1000, supplier_reg_currency: 'AED', supplier_reg_period: 'yearly', standard_reveal_rate: 0.03 });
  assert(t.includes('first 1,000 suppliers') && t.includes('AED 1,000 a year') && t.includes('no commission') && t.includes('3% fee'), t);
  assertEquals(supplierTermsFact(null), '');
  assert(unregisteredSupplierFacts('ZZ', LINK, t).includes(t));
  assert(!unregisteredSupplierFacts('ZZ', LINK).includes('WHAT A SUPPLIER PAYS'));
});
