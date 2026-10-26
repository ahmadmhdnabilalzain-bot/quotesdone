// prevented by: the supplier invitation ended "We look forward to welcoming you." with nothing a supplier could
// answer (marketing, 24 Sep 2026). Renders the invitation the way send_outbox does and fails if it stops ending
// with one question, after the portal link and before the signature, footer and unsubscribe line.
//   deno test supabase/functions/send_outbox/invitation_copy.test.ts   (pure: no network, no file reads)
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { endsWithOneQuestion, holdArabicInvitation, INVITE_REPLY_QUESTION, invitationCopyLint, withReplyQuestion } from './invitation_copy.ts';
import { tmpl } from './render.ts';
import { plainTextPart } from './supplier_mail.ts';

const LINK = 'https://quotesdone.com/en/portal?t=00000000-0000-0000-0000-000000000000';
const UNSUB = 'https://x.supabase.co/functions/v1/unsubscribe?e=a%40b.ae&t=abc';
// The live closing of app_secrets.invite_body, read 24 Sep 2026 (before the question).
const OLD = 'Dear ZZ DEMO Supplier,\n\nTo join, open your supplier portal here:\n\n' + LINK + '\n\nand complete a short company profile.\n\n'
  + 'We will never ask for payment or passwords by email. If you would prefer not to receive these invitations, use the unsubscribe '
  + 'link at the foot of this email and we will not write again.\n\nWe look forward to welcoming you.';
const WRAPPER = '<!doctype html><html><head></head><body>{{LOGO}}<div dir="auto">{{BODY}}</div>'
  + '<div>{{NAME}}</div><div>{{TITLE}}, QuotesDone</div><div>{{REPLY}}</div><div>QuotesDone Technologies &middot; Al Furjan, Dubai, UAE &middot; TDRA NOL-26-100000665{{UNSUB}}</div></body></html>';
const SUBJECT = 'Invitation: become a founding supplier on QuotesDone (free, no commission)';
const PRE = 'Free for the first 1,000 suppliers, permanently. No commission, ever. Register in minutes.';

Deno.test('the old closing is not a question, and the rules say so', () => {
  assertEquals(endsWithOneQuestion(OLD), false);
  const lint = invitationCopyLint({ lang: 'en', subject: SUBJECT, body: OLD, preheader: PRE, link: LINK });
  assert(lint.some((r) => !r.ok && /one question/.test(r.rule)));
});

Deno.test('the rendered invitation ends with one question, after the link and before the footer and unsubscribe', () => {
  const body = withReplyQuestion(OLD);
  assert(body.endsWith('\n\n' + INVITE_REPLY_QUESTION));
  assertEquals(withReplyQuestion(body), body, 'appending is idempotent');
  for (const r of invitationCopyLint({ lang: 'en', subject: SUBJECT, body, preheader: PRE, link: LINK })) assert(r.ok, `${r.rule}: ${r.detail}`);
  const html = tmpl({ body, logo: '', name: 'Ahmad Alzain', title: 'Founder', channelEmail: 'suppliers@mail.quotesdone.com', unsub: UNSUB,
    wrapper: WRAPPER, internal: false, preheader: PRE });
  const at = (s: string) => html.indexOf(s);
  const q = at(INVITE_REPLY_QUESTION);
  assert(q > 0, 'the question is not in the rendered html');
  assert(at(`<a href="${LINK}"`) < q, 'the question sits above the portal link');
  assert(q < at('<div>Ahmad Alzain</div>') && q < at('Al Furjan, Dubai, UAE') && q < at(`<a href="${UNSUB}"`), 'the question is below the footer');
  // Outlook: line breaks stay explicit <br> (#953), so the question is its own paragraph there too.
  assert(html.includes('We look forward to welcoming you.<br><br>' + INVITE_REPLY_QUESTION));
  const text = plainTextPart({ body, unsub: UNSUB, ar: false, internal: false });
  assert(text.includes(INVITE_REPLY_QUESTION + '\n\n--\n\n'), 'text part: the question is not the last line before the footer');
  assert(text.trimEnd().endsWith('to be removed.'), 'text part: the unsubscribe line is no longer last');
});

