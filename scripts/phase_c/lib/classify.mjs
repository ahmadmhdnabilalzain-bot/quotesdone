// Phase C classification vocabulary and the deterministic rules that assign it.
//
// The vocabulary is the master spec's, §3.6.  The rules below are the only place a
// component's verdict is decided, so a classification is reproducible from the measured
// inventory rather than typed into a spreadsheet by hand.
//
// The distinction that cost Phase B its 64-function figure is preserved here explicitly:
// "reachable from outside" (verify_jwt=false) is NOT the same fact as "is a product entry
// surface" (a webhook, an OAuth callback, a public page).  A function that is merely
// unauthenticated and uncalled is NO_CALLER_UNCLASSIFIED, not "externally entered".

export const CLASSES = [
  'CANONICAL_KEEP',
  'CANONICAL_BETTER_KEEP',
  'WIRE_TO_CANONICAL',
  'DUPLICATE_PATH',
  'CONFLICTING_PATH',
  'NO_CALLER_UNCLASSIFIED',
  'INACTIVE_HISTORICAL',
  'REPAIR_BEFORE_REACTIVATION',
  'INTENTIONALLY_RETIRED',
  'PHASE_D_CORRECTNESS_GAP',
];

/** Slugs whose name alone is not proof of an external product surface. */
const EXTERNAL_SURFACE = /(webhook|hook$|stripe|twilio|whatsapp|wa_|inbound|oauth|callback|sitemap|robots|rss|feed|public_|_public|share|unsubscribe|track|pixel|ics$|health|ping)/i;

/**
 * Entry classification for an edge function.
 *   internal_caller       — something in repo, database or cron invokes it
 *   external_product_entry— no internal caller, but the slug is a webhook/oauth/public surface
 *                           AND it is reachable without a Supabase JWT
 *   unauthenticated_only  — reachable without a JWT but no caller and no product surface
 *   none                  — no caller, JWT-gated: nothing can reach it today
 */
export function edgeEntry(e) {
  if (e.callers > 0) return 'internal_caller';
  if (e.verify_jwt_false && EXTERNAL_SURFACE.test(e.slug)) return 'external_product_entry';
  if (e.verify_jwt_false) return 'unauthenticated_only';
  return 'none';
}

export function classifyEdge(e) {
  const entry = edgeEntry(e);
  if (entry === 'internal_caller') return e.mutates ? 'WIRE_TO_CANONICAL' : 'CANONICAL_KEEP';
  if (entry === 'external_product_entry') return 'WIRE_TO_CANONICAL';
  return 'NO_CALLER_UNCLASSIFIED';
}

export function classifyCron(c) {
  const runs = Number(c.runs || 0);
  if (c.active) return 'WIRE_TO_CANONICAL';
  // Inactive is not dead.  A job that has executed and was switched off is history, not
  // rubble; a job that was switched off having never run has never been proven at all.
  return runs > 0 ? 'INACTIVE_HISTORICAL' : 'REPAIR_BEFORE_REACTIVATION';
}

export function classifyTrigger(t) {
  return t.tgenabled === 'O' ? 'CANONICAL_KEEP' : 'INACTIVE_HISTORICAL';
}

export function classifyRoutine(f) {
  if (f.called_by_trigger) return 'CANONICAL_KEEP';
  // A routine reached only through PostgREST still has a caller: os_api alone dispatches
  // ~60 of them by `.rpc(...)`.  Leaving that form out of the caller test is what would
  // have reported several hundred connected routines as orphans.
  const reachable = f.named_by_cron
    || Number(f.named_by_other_functions) > 0
    || f.named_by_edge_or_frontend;
  if (!reachable) return 'NO_CALLER_UNCLASSIFIED';
  return f.writes_sql || f.provolatile === 'v' ? 'WIRE_TO_CANONICAL' : 'CANONICAL_KEEP';
}

export function classifyRuntimeWorkflow(w) {
  if (Number(w.runs) > 0) return 'CANONICAL_BETTER_KEEP';
  return w.active ? 'WIRE_TO_CANONICAL' : 'REPAIR_BEFORE_REACTIVATION';
}

export function classifyFrontend(r) {
  return r.mutates ? 'WIRE_TO_CANONICAL' : 'CANONICAL_KEEP';
}

/** Does this component change persistent business state? */
export const mutatesEdge = e => !!e.mutates;
export const mutatesRoutine = f => f.provolatile === 'v' && f.writes_sql;
export const mutatesCron = () => true;         // a scheduled job exists to do something
export const mutatesTrigger = t => t.tgenabled === 'O';
