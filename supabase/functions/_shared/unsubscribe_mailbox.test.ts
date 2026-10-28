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

// THE WORDS SUPPLIERS ACTUALLY WRITE (28 Oct 2026, sales_engineer; ledger 1401 audit, scenario S6). Before this change
// only "stop" and "unsubscribe" of these were opt-outs; "Not interested", replayed on production as an invited ZZ DEMO
// lead's reply to the invitation, was stored and not suppressed.
Deno.test('the opt-outs suppliers actually write to an invitation or its reminder are honoured', () => {
  for (const s of ['Not interested', 'not interested.', 'We are not interested, thank you.', "I'm not interested", 'Please remove us from your mailing list.',
    'Remove', 'Please remove', 'remove me', 'Remove our email from your list', 'No thank you', 'No, thanks!', 'Stop sending us emails',
    'Do not contact us again', "Don't email me", 'STOP ALL', 'stopall', 'Cancel', 'End', 'Unsubscribe me please', 'Opt out', 'optout',
    'Re: Not interested', 'غير مهتمين', 'لا، شكراً']) {
    assert(req('supplier@quotesdone.com', 'Re: A question about your work in the UAE', s), s);
  }
});

Deno.test('a sentence that only contains those words is still never an opt-out', () => {
  for (const s of ['Not interested in aluminium, but we do glass partitions.', 'Can you remove the VAT line from the quote?', 'Remove the old licence and use this one',
    'Cancel my previous quotation and use the attached', 'We are interested, please send the requests', 'Yes please', 'End of month works for us',
    'Thanks, no further questions']) {
    assert(!req('supplier@quotesdone.com', 'Re: A question about your work in the UAE', s), s);
  }
});

// ONE VOCABULARY. fn_marketing_files_invite_reply files no handoff for a reply whose first line is one of its stop words;
// every one of them must also be an opt-out here, or the reply is neither handed to the sales engineer nor honoured.
// The list is read from the routine's canonical file (the LAST scripts/sql file in MANIFEST.txt, or a pending one, that
// defines it), so a word added to the SQL without this side fails here.
Deno.test('every stop word fn_marketing_files_invite_reply knows is an opt-out here', () => {
  const root = new URL('../../../', import.meta.url);
  const manifest = Deno.readTextFileSync(new URL('scripts/sql/MANIFEST.txt', root)).split(/\r?\n/).filter((l) => l.endsWith('.sql'));
  const pending = [...Deno.readDirSync(new URL('scripts/sql/pending/', root))].map((e) => 'scripts/sql/' + e.name.replace(/\.txt$/, '.sql'));
  const defines = (f: string) => { try { return /function\s+public\.fn_marketing_files_invite_reply\s*\(/i.test(Deno.readTextFileSync(new URL(f, root))); } catch { return false; } };
  const file = [...pending.filter(defines), ...manifest.filter(defines).reverse()][0];
  assert(file, 'no scripts/sql file defines fn_marketing_files_invite_reply');
  const m = Deno.readTextFileSync(new URL(file, root)).match(/v_first in \(([^)]*)\)/);
  assert(m, `${file}: the stop-word list was not found`);
  const words = [...m[1].matchAll(/'([^']+)'/g)].map((x) => x[1]);
  assert(words.length >= 5, `${file}: only ${words.length} stop words read`);
  for (const w of words) assert(req('supplier@quotesdone.com', 'Re: A question about your work in the UAE', w), `${w} (from ${file}) is a stop reply there and not an opt-out here`);
});
