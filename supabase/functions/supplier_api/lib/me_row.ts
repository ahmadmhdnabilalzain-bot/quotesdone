// supplier_api — THE SUPPLIER AS `me` ANSWERS HIM, in one place (11 Nov 2026, customer_support; supplier registration
// certification, free round 6, run 2 J1 desktop: "Create company" opened the registration form in 3,907 ms against 3,000).
//
// Two reasons it is a function and not a line inside the `me` handler:
//   * create_company answers with it (`supplier`), so the portal opens the registration form on create_company's own answer.
//     The form used to wait for create_company (1,810 ms in the browser) and THEN for a `me` (1,581 ms) to learn the row it
//     had just written: two calls in series on the step's critical path.
//   * its reads are issued together. `me` read the row, then app_secrets terms_version, then supplier_terms_version (and
//     terms_version again when that was empty), then supplier_terms_carries_from: up to five PostgREST round trips one
//     after another, none of the secrets depending on the row. Now one wave, with each secret read once.
// The answer is unchanged: the row's columns, terms_current (app_secrets terms_version) and terms_stands (the same
// acceptanceStands supplierAcceptanceStands applies). A read that fails reads as "no company" exactly as before.
// Prevented by: supplier_api/me_row.test.ts (one wave, the same answer) and create_company.test.ts (the answer carries it).
import { acceptanceStands, currentSupplierTermsVersion, supplierTermsCarriedFrom } from '../../_shared/supplier_terms.ts';

// source (12 Nov 2026, browser walk M23): read to answer `listed` (began as a listing we hold, or registered itself); the portal says
// "We already hold your company listing" only to a listed one, from `me` or the dashboard, whichever answers first. Never sent raw.
// licence_legal_name, trading_name (12 Nov 2026, ruling 1672): the form shows the company as its licence names it, never typed, and
// the optional trading name beside it; company_name is '' until the licence names the company (create_company.ts).
// licence_read_state (12 Nov 2026, final audit R2): the registration form reads `me` again after a licence answer that left before
// the model's reading, and shows the fields once the state is no longer 'ours_failed' (src/.../licenceReceived.ts awaitLateLicenceRead).
export const ME_COLUMNS = 'id,company_name,claimed_by,emirate,sector,business_role,products,services,description,certifications,company_type,company_size,founded_year,service_emirates,claimed,verified,approval_status,ai_review_notes,registration_submitted_at,accepted_terms_at,accepted_terms_version,contact_name,signatory_name,phone,trade_license_no,license_authority,license_expiry,licence_read_state,license_city,name_corrected_from,owner_email_verified,doc_extracted_at,trn,license_doc_path,egr_doc_path,egr_doc_name,egr_number,company_profile_doc_path,catalog_doc_paths,registration_status,registration_fee_due,registration_expires_at,app_rating,app_reviews,rating,reviews,licence_gate_reason,exception_due_at,source,licence_legal_name,trading_name';

// deno-lint-ignore no-explicit-any
type Db = any;
type Sec = (key: string) => Promise<string | null>;

/** The account's company as `me` serves it, or null when the account has none (or the row could not be read). */
export async function supplierOf(admin: Db, email: string, sec: Sec): Promise<Record<string, unknown> | null> {
  const seen = new Map<string, Promise<string | null>>();
  const once: Sec = (k) => { let p = seen.get(k); if (!p) { p = sec(k); seen.set(k, p); } return p; };
  const [{ data }, termsCurrent, current, carried] = await Promise.all([
    admin.from('leads').select(ME_COLUMNS).eq('claimed_by', email).maybeSingle(),
    once('terms_version'),
    currentSupplierTermsVersion(once),
    supplierTermsCarriedFrom(once),
  ]);
  if (!data) return null;
  // leads.source is read, never sent ('apify_2026-06', 'web_scrape' are ours, not his): the browser gets `listed` only (review, 12 Nov 2026).
  const { source, ...row } = data as typeof data & { source?: string | null };
  return { ...row, listed: source == null ? null : source !== 'self_registered', terms_current: termsCurrent, terms_stands: acceptanceStands(data.accepted_terms_version, current, carried) };
}
