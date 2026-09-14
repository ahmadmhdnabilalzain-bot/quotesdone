import { assert, assertEquals } from 'jsr:@std/assert@1';
import { askedPatch, choosePatch, fixtureCode, isFixtureIdentity, parseChoiceOpt, sendWhatsAppFirst, verifiedPatch, whatsappState, whatsappUnavailable } from './whatsapp_choice.ts';

const NOW = '2026-09-14T10:00:00.000Z';

// Founder, 14 Sep 2026: "for suppliers whatsapp, if they said they are using a different number from the
// normal calling number and they mentioned it, then an otp verification is needed. and that applies to
// customer sign up as well." customers and leads carry the same four columns and kyc applies the same
// patch to whichever the session is, so one proof covers both parties.
Deno.test('a different number is stored only by a verified code, for customers and suppliers alike', () => {
  const now = '2026-09-14T12:00:00.000Z';
  // Choosing cannot name a different number: only same and none are choosable.
  assertEquals(parseChoiceOpt('other'), null);
  // Asking, and sending a code, write no number at all.
  const asked = askedPatch(now);
  assert(!('whatsapp_phone' in asked) && !('whatsapp_opt' in asked), 'sending a code must not store the entered number or the choice');
  // 'same' can only store the VERIFIED mobile; without one there is no patch.
  assertEquals(choosePatch('same', null, now), null);
  const same = choosePatch('same', '+971500000081', now)!;
  assertEquals(same.whatsapp_phone, '+971500000081');
  // The only patch that stores a different number is the one written after the code was approved,
  // and it stores the verification time with it.
  const v = verifiedPatch('+971500000083', now);
  assertEquals([v.whatsapp_phone, v.whatsapp_opt, v.whatsapp_verified_at], ['+971500000083', 'other', now]);
});

Deno.test('only same and none are choosable; other comes from a verified code', () => {
  assertEquals(parseChoiceOpt('same'), 'same');
  assertEquals(parseChoiceOpt('none'), 'none');
  assertEquals(parseChoiceOpt('other'), null);
  assertEquals(parseChoiceOpt(''), null);
  assertEquals(parseChoiceOpt(undefined), null);
});

Deno.test('same writes the verified mobile, verified now, opted in', () => {
  assertEquals(choosePatch('same', '+971501234567', NOW), { whatsapp_opt: 'same', whatsapp_phone: '+971501234567', whatsapp_verified_at: NOW, whatsapp_asked_at: NOW });
});

Deno.test('same without a verified mobile produces no patch', () => {
  assertEquals(choosePatch('same', null, NOW), null);
  assertEquals(choosePatch('same', '', NOW), null);
});

Deno.test('none clears the number and opts out', () => {
  assertEquals(choosePatch('none', '+971501234567', NOW), { whatsapp_opt: 'none', whatsapp_phone: null, whatsapp_verified_at: null, whatsapp_asked_at: NOW });
});

Deno.test('every patch that sets a phone also sets verified_at', () => {
  for (const p of [choosePatch('same', '+971501234567', NOW)!, verifiedPatch('+971559999999', NOW)]) {
    assert(p.whatsapp_phone && p.whatsapp_verified_at === NOW);
  }
  assertEquals(verifiedPatch('+971559999999', NOW).whatsapp_opt, 'other');
  assertEquals(askedPatch(NOW), { whatsapp_asked_at: NOW });
});

Deno.test('refused: only the template / sender refusals, never fraud, throttle or a bad number', () => {
  assert(whatsappUnavailable(400, { code: 68008 }));
  assert(whatsappUnavailable(400, { code: '63118' }));
  assert(whatsappUnavailable(400, { code: '63008' }));
  assert(!whatsappUnavailable(403, { code: 60410 }), 'a Fraud Guard block must not be retried on SMS');
  assert(!whatsappUnavailable(400, { code: 60200, message: 'WhatsApp channel is not configured for this service' }));
  assert(!whatsappUnavailable(400, { code: 60200, message: 'Invalid parameter: To' }));
  assert(!whatsappUnavailable(429, { code: 60203, message: 'Max send attempts reached' }));
  assert(!whatsappUnavailable(400, null));
});

