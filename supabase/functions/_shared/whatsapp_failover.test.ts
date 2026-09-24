// deno test supabase/functions/_shared/whatsapp_failover.test.ts
import { assertEquals, assert } from 'jsr:@std/assert@1';
import { queueSmsTwin, routeFor, smsTextFor, waHealthFrom, type RpcFn } from './whatsapp_failover.ts';

const REAL = '+971501234567';

Deno.test('WhatsApp healthy -> WhatsApp', () => {
  assertEquals(routeFor(waHealthFrom(null), REAL), 'whatsapp');
});

Deno.test('WhatsApp down (open integration finding) -> SMS', () => {
  const h = waHealthFrom({ started_at: '2026-09-24T09:45:29Z' });
  assertEquals(h.healthy, false);
  assert(h.reason!.includes('twilio_whatsapp_sender'));
  assertEquals(routeFor(h, REAL), 'sms');
});

Deno.test('WhatsApp recovers during the day -> back to WhatsApp', () => {
  const day = [{ started_at: '2026-09-24T09:45:29Z' }, null]; // open at 09:45, closed by the watch later
  assertEquals(day.map((f) => routeFor(waHealthFrom(f), REAL)), ['sms', 'whatsapp']);
});

Deno.test('a demo / fixture number is never sent, on either channel', () => {
  assertEquals(routeFor(waHealthFrom(null), '+971500000042'), 'suppress');
  assertEquals(routeFor(waHealthFrom({}), '+971500000042'), 'suppress');
});

Deno.test('the SMS carries the same message and its link, in English for an English row', () => {
  const t = smsTextFor({ subject: 'New quote on request #12', body: 'New quote on request #12\nA supplier quoted AED 4,000.' }, 'https://quotesdone.com/me');
  assertEquals(t, 'QuotesDone: New quote on request #12 A supplier quoted AED 4,000. https://quotesdone.com/me');
  const long = smsTextFor({ subject: 's', body: 'x'.repeat(2000) }, 'https://quotesdone.com/portal');
  assert(long.length <= 600 && long.endsWith(' https://quotesdone.com/portal'));
});

// A fake of fn_wa_sms_twin's contract: one twin per notice (unique index notifications_one_sms_twin).
function fakeDb() {
  const twins = new Map<number, string>();
  const rpc: RpcFn = (_fn, a) => {
    const id = Number(a.p_notification_id);
    if (!twins.has(id)) twins.set(id, String(a.p_body));
    return Promise.resolve({ data: { ok: true, outcome: 'sms_twin' }, error: null });
  };
  return { twins, rpc };
}

Deno.test('a single failure -> exactly one SMS twin, however often it is reported', async () => {
  const db = fakeDb();
  // the send is rejected in the loop, then wa_status reports it failed and the late scan sees it again
  await queueSmsTwin(db.rpc, 7, 'QuotesDone: hello', 'Twilio rejected the WhatsApp send');
  await queueSmsTwin(db.rpc, 7, 'QuotesDone: hello', 'WhatsApp reported the message failed (Twilio 63005)');
  assertEquals(db.twins.size, 1);
});

Deno.test('a database error is reported, never counted as queued', async () => {
  const rpc: RpcFn = () => Promise.resolve({ data: null, error: { message: 'boom' } });
  assertEquals((await queueSmsTwin(rpc, 1, 'x', 'y')).ok, false);
});
