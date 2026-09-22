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
  'Thank you for calling QuotesDone. This number is for WhatsApp messages only. '
  + `Please message us on WhatsApp or visit ${web}.`;
const sayAr = (web: string) =>
  'شكرًا لاتصالكم بـ QuotesDone. هذا الرقم مخصص لرسائل واتساب فقط، '
  + `يُرجى مراسلتنا عبر واتساب أو زيارة موقعنا ${web}.`;

// & < > would break the TwiML; the sentences are ours, but a domain is interpolated, so it is escaped.
const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** UAE caller? Twilio's FromCountry first; the E.164 number is the fallback when it is absent. */
export function inUae(fromCountry: string, from: string): boolean {
  if (String(fromCountry || '').trim().toUpperCase() === 'AE') return true;
  return /^\+?971/.test(String(from || '').replace(/[^0-9+]/g, ''));
}

// Polly.Hala is Twilio's Gulf Arabic neural voice; ar-AE is the locale the founder's market speaks.
export function twiml(uae: boolean): string {
  const web = esc(host(uae ? AE_ORIGIN : CANONICAL_ORIGIN));
  return '<?xml version="1.0" encoding="UTF-8"?>'
    + '<Response>'
    + `<Say language="en-US">${esc(sayEn(web))}</Say>`
    + `<Say language="ar-AE" voice="Polly.Hala">${esc(sayAr(web))}</Say>`
    + '<Hangup/>'
    + '</Response>';
}
