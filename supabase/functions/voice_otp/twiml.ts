// What a caller hears, and in which domain. Separated from index.ts so it can be tested without
// starting a server (importing a module that calls Deno.serve binds a port in the test run).
//
// WHICH DOMAIN. A UAE caller is told quotesdone.ae, everyone else quotesdone.com. That is the
// founder's TDRA rule of 14 Sep applied to the one audience an edge function can identify without a
// browser: Twilio posts FromCountry (and the E.164 From) on every voice webhook, so the country is
// a fact about this call, not a guess. It is the same split the printed documents already make
// (_shared/doc_template.ts prints quotesdone.ae). Links in mail and WhatsApp deliberately stay on
// .com because they are not tied to a session; a spoken domain is neither, and an Arabic-speaking
// caller in Dubai hearing ".com" is the case this exists to avoid. An unknown caller gets .com,
// which redirects a UAE visitor to .ae itself.
import { AE_ORIGIN, CANONICAL_ORIGIN } from '../_shared/site_origins.ts';

const host = (origin: string) => origin.replace(/^https?:\/\//, '');

const sayEn = (web: string) =>
  'Thank you for calling QuotesDone. We answer in writing, so nobody picks up on this line. '
  + 'Send a WhatsApp message to this same number and we will reply. '
  + `Or use the contact page on ${web}; every message there is answered.`;
const sayAr = (web: string) =>
  'شكرًا لاتصالكم بـ QuotesDone. نردّ كتابيًا، لذلك لا يجيب أحد على هذا الخط. '
  + 'أرسلوا رسالة واتساب إلى هذا الرقم نفسه وسنرد عليكم. '
  + `أو استخدموا صفحة التواصل في موقعنا ${web}، وكل رسالة تصلنا هناك يُرَد عليها.`;

// & < > would break the TwiML; the sentences are ours, but a domain is interpolated, so it is escaped.
const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** UAE caller? Twilio's FromCountry first; the E.164 number is the fallback when it is absent. */
export function inUae(fromCountry: string, from: string): boolean {
  if (String(fromCountry || '').trim().toUpperCase() === 'AE') return true;
  return /^\+?971/.test(String(from || '').replace(/[^0-9+]/g, ''));
}

// Polly.Hala is Twilio's Gulf Arabic neural voice; ar-AE is the locale the founder's market speaks.
export function twiml(uae: boolean): string {
  // Escaped once, by esc() on the whole sentence below. Escaping the domain here as well was a
  // double-escape: harmless on a hostname with no &<> in it, and wrong the day one has.
  const web = host(uae ? AE_ORIGIN : CANONICAL_ORIGIN);
  return '<?xml version="1.0" encoding="UTF-8"?>'
    + '<Response>'
    + `<Say language="en-US" loop="2">${esc(sayEn(web))}</Say>`
    + `<Say language="ar-AE" voice="Polly.Hala" loop="2">${esc(sayAr(web))}</Say>`
    + '<Hangup/>'
    + '</Response>';
}
