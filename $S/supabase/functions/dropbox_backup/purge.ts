// The ONE Dropbox delete outside the export retention (founder ruling 1181, 12 Oct 2026; it_engineer): the copies of
// an UNFINISHED sign-up, "as if he didn't even try" (privacy policy 1.6: "deleted in full after 30 minutes").
// dropbox_backup deletes only a path that fn_unfinished_signup_purge listed in signup_purge_dropbox for a sign-up it
// removed (guarded there on the completion fields), and only inside the entity tree: never a table export, never
// _selftest, _sandbox or _archive, never anything outside /QuotesDone Backup/. Every other Dropbox rule stays
// "never delete".
const ROOT = '/QuotesDone Backup/';
export function signupPurgeDeleteAllowed(path: string): boolean {
  if (!path.startsWith(ROOT) || path.includes('//') || path.includes('\\')) return false;
  if (path.split('/').some((seg) => seg === '.' || seg === '..')) return false;      // no relative segment anywhere
  const rest = path.slice(ROOT.length);
  if (rest.startsWith('_') || rest.startsWith('Company/Database Exports/')) return false;
  return /^(Customers|Suppliers|Storage|Company\/Correspondence|Finance)\/.+\/[^/]+$/.test(rest);
}
