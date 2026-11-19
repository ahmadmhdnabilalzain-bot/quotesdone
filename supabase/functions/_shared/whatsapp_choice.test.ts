import { assert, assertEquals } from 'jsr:@std/assert@1';
import { askedPatch, choosePatch, parseChoiceOpt, sendWhatsAppFirst, verifiedPatch, whatsappState, whatsappUnavailable, voiceAfterSms } from './whatsapp_choice.ts';

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

Deno.test('state: an unverified phone is reported as no phone; asked covers opt or timestamp', () => {
  assertEquals(whatsappState(null), { opt: null, phone: null, verified: false, asked: false });
  assertEquals(whatsappState({ whatsapp_phone: '+971501234567', whatsapp_verified_at: null }), { opt: null, phone: null, verified: false, asked: false });
  assertEquals(whatsappState({ whatsapp_asked_at: NOW }), { opt: null, phone: null, verified: false, asked: true });
  assertEquals(whatsappState({ whatsapp_opt: 'other', whatsapp_phone: '+971559999999', whatsapp_verified_at: NOW }), { opt: 'other', phone: '+971559999999', verified: true, asked: true });
  assertEquals(whatsappState({ whatsapp_opt: 'bogus' }).opt, null);
});

// ---- SMS, then voice (customer_support, 6 Oct 2026)

const sent = (ok: boolean, jd: unknown) => ({ r: { ok, status: ok ? 201 : 400 }, jd, refused: null, ok, channel: ok ? 'sms' : null }) as never;
Deno.test('voice: SMS that cannot reach the number (landline 60205) -> one call, channel call', async () => {
  const calls: string[] = [];
  const res = await voiceAfterSms(sent(false, { code: 60205 }), (ch) => { calls.push(ch); return Promise.resolve({ r: { ok: true, status: 201 }, jd: { status: 'pending' } }); });
  assertEquals([calls, res.ok, res.channel], [['call'], true, 'call']);
});
Deno.test('voice: a delivered SMS, a fraud block or a rate limit is never retried by voice', async () => {
  for (const first of [sent(true, { status: 'pending' }), sent(false, { code: 60410 }), sent(false, { code: 60203 }), sent(false, { code: 60200 })]) {
    const calls: string[] = [];
    const res = await voiceAfterSms(first, (ch) => { calls.push(ch); return Promise.resolve({ r: { ok: true, status: 201 }, jd: {} }); });
    assertEquals(calls, []);
    assertEquals(res, first);
  }
});
Deno.test('voice: a refused call is a failure, not a false sent', async () => {
  const res = await voiceAfterSms(sent(false, { code: 21614 }), () => Promise.resolve({ r: { ok: false, status: 400 }, jd: { code: 60200 } }));
  assertEquals([res.ok, res.channel], [false, null]);
});

// it_engineer, 18 Oct 2026 (review of #1432): WhatsApp only where it is known to reach the person, SMS failover.
import { channelOfRow, failoverStep, FAILOVER_AFTER_S, nextChannel, sidOfRow } from './whatsapp_choice.ts';
Deno.test('WhatsApp goes only to a confirmed number or to the number the user just chose WhatsApp for', () => {
  const m = '+971501234567';
  assertEquals(nextChannel({ e164: m }), 'sms');                          // unconfirmed, nobody chose: SMS
  assertEquals(nextChannel({ e164: m, waConfirmed: true }), 'whatsapp');  // the account confirmed it
  assertEquals(nextChannel({ e164: m, asked: 'whatsapp' }), 'whatsapp');  // signed-in user chose it in sign-up
  assertEquals(nextChannel({ e164: m, asked: 'whatsapp', lastChannel: 'whatsapp' }), 'sms'); // asked again = not arrived
  assertEquals(nextChannel({ e164: m, waConfirmed: true, lastChannel: 'whatsapp' }), 'sms');
  assertEquals(nextChannel({ e164: m, waConfirmed: true, asked: 'sms' }), 'sms');
  assertEquals(nextChannel({ e164: m, asked: 'call' }), 'call');
  assertEquals(nextChannel({ e164: '+97142587734', asked: 'whatsapp' }), 'sms'); // a landline never gets WhatsApp
  assertEquals(nextChannel({ e164: '+447700900000', waConfirmed: true }), 'sms');
});
Deno.test('a WhatsApp code fails over to SMS when Twilio reports it undelivered or it is late', () => {
  assertEquals(failoverStep('DELIVERED', 60e3), 'none');
  assertEquals(failoverStep('read', 60e3), 'none');
  assertEquals(failoverStep('UNDELIVERED', 2e3), 'sms');
  assertEquals(failoverStep('failed', 2e3), 'sms');
  assertEquals(failoverStep('SENT', FAILOVER_AFTER_S * 1000 - 1), 'wait');
  assertEquals(failoverStep('SENT', FAILOVER_AFTER_S * 1000), 'sms');
  assertEquals(failoverStep(null, FAILOVER_AFTER_S * 1000 + 5), 'sms');
});
Deno.test('the ledger row carries the channel and the Verify SID, never a code', () => {
  assertEquals(channelOfRow('twilio:whatsapp:VEc60112ca453826c0f5df15847908a061'), 'whatsapp');
  assertEquals(sidOfRow('twilio:whatsapp:VEc60112ca453826c0f5df15847908a061'), 'VEc60112ca453826c0f5df15847908a061');
  assertEquals(channelOfRow('twilio:sms'), 'sms');
  assertEquals(sidOfRow('twilio:sms'), null);
  assertEquals(channelOfRow('twilio'), null);
  assertEquals(channelOfRow('twilio:sms:123456'), null);   // a 6-digit code is never a valid row
});

