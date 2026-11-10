// supplier_address — THE ADDRESS A SUPPLIER IS WRITTEN AT (customer_support, 10 Nov 2026; supplier follow-up of #1909 item 4).
// leads.claimed_by is the address the company signs in with (proven by a code); leads.email is the listing's address,
// scraped or typed by whoever invited it. A notice to a registered supplier goes to the first, the listing only when
// nobody has claimed it. MEASURED on origin/main: the loss notice (job_awarded_other) and the new-request notice
// (new_inquiry) in customer_api/lib/matching.ts wrote leads.email. The database twin is public.fn_supplier_address
// (scripts/sql/a_supplier_is_written_at_the_address_it_signs_in_with.sql); both answer trimmed and lower-cased.
// prevented by: scripts/checks/a_supplier_is_written_at_the_address_it_signs_in_with.test.mjs
export function supplierAddress(l: { claimed_by?: string | null; email?: string | null } | null | undefined): string | null {
  const a = (String(l?.claimed_by ?? '').trim() || String(l?.email ?? '').trim()).toLowerCase();
  return /^[^@\s]+@[^@\s]+$/.test(a) ? a : null;
}
