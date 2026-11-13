// deno test --no-lock --node-modules-dir=none -A supabase/functions/my_data_pdf/document.test.ts
// A person's data copy is a document he can read (founder ledgers 1669 and 1671, 12 Nov 2026): what the builder turns
// an export into, and what the template then draws. Every party is ZZ DEMO (./fixtures.ts).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { clean, dataCopyBody, dubaiDate, dubaiDateTime, fileName, knownCode, nameEmoji, words } from './document.ts';
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
  for (const h of ['Your company', 'Your quotations', 'WhatsApp conversations', 'Messages in the portal', 'Messages we sent to your e-mail', 'Payments and refunds', 'Marketing preferences', 'Correcting or erasing your data']) assert(t.includes(h), h);
  assert(!t.includes('"Your account"'), 'no empty customer section in a supplier copy');
  for (const line of ['Your company has not sent any quotations.', 'There are no portal messages.', 'There are no payments or refunds.', '2 more e-mail(s)']) assert(t.includes(line), line);
  assert(t.includes('You · 29 July 2026 at 12:27 am'), 'who and when');
  assert(t.includes('QuotesDone · 29 July 2026 at 12:27 am'));
  assert(t.includes('Welcome to QuotesDone [waving hand]'), 'the emoji in words');
  assert(t.includes('مرحبا، نحن مورد حديد في دبي'), 'an Arabic message stays as written');
  assert(t.includes('Free (one of our first suppliers)') && t.includes('A public business directory or website'), 'codes in words');
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
  for (const s of ['حسابكم', 'طلباتكم', 'محادثات واتساب', 'المتحكم في البيانات هو QuotesDone Technologies', 'شكرًا لكم [إبهام مرفوع]', ' · أنتم']) assert(ta.includes(s), s);
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
  assert(sup.includes('Your company documents') && sup.includes('trade-licence.pdf · Trade licence · 1 October 2026'));
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

// Live walk of 13 Nov 2026 (run 272229bd): what the copy said that was not true or not a sentence.
Deno.test('walk 1: an empty e-mail or WhatsApp section says only what is true for a person who was sent sign-in codes', () => {
  const none = { ...SUPPLIER_EXPORT, emails_we_sent: [], emails_total: 0, emails_not_sent: 0, whatsapp: [], whatsapp_total: 0, whatsapp_withheld: 0 };
  for (const lang of ['en', 'ar'] as const) {
    const t = textOf(dataCopyBody({ exp: { ...CUSTOMER_EXPORT, ...none }, lang, role: 'customer' }).blocks);
    assert(!t.includes('We have not sent you any e-mails.') && !t.includes('لم نرسل إليكم أي رسالة إلكترونية.'), 'the false sentence is gone');
    assert(!t.includes('We have no WhatsApp messages with you.') && !t.includes('لا توجد رسائل واتساب بيننا وبينكم.'));
  }
  const t = textOf(dataCopyBody({ exp: none, lang: 'en', role: 'supplier' }).blocks);
  // review of #1993: one plain sentence for the empty e-mail section, which names the codes itself (no second line)
  assert(t.includes('We have no record of any e-mail we sent you, other than one-time codes.'), 'the empty e-mail section is true');
  assert(!t.includes('One-time sign-in and verification codes we e-mailed you are not listed here.'), 'and does not repeat itself');
  assert(t.includes('One-time codes we sent you by WhatsApp or text message are not listed here.'), 'so does the WhatsApp section');
  // and the same notes stand when the sections have content
  const full = textOf(dataCopyBody({ exp: SUPPLIER_EXPORT, lang: 'en', role: 'supplier' }).blocks);
  assert(full.includes('One-time sign-in and verification codes we e-mailed you are not listed here.'));
  assert(full.includes('for example notices about your account, requests, quotations and payments'), 'the list is described by example, not as all it can hold');
  assert(full.includes('One-time codes we sent you by WhatsApp or text message are not listed here.'));
});

