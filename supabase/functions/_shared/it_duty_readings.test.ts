// duty:expiry:tls must report the certificate in service, never an older one (19 Oct 2026: crt.sh lagged a
// Vercel renewal and the duty said 8-9 Nov while the served certificate ran to 9 Jan 2027).
import { assertEquals } from 'jsr:@std/assert@1';
import { tlsExpiry } from './it_duty_readings.ts';

const NOW = Date.parse('2026-10-19T00:00:00Z');
const OLD = { not_before: '2026-08-10T00:00:00', not_after: '2026-11-08T00:00:00' };
const NEW = { not_before: '2026-10-11T00:00:00', not_after: '2027-01-09T12:57:32' };
const FUTURE = { not_before: '2026-12-01T00:00:00', not_after: '2027-03-01T00:00:00' };

Deno.test('the served certificate wins over a lagging crt.sh', () => {
  assertEquals(tlsExpiry('2027-01-09T12:57:32.000Z', [OLD], NOW)?.expires_on, '2027-01-09');
});
Deno.test('crt.sh fallback: the newest valid not_after, never an older one, never a not-yet-valid one', () => {
  assertEquals(tlsExpiry(null, [NEW, OLD, FUTURE], NOW)?.expires_on, '2027-01-09');
  assertEquals(tlsExpiry(null, [OLD, NEW], NOW)?.source, 'crt.sh');
});
Deno.test('nothing readable is null, so the caller reports unavailable', () => {
  assertEquals(tlsExpiry(null, '<html>502</html>', NOW), null);
  assertEquals(tlsExpiry(null, [{ not_before: '2026-01-01', not_after: '2026-02-01' }], NOW), null);
});