// ---- the channel fallback (founder, 15 Sep 2026: WhatsApp first on every attempt, SMS only on refusal)
const fake = (answers: Record<string, { status: number; jd: unknown }>) => {
  const calls: string[] = [];
  const send = (ch: 'whatsapp' | 'sms') => { calls.push(ch); const a = answers[ch]; return Promise.resolve({ r: { ok: a.status < 300, status: a.status }, jd: a.jd }); };
  return { calls, send };
};

Deno.test('fallback: WhatsApp delivers -> one send, channel whatsapp', async () => {
  const f = fake({ whatsapp: { status: 201, jd: { status: 'pending', channel: 'whatsapp', send_code_attempts: [{ channel: 'whatsapp' }] } }, sms: { status: 201, jd: {} } });
  const res = await sendWhatsAppFirst(f.send);
  assertEquals(f.calls, ['whatsapp']);
  assertEquals([res.ok, res.channel, res.refused], [true, 'whatsapp', null]);
});

Deno.test('fallback: template refusal 68008 -> SMS to the same number, channel sms, refusal recorded', async () => {
  const f = fake({ whatsapp: { status: 400, jd: { code: 68008, message: 'Verify WhatsApp channel not configured' } }, sms: { status: 201, jd: { status: 'pending', channel: 'sms' } } });
  const res = await sendWhatsAppFirst(f.send);
  assertEquals(f.calls, ['whatsapp', 'sms']);
  assertEquals([res.ok, res.channel, res.refused], [true, 'sms', 68008]);
});

Deno.test('fallback: Verify accepts WhatsApp but delivers by SMS (measured 15 Sep 2026) -> channel sms, no second send', async () => {
  const f = fake({ whatsapp: { status: 201, jd: { status: 'pending', channel: 'whatsapp', send_code_attempts: [{ channel: 'sms' }] } }, sms: { status: 201, jd: {} } });
  const res = await sendWhatsAppFirst(f.send);
  assertEquals(f.calls, ['whatsapp']);
  assertEquals([res.ok, res.channel, res.refused], [true, 'sms', null]);
});

Deno.test('fallback: any other refusal is a failure and never falls back', async () => {
  for (const jd of [{ code: 60410 }, { code: 60200 }, { code: 60203 }]) {
    const f = fake({ whatsapp: { status: 400, jd }, sms: { status: 201, jd: {} } });
    const res = await sendWhatsAppFirst(f.send);
    assertEquals(f.calls, ['whatsapp'], JSON.stringify(jd));
    assertEquals([res.ok, res.channel], [false, null]);
  }
  const both = fake({ whatsapp: { status: 400, jd: { code: 68008 } }, sms: { status: 400, jd: { code: 21211 } } });
  const r2 = await sendWhatsAppFirst(both.send);
  assertEquals([both.calls, r2.ok, r2.channel], [['whatsapp', 'sms'], false, null]);
});

Deno.test('fixtures: both reserved markers required; the code is deterministic and 6 digits', async () => {
  assert(isFixtureIdentity('qd-x-cust1@example.invalid', '+971500000042'));
  assert(!isFixtureIdentity('someone@gmail.com', '+971500000042'));
  assert(!isFixtureIdentity('qd-x-cust1@example.invalid', '+971501234567'));
  const a = await fixtureCode('k', 'QD-x@example.invalid', '+971500000042');
  assert(/^\d{6}$/.test(a));
  assertEquals(a, await fixtureCode('k', 'qd-x@example.invalid', '+971500000042'));
  assert(a !== await fixtureCode('other-key', 'qd-x@example.invalid', '+971500000042'));
});

Deno.test('state: an unverified phone is reported as no phone; asked covers opt or timestamp', () => {
  assertEquals(whatsappState(null), { opt: null, phone: null, verified: false, asked: false });
  assertEquals(whatsappState({ whatsapp_phone: '+971501234567', whatsapp_verified_at: null }), { opt: null, phone: null, verified: false, asked: false });
  assertEquals(whatsappState({ whatsapp_asked_at: NOW }), { opt: null, phone: null, verified: false, asked: true });
  assertEquals(whatsappState({ whatsapp_opt: 'other', whatsapp_phone: '+971559999999', whatsapp_verified_at: NOW }), { opt: 'other', phone: '+971559999999', verified: true, asked: true });
  assertEquals(whatsappState({ whatsapp_opt: 'bogus' }).opt, null);
});
