import { assertEquals } from 'jsr:@std/assert@1';
import { deliveryOutcome } from './delivery_status.ts';

// The four words must stay inside notifications_provider_status_known, or every update is refused.
const ALLOWED = ['accepted', 'scheduled', 'queued', 'sending', 'sent', 'delivered', 'undelivered', 'failed', 'read'];

Deno.test('each delivery event maps to a status the column accepts', () => {
  for (const t of ['email.delivery_delayed', 'email.delivered', 'email.bounced', 'email.complained']) {
    const o = deliveryOutcome(t, '');
    assertEquals(!!o && ALLOWED.includes(o.status), true, t);
  }
});
Deno.test('a bounce and a complaint are final and carry the provider detail', () => {
  assertEquals(deliveryOutcome('email.bounced', 'Permanent'), { status: 'undelivered', code: 'bounce:permanent', onlyIf: null });
  assertEquals(deliveryOutcome('email.complained', ''), { status: 'delivered', code: 'complained', onlyIf: null });
});
Deno.test('a late delay or delivered never moves a final status backwards', () => {
  assertEquals(deliveryOutcome('email.delivery_delayed', '')?.onlyIf, 'provider_status.is.null');
  assertEquals(deliveryOutcome('email.delivered', '')?.onlyIf, 'provider_status.is.null,provider_status.eq.sending');
});
Deno.test('events that are not outcomes write nothing', () => {
  for (const t of ['email.sent', 'email.opened', 'email.clicked', '']) assertEquals(deliveryOutcome(t, ''), null);
});
