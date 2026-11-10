// The customer's Messages -> e-mail channel must never show back-office mail. Pure function, no
// permissions: `deno test supabase/functions/_shared/customer_mail.test.ts`.
import { assertEquals } from 'jsr:@std/assert@1';
import { composeMailReply, isCustomerCorrespondence, isInternalMailbox, noAutoReply } from './customer_mail.ts';

Deno.test('the GoDaddy expense forward seen live on 14 Sep 2026 is excluded', () => {
  // The exact shape accountant/actions/expenses.ts (expense_sweep) writes for a booked historical-sweep receipt.
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

// ── the automatic reply (28 Sep 2026, customer_support) ─────────────────────────────────────────────
const FOUNDER = ['management@quotesdone.com', 'owner@example.invalid'];
const cust = (o: Record<string, unknown> = {}) => ({ from_email: 'zz-demo-customer@example.invalid', to_email: 'info@mail.quotesdone.com', body: 'Hello', ...o });

Deno.test('a customer writing to info@ is answered', () => {
  assertEquals(noAutoReply(cust(), FOUNDER), null);
  assertEquals(noAutoReply(cust({ raw: { auto_submitted: 'no' } }), FOUNDER), null);
});

Deno.test('the four classes the founder named are never answered', () => {
  assertEquals(noAutoReply(cust({ from_email: 'Owner@Example.invalid' }), FOUNDER), 'founder');
  assertEquals(noAutoReply(cust({ from_email: 'management@quotesdone.com' }), FOUNDER), 'founder');
  assertEquals(noAutoReply(cust({ from_email: 'security-noreply@linkedin.com' }), FOUNDER), 'no_reply'); // inbound 159, 23 Sep
  assertEquals(noAutoReply(cust({ from_email: 'no-reply@accounts.google.com' }), FOUNDER), 'no_reply');
  assertEquals(noAutoReply(cust({ from_email: 'verify@example.invalid' }), FOUNDER), 'no_reply');
  assertEquals(noAutoReply(cust({ from_email: 'MAILER-DAEMON@amazonses.com' }), FOUNDER), 'bounce');
  assertEquals(noAutoReply(cust({ raw: { content_type: 'multipart/report; report-type=delivery-status' } }), FOUNDER), 'bounce');
  assertEquals(noAutoReply(cust({ raw: { calendar: true } }), FOUNDER), 'calendar');
  assertEquals(noAutoReply(cust({ to_email: 'calendar+b3a7@mail.quotesdone.com' }), FOUNDER), 'calendar');
  assertEquals(noAutoReply(cust({ raw: { auto_submitted: 'auto-replied' } }), FOUNDER), 'auto_submitted');
  assertEquals(noAutoReply(cust({ to_email: 'expenses@mail.quotesdone.com' }), FOUNDER), 'internal');
  assertEquals(noAutoReply(cust({ from_email: 'x@mail.quotesdone.com' }), FOUNDER), 'internal');
  assertEquals(noAutoReply(cust({ from_email: '' }), FOUNDER), 'no_reply');
});

// Rulings 1195/1196 (12 Oct 2026): the passage, receipt and person sentences were removed; the body is always the
// model's reply and only the greeting and sign-off are code.
Deno.test('the e-mail is the model reply between a fixed greeting and sign-off, in the asker\'s language', () => {
  const a = composeMailReply({ lang: 'en', answer: 'You pay 3% only when you reveal.' });
  assertEquals(a, 'Hello,\n\nYou pay 3% only when you reveal.\n\nKind regards,\nThe QuotesDone Team');
  const ar = composeMailReply({ lang: 'ar', answer: 'تدفع 3% فقط عند الكشف.' });
  assertEquals(ar.startsWith('مرحباً') && ar.includes('تدفع 3% فقط عند الكشف.'), true);
});

// PREVENTED BY (28 Oct 2026, sales_engineer, ledger 1375): every reply to the invitation mailbox read "Not answered
// automatically: internal" (inbound_messages 653-655 on 27 Oct; a ZZ DEMO invited lead's "yes" probed 28 Oct).
import { INVITATION_MAILBOX, invitationReplyAnswerable } from './customer_mail.ts';
const yes = (o: Record<string, unknown> = {}) => ({ from_email: 'sales@glassco.ae', to_email: INVITATION_MAILBOX, body: 'Yes, we are interested.', raw: {}, ...o });
Deno.test('an invited supplier\'s reply to supplier@ is answerable, and passes every other rule', () => {
  assertEquals(noAutoReply(yes(), FOUNDER), 'internal');            // the mailbox alone made it internal
  assertEquals(invitationReplyAnswerable(yes(), 'supplier'), true);
  assertEquals(noAutoReply({ ...yes(), to_email: '' }, FOUNDER), null);
  assertEquals(invitationReplyAnswerable(yes({ to_email: 'QuotesDone <supplier@quotesdone.com>' }), 'supplier'), true);
});
Deno.test('anyone who is not a lead writing to supplier@ stays unanswered (the founder\'s warm-up contacts included)', () => {
  for (const rel of [null, undefined, 'customer', 'staff']) assertEquals(invitationReplyAnswerable(yes(), rel), false);
});
Deno.test('a back-office row, a seat-owned row, our own domain or another internal box is never made answerable', () => {
  assertEquals(invitationReplyAnswerable(yes({ owner_role: 'accountant' }), 'supplier'), false);
  assertEquals(invitationReplyAnswerable(yes({ body: '[expense subscription] x' }), 'supplier'), false);
  assertEquals(invitationReplyAnswerable(yes({ from_email: 'someone@quotesdone.com' }), 'supplier'), false);
  assertEquals(invitationReplyAnswerable(yes({ to_email: 'supplier@quotesdone.com, expenses@mail.quotesdone.com' }), 'supplier'), false);
  assertEquals(invitationReplyAnswerable(yes({ to_email: 'docs@quotesdone.com' }), 'supplier'), false);
});
Deno.test('a bounce or an auto-reply to supplier@ is still not answered once the mailbox exception applies', () => {
  assertEquals(noAutoReply({ ...yes({ raw: { auto_submitted: 'auto-replied' } }), to_email: '' }, FOUNDER), 'auto_submitted');
  assertEquals(noAutoReply({ ...yes({ from_email: 'mailer-daemon@glassco.ae' }), to_email: '' }, FOUNDER), 'bounce');
});

Deno.test('an invited supplier who said stop, is suppressed, or is an auto-reply is never answered through supplier@ (review of #1699)', () => {
  const m = (o: Record<string, unknown> = {}) => ({ from_email: 'info@acme-fitout.ae', to_email: INVITATION_MAILBOX, body: 'Yes, please send me the details', ...o });
  assertEquals(invitationReplyAnswerable(m(), 'supplier'), true);                                           // the plain yes still is
  assertEquals(invitationReplyAnswerable(m(), 'supplier', true), false);                                    // in email_suppressions
  assertEquals(invitationReplyAnswerable(m({ body: '[UNSUBSCRIBE REQUEST NOT APPLIED: x. customer_support to review.]\n\nstop' }), 'supplier'), false);
  assertEquals(invitationReplyAnswerable(m({ body: 'stop' }), 'supplier'), false);
  assertEquals(invitationReplyAnswerable(m({ subject: 'Unsubscribe' }), 'supplier'), false);
  assertEquals(invitationReplyAnswerable(m({ subject: 'Automatic reply: Would your company like requests?' }), 'supplier'), false);
  assertEquals(invitationReplyAnswerable(m({ subject: 'Out of Office' }), 'supplier'), false);
  assertEquals(invitationReplyAnswerable(m({ raw: { x_autoreply: 'yes' } }), 'supplier'), false);
  assertEquals(invitationReplyAnswerable(m({ raw: { precedence: 'auto_reply' } }), 'supplier'), false);
  assertEquals(invitationReplyAnswerable(m({ raw: { precedence: 'bulk' } }), 'supplier'), false);
});
