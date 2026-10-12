// deno test supabase/functions/dropbox_backup/purge.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { signupPurgeDeleteAllowed } from './purge.ts';

Deno.test('an unfinished sign-up\'s copy in the entity tree may be deleted', () => {
  for (const p of ['/QuotesDone Backup/Customers/Ann (aaaaaaaa)/Customer Details.pdf',
    '/QuotesDone Backup/Suppliers/uncategorized/Co (12)/Trade licence - a.pdf',
    '/QuotesDone Backup/Storage/supplier-docs/licenses/12/a.pdf',
    '/QuotesDone Backup/Company/Correspondence/2026-10/x.pdf']) assertEquals(signupPurgeDeleteAllowed(p), true, p);
});

Deno.test('a table export, a probe, a sandbox, an archive, a folder or anything outside the tree is never deleted', () => {
  for (const p of ['/QuotesDone Backup/Company/Database Exports/2026-10/2026-10-01/leads/page_0001.json',
    '/QuotesDone Backup/_selftest/x.txt', '/QuotesDone Backup/_sandbox/t/Customers/a.pdf', '/QuotesDone Backup/_archive/x/a.pdf',
    '/QuotesDone Backup/Customers', '/QuotesDone Backup/Customers/Ann (aaaaaaaa)', '/elsewhere/a.pdf',
    '/QuotesDone Backup/Customers/../_archive/a.pdf', '/QuotesDone Backup//Customers/a.pdf']) assertEquals(signupPurgeDeleteAllowed(p), false, p);
});
