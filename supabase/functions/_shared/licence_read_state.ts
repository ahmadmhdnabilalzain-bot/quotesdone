// WHOSE FAILURE AN UNREAD LICENCE IS (10 Nov 2026, customer_support; supplier-journey follow-up, item 6 of #1901's report).
//
// MEASURED BEFORE THIS FILE. supplier_api process_docs answered `license_error: 'extract_failed'` to the browser when OUR
// reader failed (license_extract timed out, the gateway answered 5xx or was out of credit, the reply did not parse) and
// stored nothing about it. The row then looked exactly like a licence the supplier had made unreadable: the licence number
// (or name, expiry, authority) empty, so fn_sales_engineer_verifies_supplier held it licence_number_unread and
// fn_sales_engineer_decides_held_registrations asked the supplier three times (day 0, 3, 7) for "a clearer copy of the whole
// page" and closed the registration at day 14, for a file that may have been perfectly legible. The OpenRouter account
// was out of credit on 10 Nov (checkpoint-10-nov), so every scanned licence was on that path.
//
// THE RULE, one function every licence reader calls (supplier_api process_docs, supplier_portal save_documents):
//   * 'read'            our reader finished. Whatever is still blank is what the document itself did not show, and the gate
//                       may ask the supplier for a clearer copy;
//   * 'file_unreadable' the model was asked and answered that the document cannot be read (licence_extract's
//                       normaliseLicence: no name, or 'low' confidence). The file is the problem; asking is right;
//   * 'ours_failed'     a field is still blank and our model was NOT able to answer: it failed, it is switched off
//                       (app_secrets.document_expiry_ai), or the stored bytes could not be fetched to send it. The supplier is
//                       never asked for this: the gate holds the registration as 'licence_being_read', the sweep reads the
//                       licence again (supplier_api docs_reread, fn_supplier_licence_reread_claim), and a licence we still
//                       cannot read after three days goes to the ceo seat, never to the 14-day close.
// Prevented by: _shared/licence_read_state.test.ts.
import { licenceNeedsModel } from './document_expiry.ts';

/** What happened when the model was (or was not) asked to read the licence. */
export type LicenceModelOutcome =
  | 'not_needed'   // code read every field the gate stands on, so the model was not asked
  | 'not_sent'     // a field was blank but there was nothing to send (no bytes, no images)
  | 'off'          // a field was blank and the document model is switched off
  | 'failed'       // the model was asked and did not answer usably (5xx, timeout, out of credit, unparseable)
  | 'unreadable'   // the model answered: this document cannot be read
  | 'read';        // the model answered with a reading

export type LicenceReadState = 'read' | 'ours_failed' | 'file_unreadable';

/** The four fields the verification gate stands on, as they will be written to the row. */
export type LicenceRowFields = { licence_legal_name?: unknown; trade_license_no?: unknown; license_expiry?: unknown; license_authority?: unknown };

const filled = (v: unknown) => v != null && String(v).trim() !== '';

/** True when one of the four fields the gate stands on is still blank after every reader ran. */
export function licenceLeftUnread(f: LicenceRowFields): boolean {
  return licenceNeedsModel({
    legal_name_en: filled(f.licence_legal_name) ? String(f.licence_legal_name) : null,
    licence_no: filled(f.trade_license_no) ? String(f.trade_license_no) : null,
    expiry_date: filled(f.license_expiry) ? String(f.license_expiry) : null,
    authority: filled(f.license_authority) ? String(f.license_authority) : null,
  });
}

/** Whose failure a licence read is. See the header: only 'ours_failed' keeps the supplier from being asked. */
export function licenceReadState(leftUnread: boolean, model: LicenceModelOutcome): LicenceReadState {
  if (!leftUnread) return 'read';
  if (model === 'read') return 'read';
  if (model === 'unreadable') return 'file_unreadable';
  return 'ours_failed';
}

/** The outcome of one license_extract answer (supplier_api's extract(), supplier_portal's direct call). */
// deno-lint-ignore no-explicit-any
export function modelOutcomeOf(jd: any): LicenceModelOutcome {
  if (jd?.ok && jd.doc && !jd.doc.unreadable) return 'read';
  if (jd?.ok && jd.doc?.unreadable) return 'unreadable';
  return 'failed';
}

/** What the supplier reads while our reader has not finished. English only (suppliers are always written in English). */
export const LICENCE_BEING_READ_NOTE =
  'Our document reader has not finished reading your trade licence yet. That is on our side, not yours: we read it again automatically and tell you if anything is needed. Nothing was guessed.';