Deno.test('waDeliveredCode: only a code delivered on WhatsApp confirms the WhatsApp number (known-bad: sms, call, failover, garbage)', async () => {
  const { waDeliveredCode } = await import('./whatsapp_choice.ts');
  assert(waDeliveredCode('qd:whatsapp:SM' + 'a'.repeat(32)));
  assert(waDeliveredCode('twilio:whatsapp:VE' + 'a'.repeat(32)));
  for (const c of ['twilio:sms', 'twilio:call', 'twilio:sms:SM' + 'a'.repeat(32), '', null, undefined, '123456']) assert(!waDeliveredCode(c as string), String(c));
});

// Reviews of the walk of 12 Nov 2026, D2 then R1: a new mobile proven by SMS left whatsapp_phone on the old number while the answer
// said "same"; moving it unproven to the new number would send sign-in codes by WhatsApp to a number nobody said is on WhatsApp. Known-bad
// controls: on origin/main the source assertion fails; on 8fb0da128 the cleared-answer assertion fails.
Deno.test('a new mobile proven by SMS re-asks a "same" WhatsApp answer; a WhatsApp code proves it; other answers stay his', async () => {
  const { waAfterMobileVerified } = await import('./whatsapp_choice.ts');
  const now = '2026-11-12T22:00:00.000Z';
  // R1: proven by SMS, "same" spoke of the OLD number: the answer is cleared and asked again, never moved unproven to the new one
  const cleared = waAfterMobileVerified('same', '+971559999999', false, now);
  assertEquals(cleared, { whatsapp_opt: null, whatsapp_phone: null, whatsapp_verified_at: null, whatsapp_asked_at: null });
  assertEquals(whatsappState(cleared as never), { opt: null, phone: null, verified: false, asked: false }, 'the portal must ask again (asked: false)');
  assertEquals(waAfterMobileVerified('other', '+971559999999', false, now), null, 'another WhatsApp number he proved is his choice');
  assertEquals(waAfterMobileVerified('none', '+971559999999', false, now), null);
  assertEquals(waAfterMobileVerified(null, '+971559999999', false, now), null, 'no answer yet: he is still asked');
  assertEquals(waAfterMobileVerified('none', '+971559999999', true, now), verifiedPatch('+971559999999', now), 'a code on WhatsApp proves it, as before');
  const kyc = await Deno.readTextFile(new URL('../kyc/index.ts', import.meta.url));
  const verify = kyc.slice(kyc.indexOf("if (action === 'verify_sms')"), kyc.indexOf("return J({ ok: true });", kyc.indexOf("if (action === 'verify_sms')")));
  assert(/waAfterMobileVerified\(waNow\?\.whatsapp_opt, phone, waDeliveredCode\(lastCodeRow\?\.code\)/.test(verify), 'verify_sms does not move a "same" WhatsApp number with the new mobile');
  assert(/if \(waPatch\) await writeWa\(waPatch\)/.test(verify));
});

// it_engineer, 19 Nov 2026 (ledger 1252): a code already typed back is never sent again by SMS.
import { failoverSid } from './whatsapp_choice.ts';
Deno.test('failoverSid: only an unused WhatsApp code is failed over (known-bad: used, sms, call, garbage, nothing)', () => {
  const OWN = 'qd:whatsapp:SM' + 'b'.repeat(32), VER = 'twilio:whatsapp:VE' + 'c'.repeat(32);
  assertEquals(failoverSid({ code: OWN, used_at: null }), 'SM' + 'b'.repeat(32));
  assertEquals(failoverSid({ code: VER }), 'VE' + 'c'.repeat(32));
  assertEquals(failoverSid({ code: OWN, used_at: '2026-11-17T08:38:08Z' }), null);   // typed back 20 s after the send
  assertEquals(failoverSid({ code: VER, used_at: '2026-11-12T19:53:56Z' }), null);
  assertEquals(failoverSid({ code: 'twilio:sms:VE' + 'c'.repeat(32) }), null);         // an SMS is not failed over again
  assertEquals(failoverSid({ code: 'twilio:call' }), null);
  assertEquals(failoverSid({ code: 'twilio' }), null);
  assertEquals(failoverSid({ code: 'garbage' }), null);
  assertEquals(failoverSid(null), null);
  assertEquals(failoverSid(undefined), null);
});
