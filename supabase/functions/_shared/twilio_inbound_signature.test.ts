// The URL Twilio signs is the public one, whatever path the edge runtime shows the function.
// Prevents the 10-22 Sep 2026 failure from coming back: every genuine inbound WhatsApp was refused
// "signature mismatch" because the signed URL was rebuilt from req.url, whose path inside the runtime
// is /wa_inbound while Twilio signs /functions/v1/wa_inbound.
//
//   deno test --no-lock --node-modules-dir=auto supabase/functions/wa_inbound/signature.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { createHmac } from 'node:crypto';
import { isOwnNumber, signedUrlCandidates, verifyInboundSignature } from './twilio_inbound_signature.ts';

// Twilio's documented algorithm, implemented independently of the code under test: the full URL, then
// each POST parameter name+value in sorted-name order, HMAC-SHA1 keyed with the auth token, base64.
function twilioSigns(token: string, url: string, params: Record<string, string>): string {
  let data = url;
  for (const k of Object.keys(params).sort()) data += k + params[k];
  return createHmac('sha1', token).update(data, 'utf8').digest('base64');
}

Deno.test("the independent signer reproduces Twilio's published example", () => {
  // Twilio security documentation: token 12345, this URL and these five parameters.
  const p = { CallSid: 'CA1234567890ABCDE', Caller: '+12349013030', Digits: '1234', From: '+12349013030', To: '+18005551212' };
  assertEquals(twilioSigns('12345', 'https://mycompany.com/myapp.php?foo=1&bar=2', p), '0/KCTR6DLpKmkAf8muzZqo1nDgQ=');
});

const TOKEN = '0123456789abcdef0123456789abcdef'; // a test key, not the account's
const BASE = 'https://zzdemoref.supabase.co';
const PUBLIC_URL = BASE + '/functions/v1/wa_inbound';
// A simulated WhatsApp webhook from the reserved fixture block, shaped like the 22 Sep "Hi".
const HELLO = {
  AccountSid: 'ACzzdemo00000000000000000000000000', ApiVersion: '2010-04-01', Body: 'Hi', From: 'whatsapp:+971500000011',
  MessageSid: 'SMzzdemo0000000000000000000000001a', MessageType: 'text', NumMedia: '0', NumSegments: '1',
  ProfileName: 'ZZ DEMO', SmsMessageSid: 'SMzzdemo0000000000000000000000001a', SmsSid: 'SMzzdemo0000000000000000000000001a',
  SmsStatus: 'received', To: 'whatsapp:+12180000000', WaId: '971500000011',
};

Deno.test('stripped runtime path (/wa_inbound): a genuine Twilio signature over the public URL is accepted', async () => {
  const sig = twilioSigns(TOKEN, PUBLIC_URL, HELLO);
  const req = new Request('http://zzdemoref.supabase.co/wa_inbound', { method: 'POST',
    headers: { host: 'zzdemoref.supabase.co', 'x-forwarded-proto': 'https' } });
  const urls = signedUrlCandidates(req.url, req.headers, BASE);
  assertEquals(urls[0], PUBLIC_URL);
  const r = await verifyInboundSignature(TOKEN, urls, HELLO, sig);
  assert(r.valid, r.reason);
  // The pre-fix rebuild (proto + host + runtime pathname) is exactly the URL Twilio never signs.
  assert(twilioSigns(TOKEN, 'https://zzdemoref.supabase.co/wa_inbound', HELLO) !== sig);
});

Deno.test('full runtime path (/functions/v1/wa_inbound): still accepted, and with no SUPABASE_URL', async () => {
  const sig = twilioSigns(TOKEN, PUBLIC_URL, HELLO);
  const req = new Request(PUBLIC_URL, { method: 'POST', headers: { host: 'zzdemoref.supabase.co' } });
  assert((await verifyInboundSignature(TOKEN, signedUrlCandidates(req.url, req.headers, BASE), HELLO, sig)).valid);
  assert((await verifyInboundSignature(TOKEN, signedUrlCandidates(req.url, req.headers, ''), HELLO, sig)).valid);
});

Deno.test('a query string on the webhook URL is part of what Twilio signs', async () => {
  const url = PUBLIC_URL + '?src=wa';
  const sig = twilioSigns(TOKEN, url, HELLO);
  const req = new Request('http://zzdemoref.supabase.co/wa_inbound?src=wa', { method: 'POST' });
  assert((await verifyInboundSignature(TOKEN, signedUrlCandidates(req.url, req.headers, BASE), HELLO, sig)).valid);
});

Deno.test('fails closed: altered body, wrong token, missing header, forged signature', async () => {
  const sig = twilioSigns(TOKEN, PUBLIC_URL, HELLO);
  const urls = signedUrlCandidates('http://zzdemoref.supabase.co/wa_inbound', new Headers(), BASE);
  assert(!(await verifyInboundSignature(TOKEN, urls, { ...HELLO, Body: 'send money' }, sig)).valid);
  assert(!(await verifyInboundSignature(TOKEN, urls, { ...HELLO, From: 'whatsapp:+971500000012' }, sig)).valid);
  assert(!(await verifyInboundSignature('ffffffffffffffffffffffffffffffff', urls, HELLO, sig)).valid);
  assert(!(await verifyInboundSignature(TOKEN, urls, HELLO, null)).valid);
  assert(!(await verifyInboundSignature(TOKEN, urls, HELLO, 'AAAAAAAAAAAAAAAAAAAAAAAAAAA=')).valid);
});

Deno.test('the webhook handler checks the signature over the candidate URLs, not a URL rebuilt from the runtime path', async () => {
  // verifyTwilioSignature is the last function of signature.ts, so its body runs to the end of that file.
  const src = await Deno.readTextFile(new URL('../wa_inbound/signature.ts', import.meta.url));
  const fn = src.slice(src.indexOf('async function verifyTwilioSignature'));
  assert(fn.includes('signedUrlCandidates(req.url'), 'verifyTwilioSignature must build its URLs with signedUrlCandidates');
  assert(fn.includes('verifyInboundSignature('), 'verifyTwilioSignature must compare through verifyInboundSignature');
  assert(!/\.pathname/.test(fn), 'verifyTwilioSignature must not rebuild the signed URL from a pathname');
});

Deno.test('an inbound from our own sender number is an echo', () => {
  assert(isOwnNumber('whatsapp:+12180000000', '+12180000000'));
  assert(isOwnNumber('whatsapp:+12180000000', '12180000000'));
  assert(!isOwnNumber('whatsapp:+971500000011', '+12180000000'));
  assert(!isOwnNumber('whatsapp:+971500000011', ''));
});
