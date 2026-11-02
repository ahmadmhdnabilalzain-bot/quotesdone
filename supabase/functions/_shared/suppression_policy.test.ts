// Replays the two faults the 22 Sep 2026 review of PR #804 found. Run: deno test supabase/functions/_shared/suppression_policy.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { blocksTransactional, exchangeInternal, fromDomainAuthenticated, neverSuppressible, OPT_OUT_TYPES, senderAuthenticated, suppressionStops } from './suppression_policy.ts';

// Review of #1792: a bounce from our own tenant's Exchange is believed only on the tenant's own stamp, never on the From alone.
Deno.test('only our tenant\'s Exchange, stamped Internal, on the M365 lane, is our own tenant', () => {
  const sys = 'microsoftexchange329e71ec88ae4615bbc36ab6ce41109e@netorgft20811795.onmicrosoft.com';
  assert(exchangeInternal('m365:AAMk1', 'Internal', sys));
  assert(exchangeInternal('m365:AAMk1', 'internal', 'Microsoft Outlook <' + sys + '>'));
  assert(!exchangeInternal('m365:AAMk1', 'Anonymous', sys), 'mail from outside is stamped Anonymous');
  assert(!exchangeInternal('m365:AAMk1', undefined, sys), 'no stamp, no proof');
  assert(!exchangeInternal('re_123', 'Internal', sys), 'only the M365 lane carries the tenant\'s stamp');
  assert(!exchangeInternal('m365:AAMk1', 'Internal', 'postmaster@evil.example'), 'another sender');
});

Deno.test('an unsubscribed address still receives a sign-in code; a hard-bounced or complained one does not', () => {
  assert(!blocksTransactional('unsubscribe'));
  assert(blocksTransactional('hard_bounce:permanent'));
  assert(blocksTransactional('spam_complaint'));
  assert(blocksTransactional('blocked: nonexistent qa mailbox pattern'));
});

Deno.test('an unsubscribe stops only the invitation and its reminders; a bounce stops everything', () => {
  assertEquals([...OPT_OUT_TYPES], ['supplier_invite', 'supplier_invite_nudge', 'supplier_registration_reminder', 'supplier_rfq_widened_invite']);
  // the reminder of an unopened invitation is stopped too: a nudge queued before the "stop" never leaves (ledger 1401 audit S6)
  for (const t of ['supplier_invite', 'supplier_invite_nudge', 'supplier_registration_reminder', 'supplier_rfq_widened_invite']) assert(suppressionStops('unsubscribe', t), t);
  for (const t of ['new_inquiry', 'rfq_quote_reminder', 'rfq_short_of_quotes', 'reveal_outcome_check', 'quote_accepted', 'registration_received', 'reveal_no_response_notice', 'nonresponse_charge', 'login_otp']) {
    assert(!suppressionStops('unsubscribe', t), t);
    assert(suppressionStops('hard_bounce:permanent', t), t);
    assert(suppressionStops('spam_complaint', t), t);
  }
});

// The founder's Outlook "Approve" to the September calendar, 24 Sep 2026 (inbound_messages 162), exactly as
// Resend returned the header: SES's verdict plus Microsoft 365's own internal stamp, as one JSON-encoded array.
const M365_REPLY = JSON.stringify([
  'amazonses.com; spf=pass (spfCheck: domain of quotesdone.com designates 40.107.54.86 as permitted sender) client-ip=40.107.54.86; envelope-from=management@quotesdone.com; helo=DXZP273CU001.outbound.protection.outlook.com; dmarc=pass header.from=quotesdone.com;',
  'dkim=none (message not signed) header.d=none;dmarc=none action=none header.from=quotesdone.com;',
]);

Deno.test("an Outlook reply carrying Microsoft's own second header is authenticated by SES's verdict", () => {
  assert(fromDomainAuthenticated(M365_REPLY, 'management@quotesdone.com'));
  assert(!fromDomainAuthenticated(M365_REPLY, 'owner@example.invalid'));                          // SES passed quotesdone.com only
  const forged = 'amazonses.com; dmarc=pass header.from=example.invalid;';
  const real = 'amazonses.com; spf=fail; dkim=none; dmarc=fail header.from=example.invalid;';
  assert(!fromDomainAuthenticated(JSON.stringify([forged, real, 'x; dmarc=none']), 'owner@example.invalid')); // two SES verdicts, any order
  assert(!fromDomainAuthenticated(JSON.stringify(['mx.attacker.invalid; dmarc=pass header.from=example.invalid;']), 'owner@example.invalid'));
  assert(!fromDomainAuthenticated('["not json', 'management@quotesdone.com'));
  assert(!fromDomainAuthenticated(JSON.stringify([{ v: 'amazonses.com; dmarc=pass header.from=quotesdone.com;' }]), 'management@quotesdone.com'));
});