Deno.test('the rules refuse the word AI, Arabic copy, and a closing with two sentences', () => {
  const body = withReplyQuestion(OLD);
  assert(!invitationCopyLint({ lang: 'en', subject: 'Our AI finds you work', body, preheader: PRE, link: LINK })[1].ok);
  assert(!invitationCopyLint({ lang: 'en', subject: SUBJECT, body, preheader: 'Smart matching, ai powered', link: LINK })[1].ok);
  assert(invitationCopyLint({ lang: 'en', subject: 'Maintain your fleet', body, preheader: PRE, link: LINK })[1].ok, 'a word containing "ai" is not the word');
  assert(!invitationCopyLint({ lang: 'ar', subject: SUBJECT, body, preheader: PRE, link: LINK })[0].ok);
  assert(!invitationCopyLint({ lang: 'en', subject: 'دعوة', body, preheader: PRE, link: LINK })[0].ok);
  assertEquals(endsWithOneQuestion('x\n\nThanks. Which trades do you cover?'), false);
  assertEquals(endsWithOneQuestion('x\n\nWhich trades? And which emirates?'), false);
  assertEquals(endsWithOneQuestion('x\n\nWhich trades do you cover?'), true);
});

Deno.test('an abbreviation is not a sentence break, so a closing question that uses one is not given a second', () => {
  const q = 'Which trades do you cover, e.g. MEP, joinery or L.L.C. fit-out works?';
  assert(endsWithOneQuestion('x\n\n' + q));
  assert(endsWithOneQuestion('x\n\nDoes Acme Co. cover HVAC, etc. in Dubai?'));
  assertEquals(withReplyQuestion('x\n\n' + q), 'x\n\n' + q, 'a rewritten closing question got the fallback appended');
  assertEquals(endsWithOneQuestion('x\n\nThanks. Which trades do you cover?'), false, 'a real sentence break still counts');
});

Deno.test('a supplier invitation queued in Arabic is held, never sent; nothing else is', () => {
  assertEquals(holdArabicInvitation('supplier_invite', 'ar'), true);
  assertEquals(holdArabicInvitation('supplier_invite_seed', 'AR'), true);
  assertEquals(holdArabicInvitation('supplier_invite', 'en'), false);
  assertEquals(holdArabicInvitation('supplier_invite', null), false);
  assertEquals(holdArabicInvitation('supplier_rfq_widened_invite', 'ar'), false, 'without supplierSide, only invitations are judged');
  // 28 Sep 2026 (founder): every supplier-bound row is English, so any supplier-side row in Arabic is held.
  assertEquals(holdArabicInvitation('supplier_approved', 'ar', true), true);
  assertEquals(holdArabicInvitation('supplier_approved', 'en', true), false);
  assertEquals(holdArabicInvitation('customer_quote_ready', 'ar', false), false, 'a customer keeps their language');
});

// 5 Oct 2026: the LIVE invite_body offered "free ... until" a dated day, then a subscription from the next one
// (founder ruling 6 Sep: no dates). The exact old bullet must fail; the ruled wording must pass.
Deno.test('no date in the invitation copy: the old dated offer fails, the ruled offer passes', async () => {
  const { invitationCopyLint } = await import('./invitation_copy.ts');
  const link = 'https://quotesdone.com/en/portal?t=00000000-0000-0000-0000-000000000000';
  const q = 'Which trades does your company cover?';
  const lint = (offer: string) => invitationCopyLint({ lang: 'en', subject: 'x', preheader: '', link,
    body: `Dear ZZ DEMO Supplier,\n\n${offer}\n\n${link}\n\n${q}` }).find((r) => r.rule.startsWith('no date'))!;
  if (lint('- Registration is free for all suppliers until 31 July 2027. From 1 August 2027 an annual subscription of AED 1,000 applies.').ok) throw new Error('dated offer passed');
  for (const d of ['until 2027', 'from August 2027', 'ends 31 July']) if (lint('Free ' + d + '.').ok) throw new Error('passed: ' + d);
  if (!lint('- Registration is free permanently for the first 1,000 supplier registrations. From the 1,001st registration an annual subscription of AED 1,000 applies.').ok) throw new Error('ruled offer failed');
});
