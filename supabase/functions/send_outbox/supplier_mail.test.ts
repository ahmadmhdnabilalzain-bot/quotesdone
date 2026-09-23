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
// the licence footer, then {{UNSUB}}.
const WRAPPER = '<!doctype html><html><head></head><body>{{LOGO}}<div dir="auto">{{BODY}}</div>'
  + '<div>{{NAME}}</div><div>{{TITLE}}, QuotesDone</div><div>{{REPLY}}</div><div>QuotesDone Technologies &middot; Dubai, UAE &middot; DET Trader Licence No. 1633275 &middot; TDRA NOL-26-100000665{{UNSUB}}</div></body></html>';

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
  // 22 Sep 2026 (DL-06): the footer names the licence the company actually holds, and the TDRA permit.
  assertStringIncludes(en, 'DET Trader Licence No. 1633275 · TDRA NOL-26-100000665');
  assert(!/E-Trader/.test(en), 'the DET issues no "E-Trader" licence to this company');
  const ar = plainTextPart({ body: 'السادة', unsub: UNSUB, ar: true, internal: false });
  assertStringIncludes(ar, 'رخصة تاجر رقم 1633275');
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
