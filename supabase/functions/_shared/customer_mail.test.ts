// The customer's Messages -> e-mail channel must never show back-office mail. Pure function, no
// permissions: `deno test supabase/functions/_shared/customer_mail.test.ts`.
import { assertEquals } from 'jsr:@std/assert@1';
import { isCustomerCorrespondence, isInternalMailbox } from './customer_mail.ts';

Deno.test('the GoDaddy expense forward seen live on 14 Sep 2026 is excluded', () => {
  // The exact shape accountant/index.ts writes for a booked historical-sweep receipt.
  assertEquals(isCustomerCorrespondence({
    to_email: 'expenses@mail.quotesdone.com',
    owner_role: null,
    body: '[expense subscription] GoDaddy 40.95 AED on 2026-08-14 +pdf — accountant historical sweep, Resend inbound id 0000',
  }), false);
  // The same body even if the recipient were recorded differently: the tag alone excludes it.
  assertEquals(isCustomerCorrespondence({ to_email: 'info@mail.quotesdone.com', body: '[expense one-off] GoDaddy 40.95 AED' }), false);
});

Deno.test('refused, held and owned receipt rows are excluded', () => {
  assertEquals(isCustomerCorrespondence({ to_email: 'x@example.invalid', body: '[REFUSED — sender is not on app_secrets.expense_forwarders] ...' }), false);
  assertEquals(isCustomerCorrespondence({ to_email: 'x@example.invalid', body: '[HELD — no amount could be read, nothing booked] ...' }), false);
  assertEquals(isCustomerCorrespondence({ to_email: 'x@example.invalid', body: '[receipt received but NOT booked — sender not allowlisted] ...' }), false);
  assertEquals(isCustomerCorrespondence({ to_email: 'info@mail.quotesdone.com', owner_role: 'bookkeeper', body: 'hello' }), false);
});

Deno.test('mail to internal mailboxes is excluded, info@ is not', () => {
  for (const a of ['expenses@mail.quotesdone.com', 'Expenses <EXPENSES@mail.quotesdone.com>', 'docs@mail.quotesdone.com',
    'supplier@quotesdone.com', 'management@quotesdone.com', 'info@mail.quotesdone.com, expenses@mail.quotesdone.com']) {
    assertEquals(isInternalMailbox(a), true, a);
  }
  for (const a of ['info@mail.quotesdone.com', 'info@quotesdone.com', 'expenses@example.invalid', '', null]) {
    assertEquals(isInternalMailbox(a), false, String(a));
  }
});

Deno.test('a normal customer message is kept', () => {
  assertEquals(isCustomerCorrespondence({
    to_email: 'info@mail.quotesdone.com', owner_role: null,
    body: 'Hi, I posted a kitchen fit-out request yesterday — when will I see quotes?',
  }), true);
});
