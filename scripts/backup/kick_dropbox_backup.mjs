// The Dropbox backup's second scheduler, outside Supabase (sales_engineer, 14 Sep 2026).
// Run by .github/workflows/dropbox-backup-second-scheduler.yml. It asks the database to kick
// dropbox_backup (public.fn_backup_kick, which enqueues and uploads through pg_net), so a document
// still reaches Dropbox if resilience_ping's own clock (Vercel Cron) stops. It carries no Dropbox or
// function credential: the management token runs one SQL statement and the database does the rest.
import { sql } from '../lib/db.mjs';

const [row] = await sql("select public.fn_backup_kick('github_actions', 'enqueue') as kick, "
  + "(select count(*) from public.doc_backups where status in ('pending','error') and attempts < 5 and entity <> 'zz_demo') as queued");
console.log(JSON.stringify(row));
const k = row?.kick || {};
if (!k.kicked && !String(k.reason || '').startsWith('debounced')) {
  console.error('::error::the database could not kick dropbox_backup: ' + (k.reason || 'no answer'));
  process.exit(1);
}
