// WHAT WAS READ OFF THE LICENCE IS SHOWN BACK (10 Nov 2026, customer_support; supplier registration certification, founder
// ruling 1620: the registration must visibly "read their trade licence").
//
// process_docs writes what CODE reads off a text licence (number, authority, legal name, expiry) to the row, but answered the
// browser only with the expiry: out.license = { expiry, source, keyword, read_by, licence_name }. The registration form fills
// its read-only "Trade licence no." and "Licensing authority" fields from out.license.license_number / .authority, which only the
// MODEL branch set, and the model is not asked when code read everything. So a clean licence, read whole, showed the supplier two
// empty fields under "we read the number, authority, expiry and TRN automatically". The answer now carries what the ROW holds
// after this call, so the screen shows exactly what was recorded, whichever reader read it (a model's number never displaces
// code's, as on the row). A licence number set aside as another company's is removed afterwards, as before.
// Prevented by: licence_shown_back.test.ts.

export type LicenceRow = { trade_license_no?: unknown; license_authority?: unknown; licence_legal_name?: unknown; license_expiry?: unknown; emirate?: unknown };
const s = (v: unknown): string | null => (v === null || v === undefined || String(v).trim() === '' ? null : String(v).trim());

/** out.license with the row's recorded fields over it; null when this call read no licence at all. */
export function licenceShownBack(current: Record<string, unknown> | undefined, row: LicenceRow, licenceInCall: boolean): Record<string, unknown> | undefined {
  if (!licenceInCall) return current;
  const recorded = {
    license_number: s(row.trade_license_no), authority: s(row.license_authority), legal_name: s(row.licence_legal_name),
    expiry: s(row.license_expiry), emirate: s(row.emirate),
  };
  if (!current && Object.values(recorded).every((v) => v === null)) return current;
  const out: Record<string, unknown> = { ...(current || {}) };
  for (const [k, v] of Object.entries(recorded)) if (v !== null) out[k] = v;
  return out;
}
