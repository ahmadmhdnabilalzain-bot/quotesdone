// THE SUPPLIER PORTAL ASKS `me` ONLY WHEN IT DOES NOT ALREADY KNOW THE ANSWER (11 Nov 2026, customer_support; supplier
// registration certification, free round 6, run 2 J1 desktop: "Create company" opened the registration form in 3,907 ms
// against 3,000; the step met create_company 1,810 ms, `me` 1,671 ms, `me` 1,581 ms).
//
// Read on production's edge log for that minute: the first `me` was the one SupplierPortal.onAuth warms at sign-in, still
// on its way when the supplier pressed Create company (#1928 opens "Register your company" at once on login_otp's
// has_company=false, so that `me` now runs into the next step; its answer, "no company", was already known). The second
// was Onboarding re-reading `me` after create_company answered: two calls in series on the step's critical path.
//   * whenToWarmMe: sign-in with has_company=false and no invitation being claimed warms the dashboard only. The
//     dashboard's own answer still corrects a wrong hint (Dashboard reads `me` once the dashboard names a supplier).
//   * supplierFromCreate: create_company answers with the supplier `me` would read (supplier_api/lib/me_row.ts); the
//     form opens on it. An answer without it (an older deployment, a read that failed) falls back to asking `me`.
// Pure, no imports: node --test src/lib/supplierRegistrationReads.test.mjs runs it as it is.

/** Sign-in warms `me` beside the dashboard unless the code answer said there is no company and no claim is pending. */
export function warmsMe(o: { hasCompany?: boolean; claimPending: boolean }): boolean {
  return !(o.hasCompany === false && !o.claimPending);
}

/** Dashboard reads `me` now, or waits: with the "no company yet" hint it waits for the dashboard to name a supplier. */
export function readsMeNow(o: { noCompanyYet: boolean; dashboardAnswered: boolean }): boolean {
  return !o.noCompanyYet || o.dashboardAnswered;
}

/** The supplier create_company answered with, or null when the portal must ask `me` (an answer without it). */
export function supplierFromCreate(j: unknown): Record<string, unknown> | null {
  const a = j as { ok?: unknown; id?: unknown; supplier?: unknown } | null;
  if (!a || a.ok !== true || !a.supplier || typeof a.supplier !== 'object') return null;
  const s = a.supplier as Record<string, unknown>;
  return a.id == null || String(s.id) === String(a.id) ? s : null;
}
