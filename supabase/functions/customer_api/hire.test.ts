// What Hire does given what is already recorded (lib/hire.ts; customer-journey audit 10 Nov 2026).
//   deno test -A --no-lock --node-modules-dir=none supabase/functions/customer_api/hire.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { hireStep } from './lib/hire.ts';

Deno.test('nobody hired yet: award', () => {
  assertEquals(hireStep({ status: 'revealed', hired_supplier_id: null }, 7), { kind: 'award', from: 'unhired' });
});
Deno.test('the follow-up recorded this supplier but the request is still revealed: the press completes it', () => {
  assertEquals(hireStep({ status: 'revealed', hired_supplier_id: 7 }, 7), { kind: 'award', from: 'recorded' });
});
Deno.test('completed with this supplier: nothing to do; another supplier recorded: refused', () => {
  assertEquals(hireStep({ status: 'completed', hired_supplier_id: 7 }, 7), { kind: 'already_completed' });
  assertEquals(hireStep({ status: 'revealed', hired_supplier_id: 7 }, 8), { kind: 'already_hired' });
  assertEquals(hireStep({ status: 'completed', hired_supplier_id: 7 }, 8), { kind: 'already_hired' });
});
Deno.test('complete_inquiry decides with hireStep and completes a recorded hire, guarded on its status', async () => {
  const src = await Deno.readTextFile(new URL('./actions/inquiry_lifecycle.ts', import.meta.url));
  const body = src.slice(src.indexOf("if (action === 'complete_inquiry')"), src.indexOf("if (action === 'edit_inquiry')"));
  assert(/hireStep\(inq, q\.supplier_id\)/.test(body), 'complete_inquiry asks hireStep');
  assert(/\.neq\('status', 'completed'\)/.test(body) && /\.eq\('hired_supplier_id', q\.supplier_id\)/.test(body), 'a recorded hire is completed only once');
});
