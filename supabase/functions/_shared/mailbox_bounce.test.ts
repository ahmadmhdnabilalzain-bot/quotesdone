import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { permanentlyBouncedAddress } from './mailbox_bounce.ts';

const GMAIL = "Address not found\r\nYour message wasn't delivered to sales@Example-Homes.com because the address couldn't be found, or is unable to receive mail.\r\nThe email account that you tried to reach does not exist.";

Deno.test('the delivery report measured on 29 Oct names the dead address', () => {
  assertEquals(permanentlyBouncedAddress('Mail Delivery Subsystem <mailer-daemon@googlemail.com>', GMAIL), 'sales@example-homes.com');
});

Deno.test('a standard report is read from Final-Recipient', () => {
  assertEquals(permanentlyBouncedAddress('postmaster@outlook.com', 'Final-Recipient: rfc822; a.b@example.ae\nStatus: 5.1.1\n'), 'a.b@example.ae');
});

Deno.test('known-bad controls: a person, a temporary failure and an unnamed address are not bounces', () => {
  assertEquals(permanentlyBouncedAddress('info@example.ae', GMAIL), null);
  assertEquals(permanentlyBouncedAddress('mailer-daemon@googlemail.com', "Your message wasn't delivered to a@example.ae because the mailbox is full."), null);
  assertEquals(permanentlyBouncedAddress('mailer-daemon@googlemail.com', 'Address not found'), null);
});
