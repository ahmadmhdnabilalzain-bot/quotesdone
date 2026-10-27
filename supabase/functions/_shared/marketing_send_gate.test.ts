import { assertEquals } from 'jsr:@std/assert@1';
import {
  isMarketingType, isStop, marketingGate, pickSender, renderWaInvite, senderQualityOk, supplierInviteGate,
  WA_INVITE_APPROVED_OFFER, WA_INVITE_BUTTONS, WA_INVITE_TEMPLATE_EN, waInviteTrade,
} from './marketing_send_gate.ts';
import { ANY_LINK } from '../send_outbox/m365_lane.ts';

// 27 Oct 2026: nothing leaves unless BOTH switches are exactly 'true' and no brake is open; opt-out cancels first.
Deno.test('invite gate: every switch off, missing or mistyped holds; a brake holds; both on sends', () => {
  const on = { golive: 'true', inviteEnabled: 'true', brakeOpen: false };
  assertEquals(supplierInviteGate(on).action, 'send');
  for (const [k, v] of [['golive', undefined], ['golive', 'false'], ['golive', 'TRUE'], ['golive', ''], ['inviteEnabled', undefined],
    ['inviteEnabled', 'false'], ['inviteEnabled', 'yes'], ['inviteEnabled', null]] as const) {
    assertEquals(supplierInviteGate({ ...on, [k]: v }).action, 'hold', k + '=' + String(v));
  }
  assertEquals(supplierInviteGate({ ...on, brakeOpen: true }).action, 'hold');
  assertEquals(supplierInviteGate({ golive: 'false', inviteEnabled: 'false', brakeOpen: true, whatsappOpt: 'none' }).action, 'cancel');
  assertEquals(supplierInviteGate({ ...on, inviteEnabled: 'false' }).why.includes('invite_enabled'), true);
});
Deno.test('sender quality: only ONLINE + HIGH (or GREEN) sends', () => {
  assertEquals(senderQualityOk('HIGH', 'ONLINE'), true);
  assertEquals(senderQualityOk('green', 'online'), true);
  for (const [r, s] of [['MEDIUM', 'ONLINE'], ['LOW', 'ONLINE'], ['YELLOW', 'ONLINE'], ['RED', 'ONLINE'], [null, 'ONLINE'], ['UNKNOWN', 'ONLINE'],
    ['HIGH', 'OFFLINE'], ['HIGH', 'TWILIO_REVIEW'], ['HIGH', null]]) assertEquals(senderQualityOk(r, s), false, r + '/' + s);
});
Deno.test('pickSender finds our number in a Twilio senders page and reads its rating', () => {
  const page = { senders: [
    { sid: 'XE1', sender_id: 'whatsapp:+15550000000', status: 'ONLINE', properties: { quality_rating: 'HIGH' } },
    { sid: 'XE2', sender_id: 'whatsapp:+971500000099', status: 'ONLINE', properties: { quality_rating: 'MEDIUM', messaging_limit: '1K Customers/24hr' } },
  ] };
  assertEquals(pickSender(page, '971500000099'), { sid: 'XE2', status: 'ONLINE', rating: 'MEDIUM', limit: '1K Customers/24hr' });
  assertEquals(pickSender(page, '+971 50 000 0099')?.sid, 'XE2');
  assertEquals(pickSender(page, '971500000000'), null);
  assertEquals(pickSender(null, '971500000099'), null);
});
Deno.test('the WhatsApp invitation: no link, English, the STOP line, one mid-sentence variable, the approved offer', () => {
  const t = WA_INVITE_TEMPLATE_EN;
  assertEquals(ANY_LINK.test(t), false, 'a link (ruling 1301)');
  assertEquals(/[؀-ۿ]/.test(t), false, 'Arabic to a supplier');
  assertEquals(/\bAI\b/.test(t), false);
  assertEquals(t.match(/\{\{\d\}\}/g), ['{{1}}']);
  assertEquals(/^\{\{|\}\}$/.test(t.trim()), false);
  assertEquals(t.length <= 1024, true);
  assertEquals(t.endsWith('reply STOP and we won\'t message you again.'), true);
  // The promises the founder approved (ledger 1298), checked against the stored offer and the canon, not the email
  // body. #1648 removed the offer from the email for filter reasons only (WA_INVITE_APPROVED_OFFER says why).
  const canon = Deno.readTextFileSync(new URL('../../../knowledge/COMPANY_CANON.md', import.meta.url));
  for (const { promise, canon: fact } of WA_INVITE_APPROVED_OFFER) {
    assertEquals(t.toLowerCase().includes(promise.toLowerCase()), true, 'the template carries: ' + promise);
    if (fact) assertEquals(canon.includes(fact), true, 'COMPANY_CANON.md still states: ' + fact);
  }
  // nothing more: no price, percentage, discount, deadline or other commercial claim beyond the approved offer
  assertEquals(/\bAED\b|%|\bdiscount|\bguarantee|\bexclusive|\blimited\b|\bdeadline|\bexpires?\b|\buntil\b/i.test(t), false, 'an offer beyond the approved one');
  assertEquals(WA_INVITE_BUTTONS.map((b) => b.title), ['Set up my page', 'Stop']);
  for (const b of WA_INVITE_BUTTONS) assertEquals(b.title.length <= 20, true, 'Meta caps a quick-reply title at 20');
  assertEquals(isStop(WA_INVITE_BUTTONS[1].title), true, 'the Stop button must read as an opt-out in wa_inbound');
  assertEquals(isStop(WA_INVITE_BUTTONS[0].title), false);
});
Deno.test('the trade variable is one short lower-case line; empty reads "new"', () => {
  assertEquals(waInviteTrade('interior_fitout'), 'interior fitout');
  assertEquals(waInviteTrade('  HVAC\n Works '), 'hvac works');
  assertEquals(waInviteTrade(null), 'new');
  assertEquals(waInviteTrade('x'.repeat(200)).length, 60);
  assertEquals(renderWaInvite('painting').includes('onboarding painting suppliers'), true);
});

