import { assertEquals } from 'jsr:@std/assert@1';
import { resendWithRetry } from './resend_send.ts';

const mail = { from: 'a@example.invalid', to: 'b@quotesdone.com', subject: 's', html: 'h' };
const seq = (codes: number[]) => { let i = 0; const calls: number[] = []; return { calls, f: async () => { const c = codes[i++]; calls.push(c); return new Response('{}', { status: c, headers: c === 429 ? { 'retry-after': '2' } : {} }); } }; };
const waits: number[] = []; const sleep = async (ms: number) => { waits.push(ms); };

Deno.test('a busy second is retried once and the code is delivered', async () => {
  const s = seq([429, 200]);
  assertEquals(await resendWithRetry('k', mail, s.f, sleep), true);
  assertEquals(s.calls, [429, 200]);
  assertEquals(waits.at(-1), 2000);
});
Deno.test('a second refusal is reported as not sent', async () => {
  const s = seq([429, 429]);
  assertEquals(await resendWithRetry('k', mail, s.f, sleep), false);
  assertEquals(s.calls.length, 2);
});
Deno.test('any other refusal is not retried', async () => {
  const s = seq([422]);
  assertEquals(await resendWithRetry('k', mail, s.f, sleep), false);
  assertEquals(s.calls.length, 1);
});
Deno.test('a network failure is not sent', async () => {
  assertEquals(await resendWithRetry('k', mail, () => Promise.reject(new Error('down')), sleep), false);
});

// A reserved fixture address never reaches Resend (22 Sep 2026): the harness's sign-in and confirm
// codes to @example.invalid hard-bounced six times against our sending domain.
Deno.test('a reserved test address is answered as sent and no request leaves', async () => {
  let calls = 0;
  const f = async () => { calls++; return new Response('{}', { status: 200 }); };
  for (const to of ['qd-stub@example.invalid', 'ZZ.Demo@Sub.Example.COM', 'x@foo.test']) {
    assertEquals(await resendWithRetry('k', { ...mail, to }, f, sleep), true);
  }
  assertEquals(calls, 0);
});
Deno.test('a real address is handed to Resend, with its reply-to', async () => {
  const bodies: string[] = [];
  const f = async (_u: string, init: RequestInit) => { bodies.push(String(init.body)); return new Response('{}', { status: 200 }); };
  assertEquals(await resendWithRetry('k', { ...mail, reply_to: 'info@quotesdone.com' }, f, sleep), true);
  assertEquals(bodies.length, 1);
  assertEquals(JSON.parse(bodies[0]).reply_to, 'info@quotesdone.com');
});
