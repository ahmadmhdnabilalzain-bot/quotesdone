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

Deno.test('the demo purge deletes only a frozen, reviewed path (or inside one) and the probe roots', async () => {
  const { demoPurgeDeleteAllowed, DEMO_PURGE_PATHS } = await import('./purge.ts');
  for (const p of DEMO_PURGE_PATHS) {
    assertEquals(demoPurgeDeleteAllowed(p), true, p);
    assertEquals(demoPurgeDeleteAllowed(p + '/Inquiries/x.pdf'), true, p + '/...');
  }
  for (const p of ['/QuotesDone Backup/_sandbox/1c94fa6a', '/QuotesDone Backup/_selftest/auth_probe_1.txt'])
    assertEquals(demoPurgeDeleteAllowed(p), true, p);
  // must never delete: real-looking or merely test-sounding names, the real customers, prefixes, the roots, other archives
  for (const p of ['/QuotesDone Backup/Suppliers/interior-design/QA Interiors LLC (30001)', '/QuotesDone Backup/Suppliers/joinery-kitchens/Demo Kitchens (30002)',
    '/QuotesDone Backup/Suppliers/Other/Al Test Trading (30003)', '/QuotesDone Backup/Customers/Contest Trading (5)',
    '/QuotesDone Backup/Suppliers/Uncategorized/ZZ Demolition LLC (77)', '/QuotesDone Backup/Customers/Ann ZZ DEMO',
    '/QuotesDone Backup/Customers/ZZ DEMO Customer 1 (abcdef12)',          // a marker name alone is not on the list
    '/QuotesDone Backup/Customers/ahmad alzain', '/QuotesDone Backup/Customers/Umarah Nabi (ba61fa16)',
    '/QuotesDone Backup/_archive/superseded-tnc-2026-10-12/Customers/Umarah Nabi (ba61fa16)',
    // held until the founder answers (coordinator, 13 Oct 2026): real-looking names, never on the list
    '/QuotesDone Backup/Customers/Ahmad Nabil Al Zain', '/QuotesDone Backup/Customers/Ahmad Nabil Al Zain/Signed-Terms-Acceptance.pdf',
    '/QuotesDone Backup/Customers/TIWNKLE SHARMA', '/QuotesDone Backup/Customers/TIWNKLE SHARMA/Signed-Terms-Acceptance.pdf',
    '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/ahmad alzain (95e4345e)',
    '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/ahmad alzain (95e4345e)/Customer Details.pdf',
    '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/Ahmad Nabil Al Zain (dbb4e36f)',
    '/QuotesDone Backup/_archive/ownerless-2026-10-12/Customers/TIWNKLE SHARMA (ca038493)',
    '/QuotesDone Backup/_archive/ownerless-2026-10-12', '/QuotesDone Backup/_archive/demo-leftovers-2026-10-12',   // never a whole set
    '/QuotesDone Backup/Customers/ahmad test 3', '/QuotesDone Backup/Customers/ahmad test 2x',    // a prefix is not the folder
    '/QuotesDone Backup/Customers', '/QuotesDone Backup/_archive', '/QuotesDone Backup/_sandbox',
    '/QuotesDone Backup/Customers/ahmad test/../ahmad alzain/a.pdf', '/QuotesDone Backup//Customers/ahmad test',
    '/elsewhere/Customers/ahmad test'])
    assertEquals(demoPurgeDeleteAllowed(p), false, p);
});