Deno.test('STOP: case, punctuation and whitespace', () => {
  for (const s of ['STOP', 'stop', 'Stop.', ' stop! ', 'StOp!!!', '"stop"', 'Unsubscribe', 'opt-out', 'STOP\n']) assertEquals(isStop(s), true, s);
});
Deno.test('STOP: Arabic forms, with and without hamza, diacritics or tatweel', () => {
  for (const s of ['إيقاف', 'ايقاف', 'إلغاء', 'الغاء', 'توقف', 'أوقف.', 'إلغاء الاشتراك', 'إيـقـاف', 'إِيقَاف']) assertEquals(isStop(s), true, s);
});
Deno.test('STOP: a sentence that mentions stop is not an opt-out', () => {
  for (const s of ['', null, 'please do not stop sending', 'bus stop near me', 'hello', 'stopper']) assertEquals(isStop(s as string), false, String(s));
});
Deno.test('gate: switch off or missing holds, opt-out cancels, on sends', () => {
  assertEquals(marketingGate(undefined, null), 'hold');
  assertEquals(marketingGate('', null), 'hold');
  assertEquals(marketingGate('false', 'same'), 'hold');
  assertEquals(marketingGate('TRUE ', null), 'hold');
  assertEquals(marketingGate('true', null), 'send');
  assertEquals(marketingGate('true', 'none'), 'cancel');
  assertEquals(marketingGate(undefined, 'none'), 'cancel');
});
Deno.test('every marketing type is gated; a transactional type is not', () => {
  assertEquals(isMarketingType('supplier_invite_wa'), true);
  assertEquals(isMarketingType('supplier_account_notice'), false);
  assertEquals(isMarketingType('supplier_invite'), false);
});
