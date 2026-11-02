// Prevented-by test for the supplier journey audit of 28 Oct 2026 (docs/reports/supplier_journey_audit_28_oct/sales_agent):
// three model replies to an invited, unregistered supplier went out with no registration link. The bodies below are those
// replies verbatim (greeting and sign-off removed, as composeMailReply adds them), from cases c2, c5 and c8.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { claimLinkOf, customerFacts, SUPPLIER_SIGN_IN_FACT, supplierFacts, unregisteredSupplierFacts, withClaimLink } from './account_facts.ts';

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
  for (const c of calls) assert(/answer:\s*withClaimLink\(body,\s*facts\)/.test(c), 'unwrapped reply path: ' + c);
});
