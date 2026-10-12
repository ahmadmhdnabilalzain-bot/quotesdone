// An unfinished sign-up's backups (founder ruling 1181, 12 Oct 2026; it_engineer). The sign-up is removed by
// fn_unfinished_signup_purge; its Dropbox copies are MOVED, never deleted, to
// /QuotesDone Backup/_archive/unfinished-signups/<YYYY-MM>/<the path it had>, so nothing reads it as a
// customer's or a company's folder again and nothing is lost.
export const ARCHIVE_ROOT = '/QuotesDone Backup/_archive/unfinished-signups';
export function archivePath(dropboxPath: string, when: Date): string {
  const rest = dropboxPath.replace(/^\/QuotesDone Backup\//, '');
  if (rest === dropboxPath || rest.startsWith('_archive/')) throw new Error('not a path of the backup tree: ' + dropboxPath.slice(0, 80));
  return `${ARCHIVE_ROOT}/${when.toISOString().slice(0, 7)}/${rest}`;
}
