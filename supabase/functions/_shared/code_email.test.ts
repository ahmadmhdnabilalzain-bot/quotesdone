// The one-time code e-mail carries a plain-text part that says what the HTML says (15 Nov 2026, customer_support,
// founder ledger 1699). An HTML-only message is a spam signal; GlockApps placed our mail at Microsoft 0/21 on 10 Nov.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { codeEmail } from './code_email.ts';

for (const purpose of ['signin', 'confirm'] as const) {
  for (const ar of [false, true]) {
    Deno.test(`the ${purpose} code e-mail (${ar ? 'Arabic' : 'English'}) carries a plain-text part with the code`, () => {
      const m = codeEmail(purpose, '483920', ar);
      assert(m.text.includes('483920'), 'the code is in the text part');
      assert(!/https?:|<[a-z]/i.test(m.text), 'the text part has no link and no markup');
      const lead = m.html.match(/<p style="font-size:14px[^>]*>([^<]+)<\/p>/)?.[1];
      assert(lead && m.text.includes(lead), 'the text part says what the HTML says');
      if (ar) assertEquals(m.text.replace(/QuotesDone/g, '').match(/[A-Za-z]/g), null, 'no English in the Arabic text part');
    });
  }
}
