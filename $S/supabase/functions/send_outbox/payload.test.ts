// deno test supabase/functions/send_outbox/payload.test.ts
// The supplier invitation, built by the real frame (render.ts, arabic_frame.ts, supplier_mail.ts) and the
// real payload builder, must pass every inbox rule; and each rule must fail on the input it exists for.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { inboxLint, ownDomain, resendPayload } from './payload.ts';
import { tmpl } from './render.ts';
import { arabicFrame } from './arabic_frame.ts';
import { plainTextPart } from './supplier_mail.ts';

const HOSTS = ['quotesdone.com', 'htdblwldjkcgjvmqkbeh.supabase.co'];
const LINK = 'https://quotesdone.com/en/portal?t=00000000-0000-0000-0000-000000000000';
const UNSUB = 'https://quotesdone.com/u/unsubscribe?e=zz-demo%40example.invalid&t=abc';
const PROJECT = 'https://htdblwldjkcgjvmqkbeh.supabase.co';
const BODY_EN = `Dear ZZ DEMO Supplier,\n\nQuotesDone is a new UAE marketplace that connects clients with suppliers. A client describes a job and we send it only to suppliers who can genuinely quote for it.\n\nTo join, open your supplier portal here:\n\n${LINK}\n\nand complete a short company profile.\n\nIf you would prefer not to receive these invitations, simply reply and we will remove you.`;
const BODY_AR = `السادة/ ZZ DEMO المحترمين،\n\nيسرّنا أن ندعوكم للانضمام إلى QuotesDone، المنصة الإماراتية لطلبات عروض الأسعار التي تربط العملاء بالموردين المؤهَّلين.\n\nللتسجيل، يُرجى الدخول إلى بوابة الموردين عبر الرابط التالي:\n\n${LINK}\n\nوفي حال عدم رغبتكم في تلقي مراسلات مماثلة، يكفي الرد على هذه الرسالة.`;

function build(body: string, ar: boolean, subject = 'Invitation: become a founding supplier on QuotesDone') {
  const html0 = tmpl({ body, logo: '', name: ar ? 'أحمد الزين' : 'Ahmad Alzain', title: ar ? 'المؤسس' : 'Founder',
    channelEmail: 'suppliers@mail.quotesdone.com', unsub: UNSUB, internal: false, subject });
  return resendPayload({ from: 'QuotesDone Suppliers <supplier@quotesdone.com>', to: 'zz-demo@example.invalid',
    reply: 'suppliers@mail.quotesdone.com', subject, html: ar ? arabicFrame(html0) : html0,
    text: plainTextPart({ body, unsub: UNSUB, ar, internal: false }), unsub: UNSUB, unsubMailto: 'suppliers@mail.quotesdone.com' });
}
const failing = (m: ReturnType<typeof build>) => inboxLint(m, HOSTS).filter((l) => !l.ok).map((l) => l.rule);

Deno.test('the English invitation passes every inbox rule', () => {
  assertEquals(failing(build(BODY_EN, false)), []);
});

Deno.test('the Arabic invitation passes every inbox rule, right-to-left', () => {
  const m = build(BODY_AR, true, 'دعوة للانضمام إلى الموردين المؤسِّسين في QuotesDone');
  assertEquals(failing(m), []);
  assert(inboxLint(m, HOSTS).some((l) => l.rule === 'Arabic mail is right-to-left' && l.ok));
});

Deno.test('the payload carries one-click List-Unsubscribe and the text part', () => {
  const m = build(BODY_EN, false);
  assertEquals(m.headers?.['List-Unsubscribe-Post'], 'List-Unsubscribe=One-Click');
  assert(m.headers?.['List-Unsubscribe']?.startsWith(`<${UNSUB}>, <mailto:`));
  assert(m.text.includes(LINK) && m.text.includes(UNSUB));
});

Deno.test('each rule fails on the input it exists for', () => {
  assert(failing(build(BODY_EN, false, 'URGENT!! Act now: guaranteed clients')).includes('subject free of filter trigger words'));
  // the live subject's "(free, no commission)" scored 0 at SpamAssassin (mail-tester.com, 22 Sep 2026)
  assert(!failing(build(BODY_EN, false, 'Invitation: become a founding supplier on QuotesDone (free, no commission)'))
    .includes('subject free of filter trigger words'));
  assert(failing(build(BODY_EN.replace(LINK, 'https://bit.ly/abc'), false)).includes('no link shortener or click-tracking redirect'));
  assert(failing(build(BODY_EN.replace(LINK, 'https://quotesdone-offers.example/x'), false)).includes('links and images only on our own hosts'));
  const noText = { ...build(BODY_EN, false), text: '' };
  assert(failing(noText).includes('text/plain alternative present'));
  const noUnsub = { ...build(BODY_EN, false), headers: undefined };
  assert(failing(noUnsub).includes('one-click List-Unsubscribe (RFC 8058)'));
  const noreply = { ...build(BODY_EN, false), reply_to: 'no-reply@quotesdone.com' };
  assert(failing(noreply).includes('Reply-To is a real mailbox'));
  const ltr = build(BODY_AR, true);
  assert(failing({ ...ltr, html: ltr.html.replace(' dir="rtl" lang="ar"', '') }).includes('Arabic mail is right-to-left'));
});

// mail-tester.com, 22 Sep 2026: 9.6/10, the only loss SpamAssassin URI_NOVOWEL from the project host in
// the unsubscribe link and the logo. Replayed here, and the fix (ownDomain + unsubscribe_public_base).
Deno.test('the project host in a link or image is flagged, and ownDomain moves the logo to quotesdone.com', () => {
  const m = build(BODY_EN, false);
  const logo = `<img src="${PROJECT}/storage/v1/object/public/brand/kit/05_Logo_Lockups/horizontal_OnDark_trimmed.png" alt="QuotesDone">`;
  const withProjectHost = { ...m, html: m.html.replace(/(<body[^>]*>)/, '$1' + logo) };
  assert(failing(withProjectHost).includes('no hostname a spam filter reads as random (URI_NOVOWEL)'));
  const moved = { ...withProjectHost, html: ownDomain(withProjectHost.html, PROJECT, 'https://quotesdone.com/m/brand') };
  assertEquals(failing(moved), []);
  assert(moved.html.includes('https://quotesdone.com/m/brand/kit/05_Logo_Lockups/horizontal_OnDark_trimmed.png'));
  assertEquals(ownDomain('x', PROJECT, ''), 'x');
});

Deno.test('a reply to a customer threads: In-Reply-To and References carry the inbound Message-ID, beside List-Unsubscribe', () => {
  const base = { from: 'f', to: 'zz-demo@example.invalid', reply: 'r', subject: 'Re: q', html: 'h', text: 't', unsubMailto: 'u@x' };
  const m = resendPayload({ ...base, unsub: UNSUB, inReplyTo: 'abc@mail.example.invalid' });
  assertEquals(m.headers?.['In-Reply-To'], '<abc@mail.example.invalid>');
  assertEquals(m.headers?.['References'], '<abc@mail.example.invalid>');
  assert(m.headers?.['List-Unsubscribe']);
  assertEquals(resendPayload({ ...base, unsub: '', inReplyTo: '<x@y>' }).headers, { 'In-Reply-To': '<x@y>', 'References': '<x@y>' });
  assertEquals(resendPayload({ ...base, unsub: '' }).headers, undefined);
});
