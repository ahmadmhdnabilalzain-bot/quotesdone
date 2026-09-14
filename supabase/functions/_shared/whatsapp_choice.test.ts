import { assert, assertEquals } from 'jsr:@std/assert@1';
import { askedPatch, choosePatch, parseChoiceOpt, verifiedPatch, whatsappState, whatsappUnavailable } from './whatsapp_choice.ts';

const NOW = '2026-09-14T10:00:00.000Z';

Deno.test('only same and none are choosable; other comes from a verified code', () => {
  assertEquals(parseChoiceOpt('same'), 'same');
  assertEquals(parseChoiceOpt('none'), 'none');
  assertEquals(parseChoiceOpt('other'), null);
  assertEquals(parseChoiceOpt(''), null);
  assertEquals(parseChoiceOpt(undefined), null);
});

Deno.test('same writes the verified mobile, verified now, opted in', () => {
  assertEquals(choosePatch('same', '+971501234567', NOW), { whatsapp_opt: 'same', whatsapp_phone: '+971501234567', whatsapp_verified_at: NOW, wa_optin: true, whatsapp_asked_at: NOW });
});

Deno.test('same without a verified mobile produces no patch', () => {
  assertEquals(choosePatch('same', null, NOW), null);
  assertEquals(choosePatch('same', '', NOW), null);
});

Deno.test('none clears the number and opts out', () => {
  assertEquals(choosePatch('none', '+971501234567', NOW), { whatsapp_opt: 'none', whatsapp_phone: null, whatsapp_verified_at: null, wa_optin: false, whatsapp_asked_at: NOW });
});

Deno.test('every patch that sets a phone also sets verified_at', () => {
  for (const p of [choosePatch('same', '+971501234567', NOW)!, verifiedPatch('+971559999999', NOW)]) {
    assert(p.whatsapp_phone && p.whatsapp_verified_at === NOW);
  }
  assertEquals(verifiedPatch('+971559999999', NOW).whatsapp_opt, 'other');
  assertEquals(askedPatch(NOW), { whatsapp_asked_at: NOW });
});

Deno.test('unavailable: named codes, and a 4xx that mentions WhatsApp', () => {
  assert(whatsappUnavailable(400, { code: 68008 }));
  assert(whatsappUnavailable(400, { code: '63008' }));
  assert(whatsappUnavailable(403, { code: 60410 }));
  assert(whatsappUnavailable(400, { code: 60200, message: 'WhatsApp channel is not configured for this service' }));
  assert(!whatsappUnavailable(400, { code: 60200, message: 'Invalid parameter: To' }));
  assert(!whatsappUnavailable(500, { message: 'whatsapp upstream error' }));
  assert(!whatsappUnavailable(429, { code: 60203, message: 'Max send attempts reached' }));
  assert(!whatsappUnavailable(400, null));
});

Deno.test('state: an unverified phone is reported as no phone; asked covers opt or timestamp', () => {
  assertEquals(whatsappState(null), { opt: null, phone: null, verified: false, asked: false });
  assertEquals(whatsappState({ whatsapp_phone: '+971501234567', whatsapp_verified_at: null }), { opt: null, phone: null, verified: false, asked: false });
  assertEquals(whatsappState({ whatsapp_asked_at: NOW }), { opt: null, phone: null, verified: false, asked: true });
  assertEquals(whatsappState({ whatsapp_opt: 'other', whatsapp_phone: '+971559999999', whatsapp_verified_at: NOW }), { opt: 'other', phone: '+971559999999', verified: true, asked: true });
  assertEquals(whatsappState({ whatsapp_opt: 'bogus' }).opt, null);
});
