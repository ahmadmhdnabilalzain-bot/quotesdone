import { assertEquals } from 'jsr:@std/assert@1';
import { replyViolations, guardSupportReply } from './support_reply_guard.ts';

Deno.test('a reasoning block is never sent to a customer (run a8ad5ed7)', () => {
  assertEquals(replyViolations('<reasoning>Customer said Thursday. Ask budget.</reasoning>تمام، البدء يوم الخميس.'), ['prompt']);
  assertEquals(replyViolations('<reasoning>Customer says bring materials. Keep it short.'), ['prompt']);
  assertEquals(guardSupportReply('<thinking>plan</thinking>Hello', 'en').text, '');
  assertEquals(replyViolations('Reasoning about tiles: porcelain is denser.'), []);
});
