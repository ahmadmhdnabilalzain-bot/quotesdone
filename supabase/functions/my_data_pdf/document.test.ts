// deno test --no-lock --node-modules-dir=none -A supabase/functions/my_data_pdf/document.test.ts
// A person's data copy is a document he can read (founder ledgers 1669 and 1671, 12 Nov 2026): what the builder turns
// an export into, and what the template then draws. Every party is ZZ DEMO (./fixtures.ts).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { clean, dataCopyBody, dubaiDate, dubaiDateTime, fileName, nameEmoji, words } from './document.ts';
import { ARABIC_CUSTOMER_EXPORT, CUSTOMER_EXPORT, SUPPLIER_EXPORT } from './fixtures.ts';
import { renderPdf } from '../pdf_native/render.ts';
import { pdfPages } from '../_shared/pdf_text_positions.ts';

const FONTS = new URL('../pdf_native/fixtures/brand/', import.meta.url);
const fetchBytes = async (p: string) => (/\.ttf$/.test(p) ? await Deno.readFile(new URL(p, FONTS)) : null);
// deno-lint-ignore no-explicit-any
const textOf = (blocks: any[]) => JSON.stringify(blocks.flatMap((b) => [b.text, b.label, b.title, b.pairs]).filter((x) => x != null));

Deno.test('Dubai time is written out, and 20:27 UTC on 28 July is 00:27 on 29 July (UTC+4, no daylight saving)', () => {
  assertEquals(dubaiDateTime('2026-07-28T20:27:43.938602+00:00', 'en'), '29 July 2026 at 12:27 am');
  assertEquals(dubaiDateTime('2026-07-28T19:59:00Z', 'en'), '28 July 2026 at 11:59 pm');
  // January and July read the same offset: Dubai keeps no daylight saving
  assertEquals(dubaiDateTime('2026-01-15T20:00:00Z', 'en'), '16 January 2026 at 12:00 am');
  assert(dubaiDateTime('2026-07-28T20:27:43Z', 'ar').startsWith('29 يوليو 2026'), dubaiDateTime('2026-07-28T20:27:43Z', 'ar'));
  assertEquals(dubaiDate('2027-06-24', 'en'), '24 June 2027', 'a bare date is a calendar day, never shifted');
  assertEquals(dubaiDateTime(null, 'en'), '');
});

Deno.test('line breaks are real, an escaped \\n is a line break too, and emoji are named in words', () => {
  assertEquals(clean('a\\nb\r\nc', 'en'), 'a\nb\nc');
  assertEquals(nameEmoji('Welcome 👋', 'en'), 'Welcome [waving hand]');
  assertEquals(nameEmoji('شكرًا 👍', 'ar'), 'شكرًا [إبهام مرفوع]');
  assertEquals(nameEmoji('❤️ and 🦄', 'en'), '[heart] and [emoji]');
  assertEquals(nameEmoji('Copyright © 2026', 'en'), 'Copyright © 2026', 'text symbols are not emoji');
  assertEquals(words('en', 'supplier_non_response'), 'the supplier did not respond');
  assertEquals(words('en', 'some_new_state'), 'Some new state', 'an unknown code is words, never a key');
  assert(/^QuotesDone-my-data-\d{4}-\d{2}-\d{2}\.pdf$/.test(fileName()));
});

Deno.test('a supplier copy: his company, WhatsApp with who said what, empty sections in one line, no key, null, [] or ISO time', () => {
  const b = dataCopyBody({ exp: SUPPLIER_EXPORT, lang: 'ar', role: 'supplier' });
  assertEquals(b.lang, 'en', 'a supplier is written to in English whatever the portal language');
  const t = textOf(b.blocks);
  for (const h of ['Your company', 'Your quotations', 'Messages on WhatsApp', 'Messages in the portal', 'E-mails we sent you', 'Payments and refunds', 'Marketing preferences', 'Correcting or erasing your data']) assert(t.includes(h), h);
  assert(!t.includes('"Your account"'), 'no empty customer section in a supplier copy');
  for (const line of ['Your company has not sent any quotations.', 'There are no portal messages.', 'There are no payments or refunds.', '2 more e-mail(s)']) assert(t.includes(line), line);
  assert(t.includes('You · 29 July 2026 at 12:27 am'), 'who and when');
  assert(t.includes('QuotesDone · 29 July 2026 at 12:27 am'));
  assert(t.includes('Welcome to QuotesDone [waving hand]'), 'the emoji in words');
  assert(t.includes('مرحبا، نحن مورد حديد في دبي'), 'an Arabic message stays as written');
  assert(t.includes('Free (one of our first suppliers)') && t.includes('Google maps'), 'codes in words');
  assert(t.includes('You have not opted out of marketing e-mails.'), 'opt-out said in words');
  const email = b.blocks.find((x) => x.lines && String(x.text).startsWith('Thank you for your reply.'));
  assert(email && String(email.text).includes('\n\nTo register') && email.lines, 'the e-mail keeps its paragraphs');
  for (const bad of [/\bnull\b/, /\[\]/, /\d{4}-\d{2}-\d{2}T\d{2}/, /\\\\n/, /\b(opt_out|generated_at|supplier_records|emails_we_sent|registered_by_you|company_name)\b/]) {
    assert(!bad.test(t), `raw data on the page: ${bad}`);
  }
});

