// A SUPPLIER IN THE UAE IS NEVER GIVEN A FOREIGN TELEPHONE NUMBER BY A REPLY A MODEL WRITES (it_engineer, 19 Nov 2026).
// The person line of ai_reply.ts named the WhatsApp sender's +1 number to every audience; a supplier now gets the e-mail and the
// UAE line the company brief publishes, and a sentence that writes a foreign number to him is refused. Customers keep the
// published WhatsApp line. confirmLine still names the sender: the supplier must send his code TO it (ruling 863, no new sender).
import { assert, assertEquals, assertFalse } from 'jsr:@std/assert';
import { aiSystem, personContact, SUPPLIER_PERSON_CONTACT, supplierPhoneProblems } from './ai_reply.ts';
import { BRIEF_TEXT } from './brief.generated.ts';
import { confirmLine, FOREIGN_PHONE, OUR_WHATSAPP } from './whatsapp_offer.ts';
import { FOREIGN_PHONE as LANE_FOREIGN_PHONE } from '../send_outbox/m365_lane.ts';

const base = { seat: 'customer_support' as const, channel: 'email', lang: 'en' as const, message: 'Can I speak to someone?' };

Deno.test('a supplier who asks for a person is given no foreign number; a customer keeps the published WhatsApp line', () => {
  for (const briefInPrompt of [true, false]) {
    const sup = aiSystem({ ...base, audience: 'supplier', briefInPrompt }, 'en');
    assertFalse(sup.includes(OUR_WHATSAPP), 'the supplier prompt still writes the +1 number');
    assert(sup.includes(SUPPLIER_PERSON_CONTACT) && sup.includes('Never write a telephone number outside the UAE'), sup);
    const cus = aiSystem({ ...base, audience: 'customer', briefInPrompt }, 'en');
    assert(cus.includes('+1 218 316 6814 (WhatsApp, Mon-Fri 9am-6pm GST)'), 'control: the customer line is unchanged');
  }
  assertFalse(FOREIGN_PHONE.test(personContact('supplier')), 'the supplier contact line itself carries a foreign number');
});

Deno.test('the supplier contact is one the company already publishes, not a new one', () => {
  const company = JSON.parse(Deno.readTextFileSync('src/content/company.json'));
  assert(SUPPLIER_PERSON_CONTACT.includes(company.licence_phone.number) && SUPPLIER_PERSON_CONTACT.includes(company.email));
  assert(BRIEF_TEXT.includes('calls **' + company.licence_phone.number + '**'), 'the brief no longer publishes the UAE line');
});

Deno.test('a sentence that gives a supplier a foreign number is refused, a UAE one is not', () => {
  assertEquals(supplierPhoneProblems('Message us on WhatsApp at +1 218 316 6814.').length, 1);
  assertEquals(supplierPhoneProblems('Reach us on +12183166814.').length, 1);
  assertEquals(supplierPhoneProblems('Call +971 56 791 8605 or write to management@quotesdone.com.'), []);
  assertEquals(supplierPhoneProblems('Your quotation of AED 12,500 + 5% VAT is noted.'), []);
});

Deno.test('one definition of a foreign number: the campaign lint and the reply check read the same pattern', () => {
  assertEquals(LANE_FOREIGN_PHONE, FOREIGN_PHONE);
  // the one line that names the sender to a supplier, by design: he sends the code to that WhatsApp
  assert(FOREIGN_PHONE.test(confirmLine('48213307')));
});