// The exact header Resend's receiving MTA added to a real inbound mail on 21 Sep 2026 (from our own sender).
const SES_PASS = 'amazonses.com; spf=pass (spfCheck: domain of send.quotesdone.com designates 54.240.14.56 as permitted sender) client-ip=54.240.14.56; envelope-from=0100@send.quotesdone.com; helo=a14-56.smtp-out.amazonses.com; dkim=pass header.i=@quotesdone.com; dkim=pass header.i=@amazonses.com; dmarc=pass header.from=quotesdone.com;';

Deno.test('a forged From is not authenticated; only the receiving server\'s own verdict counts', () => {
  assert(fromDomainAuthenticated(SES_PASS, 'supplier@quotesdone.com'));
  assert(!fromDomainAuthenticated(SES_PASS, 'owner@example.invalid'));                  // passes for another domain only
  assert(!fromDomainAuthenticated(undefined, 'owner@example.invalid'));                 // no header at all
  assert(!fromDomainAuthenticated('amazonses.com; spf=fail; dkim=none; dmarc=fail header.from=example.invalid;', 'owner@example.invalid'));
  assert(!fromDomainAuthenticated('mx.attacker.invalid; dmarc=pass header.from=example.invalid;', 'owner@example.invalid'));  // not SES's
  // a second, sender-supplied header in ANY shape fails closed (re-review, 22 Sep 2026)
  const forged = 'amazonses.com; dmarc=pass header.from=example.invalid;';
  const real = 'amazonses.com; spf=fail; dkim=none; dmarc=fail header.from=example.invalid;';
  assert(!fromDomainAuthenticated([real, forged], 'owner@example.invalid'));                       // as array[2]
  assert(!fromDomainAuthenticated(JSON.stringify([real, forged]), 'owner@example.invalid'));       // as Resend returns a repeated header
  assert(!fromDomainAuthenticated(real + ' ' + forged, 'owner@example.invalid'));                  // joined into one string
  assert(!fromDomainAuthenticated(real + '\r\nAuthentication-Results: ' + forged, 'owner@example.invalid'));
  assert(!fromDomainAuthenticated([real + forged], 'owner@example.invalid'));                      // first element carries an injected block
  assert(!fromDomainAuthenticated('amazonses.com; spf=fail (dmarc=pass header.from=example.invalid) ;', 'owner@example.invalid')); // inside a comment
  // the genuine single SES header still authenticates, including the SPF clause SES writes after client-ip
  assert(fromDomainAuthenticated('amazonses.com; spf=pass (spfCheck: x) client-ip=1.2.3.4; envelope-from=b@example.invalid; helo=h; dkim=none; dmarc=none header.from=example.invalid;', 'owner@example.invalid'));
  assert(fromDomainAuthenticated('amazonses.com; spf=none; dkim=pass header.i=@mail.example.invalid; dmarc=none header.from=example.invalid;', 'owner@example.invalid'));
});

Deno.test('our own domains and the admin addresses can never be suppressed by an email', () => {
  assert(neverSuppressible('management@quotesdone.com', []));
  assert(neverSuppressible('Someone@Mail.QuotesDone.com', []));
  assert(neverSuppressible('x@quotesdone.ae', []));
  assert(neverSuppressible('zz.demo.founder@example.invalid', ['ZZ.Demo.Founder@example.invalid']));
  assert(!neverSuppressible('zz.demo.supplier@example.invalid', ['zz.demo.founder@example.invalid']));
  assert(!neverSuppressible('a@notquotesdone.com', []));
});

Deno.test('senderAuthenticated reads the lane: EOP for an m365 handover, SES for the rest, never the other way (review of #1699)', () => {
  const eop = 'spf=pass (sender IP is 209.85.128.41) smtp.mailfrom=supplier.ae; dkim=pass (signature was verified) header.d=supplier.ae;dmarc=pass action=none header.from=supplier.ae;compauth=pass reason=100';
  const eopFail = 'spf=fail (sender IP is 203.0.113.9) smtp.mailfrom=supplier.ae; dkim=none (message not signed) header.d=none;dmarc=fail action=quarantine header.from=supplier.ae;compauth=fail reason=000';
  const ses = 'amazonses.com; spf=pass (spfCheck) envelope-from=b@supplier.ae; dkim=pass header.i=@supplier.ae; dmarc=pass header.from=supplier.ae;';
  assert(senderAuthenticated('m365:AAMk1', eop, 'info@supplier.ae'));
  assert(!senderAuthenticated('m365:AAMk1', eopFail, 'info@supplier.ae'));        // a spoofed From fails EOP's DMARC
  assert(!senderAuthenticated('m365:AAMk1', eop, 'info@other.ae'));              // EOP passed another domain
  assert(!senderAuthenticated('m365:AAMk1', ses, 'info@supplier.ae'));           // an SES verdict on the m365 lane is not EOP's
  assert(senderAuthenticated('re_123', ses, 'info@supplier.ae'));
  assert(!senderAuthenticated('re_123', eop, 'info@supplier.ae'));               // an EOP-shaped header on the SES lane is refused
  assert(!senderAuthenticated(null, eop, 'info@supplier.ae'));
});
