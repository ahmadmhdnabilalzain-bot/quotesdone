import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { permanentlyBouncedAddress } from './mailbox_bounce.ts';

const GMAIL = "Address not found\r\nYour message wasn't delivered to sales@Example-Homes.com because the address couldn't be found, or is unable to receive mail.\r\nThe email account that you tried to reach does not exist.";

Deno.test('the delivery report measured on 29 Oct names the dead address', () => {
  assertEquals(permanentlyBouncedAddress('Mail Delivery Subsystem <mailer-daemon@googlemail.com>', GMAIL), 'sales@example-homes.com');
});

Deno.test('a standard report is read from Final-Recipient', () => {
  assertEquals(permanentlyBouncedAddress('postmaster@outlook.com', 'Final-Recipient: rfc822; a.b@example.ae\nStatus: 5.1.1\n'), 'a.b@example.ae');
});

const MS = 'MicrosoftExchange329e71ec88ae4615bbc36ab6ce41109e@NETORGFT20811795.onmicrosoft.com';

Deno.test('Microsoft report wording names the dead address', () => {
  assertEquals(permanentlyBouncedAddress(MS, "Your message to Sales@Example.ae couldn't be delivered. sales wasn't found at example.ae."), 'sales@example.ae');
  assertEquals(permanentlyBouncedAddress(MS, "Your message to a@example.ae couldn’t be delivered. a wasn’t found at example.ae."), 'a@example.ae');
  assertEquals(permanentlyBouncedAddress(MS, "Delivery has failed to these recipients or groups:\r\n\r\nb@dead.example (b@dead.example)\r\nThe Domain Name System (DNS) reported that the recipient's domain does not exist."), 'b@dead.example');
});

Deno.test('a refused connection is permanent only when the report says repeated attempts failed', () => {
  const refused = 'Delivery has failed to these recipients or groups:\n\nc@example.ae (c@example.ae)\nThe recipient\'s email system refused the connection.';
  assertEquals(permanentlyBouncedAddress(MS, refused), null);
  assertEquals(permanentlyBouncedAddress(MS, refused + ' Repeated attempts to deliver the message failed.'), 'c@example.ae');
});

Deno.test('known-bad Microsoft controls: a person using the wording, a full mailbox, a policy block, a bare header', () => {
  assertEquals(permanentlyBouncedAddress('sales@example.ae', "Your message to a@example.ae couldn't be delivered. a wasn't found at example.ae."), null);
  assertEquals(permanentlyBouncedAddress(MS, "Your message to a@example.ae couldn't be delivered. The mailbox is full."), null);
  assertEquals(permanentlyBouncedAddress(MS, "Your message to a@example.ae couldn't be delivered. It was blocked by policy (5.7.1)."), null);
  assertEquals(permanentlyBouncedAddress(MS, 'Delivery has failed to these recipients or groups: a@example.ae (a@example.ae)'), null);
  assertEquals(permanentlyBouncedAddress(MS, "a wasn't found at example.ae."), null);
});

Deno.test('known-bad controls: a person, a temporary failure and an unnamed address are not bounces', () => {
  assertEquals(permanentlyBouncedAddress('info@example.ae', GMAIL), null);
  assertEquals(permanentlyBouncedAddress('mailer-daemon@googlemail.com', "Your message wasn't delivered to a@example.ae because the mailbox is full."), null);
  assertEquals(permanentlyBouncedAddress('mailer-daemon@googlemail.com', 'Address not found'), null);
});
