// Twilio status-callback signatures (22 Sep 2026, customer_support). The oracle is node:crypto's HMAC,
// an implementation independent of the WebCrypto one under test, over the exact string Twilio's
// security page builds: URL, then each POST parameter as name+value in sorted order.
// Run: deno test supabase/functions/_shared/twilio_status.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { createHmac } from 'node:crypto';
import { statusCallbackUrls, twilioSignature, verifyTwilioSignature, verifyTwilioSignatureAny } from './twilio_status.ts';

const TOKEN = '12345';
const URL_ = 'https://project-ref.supabase.co/functions/v1/wa_status';
const PARAMS = { MessageSid: 'SMZZDEMOPROBE000000000000000000001', MessageStatus: 'undelivered', ErrorCode: '63016',
                 AccountSid: 'ACzz', To: 'whatsapp:+971500000099', From: 'whatsapp:+12183166814' };
const oracle = (token: string, url: string, p: Record<string, string>) =>
  createHmac('sha1', token).update(url + Object.keys(p).sort().map((k) => k + p[k]).join('')).digest('base64');

Deno.test('the signature is Twilio\'s scheme, checked against an independent HMAC', async () => {
  assertEquals(await twilioSignature(TOKEN, URL_, PARAMS), oracle(TOKEN, URL_, PARAMS));
  // the security page's own construction string
  const doc = { CallSid: 'CA1234567890ABCDE', Caller: '+14158675310', Digits: '1234', From: '+14158675310', To: '+18005551212' };
  assertEquals(await twilioSignature(TOKEN, 'https://example.com/myapp.php?foo=1&bar=2', doc),
    createHmac('sha1', TOKEN).update('https://example.com/myapp.php?foo=1&bar=2CallSidCA1234567890ABCDECaller+14158675310Digits1234From+14158675310To+18005551212').digest('base64'));
});

Deno.test('a valid signature is accepted', async () => {
  const r = await verifyTwilioSignature(TOKEN, URL_, PARAMS, oracle(TOKEN, URL_, PARAMS));
  assert(r.valid, r.reason);
});

Deno.test('an invalid signature is refused: altered status, other URL, other token', async () => {
  const good = oracle(TOKEN, URL_, PARAMS);
  assert(!(await verifyTwilioSignature(TOKEN, URL_, { ...PARAMS, MessageStatus: 'delivered' }, good)).valid, 'a forged "delivered" must not pass');
  assert(!(await verifyTwilioSignature(TOKEN, URL_ + '?x=1', PARAMS, good)).valid);
  assert(!(await verifyTwilioSignature('54321', URL_, PARAMS, good)).valid);
  assert(!(await verifyTwilioSignature(TOKEN, URL_, PARAMS, good.slice(0, -2) + 'AA')).valid);
});

Deno.test('missing signature or missing token fails closed', async () => {
  assert(!(await verifyTwilioSignature(TOKEN, URL_, PARAMS, null)).valid);
  assert(!(await verifyTwilioSignature(TOKEN, URL_, PARAMS, '')).valid);
  assert(!(await verifyTwilioSignature('', URL_, PARAMS, oracle(TOKEN, URL_, PARAMS))).valid);
  assert(!(await verifyTwilioSignature(undefined, URL_, PARAMS, oracle(TOKEN, URL_, PARAMS))).valid);
});

// R6 (it_engineer, 10 Nov 2026): a send names the region-pinned URL; a message sent before the pin is signed over the old one,
// and its later callbacks (delivered, read) must still verify. Red before: wa_status checked one URL.
Deno.test('a callback verifies over the pinned URL and over the old one; a forgery over neither is refused', async () => {
  const urls = ['https://project-ref.supabase.co/functions/v1/wa_status?forceFunctionRegion=ap-southeast-1', URL_];
  for (const u of urls) {
    const r = await verifyTwilioSignatureAny(TOKEN, urls, PARAMS, oracle(TOKEN, u, PARAMS));
    assert(r.valid && r.url === u, JSON.stringify(r));
  }
  assert(!(await verifyTwilioSignatureAny(TOKEN, urls, PARAMS, oracle(TOKEN, URL_ + '?x=1', PARAMS))).valid);
  assert(!(await verifyTwilioSignatureAny(TOKEN, urls, { ...PARAMS, MessageStatus: 'read' }, oracle(TOKEN, urls[0], PARAMS))).valid);
});

Deno.test('the callback URLs are the pinned one first, then the old one', () => {
  const env = Deno.env.get;
  (Deno.env as unknown as { get: (k: string) => string | undefined }).get = (k) => (k === 'SUPABASE_URL' ? 'https://project-ref.supabase.co' : undefined);
  try {
    assertEquals(statusCallbackUrls(), ['https://project-ref.supabase.co/functions/v1/wa_status?forceFunctionRegion=ap-southeast-1', URL_]);
  } finally { (Deno.env as unknown as { get: typeof env }).get = env; }
});
