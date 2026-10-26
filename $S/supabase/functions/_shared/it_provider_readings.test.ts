import { assertEquals } from 'jsr:@std/assert@1';
import { firewallReading, STATUS_PAGES, statusReading } from './it_provider_readings.ts';

Deno.test('a status page with an indicator is measured', () => {
  const r = statusReading('twilio', 200, { status: { indicator: 'major', description: 'Partial outage' } });
  assertEquals(r, { provider: 'twilio', basis: 'measured', indicator: 'major', description: 'Partial outage' });
});

Deno.test('an unreadable status page is unavailable, never healthy', () => {
  assertEquals(statusReading('stripe', 404, null).basis, 'unavailable');
  assertEquals(statusReading('stripe', 200, { page: {} }).basis, 'unavailable');
});

Deno.test('the six providers the audit named are all read', () => {
  assertEquals(Object.keys(STATUS_PAGES).sort(), ['dropbox', 'resend', 'stripe', 'supabase', 'twilio', 'vercel']);
});

Deno.test('firewall: off and under attack are measured; an odd shape is unavailable', () => {
  const r = firewallReading({ status: 200, json: { firewallEnabled: false } }, { status: 200, json: { anomalies: [{}] } });
  assertEquals(r, { config: { basis: 'measured', enabled: false }, attack: { basis: 'measured', under_attack: true } });
  const u = firewallReading({ status: 403, json: {} }, { status: 404, json: null });
  assertEquals([u.config.basis, u.attack.basis], ['unavailable', 'unavailable']);
  assertEquals(firewallReading({ status: 200, json: { firewallEnabled: true } }, { status: 200, json: { anomalies: [] } }).attack,
    { basis: 'measured', under_attack: false });
});
