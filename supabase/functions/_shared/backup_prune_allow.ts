// The backup-retention allow-list, as the edge functions check it (it_engineer, 15 Sep 2026).
//
// The SAME rule as public.fn_backup_prune_path_allowed and public.fn_backup_prune_dropbox_allowed in
// scripts/sql/the_backups_are_kept_ninety_days_and_friday_copies_a_year.sql. The database picks what may
// be deleted; backup op 'prune' and dropbox_backup op 'prune' check every path again here before touching
// it, so a database bug alone cannot delete a document.
//
// The founder, 15 Sep 2026: "that doesnt mean removing the verified suppliers and registered customers
// later yea? ... of course that data should never get lost no matter what". So this is an ALLOW-list: only
// the table export's own files in the 'backups' bucket, never a stored document.
//
// Final review of #672 (HIGH): a table name used to be [a-z0-9_]+, which let backup v1's inventory of the
// backups bucket itself (<day>/_storage_backups.json) through. Measured 15 Sep 2026: 0 of those exist, but
// 87 other inventories did pass (<day>/_storage_brand.json, _storage_reports.json, _storage_site.json).
// A table name now starts with a letter, and no path segment may start with '_' except _manifest.json.
const MANIFEST = /^\d{4}-\d{2}-\d{2}\/_manifest\.json$/;
const PAGE = /^\d{4}-\d{2}-\d{2}\/[a-z][a-z0-9_]*\/page_\d{4}\.json$/;   // backup v1 (paged) and v2
const FLAT = /^\d{4}-\d{2}-\d{2}\/[a-z][a-z0-9_]*\.json$/;               // backup v1 (one file per table)

export function exportPathAllowed(bucket: unknown, path: unknown): boolean {
  if (bucket !== 'backups' || typeof path !== 'string') return false;
  if (!MANIFEST.test(path) && path.includes('/_')) return false;
  return MANIFEST.test(path) || PAGE.test(path) || FLAT.test(path);
}

export type ExportRow = { bucket?: unknown; path?: unknown; dedupe_key?: unknown; doc_type?: unknown; dropbox_path?: unknown };

// A doc_backups row exactly as the TABLE EXPORTS rule of fn_enqueue_doc_backups files it.
export function dropboxExportAllowed(r: ExportRow): boolean {
  if (!exportPathAllowed(r.bucket, r.path)) return false;
  const p = r.path as string;
  return r.doc_type === 'Database export' && r.dedupe_key === 'EXPORT:' + p
    && r.dropbox_path === '/QuotesDone Backup/Company/Database Exports/' + p.slice(0, 7) + '/' + p;
}
