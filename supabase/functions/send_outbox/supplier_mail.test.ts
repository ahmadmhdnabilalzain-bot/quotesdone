// Recurrence guards for the supplier campaign's send-time rules (21 Sep 2026, customer_support).
//   deno test supabase/functions/send_outbox/supplier_mail.test.ts   (pure; the source-wiring half is
//   scripts/checks/the_supplier_campaign_honours_unsubscribe.test.mjs, because CI runs deno without --allow-read)
import { assert, assertEquals, assertMatch, assertStringIncludes } from 'jsr:@std/assert@1';
import { foldEmail, holdForNoUnsubscribe, plainTextPart } from './supplier_mail.ts';
import { tmpl } from './render.ts';
import { arabicFrame } from './arabic_frame.ts';

const LINK = 'https://quotesdone.com/en/portal?t=00000000-0000-0000-0000-000000000000';
const UNSUB = 'https://x.supabase.co/functions/v1/unsubscribe?e=a%40b.ae&t=abc';
// The shape of templates.email_supplier as measured on 21 Sep 2026: {{BODY}} inside a pre-wrap div,
// the footer (Al Furjan, no licence number since 24 Sep 2026), then {{UNSUB}}.
const WRAPPER = '<!doctype html><html><head></head><body>{{LOGO}}<div dir="auto">{{BODY}}</div>'
  + '<div>{{NAME}}</div><div>{{TITLE}}, QuotesDone</div><div>{{REPLY}}</div><div>QuotesDone Technologies &middot; Al Furjan, Dubai, UAE &middot; TDRA NOL-26-100000665{{UNSUB}}</div></body></html>';

Deno.test('an unsubscribed address with a capital letter is still recognised', () => {
  const suppressed = new Set(['buyer@acme.ae'].map(foldEmail));
  assert(suppressed.has(foldEmail(' Buyer@ACME.ae ')));
});

Deno.test('supplier marketing with no unsubscribe link is held; transactional and non-supplier mail is not', () => {
  assertEquals(holdForNoUnsubscribe(true, false, ''), true);
  assertEquals(holdForNoUnsubscribe(true, false, '  '), true);
  assertEquals(holdForNoUnsubscribe(true, false, UNSUB), false);
  assertEquals(holdForNoUnsubscribe(true, true, ''), false);   // licence/document request
  assertEquals(holdForNoUnsubscribe(false, false, ''), false); // customer/internal
});

Deno.test('the plain-text part carries the body, the licence footer and the unsubscribe URL, per language', () => {
  const en = plainTextPart({ body: 'Dear X,\n\n' + LINK, unsub: UNSUB, ar: false, internal: false });
  assertStringIncludes(en, LINK);
  assertStringIncludes(en, 'Unsubscribe: ' + UNSUB);
  // 24 Sep 2026 (ledger 993): no trade licence number in supplier mail; the address is Al Furjan, Dubai.
  assertStringIncludes(en, 'QuotesDone Technologies · Al Furjan, Dubai, UAE · TDRA NOL-26-100000665');
  assert(!/1633275|[Ll]icen[cs]e No/.test(en), 'no trade licence number in supplier mail');
  assert(!/E-Trader/.test(en), 'the DET issues no "E-Trader" licence to this company');
  const ar = plainTextPart({ body: 'السادة', unsub: UNSUB, ar: true, internal: false });
  assertStringIncludes(ar, 'الفرجان، دبي');
  assert(!/1633275/.test(ar), 'no trade licence number in Arabic supplier mail');
  assert(!/تاجر إلكتروني/.test(ar));
  assertStringIncludes(ar, 'إلغاء الاشتراك: ' + UNSUB);
  // The second way out names the mailbox resend_inbound reads, never "reply" (that went to an unread inbox).
  assertStringIncludes(en, 'or email unsubscribe@mail.quotesdone.com to be removed.');
  assert(!/reply to this email/i.test(en));
  assert(!/Unsubscribe|Dubai, UAE/.test(ar), 'no English frame words in the Arabic text part');
});

Deno.test('the rendered invitation has a clickable portal link and the unsubscribe link, EN and AR', () => {
  const html = tmpl({ body: 'Dear X,\n\nopen your supplier portal here:\n\n' + LINK + '\n\nThanks', logo: '', name: 'N', title: 'T',
    channelEmail: 'supplier@quotesdone.com', unsub: UNSUB, wrapper: WRAPPER, internal: false });
  assertStringIncludes(html, `<a href="${LINK}"`);
  assertStringIncludes(html, `<a href="${UNSUB}"`);
  const ar = arabicFrame(tmpl({ body: 'السادة\n\n' + LINK.replace('/en/', '/ar/'), logo: '', name: 'أحمد الزين', title: 'المؤسس',
    channelEmail: 'supplier@quotesdone.com', unsub: UNSUB, wrapper: WRAPPER, internal: false }));
  assertMatch(ar, /<html dir="rtl" lang="ar"/);
  assertStringIncludes(ar, '>إلغاء الاشتراك</a>');
  assertStringIncludes(ar, 'href="https://quotesdone.com/ar/portal?t=');
  assert(!ar.includes('>Unsubscribe</a>'));
  assertStringIncludes(ar, '<div>المؤسس، QuotesDone</div>');
  assertStringIncludes(ar, 'أو مراسلة unsubscribe@mail.quotesdone.com لإزالة عنوانكم من القائمة');
});

Deno.test('the invitation carries a hidden preheader first in <body>, no licence number, and the Al Furjan address', () => {
  const html = tmpl({ body: 'Dear X,\n\n' + LINK, logo: '', name: 'N', title: 'T', channelEmail: 'supplier@quotesdone.com',
    unsub: UNSUB, wrapper: WRAPPER, internal: false, preheader: 'Free for the first 1,000 suppliers. No commission, ever.' });
  assertMatch(html, /<body><div style="display:none;[^"]*">Free for the first 1,000 suppliers\. No commission, ever\.&zwnj;/);
  assert(!/1633275/.test(html));
  assertStringIncludes(html, 'Al Furjan, Dubai, UAE');
  const ar = arabicFrame(html);
  assertStringIncludes(ar, 'الفرجان، دبي، الإمارات العربية المتحدة');
  assert(!/Al Furjan|Dubai, UAE/.test(ar), 'the Arabic frame translates the whole address');
  // No preheader asked for, none rendered: every other mail is unchanged.
  const plain = tmpl({ body: 'x', logo: '', name: 'N', title: 'T', channelEmail: 'a@b.c', unsub: UNSUB, wrapper: WRAPPER, internal: false });
  assert(!/display:none/.test(plain));
});
