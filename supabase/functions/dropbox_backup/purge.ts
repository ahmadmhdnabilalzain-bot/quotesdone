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

// THE DEMO PURGE (founder ruling 1199, 12 Oct 2026; it_engineer). fn_demo_purge lists Dropbox paths in the same queue;
// one is deleted ONLY if it is a path in the frozen, reviewed demo_purge_paths.json (or inside one), or inside the
// _sandbox/ or _selftest/ probe roots. No name pattern ever decides: "QA Interiors LLC" or "ZZ Demolition" is safe.
import FROZEN from './demo_purge_paths.json' with { type: 'json' };
const DEMO_ROOT = /^_(sandbox|selftest)\/[^/]+(\/.+)?$/;
export const DEMO_PURGE_PATHS: readonly string[] = FROZEN.paths;
export function demoPurgeDeleteAllowed(path: string, frozen: readonly string[] = DEMO_PURGE_PATHS): boolean {
  if (!path.startsWith(ROOT) || path.includes('//') || path.includes('\\')) return false;
  if (path.split('/').some((seg) => seg === '.' || seg === '..')) return false;
  if (DEMO_ROOT.test(path.slice(ROOT.length))) return true;
  return frozen.some((p) => path === p || path.startsWith(p + '/'));
}
