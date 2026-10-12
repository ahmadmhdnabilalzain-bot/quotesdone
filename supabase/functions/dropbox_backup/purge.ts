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

// THE DEMO PURGE (founder ruling 1199, 12 Oct 2026; it_engineer): fn_demo_purge lists, in the same queue, each Dropbox
// copy of a demo entity and each whole demo folder. A path is allowed only when the marker is IN THE PATH: an entity
// folder (or anything inside it) named ZZ DEMO / __selftest__ / QD DEMO, or anything under the _sandbox / _selftest
// probe roots. Never the root, a table export, _archive, or a folder without the marker.
const DEMO_ENTITY = /^(Customers|Suppliers\/[^/]+)\/(ZZ ?DEMO(?![a-z])|__selftest__|QD DEMO(?![a-z]))[^/]*(\/.+)?$/i;   // a word: never "ZZ Demolition"
const DEMO_ROOT = /^_(sandbox|selftest)\/[^/]+(\/.+)?$/;
export function demoPurgeDeleteAllowed(path: string): boolean {
  if (!path.startsWith(ROOT) || path.includes('//') || path.includes('\\')) return false;
  if (path.split('/').some((seg) => seg === '.' || seg === '..')) return false;
  const rest = path.slice(ROOT.length);
  return DEMO_ENTITY.test(rest) || DEMO_ROOT.test(rest);
}