Deno.test('walk 3: a supplier copy lists his company documents once, in one place, all of them', () => {
  const exp = { ...SUPPLIER_EXPORT,
    supplier_records: [{ ...SUPPLIER_EXPORT.supplier_records[0], documents: ['trade_licence.pdf'], signed_terms_certificate_at: '2026-11-13T00:31:00+00:00' }],
    company_files: [{ file_name: 'trade_licence.pdf', kind: 'licence', at: '2026-11-13T00:30:00+00:00' }, { file_name: 'company_profile.pdf', kind: 'profile', at: '2026-11-13T00:30:30+00:00' }] };
  const b = dataCopyBody({ exp, lang: 'en', role: 'supplier' }).blocks;
  const t = textOf(b);
  assert(!t.includes('Documents you uploaded'), 'no second, shorter list on the company record');
  assert(t.includes('Certificates and project references you added are in the Documents tab of your portal.'), 'the list says what it leaves out (review of #1993)');
  assert(!t.includes('The files on your company record'), 'never claims to be every file');
  assertEquals((t.match(/trade_licence\.pdf/g) || []).length, 1, 'the licence is named once');
  for (const s of ['Your company documents', 'trade_licence.pdf · Trade licence · 13 November 2026', 'company_profile.pdf · Company profile · 13 November 2026',
    'Signed supplier agreement (certificate) · 13 November 2026']) assert(t.includes(s), s);
});

Deno.test('walk 4: no stored code is printed: WhatsApp updates in words, and every status, kind and source', () => {
  const acct = (o: Record<string, unknown>) => textOf(dataCopyBody({ exp: { ...CUSTOMER_EXPORT,
    customer_accounts: [{ ...CUSTOMER_EXPORT.customer_accounts[0], mobile: '+971500000001', ...o }] }, lang: 'en', role: 'customer' }).blocks);
  assert(acct({ whatsapp_updates: 'same', whatsapp_number: '+971500000001' }).includes('Yes, on the same number as your mobile'));
  assert(acct({ whatsapp_updates: 'other', whatsapp_number: '+971500000009' }).includes('Yes, on +971500000009'));
  assert(acct({ whatsapp_updates: 'none' }).includes('"WhatsApp updates","No"'));
  assert(acct({ whatsapp_updates: null }).includes('"WhatsApp updates","Not answered"'));
  for (const v of ['same', 'other', 'none']) assert(!/"(Same|Other|None)"/.test(acct({ whatsapp_updates: v })), v);
  // every code the database holds today for the fields the copy prints (read 13 Nov 2026), in both languages
  const CODES = ['draft', 'open', 'quoted', 'revealed', 'completed', 'cancelled', 'expired', 'lost', 'held', 'matching', 'submitted', 'withdrawn',
    'accepted', 'declined', 'stale', 'paid', 'pending', 'unpaid', 'refunded', 'succeeded', 'failed', 'requested', 'approved', 'rejected',
    'needs_review', 'exempt', 'active', 'pending_payment', 'other', 'supplier_non_response', 'received', 'cooling_off', 'awaiting_code'];
  for (const lang of ['en', 'ar'] as const) for (const c of CODES) {
    assert(knownCode(lang, c) && !/_/.test(words(lang, c)), `${lang} ${c} -> ${words(lang, c)}`);
  }
  for (const src of ['apify_2026-06', 'uaecompanies', 'uaecsd_xlsx', 'web_scrape', 'yellowpages', 'enriched_v7', 'marketing_sourcing', 'self_registered']) {
    const t = textOf(dataCopyBody({ exp: { ...SUPPLIER_EXPORT, supplier_records: [{ ...SUPPLIER_EXPORT.supplier_records[0], where_we_found_the_listing: src }] }, lang: 'en', role: 'supplier' }).blocks);
    assert(/"Where we found the listing","(A public business directory or website|You registered the company yourself)"/.test(t), src);
  }
});
