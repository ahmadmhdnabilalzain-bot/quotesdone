// Run: deno test --no-lock supabase/functions/wa_inbound/wa_row.test.ts
import { assertEquals } from 'jsr:@std/assert';
import { waRow } from './wa_row.ts';

Deno.test('a sent reply records its arrival and its reply time; an unsent one records no reply time', () => {
  const at = '2026-09-30T10:00:00.000Z', now = new Date('2026-09-30T10:02:00.000Z');
  const sent = waRow(at, { inbound: 'ZZ DEMO hi', reply: 'hello', sent: true }, now);
  assertEquals(sent.created_at, at);
  assertEquals(sent.replied_at, '2026-09-30T10:02:00.000Z');
  assertEquals(waRow(at, { inbound: 'ZZ DEMO hi', reply: '', sent: false }, now).replied_at, null);
  assertEquals(waRow(at, { inbound: 'ZZ DEMO hi', reply: 'x' }, now).replied_at, null);
});
