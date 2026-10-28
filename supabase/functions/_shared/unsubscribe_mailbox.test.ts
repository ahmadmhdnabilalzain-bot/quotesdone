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
