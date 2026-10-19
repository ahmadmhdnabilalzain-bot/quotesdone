import { assertEquals } from 'jsr:@std/assert@1';
import { isMarketingType, isStop, marketingGate } from './marketing_send_gate.ts';

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
