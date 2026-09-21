// Replays the two faults the 22 Sep 2026 review of PR #804 found. Run: deno test supabase/functions/_shared/suppression_policy.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { blocksTransactional, fromDomainAuthenticated, neverSuppressible, OPT_OUT_TYPES, suppressionStops } from './suppression_policy.ts';

Deno.test('an unsubscribed address still receives a sign-in code; a hard-bounced or complained one does not', () => {
  assert(!blocksTransactional('unsubscribe'));
  assert(blocksTransactional('hard_bounce:permanent'));
  assert(blocksTransactional('spam_complaint'));
  assert(blocksTransactional('blocked: nonexistent qa mailbox pattern'));
});

Deno.test('an unsubscribe stops only the invitation and its reminders; a bounce stops everything', () => {
  assertEquals([...OPT_OUT_TYPES], ['supplier_invite', 'supplier_registration_reminder']);
  for (const t of ['supplier_invite', 'supplier_registration_reminder']) assert(suppressionStops('unsubscribe', t), t);
  for (const t of ['new_inquiry', 'quote_accepted', 'registration_received', 'reveal_no_response_notice', 'nonresponse_charge', 'login_otp']) {
    assert(!suppressionStops('unsubscribe', t), t);
    assert(suppressionStops('hard_bounce:permanent', t), t);
    assert(suppressionStops('spam_complaint', t), t);
  }
});

// The exact header Resend's receiving MTA added to a real inbound mail on 21 Sep 2026 (from our own sender).
const SES_PASS = 'amazonses.com; spf=pass (spfCheck: domain of send.quotesdone.com designates 54.240.14.56 as permitted sender) client-ip=54.240.14.56; envelope-from=0100@send.quotesdone.com; helo=a14-56.smtp-out.amazonses.com; dkim=pass header.i=@quotesdone.com; dkim=pass header.i=@amazonses.com; dmarc=pass header.from=quotesdone.com;';

Deno.test('a forged From is not authenticated; only the receiving server\'s own verdict counts', () => {
  assert(fromDomainAuthenticated(SES_PASS, 'supplier@quotesdone.com'));
  assert(!fromDomainAuthenticated(SES_PASS, 'owner@example.invalid'));                  // passes for another domain only
  assert(!fromDomainAuthenticated(undefined, 'owner@example.invalid'));                 // no header at all
  assert(!fromDomainAuthenticated('amazonses.com; spf=fail; dkim=none; dmarc=fail header.from=example.invalid;', 'owner@example.invalid'));
  assert(!fromDomainAuthenticated('mx.attacker.invalid; dmarc=pass header.from=example.invalid;', 'owner@example.invalid'));  // not SES's
  // a sender-supplied header further down the message never counts: only the first (the receiver's)
  assert(!fromDomainAuthenticated(['amazonses.com; dmarc=fail header.from=example.invalid;', 'amazonses.com; dmarc=pass header.from=example.invalid;'], 'owner@example.invalid'));
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
