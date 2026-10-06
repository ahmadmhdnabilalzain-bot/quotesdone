import { assertEquals } from 'jsr:@std/assert@1';
import { twilioVerdict } from './verdict.ts';

Deno.test('a Twilio 404 is missing, never "404" (6 Oct 2026: six rows read "404")', () => {
  assertEquals(twilioVerdict(404, { code: 20404, message: 'not found', status: 404 }), { status: 'missing', reason: null, http: 404 });
});

Deno.test('any other non-2xx is no verdict, and carries its code', () => {
  assertEquals(twilioVerdict(500, { status: 500 }), { status: 'error:http_500', reason: null, http: 500 });
});

Deno.test('the error body status is never read as a verdict, on any answer', () => {
  assertEquals(twilioVerdict(200, { status: 404 }).status, 'unknown');
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assertEquals(/twilioVerdict\(r\.status, j\)/.test(src), true);
  assertEquals(/j\?\.status\s*\|\|/.test(src), false, 'the watcher reads the error body status again');
});

Deno.test('a 2xx answer gives the WhatsApp verdict', () => {
  assertEquals(twilioVerdict(200, { whatsapp: { status: 'approved' } }), { status: 'approved', reason: null, http: 200 });
  assertEquals(twilioVerdict(200, { whatsapp: { status: 'rejected', rejection_reason: 'format' } }), { status: 'rejected', reason: 'format', http: 200 });
});