Deno.test('a supplier copy never prints the customer\'s payment, even from the routine as it was before 12 Nov 2026', () => {
  const old = { ...SUPPLIER_EXPORT, reveals: undefined, transactions: [{ id: 'zz', revealed_at: '2026-10-08T12:00:00Z', customer_id: 'zz-cust', total_charged: 1155,
    payment_ref: 'pi_zz', stripe_invoice_hosted_url: 'https://example.invalid/zz-invoice', stripe_invoice_number: 'ZZ-1', ack_token: 'tok' }],
    refunds: [{ customer_id: 'zz-cust', amount_fils: 115500, stripe_receipt_url: 'https://example.invalid/zz-receipt', decided_by: 'staff', reason_code: 'supplier_non_response', requested_at: '2026-10-20T08:00:00Z' }] };
  const t = textOf(dataCopyBody({ exp: old, lang: 'en', role: 'supplier' }).blocks);
  assert(t.includes('On 8 October 2026, a customer revealed your quotation'), t);
  assert(t.includes('refunded to the customer (the supplier did not respond)'));
  for (const leak of ['1,155', 'zz-invoice', 'zz-receipt', 'pi_zz', 'ZZ-1', 'tok', 'staff', 'zz-cust']) assert(!t.includes(leak), `leaked: ${leak}`);
});

Deno.test('a customer copy: requests, his own payment and invoice, portal messages; an Arabic customer reads Arabic', () => {
  const en = dataCopyBody({ exp: CUSTOMER_EXPORT, lang: 'en', role: 'customer' });
  const t = textOf(en.blocks);
  for (const s of ['Your account', 'Your requests', 'Request 1042: Structural steel', 'AED 1,155.00', 'Open your invoice', 'The supplier · 8 October 2026 at 5:00 pm',
    'Thank you [folded hands]\\n(A file was attached.)', 'You opted out of marketing e-mails on 1 November 2026.', 'You agreed to receive marketing messages on 15 September 2026.']) assert(t.includes(s), s);
  assert(!t.includes('Your quotations') && !t.includes('Your company'), 'no empty supplier sections in a customer copy');
  const ar = dataCopyBody({ exp: ARABIC_CUSTOMER_EXPORT, lang: 'ar', role: 'customer' });
  assertEquals(ar.lang, 'ar');
  const ta = textOf(ar.blocks);
  for (const s of ['حسابكم', 'طلباتكم', 'رسائل واتساب', 'المتحكم في البيانات هو QuotesDone Technologies', 'شكرًا لكم [إبهام مرفوع]', ' · أنتم']) assert(ta.includes(s), s);
});

Deno.test('the template draws it: letterhead and footer on every page, page x of y, nothing dropped, Arabic too', async () => {
  for (const [exp, lang, role] of [[SUPPLIER_EXPORT, 'en', 'supplier'], [CUSTOMER_EXPORT, 'en', 'customer'], [ARABIC_CUSTOMER_EXPORT, 'ar', 'customer']] as const) {
    // a long WhatsApp history, so the copy runs over several pages
    const long = { ...exp, whatsapp: Array.from({ length: 40 }, (_, i) => ({ at: new Date(Date.UTC(2026, 9, 1, 8, i)).toISOString(), received: 'Message ' + (i + 1) + '\nsecond line', replied: 'Reply ' + (i + 1) })) };
    const body = dataCopyBody({ exp: long, lang, role });
    const r = await renderPdf(body, { fetchBytes });
    assert(r.ok, JSON.stringify((r as { body?: unknown }).body));
    if (!r.ok) return;
    assertEquals(r.meta.glyphs_dropped, 0, `dropped: ${r.meta.glyphs_dropped_sample}`);
    const pages = await pdfPages(r.bytes);
    assert(pages.length >= 3, `${pages.length} page(s)`);
    pages.forEach((p, i) => {
      const s = p.runs.map((x) => x.text).join(' ');
      assert(s.includes('1633275'), `page ${i + 1} has no legal footer`);
      assert(lang === 'ar' ? /صفحة|1/.test(s) : s.includes(`Page ${i + 1} of ${pages.length}`), `page ${i + 1} has no page number`);
    });
    const all = pages.flatMap((p) => p.runs.map((x) => x.text)).join(' ');
    assert(all.includes('Reply 40'), 'the last message reached the PDF');
    assert(!/\bnull\b|\[\]|\d{4}-\d{2}-\d{2}T/.test(all), 'raw data in the PDF');
  }
});

Deno.test('what the review of #1986 asked the copy to say: withheld and capped history, undelivered messages, files, requests', () => {
  const sup = textOf(dataCopyBody({ exp: SUPPLIER_EXPORT, lang: 'en', role: 'supplier' }).blocks);
  assert(sup.includes('1 of your numbers is also verified on another account, so its messages are not in this copy.'), 'shared number said in one line');
  assert(sup.includes('Your company documents') && sup.includes('trade-licence.pdf · 1 October 2026'));
  assert(sup.includes('Your privacy requests') && sup.includes('A copy of your data, asked on 1 November 2026: Completed.'));
  const cus = textOf(dataCopyBody({ exp: CUSTOMER_EXPORT, lang: 'en', role: 'customer' }).blocks);
  assert(cus.includes('The 1 most recent of 640 are shown. To receive the rest, write to management@quotesdone.com.'));
  assert(cus.includes('My number is in the file.\\n(Not delivered.)'), 'his own undelivered message is kept, marked');
  assert(cus.includes('ground-floor-plan.pdf · 5 October 2026 · Request 1042'));
  assert(cus.includes('You have not made any privacy requests before this one.'));
  // another person's undelivered message never reaches the reader
  const other = { ...CUSTOMER_EXPORT, portal_chat: [{ at: '2026-10-08T13:00:00Z', from: 'supplier', text: 'call me on 050', delivered: false }] };
  assert(!textOf(dataCopyBody({ exp: other, lang: 'en', role: 'customer' }).blocks).includes('call me on 050'));
});
