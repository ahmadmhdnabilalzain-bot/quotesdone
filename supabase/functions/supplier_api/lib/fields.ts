// supplier_api — the field lists, limits and small value helpers the actions share.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).

// 15 Sep 2026 (sales_engineer): trade_license_no, license_expiry and license_doc_path are NOT here. They
// are written only by the upload paths, from the stored file and what license_extract read off it; from
// this list a supplier could type their own expiry or point at a path that is not their licence.
// bank_name, bank_account_name, bank_iban and iban_doc_path left this list on 21 Sep 2026: the columns are
// being dropped/purged (scripts/sql/the_founder_removed_bank_details_from_the_estate.sql). Money moves both
// directions through Stripe, so the estate never holds a supplier's bank details — founder instruction 527.
// A file over the 25 MB ceiling (the supplier-docs bucket's file_size_limit) was told its FORMAT was wrong. 3 of 29 real UAE
// profiles measured on 13 Oct 2026 are larger (30, 38 and 85 MB): the supplier is now told the size, and how to fix it.
export const TOO_LARGE = (what: string) => `That ${what} is larger than 25 MB. Please upload a smaller copy - most PDF tools can export a compressed or "smallest file size" version.`;
// egr_doc_path left this list on 10 Nov 2026 (it_engineer, security checklist audit, M1): save_profile wrote it
// verbatim, so a supplier could point it at any object in supplier-docs, another supplier's licence included, and
// supplier_portal would sign that file back as "their" establishment card. The path is written only by the portal's
// upload (supplier_portal DOC_KINDS.egr, under certs/<supplier id>/), as license_doc_path is. Nothing in src/ sends it
// here. Prevented by supplier_api/profile_cols.test.ts.
// trading_name (ruling 1672, 12 Nov 2026): the optional shop or brand name when it differs from the licensed name; company_name is
// never in this list: it is the trade licence's (fn_sales_engineer_verifies_supplier names the company from it).
export const PROFILE_COLS = ['contact_name','signatory_name','emirates_id','phone','products','services','description','certifications','founded_year','company_type','company_size','trn','egr_doc_name','egr_number','trading_name'];
const YEAR_MS = 365 * 864e5;
export const CONCLUDED = ['completed','closed','cancelled'];
// EVIDENCE FIX 19 Jul 2026 -----------------------------------------------------------------
// Terms acceptance here recorded WHEN (accepted_terms_at) and WHICH VERSION
// (accepted_terms_version) but not FROM WHERE. The leads.accepted_terms_ip column already
// existed and auth_api / kyc already populated it - supplier_api, the main registration
// surface, was the one path that did not.
//
// Why it matters: the non-response fine (3%) drives an automated collections -> legal
// escalation path. If a supplier disputes the fine, the platform must evidence that THIS
// party accepted THAT version of the terms at THAT time from THAT address. Timestamp plus
// version without an originating IP is materially weaker evidence.
//
// Same derivation as auth_api line 9 so the two paths produce comparable records.
export const clip = (v: unknown, n: number) => (v == null || String(v).trim() === '') ? null : String(v).slice(0, n);

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const numOrNull = (v: unknown) => { const n = Number(v); return isFinite(n) && n !== 0 ? n : (isFinite(n) && String(v).trim() !== '' ? n : null); };

function b64ToBytes(b64:string){ const bin=atob(String(b64).replace(/^data:[^;]+;base64,/,'')); const a=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)a[i]=bin.charCodeAt(i); return a; }
