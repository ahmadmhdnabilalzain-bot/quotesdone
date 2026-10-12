// deno test supabase/functions/dropbox_backup/archive.test.ts
import { assertEquals, assertThrows } from 'jsr:@std/assert@1';
import { archivePath } from './archive.ts';

Deno.test('an unfinished sign-up keeps its path under _archive/unfinished-signups/<month>/', () => {
  assertEquals(archivePath('/QuotesDone Backup/Customers/Ann (aaaaaaaa)/Customer Details.pdf', new Date('2026-10-12T08:00:00Z')),
    '/QuotesDone Backup/_archive/unfinished-signups/2026-10/Customers/Ann (aaaaaaaa)/Customer Details.pdf');
});
Deno.test('nothing outside the tree, and nothing already archived, is moved', () => {
  assertThrows(() => archivePath('/elsewhere/a.pdf', new Date()));
  assertThrows(() => archivePath('/QuotesDone Backup/_archive/x/a.pdf', new Date()));
});
