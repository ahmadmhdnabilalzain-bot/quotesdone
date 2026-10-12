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
    '/QuotesDone Backup/Customers/../_archive/a.pdf', '/QuotesDone Backup//Customers/a.pdf',
    '/QuotesDone Backup/Customers/./Ann (aaaaaaaa)/a.pdf', '/QuotesDone Backup/Customers/Ann/..', '/QuotesDone Backup/Customers/Ann/.',
    '/QuotesDone Backup/Customers/Ann/../../Company/Database Exports/x.json']) assertEquals(signupPurgeDeleteAllowed(p), false, p);
});

Deno.test('the demo purge deletes only a path whose name carries the demo marker', async () => {
  const { demoPurgeDeleteAllowed } = await import('./purge.ts');
  for (const p of ['/QuotesDone Backup/Customers/ZZ DEMO - shared handset A (ccef2d0d)',
    '/QuotesDone Backup/Customers/ZZ DEMO Customer 85929fc6 (5fc48b40)/Customer Details.pdf',
    '/QuotesDone Backup/Suppliers/Uncategorized/ZZ DEMO — section 8 probe supplier A (40466)',
    '/QuotesDone Backup/Customers/__selftest__ctrl A (ae8d1a34)', '/QuotesDone Backup/Customers/QD DEMO Customer (cbfd972e)',
    '/QuotesDone Backup/_sandbox/1c94fa6a', '/QuotesDone Backup/Customers/QA Test Customer (58371fbd)',
    '/QuotesDone Backup/Customers/ahmad test (70f15bc3)/x.pdf', '/QuotesDone Backup/Customers/DEMO — Sara Ahmed (657e47eb)', '/QuotesDone Backup/Customers/qa.portal.testquotesdone.com', '/QuotesDone Backup/_selftest/auth_probe_1.txt']) assertEquals(demoPurgeDeleteAllowed(p), true, p);
  for (const p of ['/QuotesDone Backup/Customers/Contest Trading (5)', '/QuotesDone Backup/Customers/ahmad alzain',
    '/QuotesDone Backup/Customers', '/QuotesDone Backup/_sandbox', '/QuotesDone Backup/_archive/ZZ DEMO x',
    '/QuotesDone Backup/Company/Database Exports/ZZ DEMO.json', '/QuotesDone Backup/Customers/ZZ DEMO x/../../Company',
    '/QuotesDone Backup//Customers/ZZ DEMO x', '/elsewhere/Customers/ZZ DEMO x', '/QuotesDone Backup/Suppliers/Uncategorized/ZZ Demolition LLC (77)',
    '/QuotesDone Backup/Customers/ZZDemolition (1a2b3c4d)/a.pdf'])
    assertEquals(demoPurgeDeleteAllowed(p), false, p);
});
