// The backup-retention allow-list refuses every document and every inventory, and allows only export files.
// The same cases are asserted against the SQL twin in the probe of
// scripts/sql/the_backups_are_kept_ninety_days_and_friday_copies_a_year.sql.
import { assert } from 'jsr:@std/assert@1';
import { dropboxExportAllowed, exportPathAllowed } from './backup_prune_allow.ts';

Deno.test('the table export files are allowed', () => {
  for (const p of ['2026-06-23/customers.json', '2026-09-20/leads/page_0000.json', '2026-09-20/kb_chunks/page_2615.json',
                   '2026-09-20/_manifest.json']) {
    assert(exportPathAllowed('backups', p), p + ' should be allowed');
  }
});

Deno.test('inventories, documents and anything outside the dated export shapes are refused', () => {
  const refused: [unknown, unknown][] = [
    ['backups', '2026-06-23/_storage_backups.json'],        // the final-review case: no hyphen in the name
    ['backups', '2026-06-23/_storage_supplier-docs.json'],
    ['backups', '2026-06-23/_storage_brand.json'],          // one of the 87 the old pattern let through
    ['backups', '2026-06-23/_anything.json'],
    ['backups', '2026-06-23/_storage/page_0000.json'],
    ['backups', '2026-06-23/9leads.json'],
    ['backups', '2026-06-23/../supplier-docs/licence.pdf'],
    ['backups', 'conversations/2026-09/x.pdf'],
    ['backups', 'accountant/year-end/2026/pack.pdf'],
    ['supplier-docs', '123/Trade licence - licence.pdf'],    // a supplier's trade licence
    ['supplier-docs', '2026-09-20/leads/page_0000.json'],   // right shape, wrong bucket
    ['signed-terms', '123/terms.pdf'],
    [null, null],
  ];
  for (const [b, p] of refused) assert(!exportPathAllowed(b, p), `${b}:${p} must be refused`);
});

Deno.test('a Dropbox row is allowed only as the TABLE EXPORTS rule files it', () => {
  const ok = { bucket: 'backups', path: '2026-09-20/leads/page_0000.json', doc_type: 'Database export',
               dedupe_key: 'EXPORT:2026-09-20/leads/page_0000.json',
               dropbox_path: '/QuotesDone Backup/Company/Database Exports/2026-09/2026-09-20/leads/page_0000.json' };
  assert(dropboxExportAllowed(ok));
  assert(!dropboxExportAllowed({ ...ok, doc_type: 'Trade licence' }));
  assert(!dropboxExportAllowed({ ...ok, dropbox_path: '/QuotesDone Backup/Suppliers/X (1)/Trade licence - licence.pdf' }));
  assert(!dropboxExportAllowed({ ...ok, dedupe_key: 'S:1:Trade licence:x.pdf' }));
  const inv = '2026-06-23/_storage_backups.json';
  assert(!dropboxExportAllowed({ bucket: 'backups', path: inv, doc_type: 'Database export', dedupe_key: 'EXPORT:' + inv,
                                 dropbox_path: '/QuotesDone Backup/Company/Database Exports/2026-06/' + inv }),
    'an inventory filed exactly like an export file must still be refused');
  assert(!dropboxExportAllowed({ bucket: 'supplier-docs', path: 'ZZ DEMO probe/licence.pdf', doc_type: 'Trade licence',
                                 dedupe_key: 'EXPORT:2025-01-02/zz_demo_probe/licence.pdf',
                                 dropbox_path: '/QuotesDone Backup/Suppliers/ZZ DEMO probe/Trade licence - licence.pdf' }));
});
