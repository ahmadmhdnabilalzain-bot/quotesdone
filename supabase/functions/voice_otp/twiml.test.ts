// A UAE caller hears quotesdone.ae; everyone else hears quotesdone.com.
//
// The founder's TDRA rule of 14 Sep applied to a phone call. Twilio posts FromCountry on every
// voice webhook, so the country is a fact about the call and not a guess — but it is occasionally
// absent, which is why the E.164 number is a second reading of the same thing.
//
//   deno test supabase/functions/voice_otp/twiml.test.ts
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { inUae, twiml } from './twiml.ts';

Deno.test('the caller country decides the domain, by FromCountry or by the number', () => {
  assert(inUae('AE', ''));
  assert(inUae('ae', ''));
  assert(inUae('', '+971509319355'));
  assert(inUae('', 'whatsapp:+971 50 931 9355'), 'punctuation and a scheme prefix must not hide a UAE number');
  assert(!inUae('GB', '+447700900000'));
  assert(!inUae('', '+14155550100'));
  assert(!inUae('', ''), 'unknown caller is not assumed to be in the UAE; .com redirects them itself');
  // The country wins when the two disagree: a UAE roamer calling from a foreign SIM is still here.
  assert(inUae('AE', '+447700900000'));
});

Deno.test('both languages carry the same domain, and only one of the two domains appears', () => {
  const ae = twiml(true);
  assertStringIncludes(ae, 'contact page on quotesdone.ae;');
  assertStringIncludes(ae, 'موقعنا quotesdone.ae،');
  assertEquals(ae.includes('quotesdone.com'), false, 'a UAE caller must not hear the .com host');

  const com = twiml(false);
  assertStringIncludes(com, 'contact page on quotesdone.com;');
  assertStringIncludes(com, 'موقعنا quotesdone.com،');
  assertEquals(com.includes('quotesdone.ae'), false);
});

Deno.test('it is TwiML that hangs up, and it is no longer the 410', () => {
  for (const x of [twiml(true), twiml(false)]) {
    assert(x.startsWith('<?xml version="1.0" encoding="UTF-8"?><Response>'));
    assertStringIncludes(x, '<Say language="en-US" loop="2">');
    assertStringIncludes(x, 'Send a WhatsApp message to this same number');
    assertStringIncludes(x, '<Say language="ar-AE" voice="Polly.Hala" loop="2">');
    assert(x.trimEnd().endsWith('<Hangup/></Response>'));
    assertEquals(x.includes('This service is unavailable'), false);
    // No stray & < > from the interpolated domain — Twilio refuses malformed TwiML outright.
    assertEquals(/&(?!amp;|lt;|gt;)/.test(x), false);
  }
});
