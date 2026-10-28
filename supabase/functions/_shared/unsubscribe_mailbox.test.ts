// Replays the 21 Sep 2026 gap: an unsubscribe sent by email had no reader. Run: deno test supabase/functions/_shared/unsubscribe_mailbox.test.ts
import { assert } from 'jsr:@std/assert@1';
import { isUnsubscribeRequest, UNSUBSCRIBE_MAILBOX } from './unsubscribe_mailbox.ts';

const req = (to: string, subject: string, text = '') => isUnsubscribeRequest({ to, subject, text });

Deno.test('anything sent to the unsubscribe mailbox is a request, whatever it says (List-Unsubscribe mailto)', () => {
  assert(req(UNSUBSCRIBE_MAILBOX, ''));
  assert(req('Unsubscribe@Mail.QuotesDone.com', 'hello'));
});

Deno.test('a reply that is only the request is honoured, in English and Arabic, behind reply prefixes', () => {
  for (const s of ['unsubscribe', 'Re: Unsubscribe', 'RE: remove me!', 'STOP', 'Opt-out', 'رد: إلغاء الاشتراك', 'الغاء الاشتراك']) {
    assert(req('docs@mail.quotesdone.com', s), s);
  }
  assert(req('docs@mail.quotesdone.com', 'Re: licence renewal', '\n\n  Unsubscribe.\n\nSent from my iPhone'));
});

Deno.test('ordinary supplier mail that merely mentions the words is never an unsubscribe', () => {
  assert(!req('docs@mail.quotesdone.com', 'Re: licence renewal', 'Attached. Please do not stop the tender.'));
  assert(!req('docs@mail.quotesdone.com', 'How do I unsubscribe my colleague and add me?'));
  assert(!req('docs@mail.quotesdone.com', 'Trade licence', 'stop by our office tomorrow'));
});

// ── A REPLY TO THE INVITATION THAT ASKS TO STOP (28 Oct 2026, supplier-journey audit run 490a318b) ──────────────────
// The reply as the Microsoft 365 reader hands it in: the supplier's words, then the quoted invitation.
const INVITE = "Hello,\r\n\r\nI'm Ahmad, founder of QuotesDone in Dubai. ... Would your company like to receive aluminium requests when they come in?\r\n\r\nIf this isn't relevant, reply \"stop\" and we won't contact you again.";
const reply = (text: string, subject = 'Re: A question about your aluminium work') =>
  isUnsubscribeRequest({ to: 'supplier@quotesdone.com', subject, text: text + '\r\n\r\nOn Tue, 28 Oct 2026, Ahmad Alzain at QuotesDone wrote:\r\n> ' + INVITE.split('\r\n').join('\r\n> ') });

Deno.test('the measured reply "Please remove me / stop" to the invitation mailbox is a stop', () => {
  assert(reply('Please remove me / stop'));
});

Deno.test('a stop to the invitation, as suppliers write it, in English and Arabic', () => {
  for (const t of ['Stop please', 'STOP.', 'Kindly unsubscribe us, thanks', 'Remove me from your mailing list', 'Please take us off your list.',
    'No thanks', 'No, thank you.', 'Not interested', 'We are not interested, thank you', 'Hi Ahmad,\r\n\r\nPlease remove me from your list.\r\n\r\nThanks\r\nAhmed',
    'Hello,\r\nNot relevant to us.\r\nRegards', 'Thank you for your email.\r\nPlease stop sending us emails.',
    'توقف', 'توقفوا من فضلك', 'لا ترسلوا', 'لا ترسلوا لنا شكرا', 'إلغاء الاشتراك من فضلك', 'الرجاء الإزالة', 'غير مهتمين', 'لسنا مهتمين، شكراً',
    'السلام عليكم\r\nلا تتواصلوا معنا']) {
    assert(reply(t), t);
  }
  assert(reply('', 'Re: Stop'), 'a subject that is only the request');
});

Deno.test('a reply that is not a stop is never one, however it uses the words', () => {
  for (const t of ['Yes, interested', 'Yes please, we would like to receive requests.', 'نعم، مهتمين', 'No, we are interested',
    'Please do not stop the tender', 'We stopped working with aluminium but we do glass, interested', 'Stop by our office tomorrow',
    'Do you charge fees? No commission?', 'Interested. Please remove the old contact and use this email.', 'Hi Ahmad,', '',
    'How do I unsubscribe my colleague and add me?', 'We are interested, not in aluminium but glass']) {
    assert(!reply(t), t);
  }
});

Deno.test('the quoted invitation is never read: its own "reply stop" line does not make a yes into a stop', () => {
  assert(!reply('Yes'));
  assert(!reply('Sure, send the details'));
});

Deno.test('outside the invitation mailbox only the whole-line rule decides, as before', () => {
  assert(!isUnsubscribeRequest({ to: 'docs@mail.quotesdone.com', subject: 'Re: licence', text: 'Please remove me / stop' }));
  assert(!isUnsubscribeRequest({ to: 'info@quotesdone.com', subject: 'Re: your question', text: 'No thanks' }));
  assert(isUnsubscribeRequest({ to: 'info@quotesdone.com', subject: 'Re: your question', text: 'Stop' }));
});
