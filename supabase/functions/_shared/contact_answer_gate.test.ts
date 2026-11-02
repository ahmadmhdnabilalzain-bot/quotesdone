// deno test --no-check --node-modules-dir=none supabase/functions/_shared/contact_answer_gate.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { answerHold } from './contact_answer_gate.ts';

const mx = async () => ({ kind: 'mx' as const, hosts: ['mx.example.net'] });
const open = async () => true;
const counts = () => { const n: Record<string, number> = {}; return async (k: string, limit: number) => (n[k] = (n[k] ?? 0) + 1) <= limit; };

Deno.test('a real address with an MX under its limits is answered', async () => {
  assertEquals(await answerHold('buyer@acme-fitout.ae', '1.2.3.4', open, mx), null);
});
Deno.test('KNOWN-BAD: a typo domain, a bad shape, no MX, an unreadable MX are held', async () => {
  assertEquals(await answerHold('x@gmial.com', '1.2.3.4', open, mx), 'address_check');
  assertEquals(await answerHold('not-an-address', '1.2.3.4', open, mx), 'address_check');
  assertEquals(await answerHold('x@nodomain-qd.ae', '1.2.3.4', open, async () => ({ kind: 'nxdomain', hosts: [] })), 'no_mx');
  assertEquals(await answerHold('x@nullmx-qd.ae', '1.2.3.4', open, async () => ({ kind: 'no_records', hosts: [] })), 'no_mx');
  assertEquals(await answerHold('x@slow-qd.ae', '1.2.3.4', open, async () => ({ kind: 'error', hosts: [] })), 'mx_unreadable');
});
Deno.test('KNOWN-BAD: a fourth answer to one IP and a third to one address are held; a limiter that cannot count holds', async () => {
  const a = counts();
  for (let i = 0; i < 3; i++) assertEquals(await answerHold(`p${i}@acme-fitout.ae`, '9.9.9.9', a, mx), null);
  assertEquals(await answerHold('p9@acme-fitout.ae', '9.9.9.9', a, mx), 'ip_daily_limit');
  const b = counts();
  assertEquals(await answerHold('same@acme-fitout.ae', '1.1.1.1', b, mx), null);
  assertEquals(await answerHold('same@acme-fitout.ae', '2.2.2.2', b, mx), null);
  assertEquals(await answerHold('same@acme-fitout.ae', '3.3.3.3', b, mx), 'address_daily_limit');
  assertEquals(await answerHold('y@acme-fitout.ae', '4.4.4.4', async () => false, mx), 'ip_daily_limit');
});
